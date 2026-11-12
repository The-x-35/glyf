import type { FastifyInstance } from "fastify";
import { isAddress, getAddress } from "viem";
import { TTLCache } from "../lib/cache.js";
import { bonfidaSns, ensName, resolveEns, viemEns, type EnsLookup, type SnsLookup } from "../lib/names.js";

/**
 * Names for the keyboard's send chip: GET /names/resolve?name=arpit.eth turns
 * a name into the addresses it points at, GET /names/reverse?address=0x…
 * names an address someone pasted.
 *
 * `.sol` is SNS, anything else with a dot is ENS (subnames and offchain
 * names included). Lookups, not model runs: they never touch the plan meter,
 * and the gate in front of every route already wants a session. Answers are
 * kept five minutes, so a chip shown on every pause costs one lookup.
 */

export interface NamesDeps {
  ens?: EnsLookup;
  /** Built from SOLANA_RPC_URL unless a test passes one; null = no SNS. */
  sns?: SnsLookup | null;
}

const SOL_NAME = /^(?:[a-z0-9-]+\.)+sol$/;
const BASE58_ADDRESS = /^[1-9A-HJ-NP-Za-km-z]{32,44}$/;

export function namesRoutes(app: FastifyInstance, deps: NamesDeps = {}): void {
  let ens = deps.ens;
  let sns = deps.sns;
  const ensNow = () => (ens ??= viemEns());
  const snsNow = () => {
    if (sns === undefined) {
      const url = (process.env.SOLANA_RPC_URL ?? "").trim();
      sns = url ? bonfidaSns(url) : null;
    }
    return sns;
  };
  const cache = new TTLCache(5 * 60 * 1000, 2000);

  app.get("/names/resolve", async (req, reply) => {
    const raw = ((req.query as { name?: string }).name ?? "").trim().toLowerCase().replace(/^@/, "");
    const sol = SOL_NAME.test(raw);
    const name = sol ? raw : ensName(raw);
    if (!name) return reply.code(400).send({ ok: false, error: "name?" });
    const hit = cache.get(`n:${name}`);
    if (hit) return reply.code(hit === "null" ? 404 : 200).send(hit === "null"
      ? { ok: false, found: false, name } : { ok: true, found: true, ...JSON.parse(hit) });
    try {
      let answer;
      if (sol) {
        const lookup = snsNow();
        if (!lookup) return reply.code(503).send({ ok: false, error: ".sol names aren't set up on this server" });
        const owner = await lookup.resolve(name);
        answer = owner ? { name, addresses: { solana: owner } } : null;
      } else {
        answer = await resolveEns(ensNow(), name);
      }
      cache.set(`n:${name}`, answer ? JSON.stringify(answer) : "null");
      // Names and addresses stay out of the log.
      req.log.info({ kind: sol ? "sns" : "ens", found: Boolean(answer) }, "names_resolve");
      reply.header("cache-control", "private, max-age=300");
      if (!answer) return reply.code(404).send({ ok: false, found: false, name });
      return { ok: true, found: true, ...answer };
    } catch (err) {
      req.log.warn({ err: err instanceof Error ? err.message : String(err) }, "names_resolve_failed");
      return reply.code(502).send({ ok: false, error: "Couldn't look that name up. Try again in a moment" });
    }
  });

  app.get("/names/reverse", async (req, reply) => {
    const raw = ((req.query as { address?: string }).address ?? "").trim();
    const evm = isAddress(raw, { strict: false });
    if (!evm && !BASE58_ADDRESS.test(raw)) return reply.code(400).send({ ok: false, error: "address?" });
    const address = evm ? getAddress(raw) : raw;
    const hit = cache.get(`a:${address}`);
    if (hit !== undefined) {
      return hit === "" ? reply.code(404).send({ ok: false, found: false, address })
        : { ok: true, found: true, address, name: hit };
    }
    try {
      let name: string | null;
      if (evm) {
        name = await ensNow().name(address as `0x${string}`);
      } else {
        const lookup = snsNow();
        if (!lookup) return reply.code(503).send({ ok: false, error: ".sol names aren't set up on this server" });
        name = await lookup.primary(address);
      }
      cache.set(`a:${address}`, name ?? "");
      req.log.info({ kind: evm ? "ens" : "sns", found: Boolean(name) }, "names_reverse");
      reply.header("cache-control", "private, max-age=300");
      if (!name) return reply.code(404).send({ ok: false, found: false, address });
      return { ok: true, found: true, address, name };
    } catch (err) {
      req.log.warn({ err: err instanceof Error ? err.message : String(err) }, "names_reverse_failed");
      return reply.code(502).send({ ok: false, error: "Couldn't look that address up. Try again in a moment" });
    }
  });
}

import type { FastifyInstance } from "fastify";
import { isAddress, getAddress } from "viem";
import { TTLCache } from "../lib/cache.js";
import {
  bonfidaSns, ensName, NEAR_IMPLICIT_ACCOUNT, NEAR_NAME, nearRpc, resolveEns, viemEns,
  type EnsLookup, type NearLookup, type SnsLookup,
} from "../lib/names.js";

/**
 * Names for the keyboard's send chip: GET /names/resolve?name=arpit.eth turns
 * a name into the addresses it points at, GET /names/reverse?address=0x…
 * names an address someone pasted.
 *
 * `.sol` is SNS, `.near` (and a NEAR implicit account, 64 hex characters)
 * is NEAR, anything else with a dot is ENS (subnames and offchain names
 * included). A NEAR account id is its own address, so NEAR is only asked
 * whether it exists: `{chain: "near", address, exists}` beside the usual
 * shape. An implicit account exists by construction (its id is its key)
 * and can be paid before it is funded; `funded` says whether it has been. Lookups, not model runs: they never touch the plan meter,
 * and the gate in front of every route already wants a session. Answers are
 * kept five minutes, so a chip shown on every pause costs one lookup.
 */

export interface NamesDeps {
  ens?: EnsLookup;
  /** Built from SOLANA_RPC_URL unless a test passes one; null = no SNS. */
  sns?: SnsLookup | null;
  /** NEAR RPC view_account (NEAR_RPC_URL or rpc.mainnet.near.org). */
  near?: NearLookup;
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
  const near = deps.near ?? nearRpc();
  const cache = new TTLCache(5 * 60 * 1000, 2000);

  /** A .near name or an implicit account: whether NEAR has it. */
  async function nearAnswer(account: string) {
    const implicit = NEAR_IMPLICIT_ACCOUNT.test(account);
    let funded: boolean | undefined;
    try {
      funded = await near.exists(account);
    } catch (err) {
      // A name can't be vouched for without NEAR; an implicit account can.
      if (!implicit) throw err;
    }
    const exists = implicit || funded === true;
    return { name: account, chain: "near" as const, address: account, exists,
      ...(implicit ? { implicit: true, ...(funded !== undefined ? { funded } : {}) } : {}),
      ...(exists ? { addresses: { near: account } } : {}) };
  }

  app.get("/names/resolve", async (req, reply) => {
    const raw = ((req.query as { name?: string }).name ?? "").trim().toLowerCase().replace(/^@/, "");
    if (NEAR_NAME.test(raw) || NEAR_IMPLICIT_ACCOUNT.test(raw)) {
      const hit = cache.get(`near:${raw}`);
      try {
        const answer = hit ? JSON.parse(hit) as Awaited<ReturnType<typeof nearAnswer>> : await nearAnswer(raw);
        if (!hit) cache.set(`near:${raw}`, JSON.stringify(answer));
        if (!hit) req.log.info({ kind: "near", found: answer.exists }, "names_resolve");
        reply.header("cache-control", "private, max-age=300");
        if (!answer.exists) return reply.code(404).send({ ok: false, found: false, ...answer });
        return { ok: true, found: true, ...answer };
      } catch (err) {
        req.log.warn({ err: err instanceof Error ? err.message : String(err) }, "names_resolve_failed");
        return reply.code(502).send({ ok: false, error: "Couldn't look that name up. Try again in a moment" });
      }
    }
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

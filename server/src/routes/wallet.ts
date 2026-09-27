import type { FastifyInstance } from "fastify";
import { z } from "zod";

/**
 * POST /wallet/rpc — Solana JSON-RPC for the app's wallet, with the RPC
 * provider's key added here so it never ships inside the app (SPEC §1.6).
 *
 * The wallet itself lives on the phone: it builds each transaction, Phantom
 * signs it, and swaps and private sends go straight to Jupiter and
 * MagicBlock. This route only carries the few calls that need a node: a
 * blockhash to build with, balances, whether an address is a token, sending
 * a signed transaction and asking how it went. The server never holds or
 * sees a key that can move money.
 */

const ALLOWED = new Set([
  "getLatestBlockhash",
  "getBalance",
  "getTokenAccountsByOwner",
  "getAccountInfo",
  "sendTransaction",
  "getSignatureStatuses",
]);

const RpcSchema = z.object({
  method: z.string().min(1).max(40),
  params: z.array(z.unknown()).max(4).default([]),
});

export interface WalletDeps {
  /** SOLANA_RPC_URL (with the provider's key) unless a test passes one. */
  rpcUrl?: string;
  fetchImpl?: typeof fetch;
}

export function walletRoutes(app: FastifyInstance, deps: WalletDeps = {}): void {
  const fetchImpl = deps.fetchImpl ?? fetch;

  app.post("/wallet/rpc", async (req, reply) => {
    const url = deps.rpcUrl ?? process.env.SOLANA_RPC_URL;
    if (!url) return reply.code(503).send({ ok: false, error: "The wallet isn't set up on this server" });
    const parsed = RpcSchema.safeParse(req.body);
    if (!parsed.success || !ALLOWED.has(parsed.data.method)) {
      return reply.code(400).send({ ok: false, error: "Bad request" });
    }
    const { method, params } = parsed.data;
    try {
      const res = await fetchImpl(url, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
        signal: AbortSignal.timeout(15_000),
      });
      const json = await res.json() as { result?: unknown; error?: { code?: number; message?: string } };
      if (json.error) {
        // The node's own words ("insufficient funds for rent"…), which the app
        // turns into something a person can act on.
        return reply.code(400).send({ ok: false, error: json.error.message ?? "RPC error", code: json.error.code });
      }
      // Addresses, amounts and transactions stay out of the log.
      req.log.info({ method }, "wallet_rpc");
      return { ok: true, result: json.result ?? null };
    } catch (err) {
      req.log.warn({ method, err: err instanceof Error ? err.message : String(err) }, "wallet_rpc_failed");
      return reply.code(502).send({ ok: false, error: "Solana didn't answer. Try again in a moment" });
    }
  });
}

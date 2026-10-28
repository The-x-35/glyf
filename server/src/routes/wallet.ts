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

/** Arpit's wallet, the fee vault until GLYF_FEE_WALLET names another
 *  (2026-10-28: "use this for now to take fees"). Public, not a secret. */
export const DEFAULT_FEE_WALLET = "4j8FqYuNix7RfFgKmiRZnCE1acNnTarqm1SbZYdQZmFA";

export interface WalletDeps {
  /** SOLANA_RPC_URL (with the provider's key) unless a test passes one. */
  rpcUrl?: string;
  fetchImpl?: typeof fetch;
}

export function walletRoutes(app: FastifyInstance, deps: WalletDeps = {}): void {
  const fetchImpl = deps.fetchImpl ?? fetch;

  /** GET /wallet/fees — Glyf's fee on private payments (MagicBlock): the
   *  wallet that receives it (GLYF_FEE_WALLET, falling back to the USDC
   *  plans' GLYF_TREASURY) and the rate in basis points (GLYF_PRIVATE_FEE_BPS,
   *  default 10 = 0.1%). The phone adds the transfer to the transaction the
   *  person signs, so every Glyf private payment carries this one address:
   *  how MagicBlock counts Glyf's usage (Arpit, 2026-10-28). No wallet set,
   *  no fee. */
  app.get("/wallet/fees", async () => {
    const raw = (process.env.GLYF_FEE_WALLET || process.env.GLYF_TREASURY || DEFAULT_FEE_WALLET).trim();
    const wallet = /^[1-9A-HJ-NP-Za-km-z]{32,44}$/.test(raw) ? raw : null;
    const parsed = Number.parseInt(process.env.GLYF_PRIVATE_FEE_BPS ?? "10", 10);
    const bps = Number.isFinite(parsed) && parsed >= 0 && parsed <= 100 ? parsed : 10;
    return { ok: true, privateFeeBps: wallet ? bps : 0, feeWallet: wallet };
  });

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

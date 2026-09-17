import type { FastifyInstance, FastifyReply } from "fastify";
import { z } from "zod";
import { balance, buildTransfer, MagicBlockError, MINTS, quote } from "../lib/magicblock.js";

/**
 * POST /wallet/transfer — build a private payment for the app to sign.
 * GET  /wallet/balance  — what the address holds.
 * POST /wallet/quote    — swap quote for the wallet's Swap tab.
 *
 * The server builds and never signs: no key of the user's is ever here (§1.5).
 * The app signs with its Privy embedded wallet and submits.
 */

const TransferSchema = z.object({
  from: z.string().min(32).max(64),
  to: z.string().min(32).max(64),
  mint: z.string().min(3).max(64).default("USDC"),
  amount: z.string().min(1).max(24),
  private: z.boolean().default(true),
  cluster: z.enum(["mainnet", "devnet"]).optional(),
  memo: z.string().max(120).optional(),
});

const QuoteSchema = z.object({
  from: z.string().min(3).max(64),
  to: z.string().min(3).max(64),
  amount: z.string().min(1).max(24),
  cluster: z.enum(["mainnet", "devnet"]).optional(),
});

function fail(reply: FastifyReply, err: unknown): unknown {
  if (err instanceof MagicBlockError) {
    return reply.code(err.status).send({ ok: false, error: err.message, code: err.code });
  }
  return reply.code(502).send({ ok: false, error: "Payments are unavailable right now" });
}

export function walletRoutes(app: FastifyInstance): void {

  app.get("/wallet/mints", async () => ({ ok: true, mints: MINTS }));

  /** What the app needs to start Privy. Both ids are public by design — the
   *  app secret stays here and is never sent anywhere. */
  app.get("/wallet/config", async () => ({
    ok: true,
    privyAppId: process.env.PRIVY_APP_ID ?? "",
    privyAppClientId: process.env.PRIVY_APP_CLIENT_ID ?? "",
    ready: Boolean(process.env.PRIVY_APP_ID && process.env.PRIVY_APP_CLIENT_ID),
    cluster: process.env.SOLANA_CLUSTER ?? "mainnet",
  }));

  app.post("/wallet/transfer", async (req, reply) => {
    const parsed = TransferSchema.safeParse(req.body);
    if (!parsed.success) {
      req.log.warn({ issues: parsed.error.issues }, "wallet transfer bad request");
      return reply.code(400).send({ ok: false, error: "Bad request" });
    }
    const { from, to, mint, amount, cluster, memo } = parsed.data;
    if (from === to) {
      return reply.code(400).send({ ok: false, error: "That is your own address" });
    }
    try {
      const built = await buildTransfer({
        from, to, mint, amount, private: parsed.data.private, cluster, memo,
      });
      // Amounts and addresses stay out of the log: only that it happened.
      req.log.info({ private: parsed.data.private, mint }, "wallet_transfer_built");
      return {
        ok: true,
        transactionBase64: built.transactionBase64,
        version: built.version,
        requiredSigners: built.requiredSigners,
        recentBlockhash: built.recentBlockhash,
        lastValidBlockHeight: built.lastValidBlockHeight,
        fees: built.fees ?? {},
        private: parsed.data.private,
      };
    } catch (err) {
      return fail(reply, err);
    }
  });

  app.get<{ Querystring: { owner?: string; mint?: string; cluster?: string } }>(
    "/wallet/balance", async (req, reply) => {
      const owner = (req.query.owner ?? "").trim();
      if (owner.length < 32) {
        return reply.code(400).send({ ok: false, error: "Bad request" });
      }
      try {
        const res = await balance(owner, req.query.mint ?? "USDC", req.query.cluster);
        return { ok: true, ...res };
      } catch (err) {
        return fail(reply, err);
      }
    });

  app.post("/wallet/quote", async (req, reply) => {
    const parsed = QuoteSchema.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ ok: false, error: "Bad request" });
    try {
      const res = await quote(parsed.data.from, parsed.data.to,
                              parsed.data.amount, parsed.data.cluster);
      return { ok: true, quote: res };
    } catch (err) {
      return fail(reply, err);
    }
  });
}

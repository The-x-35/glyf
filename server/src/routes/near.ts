import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";
import { z } from "zod";
import type { FetchFn } from "../lib/evm.js";
import { nearRpc, type NearLookup } from "../lib/names.js";
import { guardRecipient } from "../lib/nearguard.js";
import { addressFits, IntentsError, NearIntents, nearChainOf } from "../lib/nearintents.js";

/**
 * NEAR Intents for the trade panel (docs/NEAR-SPEC.md, "Server API"):
 *
 * - POST /near/quote: a live quote with a deposit address when the phone
 *   sends both `refundTo` and `recipient`, a dry preview otherwise; with a
 *   recipient, Guard's checks ride along (lib/nearguard.ts).
 * - GET /near/status?deposit=…: where the swap is, until it lands.
 * - POST /near/submit: the deposit's tx hash, so 1Click picks it up sooner.
 *
 * Session-gated like every route (lib/protect.ts). Quotes cost no run: no
 * model is called. Amounts and addresses stay out of the log.
 */

const Address = z.string().trim().min(1).max(128);

const QuoteBody = z.object({
  sell: z.string().trim().min(1).max(80),
  sellChain: z.string().trim().min(1).max(40),
  buy: z.string().trim().min(1).max(80),
  buyChain: z.string().trim().min(1).max(40),
  amount: z.string().trim().regex(/^\d+(\.\d+)?$/, "amount?").max(40),
  exact: z.enum(["in", "out"]).default("in"),
  refundTo: Address.optional(),
  recipient: Address.optional(),
  slippage: z.number().gt(0).max(50).default(1),
  recent: z.array(Address).max(100).optional(),
  dailyLimitUsd: z.number().nonnegative().optional(),
  spentTodayUsd: z.number().nonnegative().optional(),
});

const DEPOSIT = /^[A-Za-z0-9._:-]{8,128}$/;
const SubmitBody = z.object({
  depositAddress: z.string().trim().regex(DEPOSIT, "depositAddress?"),
  txHash: z.string().trim().regex(/^[A-Za-z0-9]{16,140}$/, "txHash?"),
  memo: z.string().trim().max(64).optional(),
  /** The NEAR account that paid a deposit on NEAR (1Click's nearSenderAccount). */
  nearSenderAccount: z.string().trim().regex(/^[a-z0-9._-]{2,64}$/, "nearSenderAccount?").optional(),
});

export interface NearDeps {
  fetchImpl?: FetchFn;
  /** NEAR_INTENTS_JWT unless a test passes one. */
  jwt?: () => string;
  near?: NearLookup;
  now?: () => number;
}

export function nearRoutes(app: FastifyInstance, deps: NearDeps = {}): void {
  const intents = new NearIntents({ fetchImpl: deps.fetchImpl, jwt: deps.jwt, now: deps.now });
  const near = deps.near ?? nearRpc(deps.fetchImpl);

  function failed(req: FastifyRequest, reply: FastifyReply, err: unknown, what: string) {
    if (err instanceof IntentsError) {
      if (err.status === 502) req.log.warn({ err: err.message }, `${what}_failed`);
      return reply.code(err.status).send({ ok: false, error: err.message });
    }
    req.log.warn({ err: err instanceof Error ? err.message : String(err) }, `${what}_failed`);
    return reply.code(502).send({ ok: false, error: "NEAR Intents didn't answer. Try again in a moment" });
  }

  app.post("/near/quote", async (req, reply) => {
    const parsed = QuoteBody.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ ok: false, error: parsed.error.issues[0]?.message ?? "Bad request" });
    const b = parsed.data;
    const buyChain = nearChainOf(b.buyChain);
    // A recipient that can't be on the destination chain gets the preview
    // and Guard's block, rather than 1Click's "recipient is not valid".
    const fits = !b.recipient || !buyChain || addressFits(buyChain, b.recipient);
    const ask = (recipient?: string) => intents.quote({ sell: b.sell, sellChain: b.sellChain, buy: b.buy,
      buyChain: b.buyChain, amount: b.amount, exact: b.exact, slippage: b.slippage, refundTo: b.refundTo,
      ...(recipient ? { recipient } : {}) });
    const check = (amountInUsd: string | null) => guardRecipient({ recipient: b.recipient!, chain: buyChain!,
      recent: b.recent, amountInUsd: amountInUsd === null ? null : Number(amountInUsd),
      dailyLimitUsd: b.dailyLimitUsd, spentTodayUsd: b.spentTodayUsd }, near);
    try {
      let quote: Awaited<ReturnType<typeof ask>>;
      let guard: Awaited<ReturnType<typeof check>> | undefined;
      try {
        quote = await ask(fits ? b.recipient : undefined);
      } catch (err) {
        // 1Click refuses a live quote to a .near name that doesn't exist
        // with a bare "Internal server error". When Guard blocks that
        // recipient anyway, the answer is the preview with Guard's reason.
        if (!(err instanceof IntentsError) || err.status !== 400 || !fits || !b.recipient || !buyChain) throw err;
        guard = await check(null);
        if (guard.level !== "block") throw err;
        quote = await ask(undefined);
      }
      if (b.recipient && buyChain && !guard) guard = await check(quote.amountInUsd);
      req.log.info({ sellChain: quote.sell.chain, buyChain: quote.buy.chain, exact: quote.exact, dry: quote.dry,
        guard: guard?.level }, "near_quote");
      return { ...quote, ...(guard ? { guard } : {}) };
    } catch (err) {
      return failed(req, reply, err, "near_quote");
    }
  });

  app.get("/near/status", async (req, reply) => {
    const q = req.query as { deposit?: string; depositAddress?: string; memo?: string };
    const deposit = String(q.deposit ?? q.depositAddress ?? "").trim();
    if (!DEPOSIT.test(deposit)) return reply.code(400).send({ ok: false, error: "deposit?" });
    const memo = typeof q.memo === "string" && q.memo.trim() ? q.memo.trim().slice(0, 64) : undefined;
    try {
      const status = await intents.status(deposit, memo);
      reply.header("cache-control", "no-store");
      return status;
    } catch (err) {
      return failed(req, reply, err, "near_status");
    }
  });

  app.post("/near/submit", async (req, reply) => {
    const parsed = SubmitBody.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ ok: false, error: parsed.error.issues[0]?.message ?? "Bad request" });
    const b = parsed.data;
    try {
      const out = await intents.submit(b.depositAddress, b.txHash, b.memo || undefined, b.nearSenderAccount || undefined);
      req.log.info("near_submit");
      return out;
    } catch (err) {
      return failed(req, reply, err, "near_submit");
    }
  });
}

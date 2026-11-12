import { randomBytes } from "node:crypto";
import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";
import { z } from "zod";
import { env } from "../env.js";
import type { FetchFn } from "../lib/evm.js";
import type { Limiter } from "../lib/limits.js";
import { NEAR_NAME, nearRpc, type NearLookup } from "../lib/names.js";
import { IntentsError, NEAR_CHAINS, NearIntents, nearChainOf, type StatusAnswer } from "../lib/nearintents.js";
import { depositUri, metamaskLink, notFoundPage, qrDataUri, renderPayPage } from "../lib/paypage.js";
import {
  amountWords, chainForRecipient, coinWords, cleanAmount, getPayer, getRequest, MAX_PAYERS, newId, PAY_WITH, payersOf,
  recipientProblem, saveRequest, savePayer, shareOf, SPUTNIK, tallyOf, type Payer, type PayRequest,
} from "../lib/payrequests.js";
import { clientIp } from "../lib/protect.js";
import type { KV } from "../lib/store.js";

/**
 * Pay links (docs/NEAR-SPEC.md, "Pay links"):
 *
 * - POST /near/requests (session): "you owe me $22.50" as a link.
 * - GET /pay/:id (open): the page.
 * - POST /pay/:id/quote (open, per-IP limit): a live EXACT_OUTPUT NEAR
 *   Intents quote that pays the requester exactly their amount, on their
 *   chain, from whatever the payer picked; a deposit address and its QR.
 * - GET /pay/:id/status[?deposit=] (open): one payer's deposit, as GET
 *   /near/status says it, and the link's "2 of 4 paid".
 *
 * Nothing is signed here: the payer's own wallet sends the deposit, and
 * 1Click pays the requester or refunds the payer. Addresses and amounts stay
 * out of the log.
 */

const Address = z.string().trim().min(2).max(128);

const RequestBody = z.object({
  amount: z.union([z.number(), z.string().max(24)]),
  coin: z.string().trim().max(12).regex(/^\$?[A-Za-z][A-Za-z0-9.]{0,10}$/, "coin?").default("USDC"),
  chain: z.string().trim().min(1).max(40).optional(),
  to: Address,
  note: z.string().max(200).default(""),
  each: z.boolean().optional(),
  count: z.number().int().min(1).max(100).optional(),
  /** The writer is one of `count` ("$90 for 4 of us"): the share is still
   *  the total over count, and count - 1 people are asked to pay. */
  us: z.boolean().optional(),
});

const QuoteBody = z.object({
  with: z.enum(PAY_WITH.map(o => o.id) as [string, ...string[]]),
  refundTo: Address,
});

const DEPOSIT = /^[A-Za-z0-9._:-]{8,128}$/;
/** A pending payer is asked about again at most this often, and only for a
 *  day: a deposit address 1Click gave out expires within hours. */
const RECHECK_MS = 30_000;
const FOLLOW_MS = 24 * 3600 * 1000;
const RECHECKS_PER_LOOK = 6;

export interface PayDeps {
  kv: KV;
  limits: Limiter;
  fetchImpl?: FetchFn;
  jwt?: () => string;
  near?: NearLookup;
  now?: () => number;
  /** Where links point; PUBLIC_BASE_URL, else api.tryglyf.com in production. */
  base?: () => string;
  /** Quotes one address may ask for a minute. */
  quotesPerMinute?: number;
  /** Links one account may make a day. */
  requestsPerDay?: number;
}

export function payBase(): string {
  const set = process.env.PUBLIC_BASE_URL?.trim().replace(/\/+$/, "");
  if (set) return set;
  if (process.env.NODE_ENV === "production" || process.env.VERCEL) return "https://api.tryglyf.com";
  return `http://127.0.0.1:${env.port}`;
}

/** Plain words for the note: no control characters, one line, 80 at most. */
export function cleanNote(raw: string): string {
  return raw.replace(/[\u0000-\u001f\u007f-\u009f\u200b-\u200f\u2028-\u202e\u2066-\u2069]/g, " ")
    .replace(/\s+/g, " ").trim().slice(0, 80).trim();
}

/** What the keyboard puts in the chat with the link. */
export function chatText(r: PayRequest, url: string): string {
  const money = amountWords(r.amount, r.coin);
  const forWhat = r.note ? ` for ${r.note}` : "";
  if (r.pot) return `Chip in ${money}${forWhat}: ${url}`;
  if (r.each || r.count) return `Pay your ${money} share${forWhat}: ${url}`;
  return `Pay ${money}${forWhat}: ${url}`;
}

export function payRoutes(app: FastifyInstance, deps: PayDeps): void {
  const { kv, limits } = deps;
  const intents = new NearIntents({ fetchImpl: deps.fetchImpl, jwt: deps.jwt, now: deps.now });
  const near = deps.near ?? nearRpc(deps.fetchImpl);
  const now = deps.now ?? Date.now;
  const base = deps.base ?? payBase;
  const quotesPerMinute = deps.quotesPerMinute ?? 10;
  const requestsPerDay = deps.requestsPerDay ?? 100;

  function failed(req: FastifyRequest, reply: FastifyReply, err: unknown, what: string) {
    if (err instanceof IntentsError) {
      if (err.status === 502) req.log.warn({ err: err.message }, `${what}_failed`);
      return reply.code(err.status).send({ ok: false, error: err.message });
    }
    req.log.warn({ err: err instanceof Error ? err.message : String(err) }, `${what}_failed`);
    return reply.code(502).send({ ok: false, error: "NEAR Intents didn't answer. Try again in a moment" });
  }

  /** Asks 1Click about one payer and keeps what it said. */
  async function check(p: Payer, memo?: string): Promise<StatusAnswer> {
    const s = await intents.status(p.depositAddress, memo ?? p.depositMemo ?? undefined);
    const t = now();
    savePayer(kv, { ...p, status: s.status, checkedAt: t,
      paidAt: s.status === "SUCCESS" ? (p.paidAt ?? t) : p.paidAt });
    return s;
  }

  /** The link's payers who may have paid since anyone looked: a few at a
   *  time, each at most every 30 s, for a day. */
  async function recheck(id: string): Promise<void> {
    const t = now();
    const due = payersOf(kv, id)
      .filter(p => ["PENDING_DEPOSIT", "INCOMPLETE_DEPOSIT", "PROCESSING"].includes(p.status)
        && t - p.createdAt < FOLLOW_MS && t - p.checkedAt >= RECHECK_MS)
      .sort((a, b) => a.checkedAt - b.checkedAt)
      .slice(0, RECHECKS_PER_LOOK);
    await Promise.all(due.map(p => check(p).catch(() => undefined)));
  }

  app.post("/near/requests", async (req, reply) => {
    const user = req.glyfUser;
    if (!user) return reply.code(401).send({ ok: false, error: "Sign in to use Glyf" });
    const parsed = RequestBody.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ ok: false, error: parsed.error.issues[0]?.message ?? "Bad request" });
    const b = parsed.data;
    const amount = cleanAmount(b.amount);
    if (!amount) return reply.code(400).send({ ok: false, error: "amount?" });
    const to = b.to.trim();
    const chain = b.chain ? nearChainOf(b.chain) : chainForRecipient(to);
    if (!chain) return reply.code(400).send({ ok: false, error: `NEAR Intents isn't on ${b.chain!.slice(0, 20)}` });
    const problem = recipientProblem(chain, to);
    if (problem) return reply.code(400).send({ ok: false, error: problem });
    if (await limits.spend(`user:${user}|payreq`, "day", requestsPerDay) < 0) {
      return reply.code(429).send({ ok: false, error: "That's a lot of pay links for one day. Try again tomorrow" });
    }
    if (chain.key === "near" && NEAR_NAME.test(to)) {
      // Coins sent to a NEAR account that isn't there come back as a refund
      // at best. A node that can't say lets the link through.
      const exists = await near.exists(to).catch(() => true);
      if (!exists) return reply.code(400).send({ ok: false, error: `No NEAR account ${to}` });
    }
    let coin: string;
    try {
      const token = await intents.token(chain, b.coin.replace(/^\$/, ""));
      coin = token.symbol.toUpperCase() === "WNEAR" ? "NEAR" : token.symbol.toUpperCase() === "GRAM" ? "TON" : token.symbol.toUpperCase();
    } catch (err) {
      return failed(req, reply, err, "pay_request");
    }
    const each = b.each === true;
    const share = shareOf(amount, coin, each, b.count ?? null);
    const count = b.count === undefined ? null : b.us && b.count >= 2 ? b.count - 1 : b.count;
    const r: PayRequest = {
      id: newId(), amount: share, typedAmount: amount, coin, chain: chain.key, to,
      note: cleanNote(b.note), each, count, pot: SPUTNIK.test(to), createdBy: user, createdAt: now(),
    };
    saveRequest(kv, r);
    const url = `${base()}/pay/${r.id}`;
    req.log.info({ chain: r.chain, pot: r.pot, each, count }, "pay_request");
    return { ok: true, id: r.id, url, text: chatText(r, url), amount: r.amount, coin: r.coin, chain: r.chain,
      to: r.to, note: r.note, each: r.each, count: r.count, pot: r.pot };
  });

  app.get("/pay/:id", async (req, reply) => {
    const r = getRequest(kv, (req.params as { id: string }).id);
    reply.header("x-content-type-options", "nosniff");
    reply.header("referrer-policy", "no-referrer");
    if (!r) {
      reply.header("content-security-policy", "default-src 'none'; style-src 'unsafe-inline'; frame-ancestors 'none'");
      return reply.code(404).type("text/html").send(notFoundPage());
    }
    const nonce = randomBytes(16).toString("base64");
    reply.header("cache-control", "no-store");
    // One script, this page's; it may only talk to this server.
    reply.header("content-security-policy",
      `default-src 'none'; script-src 'nonce-${nonce}'; style-src 'unsafe-inline'; img-src data:; connect-src 'self'; `
      + "base-uri 'none'; form-action 'none'; frame-ancestors 'none'");
    return reply.type("text/html").send(renderPayPage(r, tallyOf(r, payersOf(kv, r.id)), nonce));
  });

  app.post("/pay/:id/quote", async (req, reply) => {
    if (await limits.spend(`ip:${clientIp(req)}|payquote`, "minute", quotesPerMinute) < 0) {
      return reply.code(429).send({ ok: false, error: "Too many tries. Wait a minute" });
    }
    const r = getRequest(kv, (req.params as { id: string }).id);
    if (!r) return reply.code(404).send({ ok: false, error: "This pay link doesn't exist" });
    const parsed = QuoteBody.safeParse(req.body);
    if (!parsed.success) {
      const field = parsed.error.issues[0]?.path[0];
      return reply.code(400).send({ ok: false, error: field === "refundTo" ? "Add your refund address" : "Pick what you pay with" });
    }
    const pick = PAY_WITH.find(o => o.id === parsed.data.with)!;
    const payers = payersOf(kv, r.id);
    if (tallyOf(r, payers).full) return reply.code(409).send({ ok: false, error: "Everyone's paid" });
    if (payers.length >= MAX_PAYERS) return reply.code(429).send({ ok: false, error: "This link has had too many tries" });
    const payChain = NEAR_CHAINS[pick.chain];
    if (pick.coin === r.coin && pick.chain === r.chain) {
      return reply.code(400).send({ ok: false, error: `That's what they asked for. Send ${r.coin} on ${payChain.name} straight to ${r.to}` });
    }
    try {
      const q = await intents.quote({ sell: pick.coin, sellChain: pick.chain, buy: r.coin, buyChain: r.chain,
        amount: r.amount, exact: "out", refundTo: parsed.data.refundTo, recipient: r.to });
      if (q.dry || !q.depositAddress || !q.deposit) throw new IntentsError(502, "NEAR Intents sent back no deposit address");
      const t = now();
      savePayer(kv, { request: r.id, depositAddress: q.depositAddress, depositMemo: q.depositMemo, coin: q.sell.symbol,
        chain: payChain.key, amountIn: q.amountIn, status: "PENDING_DEPOSIT", createdAt: t, checkedAt: t, paidAt: null });
      const uri = depositUri(payChain.key, q.depositAddress, q.amountIn,
        q.deposit.kind === "spl" ? q.deposit.mint : undefined);
      req.log.info({ chain: payChain.key, to: r.chain }, "pay_quote");
      return {
        ok: true, venue: q.venue, depositAddress: q.depositAddress, depositMemo: q.depositMemo,
        amount: q.amountIn, amountBase: q.amountInBase, amountUsd: q.amountInUsd, coin: q.sell.symbol,
        chain: payChain.key, chainName: payChain.name,
        gets: `${coinWords(r.amount, r.coin)} on ${NEAR_CHAINS[r.chain]?.name ?? r.chain}`,
        deadline: q.deadline, timeSeconds: q.timeSeconds, deposit: q.deposit,
        qr: await qrDataUri(uri), uri, wallet: metamaskLink(q.deposit), explorer: q.explorer,
      };
    } catch (err) {
      return failed(req, reply, err, "pay_quote");
    }
  });

  app.get("/pay/:id/status", async (req, reply) => {
    const r = getRequest(kv, (req.params as { id: string }).id);
    if (!r) return reply.code(404).send({ ok: false, error: "This pay link doesn't exist" });
    reply.header("cache-control", "no-store");
    const q = req.query as { deposit?: string; memo?: string };
    if (q.deposit === undefined) {
      await recheck(r.id);
      return { ok: true, tally: tallyOf(r, payersOf(kv, r.id)) };
    }
    const deposit = String(q.deposit).trim();
    if (!DEPOSIT.test(deposit)) return reply.code(400).send({ ok: false, error: "deposit?" });
    const payer = getPayer(kv, r.id, deposit);
    if (!payer) return reply.code(404).send({ ok: false, error: "That deposit isn't for this link" });
    const memo = typeof q.memo === "string" && q.memo.trim() ? q.memo.trim().slice(0, 64) : undefined;
    try {
      const s = await check(payer, memo);
      return { ...s, tally: tallyOf(r, payersOf(kv, r.id)) };
    } catch (err) {
      return failed(req, reply, err, "pay_status");
    }
  });
}

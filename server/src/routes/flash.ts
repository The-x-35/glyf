import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";
import { z } from "zod";
import { chainOf, type FetchFn } from "../lib/evm.js";
import { findSolanaToken, findToken, NATIVE } from "../lib/tokens.js";

/**
 * Definitive Flash, for the keyboard's trades: "sell my ETH if it drops
 * below 3000" is a Flash stop-loss, "buy $20 of eth over a day" a TWAP.
 *
 * Flash is non-custodial: /quote returns what the wallet signs (EIP-712
 * typed data on EVM, a plain Ed25519 message on Solana), the phone signs it,
 * and /order hands the signature back. This server only adds the API key
 * (FLASH_API_KEY, never shipped in the app), checks each body's shape
 * against Flash's documented API (flash.definitive.fi/v1/openapi.json,
 * read 2026-11-06), and turns the coins the keyboard names ("ETH", "USDC")
 * into the addresses Flash wants. Quotes come back as Flash wrote them.
 */

export const FLASH_API = "https://flash.definitive.fi/v1";

const CHAINS = ["arbitrum", "avalanche", "base", "bsc", "ethereum", "optimism", "polygon", "solana",
  "hyperevm", "plasma", "monad", "robinhood", "ink", "arc", "elysium"] as const;
const ORDER_TYPES = ["market", "limit", "twap", "stop", "stop-loss", "take-profit", "bracket",
  "trailing-stop", "trailing-stop-limit"] as const;
/** Flash has no separate type for these: a stop, stop-loss or take-profit
 *  with a limit price IS its limit variant (placing-orders.md). */
const LIMIT_VARIANTS: Record<string, (typeof ORDER_TYPES)[number]> = {
  "stop-limit": "stop", "stop-loss-limit": "stop-loss", "take-profit-limit": "take-profit",
};

const Decimal = z.string().regex(/^\d+(\.\d+)?$/).max(40);
const Time = z.string().datetime({ offset: true });
const Address = z.string().min(1).max(64);
const Trigger = z.object({
  notionalPrice: Decimal.optional(),
  crossPrice: Decimal.optional(),
  triggerType: z.enum(["upper", "lower"]),
  limitPrice: Decimal.optional(),
}).refine(t => Boolean(t.notionalPrice) !== Boolean(t.crossPrice), "each trigger takes one of notionalPrice or crossPrice");
const TrailingStop = z.object({ trailPercent: Decimal, activationPrice: Decimal.optional() });
const BracketLeg = z.object({
  notionalPrice: Decimal.optional(),
  crossPrice: Decimal.optional(),
  limitPrice: Decimal.optional(),
}).refine(t => Boolean(t.notionalPrice) !== Boolean(t.crossPrice), "each leg takes one of notionalPrice or crossPrice");

/** The trade itself, shared by /quote and /order. */
const Trade = {
  targetChain: z.enum(CHAINS),
  contraChain: z.enum(CHAINS),
  targetAsset: Address,
  contraAsset: Address,
  side: z.enum(["buy", "sell"]),
  qty: Decimal,
  orderType: z.enum(ORDER_TYPES),
  quickTrade: z.boolean().optional(),
  maxSlippage: Decimal.optional(),
  maxPriceImpact: Decimal.optional(),
  limitNotionalPrice: Decimal.optional(),
  limitCrossPrice: Decimal.optional(),
  recipientAddress: Address.optional(),
  flashIntegratorFeeBps: z.string().regex(/^\d{1,4}$/).optional(),
  twapBucketCount: z.number().int().min(2).max(2560).optional(),
  startTime: Time.optional(),
  triggers: z.array(Trigger).max(2).optional(),
  trailingStop: TrailingStop.optional(),
};

const QuoteSchema = z.object({
  ...Trade,
  funderAddress: Address.optional(),
  evmUsePermit2: z.boolean().optional(),
  forceMinimalAllowance: z.boolean().optional(),
  svmUseNativeSOL: z.boolean().optional(),
  expireTime: Time.optional(),
  durationSeconds: z.number().int().min(300).optional(),
  attachedBracket: z.object({ takeProfit: BracketLeg, stopLoss: BracketLeg, expireTime: Time.optional() }).optional(),
});

const OrderSchema = z.object({
  ...Trade,
  funderAddress: Address,
  quoteId: z.string().min(1).max(200).optional(),
  bridgeQuoteId: z.string().min(1).max(200).optional(),
  erc8021AttributionCode: z.string().regex(/^[a-zA-Z0-9_.-]{1,32}$/).optional(),
  userSignature: z.string().min(1).max(1000),
  evmOrderTypedData: z.string().max(20_000).optional(),
  evmPermitTypedData: z.string().max(20_000).optional(),
  evmPermitSignature: z.string().max(1000).optional(),
  svmNonce: z.string().max(100).optional(),
  svmDeadline: z.string().max(40).optional(),
  svmSponsoredDelegateTx: z.string().max(4000).optional(),
  attachedBracket: z.object({
    takeProfit: BracketLeg,
    stopLoss: BracketLeg,
    userSignature: z.string().min(1).max(1000),
    salt: z.string().min(1).max(200).optional(),
    svmNonce: z.string().min(1).max(100).optional(),
    deadline: z.string().min(1).max(40),
    signedMaxFromAmount: z.string().min(1).max(80),
    evmPermitSignature: z.string().max(1000).optional(),
    evmPermitTypedData: z.string().max(20_000).optional(),
  }).optional(),
});

const SignedMessage = z.object({
  cancelMessage: z.string().min(1).max(4000),
  userSignature: z.string().min(1).max(1000),
});
const BatchCancel = SignedMessage.extend({
  orderIds: z.array(z.string().regex(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/)).min(1).max(25),
});
const UpdateSchema = z.object({
  updateMessage: z.string().min(1).max(4000),
  userSignature: z.string().min(1).max(1000),
  limitNotionalPrice: Decimal.optional(),
  limitCrossPrice: Decimal.optional(),
  trigger: z.record(z.unknown()).optional(),
  triggers: z.array(z.record(z.unknown())).max(2).optional(),
});
const OrderId = z.string().uuid();

/** Fields /order takes, so a quote's request can be turned into the body
 *  the phone submits (everything else is quote-only). */
const ORDER_FIELDS = new Set(Object.keys(OrderSchema.shape));

export interface FlashDeps {
  /** FLASH_API_KEY unless a test passes one. */
  apiKey?: string;
  fetchImpl?: FetchFn;
}

type Token = { address: string; symbol?: string; decimals?: number; native?: boolean };

/** "ETH", "usdc", or an address, on one of Flash's chains. A gas coin is
 *  Flash's native convention: 0xEeee… on EVM (the quote then carries a
 *  `wrap` to send first), the wSOL mint on Solana. */
function tokenOn(chain: string, query: string): Token | null {
  const raw = query.trim();
  if (chain === "solana") {
    const sol = findSolanaToken(raw);
    if (sol) return sol;
    return /^[1-9A-HJ-NP-Za-km-z]{32,44}$/.test(raw) ? { address: raw } : null;
  }
  const evm = chainOf(chain);
  const listed = evm ? findToken(evm, raw) : null;
  if (listed) return { ...listed, address: listed.native ? NATIVE : listed.address };
  return /^0x[0-9a-fA-F]{40}$/.test(raw) ? { address: raw } : null;
}

/** What Flash's docs require of each order type, said before Flash has to. */
function shapeProblem(q: z.infer<typeof QuoteSchema>): string | null {
  const limit = Boolean(q.limitNotionalPrice) || Boolean(q.limitCrossPrice);
  if (q.limitNotionalPrice && q.limitCrossPrice) return "Set one of limitNotionalPrice or limitCrossPrice";
  if (q.targetChain !== q.contraChain) {
    if (q.orderType !== "market") return "Cross-chain orders are market orders only";
    if (!q.recipientAddress) return "A cross-chain order needs recipientAddress";
  }
  switch (q.orderType) {
    case "market":
      if (limit) return "A market order takes no limit price";
      break;
    case "limit":
      if (!limit) return "A limit order needs a limit price";
      break;
    case "twap":
      if (!q.durationSeconds) return "A TWAP needs durationSeconds (at least 300)";
      break;
    case "stop": case "stop-loss": case "take-profit":
      if (q.triggers?.length !== 1) return `A ${q.orderType} order takes exactly one trigger`;
      if (q.triggers[0].limitPrice) return "Use limitNotionalPrice for a trigger order's limit";
      if (q.orderType === "stop-loss" && q.triggers[0].triggerType !== "lower") return "A stop-loss fires on a lower trigger";
      if (q.orderType === "take-profit" && q.triggers[0].triggerType !== "upper") return "A take-profit fires on an upper trigger";
      break;
    case "bracket":
      if (q.side !== "sell") return "A bracket sells an asset you hold";
      if (q.triggers?.length !== 2 || q.triggers[0].triggerType === q.triggers[1].triggerType) {
        return "A bracket takes two triggers, one upper and one lower";
      }
      if (limit) return "A bracket's limits go on each trigger's limitPrice";
      break;
    case "trailing-stop": case "trailing-stop-limit":
      if (!q.trailingStop) return "A trailing stop needs trailingStop.trailPercent";
      if (limit || q.triggers?.length) return "A trailing stop takes no limit price or triggers";
      break;
  }
  if (q.trailingStop && !q.orderType.startsWith("trailing")) return "trailingStop is only for trailing stops";
  if (q.durationSeconds && q.orderType !== "twap") return "durationSeconds is only for TWAP";
  if (q.attachedBracket) {
    if (!["market", "limit", "twap"].includes(q.orderType)) return "An attached bracket rides a market, limit or TWAP order";
    if (q.targetChain !== q.contraChain) return "An attached bracket is same-chain only";
    if (!q.funderAddress) return "An attached bracket needs funderAddress";
    if (q.orderType === "limit" && q.limitNotionalPrice) return "With an attached bracket, give the limit as limitCrossPrice";
  }
  return null;
}

export function flashRoutes(app: FastifyInstance, deps: FlashDeps = {}): void {
  const fetchImpl = deps.fetchImpl ?? fetch;

  /** One call to Flash. Its own error ({error: {code, message}}) goes back
   *  with its status; a Flash that doesn't answer is a 502. */
  async function flash(req: FastifyRequest, reply: FastifyReply, path: string,
    init: { method?: string; body?: unknown; query?: Record<string, string | undefined> } = {}) {
    const key = (deps.apiKey ?? process.env.FLASH_API_KEY ?? "").trim();
    if (!key) return reply.code(503).send({ ok: false, error: "Trading isn't set up on this server" });
    const qs = new URLSearchParams(Object.entries(init.query ?? {})
      .filter((e): e is [string, string] => typeof e[1] === "string" && e[1] !== "")).toString();
    try {
      const res = await fetchImpl(`${FLASH_API}${path}${qs ? `?${qs}` : ""}`, {
        method: init.method ?? "GET",
        headers: { "x-definitive-api-key": key, accept: "application/json",
          ...(init.body !== undefined ? { "content-type": "application/json" } : {}) },
        ...(init.body !== undefined ? { body: JSON.stringify(init.body) } : {}),
        signal: AbortSignal.timeout(20_000),
      });
      const json = await res.json().catch(() => null) as Record<string, unknown> | null;
      // Wallets, amounts and signatures stay out of the log.
      req.log.info({ path: path.replace(/[0-9a-f-]{36}/, ":id"), status: res.status }, "flash");
      if (!res.ok || !json) {
        const err = (json?.error ?? {}) as { code?: string; message?: string };
        const status = res.status >= 400 && res.status < 500 ? res.status : 502;
        return { failed: reply.code(status).send({ ok: false, error: err.message ?? "Flash couldn't do that", code: err.code }) };
      }
      return { json };
    } catch (err) {
      req.log.warn({ path, err: err instanceof Error ? err.message : String(err) }, "flash_failed");
      return { failed: reply.code(502).send({ ok: false, error: "Flash didn't answer. Try again in a moment" }) };
    }
  }

  /** ?query=pepe&chain=base&limit=10 — Flash's asset search. */
  app.get("/flash/search", async (req, reply) => {
    const q = req.query as { query?: string; chain?: string; limit?: string };
    const query = (q.query ?? "").trim();
    if (!query || query.length > 80) return reply.code(400).send({ ok: false, error: "query?" });
    if (q.chain && !(CHAINS as readonly string[]).includes(q.chain)) return reply.code(400).send({ ok: false, error: "chain?" });
    const limit = Math.min(Math.max(Number.parseInt(q.limit ?? "10", 10) || 10, 1), 25);
    const out = await flash(req, reply, "/search", { query: { query, chain: q.chain, limit: String(limit) } });
    if ("failed" in out) return out.failed;
    return { ok: true, ...out.json };
  });

  /** Flash's own quote body, except the coins may come as `target` and
   *  `contra` symbols ("ETH", "USDC") instead of targetAsset/contraAsset.
   *  The answer is Flash's quote as it wrote it, plus `tokens` (what each
   *  symbol became) and `order`: the /flash/order body with every echo
   *  Flash wants already in place, for the phone to add its signatures. */
  app.post("/flash/quote", async (req, reply) => {
    const body = { ...(req.body as Record<string, unknown> ?? {}) };
    if (typeof body.chain === "string") {
      body.targetChain ??= body.chain;
      body.contraChain ??= body.chain;
    }
    delete body.chain;
    if (typeof body.orderType === "string" && LIMIT_VARIANTS[body.orderType]) {
      const limitless = !body.limitNotionalPrice && !body.limitCrossPrice;
      if (limitless) return reply.code(400).send({ ok: false, error: `A ${body.orderType} order needs a limit price` });
      body.orderType = LIMIT_VARIANTS[body.orderType];
    }
    const tokens: Record<"target" | "contra", Token | null> = { target: null, contra: null };
    for (const side of ["target", "contra"] as const) {
      const named = body[side];
      delete body[side];
      if (typeof named !== "string") continue;
      const chain = String(body[`${side}Chain`] ?? "");
      const token = tokenOn(chain, named);
      if (!token) return reply.code(400).send({ ok: false, error: `Don't know ${named.slice(0, 20)} on ${chain || "that chain"}` });
      tokens[side] = token;
      body[`${side}Asset`] = token.address;
    }
    const parsed = QuoteSchema.safeParse(body);
    if (!parsed.success) {
      return reply.code(400).send({ ok: false, error: parsed.error.issues[0]?.message ?? "Bad request",
        field: parsed.error.issues[0]?.path.join(".") });
    }
    const quote = parsed.data;
    const problem = shapeProblem(quote);
    if (problem) return reply.code(400).send({ ok: false, error: problem });
    // Spending native SOL takes Flash's native-SOL intent; it quotes the
    // wrap instructions to send first.
    const spentSide = quote.side === "buy" ? "contra" : "target";
    const spentChain = quote[`${spentSide}Chain`];
    if (spentChain === "solana" && quote[`${spentSide}Asset`] === "So11111111111111111111111111111111111111112"
      && tokens[spentSide]?.native && quote.svmUseNativeSOL === undefined) {
      quote.svmUseNativeSOL = true;
    }
    const out = await flash(req, reply, "/quote", { method: "POST", body: quote });
    if ("failed" in out) return out.failed;
    const answer = out.json as Record<string, any>;
    return { ok: true, ...answer, tokens, order: orderDraft(quote, answer, spentSide) };
  });

  app.post("/flash/order", async (req, reply) => {
    const parsed = OrderSchema.safeParse(req.body);
    if (!parsed.success) {
      return reply.code(400).send({ ok: false, error: parsed.error.issues[0]?.message ?? "Bad request",
        field: parsed.error.issues[0]?.path.join(".") });
    }
    const order = parsed.data;
    for (const side of ["targetAsset", "contraAsset"] as const) {
      const spent = order.side === "buy" ? "contraAsset" : "targetAsset";
      if (side === spent && order[side].toLowerCase() === NATIVE.toLowerCase()) {
        return reply.code(400).send({ ok: false, error: "Submit with the wrapped coin from the quote's wrap.wrappedAsset" });
      }
    }
    const out = await flash(req, reply, "/order", { method: "POST", body: order });
    if ("failed" in out) return out.failed;
    return { ok: true, ...out.json };
  });

  /** ?funderAddress=…, and orderId for one order with its fills. A list
   *  always names its wallet: without one, Flash returns every wallet's
   *  orders under Glyf's key. */
  app.get("/flash/orders", async (req, reply) => {
    const q = req.query as { funderAddress?: string; orderId?: string; statuses?: string; pageSize?: string; pageToken?: string };
    const funder = (q.funderAddress ?? "").trim();
    if (!funder || funder.length > 64) return reply.code(400).send({ ok: false, error: "funderAddress?" });
    if (q.orderId) {
      if (!OrderId.safeParse(q.orderId).success) return reply.code(400).send({ ok: false, error: "orderId?" });
      const out = await flash(req, reply, `/orders/${q.orderId}`, { query: { funderAddress: funder } });
      if ("failed" in out) return out.failed;
      return { ok: true, ...out.json };
    }
    if (q.statuses && !/^[A-Z_,]{1,400}$/.test(q.statuses)) return reply.code(400).send({ ok: false, error: "statuses?" });
    const pageSize = q.pageSize ? String(Math.min(Math.max(Number.parseInt(q.pageSize, 10) || 50, 1), 200)) : undefined;
    const out = await flash(req, reply, "/orders", { query: { funderAddress: funder, statuses: q.statuses,
      pageSize, pageToken: q.pageToken?.slice(0, 500) } });
    if ("failed" in out) return out.failed;
    return { ok: true, ...out.json };
  });

  /** Cancel one order: the funder signs Flash's own cancel message. */
  app.post("/flash/orders/:orderId/cancel", async (req, reply) => {
    const { orderId } = req.params as { orderId: string };
    const parsed = SignedMessage.safeParse(req.body);
    if (!OrderId.safeParse(orderId).success || !parsed.success) return reply.code(400).send({ ok: false, error: "Bad request" });
    const out = await flash(req, reply, `/orders/${orderId}/cancel`, { method: "POST", body: parsed.data });
    if ("failed" in out) return out.failed;
    return { ok: true, ...out.json };
  });

  /** Cancel up to 25 with one signature. */
  app.post("/flash/orders/cancel", async (req, reply) => {
    const parsed = BatchCancel.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ ok: false, error: "Bad request" });
    const out = await flash(req, reply, "/orders/cancel", { method: "POST", body: parsed.data });
    if ("failed" in out) return out.failed;
    return { ok: true, ...out.json };
  });

  /** Move a resting order's limit or trigger ("move my stop to 2900"). */
  app.patch("/flash/orders/:orderId", async (req, reply) => {
    const { orderId } = req.params as { orderId: string };
    const parsed = UpdateSchema.safeParse(req.body);
    if (!OrderId.safeParse(orderId).success || !parsed.success) return reply.code(400).send({ ok: false, error: "Bad request" });
    const out = await flash(req, reply, `/orders/${orderId}`, { method: "PATCH", body: parsed.data });
    if ("failed" in out) return out.failed;
    return { ok: true, ...out.json };
  });

  /** A signed entry of the quote's setupTxs (token accounts, a wrap, an
   *  allowance), broadcast by Flash so the phone needs no RPC for it. */
  app.post("/flash/setup-transaction", async (req, reply) => {
    const parsed = z.object({ signedSetupTx: z.string().min(1).max(20_000) }).safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ ok: false, error: "Bad request" });
    const out = await flash(req, reply, "/setup-transaction", { method: "POST", body: parsed.data });
    if ("failed" in out) return out.failed;
    return { ok: true, ...out.json };
  });
}

/** The /flash/order body for a quote, minus the signatures: the same trade
 *  (Flash checks it against what was signed), the spent gas coin swapped for
 *  the wrapped one the quote priced (evm-overview.md: submitting 0xEeee… as
 *  the spent asset is rejected), and every value the docs say to echo. The
 *  phone adds `userSignature`, `evmPermitSignature` when there is a permit,
 *  `svmSponsoredDelegateTx` (signed) when offered, and
 *  `attachedBracket.userSignature` / `attachedBracket.evmPermitSignature`. */
function orderDraft(quote: z.infer<typeof QuoteSchema>, answer: Record<string, any>, spentSide: "target" | "contra") {
  const draft: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(quote)) {
    if (ORDER_FIELDS.has(k) && k !== "attachedBracket" && v !== undefined) draft[k] = v;
  }
  const wrapped = answer.wrap?.wrappedAsset;
  if (typeof wrapped === "string" && quote[`${spentSide}Chain`] !== "solana"
    && String(draft[`${spentSide}Asset`]).toLowerCase() === NATIVE.toLowerCase()) {
    draft[`${spentSide}Asset`] = wrapped;
  }
  if (answer.quoteId) draft.quoteId = answer.quoteId;
  if (answer.bridgeQuoteId) draft.bridgeQuoteId = answer.bridgeQuoteId;
  if (answer.evm?.orderTypedData) draft.evmOrderTypedData = answer.evm.orderTypedData;
  if (answer.evm?.permitTypedData) draft.evmPermitTypedData = answer.evm.permitTypedData;
  if (answer.svm?.nonce) draft.svmNonce = answer.svm.nonce;
  if (answer.svm?.deadline) draft.svmDeadline = answer.svm.deadline;
  const pair = answer.attachedBracket;
  if (quote.attachedBracket && pair) {
    draft.attachedBracket = {
      takeProfit: quote.attachedBracket.takeProfit,
      stopLoss: quote.attachedBracket.stopLoss,
      deadline: pair.deadline,
      signedMaxFromAmount: pair.signedMaxFromAmount,
      ...(pair.salt ? { salt: pair.salt } : {}),
      ...(pair.svm?.nonce ? { svmNonce: pair.svm.nonce } : {}),
      ...(pair.evm?.permitTypedData ? { evmPermitTypedData: pair.evm.permitTypedData } : {}),
    };
  }
  return draft;
}

import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";
import { formatUnits, getAddress, isAddress, parseUnits } from "viem";
import { z } from "zod";
import { chainOf, RpcError, type EvmChain, type FetchFn } from "../lib/evm.js";
import { findToken, STABLES, type EvmToken } from "../lib/tokens.js";
import { chainTokens, resolveAnyToken, routeMids, searchTokens } from "../lib/tokenlist.js";
import {
  apiToken, plainFromApi, quoteV3Many, quoteV3TwoHop, TRADING_API, V3, v3Address, v3Approval, v3SwapTx, wrapTx,
  type PlainTx, type V3Quote,
} from "../lib/uniswap.js";

/**
 * POST /uniswap/quote and POST /uniswap/swap: "swap 0.05 eth to usdc on
 * base" from the keyboard.
 *
 * Both take {chain, sell, buy, amount} — coins as symbols ("ETH", "usdc")
 * or addresses, `amount` in whole coins of `sell` — plus `swapper` (the
 * wallet) for a swap, and an optional `slippage` in percent (0.5 unless
 * said). Both answer in one shape, whichever way the trade was routed:
 * amounts as whole-coin decimals (and base units beside them), the coins on
 * each side, and for a swap the plain transactions the phone's wallet signs
 * and sends through /evm/rpc: `approval` first when the allowance is short,
 * then `txs` in order. Routing is lib/uniswap.ts: the Trading API with
 * UNISWAP_API_KEY, Uniswap v3 on-chain without it.
 */

const Body = z.object({
  chain: z.union([z.string().min(1).max(40), z.number().int().positive()]),
  /** Where `buy` is, when it isn't `chain`: a cross-chain swap (Trading
   *  API only, routing BRIDGE). */
  buyChain: z.union([z.string().min(1).max(40), z.number().int().positive()]).optional(),
  sell: z.string().min(1).max(64).optional(),
  buy: z.string().min(1).max(64).optional(),
  tokenIn: z.string().min(1).max(64).optional(),
  tokenOut: z.string().min(1).max(64).optional(),
  amount: z.string().regex(/^\d+(\.\d+)?$/).max(40),
  swapper: z.string().refine(s => isAddress(s, { strict: false }), "swapper?").optional(),
  recipient: z.string().refine(s => isAddress(s, { strict: false }), "recipient?").optional(),
  slippage: z.number().gt(0).max(50).default(0.5),
});

/** Who a quote is for when the phone hasn't said: the Trading API wants a
 *  swapper to simulate against, and a quote moves nothing. */
const QUOTE_ONLY_SWAPPER = "0x000000000000000000000000000000000000dEaD";

interface Trade {
  chain: EvmChain;
  /** `buy`'s chain: `chain` unless the swap crosses chains. */
  buyChain: EvmChain;
  sell: EvmToken;
  buy: EvmToken;
  amountIn: bigint;
  swapper?: `0x${string}`;
  recipient?: `0x${string}`;
  slippage: number;
}

export interface UniswapDeps {
  /** UNISWAP_API_KEY unless a test passes one ("" = on-chain v3). */
  apiKey?: string;
  fetchImpl?: FetchFn;
  now?: () => number;
}

export function uniswapRoutes(app: FastifyInstance, deps: UniswapDeps = {}): void {
  const fetchImpl = deps.fetchImpl ?? fetch;
  const now = deps.now ?? Date.now;
  const apiKey = () => (deps.apiKey ?? process.env.UNISWAP_API_KEY ?? "").trim();

  async function trade(req: FastifyRequest, reply: FastifyReply, needWallet: boolean): Promise<Trade | null> {
    const parsed = Body.safeParse(req.body);
    if (!parsed.success) {
      reply.code(400).send({ ok: false, error: parsed.error.issues[0]?.message ?? "Bad request" });
      return null;
    }
    const b = parsed.data;
    const chain = chainOf(b.chain);
    const sellQ = b.sell ?? b.tokenIn;
    const buyQ = b.buy ?? b.tokenOut;
    if (!chain || !sellQ || !buyQ) {
      reply.code(400).send({ ok: false, error: "chain, sell and buy?" });
      return null;
    }
    if (!V3[chain.key]) {
      reply.code(400).send({ ok: false, error: `Uniswap isn't on ${chain.name}` });
      return null;
    }
    if (needWallet && !b.swapper) {
      reply.code(400).send({ ok: false, error: "swapper?" });
      return null;
    }
    const buyChain = b.buyChain === undefined ? chain : chainOf(b.buyChain);
    if (!buyChain || !V3[buyChain.key]) {
      reply.code(400).send({ ok: false, error: "buyChain?" });
      return null;
    }
    const crossing = buyChain.id !== chain.id;
    if (crossing && !apiKey()) {
      reply.code(400).send({ ok: false, code: "needs_key", error: "Cross-chain swaps need a Uniswap API key" });
      return null;
    }
    const [sell, buy] = await Promise.all([resolveAnyToken(fetchImpl, chain, sellQ), resolveAnyToken(fetchImpl, buyChain, buyQ)]);
    if (!sell || !buy) {
      reply.code(400).send({ ok: false, error: `Don't know ${(!sell ? sellQ : buyQ).slice(0, 20)} on ${(!sell ? chain : buyChain).name}` });
      return null;
    }
    if (!crossing && sell.address === buy.address) {
      reply.code(400).send({ ok: false, error: "That's the same coin" });
      return null;
    }
    let amountIn: bigint;
    try {
      amountIn = parseUnits(b.amount, sell.decimals);
    } catch {
      amountIn = 0n;
    }
    if (amountIn <= 0n) {
      reply.code(400).send({ ok: false, error: "amount?" });
      return null;
    }
    return { chain, buyChain, sell, buy, amountIn, slippage: b.slippage,
      ...(b.swapper ? { swapper: getAddress(b.swapper) } : {}),
      ...(b.recipient ? { recipient: getAddress(b.recipient) } : {}) };
  }

  /** The Trading API, proxy-approval mode: no Permit2 in any answer. */
  async function api(path: string, body: unknown): Promise<Record<string, any>> {
    const res = await fetchImpl(`${TRADING_API}${path}`, {
      method: "POST",
      headers: { "x-api-key": apiKey(), "content-type": "application/json", accept: "application/json",
        "x-permit2-disabled": "true" },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(15_000),
    });
    const json = await res.json().catch(() => ({})) as Record<string, any>;
    if (!res.ok) throw new ApiError(res.status, json?.detail ?? json?.message ?? json?.errorCode ?? "Uniswap couldn't quote that");
    return json;
  }

  function apiQuote(t: Trade) {
    return api("/quote", {
      type: "EXACT_INPUT",
      amount: t.amountIn.toString(),
      tokenInChainId: t.chain.id,
      tokenOutChainId: t.buyChain.id,
      tokenIn: apiToken(t.sell),
      tokenOut: apiToken(t.buy),
      swapper: t.swapper ?? QUOTE_ONLY_SWAPPER,
      ...(t.recipient ? { recipient: t.recipient } : {}),
      slippageTolerance: t.slippage,
      routingPreference: "BEST_PRICE",
      // Pools only: UniswapX orders need a Permit2 signature. A cross-chain
      // quote leaves the protocols to Uniswap (its bridge routes).
      ...(t.buyChain.id === t.chain.id ? { protocols: ["V2", "V3", "V4"] } : {}),
    });
  }

  /** What the coins on each side are worth, when it costs nothing extra
   *  (a dollar coin on either side) or one eth_call (v3, both sides priced
   *  against the chain's USDC). Missing when there's no honest number. */
  async function usd(t: Trade, amountOut: bigint, route: "api" | "v3"): Promise<{ sellUsd?: string; buyUsd?: string }> {
    const sellAmount = formatUnits(t.amountIn, t.sell.decimals);
    const buyAmount = formatUnits(amountOut, t.buy.decimals);
    if (STABLES.has(t.sell.symbol)) return { sellUsd: sellAmount, buyUsd: sellAmount };
    if (STABLES.has(t.buy.symbol)) return { sellUsd: buyAmount, buyUsd: buyAmount };
    if (t.buyChain.id !== t.chain.id) return {};
    const usdc = findToken(t.chain, "USDC");
    if (route !== "v3" || !usdc) return {};
    try {
      const [inQ, outQ] = await quoteV3Many(fetchImpl, t.chain, [
        { tokenIn: v3Address(t.chain, t.sell)!, tokenOut: usdc.address, amountIn: t.amountIn },
        { tokenIn: v3Address(t.chain, t.buy)!, tokenOut: usdc.address, amountIn: amountOut },
      ]);
      return {
        ...(inQ ? { sellUsd: formatUnits(inQ.amountOut, 6) } : {}),
        ...(outQ ? { buyUsd: formatUnits(outQ.amountOut, 6) } : {}),
      };
    } catch {
      return {};
    }
  }

  /** The one answer shape, for either route. */
  async function answer(t: Trade, a: {
    route: "api" | "v3"; amountOut: bigint; minOut?: bigint; priceImpact?: number; gasEstimate?: string;
    fee?: number; via?: `0x${string}`; txs: PlainTx[]; approval?: PlainTx; approvalReset?: PlainTx;
  }) {
    const prices = await usd(t, a.amountOut, a.route);
    const side = (token: EvmToken, price?: string) => ({ address: token.address, symbol: token.symbol,
      decimals: token.decimals, ...(token.native ? { native: true } : {}), ...(price ? { usd: price } : {}) });
    return {
      ok: true,
      route: a.route,
      chain: t.chain.key,
      chainId: t.chain.id,
      ...(t.buyChain.id !== t.chain.id ? { buyChain: t.buyChain.key, buyChainId: t.buyChain.id } : {}),
      amountIn: formatUnits(t.amountIn, t.sell.decimals),
      amountOut: formatUnits(a.amountOut, t.buy.decimals),
      amountInRaw: t.amountIn.toString(),
      amountOutRaw: a.amountOut.toString(),
      ...(a.minOut !== undefined ? { minAmountOut: formatUnits(a.minOut, t.buy.decimals) } : {}),
      sell: side(t.sell, prices.sellUsd),
      buy: side(t.buy, prices.buyUsd),
      ...prices,
      ...(a.priceImpact !== undefined ? { priceImpact: a.priceImpact } : {}),
      ...(a.gasEstimate ? { gasEstimate: a.gasEstimate } : {}),
      ...(a.fee !== undefined ? { fee: a.fee } : {}),
      ...(a.via ? { via: a.via } : {}),
      txs: a.txs,
      ...(a.approvalReset ? { approvalReset: a.approvalReset } : {}),
      ...(a.approval ? { approval: a.approval } : {}),
    };
  }

  const isWrap = (t: Trade) => t.buyChain.id === t.chain.id && ((t.sell.native && t.buy.address === v3Address(t.chain, t.sell))
    || (t.buy.native && t.sell.address === v3Address(t.chain, t.buy)));

  /** The v3 quote, or an error already sent. */
  async function v3(t: Trade, reply: FastifyReply) {
    const tokenIn = v3Address(t.chain, t.sell);
    const tokenOut = v3Address(t.chain, t.buy);
    if (!tokenIn || !tokenOut) {
      reply.code(400).send({ ok: false, error: `No wrapped ${t.chain.native} listed on ${t.chain.name}` });
      return null;
    }
    let [best]: (V3Quote | null)[] = await quoteV3Many(fetchImpl, t.chain, [{ tokenIn, tokenOut, amountIn: t.amountIn }]);
    // No pool of its own: through WETH or USDC, two pools in one swap.
    if (!best) best = await quoteV3TwoHop(fetchImpl, t.chain, { tokenIn, tokenOut, amountIn: t.amountIn }, routeMids(t.chain));
    if (!best) {
      reply.code(404).send({ ok: false, error: `No Uniswap pool for ${t.sell.symbol} and ${t.buy.symbol} on ${t.chain.name}` });
      return null;
    }
    return best;
  }

  const minOut = (out: bigint, slippage: number) => out * BigInt(10_000 - Math.round(slippage * 100)) / 10_000n;

  async function failed(req: FastifyRequest, reply: FastifyReply, err: unknown) {
    if (err instanceof ApiError && err.status >= 400 && err.status < 500 && err.status !== 401 && err.status !== 403) {
      // "No quotes available", "insufficient liquidity": Uniswap's own words.
      return reply.code(err.status === 404 ? 404 : 400).send({ ok: false, error: err.message });
    }
    if (err instanceof RpcError) return reply.code(400).send({ ok: false, error: err.message });
    req.log.warn({ err: err instanceof Error ? err.message : String(err) }, "uniswap_failed");
    return reply.code(502).send({ ok: false, error: "Uniswap didn't answer. Try again in a moment" });
  }

  /** GET /uniswap/tokens?chain=base&q=pepe (or chainId=8453): the swap
   *  panel's token picker. Common tokens first with no query; a pasted
   *  address that no list has is read from its contract. Also says whether
   *  cross-chain swaps can be quoted (they need the Trading API key). */
  app.get("/uniswap/tokens", async (req, reply) => {
    const q = req.query as { chain?: string; chainId?: string; q?: string; limit?: string };
    const chain = chainOf(q.chainId ?? q.chain ?? "base");
    if (!chain || !V3[chain.key]) return reply.code(400).send({ ok: false, error: "chain?" });
    const query = String(q.q ?? "").slice(0, 64);
    const limit = Math.min(100, Math.max(1, Number(q.limit) || 40));
    try {
      const all = await chainTokens(fetchImpl, chain);
      let rows = searchTokens(all, query, limit);
      if (rows.length === 0 && isAddress(query.trim(), { strict: false })) {
        const read = await resolveAnyToken(fetchImpl, chain, query);
        if (read) rows = [read];
      }
      return {
        ok: true, chain: chain.key, chainId: chain.id, crossChain: Boolean(apiKey()),
        tokens: rows.map(t => ({ symbol: t.symbol, name: t.name, address: t.address, decimals: t.decimals,
          ...(t.native ? { native: true } : {}), ...("logoURI" in t && t.logoURI ? { logoURI: t.logoURI } : {}) })),
      };
    } catch (err) {
      return failed(req, reply, err);
    }
  });

  app.post("/uniswap/quote", async (req, reply) => {
    const t = await trade(req, reply, false);
    if (!t) return reply;
    try {
      if (apiKey()) {
        const q = await apiQuote(t);
        req.log.info({ chain: t.chain.key, route: "api", routing: q.routing }, "uniswap_quote");
        return answer(t, { route: "api", amountOut: BigInt(q.quote?.output?.amount ?? 0),
          ...(q.quote?.output?.minimumAmount ? { minOut: BigInt(q.quote.output.minimumAmount) } : {}),
          ...(typeof q.quote?.priceImpact === "number" ? { priceImpact: q.quote.priceImpact } : {}),
          ...(q.quote?.gasUseEstimate ? { gasEstimate: String(q.quote.gasUseEstimate) } : {}),
          txs: [] });
      }
      if (isWrap(t)) return answer(t, { route: "v3", amountOut: t.amountIn, minOut: t.amountIn, txs: [] });
      const best = await v3(t, reply);
      if (!best) return reply;
      req.log.info({ chain: t.chain.key, route: "v3", fee: best.fee, hops: best.via ? 2 : 1 }, "uniswap_quote");
      return answer(t, { route: "v3", amountOut: best.amountOut, minOut: minOut(best.amountOut, t.slippage),
        gasEstimate: best.gasEstimate.toString(), fee: best.fee, via: best.via, txs: [] });
    } catch (err) {
      return failed(req, reply, err);
    }
  });

  app.post("/uniswap/swap", async (req, reply) => {
    const t = await trade(req, reply, true);
    if (!t) return reply;
    const swapper = t.swapper!;
    try {
      if (apiKey()) {
        const [approval, q] = await Promise.all([
          t.sell.native ? null : api("/check_approval", { walletAddress: swapper, token: t.sell.address,
            amount: t.amountIn.toString(), chainId: t.chain.id }),
          apiQuote(t),
        ]);
        // BRIDGE: Uniswap's cross-chain route, still one plain transaction.
        if (!["CLASSIC", "WRAP", "UNWRAP", "BRIDGE"].includes(q.routing)) {
          return reply.code(400).send({ ok: false, error: "Uniswap offered a route this wallet can't send" });
        }
        const built = await api("/swap", { quote: q.quote });
        const tx = plainFromApi(built.swap, t.chain.id);
        if (!tx) return reply.code(502).send({ ok: false, error: "Uniswap sent back an empty swap" });
        const approve = approval?.approval ? plainFromApi(approval.approval, t.chain.id) : null;
        const reset = approval?.cancel ? plainFromApi(approval.cancel, t.chain.id) : null;
        req.log.info({ chain: t.chain.key, route: "api", routing: q.routing, approve: Boolean(approve) }, "uniswap_swap");
        return answer(t, { route: "api", amountOut: BigInt(q.quote?.output?.amount ?? 0),
          ...(q.quote?.output?.minimumAmount ? { minOut: BigInt(q.quote.output.minimumAmount) } : {}),
          ...(typeof q.quote?.priceImpact === "number" ? { priceImpact: q.quote.priceImpact } : {}),
          ...(q.quote?.gasUseEstimate ? { gasEstimate: String(q.quote.gasUseEstimate) } : {}),
          txs: [tx], ...(approve ? { approval: approve } : {}), ...(reset ? { approvalReset: reset } : {}) });
      }
      if (isWrap(t)) {
        return answer(t, { route: "v3", amountOut: t.amountIn, minOut: t.amountIn, txs: [wrapTx(t.chain, t.sell, t.amountIn)] });
      }
      const best = await v3(t, reply);
      if (!best) return reply;
      const approvals = await v3Approval(fetchImpl, t.chain, t.sell, swapper, t.amountIn);
      const min = minOut(best.amountOut, t.slippage);
      const deadline = BigInt(Math.floor(now() / 1000) + 20 * 60);
      const tx = v3SwapTx(t.chain, { sell: t.sell, buy: t.buy, amountIn: t.amountIn, minOut: min, fee: best.fee,
        recipient: t.recipient ?? swapper, deadline, ...(best.via && best.fees ? { via: best.via, fees: best.fees } : {}) });
      req.log.info({ chain: t.chain.key, route: "v3", fee: best.fee, approve: Boolean(approvals.approval) }, "uniswap_swap");
      return answer(t, { route: "v3", amountOut: best.amountOut, minOut: min, gasEstimate: best.gasEstimate.toString(),
        fee: best.fee, via: best.via, txs: [tx], ...approvals });
    } catch (err) {
      return failed(req, reply, err);
    }
  });
}

class ApiError extends Error {
  constructor(readonly status: number, message: string) {
    super(message);
  }
}

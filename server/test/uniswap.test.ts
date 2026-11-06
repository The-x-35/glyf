import Fastify from "fastify";
import { decodeFunctionData, encodeFunctionResult, getAddress, toFunctionSelector, type Hex } from "viem";
import { describe, expect, it } from "vitest";
import { ERC20_ABI } from "../src/lib/tokens.js";
import { MULTICALL3, MULTICALL3_ABI, QUOTER_ABI, QUOTER_PATH_ABI, ROUTER_ABI, TRADING_API, V3 } from "../src/lib/uniswap.js";
import { uniswapRoutes } from "../src/routes/uniswap.js";
import { resetTokenList, searchTokens, TOKEN_LIST_URL } from "../src/lib/tokenlist.js";
import { v3Path } from "../src/lib/uniswap.js";

const SWAPPER = getAddress("0x1111111111111111111111111111111111111111");
const WETH = getAddress("0x4200000000000000000000000000000000000006");
const USDC = getAddress("0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913");
const CBBTC = getAddress("0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf");
const NOW = 1_800_000_000_000;
/** PEPE on Base, from Uniswap's default list; priced at $0.00001. */
const PEPE = getAddress("0xB4fDe59a779991bfB6a52253B51947828b982be3");
/** Pairs with no pool of their own (sorted addresses joined). */
const NO_DIRECT = new Set([[PEPE, USDC].sort().join(), [CBBTC, PEPE].sort().join(), [PEPE, WETH].sort().join()]);
const LIST = { name: "Uniswap Labs Default", tokens: [
  { chainId: 8453, address: PEPE, name: "Pepe", symbol: "PEPE", decimals: 18, logoURI: "https://example.org/pepe.png" },
  { chainId: 8453, address: USDC, name: "USD Coin", symbol: "USDC", decimals: 6, logoURI: "https://example.org/usdc.png" },
  { chainId: 8453, address: "0x4ed4E862860beD51a9570b96d89aF5E1B0Efefed", name: "Degen", symbol: "DEGEN", decimals: 18 },
  { chainId: 1, address: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2", name: "Wrapped Ether", symbol: "WETH", decimals: 18, logoURI: "https://example.org/weth.png" },
  { chainId: 8453, address: "not-an-address", name: "Junk", symbol: "JUNK", decimals: 18 },
  { chainId: 42161, address: "0x35E6A59F786d9266c7961eA28c7b768B33959cbB", name: "Pepe", symbol: "PEPE", decimals: 18 },
] };

/** ETH at $3,000, BTC at $90,000, every pool on the 0.05% tier only. */
function priced(tokenIn: string, tokenOut: string, amountIn: bigint): bigint | null {
  // Dollars per whole token, in millionths.
  const usdPerUnit: Record<string, [bigint, number]> = { [WETH]: [3_000_000_000n, 18], [USDC]: [1_000_000n, 6],
    [CBBTC]: [90_000_000_000n, 8], [PEPE]: [10n, 18] };
  const a = usdPerUnit[getAddress(tokenIn)];
  const b = usdPerUnit[getAddress(tokenOut)];
  if (!a || !b) return null;
  return amountIn * a[0] * 10n ** BigInt(b[1]) / (b[0] * 10n ** BigInt(a[1]));
}

const PATH_SELECTOR = toFunctionSelector(QUOTER_PATH_ABI[0]);

/** Two pools: each leg priced like a single pool, 0.05% tier only. */
function pathQuote(callData: Hex): { success: boolean; returnData: Hex } {
  const q = decodeFunctionData({ abi: QUOTER_PATH_ABI, data: callData });
  const [path, amountIn] = q.args;
  const hex = path.slice(2);
  const a = getAddress(`0x${hex.slice(0, 40)}`);
  const fee1 = parseInt(hex.slice(40, 46), 16);
  const mid = getAddress(`0x${hex.slice(46, 86)}`);
  const fee2 = parseInt(hex.slice(86, 92), 16);
  const b = getAddress(`0x${hex.slice(92, 132)}`);
  const first = fee1 === 500 ? priced(a, mid, amountIn) : null;
  const out = first !== null && fee2 === 500 ? priced(mid, b, first) : null;
  if (out === null) return { success: false, returnData: "0x" };
  return { success: true, returnData: encodeFunctionResult({ abi: QUOTER_PATH_ABI, functionName: "quoteExactInput",
    result: [out, [], [], 180_000n] }) };
}

/** A stand-in Base node: Multicall3 over QuoterV2, and token allowances. */
function fakeBase(allowance = 0n, opts: { list?: object; apiKey?: string } = {}) {
  const calls: { method: string; to?: string }[] = [];
  const fetchImpl = (async (url: string, init: RequestInit) => {
    if (String(url) === TOKEN_LIST_URL) {
      calls.push({ method: "tokenlist" });
      if (!opts.list) return new Response("nope", { status: 503 });
      return new Response(JSON.stringify(opts.list), { headers: { "content-type": "application/json" } });
    }
    const { method, params } = JSON.parse(String(init.body));
    const { to, data } = (params[0] ?? {}) as { to: string; data: Hex };
    calls.push({ method, to });
    let result: Hex = "0x";
    if (getAddress(to) === MULTICALL3) {
      const { args } = decodeFunctionData({ abi: MULTICALL3_ABI, data });
      const results = args[0].map(call => {
        if (call.callData.startsWith(PATH_SELECTOR)) return pathQuote(call.callData);
        const q = decodeFunctionData({ abi: QUOTER_ABI, data: call.callData });
        const p = q.args[0];
        const out = p.fee === 500 && !NO_DIRECT.has([p.tokenIn, p.tokenOut].map(x => getAddress(x)).sort().join())
          ? priced(p.tokenIn, p.tokenOut, p.amountIn) : null;
        if (out === null) return { success: false, returnData: "0x" as Hex };
        return { success: true, returnData: encodeFunctionResult({ abi: QUOTER_ABI, functionName: "quoteExactInputSingle",
          result: [out, 0n, 1, 90_000n] }) };
      });
      result = encodeFunctionResult({ abi: MULTICALL3_ABI, functionName: "aggregate3", result: results });
    } else {
      const call = decodeFunctionData({ abi: ERC20_ABI, data });
      if (call.functionName === "allowance") {
        expect(call.args).toEqual([SWAPPER, V3.base.swapRouter02]);
        result = encodeFunctionResult({ abi: ERC20_ABI, functionName: "allowance", result: allowance });
      }
    }
    return new Response(JSON.stringify({ jsonrpc: "2.0", id: 1, result }), { headers: { "content-type": "application/json" } });
  }) as unknown as typeof fetch;
  const app = Fastify();
  uniswapRoutes(app, { apiKey: opts.apiKey ?? "", fetchImpl, now: () => NOW });
  return { app, calls };
}

describe("Uniswap v3, no API key", () => {
  it("quotes 0.05 ETH to USDC on Base over the fee tiers and picks the one that fills", async () => {
    const { app, calls } = fakeBase();
    const res = await app.inject({ method: "POST", url: "/uniswap/quote",
      payload: { chain: "base", sell: "ETH", buy: "usdc", amount: "0.05" } });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({
      ok: true, route: "v3", chainId: 8453, amountIn: "0.05", amountOut: "150", amountOutRaw: "150000000",
      minAmountOut: "149.25", fee: 500, gasEstimate: "90000", txs: [],
      sell: { symbol: "ETH", decimals: 18, native: true, usd: "150" },
      buy: { symbol: "USDC", address: USDC, decimals: 6, usd: "150" },
      sellUsd: "150", buyUsd: "150",
    });
    // Four tiers, one eth_call.
    expect(calls).toHaveLength(1);
  });

  it("prices both sides against USDC when neither is a dollar coin", async () => {
    const { app, calls } = fakeBase();
    const res = await app.inject({ method: "POST", url: "/uniswap/quote",
      payload: { chain: "base", sell: "eth", buy: "btc", amount: "3" } });
    expect(res.json()).toMatchObject({ amountOut: "0.1", buy: { symbol: "cbBTC" }, sellUsd: "9000", buyUsd: "9000" });
    expect(calls).toHaveLength(2);
  });

  it("builds SwapRouter02 calldata: ETH in rides as value", async () => {
    const { app } = fakeBase();
    const res = await app.inject({ method: "POST", url: "/uniswap/swap",
      payload: { chain: "base", sell: "ETH", buy: "USDC", amount: "0.05", swapper: SWAPPER.toLowerCase(), slippage: 1 } });
    const body = res.json();
    expect(body).not.toHaveProperty("approval");
    expect(body.txs).toHaveLength(1);
    const [tx] = body.txs;
    expect(tx).toMatchObject({ to: V3.base.swapRouter02, value: "50000000000000000", chainId: 8453 });
    const outer = decodeFunctionData({ abi: ROUTER_ABI, data: tx.data });
    expect(outer.functionName).toBe("multicall");
    const [deadline, steps] = outer.args as [bigint, Hex[]];
    expect(deadline).toBe(BigInt(NOW / 1000 + 1200));
    const swap = decodeFunctionData({ abi: ROUTER_ABI, data: steps[0] });
    expect(swap.args[0]).toEqual({ tokenIn: WETH, tokenOut: USDC, fee: 500, recipient: SWAPPER,
      amountIn: 50_000_000_000_000_000n, amountOutMinimum: 148_500_000n, sqrtPriceLimitX96: 0n });
  });

  it("selling for ETH swaps to the router and unwraps, after an exact approve", async () => {
    const { app } = fakeBase(1n);
    const res = await app.inject({ method: "POST", url: "/uniswap/swap",
      payload: { chain: "base", sell: "USDC", buy: "ETH", amount: "300", swapper: SWAPPER } });
    const body = res.json();
    expect(body.amountOut).toBe("0.1");
    expect(body.approval).toMatchObject({ to: USDC, value: "0", chainId: 8453 });
    const approve = decodeFunctionData({ abi: ERC20_ABI, data: body.approval.data });
    expect(approve.args).toEqual([V3.base.swapRouter02, 300_000_000n]);
    const [, steps] = decodeFunctionData({ abi: ROUTER_ABI, data: body.txs[0].data }).args as [bigint, Hex[]];
    const swap = decodeFunctionData({ abi: ROUTER_ABI, data: steps[0] });
    expect((swap.args[0] as { recipient: string }).recipient).toBe("0x0000000000000000000000000000000000000002");
    const unwrap = decodeFunctionData({ abi: ROUTER_ABI, data: steps[1] });
    expect(unwrap.functionName).toBe("unwrapWETH9");
    expect(unwrap.args).toEqual([99_500_000_000_000_000n, SWAPPER]);
    expect(body.txs[0].value).toBe("0");
  });

  it("skips the approve when the allowance already covers it", async () => {
    const { app } = fakeBase(10n ** 30n);
    const res = await app.inject({ method: "POST", url: "/uniswap/swap",
      payload: { chain: "base", sell: "USDC", buy: "WETH", amount: "300", swapper: SWAPPER } });
    expect(res.json()).not.toHaveProperty("approval");
  });

  it("ETH to WETH is WETH's own deposit", async () => {
    const { app, calls } = fakeBase();
    const res = await app.inject({ method: "POST", url: "/uniswap/swap",
      payload: { chain: "base", sell: "ETH", buy: "WETH", amount: "1", swapper: SWAPPER } });
    expect(res.json().txs[0]).toEqual({ to: WETH, data: "0xd0e30db0", value: "1000000000000000000", chainId: 8453 });
    expect(res.json()).toMatchObject({ amountOut: "1", sellUsd: "3000", buyUsd: "3000" });
    // No quote and no allowance: the one call prices it.
    expect(calls.map(c => c.to && getAddress(c.to))).toEqual([MULTICALL3]);
  });

  it("says no pool, no chain, no coin and no wallet plainly", async () => {
    const { app } = fakeBase();
    const ask = (payload: object, url = "/uniswap/quote") => app.inject({ method: "POST", url, payload });
    expect((await ask({ chain: "base", sell: "LINK", buy: "DAI", amount: "1" })).statusCode).toBe(404);
    expect((await ask({ chain: "whitechain", sell: "WBT", buy: "USDT", amount: "1" })).json().error).toMatch(/isn't on Whitechain/);
    expect((await ask({ chain: "base", sell: "ETH", buy: "DOGE", amount: "1" })).statusCode).toBe(400);
    expect((await ask({ chain: "base", sell: "ETH", buy: "USDC", amount: "0" })).statusCode).toBe(400);
    expect((await ask({ chain: "base", sell: "ETH", buy: "USDC", amount: "1" }, "/uniswap/swap")).json().error).toBe("swapper?");
  });
});

describe("Uniswap Trading API, with a key", () => {
  function setup(routing = "CLASSIC") {
    const calls: { url: string; headers: Record<string, string>; body: any }[] = [];
    const fetchImpl = (async (url: string, init: RequestInit) => {
      const body = JSON.parse(String(init.body));
      calls.push({ url: String(url), headers: init.headers as Record<string, string>, body });
      const path = String(url).slice(TRADING_API.length);
      const json = path === "/check_approval"
        ? { requestId: "a", approval: { to: USDC, from: SWAPPER, data: "0x095ea7b3ff", value: "0", chainId: 8453 }, cancel: null }
        : path === "/quote"
          ? { requestId: "q", routing, permitData: null, quote: { chainId: 8453, input: { amount: body.amount, token: body.tokenIn },
            output: { amount: "16666666666666666", token: body.tokenOut, minimumAmount: "16583333333333333" },
            priceImpact: 0.02, gasUseEstimate: "120000", quoteId: "uq-1" } }
          : { requestId: "s", swap: { to: "0x0000000085E102724e78eCd2F45DC9cA239Affad", from: SWAPPER,
            data: "0x3593564c00", value: "0x0", chainId: 8453, gasLimit: "210000" } };
      return new Response(JSON.stringify(json), { headers: { "content-type": "application/json" } });
    }) as unknown as typeof fetch;
    const app = Fastify();
    uniswapRoutes(app, { apiKey: "uni-key", fetchImpl });
    return { app, calls };
  }

  it("quotes through the API in proxy-approval mode, same answer shape", async () => {
    const { app, calls } = setup();
    const res = await app.inject({ method: "POST", url: "/uniswap/quote",
      payload: { chain: "base", sell: "USDC", buy: "ETH", amount: "50" } });
    expect(res.json()).toMatchObject({ ok: true, route: "api", amountIn: "50", amountOut: "0.016666666666666666",
      priceImpact: 0.02, gasEstimate: "120000", sellUsd: "50", buyUsd: "50", txs: [] });
    expect(calls[0].headers).toMatchObject({ "x-api-key": "uni-key", "x-permit2-disabled": "true" });
    expect(calls[0].body).toMatchObject({ type: "EXACT_INPUT", amount: "50000000", tokenInChainId: 8453,
      tokenIn: USDC, tokenOut: "0x0000000000000000000000000000000000000000", protocols: ["V2", "V3", "V4"] });
    expect(res.body).not.toContain("uni-key");
  });

  it("checks the approval, quotes, and builds plain transactions", async () => {
    const { app, calls } = setup();
    const res = await app.inject({ method: "POST", url: "/uniswap/swap",
      payload: { chain: "base", sell: "USDC", buy: "ETH", amount: "50", swapper: SWAPPER } });
    const body = res.json();
    expect(calls.map(c => c.url.slice(TRADING_API.length)).sort()).toEqual(["/check_approval", "/quote", "/swap"]);
    expect(calls.find(c => c.url.endsWith("/swap"))?.body).toEqual({ quote: expect.objectContaining({ quoteId: "uq-1" }) });
    expect(body.approval).toEqual({ to: USDC, data: "0x095ea7b3ff", value: "0", chainId: 8453 });
    expect(body.txs).toEqual([{ to: "0x0000000085E102724e78eCd2F45DC9cA239Affad", data: "0x3593564c00", value: "0",
      chainId: 8453, gas: "210000" }]);
    expect(body.minAmountOut).toBe("0.016583333333333333");
  });

  it("refuses a route the phone's wallet can't send", async () => {
    const { app } = setup("DUTCH_V2");
    const res = await app.inject({ method: "POST", url: "/uniswap/swap",
      payload: { chain: "base", sell: "USDC", buy: "ETH", amount: "50", swapper: SWAPPER } });
    expect(res.statusCode).toBe(400);
  });
});

describe("Any token to any token", () => {
  it("lists Base's tokens for the picker: common first, logos, search, a pasted address", async () => {
    resetTokenList();
    const { app, calls } = fakeBase(0n, { list: LIST });
    const res = await app.inject({ method: "GET", url: "/uniswap/tokens?chainId=8453" });
    const body = res.json();
    expect(body).toMatchObject({ ok: true, chain: "base", chainId: 8453, crossChain: false });
    const symbols = body.tokens.map((t: { symbol: string }) => t.symbol);
    expect(symbols.slice(0, 3)).toEqual(["ETH", "USDC", "WETH"]);
    expect(symbols).toContain("PEPE");
    expect(symbols).not.toContain("JUNK");
    expect(body.tokens[0]).toMatchObject({ native: true, logoURI: "https://example.org/weth.png" });
    expect(body.tokens.find((t: { symbol: string }) => t.symbol === "USDC").logoURI).toBe("https://example.org/usdc.png");
    // One fetch of the list, then the cache.
    await app.inject({ method: "GET", url: "/uniswap/tokens?chain=base&q=pe" });
    expect(calls.filter(c => c.method === "tokenlist")).toHaveLength(1);
    const pe = (await app.inject({ method: "GET", url: "/uniswap/tokens?chain=base&q=pe" })).json();
    expect(pe.tokens[0].symbol).toBe("PEPE");
    const byAddress = (await app.inject({ method: "GET", url: `/uniswap/tokens?chain=base&q=${PEPE.toLowerCase()}` })).json();
    expect(byAddress.tokens).toHaveLength(1);
    expect(byAddress.tokens[0]).toMatchObject({ symbol: "PEPE", decimals: 18 });
    expect((await app.inject({ method: "GET", url: "/uniswap/tokens?chain=whitechain" })).statusCode).toBe(400);
  });

  it("reads a pasted address no list has from its contract", async () => {
    resetTokenList();
    const unknown = "0x9999999999999999999999999999999999999999";
    const fetchImpl = (async (url: string, init: RequestInit) => {
      if (String(url) === TOKEN_LIST_URL) return new Response(JSON.stringify(LIST));
      const { params } = JSON.parse(String(init.body));
      const call = decodeFunctionData({ abi: ERC20_ABI, data: params[0].data });
      const result = call.functionName === "symbol" ? encodeFunctionResult({ abi: ERC20_ABI, functionName: "symbol", result: "ZORA" })
        : call.functionName === "name" ? encodeFunctionResult({ abi: ERC20_ABI, functionName: "name", result: "Zora" })
          : encodeFunctionResult({ abi: ERC20_ABI, functionName: "decimals", result: 18 });
      return new Response(JSON.stringify({ jsonrpc: "2.0", id: 1, result }));
    }) as unknown as typeof fetch;
    const app = Fastify();
    uniswapRoutes(app, { apiKey: "", fetchImpl });
    const res = (await app.inject({ method: "GET", url: `/uniswap/tokens?chain=base&q=${unknown}` })).json();
    expect(res.tokens).toEqual([{ symbol: "ZORA", name: "Zora", address: getAddress(unknown), decimals: 18 }]);
  });

  it("still serves the issuers' tokens when the list can't be fetched", async () => {
    resetTokenList();
    const { app } = fakeBase(0n);
    const res = (await app.inject({ method: "GET", url: "/uniswap/tokens?chain=base" })).json();
    expect(res.tokens.map((t: { symbol: string }) => t.symbol).slice(0, 2)).toEqual(["ETH", "USDC"]);
  });

  it("searches exact symbol, then prefix, then name", () => {
    const row = (symbol: string, name: string) => ({ symbol, name, address: WETH, decimals: 18 });
    const all = [row("XPEPE", "x"), row("PEPE", "Pepe"), row("PEPECOIN", "p"), row("FROG", "Pepe's friend")];
    expect(searchTokens(all, "pepe").map(t => t.symbol)).toEqual(["PEPE", "PEPECOIN", "FROG", "XPEPE"]);
    expect(searchTokens(all, "$pepe")[0].symbol).toBe("PEPE");
    expect(searchTokens(all, "zzz")).toEqual([]);
  });

  it("packs a v3 path: token, 3-byte fee, token, fee, token", () => {
    expect(v3Path([PEPE, WETH, USDC], [3000, 500])).toBe(
      `0x${PEPE.slice(2).toLowerCase()}000bb8${WETH.slice(2).toLowerCase()}0001f4${USDC.slice(2).toLowerCase()}`);
  });

  it("swaps ETH to PEPE by symbol through two pools when there's no direct pool", async () => {
    resetTokenList();
    const { app } = fakeBase(0n, { list: LIST });
    const q = await app.inject({ method: "POST", url: "/uniswap/quote",
      payload: { chain: "base", sell: "usdc", buy: "pepe", amount: "10" } });
    expect(q.statusCode).toBe(200);
    // 10 USDC → WETH → PEPE at $0.00001: about one million PEPE.
    expect(q.json()).toMatchObject({ ok: true, route: "v3", via: WETH, buy: { symbol: "PEPE", address: PEPE } });
    expect(Math.round(Number(q.json().amountOut))).toBe(1_000_000);
    const s = await app.inject({ method: "POST", url: "/uniswap/swap",
      payload: { chain: "base", sell: "USDC", buy: "PEPE", amount: "10", swapper: SWAPPER } });
    const body = s.json();
    // Exact-amount approve, then exactInput over USDC → WETH → PEPE.
    expect(decodeFunctionData({ abi: ERC20_ABI, data: body.approval.data }).args).toEqual([V3.base.swapRouter02, 10_000_000n]);
    const outer = decodeFunctionData({ abi: ROUTER_ABI, data: body.txs[0].data });
    expect(outer.functionName).toBe("multicall");
    const inner = decodeFunctionData({ abi: ROUTER_ABI, data: (outer.args[1] as Hex[])[0] });
    expect(inner.functionName).toBe("exactInput");
    expect(inner.args[0]).toMatchObject({ path: v3Path([USDC, WETH, PEPE], [500, 500]), recipient: SWAPPER, amountIn: 10_000_000n });
  });
});

describe("Cross-chain swaps", () => {
  it("say they need a Uniswap API key when there is none", async () => {
    resetTokenList();
    const { app, calls } = fakeBase(0n, { list: LIST });
    const res = await app.inject({ method: "POST", url: "/uniswap/quote",
      payload: { chain: "base", buyChain: "arbitrum", sell: "USDC", buy: "ETH", amount: "50" } });
    expect(res.statusCode).toBe(400);
    expect(res.json()).toEqual({ ok: false, code: "needs_key", error: "Cross-chain swaps need a Uniswap API key" });
    expect(calls).toHaveLength(0);
  });

  it("quote through the Trading API with the out chain's id and send BRIDGE as a plain transaction", async () => {
    const calls: { url: string; body: any }[] = [];
    const fetchImpl = (async (url: string, init: RequestInit) => {
      const body = JSON.parse(String(init.body));
      calls.push({ url: String(url), body });
      const path = String(url).slice(TRADING_API.length);
      const json = path === "/check_approval" ? { approval: null, cancel: null }
        : path === "/quote" ? { routing: "BRIDGE", quote: { output: { amount: "49900000" }, quoteId: "b-1" } }
          : { swap: { to: "0x09aea4b2242abC8bb4BB78D537A67a245A7bEC64", data: "0xad5425c600", value: "0", chainId: 8453 } };
      return new Response(JSON.stringify(json));
    }) as unknown as typeof fetch;
    const app = Fastify();
    uniswapRoutes(app, { apiKey: "uni-key", fetchImpl });
    const q = await app.inject({ method: "POST", url: "/uniswap/quote",
      payload: { chain: "base", buyChain: "arbitrum", sell: "USDC", buy: "USDC", amount: "50" } });
    expect(q.json()).toMatchObject({ ok: true, route: "api", chain: "base", buyChain: "arbitrum", buyChainId: 42161, amountOut: "49.9" });
    expect(calls[0].body).toMatchObject({ tokenInChainId: 8453, tokenOutChainId: 42161,
      tokenOut: "0xaf88d065e77c8cC2239327C5EDb3A432268e5831" });
    expect(calls[0].body.protocols).toBeUndefined();
    const s = await app.inject({ method: "POST", url: "/uniswap/swap",
      payload: { chain: "base", buyChain: "arbitrum", sell: "USDC", buy: "USDC", amount: "50", swapper: SWAPPER } });
    expect(s.json().txs).toEqual([{ to: "0x09aea4b2242abC8bb4BB78D537A67a245A7bEC64", data: "0xad5425c600", value: "0", chainId: 8453 }]);
  });
});

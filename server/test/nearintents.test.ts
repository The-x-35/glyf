import Fastify from "fastify";
import { decodeFunctionData, getAddress, parseAbi } from "viem";
import { describe, expect, it } from "vitest";
import type { NearLookup } from "../src/lib/names.js";
import {
  addressFits, depositFor, EXPLORER, NEAR_CHAINS, nearChainOf, NearIntents, ONECLICK, pickToken, statusOf,
  type IntentToken,
} from "../src/lib/nearintents.js";
import { nearRoutes } from "../src/routes/near.js";

const NOW = Date.parse("2026-11-13T00:00:00Z");
const BASE_USDC = "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913";
const DEPOSIT = "0x76b4c56085ED136a8744D52bE956396624a730E8";
const MINE = "0x1111111111111111111111111111111111111111";
const PHANTOM = "7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU";

/** A slice of 1Click's /v0/tokens, as it answered on 2026-11-12. */
const TOKENS: IntentToken[] = [
  { assetId: `nep141:base-${BASE_USDC}.omft.near`, decimals: 6, blockchain: "base", symbol: "USDC", price: 1, contractAddress: BASE_USDC },
  { assetId: "nep141:base.omft.near", decimals: 18, blockchain: "base", symbol: "ETH", price: 2000 },
  { assetId: "nep141:sol.omft.near", decimals: 9, blockchain: "sol", symbol: "SOL", price: 80 },
  { assetId: "nep141:sol-5ce3bf3a31af18be40ba30f721101b4341690186.omft.near", decimals: 6, blockchain: "sol", symbol: "USDC",
    price: 1, contractAddress: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v" },
  { assetId: "1cs_v1:sol:spl:A7bdiYdS5GjqGFtxf17ppRHtDKPkkRqbKtR27dxvQXaS", decimals: 8, blockchain: "sol", symbol: "ZEC",
    price: 900, contractAddress: "A7bdiYdS5GjqGFtxf17ppRHtDKPkkRqbKtR27dxvQXaS" },
  { assetId: "nep141:wrap.near", decimals: 24, blockchain: "near", symbol: "wNEAR", price: 3.4, contractAddress: "wrap.near" },
  { assetId: "nep141:17208628f84f5d6ad33f0da3bbbeb27ffcb398eac501a31bd6ad2011e36133a1", decimals: 6, blockchain: "near",
    symbol: "USDC", price: 1, contractAddress: "17208628f84f5d6ad33f0da3bbbeb27ffcb398eac501a31bd6ad2011e36133a1" },
  { assetId: "1cs_v1:btc:native:coin", decimals: 8, blockchain: "btc", symbol: "BTC", price: 72000 },
  { assetId: "nep141:btc.omft.near", decimals: 8, blockchain: "btc", symbol: "BTC", price: 72000 },
  { assetId: "nep245:v2_1.omni.hot.tg:56_11111111111111111111", decimals: 18, blockchain: "bsc", symbol: "BNB(DEPRECATED)" },
  { assetId: "nep141:bnb.omdep.near", decimals: 18, blockchain: "bsc", symbol: "BNB", price: 600 },
  { assetId: "nep141:zec.omft.near", decimals: 8, blockchain: "zec", symbol: "ZEC", price: 900 },
];

type Call = { url: string; method: string; body?: any; auth?: string };

/** A stand-in 1Click: the token list, quotes priced from TOKENS, statuses. */
function fake1Click(opts: { quote?: (body: any) => Response; status?: (q: URLSearchParams) => Response } = {}) {
  const calls: Call[] = [];
  const fetchImpl = (async (url: string, init: RequestInit = {}) => {
    const u = new URL(String(url));
    const headers = (init.headers ?? {}) as Record<string, string>;
    const body = init.body ? JSON.parse(String(init.body)) : undefined;
    calls.push({ url: String(url), method: init.method ?? "GET", body, auth: headers.authorization });
    const ok = (json: unknown) => new Response(JSON.stringify(json), { headers: { "content-type": "application/json" } });
    if (u.origin !== ONECLICK) throw new Error(`unexpected ${url}`);
    if (u.pathname === "/v0/tokens") return ok(TOKENS);
    if (u.pathname === "/v0/quote") {
      if (opts.quote) return opts.quote(body);
      const sell = TOKENS.find(t => t.assetId === body.originAsset)!;
      const buy = TOKENS.find(t => t.assetId === body.destinationAsset)!;
      const rate = sell.price! / buy.price!;
      const scale = (n: bigint, from: number, to: number) => n * 10n ** BigInt(to) / 10n ** BigInt(from);
      const amount = BigInt(body.amount);
      const fx = (n: bigint, r: number) => BigInt(Math.round(Number(n) * r));
      const [amountIn, amountOut] = body.swapType === "EXACT_INPUT"
        ? [amount, fx(scale(amount, sell.decimals, buy.decimals), rate * 0.99)]
        : [fx(scale(amount, buy.decimals, sell.decimals), 1.01 / rate), amount];
      return ok({ quote: {
        amountIn: amountIn.toString(), amountInFormatted: "x", amountInUsd: "19.991420000000", minAmountIn: amountIn.toString(),
        amountOut: amountOut.toString(), amountOutFormatted: "x", amountOutUsd: "19.880000000000",
        minAmountOut: (amountOut * 99n / 100n).toString(), timeEstimate: 32,
        ...(body.dry ? {} : { depositAddress: body.originAsset.startsWith("nep141:sol") ? "Dep0sitSo1anaAddre55xxxxxxxxxxxxxxxxxxxxxx1" : DEPOSIT,
          deadline: "2026-11-14T00:00:00.000Z" }),
      }, quoteRequest: body, signature: "ed25519:x", timestamp: "2026-11-13T00:00:00Z", correlationId: "c" });
    }
    if (u.pathname === "/v0/status") {
      if (opts.status) return opts.status(u.searchParams);
      return new Response(JSON.stringify({ message: "Deposit address not found" }), { status: 404 });
    }
    if (u.pathname === "/v0/deposit/submit") return ok({ correlationId: "c", status: "KNOWN_DEPOSIT_TX" });
    throw new Error(`unexpected ${url}`);
  }) as unknown as typeof fetch;
  return { calls, fetchImpl };
}

const fakeNear = (accounts: string[]): NearLookup => ({ exists: async a => accounts.includes(a) });

function intents(opts: Parameters<typeof fake1Click>[0] = {}, jwt = "") {
  const f = fake1Click(opts);
  return { ...f, n: new NearIntents({ fetchImpl: f.fetchImpl, jwt: () => jwt, now: () => NOW }) };
}

describe("NEAR Intents chains, addresses and tokens", () => {
  it("knows each chain by Glyf's word, a nickname or 1Click's code", () => {
    expect(nearChainOf("solana")?.oneClick).toBe("sol");
    expect(nearChainOf("SOL")?.key).toBe("solana");
    expect(nearChainOf("btc")?.key).toBe("bitcoin");
    expect(nearChainOf("arb")?.chainId).toBe(42161);
    expect(nearChainOf("doge")?.oneClick).toBe("doge");
    expect(nearChainOf("eth")?.key).toBe("ethereum");
    expect(nearChainOf("unichain")).toBeNull();
    expect(Object.keys(NEAR_CHAINS)).toHaveLength(21);
  });

  it("tells each chain's addresses apart by shape", () => {
    expect(addressFits(NEAR_CHAINS.base, MINE)).toBe(true);
    expect(addressFits(NEAR_CHAINS.solana, PHANTOM)).toBe(true);
    expect(addressFits(NEAR_CHAINS.solana, MINE)).toBe(false);
    expect(addressFits(NEAR_CHAINS.near, "alice.near")).toBe(true);
    expect(addressFits(NEAR_CHAINS.near, "98793cd91a3f870fb126f66285808c7e094afcfc4eda8a970f6648cdf0dbd6de")).toBe(true);
    expect(addressFits(NEAR_CHAINS.near, "Alice.near")).toBe(false);
    expect(addressFits(NEAR_CHAINS.bitcoin, "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh")).toBe(true);
    expect(addressFits(NEAR_CHAINS.bitcoin, MINE)).toBe(false);
    expect(addressFits(NEAR_CHAINS.zcash, "t1Hsc1LR8yKnbbe3twRp88p6vFfC5t7DLbs")).toBe(true);
    expect(addressFits(NEAR_CHAINS.zcash, "zs1z7rejlpsa98s2rrrfkwmaxu53e4ue0ulcrw0h4x5g8jl04tak0d3mm47vdtahatqrlkngh9sly")).toBe(false);
    // Every dry-quote stand-in fits its own chain.
    for (const c of Object.values(NEAR_CHAINS)) expect(addressFits(c, c.placeholder), c.key).toBe(true);
  });

  it("picks the coin the person means: the chain's own bridge first, never a deprecated one", () => {
    expect(pickToken(TOKENS, NEAR_CHAINS.base, "usdc")?.contractAddress).toBe(BASE_USDC);
    expect(pickToken(TOKENS, NEAR_CHAINS.base, "$ETH")?.assetId).toBe("nep141:base.omft.near");
    expect(pickToken(TOKENS, NEAR_CHAINS.near, "near")?.assetId).toBe("nep141:wrap.near");
    expect(pickToken(TOKENS, NEAR_CHAINS.bitcoin, "btc")?.assetId).toBe("nep141:btc.omft.near");
    expect(pickToken(TOKENS, NEAR_CHAINS.bsc, "bnb")?.assetId).toBe("nep141:bnb.omdep.near");
    expect(pickToken(TOKENS, NEAR_CHAINS.solana, "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v")?.symbol).toBe("USDC");
    expect(pickToken(TOKENS, NEAR_CHAINS.solana, "nep141:sol.omft.near")?.symbol).toBe("SOL");
    expect(pickToken(TOKENS, NEAR_CHAINS.base, "pepe")).toBeNull();
  });

  it("reads 1Click's statuses in the spec's words", () => {
    expect(statusOf("KNOWN_DEPOSIT_TX")).toBe("PROCESSING");
    expect(statusOf("SUCCESS")).toBe("SUCCESS");
    expect(statusOf("something new")).toBe("PENDING_DEPOSIT");
  });
});

describe("NEAR Intents deposits", () => {
  const ERC20 = parseAbi(["function transfer(address to, uint256 amount) returns (bool)"]);

  it("pays an ERC-20 deposit with a plain transfer to the deposit address", () => {
    const d = depositFor(NEAR_CHAINS.base, TOKENS[0], DEPOSIT.toLowerCase(), "20000000", null);
    expect(d).toMatchObject({ kind: "erc20", chain: "base", chainId: 8453, to: getAddress(BASE_USDC), value: "0",
      amountBase: "20000000", token: getAddress(BASE_USDC), depositAddress: DEPOSIT });
    const call = decodeFunctionData({ abi: ERC20, data: (d as { data: `0x${string}` }).data });
    expect(call.functionName).toBe("transfer");
    expect(call.args).toEqual([DEPOSIT, 20000000n]);
  });

  it("pays gas coins, SOL and SPL tokens straight to the deposit address, anything else by hand", () => {
    expect(depositFor(NEAR_CHAINS.base, TOKENS[1], DEPOSIT, "1000", null))
      .toEqual({ kind: "native", chain: "base", chainId: 8453, to: DEPOSIT, value: "1000", data: "0x", amountBase: "1000", depositAddress: DEPOSIT });
    expect(depositFor(NEAR_CHAINS.solana, TOKENS[2], PHANTOM, "200000000", null))
      .toEqual({ kind: "sol", chain: "solana", to: PHANTOM, lamports: "200000000", amountBase: "200000000", depositAddress: PHANTOM });
    expect(depositFor(NEAR_CHAINS.solana, TOKENS[3], PHANTOM, "5000000", null)).toEqual({ kind: "spl", chain: "solana", to: PHANTOM,
      mint: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v", amountBase: "5000000", decimals: 6, depositAddress: PHANTOM });
    expect(depositFor(NEAR_CHAINS.bitcoin, TOKENS[8], "bc1qdeposit", "150000", "42")).toEqual({ kind: "manual", chain: "bitcoin",
      to: "bc1qdeposit", memo: "42", amount: "0.0015", amountBase: "150000", symbol: "BTC", depositAddress: "bc1qdeposit" });
  });
});

describe("NEAR Intents quotes", () => {
  it("asks for a dry quote with stand-in addresses when the phone gave none", async () => {
    const { n, calls } = intents();
    const q = await n.quote({ sell: "USDC", sellChain: "base", buy: "SOL", buyChain: "solana", amount: "20" });
    const sent = calls.find(c => c.url.endsWith("/v0/quote"))!.body;
    expect(sent).toEqual({ dry: true, swapType: "EXACT_INPUT", slippageTolerance: 100,
      originAsset: `nep141:base-${BASE_USDC}.omft.near`, depositType: "ORIGIN_CHAIN", destinationAsset: "nep141:sol.omft.near",
      amount: "20000000", refundTo: NEAR_CHAINS.base.placeholder, refundType: "ORIGIN_CHAIN",
      recipient: NEAR_CHAINS.solana.placeholder, recipientType: "DESTINATION_CHAIN",
      deadline: "2026-11-13T01:00:00.000Z", referral: "glyf" });
    expect(q).toMatchObject({ ok: true, dry: true, venue: "NEAR Intents", exact: "in",
      sell: { symbol: "USDC", chain: "base", decimals: 6, address: BASE_USDC },
      buy: { symbol: "SOL", chain: "solana", decimals: 9, assetId: "nep141:sol.omft.near", address: null },
      amountIn: "20", amountInBase: "20000000", amountInUsd: "19.99", amountOut: "0.2475", amountOutBase: "247500000",
      amountOutUsd: "19.88", minAmountOut: "0.245025", timeSeconds: 32,
      depositAddress: null, deposit: null, explorer: null, recipient: null, refundTo: null });
  });

  it("gets a deposit address and builds the deposit when both addresses are there", async () => {
    const { n, calls } = intents();
    const q = await n.quote({ sell: "usdc", sellChain: "base", buy: "sol", buyChain: "solana", amount: "20",
      refundTo: MINE, recipient: PHANTOM, slippage: 0.5 });
    const sent = calls.find(c => c.url.endsWith("/v0/quote"))!.body;
    expect(sent).toMatchObject({ dry: false, refundTo: MINE, recipient: PHANTOM, slippageTolerance: 50 });
    expect(q).toMatchObject({ dry: false, depositAddress: DEPOSIT, deadline: "2026-11-14T00:00:00.000Z",
      deposit: { kind: "erc20", amountBase: "20000000", depositAddress: DEPOSIT },
      explorer: EXPLORER + DEPOSIT, recipient: PHANTOM, refundTo: MINE });
  });

  it("prices a send by what the recipient gets (EXACT_OUTPUT) and deposits 1Click's amountIn", async () => {
    const { n, calls } = intents();
    const q = await n.quote({ sell: "USDC", sellChain: "base", buy: "USDC", buyChain: "near", amount: "5", exact: "out",
      refundTo: MINE, recipient: "alice.near" });
    const sent = calls.find(c => c.url.endsWith("/v0/quote"))!.body;
    expect(sent).toMatchObject({ swapType: "EXACT_OUTPUT", amount: "5000000", recipient: "alice.near" });
    expect(q).toMatchObject({ exact: "out", amountOut: "5", amountIn: "5.05", amountInBase: "5050000",
      buy: { symbol: "USDC", chain: "near" }, deposit: { kind: "erc20", amountBase: "5050000" } });
  });

  it("names NEAR's own coin NEAR, though 1Click lists it as wNEAR", async () => {
    const { n } = intents();
    const q = await n.quote({ sell: "SOL", sellChain: "solana", buy: "NEAR", buyChain: "near", amount: "0.2" });
    expect(q.buy).toMatchObject({ symbol: "NEAR", assetId: "nep141:wrap.near", decimals: 24 });
  });

  it("gives a deposit from Bitcoin three hours and a manual deposit", async () => {
    const { n, calls } = intents();
    const q = await n.quote({ sell: "BTC", sellChain: "bitcoin", buy: "USDC", buyChain: "base", amount: "0.01",
      refundTo: "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh", recipient: MINE });
    expect(calls.find(c => c.url.endsWith("/v0/quote"))!.body.deadline).toBe("2026-11-13T03:00:00.000Z");
    expect(q.deposit).toMatchObject({ kind: "manual", chain: "bitcoin", amount: "0.01", symbol: "BTC" });
  });

  it("refuses what it can't trade, in plain words", async () => {
    const { n } = intents();
    await expect(n.quote({ sell: "PEPE", sellChain: "base", buy: "SOL", buyChain: "solana", amount: "1" }))
      .rejects.toMatchObject({ status: 400, message: "NEAR Intents doesn't trade PEPE on Base" });
    await expect(n.quote({ sell: "USDC", sellChain: "unichain", buy: "SOL", buyChain: "solana", amount: "1" }))
      .rejects.toMatchObject({ status: 400, message: "NEAR Intents isn't on unichain" });
    await expect(n.quote({ sell: "USDC", sellChain: "base", buy: "USDC", buyChain: "base", amount: "1" }))
      .rejects.toMatchObject({ message: "That's the same coin" });
    await expect(n.quote({ sell: "USDC", sellChain: "base", buy: "SOL", buyChain: "solana", amount: "0" }))
      .rejects.toMatchObject({ message: "amount?" });
    await expect(n.quote({ sell: "USDC", sellChain: "base", buy: "SOL", buyChain: "solana", amount: "1", refundTo: PHANTOM, recipient: PHANTOM }))
      .rejects.toMatchObject({ message: "Refunds need your Base address" });
  });

  it("turns 1Click's minimum into dollars, and its other refusals into the trade's words", async () => {
    const low = intents({ quote: () => new Response(JSON.stringify({ message: "Amount is too low for bridge, try at least 150000" }), { status: 400 }) });
    await expect(low.n.quote({ sell: "USDC", sellChain: "base", buy: "SOL", buyChain: "solana", amount: "0.01" }))
      .rejects.toMatchObject({ status: 400, message: "Too small for NEAR Intents: at least $0.15" });
    const none = intents({ quote: () => new Response(JSON.stringify({ message: "Quoting for this pair is not available" }), { status: 400 }) });
    await expect(none.n.quote({ sell: "USDC", sellChain: "base", buy: "ZEC", buyChain: "zcash", amount: "20" }))
      .rejects.toMatchObject({ message: "NEAR Intents can't trade USDC on Base for ZEC on Zcash right now" });
    const down = intents({ quote: () => new Response(JSON.stringify({ message: "Internal server error" }), { status: 500 }) });
    await expect(down.n.quote({ sell: "USDC", sellChain: "base", buy: "SOL", buyChain: "solana", amount: "20" }))
      .rejects.toMatchObject({ status: 502, message: "NEAR Intents didn't answer. Try again in a moment" });
  });

  it("keeps the token list ten minutes, and sends NEAR_INTENTS_JWT as Bearer only when set", async () => {
    const keyless = intents();
    await keyless.n.quote({ sell: "USDC", sellChain: "base", buy: "SOL", buyChain: "solana", amount: "20" });
    await keyless.n.quote({ sell: "USDC", sellChain: "base", buy: "SOL", buyChain: "solana", amount: "30" });
    expect(keyless.calls.filter(c => c.url.endsWith("/v0/tokens"))).toHaveLength(1);
    expect(keyless.calls.every(c => c.auth === undefined)).toBe(true);
    const keyed = intents({}, "jwt-123");
    await keyed.n.quote({ sell: "USDC", sellChain: "base", buy: "SOL", buyChain: "solana", amount: "20" });
    expect(keyed.calls.every(c => c.auth === "Bearer jwt-123")).toBe(true);
  });
});

describe("NEAR Intents status and submit", () => {
  it("follows a swap until it lands, with both transactions", async () => {
    const { n, calls } = intents({ status: q => new Response(JSON.stringify({ status: "SUCCESS", updatedAt: "x", quoteResponse: {},
      swapDetails: { amountOutFormatted: "0.2438", intentHashes: [], nearTxHashes: [],
        originChainTxHashes: [{ hash: "0xabc", explorerUrl: "https://basescan.org/tx/0xabc" }],
        destinationChainTxHashes: [{ hash: "5sig", explorerUrl: "https://solscan.io/tx/5sig" }] },
      seen: q.get("depositMemo") })) });
    const s = await n.status(DEPOSIT, "7");
    expect(calls.at(-1)!.url).toBe(`${ONECLICK}/v0/status?depositAddress=${DEPOSIT}&depositMemo=7`);
    expect(s).toEqual({ ok: true, status: "SUCCESS", done: true, amountOut: "0.2438",
      destinationTx: { hash: "5sig", url: "https://solscan.io/tx/5sig" }, originTx: { hash: "0xabc", url: "https://basescan.org/tx/0xabc" },
      explorer: EXPLORER + DEPOSIT });
  });

  it("says a seen deposit is processing, a refund what came back, and an unknown address 404", async () => {
    const seen = intents({ status: () => new Response(JSON.stringify({ status: "KNOWN_DEPOSIT_TX", swapDetails: {} })) });
    expect(await seen.n.status(DEPOSIT)).toMatchObject({ status: "PROCESSING", done: false });
    const back = intents({ status: () => new Response(JSON.stringify({ status: "REFUNDED", swapDetails: { refundedAmountFormatted: "20" } })) });
    expect(await back.n.status(DEPOSIT)).toMatchObject({ status: "REFUNDED", done: true, refunded: "20" });
    const { n } = intents();
    await expect(n.status(DEPOSIT)).rejects.toMatchObject({ status: 404, message: "NEAR Intents doesn't know that deposit address" });
  });

  it("tells 1Click about the deposit transaction", async () => {
    const { n, calls } = intents();
    expect(await n.submit(DEPOSIT, "0xfeed", "9")).toEqual({ ok: true });
    expect(calls.at(-1)).toMatchObject({ method: "POST", url: `${ONECLICK}/v0/deposit/submit`,
      body: { txHash: "0xfeed", depositAddress: DEPOSIT, memo: "9" } });
  });
});

describe("POST /near/quote, GET /near/status, POST /near/submit", () => {
  function setup(opts: Parameters<typeof fake1Click>[0] = {}, accounts: string[] = ["alice.near"]) {
    const f = fake1Click(opts);
    const app = Fastify();
    nearRoutes(app, { fetchImpl: f.fetchImpl, jwt: () => "", near: fakeNear(accounts), now: () => NOW });
    return { app, calls: f.calls };
  }
  const quote = (app: ReturnType<typeof Fastify>, payload: object) => app.inject({ method: "POST", url: "/near/quote", payload });

  it("previews a quote with no addresses and no Guard", async () => {
    const { app } = setup();
    const res = await quote(app, { sell: "USDC", sellChain: "base", buy: "SOL", buyChain: "solana", amount: "20" });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ ok: true, dry: true, venue: "NEAR Intents", amountOut: "0.2475" });
    expect(res.json().guard).toBeUndefined();
  });

  it("quotes live with Guard's checks when the phone sends both addresses", async () => {
    const { app } = setup();
    const res = await quote(app, { sell: "USDC", sellChain: "base", buy: "USDC", buyChain: "near", amount: "5", exact: "out",
      refundTo: MINE, recipient: "alice.near", recent: ["alice.near"] });
    expect(res.json()).toMatchObject({ ok: true, dry: false, depositAddress: DEPOSIT, deposit: { kind: "erc20" },
      guard: { level: "ok", checks: [] } });
  });

  it("blocks a .near name that doesn't exist and an address poisoned to look like a past one", async () => {
    const { app } = setup();
    const missing = await quote(app, { sell: "USDC", sellChain: "base", buy: "USDC", buyChain: "near", amount: "5", exact: "out",
      refundTo: MINE, recipient: "bob.near" });
    expect(missing.json().guard).toEqual({ level: "block", checks: [
      { id: "no-account", level: "block", text: "No NEAR account bob.near" },
      { id: "new-recipient", level: "warn", text: "First time paying this address" }] });
    const paid = "0xAb12000000000000000000000000000000009fE0";
    const twin = "0xab12ffffffffffffffffffffffffffffffff9fe0";
    const poisoned = await quote(app, { sell: "SOL", sellChain: "solana", buy: "USDC", buyChain: "base", amount: "0.2",
      refundTo: PHANTOM, recipient: twin, recent: [paid] });
    expect(poisoned.json().guard.checks[0]).toEqual({ id: "lookalike", level: "block", text: "Looks like 0xAb12…9fE0 you paid before, but it isn't" });
  });

  it("answers a recipient on the wrong chain with a preview and Guard's block, not 1Click's refusal", async () => {
    const { app, calls } = setup();
    const res = await quote(app, { sell: "USDC", sellChain: "base", buy: "SOL", buyChain: "solana", amount: "20",
      refundTo: MINE, recipient: MINE });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ dry: true, depositAddress: null, guard: { level: "block" } });
    expect(res.json().guard.checks[0]).toEqual({ id: "chain-mismatch", level: "block", text: "That's an EVM address, not Solana" });
    expect(calls.find(c => c.url.endsWith("/v0/quote"))!.body.recipient).toBe(NEAR_CHAINS.solana.placeholder);
  });

  it("says what's wrong with a request, and sends 1Click's failures as 400 or 502", async () => {
    const { app } = setup();
    expect((await quote(app, { sell: "USDC", sellChain: "base", buy: "SOL", buyChain: "solana", amount: "lots" })).json())
      .toEqual({ ok: false, error: "amount?" });
    const pepe = await quote(app, { sell: "PEPE", sellChain: "base", buy: "SOL", buyChain: "solana", amount: "1" });
    expect(pepe.statusCode).toBe(400);
    const down = setup({ quote: () => new Response("{}", { status: 503 }) });
    const res = await quote(down.app, { sell: "USDC", sellChain: "base", buy: "SOL", buyChain: "solana", amount: "20" });
    expect(res.statusCode).toBe(502);
    expect(res.json()).toEqual({ ok: false, error: "NEAR Intents didn't answer. Try again in a moment" });
  });

  it("follows a deposit and passes its tx hash on", async () => {
    const { app } = setup({ status: () => new Response(JSON.stringify({ status: "PROCESSING", swapDetails: {} })) });
    const s = await app.inject({ method: "GET", url: `/near/status?deposit=${DEPOSIT}` });
    expect(s.json()).toEqual({ ok: true, status: "PROCESSING", done: false, explorer: EXPLORER + DEPOSIT });
    expect(s.headers["cache-control"]).toBe("no-store");
    expect((await app.inject({ method: "GET", url: "/near/status?deposit=x" })).statusCode).toBe(400);
    const sub = await app.inject({ method: "POST", url: "/near/submit", payload: { depositAddress: DEPOSIT, txHash: "0x" + "ab".repeat(32) } });
    expect(sub.json()).toEqual({ ok: true });
    expect((await app.inject({ method: "POST", url: "/near/submit", payload: { depositAddress: DEPOSIT } })).statusCode).toBe(400);
  });

  it("is a 404 for a deposit address 1Click doesn't know", async () => {
    const { app } = setup();
    const res = await app.inject({ method: "GET", url: `/near/status?deposit=${DEPOSIT}` });
    expect(res.statusCode).toBe(404);
  });
});

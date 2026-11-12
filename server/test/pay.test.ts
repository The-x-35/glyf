import Fastify from "fastify";
import { getAddress } from "viem";
import { describe, expect, it } from "vitest";
import { buildApp } from "../src/index.js";
import { MemoryLimiter } from "../src/lib/limits.js";
import type { NearLookup } from "../src/lib/names.js";
import { ONECLICK, type IntentToken } from "../src/lib/nearintents.js";
import { depositUri, headline, metamaskLink, qrDataUri } from "../src/lib/paypage.js";
import {
  amountWords, chainForRecipient, cleanAmount, PAYERS, payersOf, recipientProblem, saveRequest, shareOf, shortRecipient,
  tallyOf, type Payer, type PayRequest,
} from "../src/lib/payrequests.js";
import { MemoryKV } from "../src/lib/store.js";
import { chatText, cleanNote, payRoutes } from "../src/routes/pay.js";
import { NEAR_CHAINS } from "../src/lib/nearintents.js";

const NOW = Date.parse("2026-11-13T00:00:00Z");
const BASE_USDC = "0x833589fcd6edb6e08f4c7c32d4f71b54bda02913";
const ARB_USDC = "0xaf88d065e77c8cc2239327c5edb3a432268e5831";
const MINE = "0x1111111111111111111111111111111111111111";
const ARB_REFUND = "0x2222222222222222222222222222222222222222";
const PHANTOM = "7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU";

const TOKENS: IntentToken[] = [
  { assetId: `nep141:base-${BASE_USDC}.omft.near`, decimals: 6, blockchain: "base", symbol: "USDC", price: 1, contractAddress: BASE_USDC },
  { assetId: `nep141:arb-${ARB_USDC}.omft.near`, decimals: 6, blockchain: "arb", symbol: "USDC", price: 1, contractAddress: ARB_USDC },
  { assetId: "nep141:base.omft.near", decimals: 18, blockchain: "base", symbol: "ETH", price: 2000 },
  { assetId: "nep141:sol.omft.near", decimals: 9, blockchain: "sol", symbol: "SOL", price: 80 },
  { assetId: "nep141:sol-5ce3bf3a31af18be40ba30f721101b4341690186.omft.near", decimals: 6, blockchain: "sol", symbol: "USDC",
    price: 1, contractAddress: "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v" },
  { assetId: "nep141:wrap.near", decimals: 24, blockchain: "near", symbol: "wNEAR", price: 3.4, contractAddress: "wrap.near" },
  { assetId: "nep141:17208628f84f5d6ad33f0da3bbbeb27ffcb398eac501a31bd6ad2011e36133a1", decimals: 6, blockchain: "near",
    symbol: "USDC", price: 1, contractAddress: "17208628f84f5d6ad33f0da3bbbeb27ffcb398eac501a31bd6ad2011e36133a1" },
  { assetId: "nep141:btc.omft.near", decimals: 8, blockchain: "btc", symbol: "BTC", price: 72000 },
  { assetId: "nep141:zec.omft.near", decimals: 8, blockchain: "zec", symbol: "ZEC", price: 900 },
];

type Call = { url: string; method: string; body?: any };

/** A stand-in 1Click: tokens, EXACT_OUTPUT quotes with a fresh deposit
 *  address each, and whatever status a test sets per deposit. */
function fake1Click() {
  const calls: Call[] = [];
  const statuses = new Map<string, unknown>();
  let n = 0;
  const fetchImpl = (async (url: string, init: RequestInit = {}) => {
    const u = new URL(String(url));
    const body = init.body ? JSON.parse(String(init.body)) : undefined;
    calls.push({ url: String(url), method: init.method ?? "GET", body });
    const ok = (json: unknown) => new Response(JSON.stringify(json), { headers: { "content-type": "application/json" } });
    if (u.origin !== ONECLICK) throw new Error(`unexpected ${url}`);
    if (u.pathname === "/v0/tokens") return ok(TOKENS);
    if (u.pathname === "/v0/quote") {
      if (body.refundTo === "0x000000000000000000000000000000000000dEaD") {
        return new Response(JSON.stringify({ message: "Amount is too low for bridge, try at least 150000" }), { status: 400 });
      }
      const sell = TOKENS.find(t => t.assetId === body.originAsset)!;
      const buy = TOKENS.find(t => t.assetId === body.destinationAsset)!;
      const out = BigInt(body.amount);
      const usd = Number(out) / 10 ** buy.decimals * buy.price!;
      const amountIn = BigInt(Math.round(usd * 1.01 / sell.price! * 10 ** sell.decimals));
      n += 1;
      const deposit = body.originAsset.startsWith("nep141:sol") ? `Dep${n}sitSo1anaAddre55xxxxxxxxxxxxxxxxxxxxxx`
        : body.originAsset.startsWith("nep141:btc") ? `bc1qdeposit${n}xxxxxxxxxxxxxxxxxxxxxxxxxxx`
          : `0x${n.toString(16).padStart(40, "7")}`;
      return ok({ quote: {
        amountIn: amountIn.toString(), amountInUsd: (usd * 1.01).toFixed(6), amountOut: out.toString(), amountOutUsd: usd.toFixed(6),
        minAmountOut: out.toString(), timeEstimate: 20,
        ...(body.dry ? {} : { depositAddress: deposit, deadline: "2026-11-13T01:00:00.000Z" }),
      } });
    }
    if (u.pathname === "/v0/status") {
      const s = statuses.get(u.searchParams.get("depositAddress") ?? "");
      if (!s) return new Response(JSON.stringify({ message: "Deposit address not found" }), { status: 404 });
      return ok(s);
    }
    throw new Error(`unexpected ${url}`);
  }) as unknown as typeof fetch;
  return { calls, statuses, fetchImpl };
}

const fakeNear = (accounts: string[]): NearLookup => ({ exists: async a => accounts.includes(a) });

function setup(opts: { accounts?: string[]; quotesPerMinute?: number; now?: () => number } = {}) {
  const f = fake1Click();
  const kv = new MemoryKV();
  const app = Fastify();
  // Stands in for lib/protect.ts: the session's user, when a test sends one.
  app.addHook("onRequest", async req => {
    const u = req.headers["x-test-user"];
    if (typeof u === "string") req.glyfUser = u;
  });
  payRoutes(app, { kv, limits: new MemoryLimiter(), fetchImpl: f.fetchImpl, jwt: () => "",
    near: fakeNear(opts.accounts ?? ["alice.near", "trip.sputnik-dao.near"]), now: opts.now ?? (() => NOW),
    base: () => "https://api.tryglyf.com", quotesPerMinute: opts.quotesPerMinute });
  const create = (payload: object) => app.inject({ method: "POST", url: "/near/requests", payload,
    headers: { "x-test-user": "google:alice" } });
  const quote = (id: string, payload: object, ip = "1.2.3.4") => app.inject({ method: "POST", url: `/pay/${id}/quote`, payload,
    headers: { "x-forwarded-for": ip } });
  return { app, kv, create, quote, ...f };
}

const request = (over: Partial<PayRequest> = {}): PayRequest => ({
  id: "abcdefghijkl", amount: "22.5", typedAmount: "22.5", coin: "USDC", chain: "base", to: MINE, note: "Dinner",
  each: true, count: 3, pot: false, createdBy: "google:alice", createdAt: NOW, ...over,
});

describe("pay link values", () => {
  it("reads amounts as people type them", () => {
    expect(cleanAmount("22.50")).toBe("22.5");
    expect(cleanAmount("$1,200")).toBe("1200");
    expect(cleanAmount(22.5)).toBe("22.5");
    expect(cleanAmount(".5")).toBe("0.5");
    expect(cleanAmount("0")).toBeNull();
    expect(cleanAmount("-3")).toBeNull();
    expect(cleanAmount("1.1234567")).toBeNull();
    expect(cleanAmount("lots")).toBeNull();
  });

  it("splits a total so the shares cover it, to the cent for dollars", () => {
    expect(shareOf("90", "USDC", false, 4)).toBe("22.5");
    expect(shareOf("100", "USDC", false, 3)).toBe("33.34");
    expect(shareOf("22.5", "USDC", true, 4)).toBe("22.5");
    expect(shareOf("22.505", "USDC", true, null)).toBe("22.51");
    expect(shareOf("0.1", "ETH", false, 3)).toBe("0.033334");
    expect(shareOf("5", "USDC", false, null)).toBe("5");
  });

  it("says amounts and recipients the short way", () => {
    expect(amountWords("22.5", "USDC")).toBe("$22.50");
    expect(amountWords("1200", "USDC")).toBe("$1,200");
    expect(amountWords("0.01", "BTC")).toBe("0.01 BTC");
    expect(shortRecipient("alice.near")).toBe("alice.near");
    expect(shortRecipient(MINE)).toBe("0x1111…1111");
    expect(shortRecipient(PHANTOM)).toBe("7xKX…gAsU");
    expect(shortRecipient("goa-trip.sputnik-dao.near")).toBe("goa-trip.sputnik-dao.near");
    expect(headline(request())).toBe("Dinner · $22.50 each to 0x1111…1111");
    expect(headline(request({ note: "", each: false, to: "alice.near" }))).toBe("$22.50 to alice.near");
  });

  it("knows the chain a recipient is on, and says when it can't be paid there", () => {
    expect(chainForRecipient(MINE).key).toBe("base");
    expect(chainForRecipient("alice.near").key).toBe("near");
    expect(chainForRecipient(PHANTOM).key).toBe("solana");
    expect(chainForRecipient("bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh").key).toBe("bitcoin");
    expect(recipientProblem(NEAR_CHAINS.solana, MINE)).toBe("That's an EVM address, not Solana");
    expect(recipientProblem(NEAR_CHAINS.base, "alice.near")).toBe("That's a NEAR address, not Base");
    expect(recipientProblem(NEAR_CHAINS.base, "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh")).toBe("That's a Bitcoin address, not Base");
    expect(recipientProblem(NEAR_CHAINS.base, MINE)).toBeNull();
  });

  it("counts who paid", () => {
    const paid = (status: Payer["status"]) => ({ status }) as Payer;
    expect(tallyOf(request(), []).words).toBe("0 of 3 paid");
    expect(tallyOf(request(), [paid("SUCCESS"), paid("PROCESSING"), paid("REFUNDED")]).words).toBe("1 of 3 paid");
    expect(tallyOf(request(), [paid("SUCCESS"), paid("SUCCESS"), paid("SUCCESS")])).toMatchObject({ words: "All 3 paid", full: true });
    expect(tallyOf(request({ count: null }), []).words).toBe("");
    expect(tallyOf(request({ count: null }), [paid("SUCCESS")]).words).toBe("1 paid");
    expect(tallyOf(request({ count: 1 }), [paid("SUCCESS")]).words).toBe("Paid");
  });

  it("keeps notes to one plain line, and writes the chat's words", () => {
    expect(cleanNote("  din‮ner\n\tat  sam's ")).toBe("din ner at sam's");
    expect(cleanNote("x".repeat(120))).toHaveLength(80);
    const url = "https://api.tryglyf.com/pay/abc";
    expect(chatText(request(), url)).toBe(`Pay your $22.50 share for Dinner: ${url}`);
    expect(chatText(request({ each: false, count: null, note: "" }), url)).toBe(`Pay $22.50: ${url}`);
    expect(chatText(request({ pot: true, to: "trip.sputnik-dao.near", note: "the cabin" }), url)).toBe(`Chip in $22.50 for the cabin: ${url}`);
  });

  it("puts a payment URI in the QR where wallets read one", async () => {
    expect(depositUri("bitcoin", "bc1qx", "0.0003")).toBe("bitcoin:bc1qx?amount=0.0003");
    expect(depositUri("zcash", "t1x", "0.02")).toBe("zcash:t1x?amount=0.02");
    expect(depositUri("solana", "Dep", "0.28", "EPj")).toBe("solana:Dep?amount=0.28&spl-token=EPj");
    expect(depositUri("base", "0xabc", "1")).toBe("0xabc");
    const qr = await qrDataUri("0xabc");
    expect(qr.startsWith("data:image/svg+xml;base64,")).toBe(true);
    expect(Buffer.from(qr.split(",")[1], "base64").toString()).toContain("<svg");
    expect(metamaskLink({ kind: "erc20", chain: "base", chainId: 8453, to: "0xT", data: "0x", value: "0", amountBase: "22725000",
      token: "0xT", depositAddress: "0xD" })).toBe("https://metamask.app.link/send/0xT@8453/transfer?address=0xD&uint256=22725000");
    expect(metamaskLink({ kind: "sol", chain: "solana", to: "D", lamports: "1", amountBase: "1", depositAddress: "D" })).toBeNull();
  });
});

describe("POST /near/requests", () => {
  it("makes a link for a share, paid as USDC on Base by default", async () => {
    const { create, kv } = setup();
    const res = await create({ amount: "22.50", to: MINE, note: "dinner", each: true, count: 3 });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body).toMatchObject({ ok: true, amount: "22.5", coin: "USDC", chain: "base", to: MINE, note: "dinner",
      each: true, count: 3, pot: false });
    expect(body.id).toMatch(/^[A-Za-z0-9_-]{12}$/);
    expect(body.url).toBe(`https://api.tryglyf.com/pay/${body.id}`);
    expect(body.text).toBe(`Pay your $22.50 share for dinner: ${body.url}`);
    expect(kv.get<PayRequest>("payreqs", body.id)).toMatchObject({ createdBy: "google:alice", typedAmount: "22.5" });
  });

  it("splits a total, pays a .near name on NEAR, and makes a Sputnik DAO a shared pot", async () => {
    const { create } = setup();
    expect((await create({ amount: 90, to: MINE, count: 4 })).json()).toMatchObject({ amount: "22.5", each: false, count: 4 });
    // "$90 for the four of us": the writer paid the bill, three people owe a quarter.
    const us = (await create({ amount: 90, to: MINE, count: 4, us: true, note: "dinner" })).json();
    expect(us).toMatchObject({ amount: "22.5", each: false, count: 3 });
    expect(us.text).toBe(`Pay your $22.50 share for dinner: ${us.url}`);
    expect((await create({ amount: 5, to: "alice.near" })).json()).toMatchObject({ chain: "near", coin: "USDC", pot: false });
    expect((await create({ amount: 2, coin: "near", to: "alice.near" })).json()).toMatchObject({ coin: "NEAR" });
    const pot = (await create({ amount: 50, to: "trip.sputnik-dao.near", note: "cabin", each: true, count: 6 })).json();
    expect(pot).toMatchObject({ ok: true, pot: true, chain: "near" });
    expect(pot.text).toBe(`Chip in $50 for cabin: ${pot.url}`);
    expect((await create({ amount: 20, to: PHANTOM, chain: "sol" })).json()).toMatchObject({ chain: "solana" });
  });

  it("refuses what can't be paid, in plain words", async () => {
    const { create } = setup();
    const err = async (payload: object) => {
      const res = await create(payload);
      return [res.statusCode, res.json().error];
    };
    expect(await err({ amount: 0, to: MINE })).toEqual([400, "amount?"]);
    expect(await err({ amount: 5, to: "bob.near" })).toEqual([400, "No NEAR account bob.near"]);
    expect(await err({ amount: 5, to: MINE, chain: "solana" })).toEqual([400, "That's an EVM address, not Solana"]);
    expect(await err({ amount: 5, to: MINE, chain: "fantom" })).toEqual([400, "NEAR Intents isn't on fantom"]);
    expect(await err({ amount: 5, to: MINE, coin: "DOGE" })).toEqual([400, "NEAR Intents doesn't trade DOGE on Base"]);
    expect(await err({ amount: 5, to: MINE, count: 0 })).toEqual([400, expect.any(String)]);
    expect(await err({ amount: 5, to: MINE, coin: "<b>" })).toEqual([400, "coin?"]);
  });

  it("needs the session's user", async () => {
    const { app } = setup();
    const res = await app.inject({ method: "POST", url: "/near/requests", payload: { amount: 5, to: MINE } });
    expect(res.statusCode).toBe(401);
  });
});

describe("GET /pay/:id", () => {
  it("shows the request, who paid, and what they can pay with", async () => {
    const { app, create } = setup();
    const { id } = (await create({ amount: "22.50", to: "alice.near", note: "Dinner", each: true, count: 4 })).json();
    const res = await app.inject({ method: "GET", url: `/pay/${id}` });
    expect(res.statusCode).toBe(200);
    expect(res.headers["content-type"]).toContain("text/html");
    const html = res.body;
    expect(html).toContain("Dinner · $22.50 each to alice.near");
    expect(html).toContain("0 of 4 paid");
    expect(html).toContain("USDC · Arbitrum");
    expect(html).toContain("BTC");
    expect(html).toContain("Pay request");
    // Its one script carries the nonce the CSP allows, and nothing else may run.
    const csp = String(res.headers["content-security-policy"]);
    const nonce = csp.match(/'nonce-([^']+)'/)![1];
    expect(html).toContain(`<script nonce="${nonce}">`);
    expect(csp).toContain("connect-src 'self'");
    expect(csp).not.toContain("unsafe-eval");
    expect(res.headers["cache-control"]).toBe("no-store");
  });

  it("leaves out what the requester asked for, says a DAO is a shared pot, and escapes the note", async () => {
    const { app, create } = setup();
    const { id } = (await create({ amount: 10, to: MINE, note: "</script><img src=x onerror=alert(1)>" })).json();
    const html = (await app.inject({ method: "GET", url: `/pay/${id}` })).body;
    expect(html).not.toContain("<img src=x");
    expect(html).toContain("&lt;/script&gt;&lt;img src=x");
    expect(html).not.toContain('value="usdc-base"');
    expect(html).toContain('value="usdc-arbitrum"');
    const pot = (await create({ amount: 50, to: "trip.sputnik-dao.near", each: true })).json();
    const potHtml = (await app.inject({ method: "GET", url: `/pay/${pot.id}` })).body;
    expect(potHtml).toContain("Shared pot");
    expect(potHtml).toContain("Into the trip DAO treasury · shared pot");
  });

  it("is a 404 page for a link that doesn't exist", async () => {
    const { app } = setup();
    for (const url of ["/pay/nope-nope-nope", "/pay/x"]) {
      const res = await app.inject({ method: "GET", url });
      expect(res.statusCode).toBe(404);
      expect(res.body).toContain("This pay link doesn't exist");
    }
  });
});

describe("POST /pay/:id/quote and GET /pay/:id/status", () => {
  it("quotes exactly the share to the requester, from what the payer picked", async () => {
    const { create, quote, calls, kv } = setup();
    const { id } = (await create({ amount: "22.50", to: MINE, note: "Dinner", each: true, count: 3 })).json();
    const res = await quote(id, { with: "usdc-arbitrum", refundTo: ARB_REFUND });
    expect(res.statusCode).toBe(200);
    const q = res.json();
    const sent = calls.find(c => c.url.endsWith("/v0/quote"))!.body;
    expect(sent).toMatchObject({ dry: false, swapType: "EXACT_OUTPUT", originAsset: `nep141:arb-${ARB_USDC}.omft.near`,
      destinationAsset: `nep141:base-${BASE_USDC}.omft.near`, amount: "22500000", recipient: MINE, refundTo: ARB_REFUND,
      refundType: "ORIGIN_CHAIN", referral: "glyf" });
    expect(q).toMatchObject({ ok: true, venue: "NEAR Intents", coin: "USDC", chain: "arbitrum", chainName: "Arbitrum",
      amount: "22.725", gets: "22.50 USDC on Base", deadline: "2026-11-13T01:00:00.000Z" });
    expect(q.depositAddress).toMatch(/^0x/);
    expect(q.deposit).toMatchObject({ kind: "erc20", chainId: 42161, amountBase: "22725000" });
    expect(q.qr.startsWith("data:image/svg+xml;base64,")).toBe(true);
    expect(q.uri).toBe(q.depositAddress);
    expect(q.wallet).toBe(`https://metamask.app.link/send/${getAddress(ARB_USDC)}@42161/transfer?address=${q.depositAddress}&uint256=22725000`);
    expect(payersOf(kv, id)).toEqual([expect.objectContaining({ depositAddress: q.depositAddress, coin: "USDC", chain: "arbitrum",
      amountIn: "22.725", status: "PENDING_DEPOSIT", paidAt: null })]);
    // The refund address is 1Click's to know, not the store's.
    expect(JSON.stringify(kv.list(PAYERS))).not.toContain(ARB_REFUND);
  });

  it("pays from Bitcoin and Solana with a payment URI in the QR", async () => {
    const { create, quote } = setup();
    const { id } = (await create({ amount: 30, to: "alice.near" })).json();
    const btc = (await quote(id, { with: "btc", refundTo: "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh" })).json();
    expect(btc).toMatchObject({ ok: true, coin: "BTC", chain: "bitcoin", deposit: { kind: "manual" }, wallet: null });
    expect(btc.uri).toBe(`bitcoin:${btc.depositAddress}?amount=${btc.amount}`);
    const sol = (await quote(id, { with: "usdc-solana", refundTo: PHANTOM })).json();
    expect(sol.uri).toBe(`solana:${sol.depositAddress}?amount=${sol.amount}&spl-token=EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v`);
  });

  it("says what's wrong with a payment, in plain words", async () => {
    const { create, quote } = setup();
    const { id } = (await create({ amount: 22.5, to: MINE })).json();
    const err = async (payload: object) => {
      const res = await quote(id, payload);
      return [res.statusCode, res.json().error];
    };
    expect(await err({ with: "usdc-base", refundTo: MINE })).toEqual([400,
      `That's what they asked for. Send USDC on Base straight to ${MINE}`]);
    expect(await err({ with: "sol", refundTo: MINE })).toEqual([400, "Refunds need your Solana address"]);
    expect(await err({ with: "doge", refundTo: MINE })).toEqual([400, "Pick what you pay with"]);
    expect(await err({ with: "sol" })).toEqual([400, "Add your refund address"]);
    expect(await err({ with: "eth-base", refundTo: "0x000000000000000000000000000000000000dEaD" }))
      .toEqual([400, "Too small for NEAR Intents: at least $0.15"]);
    const missing = await quote("nope-nope-nope", { with: "sol", refundTo: PHANTOM });
    expect(missing.statusCode).toBe(404);
  });

  it("holds each address to a few quotes a minute", async () => {
    const { create, quote } = setup({ quotesPerMinute: 2 });
    const { id } = (await create({ amount: 5, to: MINE })).json();
    expect((await quote(id, { with: "sol", refundTo: PHANTOM })).statusCode).toBe(200);
    expect((await quote(id, { with: "sol", refundTo: PHANTOM })).statusCode).toBe(200);
    const third = await quote(id, { with: "sol", refundTo: PHANTOM });
    expect(third.statusCode).toBe(429);
    expect(third.json().error).toBe("Too many tries. Wait a minute");
    expect((await quote(id, { with: "sol", refundTo: PHANTOM }, "5.6.7.8")).statusCode).toBe(200);
  });

  it("marks a payer paid when their swap lands, and says 1 of 3 paid", async () => {
    const { app, create, quote, statuses, kv } = setup();
    const { id } = (await create({ amount: "22.50", to: MINE, each: true, count: 3 })).json();
    const q = (await quote(id, { with: "sol", refundTo: PHANTOM })).json();
    const status = () => app.inject({ method: "GET", url: `/pay/${id}/status?deposit=${encodeURIComponent(q.depositAddress)}` });

    statuses.set(q.depositAddress, { status: "KNOWN_DEPOSIT_TX", swapDetails: {} });
    expect((await status()).json()).toMatchObject({ ok: true, status: "PROCESSING", done: false, tally: { paid: 0, words: "0 of 3 paid" } });

    statuses.set(q.depositAddress, { status: "SUCCESS", swapDetails: { amountOutFormatted: "22.5",
      destinationChainTxHashes: [{ hash: "0xbeef", explorerUrl: "https://basescan.org/tx/0xbeef" }] } });
    const done = (await status()).json();
    expect(done).toMatchObject({ ok: true, status: "SUCCESS", done: true, amountOut: "22.5",
      destinationTx: { hash: "0xbeef", url: "https://basescan.org/tx/0xbeef" }, tally: { paid: 1, count: 3, words: "1 of 3 paid", full: false } });
    expect(payersOf(kv, id)[0]).toMatchObject({ status: "SUCCESS", paidAt: NOW });
    expect((await app.inject({ method: "GET", url: `/pay/${id}` })).body).toContain("1 of 3 paid");
  });

  it("only follows this link's own deposits", async () => {
    const { app, create, quote } = setup();
    const a = (await create({ amount: 5, to: MINE })).json();
    const b = (await create({ amount: 5, to: MINE })).json();
    const q = (await quote(a.id, { with: "sol", refundTo: PHANTOM })).json();
    const other = await app.inject({ method: "GET", url: `/pay/${b.id}/status?deposit=${q.depositAddress}` });
    expect(other.statusCode).toBe(404);
    expect(other.json().error).toBe("That deposit isn't for this link");
    expect((await app.inject({ method: "GET", url: `/pay/${a.id}/status?deposit=<x>` })).statusCode).toBe(400);
  });

  it("looks again at pending payers when the page asks for the tally, at most every 30 seconds", async () => {
    let now = NOW;
    const { app, create, quote, statuses, calls } = setup({ now: () => now });
    const { id } = (await create({ amount: 10, to: MINE, count: 2 })).json();
    const one = (await quote(id, { with: "sol", refundTo: PHANTOM })).json();
    const two = (await quote(id, { with: "usdc-arbitrum", refundTo: ARB_REFUND })).json();
    statuses.set(one.depositAddress, { status: "SUCCESS", swapDetails: {} });
    statuses.set(two.depositAddress, { status: "SUCCESS", swapDetails: {} });
    const tally = async () => (await app.inject({ method: "GET", url: `/pay/${id}/status` })).json();
    expect(await tally()).toEqual({ ok: true, tally: { paid: 0, count: 2, words: "0 of 2 paid", full: false } });
    now += 31_000;
    expect((await tally()).tally).toMatchObject({ paid: 2, words: "All 2 paid", full: true });
    const asked = calls.filter(c => c.url.includes("/v0/status")).length;
    expect(asked).toBe(2);
    now += 31_000;
    await tally();
    expect(calls.filter(c => c.url.includes("/v0/status")).length).toBe(asked);
    // Everyone's paid: no more deposit addresses.
    const late = await quote(id, { with: "sol", refundTo: PHANTOM });
    expect(late.statusCode).toBe(409);
    expect(late.json().error).toBe("Everyone's paid");
    expect((await app.inject({ method: "GET", url: `/pay/${id}` })).body).toContain("All 2 paid");
  });
});

describe("the pay link behind the gate (lib/protect.ts)", () => {
  it("opens the page to anyone and keeps making links for signed-in phones", async () => {
    const kv = new MemoryKV();
    saveRequest(kv, request());
    const app = buildApp(kv);
    const page = await app.inject({ method: "GET", url: "/pay/abcdefghijkl" });
    expect(page.statusCode).toBe(200);
    expect(page.body).toContain("Dinner · $22.50 each to 0x1111…1111");
    expect((await app.inject({ method: "POST", url: "/near/requests", payload: { amount: 5, to: MINE } })).statusCode).toBe(401);
    expect((await app.inject({ method: "GET", url: "/pay/abcdefghijkl/other" })).statusCode).toBe(401);
  });
});

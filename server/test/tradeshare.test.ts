import { describe, expect, it } from "vitest";
import { buildApp } from "../src/index.js";
import { MemoryKV } from "../src/lib/store.js";
import { copyLink, createShare, getShare, SHARE_TTL_MS } from "../src/lib/tradeshare.js";
import { shareText } from "../src/routes/tradeshare.js";
import { signedInApp, TEST_USER } from "./helpers.js";

const HASH = "0x" + "ab".repeat(32);
const buy = {
  query: { kind: "swap", sell: "USDC", buy: "ETH", amount: "50", usd: "1", chain: "base" },
  summary: "Bought $50 of ETH on Base",
  chainId: 8453,
  txHash: HASH,
};

describe("trade shares", () => {
  it("makes a link and a line for the chat, and the link's page is open to anyone", async () => {
    const kv = new MemoryKV();
    const app = signedInApp(kv);
    const made = await app.inject({ method: "POST", url: "/trade-shares", payload: buy });
    expect(made.statusCode).toBe(200);
    const { ok, id, url, text } = made.json();
    expect(ok).toBe(true);
    expect(id).toMatch(/^[\w-]{12}$/);
    expect(url).toMatch(new RegExp(`/t/${id}$`));
    expect(text).toBe(`Bought $50 of ETH on Base with Glyf. Copy my trade: ${url}`);

    // A friend's phone: no session.
    const page = await app.inject({ url: `/t/${id}`, headers: { authorization: "" } });
    expect(page.statusCode).toBe(200);
    expect(page.headers["content-type"]).toMatch(/text\/html/);
    const csp = String(page.headers["content-security-policy"]);
    expect(csp).toContain("default-src 'none'");
    expect(csp).not.toContain("script-src");
    expect(page.body).not.toContain("<script");
    expect(page.body).toContain("Bought $50 of ETH on Base");
    expect(page.body).toContain("Uniswap");
    expect(page.body).toContain(">Base<");
    expect(page.body).toContain(`https://basescan.org/tx/${HASH}`);
    expect(page.body).toContain("Copy this trade");
    expect(page.body).toContain('href="https://tryglyf.com"');
    // The button is the keyboard's own hand-off, marked as copied.
    const href = /id="copy" href="([^"]+)"/.exec(page.body)![1].replace(/&amp;/g, "&");
    const outer = new URL(href);
    expect(outer.protocol).toBe("glyf:");
    expect(outer.host).toBe("open");
    const inner = new URL("x://" + outer.searchParams.get("path"));
    expect(inner.host).toBe("trade");
    expect(Object.fromEntries(inner.searchParams)).toEqual({ ...buy.query, copied: "1" });
  });

  it("keeps nothing that names a person, and no account details on the page", async () => {
    const kv = new MemoryKV();
    const app = signedInApp(kv);
    const made = await app.inject({ method: "POST", url: "/trade-shares", payload: {
      query: { kind: "limit", sell: "USDC", buy: "ETH", amount: "100", price: "2800", chain: "base", to: "arpit.eth",
        address: "0x2a1cB3CDA2d72e02d4BaF04C809145c0869975D7", copied: "1" },
      summary: "Placed a limit buy for ETH at $2800 on Base",
      orderId: "ord_123",
    } });
    expect(made.statusCode).toBe(200);
    const { id } = made.json();
    const kept = getShare(kv, id)!;
    expect(kept.query).toEqual({ kind: "limit", sell: "USDC", buy: "ETH", amount: "100", price: "2800", chain: "base" });
    expect(kept.chainId).toBe(8453);
    expect(kept.orderId).toBe("ord_123");
    const page = await app.inject({ url: `/t/${id}`, headers: { authorization: "" } });
    expect(page.body).toContain("Flash by Definitive");
    expect(page.body).not.toContain(TEST_USER);
    expect(page.body).not.toContain("arpit.eth");
    expect(page.body).not.toContain("0x2a1c");
  });

  it("refuses sends, requests, odd values and strangers", async () => {
    const app = signedInApp(new MemoryKV());
    const post = (payload: unknown, headers?: Record<string, string>) =>
      app.inject({ method: "POST", url: "/trade-shares", payload: payload as object, ...(headers ? { headers } : {}) });
    expect((await post({ ...buy, query: { kind: "send", sell: "USDC", buy: "USDC", to: "arpit.eth" } })).statusCode).toBe(400);
    expect((await post({ ...buy, query: { kind: "request", sell: "USDT", buy: "USDT" } })).statusCode).toBe(400);
    expect((await post({ ...buy, query: { ...buy.query, amount: "<script>" } })).statusCode).toBe(400);
    expect((await post({ ...buy, summary: "x".repeat(141) })).statusCode).toBe(400);
    expect((await post({ ...buy, txHash: "0x12" })).statusCode).toBe(400);
    const many = Object.fromEntries(Array.from({ length: 20 }, (_, i) => [`k${"abcdefghijklmnopqrst"[i]}`, "1"]));
    expect((await post({ ...buy, query: { ...buy.query, ...many } })).statusCode).toBe(400);
    // No session, no share.
    expect((await post(buy, { authorization: "" })).statusCode).toBe(401);
  });

  it("an unknown or old link is a 404 page", async () => {
    const kv = new MemoryKV();
    const app = buildApp(kv);
    const missing = await app.inject({ url: "/t/abcdefghijkl" });
    expect(missing.statusCode).toBe(404);
    expect(missing.body).toContain("Trade not found");
    expect((await app.inject({ url: "/t/short" })).statusCode).toBe(404);

    const old = createShare(kv, { user: TEST_USER, query: buy.query, summary: buy.summary }, Date.now() - SHARE_TTL_MS - 1000);
    expect(getShare(kv, old)).toBeUndefined();
    expect((await app.inject({ url: `/t/${old}` })).statusCode).toBe(404);
    // The page's other paths stay locked.
    expect((await app.inject({ url: `/t/${old}/x` })).statusCode).toBe(401);
  });

  it("writes the chat line and the copy link the way the app reads them", () => {
    expect(shareText("Swapped 0.05 ETH for USDC on Base.", "https://api.tryglyf.com/t/abc"))
      .toBe("Swapped 0.05 ETH for USDC on Base with Glyf. Copy my trade: https://api.tryglyf.com/t/abc");
    expect(copyLink({ sell: "ETH", kind: "swap" }))
      .toBe("glyf://open?path=" + encodeURIComponent("trade?copied=1&kind=swap&sell=ETH"));
  });
});

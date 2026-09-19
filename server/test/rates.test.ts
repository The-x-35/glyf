import Fastify from "fastify";
import { describe, expect, it } from "vitest";
import { Rates, pickToken, type FetchLike } from "../src/lib/rates.js";
import { ratesRoutes } from "../src/routes/rates.js";

const jupiter = [
  { id: "jupSoLaHXQiZZTSfEWMTRRgpnyFm8f6sZdosWBjx93v", symbol: "JupSOL", name: "Jupiter Staked SOL",
    isVerified: true, usdPrice: 135.17, tags: ["strict", "verified", "lst"] },
  { id: "So11111111111111111111111111111111111111112", symbol: "SOL", name: "Wrapped SOL",
    isVerified: true, usdPrice: 111.77, tags: ["major", "strict", "verified"], liquidity: 8e8 },
  { id: "FakeSoL1111111111111111111111111111111111111", symbol: "SOL", name: "Not Solana",
    isVerified: false, usdPrice: 0.5 },
];

/** A stand-in for fetch that answers by URL and counts calls. */
function fakeFetch(answer: (url: string) => unknown) {
  const calls: string[] = [];
  const f: FetchLike = async url => {
    calls.push(url);
    const body = answer(url);
    if (body === undefined) return { ok: false, status: 503, json: async () => ({}) };
    return { ok: true, status: 200, json: async () => body };
  };
  return { f, calls };
}

describe("rates", () => {
  it("picks the token that IS the ticker, never a cousin that contains it", () => {
    const sol = pickToken("SOL", jupiter);
    expect(sol?.mint).toBe("So11111111111111111111111111111111111111112");
    expect(sol?.usd).toBe(111.77);
    // Unverified and unknown tickers give nothing rather than a guess.
    expect(pickToken("SOL", [jupiter[2]])).toBeNull();
    expect(pickToken("BONK", jupiter)).toBeNull();
    expect(Rates.tickerOf("$sol")).toBe("SOL");
    expect(Rates.tickerOf("13")).toBeNull();
    expect(Rates.tickerOf("$")).toBeNull();
  });

  it("serves the dollar table and refreshes it hourly, not per keystroke", async () => {
    const { f, calls } = fakeFetch(url => url.includes("frankfurter")
      ? { date: "2026-09-18", rates: { INR: 95.88, EUR: 0.8726 } } : undefined);
    let clock = 0;
    const rates = new Rates(f, () => clock);
    const table = await rates.fiatTable();
    expect(table?.rates.INR).toBe(95.88);
    expect(table?.rates.USD).toBe(1);
    clock = 30 * 60 * 1000;
    await rates.fiatTable();
    expect(calls).toHaveLength(1);
    clock = 2 * 60 * 60 * 1000;
    await rates.fiatTable();
    expect(calls).toHaveLength(2);
  });

  it("keeps yesterday's rate when the source is down, and invents none when it never had one", async () => {
    let down = true;
    const { f } = fakeFetch(() => down ? undefined : { date: "2026-09-18", rates: { INR: 95.88 } });
    let clock = 0;
    const rates = new Rates(f, () => clock);
    expect(await rates.fiatTable()).toBeNull();
    down = false;
    expect((await rates.fiatTable())?.rates.INR).toBe(95.88);
    down = true;
    clock = 3 * 60 * 60 * 1000;
    expect((await rates.fiatTable())?.rates.INR).toBe(95.88);
  });

  it("looks a ticker up on Jupiter and remembers a miss for a minute", async () => {
    const { f, calls } = fakeFetch(url => url.includes("query=SOL") ? jupiter : []);
    let clock = 0;
    const rates = new Rates(f, () => clock);
    expect((await rates.tokenQuote("$sol"))?.usd).toBe(111.77);
    expect(await rates.tokenQuote("lol")).toBeNull();
    await rates.tokenQuote("LOL");
    await rates.tokenQuote("sol");
    expect(calls).toHaveLength(2);
    clock = 61 * 1000;
    await rates.tokenQuote("SOL");
    expect(calls).toHaveLength(3);
  });

  it("answers the strip over the API, five tickers at most", async () => {
    const { f } = fakeFetch(url => url.includes("frankfurter")
      ? { date: "2026-09-18", rates: { INR: 95.88 } }
      : url.includes("query=SOL") ? jupiter : []);
    const app = Fastify();
    ratesRoutes(app, new Rates(f));
    const fiat = await app.inject({ method: "GET", url: "/rates/fiat" });
    expect(fiat.statusCode).toBe(200);
    expect(fiat.json().rates.INR).toBe(95.88);

    const crypto = await app.inject({ method: "GET", url: "/rates/crypto?symbols=$sol,usdc,,13" });
    expect(crypto.statusCode).toBe(200);
    expect(crypto.json().quotes.SOL.usd).toBe(111.77);
    expect(crypto.json().quotes.USDC).toBeUndefined();

    expect((await app.inject({ method: "GET", url: "/rates/crypto" })).statusCode).toBe(400);
    await app.close();
  });
});

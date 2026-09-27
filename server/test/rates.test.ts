import Fastify from "fastify";
import { describe, expect, it } from "vitest";
import { Rates, pickStock, pickToken, type FetchLike } from "../src/lib/rates.js";
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
    // A miss asks twice (the ticker, then its tokenized share), then rests.
    expect(calls).toHaveLength(3);
    clock = 61 * 1000;
    await rates.tokenQuote("SOL");
    expect(calls).toHaveLength(4);
  });

  const apple = [
    { id: "XsbEhLAtcf6HdfpFZ5xEMdqW8nfAvcsP5bdudRLJzJp", symbol: "AAPLx", name: "Apple xStock",
      isVerified: true, usdPrice: 340.3, tags: ["stocks", "xstocks", "verified"], liquidity: 6e5,
      stats24h: { priceChange: 1.5 } },
    { id: "123mYEnRLM2LLYsJW3K6oyYh8uP1fngj732iG638ondo", symbol: "AAPLon", name: "Apple (Ondo Tokenized)",
      isVerified: true, usdPrice: 340.22, tags: ["equities", "verified"], liquidity: 9e5 },
    { id: "9B2sGQFakeAaplx1111111111111111111111111111", symbol: "AAPLX", name: "AAPL Stock with Dividends",
      isVerified: false, usdPrice: 0.01, tags: ["unknown"] },
    { id: "BWMwxBAppleCoin111111111111111111111111111", symbol: "AAPL", name: "Applecoin",
      isVerified: false, usdPrice: 0.02 },
  ];

  it("prices a stock by its verified tokenized share, xStock first", () => {
    const q = pickStock("AAPL", apple);
    expect(q).toMatchObject({ symbol: "AAPL", name: "Apple xStock", usd: 340.3, stock: true, change24h: 1.5 });
    // Ondo's share when there is no xStock; never an unverified look-alike.
    expect(pickStock("AAPL", apple.slice(1))?.name).toBe("Apple (Ondo Tokenized)");
    expect(pickStock("AAPL", apple.slice(2))).toBeNull();
    // A verified token that isn't a stock never prices one.
    expect(pickStock("SOL", [{ ...jupiter[1], symbol: "SOLx" }])).toBeNull();
  });

  it("answers $aapl from Jupiter, asking for the share when the ticker search misses it", async () => {
    const { f, calls } = fakeFetch(url => url.endsWith("query=AAPLx") ? apple.slice(0, 1) : url.endsWith("query=AAPL") ? apple : []);
    const rates = new Rates(f, () => 0);
    expect(await rates.tokenQuote("$aapl")).toMatchObject({ symbol: "AAPL", usd: 340.3, stock: true });
    expect(calls).toHaveLength(1);
    const second = fakeFetch(url => url.endsWith("query=TSLAx")
      ? [{ ...apple[0], id: "XsDoVfTsla111111111111111111111111111111111", symbol: "TSLAx", name: "Tesla xStock", usdPrice: 371.43 }]
      : []);
    const r2 = new Rates(second.f, () => 0);
    expect((await r2.tokenQuote("TSLA"))?.usd).toBe(371.43);
    expect(second.calls.map(c => c.split("query=")[1])).toEqual(["TSLA", "TSLAx"]);
  });

  it("prices a company typed by name: $apple is Apple, $pfizer found by name", async () => {
    const appleCoin = { id: "AppLeCoin11111111111111111111111111111111111", symbol: "APPLE", name: "Apple Coin",
      isVerified: true, usdPrice: 0.003, tags: ["verified"] };
    const pfizer = [{ ...apple[0], id: "PFExPfizer1111111111111111111111111111111111", symbol: "PFEx", name: "Pfizer xStock", usdPrice: 26.48 }];
    const { f, calls } = fakeFetch(url => url.endsWith("query=AAPL") ? apple : url.endsWith("query=APPLE") ? [appleCoin]
      : url.endsWith("query=PFIZER") ? pfizer : []);
    const rates = new Rates(f, () => 0);
    expect(await rates.tokenQuote("$apple")).toMatchObject({ symbol: "APPLE", usd: 340.3, stock: true });
    expect(calls.map(c => c.split("query=")[1])).toEqual(["AAPL"]);
    expect(await rates.tokenQuote("$pfizer")).toMatchObject({ symbol: "PFIZER", usd: 26.48, name: "Pfizer xStock" });
    // A name that is no company and no coin gives nothing.
    expect(await rates.tokenQuote("$banana")).toBeNull();
  });

  it("prices Nvidia, not a meme coin that took its ticker; SOL stays SOL", async () => {
    const meme = { id: "9dwPiStDBwJJqC3QzMnjpJP7xohZbMVmHELFx3uy3KRq", symbol: "NVDA", name: "NVIDIA",
      isVerified: true, usdPrice: 0.00017, tags: ["verified"] };
    const nvdax = { ...apple[0], id: "Xsc9qvGR1efVDFGLrVsmkzv3qi45LTBjeUKSPmx9qEh", symbol: "NVDAx", name: "NVIDIA xStock", usdPrice: 224.52 };
    const { f } = fakeFetch(url => url.endsWith("query=NVDA") ? [meme] : url.endsWith("query=NVDAx") ? [nvdax] : url.endsWith("query=SOL") ? jupiter : []);
    const rates = new Rates(f, () => 0);
    expect(await rates.tokenQuote("$nvda")).toMatchObject({ usd: 224.52, stock: true });
    expect((await rates.tokenQuote("$sol"))?.usd).toBe(111.77);
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

  it("tells a token's address from a wallet's, and says so only when Jupiter answered", async () => {
    const bonk = { id: "DezXAZ8z7PnrnRJjz3wXBoRgixCa6xjnB7YaB1pPB263", symbol: "Bonk", name: "Bonk",
      decimals: 5, usdPrice: 0.0000036, isVerified: true };
    const fresh = { id: "7GCihgDB8fe6KNjn2MYtkzZcRjQy3t9GHdC8uHYmW2hr", symbol: "POPCAT", name: "Popcat",
      decimals: 9, isVerified: false };
    let down = false;
    const { f, calls } = fakeFetch(url => down ? undefined
      : url.includes(bonk.id) ? [bonk] : url.includes(fresh.id) ? [fresh] : []);
    const rates = new Rates(f);
    expect(await rates.tokenAt(bonk.id)).toEqual({ mint: bonk.id, symbol: "Bonk", name: "Bonk", decimals: 5,
      usd: 0.0000036, verified: true });
    // Too new for a price, and not verified: still a token, said plainly.
    expect(await rates.tokenAt(fresh.id)).toEqual({ mint: fresh.id, symbol: "POPCAT", name: "Popcat",
      decimals: 9, verified: false });
    const wallet = "7dHbWXmci3dT8UFYWYZweBLXgycu7Y3iL6trKn1Y7ARj";
    expect(await rates.tokenAt(wallet)).toBeNull();
    await rates.tokenAt(bonk.id);
    expect(calls).toHaveLength(3);
    expect(await rates.tokenAt("not an address")).toBeNull();

    const app = Fastify();
    ratesRoutes(app, rates);
    const hit = await app.inject({ method: "GET", url: `/rates/token?mint=${bonk.id}` });
    expect(hit.json()).toMatchObject({ ok: true, token: { symbol: "Bonk", usd: 0.0000036 } });
    expect((await app.inject({ method: "GET", url: `/rates/token?mint=${wallet}` })).json())
      .toEqual({ ok: true, token: null });
    expect((await app.inject({ method: "GET", url: "/rates/token?mint=0OIl" })).statusCode).toBe(400);
    down = true;
    const other = "9n4nbM75f5Ui33ZbPYXn59EwSgE8CGsHtAeTH5YFeJ9E";
    expect((await app.inject({ method: "GET", url: `/rates/token?mint=${other}` })).statusCode).toBe(503);
    await app.close();
  });
});

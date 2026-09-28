import type { FastifyInstance } from "fastify";
import { Rates } from "../lib/rates.js";

/** Money for the smart strip: the dollar table for a typed amount, a token's
 *  price for a cashtag. Lookups, not model runs — they never touch the plan
 *  meter — and the gate in front of every route already wants a session. */
export function ratesRoutes(app: FastifyInstance, rates: Rates = new Rates()): void {
  app.get("/rates/fiat", async (_req, reply) => {
    const table = await rates.fiatTable();
    if (!table) return reply.code(503).send({ ok: false, error: "Rates unavailable right now" });
    reply.header("cache-control", "private, max-age=600");
    return { ok: true, ...table };
  });

  /** ?symbols=SOL,USDC — at most five, unknown ones simply absent. */
  app.get("/rates/crypto", async (req, reply) => {
    const raw = (req.query as { symbols?: string }).symbols ?? "";
    const symbols = [...new Set(raw.split(",").map(s => Rates.tickerOf(s))
      .filter((s): s is string => s !== null))].slice(0, 5);
    if (symbols.length === 0) return reply.code(400).send({ ok: false, error: "symbols?" });
    const quotes: Record<string, { usd: number; name: string; mint: string; ticker: string }> = {};
    await Promise.all(symbols.map(async symbol => {
      const q = await rates.tokenQuote(symbol);
      if (q) quotes[symbol] = { usd: q.usd, name: q.name, mint: q.mint, ticker: q.ticker ?? symbol };
    }));
    reply.header("cache-control", "private, max-age=60");
    return { ok: true, quotes };
  });

  /** ?mint=<address> — a copied address: the token there, or null when
   *  there is none (then it is someone's wallet). */
  app.get("/rates/token", async (req, reply) => {
    const mint = ((req.query as { mint?: string }).mint ?? "").trim();
    if (!Rates.isAddress(mint)) return reply.code(400).send({ ok: false, error: "mint?" });
    try {
      const token = await rates.tokenAt(mint);
      reply.header("cache-control", "private, max-age=60");
      return { ok: true, token };
    } catch {
      return reply.code(503).send({ ok: false, error: "Token lookup unavailable right now" });
    }
  });
}

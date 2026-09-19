/** Live money for the smart strip: what a typed amount is worth where the
 *  person is, and what a cashtag's token trades at.
 *
 *  Fiat comes from the ECB's daily reference rates (Frankfurter: free, no
 *  key) against the dollar; tokens come from Jupiter's verified token list,
 *  which carries a live dollar price. Both are cached here so a keyboard
 *  never talks to either service and a burst of typing costs nothing.
 *  Nothing is invented: when a source is down and nothing is cached there
 *  is no rate, and the strip shows no chip. */

export interface FiatTable {
  /** Per one dollar: `rates.INR = 95.88` means $1 = ₹95.88. USD is 1. */
  base: "USD";
  date: string;
  rates: Record<string, number>;
}

export interface TokenQuote {
  symbol: string;
  name: string;
  mint: string;
  usd: number;
}

/** What is needed of fetch, so tests can hand in a stand-in. */
export type FetchLike = (url: string, init?: { signal?: AbortSignal }) =>
  Promise<{ ok: boolean; status?: number; json(): Promise<unknown> }>;

const FX_URL = "https://api.frankfurter.dev/v1/latest?base=USD";
const JUP_SEARCH = "https://lite-api.jup.ag/tokens/v2/search?query=";
const FX_TTL = 60 * 60 * 1000;   // the ECB publishes once a day; an hour is plenty
const TOKEN_TTL = 60 * 1000;     // a token price moves every block

export class Rates {
  private fiat?: { table: FiatTable; at: number };
  private fiatInFlight?: Promise<FiatTable | null>;
  private tokens = new Map<string, { quote: TokenQuote | null; at: number }>();

  constructor(
    private fetchImpl: FetchLike = fetch as unknown as FetchLike,
    private now: () => number = Date.now,
  ) {}

  /** Every currency the ECB quotes, per dollar. One request in flight at a
   *  time: a keyboard opening on ten phones at once must not become ten
   *  calls upstream. */
  async fiatTable(): Promise<FiatTable | null> {
    if (this.fiat && this.now() - this.fiat.at < FX_TTL) return this.fiat.table;
    if (!this.fiatInFlight) {
      this.fiatInFlight = this.loadFiat().finally(() => { this.fiatInFlight = undefined; });
    }
    return this.fiatInFlight;
  }

  private async loadFiat(): Promise<FiatTable | null> {
    try {
      const res = await this.fetchImpl(FX_URL, { signal: AbortSignal.timeout(5000) });
      if (!res.ok) throw new Error(`fx ${res.status ?? ""}`);
      const body = await res.json() as { date?: string; rates?: Record<string, unknown> };
      const rates: Record<string, number> = {};
      for (const [code, value] of Object.entries(body.rates ?? {})) {
        if (typeof value === "number" && value > 0) rates[code] = value;
      }
      if (Object.keys(rates).length === 0) throw new Error("fx empty");
      const table: FiatTable = { base: "USD", date: body.date ?? "", rates: { ...rates, USD: 1 } };
      this.fiat = { table, at: this.now() };
      return table;
    } catch {
      // Yesterday's rate beats no rate; nothing beats a made-up one.
      return this.fiat?.table ?? null;
    }
  }

  /** "$sol" / "SOL" → "SOL"; anything that is not a ticker → null. */
  static tickerOf(raw: string): string | null {
    const t = raw.trim().replace(/^\$/, "").toUpperCase();
    // Letters with maybe digits ("SOL", "W3D"); a bare number is an amount.
    return /^(?=.*[A-Z])[A-Z0-9]{2,10}$/.test(t) ? t : null;
  }

  /** The dollar price of the verified token behind a ticker. A miss is
   *  remembered for a minute too, so "$lol" typed letter by letter is one
   *  lookup, not five. */
  async tokenQuote(raw: string): Promise<TokenQuote | null> {
    const symbol = Rates.tickerOf(raw);
    if (!symbol) return null;
    const hit = this.tokens.get(symbol);
    if (hit && this.now() - hit.at < TOKEN_TTL) return hit.quote;
    let quote: TokenQuote | null;
    try {
      const res = await this.fetchImpl(JUP_SEARCH + encodeURIComponent(symbol),
        { signal: AbortSignal.timeout(5000) });
      if (!res.ok) throw new Error(`jup ${res.status ?? ""}`);
      const list = await res.json();
      quote = pickToken(symbol, Array.isArray(list) ? list : []);
    } catch {
      quote = hit?.quote ?? null;
    }
    this.tokens.set(symbol, { quote, at: this.now() });
    return quote;
  }
}

interface JupToken {
  id?: string; symbol?: string; name?: string; isVerified?: boolean;
  usdPrice?: number; tags?: string[]; liquidity?: number;
}

/** The verified token that IS the ticker — never a staked or wrapped
 *  cousin whose symbol merely contains it (SOL must not become JupSOL).
 *  Among exact matches: the one the ecosystem marks major, then strict,
 *  then the deepest liquidity. */
export function pickToken(symbol: string, list: unknown[]): TokenQuote | null {
  const exact = (list as JupToken[]).filter(t =>
    t.isVerified === true && typeof t.usdPrice === "number" && t.usdPrice > 0
    && typeof t.id === "string" && (t.symbol ?? "").toUpperCase() === symbol);
  if (exact.length === 0) return null;
  const rank = (t: JupToken) =>
    (t.tags?.includes("major") ? 2 : 0) + (t.tags?.includes("strict") ? 1 : 0);
  exact.sort((a, b) => rank(b) - rank(a) || (b.liquidity ?? 0) - (a.liquidity ?? 0));
  const t = exact[0];
  return { symbol, name: t.name ?? symbol, mint: t.id as string, usd: t.usdPrice as number };
}

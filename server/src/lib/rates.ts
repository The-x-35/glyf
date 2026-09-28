/** Live money for the smart strip: what a typed amount is worth where the
 *  person is, and what a cashtag's token trades at.
 *
 *  Fiat comes from the ECB's daily reference rates (Frankfurter: free, no
 *  key) against the dollar; tokens come from Jupiter's verified token list,
 *  which carries a live dollar price. Stocks come from the same list: a
 *  ticker with no token of its own ("$aapl") is priced by its verified
 *  tokenized share on Solana (Apple xStock, AAPLx), which tracks it. Both are cached here so a keyboard
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
  /** Priced through a tokenized share (xStocks, Ondo) rather than a token. */
  stock?: boolean;
  /** Percent over the last day, when Jupiter has it. */
  change24h?: number;
  /** A coin the ecosystem tags major (SOL): it keeps its ticker even
   *  where a stock shares it. */
  major?: boolean;
  /** The market's own ticker, whatever was typed: "$apple" and "$appl"
   *  are both AAPL. */
  ticker?: string;
}

/** A token found by its address (a contract address someone copied). */
export interface MintQuote {
  mint: string;
  symbol: string;
  name: string;
  decimals: number;
  /** Missing for a token too new to have a price. */
  usd?: number;
  /** On Jupiter's verified list. An unverified token can still be bought;
   *  the app says so first. */
  verified: boolean;
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
  private mints = new Map<string, { token: MintQuote | null; at: number }>();

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

  /** "$sol" / "SOL" → "SOL", "$apple" → "APPLE"; anything that is not a
   *  ticker or a name → null. */
  static tickerOf(raw: string): string | null {
    const t = raw.trim().replace(/^\$/, "").toUpperCase();
    // Letters with maybe digits ("SOL", "W3D"); a bare number is an amount.
    return /^(?=.*[A-Z])[A-Z0-9]{2,14}$/.test(t) ? t : null;
  }

  /** The dollar price of the verified token behind a ticker. A miss is
   *  remembered for a minute too, so "$lol" typed letter by letter is one
   *  lookup, not five. */
  async tokenQuote(raw: string): Promise<TokenQuote | null> {
    const symbol = Rates.tickerOf(raw);
    if (!symbol) return null;
    // "$apple" is Apple: a known name goes straight to its ticker, so a coin
    // that took the name never answers for the company.
    const known = NAMES[symbol];
    if (known && known !== symbol) {
      const quote = await this.tokenQuote(known);
      // Bitcoin trades here as WBTC, but people read BTC.
      return quote ? { ...quote, symbol, ticker: known === "WBTC" ? "BTC" : quote.ticker ?? known } : null;
    }
    const hit = this.tokens.get(symbol);
    if (hit && this.now() - hit.at < TOKEN_TTL) return hit.quote;
    let quote: TokenQuote | null;
    try {
      const list = await this.search(symbol);
      const token = pickToken(symbol, list);
      // A stock beats a coin that merely shares its ticker (a verified meme
      // coin called NVDA is not Nvidia); only a major coin keeps its name.
      let stock = pickStock(symbol, list);
      if (!stock && !token?.major && !symbol.endsWith("X")) stock = pickStock(symbol, await this.search(`${symbol}x`));
      quote = token?.major ? token : stock ?? token;
      // Any other company typed by name ("$pfizer"): its tokenized share.
      if (!quote && symbol.length >= 3) quote = pickStockByName(symbol, list);
      // Half a name, or the usual slip ("$appl" on the way to "$apple", or
      // for AAPL): Jupiter's own best match, when the company starts so.
      if (!quote && symbol.length >= 4) quote = pickStockByPrefix(symbol, list);
    } catch {
      quote = hit?.quote ?? null;
    }
    this.tokens.set(symbol, { quote, at: this.now() });
    return quote;
  }

  /** The token at a Solana address, or null when Jupiter has none there
   *  (a wallet, in a chat). Throws when Jupiter can't be asked: "not a
   *  token" is never said on a guess. */
  async tokenAt(address: string): Promise<MintQuote | null> {
    if (!Rates.isAddress(address)) return null;
    const hit = this.mints.get(address);
    if (hit && this.now() - hit.at < TOKEN_TTL) return hit.token;
    const t = (await this.search(address) as JupToken[]).find(x => x.id === address);
    const token: MintQuote | null = t && typeof t.symbol === "string" && typeof t.decimals === "number"
      ? { mint: address, symbol: t.symbol, name: t.name ?? t.symbol, decimals: t.decimals,
          ...(typeof t.usdPrice === "number" && t.usdPrice > 0 ? { usd: t.usdPrice } : {}),
          verified: t.isVerified === true }
      : null;
    this.mints.set(address, { token, at: this.now() });
    return token;
  }

  /** Base58, 32 to 44 characters: the shape of every Solana address. */
  static isAddress(s: string): boolean {
    return /^[1-9A-HJ-NP-Za-km-z]{32,44}$/.test(s);
  }

  private async search(query: string): Promise<unknown[]> {
    const res = await this.fetchImpl(JUP_SEARCH + encodeURIComponent(query),
      { signal: AbortSignal.timeout(5000) });
    if (!res.ok) throw new Error(`jup ${res.status ?? ""}`);
    const list = await res.json();
    return Array.isArray(list) ? list : [];
  }
}

interface JupToken {
  id?: string; symbol?: string; name?: string; isVerified?: boolean; decimals?: number;
  usdPrice?: number; tags?: string[]; liquidity?: number;
  stats24h?: { priceChange?: number };
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
  return { symbol, name: t.name ?? symbol, mint: t.id as string, usd: t.usdPrice as number,
    ticker: symbol, ...(t.tags?.includes("major") ? { major: true } : {}) };
}

/** A share's own ticker: AAPLx and AAPLon are both AAPL. */
function shareTicker(symbol: string | undefined, fallback: string): string {
  const s = (symbol ?? "").replace(/(x|on)$/, "");
  return /^[A-Za-z0-9.]{1,10}$/.test(s) ? s.toUpperCase() : fallback;
}

const isShare = (t: JupToken) =>
  t.isVerified === true && typeof t.usdPrice === "number" && t.usdPrice > 0 && typeof t.id === "string"
  && (t.tags ?? []).some(tag => tag === "stocks" || tag === "equities" || tag === "xstocks");

/** A company half typed or misspelt ("APPL" on the way to "$apple", or the
 *  usual slip for AAPL): Jupiter ranks its search, so the first verified
 *  share whose company name starts with what was typed. Four letters at
 *  least, so "$tes" never guesses. */
export function pickStockByPrefix(prefix: string, list: unknown[]): TokenQuote | null {
  const want = prefix.toLowerCase();
  const t = (list as JupToken[]).find(t => isShare(t) && (t.name ?? "").toLowerCase().startsWith(want));
  if (!t) return null;
  const change = t.stats24h?.priceChange;
  return { symbol: prefix, name: t.name ?? prefix, mint: t.id as string, usd: t.usdPrice as number, stock: true,
    ticker: shareTicker(t.symbol, prefix),
    ...(typeof change === "number" && Number.isFinite(change) ? { change24h: change } : {}) };
}

/** Names people type instead of tickers. The common ones map straight to
 *  the ticker (Bitcoin trades on Solana as Wrapped BTC); any other company
 *  is found by name among the tokenized stocks. */
export const NAMES: Record<string, string> = {
  APPLE: "AAPL", TESLA: "TSLA", NVIDIA: "NVDA", MICROSOFT: "MSFT", GOOGLE: "GOOGL",
  ALPHABET: "GOOGL", AMAZON: "AMZN", FACEBOOK: "META", NETFLIX: "NFLX", COINBASE: "COIN",
  MICROSTRATEGY: "MSTR", PALANTIR: "PLTR", ROBINHOOD: "HOOD", GAMESTOP: "GME", INTEL: "INTC",
  BROADCOM: "AVGO", ORACLE: "ORCL", SALESFORCE: "CRM", ADOBE: "ADBE", DISNEY: "DIS",
  NIKE: "NKE", WALMART: "WMT", COSTCO: "COST", MCDONALDS: "MCD", COCACOLA: "KO",
  PEPSI: "PEP", JPMORGAN: "JPM", SP500: "SPY", NASDAQ: "QQQ",
  BITCOIN: "WBTC", BTC: "WBTC", ETHEREUM: "ETH", ETHER: "ETH", SOLANA: "SOL", JUPITER: "JUP",
};

/** A stock by its tokenized share: the verified xStock ("AAPLx") first,
 *  then Ondo's ("AAPLon"), then the deepest. Only tokens Jupiter tags as
 *  stocks count, so a meme coin called AAPLX never prices Apple. */
export function pickStock(symbol: string, list: unknown[]): TokenQuote | null {
  const shares = (list as JupToken[]).filter(t => {
    const sym = (t.symbol ?? "").toUpperCase();
    return t.isVerified === true && typeof t.usdPrice === "number" && t.usdPrice > 0
      && typeof t.id === "string" && (sym === `${symbol}X` || sym === `${symbol}ON`)
      && (t.tags ?? []).some(tag => tag === "stocks" || tag === "equities" || tag === "xstocks");
  });
  if (shares.length === 0) return null;
  const rank = (t: JupToken) => ((t.symbol ?? "").toUpperCase() === `${symbol}X` ? 1 : 0);
  shares.sort((a, b) => rank(b) - rank(a) || (b.liquidity ?? 0) - (a.liquidity ?? 0));
  const t = shares[0];
  const change = t.stats24h?.priceChange;
  return { symbol, name: t.name ?? symbol, mint: t.id as string, usd: t.usdPrice as number, stock: true,
    ticker: symbol,
    ...(typeof change === "number" && Number.isFinite(change) ? { change24h: change } : {}) };
}

/** A company typed by name ("PFIZER"): the verified tokenized share whose
 *  name is that company ("Pfizer xStock"), xStock first. Stocks only, so a
 *  coin named after anything never answers. */
export function pickStockByName(name: string, list: unknown[]): TokenQuote | null {
  const want = name.toLowerCase();
  const shares = (list as JupToken[]).filter(t => {
    if (t.isVerified !== true || typeof t.usdPrice !== "number" || t.usdPrice <= 0 || typeof t.id !== "string") return false;
    if (!(t.tags ?? []).some(tag => tag === "stocks" || tag === "equities" || tag === "xstocks")) return false;
    const company = (t.name ?? "").toLowerCase().replace(/\s*(xstock|\(ondo tokenized\)|-.*)$/, "").trim();
    return company === want || company.split(/[\s,.]+/)[0] === want;
  });
  if (shares.length === 0) return null;
  const rank = (t: JupToken) => ((t.symbol ?? "").endsWith("x") ? 1 : 0);
  shares.sort((a, b) => rank(b) - rank(a) || (b.liquidity ?? 0) - (a.liquidity ?? 0));
  const t = shares[0];
  const change = t.stats24h?.priceChange;
  return { symbol: name, name: t.name ?? name, mint: t.id as string, usd: t.usdPrice as number, stock: true,
    ticker: shareTicker(t.symbol, name),
    ...(typeof change === "number" && Number.isFinite(change) ? { change24h: change } : {}) };
}

import { encodeFunctionData, formatUnits, getAddress, parseAbi, parseUnits } from "viem";
import type { FetchFn } from "./evm.js";

/**
 * NEAR Intents through 1Click (docs/NEAR-SPEC.md): "swap 20 usdc on base to
 * sol", "send 5 usdc to alice.near" and every other trade that touches a
 * chain Uniswap, Jupiter and Flash can't reach.
 *
 * 1Click quotes a trade and hands back a deposit address on the origin
 * chain. The phone's wallet (MetaMask on EVM chains, Phantom on Solana)
 * sends the coins there and 1Click does the rest: it swaps inside NEAR
 * Intents and pays the recipient on the destination chain, or refunds the
 * person's own origin address. Nothing here holds a key or a coin; the
 * deposit is built here as a plain transaction the wallet signs.
 *
 * 1Click is called keyless (it then keeps 0.2% of each swap) with
 * `referral: "glyf"`; NEAR_INTENTS_JWT, when set, goes as Bearer and drops
 * that fee. The token list is kept ten minutes.
 */

export const ONECLICK = "https://1click.chaindefuser.com";
export const EXPLORER = "https://explorer.near-intents.org/transactions/";
export const VENUE = "NEAR Intents";
export const REFERRAL = "glyf";

/** How the phone can pay a deposit on this chain: its EVM wallet, its
 *  Solana wallet, or by hand from any wallet ("manual"). */
export type ChainKind = "evm" | "sol" | "other";

export interface NearChain {
  /** Glyf's word for the chain, as the keyboard and the app say it. */
  key: string;
  /** 1Click's `blockchain`. */
  oneClick: string;
  name: string;
  kind: ChainKind;
  chainId?: number;
  /** The chain's own coin. */
  native: string;
  /** A valid address for a dry quote, which needs a refundTo and a
   *  recipient but moves nothing (1Click's own examples, a BIP-173 test
   *  address, a CIP-19 test vector, well-known public accounts). */
  placeholder: string;
  /** A deposit that can take an hour to confirm gets a longer deadline. */
  slow?: boolean;
}

const EVM_PLACEHOLDER = "0x2527D02599Ba641c19FEa793cD0F167589a0f10D";

/** The table in docs/NEAR-SPEC.md ("Chains"). Placeholders checked against
 *  1Click's dry quotes on 2026-11-12. */
export const NEAR_CHAINS: Record<string, NearChain> = {
  base: { key: "base", oneClick: "base", name: "Base", kind: "evm", chainId: 8453, native: "ETH", placeholder: EVM_PLACEHOLDER },
  ethereum: { key: "ethereum", oneClick: "eth", name: "Ethereum", kind: "evm", chainId: 1, native: "ETH", placeholder: EVM_PLACEHOLDER },
  arbitrum: { key: "arbitrum", oneClick: "arb", name: "Arbitrum", kind: "evm", chainId: 42161, native: "ETH", placeholder: EVM_PLACEHOLDER },
  optimism: { key: "optimism", oneClick: "op", name: "OP Mainnet", kind: "evm", chainId: 10, native: "ETH", placeholder: EVM_PLACEHOLDER },
  polygon: { key: "polygon", oneClick: "pol", name: "Polygon", kind: "evm", chainId: 137, native: "POL", placeholder: EVM_PLACEHOLDER },
  bsc: { key: "bsc", oneClick: "bsc", name: "BNB Chain", kind: "evm", chainId: 56, native: "BNB", placeholder: EVM_PLACEHOLDER },
  avalanche: { key: "avalanche", oneClick: "avax", name: "Avalanche", kind: "evm", chainId: 43114, native: "AVAX", placeholder: EVM_PLACEHOLDER },
  gnosis: { key: "gnosis", oneClick: "gnosis", name: "Gnosis", kind: "evm", chainId: 100, native: "XDAI", placeholder: EVM_PLACEHOLDER },
  solana: { key: "solana", oneClick: "sol", name: "Solana", kind: "sol", native: "SOL", placeholder: "13QkxhNMrTPxoCkRdYdJ65tFuwXPhL5gLS2Z5Nr6gjRK" },
  near: { key: "near", oneClick: "near", name: "NEAR", kind: "other", native: "NEAR", placeholder: "0".repeat(64) },
  bitcoin: { key: "bitcoin", oneClick: "btc", name: "Bitcoin", kind: "other", native: "BTC", placeholder: "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh", slow: true },
  zcash: { key: "zcash", oneClick: "zec", name: "Zcash", kind: "other", native: "ZEC", placeholder: "t1Hsc1LR8yKnbbe3twRp88p6vFfC5t7DLbs", slow: true },
  ton: { key: "ton", oneClick: "ton", name: "TON", kind: "other", native: "TON", placeholder: "EQCxE6mUtQJKFnGfaROTKOt1lZbDiiX1kCixRv7Nw2Id_sDs" },
  tron: { key: "tron", oneClick: "tron", name: "Tron", kind: "other", native: "TRX", placeholder: "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t" },
  xrp: { key: "xrp", oneClick: "xrp", name: "XRP Ledger", kind: "other", native: "XRP", placeholder: "rEb8TK3gBgk5auZkwc6sHnwrGVJH8DuaLh" },
  dogecoin: { key: "dogecoin", oneClick: "doge", name: "Dogecoin", kind: "other", native: "DOGE", placeholder: "DH5yaieqoZN36fDVciNyRueRGvGLR3mr7L", slow: true },
  litecoin: { key: "litecoin", oneClick: "ltc", name: "Litecoin", kind: "other", native: "LTC", placeholder: "LQTpS3VaYTjCr4s9Y1t5zbeY26zevf7Fb3", slow: true },
  sui: { key: "sui", oneClick: "sui", name: "Sui", kind: "other", native: "SUI", placeholder: "0x" + "0".repeat(63) + "5" },
  aptos: { key: "aptos", oneClick: "aptos", name: "Aptos", kind: "other", native: "APT", placeholder: "0x" + "0".repeat(63) + "1" },
  stellar: { key: "stellar", oneClick: "stellar", name: "Stellar", kind: "other", native: "XLM", placeholder: "GA5ZSEJYB37JRC5AVCIA5MOP4RHTM335X2KGX3IHOJAPP5RE34K4KZVN" },
  cardano: { key: "cardano", oneClick: "cardano", name: "Cardano", kind: "other", native: "ADA", slow: true,
    placeholder: "addr1qx2fxv2umyhttkxyxp8x0dlpdt3k6cwng5pxj3jhsydzer3n0d3vllmyqwsx5wktcd8cc3sq835lu7drv2xwl2wywfgse35a3x" },
};

/** What people type for a chain, beside its key and 1Click's code. */
export const CHAIN_WORDS: Record<string, string> = {
  eth: "ethereum", mainnet: "ethereum", arb: "arbitrum", op: "optimism", pol: "polygon", matic: "polygon",
  bnb: "bsc", binance: "bsc", avax: "avalanche", xdai: "gnosis", sol: "solana", btc: "bitcoin", zec: "zcash",
  trx: "tron", ripple: "xrp", doge: "dogecoin", ltc: "litecoin", apt: "aptos", xlm: "stellar", ada: "cardano",
};

export function nearChainOf(word: unknown): NearChain | null {
  if (typeof word !== "string") return null;
  const w = word.trim().toLowerCase();
  if (NEAR_CHAINS[w]) return NEAR_CHAINS[w];
  if (CHAIN_WORDS[w]) return NEAR_CHAINS[CHAIN_WORDS[w]];
  return Object.values(NEAR_CHAINS).find(c => c.oneClick === w) ?? null;
}

/** The chain a coin lives on natively: "btc" is Bitcoin, "near" is NEAR.
 *  EVM gas coins (ETH on five chains) have no single home. */
export function homeChainOf(symbol: string): NearChain | null {
  const s = symbol.trim().replace(/^\$/, "").toUpperCase();
  return Object.values(NEAR_CHAINS).find(c => c.native === s && c.kind !== "evm") ?? null;
}

const B58 = "[1-9A-HJ-NP-Za-km-z]";
/** NEAR account ids: 2–64 characters, lowercase parts joined by dots, each
 *  part letters and digits joined by single - or _ (64-hex implicit
 *  accounts fit too). */
export const NEAR_ACCOUNT = /^(?=.{2,64}$)(([a-z\d]+[-_])*[a-z\d]+\.)*([a-z\d]+[-_])*[a-z\d]+$/;
export const NEAR_IMPLICIT = /^[0-9a-f]{64}$/;

/** What an address on each chain looks like, by format only (a checksum is
 *  the wallet's and 1Click's to check). */
const FORMATS: Record<string, RegExp> = {
  evm: /^0x[0-9a-fA-F]{40}$/,
  solana: new RegExp(`^${B58}{32,44}$`),
  near: NEAR_ACCOUNT,
  bitcoin: new RegExp(`^(bc1[ac-hj-np-z02-9]{11,71}|[13]${B58}{25,34})$`),
  zcash: new RegExp(`^t[13]${B58}{33}$`),
  ton: /^([EUk]Q[A-Za-z0-9_-]{46}|-?\d:[0-9a-fA-F]{64})$/,
  tron: new RegExp(`^T${B58}{33}$`),
  xrp: new RegExp(`^r${B58}{24,34}$`),
  dogecoin: new RegExp(`^[DA9]${B58}{25,33}$`),
  litecoin: new RegExp(`^(ltc1[ac-hj-np-z02-9]{11,71}|[LM3]${B58}{25,33})$`),
  sui: /^0x[0-9a-fA-F]{64}$/,
  aptos: /^0x[0-9a-fA-F]{1,64}$/,
  stellar: /^G[A-Z2-7]{55}$/,
  cardano: /^addr1[0-9a-z]{50,120}$/,
};

/** True when `address` has the shape of an address on `chain`. */
export function addressFits(chain: NearChain, address: string): boolean {
  const format = chain.kind === "evm" ? FORMATS.evm : FORMATS[chain.key];
  return Boolean(format?.test(address.trim()));
}

/** Which chains an address could be on, for a chain-mismatch message. */
export function chainsFor(address: string): NearChain[] {
  return Object.values(NEAR_CHAINS).filter(c => addressFits(c, address));
}

export interface IntentToken {
  assetId: string;
  decimals: number;
  blockchain: string;
  symbol: string;
  price?: number;
  contractAddress?: string;
}

export interface Side {
  symbol: string;
  chain: string;
  decimals: number;
  assetId: string;
  address: string | null;
}

export interface QuoteInput {
  sell: string;
  sellChain: string;
  buy: string;
  buyChain: string;
  /** Whole coins: of `sell` when exact is "in", of `buy` when "out". */
  amount: string;
  exact?: "in" | "out";
  refundTo?: string;
  recipient?: string;
  /** Percent; 1 unless said. */
  slippage?: number;
}

export type Deposit =
  | { kind: "erc20"; chain: string; chainId: number; to: string; data: string; value: "0"; amountBase: string; token: string; depositAddress: string }
  | { kind: "native"; chain: string; chainId: number; to: string; data: "0x"; value: string; amountBase: string; depositAddress: string }
  | { kind: "sol"; chain: "solana"; to: string; lamports: string; amountBase: string; depositAddress: string }
  | { kind: "spl"; chain: "solana"; to: string; mint: string; amountBase: string; decimals: number; depositAddress: string }
  | { kind: "manual"; chain: string; to: string; memo: string | null; amount: string; amountBase: string; symbol: string; depositAddress: string };

export interface QuoteAnswer {
  ok: true;
  dry: boolean;
  venue: typeof VENUE;
  exact: "in" | "out";
  sell: Side;
  buy: Side;
  amountIn: string;
  amountInBase: string;
  amountInUsd: string | null;
  amountOut: string;
  amountOutBase: string;
  amountOutUsd: string | null;
  minAmountOut: string;
  timeSeconds: number | null;
  depositAddress: string | null;
  depositMemo: string | null;
  deadline: string | null;
  deposit: Deposit | null;
  explorer: string | null;
  /** The recipient and refund address 1Click was given (placeholders on a
   *  dry quote are never shown). */
  recipient: string | null;
  refundTo: string | null;
}

export type SwapStatus = "PENDING_DEPOSIT" | "INCOMPLETE_DEPOSIT" | "PROCESSING" | "SUCCESS" | "REFUNDED" | "FAILED";

export interface StatusAnswer {
  ok: true;
  status: SwapStatus;
  done: boolean;
  amountOut?: string;
  refunded?: string;
  destinationTx?: { hash: string; url: string };
  originTx?: { hash: string; url: string };
  explorer: string;
}

/** A failure with words for the person and the HTTP status to send them. */
export class IntentsError extends Error {
  constructor(readonly status: 400 | 404 | 502, message: string) {
    super(message);
  }
}

const ERC20_TRANSFER = parseAbi(["function transfer(address to, uint256 amount) returns (bool)"]);
const TOKENS_KEEP_MS = 10 * 60 * 1000;

/** Wrapped NEAR is what 1Click lists for NEAR itself, and TON's own coin is
 *  listed as GRAM: the person typed and reads the coin's name. */
const LISTED_AS: Record<string, Record<string, string>> = { near: { NEAR: "WNEAR" }, ton: { TON: "GRAM" } };
const SHOWN_AS: Record<string, string> = { WNEAR: "NEAR", GRAM: "TON" };

/** The best listing of `symbol` on `chain`, or null. An asset id or a
 *  contract address picks that very token. */
export function pickToken(tokens: IntentToken[], chain: NearChain, symbol: string): IntentToken | null {
  const raw = symbol.trim().replace(/^\$/, "");
  const on = tokens.filter(t => t.blockchain === chain.oneClick && !/DEPRECATED/i.test(t.symbol));
  if (/^(nep141|nep245|1cs_v1):/.test(raw)) return on.find(t => t.assetId === raw) ?? null;
  if (raw.length > 20) return on.find(t => t.contractAddress?.toLowerCase() === raw.toLowerCase()) ?? null;
  const upper = raw.toUpperCase();
  const want = LISTED_AS[chain.key]?.[upper] ?? upper;
  const native = upper === chain.native;
  // nep141 bridged on the chain itself first (*.omft.near), then other
  // nep141s, then the HOT bridge's nep245s, then 1Click's own ids.
  const rank = (t: IntentToken) => (native && !t.contractAddress ? 0 : 10)
    + (t.assetId.startsWith("nep141:") ? (t.assetId.endsWith(".omft.near") ? 0 : 1) : t.assetId.startsWith("nep245:") ? 2 : 3);
  const rows = on.filter(t => t.symbol.toUpperCase() === want).sort((a, b) => rank(a) - rank(b));
  return rows[0] ?? null;
}

function side(t: IntentToken, chain: NearChain): Side {
  const symbol = SHOWN_AS[t.symbol.toUpperCase()] ?? t.symbol;
  return { symbol, chain: chain.key, decimals: t.decimals, assetId: t.assetId, address: t.contractAddress ?? null };
}

/** Whole coins as a decimal string, without trailing zeros. */
const whole = (base: string | bigint, decimals: number) => formatUnits(BigInt(base), decimals);

/** Dollars as 1Click says them ("19.991420000000"), to the cent. */
function usd(value: unknown): string | null {
  const n = Number(value);
  return Number.isFinite(n) && value !== "" && value !== null && value !== undefined ? n.toFixed(2) : null;
}

/** The plain transaction (or instructions) that pays the deposit. */
export function depositFor(chain: NearChain, token: IntentToken, depositAddress: string, amountBase: string,
  memo: string | null): Deposit {
  if (chain.kind === "evm" && chain.chainId && FORMATS.evm.test(depositAddress)) {
    const to = getAddress(depositAddress);
    if (token.contractAddress) {
      const tokenAddress = getAddress(token.contractAddress);
      return { kind: "erc20", chain: chain.key, chainId: chain.chainId, to: tokenAddress, value: "0", amountBase,
        token: tokenAddress, depositAddress: to,
        data: encodeFunctionData({ abi: ERC20_TRANSFER, functionName: "transfer", args: [to, BigInt(amountBase)] }) };
    }
    return { kind: "native", chain: chain.key, chainId: chain.chainId, to, value: amountBase, data: "0x", amountBase, depositAddress: to };
  }
  if (chain.kind === "sol") {
    if (!token.contractAddress) return { kind: "sol", chain: "solana", to: depositAddress, lamports: amountBase, amountBase, depositAddress };
    return { kind: "spl", chain: "solana", to: depositAddress, mint: token.contractAddress, amountBase, decimals: token.decimals, depositAddress };
  }
  return { kind: "manual", chain: chain.key, to: depositAddress, memo, amount: whole(amountBase, token.decimals), amountBase,
    symbol: SHOWN_AS[token.symbol.toUpperCase()] ?? token.symbol, depositAddress };
}

/** 1Click's statuses in the spec's words: a deposit 1Click has seen but not
 *  yet confirmed (KNOWN_DEPOSIT_TX) is already on its way. */
export function statusOf(raw: unknown): SwapStatus {
  switch (raw) {
    case "PENDING_DEPOSIT": case "INCOMPLETE_DEPOSIT": case "PROCESSING": case "SUCCESS": case "REFUNDED": case "FAILED":
      return raw;
    case "KNOWN_DEPOSIT_TX":
      return "PROCESSING";
    default:
      return "PENDING_DEPOSIT";
  }
}

export interface NearIntentsDeps {
  fetchImpl?: FetchFn;
  /** NEAR_INTENTS_JWT unless a test passes one ("" = keyless). */
  jwt?: () => string;
  now?: () => number;
}

export class NearIntents {
  private readonly fetchImpl: FetchFn;
  private readonly jwt: () => string;
  private readonly now: () => number;
  private list: { at: number; tokens: IntentToken[] } | null = null;
  private listing: Promise<IntentToken[]> | null = null;

  constructor(deps: NearIntentsDeps = {}) {
    this.fetchImpl = deps.fetchImpl ?? fetch;
    this.jwt = deps.jwt ?? (() => (process.env.NEAR_INTENTS_JWT ?? "").trim());
    this.now = deps.now ?? Date.now;
  }

  private headers(json: boolean): Record<string, string> {
    const jwt = this.jwt();
    return { accept: "application/json", ...(json ? { "content-type": "application/json" } : {}),
      ...(jwt ? { authorization: `Bearer ${jwt}` } : {}) };
  }

  /** One call to 1Click: its JSON, or IntentsError with 1Click's own words
   *  for a 4xx (502 for anything else). */
  private async call(path: string, init: { method?: string; body?: unknown } = {}): Promise<Record<string, any>> {
    let res: Response;
    try {
      res = await this.fetchImpl(`${ONECLICK}${path}`, {
        method: init.method ?? "GET",
        headers: this.headers(init.body !== undefined),
        ...(init.body !== undefined ? { body: JSON.stringify(init.body) } : {}),
        signal: AbortSignal.timeout(15_000),
      });
    } catch {
      throw new IntentsError(502, "NEAR Intents didn't answer. Try again in a moment");
    }
    const json = await res.json().catch(() => ({})) as Record<string, any>;
    if (res.ok) return json;
    const message = typeof json?.message === "string" ? json.message.slice(0, 200) : "";
    if (res.status === 404) throw new IntentsError(404, message || "NEAR Intents doesn't know that");
    // A refused JWT is the server's problem, not the person's.
    if (res.status >= 400 && res.status < 500 && res.status !== 401 && res.status !== 403 && message) {
      throw new IntentsError(400, message);
    }
    throw new IntentsError(502, "NEAR Intents didn't answer. Try again in a moment");
  }

  /** Every token 1Click can swap, kept ten minutes. */
  async tokens(): Promise<IntentToken[]> {
    const now = this.now();
    if (this.list && now - this.list.at < TOKENS_KEEP_MS) return this.list.tokens;
    this.listing ??= (async () => {
      try {
        const rows = await this.call("/v0/tokens");
        const tokens = (Array.isArray(rows) ? rows : []).filter((t: any) => t && typeof t.assetId === "string"
          && typeof t.blockchain === "string" && typeof t.symbol === "string" && Number.isInteger(t.decimals)
          && t.decimals >= 0 && t.decimals <= 36).map((t: any): IntentToken => ({
          assetId: t.assetId, decimals: t.decimals, blockchain: t.blockchain, symbol: t.symbol,
          ...(typeof t.price === "number" ? { price: t.price } : {}),
          ...(typeof t.contractAddress === "string" && t.contractAddress ? { contractAddress: t.contractAddress } : {}),
        }));
        if (tokens.length === 0) throw new IntentsError(502, "NEAR Intents didn't answer. Try again in a moment");
        this.list = { at: now, tokens };
        return tokens;
      } finally {
        this.listing = null;
      }
    })();
    return this.listing;
  }

  async token(chain: NearChain, symbol: string): Promise<IntentToken> {
    const t = pickToken(await this.tokens(), chain, symbol);
    if (!t) throw new IntentsError(400, `NEAR Intents doesn't trade ${symbol.slice(0, 20).toUpperCase()} on ${chain.name}`);
    return t;
  }

  async quote(input: QuoteInput): Promise<QuoteAnswer> {
    const sellChain = nearChainOf(input.sellChain);
    const buyChain = nearChainOf(input.buyChain);
    if (!sellChain) throw new IntentsError(400, `NEAR Intents isn't on ${String(input.sellChain).slice(0, 20)}`);
    if (!buyChain) throw new IntentsError(400, `NEAR Intents isn't on ${String(input.buyChain).slice(0, 20)}`);
    const [sell, buy] = await Promise.all([this.token(sellChain, input.sell), this.token(buyChain, input.buy)]);
    if (sell.assetId === buy.assetId) throw new IntentsError(400, "That's the same coin");
    const exact = input.exact ?? "in";
    const priced = exact === "in" ? sell : buy;
    let amount: bigint;
    try {
      amount = parseUnits(input.amount, priced.decimals);
    } catch {
      amount = 0n;
    }
    if (amount <= 0n) throw new IntentsError(400, "amount?");
    const refundTo = input.refundTo?.trim() || undefined;
    const recipient = input.recipient?.trim() || undefined;
    if (refundTo && !addressFits(sellChain, refundTo)) throw new IntentsError(400, `Refunds need your ${sellChain.name} address`);
    // Both addresses or it's a preview: 1Click checks them even then, so a
    // preview is sent valid stand-ins and never shows them.
    const dry = !refundTo || !recipient;
    const slippage = input.slippage ?? 1;
    const body = {
      dry,
      swapType: exact === "in" ? "EXACT_INPUT" : "EXACT_OUTPUT",
      slippageTolerance: Math.round(slippage * 100),
      originAsset: sell.assetId,
      depositType: "ORIGIN_CHAIN",
      destinationAsset: buy.assetId,
      amount: amount.toString(),
      refundTo: dry ? sellChain.placeholder : refundTo,
      refundType: "ORIGIN_CHAIN",
      recipient: dry ? buyChain.placeholder : recipient,
      recipientType: "DESTINATION_CHAIN",
      deadline: new Date(this.now() + (sellChain.slow ? 3 : 1) * 60 * 60 * 1000).toISOString(),
      referral: REFERRAL,
    };
    let json: Record<string, any>;
    try {
      json = await this.call("/v0/quote", { method: "POST", body });
    } catch (err) {
      throw plainQuoteError(err, { sell, buy, sellChain, buyChain, priced });
    }
    const q = json.quote ?? {};
    if (typeof q.amountIn !== "string" || typeof q.amountOut !== "string") {
      throw new IntentsError(502, "NEAR Intents sent back an empty quote");
    }
    const depositAddress = !dry && typeof q.depositAddress === "string" ? q.depositAddress : null;
    if (!dry && !depositAddress) throw new IntentsError(502, "NEAR Intents sent back no deposit address");
    const memo = typeof q.depositMemo === "string" && q.depositMemo ? q.depositMemo : null;
    // An exact-in deposit is the typed amount to the unit, whatever 1Click
    // echoes; a send deposits 1Click's amountIn.
    const amountInBase = exact === "in" ? amount.toString() : q.amountIn;
    return {
      ok: true,
      dry,
      venue: VENUE,
      exact,
      sell: side(sell, sellChain),
      buy: side(buy, buyChain),
      amountIn: whole(amountInBase, sell.decimals),
      amountInBase,
      amountInUsd: usd(q.amountInUsd),
      amountOut: whole(q.amountOut, buy.decimals),
      amountOutBase: q.amountOut,
      amountOutUsd: usd(q.amountOutUsd),
      minAmountOut: whole(typeof q.minAmountOut === "string" ? q.minAmountOut : q.amountOut, buy.decimals),
      timeSeconds: typeof q.timeEstimate === "number" ? q.timeEstimate : null,
      depositAddress,
      depositMemo: memo,
      deadline: !dry && typeof q.deadline === "string" ? q.deadline : null,
      // EXACT_OUTPUT's amountIn already carries the slippage; whatever isn't
      // needed comes back to refundTo.
      deposit: depositAddress ? depositFor(sellChain, sell, depositAddress, amountInBase, memo) : null,
      explorer: depositAddress ? EXPLORER + encodeURIComponent(depositAddress) : null,
      recipient: dry ? null : recipient!,
      refundTo: dry ? null : refundTo!,
    };
  }

  async status(depositAddress: string, memo?: string): Promise<StatusAnswer> {
    const q = new URLSearchParams({ depositAddress, ...(memo ? { depositMemo: memo } : {}) });
    let json: Record<string, any>;
    try {
      json = await this.call(`/v0/status?${q}`);
    } catch (err) {
      if (err instanceof IntentsError && err.status === 404) throw new IntentsError(404, "NEAR Intents doesn't know that deposit address");
      throw err;
    }
    const status = statusOf(json.status);
    const d = json.swapDetails ?? {};
    const tx = (rows: unknown) => {
      const first = Array.isArray(rows) ? rows.find((r: any) => r && typeof r.hash === "string") : undefined;
      return first ? { hash: String(first.hash), url: typeof first.explorerUrl === "string" ? first.explorerUrl : "" } : undefined;
    };
    const destinationTx = tx(d.destinationChainTxHashes);
    const originTx = tx(d.originChainTxHashes);
    return {
      ok: true,
      status,
      done: status === "SUCCESS" || status === "REFUNDED" || status === "FAILED",
      ...(typeof d.amountOutFormatted === "string" && status === "SUCCESS" ? { amountOut: d.amountOutFormatted } : {}),
      ...(typeof d.refundedAmountFormatted === "string" && status === "REFUNDED" ? { refunded: d.refundedAmountFormatted } : {}),
      ...(destinationTx ? { destinationTx } : {}),
      ...(originTx ? { originTx } : {}),
      explorer: EXPLORER + encodeURIComponent(depositAddress),
    };
  }

  /** Tells 1Click the deposit went out, which speeds up its pickup. */
  async submit(depositAddress: string, txHash: string, memo?: string): Promise<{ ok: true }> {
    await this.call("/v0/deposit/submit", { method: "POST", body: { txHash, depositAddress, ...(memo ? { memo } : {}) } });
    return { ok: true };
  }
}

/** 1Click's quote errors in the person's words. */
function plainQuoteError(err: unknown, t: { sell: IntentToken; buy: IntentToken; sellChain: NearChain; buyChain: NearChain;
  priced: IntentToken }): unknown {
  if (!(err instanceof IntentsError) || err.status !== 400) return err;
  const m = err.message;
  const low = m.match(/too low.*?at least (\d+)/i);
  if (low) {
    const min = Number(whole(low[1], t.priced.decimals));
    const shown = SHOWN_AS[t.priced.symbol.toUpperCase()] ?? t.priced.symbol;
    const dollars = t.priced.price ? Math.ceil(min * t.priced.price * 100) / 100 : null;
    return new IntentsError(400, dollars !== null
      ? `Too small for NEAR Intents: at least $${dollars.toFixed(2)}`
      : `Too small for NEAR Intents: at least ${min} ${shown}`);
  }
  if (/recipient is not valid/i.test(m)) return new IntentsError(400, `That isn't a ${t.buyChain.name} address`);
  if (/refundTo is not valid/i.test(m)) return new IntentsError(400, `Refunds need your ${t.sellChain.name} address`);
  if (/not available|no quotes?|failed to get quote|internal server error/i.test(m)) {
    return new IntentsError(400, `NEAR Intents can't trade ${SHOWN_AS[t.sell.symbol.toUpperCase()] ?? t.sell.symbol} on ${t.sellChain.name} `
      + `for ${SHOWN_AS[t.buy.symbol.toUpperCase()] ?? t.buy.symbol} on ${t.buyChain.name} right now`);
  }
  return err;
}

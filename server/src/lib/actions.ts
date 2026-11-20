import { z } from "zod";
import { NEAR_IMPLICIT_ACCOUNT, NEAR_NAME } from "./names.js";
import { shortAddress } from "./nearguard.js";
import { addressFits, CHAIN_WORDS, homeChainOf, NEAR_CHAINS, nearChainOf, type NearChain } from "./nearintents.js";
import { parseEarnPhrase, parsePotPhrase } from "./nearphrase.js";
import { amountWords, shareOf, SPUTNIK } from "./payrequests.js";

/**
 * The strip's recommended action: when a pause in typing reads as something
 * one of Glyf's tools does ("put 20 bucks into ether every month" is a Flash
 * DCA, "lets hop on a call" a Meet link), the suggestion model names the
 * tool and its values, and the keyboard opens that tool with them filled in
 * for the person to check and change. Nothing runs from the strip.
 *
 * The model only ever picks from TOOLS, and every value it gives is checked
 * here (zod, fixed token and chain lists): an unknown tool or a value that
 * fails its check drops the action, never the rest of the suggestion. The
 * chip's words are written here from the checked values, never by the model.
 *
 * Old phones never ask for actions (the body's `actions` flag), so their
 * answers are exactly what they were.
 */

export const TOKENS: Record<string, string> = {
  eth: "ETH", ether: "ETH", ethereum: "ETH", weth: "WETH", usdc: "USDC", usdt: "USDT", dai: "DAI",
  wbtc: "WBTC", btc: "WBTC", bitcoin: "WBTC", cbbtc: "CBBTC", uni: "UNI", link: "LINK", aave: "AAVE",
  op: "OP", arb: "ARB", pol: "POL", matic: "POL", aero: "AERO", degen: "DEGEN", sol: "SOL", solana: "SOL",
  pepe: "PEPE", ldo: "LDO",
  // Shares, tokenized on Base (the keyboard trades them there by address).
  aapl: "AAPL", apple: "AAPL", tsla: "TSLA", tesla: "TSLA", nvda: "NVDA", nvidia: "NVDA", msft: "MSFT",
  microsoft: "MSFT", googl: "GOOGL", google: "GOOGL", alphabet: "GOOGL", amzn: "AMZN", amazon: "AMZN", meta: "META",
};
const STABLES = ["USDC", "USDT", "DAI"];
export const CHAINS = ["base", "ethereum", "arbitrum", "optimism", "polygon", "unichain", "solana"] as const;
const CHAIN_ALIASES: Record<string, (typeof CHAINS)[number]> = {
  base: "base", ethereum: "ethereum", mainnet: "ethereum", "eth mainnet": "ethereum", arbitrum: "arbitrum",
  arb: "arbitrum", optimism: "optimism", op: "optimism", polygon: "polygon", unichain: "unichain", solana: "solana",
};

const token = z.string().max(12).transform((s, ctx) => {
  const t = TOKENS[s.trim().toLowerCase().replace(/^\$/, "")];
  if (!t) { ctx.addIssue({ code: "custom", message: "unknown token" }); return z.NEVER; }
  return t;
});
const asset = token.refine(t => !STABLES.includes(t), "a stablecoin isn't bought on its own");
const chain = z.string().max(16).transform((s, ctx) => {
  const c = CHAIN_ALIASES[s.trim().toLowerCase()];
  if (!c) { ctx.addIssue({ code: "custom", message: "unknown chain" }); return z.NEVER; }
  return c;
});
/** A positive amount, as the model may give it: 20, "20", "$20", "1,000". */
const amount = z.union([z.number(), z.string().max(20)]).transform((v, ctx) => {
  const n = typeof v === "number" ? v : Number(v.replace(/[$,\s]/g, "").replace(/k$/i, "000"));
  if (!Number.isFinite(n) || n <= 0 || n > 1e9) { ctx.addIssue({ code: "custom", message: "bad amount" }); return z.NEVER; }
  return String(Number(n.toPrecision(12)));
});
const percent = amount.refine(v => Number(v) >= 0.5 && Number(v) <= 50, "trail between 0.5% and 50%");
const query = z.string().trim().min(1).max(120);

/** Coins NEAR Intents moves, by what people type ("btc" is real Bitcoin
 *  here, not Uniswap's WBTC). */
export const NEAR_COINS: Record<string, string> = {
  usdc: "USDC", usdt: "USDT", eth: "ETH", ether: "ETH", sol: "SOL", solana: "SOL", btc: "BTC", bitcoin: "BTC",
  zec: "ZEC", zcash: "ZEC", near: "NEAR", ton: "TON", trx: "TRX", tron: "TRX", xrp: "XRP", doge: "DOGE",
  dogecoin: "DOGE", ltc: "LTC", litecoin: "LTC", sui: "SUI", apt: "APT", aptos: "APT", xlm: "XLM", stellar: "XLM",
  ada: "ADA", cardano: "ADA", bnb: "BNB",
};
const nearCoin = z.string().max(12).transform((s, ctx) => {
  const c = NEAR_COINS[s.trim().toLowerCase().replace(/^\$/, "")];
  if (!c) { ctx.addIssue({ code: "custom", message: "unknown coin" }); return z.NEVER; }
  return c;
});
const nearChain = z.string().max(16).transform((s, ctx) => {
  const c = nearChainOf(s);
  if (!c) { ctx.addIssue({ code: "custom", message: "unknown chain" }); return z.NEVER; }
  return c.key;
});
/** Who a NEAR Intents send can pay by name or address alone (the spec's
 *  sends): a .near name, an implicit account, a Bitcoin or Zcash address. */
const nearPayee = z.string().trim().min(2).max(100).refine(t => NEAR_NAME.test(t) || NEAR_IMPLICIT_ACCOUNT.test(t)
  || addressFits(NEAR_CHAINS.bitcoin, t) || addressFits(NEAR_CHAINS.zcash, t), "not a NEAR name or a BTC/ZEC address");

/** Where a coin sits when nobody said: its own chain (SOL on Solana, BTC on
 *  Bitcoin), else Base, the phone's default. */
export function nearSide(coin: string, chain?: string): NearChain {
  return (chain ? NEAR_CHAINS[chain] : null) ?? (typeof coin === "string" ? homeChainOf(coin) : null) ?? NEAR_CHAINS.base;
}

/** NEAR Intents takes a trade only where Uniswap, Jupiter and Flash can't:
 *  Solana against an EVM chain, or any other chain on either side. */
export function crossesForNear(a: NearChain, b: NearChain): boolean {
  return a.kind === "other" || b.kind === "other" || a.kind !== b.kind;
}

/** Earn's coins: USDC (Morpho on Base) and SOL (Kamino on Solana). */
const earnCoin = nearCoin.refine(c => c === "USDC" || c === "SOL", "Earn takes USDC or SOL");
/** The word a pot goes by ("the trip pot"): the phone maps it to its saved DAO. */
const potWord = z.string().trim().toLowerCase().pipe(z.string().regex(/^[a-z][a-z0-9-]{1,20}$/));
const potDao = z.string().trim().toLowerCase().pipe(z.string().regex(SPUTNIK));
/** Who a pot pays: a NEAR account, or the words they were called by
 *  ("the caterer"), which the app turns into an account before proposing. */
const potPayee = z.string().trim().min(2).max(64).refine(t => NEAR_NAME.test(t) || NEAR_IMPLICIT_ACCOUNT.test(t)
  || /^[\p{L}][\p{L}\p{N} .'&-]{1,40}$/u.test(t), "a NEAR account or a name");
const potCoin = z.string().max(8).transform((s, ctx) => {
  const c = s.trim().replace(/^\$/, "").toUpperCase();
  if (!["NEAR", "USDC", "USDT"].includes(c)) { ctx.addIssue({ code: "custom", message: "a pot pays NEAR, USDC or USDT" }); return z.NEVER; }
  return c;
});

const FLASH_TYPES = ["limit", "stop", "stop-loss", "take-profit", "bracket", "trailing-stop", "twap"] as const;

/** Each tool's values. Keys the model adds beyond these are dropped. */
export const ACTION_PARAMS = {
  "trade.swap": z.object({
    sell: token, buy: token, amount: amount.optional(),
    /** The amount is dollars of what's bought ("buy $20 of eth"). */
    usd: z.boolean().optional(), chain: chain.optional(),
  }).refine(p => p.sell !== p.buy, "a swap needs two tokens"),
  "trade.dca": z.object({
    asset, every: amount, period: z.enum(["hour", "day", "week", "month"]),
    periods: z.number().int().min(1).max(520).optional(),
    spend: token.refine(t => STABLES.includes(t)).optional(), chain: chain.optional(),
  }),
  "trade.flash": z.object({
    type: z.enum(FLASH_TYPES), asset, side: z.enum(["buy", "sell"]).optional(),
    amount: amount.optional(), usd: z.boolean().optional(),
    price: amount.optional(), stopPrice: amount.optional(), trailPercent: percent.optional(),
    hours: z.number().min(0.1).max(720).optional(), chain: chain.optional(),
  }).superRefine((p, ctx) => {
    const need = (ok: unknown, what: string) => { if (!ok) ctx.addIssue({ code: "custom", message: `${p.type} needs ${what}` }); };
    if (["limit", "stop", "stop-loss", "take-profit", "bracket"].includes(p.type)) need(p.price, "a price");
    if (p.type === "bracket") need(p.stopPrice && Number(p.stopPrice) < Number(p.price ?? 0), "a stop below the take-profit");
    if (p.type === "trailing-stop") need(p.trailPercent, "a trail percent");
    if (p.type === "twap") need(p.amount && p.hours, "an amount and hours");
  }),
  "trade.bridge": z.object({ asset: token, amount, from: chain, to: chain }).refine(p => p.from !== p.to, "two chains"),
  "calendar.event": z.object({ title: z.string().trim().min(1).max(80), when: z.string().trim().min(2).max(60) }),
  "meet.link": z.object({}),
  "booking.link": z.object({}),
  search: z.object({ query }),
  youtube: z.object({ query }),
  shorts: z.object({ query }),
  maps: z.object({ query }),
  translate: z.object({ to: z.string().trim().min(2).max(24).regex(/^[\p{L} ]+$/u) }),
  rewrite: z.object({}),
  convert: z.object({ query: z.string().trim().min(2).max(60) }),
  "near.swap": z.object({
    sell: nearCoin, buy: nearCoin, amount: amount.optional(), sellChain: nearChain.optional(), buyChain: nearChain.optional(),
  }).refine(p => p.sell !== p.buy || nearSide(p.sell, p.sellChain).key !== nearSide(p.buy, p.buyChain).key, "a swap needs two sides")
    .refine(p => crossesForNear(nearSide(p.sell, p.sellChain), nearSide(p.buy, p.buyChain)), "Uniswap, Jupiter or Flash does that one"),
  "near.send": z.object({ to: nearPayee, amount, coin: nearCoin.optional(), with: nearCoin.optional(), withChain: nearChain.optional() })
    .transform(p => ({ ...p, coin: p.coin ?? (addressFits(NEAR_CHAINS.bitcoin, p.to) ? "BTC"
      : addressFits(NEAR_CHAINS.zcash, p.to) ? "ZEC" : "USDC") }))
    .refine(p => !addressFits(NEAR_CHAINS.bitcoin, p.to) || p.coin === "BTC", "a Bitcoin address gets BTC")
    .refine(p => !addressFits(NEAR_CHAINS.zcash, p.to) || p.coin === "ZEC", "a Zcash address gets ZEC"),
  "near.request": z.object({
    amount, coin: nearCoin.optional(), chain: nearChain.optional(), each: z.boolean().optional(),
    count: z.number().int().min(2).max(50).optional(),
    /** The bill's people include the writer ("for 4 of us"). */
    us: z.boolean().optional(),
    note: z.string().trim().min(2).max(40).regex(/^[\p{L}\p{N} '&-]+$/u).optional(),
  }),
  /** Idle coins into an Earn vault, or (out) back out of it. */
  "near.earn": z.object({ amount: amount.optional(), coin: earnCoin.optional(), out: z.boolean().optional(), chain: nearChain.optional() })
    .transform(p => ({ ...p, coin: p.coin ?? "USDC" })),
  /** A look at a group pot: its balance, members and open payouts. */
  "near.pot": z.object({ pot: potWord.optional(), dao: potDao.optional() }),
  /** A payout from the pot, to propose for the members' vote. */
  "near.pot.pay": z.object({
    to: potPayee, amount, coin: potCoin.optional(), pot: potWord.optional(), dao: potDao.optional(),
    note: z.string().trim().min(2).max(40).regex(/^[\p{L}\p{N} '&-]+$/u).optional(),
  }).transform(p => ({ ...p, coin: p.coin ?? "USDC" })),
} as const;

export type ActionTool = keyof typeof ACTION_PARAMS;
export const ACTION_TOOLS = Object.keys(ACTION_PARAMS) as ActionTool[];

export interface Action {
  tool: ActionTool;
  label: string;
  params: Record<string, unknown>;
}

const money = (v: unknown) => {
  const n = Number(v);
  return "$" + (Number.isFinite(n) ? n.toLocaleString("en-US", { maximumFractionDigits: n < 10 ? 4 : 2 }) : String(v));
};
const ADVERB = { hour: "hourly", day: "daily", week: "weekly", month: "monthly" } as const;
const capital = (s: string) => s.charAt(0).toUpperCase() + s.slice(1);
const clip = (s: string, n = 40) => (s.length > n ? s.slice(0, n - 1) + "…" : s);
const payee = (to: string) => (NEAR_NAME.test(to) ? to : shortAddress(to));
const VIA_NEAR = " · NEAR Intents";
const VIA_DAO = " · Sputnik DAO";
const EARN_VENUE: Record<string, string> = { USDC: "Morpho", SOL: "Kamino" };
const coinMoney = (amount: string, coin: string) => (coin === "USDC" ? money(amount) : `${amount} ${coin}`);
const potName = (p: Record<string, any>) => (p.dao ? p.dao.replace(/\.sputnik-dao\.near$/, "") + " pot" : p.pot ? `${p.pot} pot` : "pot");

/** The chip's words, from checked values only. */
export function actionLabel(tool: ActionTool, p: Record<string, any>): string {
  switch (tool) {
    case "trade.swap":
      if (p.usd && p.amount) return `Buy ${money(p.amount)} of ${p.buy} · Uniswap`;
      return `Swap ${p.amount ? `${p.amount} ` : ""}${p.sell} → ${p.buy} · Uniswap`;
    case "trade.dca":
      return `DCA ${money(p.every)} of ${p.asset} ${ADVERB[p.period as keyof typeof ADVERB]} · Flash`;
    case "trade.flash":
      switch (p.type) {
        case "limit": return `${p.side === "sell" ? "Sell" : "Buy"} ${p.asset} at ${money(p.price)} · Flash`;
        case "stop": return `Buy ${p.asset} above ${money(p.price)} · Flash`;
        case "stop-loss": return `Stop-loss ${p.asset} at ${money(p.price)} · Flash`;
        case "take-profit": return `Take profit ${p.asset} at ${money(p.price)} · Flash`;
        case "bracket": return `${p.asset} TP ${money(p.price)} · SL ${money(p.stopPrice)} · Flash`;
        case "trailing-stop": return `Trail ${p.asset} by ${p.trailPercent}% · Flash`;
        default: return `Buy ${money(p.amount)} of ${p.asset} over ${p.hours} h · Flash`;
      }
    case "trade.bridge": return `Move ${p.amount} ${p.asset} to ${capital(p.to)} · Flash`;
    case "calendar.event": return `Add ${clip(p.title, 28)} · ${clip(p.when, 20)}`;
    case "meet.link": return "Insert a Meet link";
    case "booking.link": return "Share your booking link";
    case "search": return `Search ${clip(p.query)}`;
    case "youtube": return `YouTube: ${clip(p.query)}`;
    case "shorts": return `Shorts: ${clip(p.query)}`;
    case "maps": return `Maps: ${clip(p.query)}`;
    case "translate": return `Translate to ${capital(p.to)}`;
    case "rewrite": return "Tidy this up";
    case "convert": return `Convert ${clip(p.query, 30)}`;
    case "near.swap":
      if (p.sell === p.buy) return `Move ${p.amount ? `${p.amount} ` : ""}${p.sell} to ${nearSide(p.buy, p.buyChain).name}${VIA_NEAR}`;
      return `Swap ${p.amount ? `${p.amount} ` : ""}${p.sell} → ${p.buy}${VIA_NEAR}`;
    case "near.send":
      return `Send ${p.amount} ${p.coin} to ${payee(p.to)}${p.with && p.with !== p.coin ? ` with ${p.with}` : ""}${VIA_NEAR}`;
    case "near.request": {
      const coin = p.coin ?? "USDC";
      const each = Boolean(p.each || p.count);
      const share = shareOf(p.amount, coin, Boolean(p.each), p.count ?? null);
      const where = p.chain ? ` on ${NEAR_CHAINS[p.chain].name}` : "";
      return `Request ${amountWords(share, coin)}${each ? " each" : ""}${where}${VIA_NEAR}`;
    }
    case "near.earn":
      if (p.out) return `Take ${p.amount ? `${p.amount} ` : "your "}${p.coin} out of Earn${VIA_NEAR}`;
      return `Put ${p.amount ? `${p.amount} ` : ""}${p.coin} to work · ${EARN_VENUE[p.coin]}${VIA_NEAR}`;
    case "near.pot":
      return `See the ${potName(p)}${VIA_DAO}`;
    case "near.pot.pay":
      return `Propose ${coinMoney(p.amount, p.coin)} to ${clip(String(p.to).replace(/^the\s+/i, ""), 24)} from the ${potName(p)}${VIA_DAO}`;
  }
}

/** A model's action, checked: null for an unknown tool or values that fail. */
export function checkAction(raw: unknown): Action | null {
  if (!raw || typeof raw !== "object") return null;
  const { tool, params } = raw as { tool?: unknown; params?: unknown };
  if (typeof tool !== "string" || !(tool in ACTION_PARAMS)) return null;
  const t = tool as ActionTool;
  const parsed = ACTION_PARAMS[t].safeParse(params ?? {});
  if (!parsed.success) return null;
  // Drop what the model left empty, so the phone sees only real values.
  const clean = Object.fromEntries(Object.entries(parsed.data as Record<string, unknown>)
    .filter(([, v]) => v !== undefined && v !== null && v !== ""));
  return { tool: t, label: actionLabel(t, clean), params: clean };
}

/** Values the typing has to back: a chain the words never named is the
 *  model's guess ("sell my eth" came back on Ethereum from a small model), so it
 *  goes and the phone's own default (Base) stands. */
export function groundAction(action: Action | null, text: string): Action | null {
  if (!action) return null;
  if (action.tool.startsWith("near.")) return groundNear(action, text);
  const chain = action.params.chain;
  if (typeof chain !== "string") return action;
  const t = text.toLowerCase();
  // Words that are tokens too ("buy ethereum", "my op") count only after
  // "on", "to" or "from".
  const both = new Set(["ethereum", "solana", "op", "arb", "mainnet", "eth mainnet"]);
  const named = Object.entries(CHAIN_ALIASES).some(([word, c]) => c === chain &&
    new RegExp(both.has(word) ? `\\b(?:on|to|from)\\s+${word}\\b` : `\\b${word}\\b`).test(t));
  if (named) return action;
  const params = { ...action.params };
  delete params.chain;
  return { ...action, params, label: actionLabel(action.tool, params) };
}

const NUMBER_WORDS: Record<string, number> = {
  two: 2, three: 3, four: 4, five: 5, six: 6, seven: 7, eight: 8, nine: 9, ten: 10, eleven: 11, twelve: 12,
};

/** Every number the words say: "$22.50", "1,200", "1.5k", "four". */
export function numbersIn(text: string): number[] {
  const out: number[] = [];
  for (const m of text.toLowerCase().matchAll(/(\d[\d,]*(?:\.\d+)?|\.\d+)\s?(k\b)?/g)) {
    const n = Number(m[1].replace(/,/g, ""));
    if (Number.isFinite(n)) out.push(m[2] ? n * 1000 : n);
  }
  for (const m of text.toLowerCase().matchAll(/\b(two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\b/g)) {
    out.push(NUMBER_WORDS[m[1]]);
  }
  return out;
}

const typed = (text: string, value: unknown) =>
  numbersIn(text).some(n => Math.abs(n - Number(value)) < 1e-9);

/** A chain counts as named only after "on", "to", "from", "in", "via" or
 *  "into": most chain words are coins too ("sol", "near", "btc"). */
function chainNamed(key: string, text: string): boolean {
  const chain = NEAR_CHAINS[key];
  if (!chain) return false;
  const words = new Set([chain.key, chain.oneClick, chain.name.toLowerCase(),
    ...Object.entries(CHAIN_WORDS).filter(([, c]) => c === key).map(([w]) => w)]);
  const t = text.toLowerCase();
  return [...words].some(w => new RegExp(`\\b(?:on|to|from|in|via|into)\\s+(?:the\\s+)?${w.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\b`).test(t));
}

/** A coin counts as named when any of its words is in the text. */
function coinNamed(symbol: string, text: string): boolean {
  const t = text.toLowerCase();
  return Object.entries(NEAR_COINS).some(([w, c]) => c === symbol && new RegExp(`(?:^|[^a-z0-9])\\$?${w}(?![a-z0-9])`).test(t));
}

/** NEAR Intents tools move money, so every value has to be in the words:
 *  an amount, a headcount, a name or address that wasn't typed drops the
 *  action (or the optional value), a chain the words never named goes and
 *  the coin's own chain or Base stands, and a note keeps only typed words.
 *  What's left is checked again from the start. */
function groundNear(action: Action, text: string): Action | null {
  const p: Record<string, unknown> = { ...action.params };
  const t = text.toLowerCase();
  for (const key of ["chain", "sellChain", "buyChain", "withChain"]) {
    if (typeof p[key] === "string" && !chainNamed(p[key] as string, text)) delete p[key];
  }
  switch (action.tool) {
    case "near.swap":
      if (!coinNamed(p.sell as string, text) || !coinNamed(p.buy as string, text)) return null;
      if (p.amount !== undefined && !typed(text, p.amount)) delete p.amount;
      break;
    case "near.send": {
      const to = String(p.to);
      if (!(NEAR_NAME.test(to) ? t.includes(to) : text.includes(to))) return null;
      if (!typed(text, p.amount)) return null;
      if (p.coin !== "USDC" && !coinNamed(p.coin as string, text) && !addressFits(NEAR_CHAINS.bitcoin, to)
        && !addressFits(NEAR_CHAINS.zcash, to)) return null;
      if (p.with !== undefined && !coinNamed(p.with as string, text)) delete p.with;
      break;
    }
    case "near.earn": {
      const usdc = p.coin === "USDC" && (coinNamed("USDC", text) || /\$\s?\d|\b(dollars|bucks|usd|stables?)\b/.test(t));
      if (!usdc && !(p.coin === "SOL" && coinNamed("SOL", text))) return null;
      const out = /\b(out|withdraw|redeem|unstake|cash out|take back)\b/.test(t);
      if (Boolean(p.out) !== out) return null;
      if (!out && !/\b(earn\w*|to work|park|yield|interest|vault|stake|savings|apy)\b/.test(t)) return null;
      if (p.amount !== undefined && !typed(text, p.amount)) delete p.amount;
      break;
    }
    case "near.pot":
    case "near.pot.pay": {
      if (!/\b(pot|treasury|kitty)\b|\.sputnik-dao\.near\b/.test(t)) return null;
      if (typeof p.pot === "string" && !new RegExp(`\\b${p.pot}\\s+(pot|treasury|kitty)\\b`).test(t)) delete p.pot;
      if (typeof p.dao === "string" && !t.includes(p.dao as string)) delete p.dao;
      if (action.tool === "near.pot") break;
      if (!t.includes(String(p.to).toLowerCase())) return null;
      if (!typed(text, p.amount)) return null;
      if (p.coin !== "USDC" && !new RegExp(`\\b${String(p.coin).toLowerCase()}\\b`).test(t)) return null;
      if (typeof p.note === "string" && !String(p.note).toLowerCase().split(/\s+/).every(w => t.includes(w))) delete p.note;
      break;
    }
    case "near.request":
      if (!typed(text, p.amount)) return null;
      // The link is already in the message (Request put it there): asking
      // again would only make a second link for the same money.
      if (/\/pay\/[A-Za-z0-9_-]{6,}/.test(text)) return null;
      if (p.coin !== undefined && !coinNamed(p.coin as string, text)) delete p.coin;
      if (p.count !== undefined && !typed(text, p.count)) delete p.count;
      if (p.each && !/\b(each|apiece|per (person|head)|a head|everyone|every one)\b/.test(t)) delete p.each;
      if (p.us && !(p.count !== undefined && /\b(of us|us|we)\b/.test(t))) delete p.us;
      if (typeof p.note === "string" && !String(p.note).toLowerCase().split(/\s+/).every(w => t.includes(w))) delete p.note;
      break;
  }
  return checkAction({ tool: action.tool, params: p });
}

/** What the prompt says about the tools: one line each, compact enough for
 *  a small model and the suggest tier's 200 tokens. */
export const ACTION_GUIDE = `action: only when one of Glyf's tools does what they typed, {"tool":"…","params":{…}}, else leave it out. Tools (params, ? = optional):
trade.swap {sell,buy,amount?,usd?,chain?} swap or buy now; usd:true when the amount is dollars of what is bought
trade.dca {asset,every,period,periods?,spend?,chain?} a repeated buy; every = dollars each time; period hour|day|week|month; periods = how many buys
trade.flash {type,asset,side?,amount?,usd?,price?,stopPrice?,trailPercent?,hours?,chain?} an order that waits; type limit|stop|stop-loss|take-profit|bracket|trailing-stop|twap; usd:true when the amount is dollars ("buy $10 of tesla below 300" is limit, amount 10, usd true, price 300)
trade.bridge {asset,amount,from,to} the same token to another chain
calendar.event {title,when} a plan with a day or time ("dinner with sam", "fri 8pm")
meet.link {} they want a video call now
booking.link {} they want someone to pick a time
search|youtube|shorts|maps {query} something to look up, watch or find nearby
translate {to} the language to write their message in
convert {query} units or currency to convert ("5 ft in cm")
near.swap {sell,buy,amount?,sellChain?,buyChain?} a swap or move that crosses to or from Solana, Bitcoin, Zcash, NEAR or another chain Uniswap can't reach ("swap 20 usdc on base to sol")
near.send {to,amount,coin?,with?,withChain?} pay a .near name, a Bitcoin or a Zcash address an exact amount; to exactly as typed; with = the coin they pay with
near.earn {amount?,coin?,out?,chain?} idle USDC or SOL into a yield vault ("put $50 to work", "park 50 usdc", "earn on 0.5 sol"); out:true to take it back out ("take my usdc out of earn"); chain = where the coins are
near.pot {pot?,dao?} what's in a group pot ("how much is in the trip pot"); pot = their word before "pot" ("trip"), dao = a typed name.sputnik-dao.near
near.pot.pay {to,amount,coin?,pot?,dao?,note?} pay someone from the group pot ("pay the caterer $120 from the pot"); to = who, exactly as typed ("the caterer" or caterer.near); coin NEAR USDC USDT
near.request {amount,coin?,chain?,each?,count?,us?,note?} someone owes them money or a bill is split: a pay link. amount = the number typed (a total with count, each:true when it is per person); chain = where they want to be paid ("i'm on solana"); us:true when the writer is one of count ("for 4 of us"); note = what it's for, their word ("dinner")
NEAR Intents coins: USDC USDT ETH SOL BTC ZEC NEAR TON TRX XRP DOGE LTC SUI APT XLM ADA BNB. Their chains also near bitcoin zcash ton tron.
Tokens: ETH WBTC SOL USDC USDT DAI UNI LINK AAVE OP ARB POL AERO DEGEN PEPE LDO, and shares AAPL TSLA NVDA MSFT GOOGL AMZN META (Apple, Tesla, Nvidia…). Chains: base ethereum arbitrum optimism polygon unichain solana. Numbers as numbers. Give a chain only when they name one ("eth" is a token). Never invent an amount, price or name that was not typed.`;

/** Typing that a tool might act on: only these take the extra look when the
 *  rules already had a chip for the sentence. */
export function mayAct(text: string): boolean {
  return /\b(owes?|owed|split|chip in|pot|kitty|treasury|earn|earning|park|yield|vault|to work|request|zec|zcash|near|buy|sell|swap|dca|invest|stack|trade|grab|get me|shares?|stocks?|aapl|apple|tsla|tesla|nvda|nvidia|msft|microsoft|googl|google|amzn|amazon|meta|dips?|under|below|bridge|send|pay|transfer|stop[- ]?loss|take profit|limit|trail|eth|btc|bitcoin|sol|usdc|usdt|call|meet|zoom|schedule|book|calendar|remind|dinner|lunch|meeting|tomorrow|tmrw|tonight|monday|tuesday|wednesday|thursday|friday|saturday|sunday|translate|youtube|shorts|video|map|directions|near me|convert|search|google)\b/i
    .test(text);
}

/** MOCK_AI's stand-in for the model's action, so tests and the simulator run
 *  the whole path without a key. */
export function mockAction(text: string): Action | null {
  const t = text.toLowerCase();
  const earn = parseEarnPhrase(text);
  if (earn) {
    return groundAction(checkAction({ tool: "near.earn", params: { coin: earn.coin, ...(earn.amount ? { amount: earn.amount } : {}),
      ...(earn.direction === "out" ? { out: true } : {}), ...(earn.chain ? { chain: earn.chain } : {}) } }), text);
  }
  const pot = parsePotPhrase(text);
  if (pot?.ask === "balance") return groundAction(checkAction({ tool: "near.pot", params: { pot: pot.pot, dao: pot.dao } }), text);
  if (pot?.ask === "pay") {
    return groundAction(checkAction({ tool: "near.pot.pay", params: { to: pot.payee, amount: pot.amount, coin: pot.coin,
      pot: pot.pot, dao: pot.dao, note: pot.note } }), text);
  }
  const owe = t.match(/\b(?:owes? me|pay me(?: back)?)\b\D*?(\d+(?:\.\d+)?)/);
  if (owe) {
    const chain = t.match(/\b(?:on|in)\s+(solana|base|near|arbitrum|ethereum)\b/)?.[1];
    const note = t.match(/\bfor\s+(?:the\s+)?([a-z]+)\b/)?.[1];
    return groundAction(checkAction({ tool: "near.request", params: { amount: owe[1], ...(chain ? { chain } : {}),
      ...(note ? { note } : {}) } }), text);
  }
  const swap = t.match(/\bswap\s+(\d+(?:\.\d+)?)\s+([a-z]+)(?:\s+on\s+([a-z]+))?\s+(?:to|for|into)\s+([a-z]+)(?:\s+on\s+([a-z]+))?/);
  if (swap) {
    const [, n, sell, sellChain, buy, buyChain] = swap;
    return groundAction(checkAction({ tool: "near.swap", params: { amount: n, sell, buy,
      ...(sellChain ? { sellChain } : {}), ...(buyChain ? { buyChain } : {}) } }), text);
  }
  const send = t.match(/\b(?:send|pay)\s+(\d+(?:\.\d+)?)\s+([a-z]+)\s+to\s+([a-z0-9._-]+\.near)\b/);
  if (send) return groundAction(checkAction({ tool: "near.send", params: { amount: send[1], coin: send[2], to: send[3] } }), text);
  const dca = t.match(/(?:\$\s?(\d+(?:\.\d+)?)|(\d+(?:\.\d+)?)\s?(?:\$|bucks|dollars|usd))\s.*?\b(eth|ether|btc|bitcoin|sol)\b.*?\b(?:every|each|a|per)\s+(hour|day|week|month)/);
  if (dca) return checkAction({ tool: "trade.dca", params: { asset: dca[3], every: Number(dca[1] ?? dca[2]), period: dca[4] } });
  if (/\b(hop on|jump on|quick) (a )?call\b|\bvideo call\b/.test(t)) return checkAction({ tool: "meet.link", params: {} });
  const tr = t.match(/\btranslate\b.*\b(?:to|into)\s+([a-z]+)/);
  if (tr) return checkAction({ tool: "translate", params: { to: tr[1] } });
  const ev = t.match(/\b(dinner|lunch|meeting|coffee)\b.*?\b(tomorrow|tonight|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b(?:\s+(?:at\s+)?(\d{1,2}(?::\d\d)?\s?(?:am|pm)))?/);
  if (ev) return checkAction({ tool: "calendar.event", params: { title: ev[1], when: [ev[2], ev[3]].filter(Boolean).join(" ") } });
  const yt = t.match(/\b(?:trailer|music video)\b/);
  if (yt) return checkAction({ tool: "youtube", params: { query: text.trim().slice(0, 120) } });
  return null;
}

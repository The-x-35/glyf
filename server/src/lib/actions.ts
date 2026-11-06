import { z } from "zod";

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
/** A name a wallet can send to: ENS, SNS or an address. */
const recipient = z.string().trim().max(80)
  .regex(/^(?:[a-z0-9][a-z0-9-]*(?:\.[a-z0-9-]+)*\.(?:eth|sol)|0x[0-9a-fA-F]{40}|[1-9A-HJ-NP-Za-km-z]{32,44})$/i, "not a wallet name");

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
  send: z.object({ to: recipient, amount, token, chain: chain.optional() }),
  pay: z.object({ to: recipient.optional(), amount: amount.optional(), token: token.optional() }),
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
    case "send": return `Send ${p.amount} ${p.token} to ${p.to}`;
    case "pay": return p.amount ? `Pay ${p.amount} ${p.token ?? "USDC"}` : "Pay";
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
 *  model's guess ("sell my eth" came back on Ethereum from 0G's 0gm), so it
 *  goes and the phone's own default (Base) stands. */
export function groundAction(action: Action | null, text: string): Action | null {
  if (!action) return null;
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

/** What the prompt says about the tools: one line each, compact enough for
 *  a small model and the suggest tier's 200 tokens. */
export const ACTION_GUIDE = `action: only when one of Glyf's tools does what they typed, {"tool":"…","params":{…}}, else leave it out. Tools (params, ? = optional):
trade.swap {sell,buy,amount?,usd?,chain?} swap or buy now; usd:true when the amount is dollars of what is bought
trade.dca {asset,every,period,periods?,spend?,chain?} a repeated buy; every = dollars each time; period hour|day|week|month; periods = how many buys
trade.flash {type,asset,side?,amount?,price?,stopPrice?,trailPercent?,hours?,chain?} an order that waits; type limit|stop|stop-loss|take-profit|bracket|trailing-stop|twap
trade.bridge {asset,amount,from,to} the same token to another chain
send {to,amount,token} crypto to a .eth/.sol name or 0x address
calendar.event {title,when} a plan with a day or time ("dinner with sam", "fri 8pm")
meet.link {} they want a video call now
booking.link {} they want someone to pick a time
search|youtube|shorts|maps {query} something to look up, watch or find nearby
translate {to} the language to write their message in
convert {query} units or currency to convert ("5 ft in cm")
Tokens: ETH WBTC SOL USDC USDT DAI UNI LINK AAVE OP ARB POL AERO DEGEN PEPE LDO, and shares AAPL TSLA NVDA MSFT GOOGL AMZN META (Apple, Tesla, Nvidia…). Chains: base ethereum arbitrum optimism polygon unichain solana. Numbers as numbers. Give a chain only when they name one ("eth" is a token). Never invent an amount, price or name that was not typed.`;

/** Typing that a tool might act on: only these take the extra look when the
 *  rules already had a chip for the sentence. */
export function mayAct(text: string): boolean {
  return /\b(buy|sell|swap|dca|invest|stack|trade|bridge|send|pay|transfer|stop[- ]?loss|take profit|limit|trail|eth|btc|bitcoin|sol|usdc|usdt|call|meet|zoom|schedule|book|calendar|remind|dinner|lunch|meeting|tomorrow|tmrw|tonight|monday|tuesday|wednesday|thursday|friday|saturday|sunday|translate|youtube|shorts|video|map|directions|near me|convert|search|google)\b/i
    .test(text);
}

/** MOCK_AI's stand-in for the model's action, so tests and the simulator run
 *  the whole path without a key. */
export function mockAction(text: string): Action | null {
  const t = text.toLowerCase();
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

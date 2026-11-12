import { homeChainOf, nearChainOf, type NearChain, type QuoteInput } from "./nearintents.js";

/**
 * What someone types for a NEAR Intents trade, as a quote request: the
 * phrases in docs/NEAR-SPEC.md's table ("swap 20 usdc on base to sol",
 * "send 5 usdc to alice.near", "pay bob.near 10 usdc with sol"). The
 * keyboards read these themselves (TradeIntent); this one serves
 * scripts/near-quote.ts and keeps the server's reading of the table tested.
 *
 * Unsaid chains are filled the spec's way: a chain's own coin lives at home
 * (sol on Solana, btc on Bitcoin, near on NEAR), anything else is on Base;
 * a send is paid from USDC on Base unless "with …" or "from …" says
 * otherwise, and goes to the chain its address belongs to.
 */

export type PhraseKind = "swap" | "move" | "send";

export interface NearPhrase {
  kind: PhraseKind;
  quote: QuoteInput & { exact: "in" | "out" };
}

const AMOUNT = String.raw`\$?(\d+(?:\.\d+)?|\.\d+)`;
const COIN = String.raw`\$?([a-z][a-z0-9]{1,9})`;
const CHAIN = String.raw`([a-z]+)`;
const ADDR = String.raw`([A-Za-z0-9._:-]{2,128})`;

const SWAP = new RegExp(String.raw`^(?:swap|trade|convert|exchange)\s+${AMOUNT}\s+${COIN}(?:\s+on\s+${CHAIN})?\s+(?:to|for|into)\s+${COIN}(?:\s+on\s+${CHAIN})?(?:\s+to\s+${ADDR})?$`, "i");
const MOVE = new RegExp(String.raw`^(?:move|bridge)\s+${AMOUNT}\s+${COIN}\s+from\s+${CHAIN}\s+to\s+${CHAIN}(?:\s+to\s+${ADDR})?$`, "i");
const PAY_WITH = String.raw`(?:\s+(?:with|from|using)\s+([a-z0-9$]+)(?:\s+on\s+${CHAIN})?)?`;
const SEND = new RegExp(String.raw`^(?:send|pay)\s+${AMOUNT}\s+${COIN}(?:\s+on\s+${CHAIN})?\s+to\s+${ADDR}${PAY_WITH}$`, "i");
const PAY = new RegExp(String.raw`^pay\s+${ADDR}\s+${AMOUNT}\s+${COIN}(?:\s+on\s+${CHAIN})?${PAY_WITH}$`, "i");

const BASE = "base";

/** Where a coin is when no chain was said. */
function chainForCoin(coin: string, fallback = BASE): NearChain | null {
  return homeChainOf(coin) ?? nearChainOf(fallback);
}

/** The chain an address belongs to, by its shape. */
export function chainOfAddress(address: string): NearChain | null {
  const a = address.trim();
  if (/^(([a-z\d]+[-_])*[a-z\d]+\.)+near$/.test(a) || /^[0-9a-f]{64}$/.test(a)) return nearChainOf("near");
  if (/^(bc1|[13])[A-Za-z0-9]{25,}$/.test(a)) return nearChainOf("bitcoin");
  if (/^t[13][A-Za-z0-9]{33}$/.test(a)) return nearChainOf("zcash");
  if (/^0x[0-9a-fA-F]{40}$/.test(a)) return nearChainOf(BASE);
  if (/^[1-9A-HJ-NP-Za-km-z]{32,44}$/.test(a)) return nearChainOf("solana");
  return null;
}

const up = (coin: string) => coin.replace(/^\$/, "").toUpperCase();
/** ".5" is half a coin. */
const amountOf = (raw: string) => raw.startsWith(".") ? `0${raw}` : raw;

/** "with sol", "from solana", "with usdc on arbitrum": what pays a send. */
function payFrom(word: string | undefined, chainWord: string | undefined): { coin: string; chain: NearChain } | null {
  if (!word) return { coin: "USDC", chain: nearChainOf(BASE)! };
  if (chainWord) {
    const chain = nearChainOf(chainWord);
    return chain ? { coin: up(word), chain } : null;
  }
  // A chain alone ("from solana") keeps USDC and changes where it's from;
  // a coin alone ("with sol", "with eth") is that coin where it lives.
  const asChain = nearChainOf(word);
  if (asChain && word.length > 3 && !homeChainOf(word)) return { coin: "USDC", chain: asChain };
  const coin = up(word);
  const chain = chainForCoin(coin);
  return chain ? { coin, chain } : null;
}

export function parseNearPhrase(text: string): NearPhrase | null {
  const t = text.trim().replace(/\s+/g, " ").replace(/[.!?]$/, "");
  let m = t.match(SWAP);
  if (m) {
    const [, amount, sellRaw, sellChainWord, buyRaw, buyChainWord, to] = m;
    const sell = up(sellRaw);
    const buy = up(buyRaw);
    const sellChain = sellChainWord ? nearChainOf(sellChainWord) : chainForCoin(sell);
    if (!sellChain) return null;
    const buyChain = buyChainWord ? nearChainOf(buyChainWord)
      : chainForCoin(buy, sellChain.kind === "evm" ? sellChain.key : BASE);
    if (!buyChain) return null;
    return { kind: "swap", quote: { sell, sellChain: sellChain.key, buy, buyChain: buyChain.key, amount: amountOf(amount), exact: "in",
      ...(to ? { recipient: to } : {}) } };
  }
  m = t.match(MOVE);
  if (m) {
    const [, amount, coinRaw, fromWord, toWord, to] = m;
    const from = nearChainOf(fromWord);
    const into = nearChainOf(toWord);
    if (!from || !into || from.key === into.key) return null;
    const coin = up(coinRaw);
    return { kind: "move", quote: { sell: coin, sellChain: from.key, buy: coin, buyChain: into.key, amount: amountOf(amount), exact: "in",
      ...(to ? { recipient: to } : {}) } };
  }
  let send: { amount: string; coin: string; chainWord?: string; to: string; withWord?: string; withChain?: string } | null = null;
  m = t.match(SEND);
  if (m) send = { amount: m[1], coin: m[2], chainWord: m[3], to: m[4], withWord: m[5], withChain: m[6] };
  m = send ? null : t.match(PAY);
  if (m) send = { to: m[1], amount: m[2], coin: m[3], chainWord: m[4], withWord: m[5], withChain: m[6] };
  if (!send) return null;
  const buy = up(send.coin);
  const buyChain = send.chainWord ? nearChainOf(send.chainWord) : chainOfAddress(send.to) ?? chainForCoin(buy);
  const pay = payFrom(send.withWord, send.withChain);
  if (!buyChain || !pay) return null;
  return { kind: "send", quote: { sell: pay.coin, sellChain: pay.chain.key, buy, buyChain: buyChain.key,
    amount: amountOf(send.amount), exact: "out", recipient: send.to } };
}

/** "put $50 to work": idle coins into an Earn vault, or back out of one
 *  (lib/nearearn.ts). `amount` is left out for "take my usdc out of earn":
 *  everything, which the app reads from its share balance. */
export interface EarnPhrase {
  kind: "earn";
  direction: "in" | "out";
  coin: string;
  amount?: string;
  /** Where the coins are (in) or should land (out), when said. */
  chain?: string;
}

const EARN_COIN = String.raw`(usdc|sol|\$)`;
const MONEY = String.raw`(?:\$\s?(\d+(?:\.\d+)?|\.\d+)|(\d+(?:\.\d+)?|\.\d+)\s*(usdc|sol|dollars|bucks))`;
const ON_CHAIN = String.raw`(?:\s+(?:on|from|in)\s+(?!earn\b|savings\b|yield\b|a\s)([a-z]+))?`;
const TO_CHAIN = String.raw`(?:\s+(?:to|on|into)\s+([a-z]+))?`;
const EARN_IN = [
  // put $50 to work · put 50 usdc on solana to work · put my 50 usdc to work
  new RegExp(String.raw`^(?:put|set)\s+(?:my\s+)?${MONEY}${ON_CHAIN}\s+to\s+work$`, "i"),
  // earn on 50 usdc · earn with $50 · earn yield on 0.5 sol · start earning on 50 usdc
  new RegExp(String.raw`^(?:start\s+)?earn(?:ing)?(?:\s+(?:yield|interest))?\s+(?:on|with|from)\s+(?:my\s+)?${MONEY}${ON_CHAIN}$`, "i"),
  // park 50 usdc · park $50 in earn · stake 0.5 sol in earn
  new RegExp(String.raw`^(?:park|stash|deposit|stake)\s+(?:my\s+)?${MONEY}${ON_CHAIN}(?:\s+(?:in|into)\s+(?:earn|a vault|savings|yield))?$`, "i"),
];
const EARN_OUT = new RegExp(String.raw`^(?:take|pull|get|withdraw|cash)\s+(?:out\s+)?(?:my\s+|all\s+(?:my\s+)?)?(?:${MONEY}|${EARN_COIN})(?:\s+(?:back\s+)?out)?\s+(?:of|from)\s+(?:earn|the vault|savings|yield)${TO_CHAIN}$`, "i");

function earnCoin(word: string | undefined, dollars: boolean): string | null {
  if (dollars || !word) return "USDC";
  const w = word.toLowerCase();
  if (w === "sol") return "SOL";
  if (w === "usdc" || w === "dollars" || w === "bucks" || w === "$") return "USDC";
  return null;
}

export function parseEarnPhrase(text: string): EarnPhrase | null {
  const t = text.trim().replace(/\s+/g, " ").replace(/[.!?]$/, "");
  for (const re of EARN_IN) {
    const m = t.match(re);
    if (!m) continue;
    const [, dollarAmount, coinAmount, coinWord, chainWord] = m;
    const coin = earnCoin(coinWord, dollarAmount !== undefined);
    const chain = chainWord ? nearChainOf(chainWord) : null;
    if (!coin || (chainWord && !chain)) return null;
    return { kind: "earn", direction: "in", coin, amount: amountOf(dollarAmount ?? coinAmount),
      ...(chain ? { chain: chain.key } : {}) };
  }
  const m = t.match(EARN_OUT);
  if (m) {
    const [, dollarAmount, coinAmount, coinWord, bareCoin, chainWord] = m;
    const coin = earnCoin(coinWord ?? bareCoin, dollarAmount !== undefined);
    const chain = chainWord ? nearChainOf(chainWord) : null;
    if (!coin || (chainWord && !chain)) return null;
    const amount = dollarAmount ?? coinAmount;
    return { kind: "earn", direction: "out", coin, ...(amount ? { amount: amountOf(amount) } : {}),
      ...(chain ? { chain: chain.key } : {}) };
  }
  return null;
}

/** "how much is in the trip pot", "pay the caterer $120 from the pot": a
 *  Sputnik DAO group pot (lib/sputnik.ts). `pot` is the word before "pot"
 *  ("trip"), which the phone maps to the pot it saved; `dao` is a typed
 *  *.sputnik-dao.near. A payee that isn't a NEAR account ("the caterer")
 *  is kept as said: the app asks for the account before proposing. */
export type PotPhrase =
  | { kind: "pot"; ask: "balance"; pot?: string; dao?: string }
  | { kind: "pot"; ask: "pay"; payee: string; amount: string; coin: string; pot?: string; dao?: string; note?: string };

const POT_NAME = String.raw`(?:(?:the|our|my)\s+)?(?:([a-z][a-z0-9-]{1,20})\s+)?(?:pot|treasury|kitty)|([a-z0-9][a-z0-9_-]*\.sputnik-dao\.near)`;
const POT_BALANCE = [
  new RegExp(String.raw`^(?:how much|what)(?:'s| is| do we have)?\s+(?:left\s+)?in\s+(?:${POT_NAME})(?:\s+left)?$`, "i"),
  new RegExp(String.raw`^(?:check|show(?:\s+me)?|open)\s+(?:${POT_NAME})(?:\s+balance)?$`, "i"),
  new RegExp(String.raw`^(?:${POT_NAME})\s+balance$`, "i"),
];
const POT_MONEY = String.raw`(?:\$\s?(\d+(?:\.\d+)?)|(\d+(?:\.\d+)?)\s*(usdc|usdt|near|dollars|bucks))`;
const POT_PAY = new RegExp(String.raw`^(?:pay|send|give)\s+((?:the\s+)?[a-z][a-z0-9._-]{0,63}(?:\s+[a-z][a-z0-9._-]{0,30})?)\s+${POT_MONEY}\s+(?:from|out of)\s+(?:${POT_NAME})(?:\s+for\s+([a-z][a-z0-9 '&-]{1,40}))?$`, "i");
const NOT_POT_WORD = new Set(["the", "our", "my", "a", "shared", "group"]);

function potWho(word: string | undefined, dao: string | undefined): { pot?: string; dao?: string } {
  if (dao) return { dao: dao.toLowerCase() };
  if (word && !NOT_POT_WORD.has(word.toLowerCase())) return { pot: word.toLowerCase() };
  return {};
}

export function parsePotPhrase(text: string): PotPhrase | null {
  const t = text.trim().replace(/\s+/g, " ").replace(/[.!?]$/, "");
  for (const re of POT_BALANCE) {
    const m = t.match(re);
    if (m) return { kind: "pot", ask: "balance", ...potWho(m[1], m[2]) };
  }
  const m = t.match(POT_PAY);
  if (!m) return null;
  const [, payee, dollars, amount, coinWord, potWord, dao, note] = m;
  const coin = dollars !== undefined || /^(dollars|bucks)$/i.test(coinWord ?? "") ? "USDC" : coinWord.toUpperCase();
  return { kind: "pot", ask: "pay", payee: payee.trim(), amount: dollars ?? amount, coin, ...potWho(potWord, dao),
    ...(note ? { note: note.trim() } : {}) };
}

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

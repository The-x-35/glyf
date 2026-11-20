import { randomBytes } from "node:crypto";
import { NEAR_IMPLICIT_ACCOUNT, NEAR_NAME } from "./names.js";
import { shortAddress } from "./nearguard.js";
import { addressFits, chainsFor, NEAR_CHAINS, type NearChain, type SwapStatus } from "./nearintents.js";
import type { KV } from "./store.js";

/**
 * Pay links (docs/NEAR-SPEC.md, "Pay links"): "you owe me $22.50 for
 * dinner" becomes https://api.tryglyf.com/pay/<id>, a page where whoever got
 * the link pays with whatever they hold (USDC on Arbitrum, SOL, BTC, ZEC,
 * NEAR…) and the requester gets exactly the amount, in the coin and on the
 * chain they asked for, through NEAR Intents (an EXACT_OUTPUT quote).
 *
 * A request to a Sputnik DAO account (trip.sputnik-dao.near) is a shared
 * pot: every payment lands in the DAO's treasury.
 *
 * Rows live in the server's KV store (lib/store.ts, the glyf_kv table in
 * Postgres), like the shared /p/ pages: one row per request under an
 * unguessable id, and one row per payer's deposit address, so two people
 * paying at once never write the same row. A payer row keeps the deposit
 * address and where it stands, never the payer's refund address.
 */

export const REQUESTS = "payreqs";
export const PAYERS = "paypayers";

export interface PayRequest {
  id: string;
  /** Whole coins each payer pays: the share. */
  amount: string;
  /** What the person typed: the total when `each` is false. */
  typedAmount: string;
  coin: string;
  /** Glyf's chain key (lib/nearintents.ts NEAR_CHAINS): where they're paid. */
  chain: string;
  to: string;
  note: string;
  each: boolean;
  /** How many people the link is for, when said. */
  count: number | null;
  /** A Sputnik DAO treasury: a shared pot. */
  pot: boolean;
  createdBy: string;
  createdAt: number;
}

export interface Payer {
  request: string;
  depositAddress: string;
  depositMemo: string | null;
  /** What pays (the payer's pick) and how much went in, whole coins. */
  coin: string;
  chain: string;
  amountIn: string;
  status: SwapStatus;
  createdAt: number;
  checkedAt: number;
  paidAt: number | null;
}

/** What a payer can pay with: a short list, in the page's order. */
export const PAY_WITH: readonly { id: string; coin: string; chain: string; label: string }[] = [
  { id: "usdc-base", coin: "USDC", chain: "base", label: "USDC · Base" },
  { id: "usdc-arbitrum", coin: "USDC", chain: "arbitrum", label: "USDC · Arbitrum" },
  { id: "usdc-ethereum", coin: "USDC", chain: "ethereum", label: "USDC · Ethereum" },
  { id: "usdc-solana", coin: "USDC", chain: "solana", label: "USDC · Solana" },
  { id: "eth-base", coin: "ETH", chain: "base", label: "ETH · Base" },
  { id: "sol", coin: "SOL", chain: "solana", label: "SOL" },
  { id: "btc", coin: "BTC", chain: "bitcoin", label: "BTC" },
  { id: "zec", coin: "ZEC", chain: "zcash", label: "ZEC" },
  { id: "near", coin: "NEAR", chain: "near", label: "NEAR" },
];

export const STABLES = new Set(["USDC", "USDT", "DAI"]);
export const SPUTNIK = /^[a-z\d]+([-_][a-z\d]+)*\.sputnik-dao\.near$/;
export const ID = /^[A-Za-z0-9_-]{10,16}$/;

/** How many deposit addresses one link may hand out: enough for a big
 *  group's retries, not a way to fill the store. */
export const MAX_PAYERS = 60;

export function newId(): string {
  return randomBytes(9).toString("base64url"); // 12 characters, not enumerable
}

/** The chain an address is most likely on. Any lowercase word fits NEAR's
 *  account format, so NEAR is only the answer for a .near name or a 64-hex
 *  implicit account ("bc1q…" is Bitcoin). */
function likelyChain(to: string): NearChain | null {
  const t = to.trim();
  if (/^0x[0-9a-fA-F]{40}$/.test(t)) return NEAR_CHAINS.base;
  if (NEAR_NAME.test(t) || NEAR_IMPLICIT_ACCOUNT.test(t)) return NEAR_CHAINS.near;
  return chainsFor(t).find(c => c.key !== "near") ?? chainsFor(t)[0] ?? null;
}

/** The chain a bare `to` is on, when the phone didn't say. */
export function chainForRecipient(to: string): NearChain {
  return likelyChain(to) ?? NEAR_CHAINS.base;
}

/** Why `to` can't be paid on `chain`, in Guard's words; null when it can. */
export function recipientProblem(chain: NearChain, to: string): string | null {
  if (addressFits(chain, to)) return null;
  const elsewhere = likelyChain(to);
  const said = elsewhere ? (elsewhere.kind === "evm" ? "EVM" : elsewhere.name) : "";
  return said ? `That's ${/^[AEIOU]/.test(said) ? "an" : "a"} ${said} address, not ${chain.name}`
    : `That isn't a ${chain.name} address`;
}

const SCALE = 6;
const UNIT = 10n ** BigInt(SCALE);

function toUnits(amount: string): bigint {
  const [whole, frac = ""] = amount.split(".");
  return BigInt(whole) * UNIT + BigInt((frac + "0".repeat(SCALE)).slice(0, SCALE) || "0");
}

function fromUnits(units: bigint, places = SCALE): string {
  const step = 10n ** BigInt(SCALE - places);
  const rounded = (units + step - 1n) / step * step;
  const whole = rounded / UNIT;
  const frac = (rounded % UNIT).toString().padStart(SCALE, "0").slice(0, places).replace(/0+$/, "");
  return frac ? `${whole}.${frac}` : `${whole}`;
}

/** A positive amount as typed ("22.50", "$1,200", 22.5) in plain decimals,
 *  or null. At most six decimals: no payment needs more. */
export function cleanAmount(raw: unknown): string | null {
  const s = typeof raw === "number" ? String(raw) : typeof raw === "string" ? raw.replace(/[$,\s]/g, "") : "";
  if (!/^\d{1,9}(\.\d{1,6})?$/.test(s) && !/^\.\d{1,6}$/.test(s)) return null;
  const units = toUnits(s.startsWith(".") ? `0${s}` : s);
  return units > 0n ? fromUnits(units) : null;
}

/** Each payer's share. A total split by a headcount rounds UP (to the cent
 *  for dollar coins), so the shares always cover the bill. */
export function shareOf(amount: string, coin: string, each: boolean, count: number | null): string {
  const units = toUnits(amount);
  const places = STABLES.has(coin) ? 2 : SCALE;
  if (each || !count || count < 2) return fromUnits(units, places);
  return fromUnits((units + BigInt(count) - 1n) / BigInt(count), places);
}

/** "$22.50" for dollar coins, "0.01 BTC" for the rest. */
export function amountWords(amount: string, coin: string): string {
  if (STABLES.has(coin)) {
    const n = Number(amount);
    return "$" + n.toLocaleString("en-US", { minimumFractionDigits: n % 1 ? 2 : 0, maximumFractionDigits: 2 });
  }
  return `${amount} ${coin}`;
}

/** A recipient as the page shows it: .near names whole, addresses
 *  shortened ("0xAb12…9fE0"). */
export function shortRecipient(to: string): string {
  if (NEAR_NAME.test(to)) return to;
  return shortAddress(to);
}

/** "goa-trip" for goa-trip.sputnik-dao.near. */
export function daoName(to: string): string {
  return to.replace(/\.sputnik-dao\.near$/, "");
}

/** What the payer sends the requester, said with the coin: "22.50 USDC". */
export function coinWords(amount: string, coin: string): string {
  return STABLES.has(coin) ? `${Number(amount).toFixed(2)} ${coin}` : `${amount} ${coin}`;
}

export function saveRequest(kv: KV, r: PayRequest): void {
  kv.put<PayRequest>(REQUESTS, r.id, r);
}

export function getRequest(kv: KV, id: string): PayRequest | undefined {
  if (!ID.test(id)) return undefined;
  return kv.get<PayRequest>(REQUESTS, id);
}

const payerKey = (id: string, deposit: string) => `${id}:${deposit}`;

export function savePayer(kv: KV, p: Payer): void {
  kv.put<Payer>(PAYERS, payerKey(p.request, p.depositAddress), p);
}

export function getPayer(kv: KV, id: string, deposit: string): Payer | undefined {
  return kv.get<Payer>(PAYERS, payerKey(id, deposit));
}

export function payersOf(kv: KV, id: string): Payer[] {
  return kv.list<Payer>(PAYERS).map(r => r.value).filter(p => p && p.request === id);
}

export interface Tally {
  paid: number;
  count: number | null;
  /** "2 of 4 paid", "1 paid", "All 4 paid"; "" while nobody has paid a
   *  link with no headcount. */
  words: string;
  full: boolean;
}

export function tallyOf(r: PayRequest, payers: Payer[]): Tally {
  const paid = payers.filter(p => p.status === "SUCCESS").length;
  const count = r.count;
  const full = count !== null && paid >= count;
  const words = full ? (count === 1 ? "Paid" : `All ${count} paid`)
    : count !== null ? `${paid} of ${count} paid`
      : paid === 0 ? "" : `${paid} paid`;
  return { paid, count, words, full };
}

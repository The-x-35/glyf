import { NEAR_NAME, type NearLookup } from "./names.js";
import { addressFits, chainsFor, type NearChain } from "./nearintents.js";

/**
 * Guard (docs/NEAR-SPEC.md, the AI Security track): the checks every live
 * NEAR Intents quote with a recipient runs before the panel's button may
 * send. A `block` holds the button until the person taps "Send anyway"; a
 * `warn` is said and nothing more.
 *
 * - lookalike (block): shares its first 4 and last 4 characters with an
 *   address paid before but isn't it. Address poisoning sends a dust
 *   transfer from such a twin, hoping the next payment is copied from history.
 * - no-account (block): a .near name NEAR doesn't have. Coins sent there
 *   come back as a refund at best.
 * - chain-mismatch (block): the address can't be on the destination chain.
 * - new-recipient (warn): not among `recent`.
 * - over-limit (warn): today's spending would pass the person's own limit.
 * - big (warn): over $1,000.
 *
 * Everything is checked from what the phone sent and one view_account; no
 * address is logged or kept.
 */

export type GuardLevel = "ok" | "warn" | "block";

export interface GuardCheck {
  id: "lookalike" | "no-account" | "chain-mismatch" | "new-recipient" | "over-limit" | "big";
  level: "warn" | "block";
  text: string;
}

export interface GuardAnswer {
  level: GuardLevel;
  checks: GuardCheck[];
}

export interface GuardInput {
  recipient: string;
  /** The destination chain: where the recipient is paid. */
  chain: NearChain;
  recent?: string[];
  amountInUsd?: number | null;
  dailyLimitUsd?: number;
  spentTodayUsd?: number;
}

export const BIG_USD = 1000;

/** Hex addresses compare without 0x and case; everything else as typed. */
function norm(address: string): string {
  const a = address.trim();
  return /^0x[0-9a-fA-F]+$/.test(a) ? a.slice(2).toLowerCase() : a;
}

/** "0xAb12…9fE0", "7xKX…gAsU": enough of an address to recognise it. */
export function shortAddress(address: string): string {
  const a = address.trim();
  if (a.length <= 14) return a;
  return a.startsWith("0x") ? `${a.slice(0, 6)}…${a.slice(-4)}` : `${a.slice(0, 4)}…${a.slice(-4)}`;
}

const dollars = (n: number) => `$${n.toLocaleString("en-US", { maximumFractionDigits: 2, minimumFractionDigits: n % 1 ? 2 : 0 })}`;

export async function guardRecipient(input: GuardInput, near: NearLookup): Promise<GuardAnswer> {
  const checks: GuardCheck[] = [];
  const recipient = input.recipient.trim();
  const mine = norm(recipient);
  const recent = (input.recent ?? []).map(r => r.trim()).filter(Boolean);

  if (!addressFits(input.chain, recipient)) {
    // The first chain it fits, in the table's order: an EVM address is also
    // a valid NEAR account id, but nobody means that.
    const elsewhere = chainsFor(recipient)[0];
    const said = elsewhere ? (elsewhere.kind === "evm" ? "EVM" : elsewhere.name) : "";
    checks.push({ id: "chain-mismatch", level: "block",
      text: said ? `That's ${/^[AEIOU]/.test(said) ? "an" : "a"} ${said} address, not ${input.chain.name}`
        : `That isn't a ${input.chain.name} address` });
  }

  const known = recent.some(r => norm(r) === mine);
  if (!known && mine.length >= 8) {
    const twin = recent.find(r => {
      const n = norm(r);
      return n.length >= 8 && n !== mine && n.slice(0, 4) === mine.slice(0, 4) && n.slice(-4) === mine.slice(-4);
    });
    if (twin) {
      checks.push({ id: "lookalike", level: "block", text: `Looks like ${shortAddress(twin)} you paid before, but it isn't` });
    }
  }

  if (input.chain.key === "near" && NEAR_NAME.test(recipient)) {
    try {
      if (!(await near.exists(recipient))) checks.push({ id: "no-account", level: "block", text: `No NEAR account ${recipient}` });
    } catch {
      checks.push({ id: "no-account", level: "warn", text: `Couldn't check ${recipient} on NEAR` });
    }
  }

  if (!known) checks.push({ id: "new-recipient", level: "warn", text: "First time paying this address" });

  const usd = typeof input.amountInUsd === "number" && Number.isFinite(input.amountInUsd) ? input.amountInUsd : null;
  if (usd !== null && input.dailyLimitUsd !== undefined) {
    const spent = input.spentTodayUsd ?? 0;
    if (usd + spent > input.dailyLimitUsd) {
      checks.push({ id: "over-limit", level: "warn",
        text: `Over your ${dollars(input.dailyLimitUsd)} a day (${dollars(spent)} spent today)` });
    }
  }
  if (usd !== null && usd > BIG_USD) checks.push({ id: "big", level: "warn", text: `Over ${dollars(BIG_USD)}` });

  const level: GuardLevel = checks.some(c => c.level === "block") ? "block" : checks.length ? "warn" : "ok";
  return { level, checks };
}

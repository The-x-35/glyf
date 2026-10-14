/**
 * Plus and Max paid in USDC on Solana (Solana Pay transfer requests).
 *
 * The server never holds a key. A payment request is a fresh random
 * `reference` (32 bytes, base58) the app puts on the USDC transfer as a
 * read-only account; the treasury is the public address in GLYF_TREASURY.
 * To verify, the server asks Solana for transactions that touch the
 * reference and reads the treasury's USDC balance before and after: the
 * plan starts only once that much USDC has landed.
 *
 * Each reference pays once, and each Solana transaction counts once (a
 * transfer carrying two references doesn't buy two plans).
 */
import { randomBytes } from "node:crypto";
import type { SqlQuery } from "./users.js";

export const USDC_MAINNET = "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v";
export const USDC_DECIMALS = 6;

export type CryptoPlan = "plus" | "max";
export type CryptoPeriod = "month" | "year";

/** Whole dollars, the same as the App Store's US prices (§6.16). */
export const CRYPTO_PRICES: Record<CryptoPlan, Record<CryptoPeriod, number>> = {
  plus: { month: 2, year: 20 },
  max: { month: 5, year: 50 },
};

/** A plan's days, the same as the gift codes'. */
export const PERIOD_DAYS: Record<CryptoPeriod, number> = { month: 30, year: 365 };

// MARK: base58

const ALPHABET = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";

export function base58Encode(bytes: Uint8Array): string {
  let n = 0n;
  for (const b of bytes) n = (n << 8n) | BigInt(b);
  let out = "";
  while (n > 0n) {
    out = ALPHABET[Number(n % 58n)] + out;
    n /= 58n;
  }
  for (const b of bytes) {
    if (b !== 0) break;
    out = "1" + out;
  }
  return out;
}

export function base58Decode(text: string): Uint8Array | null {
  let n = 0n;
  for (const c of text) {
    const i = ALPHABET.indexOf(c);
    if (i < 0) return null;
    n = n * 58n + BigInt(i);
  }
  const bytes: number[] = [];
  while (n > 0n) {
    bytes.unshift(Number(n & 0xffn));
    n >>= 8n;
  }
  for (const c of text) {
    if (c !== "1") break;
    bytes.unshift(0);
  }
  return Uint8Array.from(bytes);
}

/** A Solana address: 32 bytes in base58. */
export function isSolanaAddress(text: string | undefined | null): text is string {
  if (!text || text.length < 32 || text.length > 44) return false;
  return base58Decode(text)?.length === 32;
}

export function newReference(): string {
  return base58Encode(randomBytes(32));
}

/** "2" USDC as base units. */
export function usdcUnits(dollars: number): bigint {
  return BigInt(Math.round(dollars * 100)) * 10n ** BigInt(USDC_DECIMALS - 2);
}

/** The Solana Pay transfer request a wallet opens
 *  (https://docs.solanapay.com/spec). */
export function solanaPayUrl(p: {
  recipient: string; amount: number; mint: string; reference: string; label: string; message: string;
}): string {
  const q = new URLSearchParams({
    amount: String(p.amount),
    "spl-token": p.mint,
    reference: p.reference,
    label: p.label,
    message: p.message,
  });
  return `solana:${p.recipient}?${q.toString().replace(/\+/g, "%20")}`;
}

// MARK: Verifying on Solana

export type Rpc = (method: string, params: unknown[]) => Promise<unknown>;

/** Solana JSON-RPC at [url]: the node's result, or a thrown error. */
export function httpRpc(url: string, fetchImpl: typeof fetch = fetch): Rpc {
  return async (method, params) => {
    const res = await fetchImpl(url, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
      signal: AbortSignal.timeout(15_000),
    });
    const json = await res.json() as { result?: unknown; error?: { message?: string } };
    if (json.error) throw new Error(json.error.message ?? "RPC error");
    return json.result ?? null;
  };
}

export type Found =
  | { status: "paid"; signature: string; received: bigint }
  | { status: "pending" }
  /** A transfer with this reference landed, for less than the price. */
  | { status: "short"; signature: string; received: bigint };

interface TokenBalance {
  owner?: string;
  mint?: string;
  uiTokenAmount?: { amount?: string };
}

/** What [owner] gained in [mint] across a transaction, in base units. */
export function received(meta: { preTokenBalances?: TokenBalance[]; postTokenBalances?: TokenBalance[] },
  owner: string, mint: string): bigint {
  const sum = (list: TokenBalance[] | undefined) => (list ?? [])
    .filter(b => b.owner === owner && b.mint === mint)
    .reduce((total, b) => total + BigInt(b.uiTokenAmount?.amount ?? "0"), 0n);
  return sum(meta.postTokenBalances) - sum(meta.preTokenBalances);
}

/** Looks for a confirmed transaction carrying [reference] that paid the
 *  treasury at least [amount] of [mint]. */
export async function findPayment(rpc: Rpc, p: {
  reference: string; treasury: string; mint: string; amount: bigint;
}): Promise<Found> {
  const sigs = await rpc("getSignaturesForAddress", [p.reference, { limit: 20, commitment: "confirmed" }]);
  const list = (Array.isArray(sigs) ? sigs : []) as { signature?: string; err?: unknown }[];
  let short: Found | null = null;
  // Oldest first: the payment that came first is the one that counts.
  for (const s of [...list].reverse()) {
    if (!s.signature || s.err) continue;
    const tx = await rpc("getTransaction", [s.signature,
      { encoding: "jsonParsed", commitment: "confirmed", maxSupportedTransactionVersion: 0 }]) as
      { meta?: { err?: unknown; preTokenBalances?: TokenBalance[]; postTokenBalances?: TokenBalance[] } } | null;
    if (!tx?.meta || tx.meta.err) continue;
    const got = received(tx.meta, p.treasury, p.mint);
    if (got >= p.amount) return { status: "paid", signature: s.signature, received: got };
    if (got > 0n && !short) short = { status: "short", signature: s.signature, received: got };
  }
  return short ?? { status: "pending" };
}

// MARK: Storage

export interface PaymentRow {
  reference: string;
  userId: string;
  plan: CryptoPlan;
  period: CryptoPeriod;
  amount: bigint;
  mint: string;
  treasury: string;
  signature: string | null;
  /** When the plan this payment bought runs out, fixed once it is paid. */
  expiresAt: Date | null;
}

const DDL = [
  `create table if not exists glyf_crypto_payments (
     reference text primary key,
     user_id text not null,
     plan text not null check (plan in ('plus', 'max')),
     period text not null check (period in ('month', 'year')),
     amount bigint not null check (amount > 0),
     mint text not null,
     treasury text not null,
     created_at timestamptz not null default now(),
     signature text unique,
     paid_at timestamptz,
     expires_at timestamptz
   )`,
  `create index if not exists glyf_crypto_payments_user on glyf_crypto_payments (user_id)`,
];

export class CryptoPayments {
  private schema: Promise<void> | null = null;
  private sqlPromise: Promise<SqlQuery> | null = null;

  constructor(private readonly source: string | SqlQuery | undefined = process.env.DATABASE_URL) {}

  get enabled(): boolean {
    return Boolean(this.source);
  }

  private sql(): Promise<SqlQuery> {
    if (!this.sqlPromise) {
      const source = this.source;
      if (!source) return Promise.reject(new Error("no database"));
      this.sqlPromise = typeof source === "function"
        ? Promise.resolve(source)
        : import("@neondatabase/serverless").then(({ neon }) => {
          const client = neon(source);
          return (async (text, params) =>
            await client.query(text, params as unknown[]) as Record<string, unknown>[]) as SqlQuery;
        });
    }
    return this.sqlPromise;
  }

  private ensureSchema(): Promise<void> {
    if (!this.schema) {
      this.schema = (async () => {
        const sql = await this.sql();
        for (const statement of DDL) {
          try {
            await sql(statement);
          } catch {
            // Two cold instances creating the same table: it exists either way.
          }
        }
      })();
    }
    return this.schema;
  }

  async create(row: Omit<PaymentRow, "signature" | "expiresAt">): Promise<void> {
    await this.ensureSchema();
    const sql = await this.sql();
    await sql(
      `insert into glyf_crypto_payments (reference, user_id, plan, period, amount, mint, treasury)
       values ($1, $2, $3, $4, $5, $6, $7)`,
      [row.reference, row.userId, row.plan, row.period, row.amount.toString(), row.mint, row.treasury]);
  }

  async get(reference: string): Promise<PaymentRow | null> {
    await this.ensureSchema();
    const sql = await this.sql();
    const rows = await sql(
      `select reference, user_id, plan, period, amount, mint, treasury, signature, expires_at
       from glyf_crypto_payments where reference = $1`, [reference]);
    const r = rows[0];
    if (!r) return null;
    return {
      reference: String(r.reference),
      userId: String(r.user_id),
      plan: r.plan === "max" ? "max" : "plus",
      period: r.period === "year" ? "year" : "month",
      amount: BigInt(String(r.amount)),
      mint: String(r.mint),
      treasury: String(r.treasury),
      signature: typeof r.signature === "string" ? r.signature : null,
      expiresAt: r.expires_at ? new Date(r.expires_at as string) : null,
    };
  }

  /** Marks the request paid by [signature], with the plan's end fixed now.
   *  "won" for the one call that does it, "already" when the request was
   *  paid before, "taken" when that transaction already paid another. */
  async markPaid(reference: string, signature: string, expiresAt: Date): Promise<"won" | "already" | "taken"> {
    await this.ensureSchema();
    const sql = await this.sql();
    try {
      const rows = await sql(
        `update glyf_crypto_payments set signature = $2, paid_at = now(), expires_at = $3
         where reference = $1 and signature is null
         returning reference`, [reference, signature, expiresAt.toISOString()]);
      return rows.length > 0 ? "won" : "already";
    } catch (err) {
      if (/unique|duplicate/i.test(err instanceof Error ? err.message : String(err))) return "taken";
      throw err;
    }
  }
}

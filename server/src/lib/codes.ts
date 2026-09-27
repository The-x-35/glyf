/**
 * Gift codes: six letters and digits that put a plan on an account for a
 * set time (a month, a year). Arpit makes them for testers and friends with
 * scripts/make-codes.ts; they live in Postgres next to the accounts.
 *
 * A code works once. Claiming it is one UPDATE that only succeeds while the
 * code is unclaimed, so two phones racing for the same code can't both win.
 */
import { randomInt } from "node:crypto";
import type { SqlQuery } from "./users.js";

/** No 0/O or 1/I/L, so a code copied off a screen or read out can't be
 *  mistyped. 31 characters in six places: about 890 million codes. */
export const CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
export const CODE_LENGTH = 6;

export function makeCode(): string {
  let code = "";
  for (let i = 0; i < CODE_LENGTH; i++) code += CODE_ALPHABET[randomInt(CODE_ALPHABET.length)];
  return code;
}

/** What someone typed, as a code: capitals, without spaces or dashes. Null
 *  when it can't be one (wrong length, not letters and digits). */
export function normalizeCode(input: string): string | null {
  const code = input.toUpperCase().replace(/[\s-]/g, "");
  return new RegExp(`^[A-Z0-9]{${CODE_LENGTH}}$`).test(code) ? code : null;
}

export type Claim =
  | { ok: true; plan: "plus" | "max"; days: number }
  | { ok: false; reason: "unknown" | "used" };

const DDL = [
  `create table if not exists glyf_codes (
     code text primary key,
     plan text not null check (plan in ('plus', 'max')),
     days integer not null check (days > 0),
     note text not null default '',
     created_at timestamptz not null default now(),
     redeemed_by text,
     redeemed_at timestamptz
   )`,
];

export class Codes {
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

  /** Stores new codes. Returns the ones kept: one that clashes with an
   *  existing code is skipped, never overwritten. */
  async add(codes: string[], plan: "plus" | "max", days: number, note = ""): Promise<string[]> {
    await this.ensureSchema();
    const sql = await this.sql();
    const kept: string[] = [];
    for (const code of codes) {
      const rows = await sql(
        `insert into glyf_codes (code, plan, days, note) values ($1, $2, $3, $4)
         on conflict (code) do nothing returning code`, [code, plan, days, note]);
      if (rows.length > 0) kept.push(code);
    }
    return kept;
  }

  /** Claims a code for this account, for good. */
  async claim(code: string, userId: string): Promise<Claim> {
    await this.ensureSchema();
    const sql = await this.sql();
    const rows = await sql(
      `update glyf_codes set redeemed_by = $2, redeemed_at = now()
       where code = $1 and redeemed_by is null
       returning plan, days`, [code, userId]);
    if (rows.length > 0) {
      return { ok: true, plan: rows[0].plan === "max" ? "max" : "plus", days: Number(rows[0].days) };
    }
    const known = await sql(`select redeemed_by from glyf_codes where code = $1`, [code]);
    return { ok: false, reason: known.length > 0 ? "used" : "unknown" };
  }

  /** Gives a claimed code back, when its plan couldn't be put on the account. */
  async release(code: string, userId: string): Promise<void> {
    await this.ensureSchema();
    const sql = await this.sql();
    await sql(
      `update glyf_codes set redeemed_by = null, redeemed_at = null
       where code = $1 and redeemed_by = $2`, [code, userId]);
  }
}

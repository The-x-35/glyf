/**
 * Reports of AI results, flagged from the keyboard's AI panel (Google Play's
 * AI-Generated Content policy: people can report offensive output without
 * leaving the app). A report keeps the result being reported and what kind
 * of request made it, so it can be looked at and the prompts fixed. Never
 * what the person typed, unless it is part of the result itself.
 */
import type { SqlQuery } from "./users.js";

export interface Report {
  /** The signed-in account, when there is one. */
  userId: string | null;
  deviceId: string;
  /** What made the result: "rewrite", "answer", "write", a glyf id… */
  feature: string;
  /** The result as the panel showed it: every version, labelled. */
  result: string;
  /** Why, in the reporter's words, when they gave one. */
  reason: string;
  platform: string;
}

const DDL = [
  `create table if not exists glyf_reports (
     id bigserial primary key,
     user_id text,
     device_id text not null,
     feature text not null,
     result text not null,
     reason text not null default '',
     platform text not null default '',
     created_at timestamptz not null default now()
   )`,
  `create index if not exists glyf_reports_at on glyf_reports (created_at desc)`,
];

export class Reports {
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

  async add(r: Report): Promise<void> {
    await this.ensureSchema();
    const sql = await this.sql();
    await sql(
      `insert into glyf_reports (user_id, device_id, feature, result, reason, platform)
       values ($1, $2, $3, $4, $5, $6)`,
      [r.userId, r.deviceId, r.feature, r.result, r.reason, r.platform]);
  }
}

/** Where the counting happens: Postgres when there is one (production and
 *  any dev box with DATABASE_URL), memory otherwise, so tests and offline
 *  runs still have working caps — just not shared ones. */
import { MemoryLimiter, PostgresLimiter, type Limiter } from "./limits.js";
import type { SqlQuery } from "./users.js";

export function buildLimiter(url = process.env.DATABASE_URL): Limiter {
  // Tests count in memory: a suite must never spend the real database's
  // counters, nor depend on what an earlier run left in them.
  if (!url || process.env.VITEST) return new MemoryLimiter();
  let sql: Promise<SqlQuery> | null = null;
  const lazy: SqlQuery = async (text, params) => {
    sql ??= import("@neondatabase/serverless").then(({ neon }) => {
      const client = neon(url);
      return (async (t, p) => await client.query(t, p as unknown[]) as Record<string, unknown>[]) as SqlQuery;
    });
    return (await sql)(text, params);
  };
  return new PostgresLimiter(lazy);
}

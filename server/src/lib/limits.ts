/** Hard limits on what one account (or one phone, signed out) may spend.
 *
 *  The old meter counted in memory, which on serverless means every cold
 *  instance starts the day again — a cap that isn't one. Counting lives in
 *  Postgres now, incremented and checked in a single statement so two
 *  requests at once can't both squeeze through the last unit.
 *
 *  Two windows guard every model call: a day's worth of runs by plan, and a
 *  burst-per-minute so nothing can drain a day in seconds. The plan comes
 *  from the database, never from the client — a phone can claim what it
 *  likes; the cap it gets is the one on its row.
 */
import type { SqlQuery } from "./users.js";

/** The shape of a query function, so tests can stand in for Postgres. */
export type SqlLike = SqlQuery;

export type Plan = "free" | "plus" | "max";

/** Nobody gets "unlimited": the top plan is a big number, not infinity. */
export interface Caps {
  runsPerDay: number;
  burstPerMinute: number;
}

export function capsFor(plan: Plan, freePerDay: number): Caps {
  switch (plan) {
    case "max": return { runsPerDay: freePerDay * 25, burstPerMinute: 30 };
    case "plus": return { runsPerDay: freePerDay * 10, burstPerMinute: 20 };
    default: return { runsPerDay: freePerDay, burstPerMinute: 12 };
  }
}

export type Window = "day" | "minute";

export function windowStart(kind: Window, now: Date): string {
  const iso = now.toISOString();
  // A day bucket to the date, a minute bucket to the minute.
  return kind === "day" ? `${iso.slice(0, 10)}T00:00:00.000Z` : `${iso.slice(0, 16)}:00.000Z`;
}

export interface Limiter {
  /** Spends one unit. Returns what is left after it, or -1 when the cap is
   *  already spent (nothing is spent in that case). */
  spend(key: string, kind: Window, cap: number, now?: Date): Promise<number>;
  /** What is left without spending anything. */
  left(key: string, kind: Window, cap: number, now?: Date): Promise<number>;
}

/** For tests and for running without a database. */
export class MemoryLimiter implements Limiter {
  private used = new Map<string, number>();

  private slot(key: string, kind: Window, now: Date): string {
    return `${key}|${kind}|${windowStart(kind, now)}`;
  }

  async spend(key: string, kind: Window, cap: number, now = new Date()): Promise<number> {
    const slot = this.slot(key, kind, now);
    const used = this.used.get(slot) ?? 0;
    if (used >= cap) return -1;
    this.used.set(slot, used + 1);
    return cap - used - 1;
  }

  async left(key: string, kind: Window, cap: number, now = new Date()): Promise<number> {
    return Math.max(0, cap - (this.used.get(this.slot(key, kind, now)) ?? 0));
  }
}

export const USAGE_DDL = [
  `create table if not exists glyf_usage (
     key text not null,
     kind text not null,
     window_start timestamptz not null,
     used int not null default 0,
     primary key (key, kind, window_start)
   )`,
  `create index if not exists glyf_usage_window on glyf_usage (window_start)`,
];

/** Counting that survives a cold start, and that two requests can't race:
 *  the increment only happens while the row is still under the cap, so the
 *  statement itself is the check. */
export class PostgresLimiter implements Limiter {
  private ready: Promise<void> | null = null;

  constructor(private readonly sql: SqlQuery) {}

  private ensure(): Promise<void> {
    if (!this.ready) {
      this.ready = (async () => {
        for (const statement of USAGE_DDL) await this.sql(statement);
      })();
      this.ready = this.ready.catch(err => {
        this.ready = null;
        throw err;
      });
    }
    return this.ready;
  }

  async spend(key: string, kind: Window, cap: number, now = new Date()): Promise<number> {
    await this.ensure();
    const rows = await this.sql(
      `insert into glyf_usage (key, kind, window_start, used) values ($1, $2, $3, 1)
       on conflict (key, kind, window_start)
       do update set used = glyf_usage.used + 1 where glyf_usage.used < $4
       returning used`,
      [key, kind, windowStart(kind, now), cap]);
    const used = rows[0]?.used;
    if (typeof used !== "number") return -1;
    if (kind === "day" && Math.random() < 0.02) await this.sweep();
    return Math.max(0, cap - used);
  }

  async left(key: string, kind: Window, cap: number, now = new Date()): Promise<number> {
    await this.ensure();
    const rows = await this.sql(
      `select used from glyf_usage where key = $1 and kind = $2 and window_start = $3`,
      [key, kind, windowStart(kind, now)]);
    const used = typeof rows[0]?.used === "number" ? rows[0].used as number : 0;
    return Math.max(0, cap - used);
  }

  /** Yesterday's rows are of no use to anyone. */
  private async sweep(): Promise<void> {
    try {
      await this.sql(`delete from glyf_usage where window_start < now() - interval '2 days'`);
    } catch {
      // Sweeping is housekeeping; never fail a request over it.
    }
  }
}

export interface Allowance {
  ok: boolean;
  /** Runs left today after this one. */
  remaining: number;
  reason?: "day" | "burst";
}

/** One model call's worth of permission: the minute first (cheap to refuse),
 *  then the day. A refused minute never spends a day's run. */
export async function allow(
  limits: Limiter, key: string, caps: Caps, now = new Date(),
): Promise<Allowance> {
  const burst = await limits.spend(key, "minute", caps.burstPerMinute, now);
  if (burst < 0) {
    return { ok: false, remaining: await limits.left(key, "day", caps.runsPerDay, now), reason: "burst" };
  }
  const day = await limits.spend(key, "day", caps.runsPerDay, now);
  if (day < 0) return { ok: false, remaining: 0, reason: "day" };
  return { ok: true, remaining: day };
}

export function refusal(reason: "day" | "burst" | undefined, plan: Plan): string {
  if (reason === "burst") return "Too fast — wait a moment and try again";
  return plan === "free"
    ? "Daily free runs used up — they come back tomorrow"
    : "Daily runs used up — they come back tomorrow";
}

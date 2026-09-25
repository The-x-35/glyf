/** §6.16 metering, server-side, keyed to the device (account keys come with
 *  auth in M7). Interface first; the in-memory impl is swapped for Postgres
 *  when the hub needs durable state (M5/M6).
 *
 *  Plans (researched against Wispr Flow $12–15/mo, Grammarly ~$12/mo):
 *  free = the shipped daily cap on the fast tier; plus ($1.99) = 10× the cap
 *  and priority; max ($4.99) = 25× the cap. Caps are enforced
 *  HERE; the plan itself is client-asserted until StoreKit receipts land
 *  (M7-ship TODO, same seam). */
export type Plan = "free" | "plus" | "max";

export function planCap(plan: Plan, freePerDay: number): number {
  switch (plan) {
    case "max": return Number.MAX_SAFE_INTEGER;
    case "plus": return freePerDay * 10;
    default: return freePerDay;
  }
}

export interface MeterStore {
  /** Consumes one run if available. Returns remaining after consumption, or -1 if exhausted. */
  consume(deviceId: string, now?: Date, cap?: number): number;
  remaining(deviceId: string, now?: Date, cap?: number): number;
}

export class MemoryMeter implements MeterStore {
  private counts = new Map<string, { day: string; used: number }>();

  constructor(private perDay: number) {}

  private day(now: Date): string {
    return now.toISOString().slice(0, 10);
  }

  private entry(deviceId: string, now: Date): { day: string; used: number } {
    const today = this.day(now);
    const e = this.counts.get(deviceId);
    if (!e || e.day !== today) {
      const fresh = { day: today, used: 0 };
      this.counts.set(deviceId, fresh);
      return fresh;
    }
    return e;
  }

  consume(deviceId: string, now = new Date(), cap = this.perDay): number {
    const e = this.entry(deviceId, now);
    if (e.used >= cap) return -1;
    e.used += 1;
    return Math.min(cap - e.used, 9999);
  }

  remaining(deviceId: string, now = new Date(), cap = this.perDay): number {
    const e = this.entry(deviceId, now);
    return Math.min(Math.max(0, cap - e.used), 9999);
  }
}

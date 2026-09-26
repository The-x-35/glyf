/** §6.16 metering, the in-memory counter the engine tests use. Plans and
 *  their daily caps live in lib/limits.ts, counted in Postgres (Guard). */
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

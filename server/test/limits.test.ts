import { describe, expect, it } from "vitest";
import { signedInApp } from "./helpers.js";
import { env } from "../src/env.js";
import {
  MemoryLimiter, PostgresLimiter, allow, capsFor, suggestCapsFor, windowStart, type SqlLike,
} from "../src/lib/limits.js";

/** A stand-in Postgres that behaves like the real statements do: the insert
 *  only increments while the row is under the cap, and returns nothing when
 *  it isn't. */
function fakeSql() {
  const rows = new Map<string, number>();
  const calls: string[] = [];
  const sql = async (text: string, params: unknown[] = []) => {
    calls.push(text.trim().split(/\s+/).slice(0, 2).join(" "));
    if (text.includes("insert into glyf_usage")) {
      const [key, kind, start, cap] = params as [string, string, string, number];
      const slot = `${key}|${kind}|${start}`;
      const used = rows.get(slot) ?? 0;
      if (used >= cap) return [];
      rows.set(slot, used + 1);
      return [{ used: used + 1 }];
    }
    if (text.includes("select used")) {
      const [key, kind, start] = params as [string, string, string];
      const used = rows.get(`${key}|${kind}|${start}`);
      return used === undefined ? [] : [{ used }];
    }
    return [];
  };
  return { sql: sql as unknown as SqlLike, rows, calls };
}

describe("hard limits", () => {
  it("windows bucket by day and by minute", () => {
    const at = new Date("2026-09-18T14:37:12.500Z");
    expect(windowStart("day", at)).toBe("2026-09-18T00:00:00.000Z");
    expect(windowStart("minute", at)).toBe("2026-09-18T14:37:00.000Z");
  });

  it("gives each plan its own ceiling, and none of them infinity", () => {
    expect(capsFor("free", 40).runsPerDay).toBe(40);
    expect(capsFor("plus", 40).runsPerDay).toBe(400);
    expect(capsFor("max", 40).runsPerDay).toBe(1000);
    expect(Number.isFinite(capsFor("max", 40).runsPerDay)).toBe(true);
    // Suggestions are counted apart, with a ceiling of their own on every plan.
    expect(suggestCapsFor("free", 300)).toEqual({ runsPerDay: 300, burstPerMinute: 20 });
    expect(suggestCapsFor("max", 300).runsPerDay).toBe(7500);
  });

  it("spends a day's runs and then refuses", async () => {
    const limits = new MemoryLimiter();
    expect(await limits.spend("user:a", "day", 2)).toBe(1);
    expect(await limits.spend("user:a", "day", 2)).toBe(0);
    expect(await limits.spend("user:a", "day", 2)).toBe(-1);
    expect(await limits.left("user:a", "day", 2)).toBe(0);
  });

  it("counts each key and each window apart", async () => {
    const limits = new MemoryLimiter();
    await limits.spend("user:a", "day", 1);
    expect(await limits.spend("user:b", "day", 1)).toBe(0);
    const tomorrow = new Date(Date.now() + 25 * 3600 * 1000);
    expect(await limits.spend("user:a", "day", 1, tomorrow)).toBe(0);
  });

  it("refuses a burst without spending the day's runs", async () => {
    const limits = new MemoryLimiter();
    const caps = { runsPerDay: 100, burstPerMinute: 2 };
    expect((await allow(limits, "user:a", caps)).ok).toBe(true);
    expect((await allow(limits, "user:a", caps)).ok).toBe(true);
    const third = await allow(limits, "user:a", caps);
    expect(third.ok).toBe(false);
    expect(third.reason).toBe("burst");
    // Two runs spent, not three: a refused minute costs nothing.
    expect(await limits.left("user:a", "day", 100)).toBe(98);
  });

  it("counts in one statement, so two requests can't both take the last one", async () => {
    const { sql, calls } = fakeSql();
    const limits = new PostgresLimiter(sql);
    const both = await Promise.all([
      limits.spend("user:a", "day", 1),
      limits.spend("user:a", "day", 1),
    ]);
    expect(both.filter(r => r >= 0)).toHaveLength(1);
    expect(both).toContain(-1);
    expect(calls.some(c => c.startsWith("insert into"))).toBe(true);
  });

  it("stops the run stream at the cap, whatever the request claims", async () => {
    const before = env.freeRunsPerDay;
    env.freeRunsPerDay = 1;
    const app = signedInApp();
    const run = (extra: Record<string, unknown>) => app.inject({
      method: "POST", url: "/glyf/run",
      payload: { glyfId: "rewrite.tighten", input: "x", vars: {}, deviceId: "cap-dev-00000001", ...extra },
    });
    expect((await run({})).payload).toContain("event: done");
    expect((await run({ plan: "max" })).payload).toContain("used up");
    expect((await run({ pro: true })).payload).toContain("used up");
    env.freeRunsPerDay = before;
  }, 20_000);

  it("stops /act at the cap too, and says when to come back", async () => {
    const before = env.freeRunsPerDay;
    env.freeRunsPerDay = 1;
    const app = signedInApp();
    const send = () => app.inject({
      method: "POST", url: "/act",
      payload: { text: "sunset", deviceId: "cap-dev-00000002", plan: "max" },
    });
    expect((await send()).statusCode).toBe(200);
    const blocked = await send();
    expect(blocked.statusCode).toBe(429);
    expect(blocked.json().error).toContain("tomorrow");
    env.freeRunsPerDay = before;
  });

  it("holds the same line on translate and vocab", async () => {
    const before = env.freeRunsPerDay;
    env.freeRunsPerDay = 1;
    const app = signedInApp();
    const device = "cap-dev-00000003";
    await app.inject({
      method: "POST", url: "/translate",
      payload: { text: "hola", primary: "English", secondary: "Spanish", deviceId: device },
    });
    const vocab = await app.inject({
      method: "POST", url: "/vocab/generate",
      payload: { description: "cricket words", deviceId: device },
    });
    expect(vocab.statusCode).toBe(429);
    env.freeRunsPerDay = before;
  });

  it("the meter chip reports what is left", async () => {
    const before = env.freeRunsPerDay;
    env.freeRunsPerDay = 3;
    const app = signedInApp();
    const device = "cap-dev-00000004";
    await app.inject({
      method: "POST", url: "/act", payload: { text: "sunset", deviceId: device },
    });
    const res = await app.inject({ method: "GET", url: `/meter/${device}` });
    expect(res.json().remaining).toBe(2);
    env.freeRunsPerDay = before;
  });

  it("refuses a body far larger than anything anyone types", async () => {
    const app = signedInApp();
    const res = await app.inject({
      method: "POST", url: "/act",
      payload: { text: "x".repeat(600 * 1024), deviceId: "cap-dev-00000005" },
    });
    expect([400, 413]).toContain(res.statusCode);
  });
});

describe("asking for something to be written", () => {
  it("routes an instruction to write, not to a search", async () => {
    const { planByRules } = await import("../src/lib/act.js");
    expect(planByRules("Write an essay on dogs")?.intent).toBe("write");
    expect(planByRules("draft a leave email for tomorrow")?.intent).toBe("write");
    expect(planByRules("explain quantum computing")?.intent).toBe("write");
    // Still a place search, not a writing job.
    expect(planByRules("best italian restaurants near me")?.intent).toBe("places");
  });

  it("knows which questions a model must not answer from memory", async () => {
    const { isLive } = await import("../src/lib/act.js");
    expect(isLive("india vs australia score")).toBe(true);
    expect(isLive("weather in pune")).toBe(true);
    expect(isLive("who wrote hamlet")).toBe(false);
  });

  it("writes the thing and offers it to the message", async () => {
    const app = signedInApp();
    const res = await app.inject({
      method: "POST", url: "/act",
      payload: { text: "Write an essay on dogs", deviceId: "write-dev-00000001" },
    });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.intent).toBe("write");
    expect(body.text.length).toBeGreaterThan(0);
    expect(body.insert).toBe(body.text);
  }, 20_000);
});

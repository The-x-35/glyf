import Fastify from "fastify";
import { describe, expect, it } from "vitest";
import { Reports } from "../src/lib/reports.js";
import { reportRoutes } from "../src/routes/report.js";
import type { SqlQuery } from "../src/lib/users.js";

/** Just enough Postgres for glyf_reports. */
function memoryDb(fail = false) {
  const rows: unknown[][] = [];
  const sql: SqlQuery = async (text, params = []) => {
    const t = text.replace(/\s+/g, " ").trim();
    if (/^create\b/i.test(t)) return [];
    if (t.startsWith("insert into glyf_reports")) {
      if (fail) throw new Error("db down");
      rows.push(params as unknown[]);
      return [];
    }
    throw new Error(`unexpected sql: ${t}`);
  };
  return { sql, rows };
}

function app(reports: Reports, now = () => 0) {
  const a = Fastify();
  // What the sign-in gate leaves on a request (lib/protect.ts).
  a.addHook("onRequest", async req => { req.glyfUser = "google:tester"; });
  reportRoutes(a, { reports, now });
  return a;
}

const report = {
  deviceId: "device-12345678",
  feature: "rewrite",
  result: "Professional: I am unable to attend tonight.",
  reason: "rude",
  platform: "android",
};

describe("POST /report", () => {
  it("keeps the flagged result with the account, the phone and the feature", async () => {
    const db = memoryDb();
    const res = await app(new Reports(db.sql)).inject({ method: "POST", url: "/report", payload: report });
    expect(res.json()).toEqual({ ok: true });
    expect(db.rows).toEqual([["google:tester", "device-12345678", "rewrite",
      "Professional: I am unable to attend tonight.", "rude", "android"]]);
  });

  it("turns away a report with nothing in it", async () => {
    const db = memoryDb();
    const res = await app(new Reports(db.sql)).inject({
      method: "POST", url: "/report", payload: { ...report, result: "" } });
    expect(res.statusCode).toBe(400);
    expect(db.rows).toHaveLength(0);
  });

  it("takes ten an hour from one phone, then asks it to wait", async () => {
    const db = memoryDb();
    let t = 0;
    const a = app(new Reports(db.sql), () => t);
    for (let i = 0; i < 10; i++) {
      expect((await a.inject({ method: "POST", url: "/report", payload: report })).statusCode).toBe(200);
    }
    expect((await a.inject({ method: "POST", url: "/report", payload: report })).statusCode).toBe(429);
    t += 3600 * 1000;
    expect((await a.inject({ method: "POST", url: "/report", payload: report })).statusCode).toBe(200);
    expect(db.rows).toHaveLength(11);
  });

  it("says so when it can't be kept", async () => {
    const res = await app(new Reports(memoryDb(true).sql)).inject({ method: "POST", url: "/report", payload: report });
    expect(res.statusCode).toBe(503);
  });

  it("answers ok on a server without a database (a local run)", async () => {
    const res = await app(new Reports(undefined)).inject({ method: "POST", url: "/report", payload: report });
    expect(res.json()).toEqual({ ok: true });
  });
});

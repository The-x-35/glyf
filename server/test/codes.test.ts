import Fastify from "fastify";
import { describe, expect, it } from "vitest";
import { CODE_ALPHABET, Codes, makeCode, normalizeCode } from "../src/lib/codes.js";
import { codeRoutes } from "../src/routes/codes.js";
import { Users, type SqlQuery } from "../src/lib/users.js";

const DAY = 24 * 3600 * 1000;

describe("gift codes", () => {
  it("are six characters nobody can misread", () => {
    const seen = new Set<string>();
    for (let i = 0; i < 2000; i++) {
      const code = makeCode();
      expect(code).toMatch(/^[A-Z2-9]{6}$/);
      expect([...code].every(c => CODE_ALPHABET.includes(c))).toBe(true);
      expect(code).not.toMatch(/[01OIL]/);
      seen.add(code);
    }
    expect(seen.size).toBeGreaterThan(1990);
  });

  it("take what people type: small letters, spaces, a dash", () => {
    expect(normalizeCode("ab3 d-9k")).toBe("AB3D9K");
    expect(normalizeCode("AB3D9")).toBeNull();
    expect(normalizeCode("AB3D9KX")).toBeNull();
    expect(normalizeCode("AB3D9!")).toBeNull();
  });
});

/** Just enough Postgres for codes, purchases and plans. */
function memoryDb() {
  const codes = new Map<string, { plan: string; days: number; redeemed_by: string | null }>();
  const purchases = new Map<string, Record<string, unknown>>();
  const people = new Map<string, Record<string, unknown>>();
  let failPurchases = false;
  const sql: SqlQuery = async (text, params = []) => {
    const t = text.replace(/\s+/g, " ").trim();
    const p = params as unknown[];
    if (/^(create|alter|do)\b/i.test(t)) return [];
    if (t.startsWith("insert into glyf_codes")) {
      if (codes.has(p[0] as string)) return [];
      codes.set(p[0] as string, { plan: p[1] as string, days: p[2] as number, redeemed_by: null });
      return [{ code: p[0] }];
    }
    if (t.startsWith("update glyf_codes set redeemed_by = $2")) {
      const row = codes.get(p[0] as string);
      if (!row || row.redeemed_by !== null) return [];
      row.redeemed_by = p[1] as string;
      return [{ plan: row.plan, days: row.days }];
    }
    if (t.startsWith("select redeemed_by from glyf_codes")) {
      const row = codes.get(p[0] as string);
      return row ? [{ redeemed_by: row.redeemed_by }] : [];
    }
    if (t.startsWith("update glyf_codes set redeemed_by = null")) {
      const row = codes.get(p[0] as string);
      if (row && row.redeemed_by === p[1]) row.redeemed_by = null;
      return [];
    }
    if (t.startsWith("insert into glyf_purchases")) {
      if (failPurchases) throw new Error("database went away");
      const had = purchases.get(p[0] as string);
      if (had && had.user_id !== p[1]) return [];
      purchases.set(p[0] as string, { user_id: p[1], plan: p[3], expires_at: p[4] });
      return [{ user_id: p[1] }];
    }
    if (t.startsWith("select plan, expires_at from glyf_purchases")) {
      return [...purchases.values()]
        .filter(r => r.user_id === p[0] && typeof r.expires_at === "string" && Date.parse(r.expires_at) > Date.now())
        .sort((a, b) => Number(b.plan === "max") - Number(a.plan === "max")
          || Date.parse(b.expires_at as string) - Date.parse(a.expires_at as string))
        .slice(0, 1).map(r => ({ plan: r.plan, expires_at: r.expires_at }));
    }
    if (t.startsWith("insert into glyf_users (user_id, plan, plan_expires_at)")) {
      people.set(p[0] as string, { plan: p[1], plan_expires_at: p[2] });
      return [];
    }
    if (t.startsWith("select plan, plan_expires_at from glyf_users")) {
      const had = people.get(p[0] as string);
      return had ? [had] : [];
    }
    throw new Error(`unexpected sql: ${t.slice(0, 60)}`);
  };
  return { sql, codes, breakPurchases: () => { failPurchases = true; } };
}

describe("POST /codes/redeem", () => {
  async function setup() {
    const db = memoryDb();
    const users = new Users(db.sql);
    const codes = new Codes(db.sql);
    await codes.add(["MONTH2", "MONTH3"], "max", 30, "test");
    await codes.add(["YEAR22"], "max", 365, "test");
    await codes.add(["PLUS22"], "plus", 30, "test");
    const app = Fastify();
    codeRoutes(app, {
      users, codes,
      verifySessionToken: async t => (t.startsWith("user:") ? t.slice(5) : null),
    });
    const send = (who: string, code: string) => app.inject({
      method: "POST", url: "/codes/redeem", headers: { authorization: `Bearer user:${who}` },
      payload: { code },
    });
    return { app, users, db, send };
  }

  it("puts the code's plan on the account for its days", async () => {
    const { users, send } = await setup();
    const res = await send("google:1", "month2");
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body).toMatchObject({ ok: true, plan: "max", codePlan: "max", days: 30 });
    const days = (Date.parse(body.expiresAt) - Date.now()) / DAY;
    expect(days).toBeGreaterThan(29.9);
    expect(days).toBeLessThan(30.1);
    expect(await users.plan("google:1")).toBe("max");
  });

  it("works once: never again, for anyone", async () => {
    const { send } = await setup();
    expect((await send("google:1", "YEAR22")).statusCode).toBe(200);
    const again = await send("google:1", "YEAR22");
    expect(again.statusCode).toBe(409);
    expect(again.json().error).toBe("That code has already been used");
    expect((await send("apple:2", "YEAR22")).statusCode).toBe(409);
  });

  it("adds a second code's days after the first", async () => {
    const { send } = await setup();
    await send("google:3", "MONTH2");
    const body = (await send("google:3", "MONTH3")).json();
    const days = (Date.parse(body.expiresAt) - Date.now()) / DAY;
    expect(days).toBeGreaterThan(59.9);
    expect(days).toBeLessThan(60.1);
  });

  it("keeps Max when a Plus code comes on top of it", async () => {
    const { users, send } = await setup();
    await send("google:4", "MONTH2");
    const body = (await send("google:4", "PLUS22")).json();
    expect(body).toMatchObject({ plan: "max", codePlan: "plus" });
    expect(await users.plan("google:4")).toBe("max");
  });

  it("says what went wrong", async () => {
    const { app, send } = await setup();
    const unknown = await send("google:5", "ZZZZZZ");
    expect(unknown.statusCode).toBe(404);
    expect(unknown.json().error).toBe("That code doesn't exist");
    expect((await send("google:5", "AB")).statusCode).toBe(400);
    const anon = await app.inject({ method: "POST", url: "/codes/redeem", payload: { code: "MONTH2" } });
    expect(anon.statusCode).toBe(401);
  });

  it("stops guessing after ten misses an hour", async () => {
    const { send } = await setup();
    for (let i = 0; i < 10; i++) expect((await send("google:6", `ZZZZZ${"ABCDEFGHJK"[i]}`)).statusCode).toBe(404);
    const blocked = await send("google:6", "MONTH2");
    expect(blocked.statusCode).toBe(429);
    // Another account isn't held up by this one's misses.
    expect((await send("google:7", "MONTH2")).statusCode).toBe(200);
  });

  it("gives the code back when the plan can't be saved", async () => {
    const { db, send } = await setup();
    db.breakPurchases();
    expect((await send("google:8", "MONTH2")).statusCode).toBe(503);
    expect(db.codes.get("MONTH2")?.redeemed_by).toBeNull();
  });
});

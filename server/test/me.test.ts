import Fastify from "fastify";
import { describe, expect, it } from "vitest";
import { meRoutes } from "../src/routes/me.js";
import { cleanPrefs, Users, type SqlQuery } from "../src/lib/users.js";
import { checkConfirmation, issueConfirmation } from "../src/lib/identity.js";
import { MemoryKV } from "../src/lib/store.js";

describe("what is kept about a person", () => {
  it("keeps settings, never vault values or anything unlisted", () => {
    const out = cleanPrefs({
      keyTheme: "site",
      haptics: true,
      bindings: { v: "surface:vault" },
      vaultKinds: ["address", "upi", "12 Hill Road"],
      vault: { fields: [{ kind: "address", value: "12 Hill Road" }] },
      lastLat: 19.07,
      backendURL: "http://x",
    });
    expect(out).toEqual({ keyTheme: "site", haptics: true, bindings: { v: "surface:vault" }, vaultKinds: ["address", "upi"] });
  });
});

describe("/me routes", () => {
  function app(queries: { text: string; params?: unknown[] }[]) {
    const sql: SqlQuery = async (text, params) => {
      queries.push({ text, params });
      return [];
    };
    const f = Fastify();
    meRoutes(f, {
      users: new Users(sql),
      verify: async (t) => (t === "good" ? "google:1234" : null),
    });
    return f;
  }

  it("refuses without a valid session", async () => {
    const res = await app([]).inject({ method: "POST", url: "/me", payload: {} });
    expect(res.statusCode).toBe(401);
    const bad = await app([]).inject({ method: "POST", url: "/me", headers: { authorization: "Bearer nope" }, payload: {} });
    expect(bad.statusCode).toBe(401);
  });

  it("records the phone a signed-in person is on", async () => {
    const queries: { text: string; params?: unknown[] }[] = [];
    const res = await app(queries).inject({
      method: "POST", url: "/me", headers: { authorization: "Bearer good" },
      payload: { platform: "ios", appVersion: "1.0.0", locale: "en-IN", region: "IN", timezone: "Asia/Kolkata" },
    });
    expect(res.json()).toMatchObject({ ok: true, stored: true, user: { id: "google:1234" } });
    // Email and name came from the provider at sign-in; this never overwrites them.
    const upsert = queries.find(q => q.text.includes("insert into glyf_users"));
    expect(upsert?.params?.slice(0, 5)).toEqual(["google:1234", null, null, null, "ios"]);
  });

  it("drops private settings and typed text on the way in", async () => {
    const queries: { text: string; params?: unknown[] }[] = [];
    const f = app(queries);
    await f.inject({
      method: "POST", url: "/me/prefs", headers: { authorization: "Bearer good" },
      payload: { prefs: { keyTheme: "glass", vault: { fields: [{ value: "secret" }] } } },
    });
    const prefs = queries.find(q => q.text.includes("insert into glyf_user_prefs"));
    expect(prefs?.params?.[1]).toBe(JSON.stringify({ keyTheme: "glass" }));

    await f.inject({
      method: "POST", url: "/me/events", headers: { authorization: "Bearer good" },
      payload: { events: [{ name: "demo_send", props: { chat: "neha", draft: "x".repeat(200), n: 2 } }] },
    });
    const event = queries.find(q => q.text.includes("insert into glyf_events"));
    expect(event?.params?.[2]).toBe(JSON.stringify({ chat: "neha", n: 2 }));
  });
});

describe("Delete account", () => {
  const SECRET = "confirm-test-secret";
  const ME = "google:1234";
  const PHONE = "phone-0000-aaaa";
  const OTHER = "phone-1111-bbbb";
  type Q = { text: string; params?: unknown[] };

  function app(queries: Q[], opts: { kv?: MemoryKV; fail?: (text: string) => Error | null; db?: boolean } = {}) {
    const sql: SqlQuery = async (text, params) => {
      const err = opts.fail?.(text);
      if (err) throw err;
      queries.push({ text, params });
      return [];
    };
    const f = Fastify();
    meRoutes(f, {
      users: new Users(opts.db === false ? undefined : sql),
      verify: async (t) => (t === "good" ? ME : t === "other" ? "apple:9999" : null),
      kv: opts.kv,
      confirmSecret: SECRET,
    });
    return f;
  }

  const auth = (who = "good") => ({ authorization: `Bearer ${who}` });

  async function confirmFor(f: ReturnType<typeof app>, who = "good"): Promise<string> {
    const res = await f.inject({ method: "POST", url: "/me/delete", headers: auth(who) });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ ok: true, expiresIn: 300 });
    return res.json().confirm as string;
  }

  /** What one phone and one other phone have on the server. */
  function seeded(): MemoryKV {
    const kv = new MemoryKV();
    kv.put("userglyfs", "g-mine", { ownerId: PHONE, def: {} });
    kv.put("userglyfs", "g-theirs", { ownerId: OTHER, def: {} });
    kv.put("hub", "g-mine", { ownerId: PHONE, installs: 3 });
    kv.put("hub", "g-theirs", { ownerId: OTHER, installs: 1 });
    kv.put("accounts", PHONE, { displayName: "Me" });
    kv.put("accounts", OTHER, { displayName: "Them" });
    kv.put("devices", PHONE, { days: ["2026-11-01"] });
    kv.put("devices", OTHER, { days: ["2026-11-01"] });
    kv.put("installs", `${PHONE}:g-theirs`, { version: 1 });
    kv.put("installs", `${OTHER}:g-mine`, { version: 1 });
    kv.put("skill-installs-by", `${PHONE}:fix.grammar`, true);
    kv.put("skill-installs-by", `${OTHER}:fix.grammar`, true);
    kv.put("connections", `${PHONE}:google`, { accessToken: "a" });
    kv.put("connections", `${OTHER}:google`, { accessToken: "b" });
    kv.put("oauth_pending", "state-1", { deviceId: PHONE, createdAt: Date.now() });
    kv.put("oauth_pending", "state-2", { deviceId: OTHER, createdAt: Date.now() });
    kv.put("telemetry", "2026-11-01:app_open", { count: 4 });
    return kv;
  }

  it("needs a session", async () => {
    const f = app([]);
    expect((await f.inject({ method: "POST", url: "/me/delete" })).statusCode).toBe(401);
    expect((await f.inject({ method: "DELETE", url: "/me", payload: { confirm: "x" } })).statusCode).toBe(401);
  });

  it("needs a fresh confirmation, not just the session", async () => {
    const queries: Q[] = [];
    const f = app(queries);
    const none = await f.inject({ method: "DELETE", url: "/me", headers: auth() });
    expect(none.statusCode).toBe(428);
    expect(none.json()).toMatchObject({ ok: false, confirm: "required" });
    const made = await f.inject({ method: "DELETE", url: "/me", headers: auth(), payload: { confirm: "123.abc" } });
    expect(made.statusCode).toBe(428);

    // Someone else's confirmation doesn't delete this account.
    const theirs = await confirmFor(f, "other");
    const swapped = await f.inject({ method: "DELETE", url: "/me", headers: auth(), payload: { confirm: theirs } });
    expect(swapped.statusCode).toBe(428);

    // Nor does one that has run out.
    const old = issueConfirmation(ME, "delete-account", { secret: SECRET, now: Date.now() - 301_000 })!;
    expect(checkConfirmation(old, ME, "delete-account", { secret: SECRET })).toBe(false);
    const stale = await f.inject({ method: "DELETE", url: "/me", headers: auth(), payload: { confirm: old } });
    expect(stale.statusCode).toBe(428);
    expect(queries.some(q => q.text.startsWith("delete"))).toBe(false);
  });

  it("deletes the account and everything kept with it", async () => {
    const queries: Q[] = [];
    const f = app(queries);
    const confirm = await confirmFor(f);
    const res = await f.inject({ method: "DELETE", url: "/me", headers: auth(),
      payload: { confirm, deviceIds: [PHONE] } });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ ok: true, stored: true });

    const ran = (fragment: string) => queries.find(q => q.text.includes(fragment));
    expect(ran("delete from glyf_users")?.params).toEqual([ME]);
    expect(ran("delete from glyf_purchases")?.params).toEqual([ME]);
    expect(ran("delete from glyf_crypto_payments")?.params).toEqual([ME]);
    expect(ran("delete from glyf_reports")?.params).toEqual([ME, [PHONE]]);
    expect(ran("update glyf_codes")?.params).toEqual([ME]);
    const usage = ran("delete from glyf_usage")?.params?.[0] as string[];
    expect(usage).toEqual(expect.arrayContaining([
      `user:${ME}`, `user:${ME}|req`, `suggest:user:${ME}`, `translate:user:${ME}`,
      `device:${PHONE}`, `suggest:device:${PHONE}`, `translate:device:${PHONE}`,
    ]));
    // Prefs and events hang off glyf_users (on delete cascade); the row
    // itself goes last, so a run cut short can be run again.
    const deletes = queries.filter(q => /^\s*(delete|update)/.test(q.text));
    expect(deletes.at(-1)?.text).toContain("delete from glyf_users");
  });

  it("forgets what is filed under the phone, and only that phone", async () => {
    const kv = seeded();
    const f = app([], { kv });
    const confirm = await confirmFor(f);
    const res = await f.inject({ method: "DELETE", url: "/me", headers: auth(),
      payload: { confirm, deviceIds: [PHONE] } });
    expect(res.statusCode).toBe(200);
    const ids = (c: string) => kv.list(c).map(e => e.id).sort();
    expect(ids("userglyfs")).toEqual(["g-theirs"]);
    expect(ids("hub")).toEqual(["g-theirs"]);
    expect(ids("accounts")).toEqual([OTHER]);
    expect(ids("devices")).toEqual([OTHER]);
    expect(ids("installs")).toEqual([`${OTHER}:g-mine`]);
    expect(ids("skill-installs-by")).toEqual([`${OTHER}:fix.grammar`]);
    expect(ids("connections")).toEqual([`${OTHER}:google`]);
    expect(ids("oauth_pending")).toEqual(["state-2"]);
    // Day counts carry no phone or account.
    expect(ids("telemetry")).toEqual(["2026-11-01:app_open"]);
  });

  it("can be asked again: nothing left, still ok", async () => {
    const kv = seeded();
    const f = app([], { kv });
    const confirm = await confirmFor(f);
    const payload = { confirm, deviceIds: [PHONE] };
    const first = await f.inject({ method: "DELETE", url: "/me", headers: auth(), payload });
    const again = await f.inject({ method: "DELETE", url: "/me", headers: auth(), payload });
    expect([first.statusCode, again.statusCode]).toEqual([200, 200]);
    expect(again.json()).toEqual({ ok: true, stored: true });
  });

  it("skips tables that were never made, but says so when the database fails", async () => {
    const missing = Object.assign(new Error('relation "glyf_crypto_payments" does not exist'), { code: "42P01" });
    const queries: Q[] = [];
    const tolerant = app(queries, { fail: t => t.includes("glyf_crypto_payments") || t.includes("glyf_codes") ? missing : null });
    const confirm = await confirmFor(tolerant);
    const ok = await tolerant.inject({ method: "DELETE", url: "/me", headers: auth(), payload: { confirm } });
    expect(ok.statusCode).toBe(200);
    expect(queries.some(q => q.text.includes("delete from glyf_users"))).toBe(true);

    const kv = seeded();
    const down = app([], { kv, fail: t => t.includes("glyf_purchases where") ? new Error("connection reset") : null });
    const c2 = await confirmFor(down);
    const failed = await down.inject({ method: "DELETE", url: "/me", headers: auth(),
      payload: { confirm: c2, deviceIds: [PHONE] } });
    expect(failed.statusCode).toBe(503);
    expect(failed.json()).toMatchObject({ ok: false });
    // Nothing is half-forgotten on the phone's side either: try again later.
    expect(kv.get("connections", `${PHONE}:google`)).toBeDefined();
  });

  it("still forgets the phone's data on a server without a database", async () => {
    const kv = seeded();
    const f = app([], { kv, db: false });
    const confirm = await confirmFor(f);
    const res = await f.inject({ method: "DELETE", url: "/me", headers: auth(),
      payload: { confirm, deviceIds: [PHONE] } });
    expect(res.json()).toEqual({ ok: true, stored: false });
    expect(kv.get("connections", `${PHONE}:google`)).toBeUndefined();
  });
});

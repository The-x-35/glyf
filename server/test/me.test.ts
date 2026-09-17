import Fastify from "fastify";
import { describe, expect, it } from "vitest";
import { meRoutes } from "../src/routes/me.js";
import { cleanPrefs, Users, type SqlQuery } from "../src/lib/users.js";

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

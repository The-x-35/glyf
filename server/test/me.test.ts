import { generateKeyPairSync, sign } from "node:crypto";
import Fastify from "fastify";
import { beforeEach, describe, expect, it } from "vitest";
import { meRoutes } from "../src/routes/me.js";
import { cleanPrefs, resetKeyCacheForTests, Users, verifyPrivyToken, type SqlQuery } from "../src/lib/users.js";

const APP = "app-under-test";

function keys() {
  const { privateKey, publicKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
  const jwk = { ...publicKey.export({ format: "jwk" }), kid: "k1", alg: "ES256", use: "sig" };
  return { privateKey, jwk };
}

function token(privateKey: ReturnType<typeof keys>["privateKey"], claims: Record<string, unknown>, kid = "k1") {
  const h = Buffer.from(JSON.stringify({ alg: "ES256", typ: "JWT", kid })).toString("base64url");
  const p = Buffer.from(JSON.stringify(claims)).toString("base64url");
  const s = sign("sha256", Buffer.from(`${h}.${p}`), { key: privateKey, dsaEncoding: "ieee-p1363" });
  return `${h}.${p}.${s.toString("base64url")}`;
}

describe("Privy session check", () => {
  beforeEach(() => resetKeyCacheForTests());

  it("accepts a token Privy signed for this app and nothing else", async () => {
    const { privateKey, jwk } = keys();
    const fetchImpl = (async () => new Response(JSON.stringify({ keys: [jwk] }))) as typeof fetch;
    const now = Date.now();
    const good = { iss: "privy.io", aud: APP, sub: "did:privy:abc", exp: now / 1000 + 600 };
    expect(await verifyPrivyToken(token(privateKey, good), { appId: APP, fetchImpl, now })).toBe("did:privy:abc");
    // Another app's token, an expired one, a forged one.
    expect(await verifyPrivyToken(token(privateKey, { ...good, aud: "other" }), { appId: APP, fetchImpl, now })).toBeNull();
    expect(await verifyPrivyToken(token(privateKey, { ...good, exp: now / 1000 - 120 }), { appId: APP, fetchImpl, now })).toBeNull();
    const forged = keys();
    expect(await verifyPrivyToken(token(forged.privateKey, good), { appId: APP, fetchImpl, now })).toBeNull();
    expect(await verifyPrivyToken("not.a.token", { appId: APP, fetchImpl, now })).toBeNull();
  });
});

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
      verify: async (t) => (t === "good" ? "did:privy:abc" : null),
      profile: async () => ({ email: "a@b.co", name: "Asha", method: "google" }),
    });
    return f;
  }

  it("refuses without a valid session", async () => {
    const res = await app([]).inject({ method: "POST", url: "/me", payload: {} });
    expect(res.statusCode).toBe(401);
    const bad = await app([]).inject({ method: "POST", url: "/me", headers: { authorization: "Bearer nope" }, payload: {} });
    expect(bad.statusCode).toBe(401);
  });

  it("stores who signed in with the email Privy vouches for", async () => {
    const queries: { text: string; params?: unknown[] }[] = [];
    const res = await app(queries).inject({
      method: "POST", url: "/me", headers: { authorization: "Bearer good" },
      payload: { platform: "ios", appVersion: "1.0.0", locale: "en-IN", region: "IN", timezone: "Asia/Kolkata" },
    });
    expect(res.json()).toMatchObject({ ok: true, stored: true, user: { id: "did:privy:abc", email: "a@b.co" } });
    const upsert = queries.find(q => q.text.includes("insert into glyf_users"));
    expect(upsert?.params?.slice(0, 5)).toEqual(["did:privy:abc", "a@b.co", "Asha", "google", "ios"]);
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

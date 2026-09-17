import { createHash, generateKeyPairSync, sign, type KeyObject } from "node:crypto";
import Fastify from "fastify";
import { beforeEach, describe, expect, it } from "vitest";
import { authRoutes } from "../src/routes/auth.js";
import {
  issueSession, resetKeyCacheForTests, signInConfig, verifyIdToken, verifySession,
} from "../src/lib/identity.js";
import { Users, type SqlQuery } from "../src/lib/users.js";

const NOW = Date.parse("2026-09-17T12:00:00Z");
const SEC = NOW / 1000;
const NONCE = "nonce-made-for-this-sign-in";
const WEB = "123-web.apps.googleusercontent.com";
const IOS = "123-ios.apps.googleusercontent.com";

function rsa(kid = "k1") {
  const { privateKey, publicKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
  return { privateKey, jwk: { ...publicKey.export({ format: "jwk" }), kid, alg: "RS256", use: "sig" } };
}

function b64(value: unknown): string {
  return Buffer.from(JSON.stringify(value)).toString("base64url");
}

function idToken(key: KeyObject, claims: Record<string, unknown>, kid = "k1"): string {
  const h = b64({ alg: "RS256", typ: "JWT", kid });
  const p = b64(claims);
  return `${h}.${p}.${sign("RSA-SHA256", Buffer.from(`${h}.${p}`), key).toString("base64url")}`;
}

function keysFetch(...jwks: object[]) {
  return (async () => new Response(JSON.stringify({ keys: jwks }))) as unknown as typeof fetch;
}

describe("Apple and Google ID tokens", () => {
  beforeEach(() => resetKeyCacheForTests());

  const google = {
    iss: "https://accounts.google.com", aud: WEB, sub: "1234", email: "asha@gmail.com",
    email_verified: true, name: "Asha Rao", iat: SEC - 10, exp: SEC + 3600, nonce: NONCE,
  };

  it("accepts Google's token for this app with this sign-in's nonce, and nothing else", async () => {
    const { privateKey, jwk } = rsa();
    const opts = { nonce: NONCE, audiences: [WEB, IOS], fetchImpl: keysFetch(jwk), now: NOW };
    expect(await verifyIdToken("google", idToken(privateKey, google), opts))
      .toEqual({ provider: "google", sub: "1234", email: "asha@gmail.com", name: "Asha Rao" });
    // The iPhone client is an audience too.
    expect(await verifyIdToken("google", idToken(privateKey, { ...google, aud: IOS }), opts)).not.toBeNull();

    const refused = [
      { ...google, aud: "someone-elses-app" },
      { ...google, exp: SEC - 3600 },
      { ...google, nonce: "a-nonce-from-another-sign-in" },
      { ...google, iss: "https://accounts.example.com" },
      { ...google, iat: SEC + 3600 },
    ];
    for (const claims of refused) {
      expect(await verifyIdToken("google", idToken(privateKey, claims), opts)).toBeNull();
    }
    // Signed by someone else's key, or not a token at all.
    expect(await verifyIdToken("google", idToken(rsa().privateKey, google), opts)).toBeNull();
    expect(await verifyIdToken("google", "not.a.token", opts)).toBeNull();
  });

  it("keeps only a verified email", async () => {
    const { privateKey, jwk } = rsa();
    const opts = { nonce: NONCE, audiences: [WEB], fetchImpl: keysFetch(jwk), now: NOW };
    const id = await verifyIdToken("google", idToken(privateKey, { ...google, email_verified: false }), opts);
    expect(id).toEqual({ provider: "google", sub: "1234", email: undefined, name: "Asha Rao" });
  });

  it("checks Apple's nonce as its SHA-256 and Apple's audience as the bundle id", async () => {
    const { privateKey, jwk } = rsa();
    const apple = {
      iss: "https://appleid.apple.com", aud: "com.demo.glyf", sub: "001234.abcd",
      email: "x7@privaterelay.appleid.com", email_verified: "true", iat: SEC - 5, exp: SEC + 600,
      nonce: createHash("sha256").update(NONCE).digest("hex"),
    };
    const opts = { nonce: NONCE, audiences: ["com.demo.glyf"], fetchImpl: keysFetch(jwk), now: NOW };
    expect(await verifyIdToken("apple", idToken(privateKey, apple), opts))
      .toEqual({ provider: "apple", sub: "001234.abcd", email: "x7@privaterelay.appleid.com", name: undefined });
    expect(await verifyIdToken("apple", idToken(privateKey, { ...apple, nonce: NONCE }), opts)).toBeNull();
    expect(await verifyIdToken("apple", idToken(privateKey, { ...apple, aud: "com.other.app" }), opts)).toBeNull();
    // A Google token is not an Apple one.
    expect(await verifyIdToken("apple", idToken(privateKey, google), opts)).toBeNull();
  });

  it("fetches the keys again when a token names one it has not seen", async () => {
    const old = rsa("old");
    const rotated = rsa("new");
    let calls = 0;
    const fetchImpl = (async () => {
      calls++;
      return new Response(JSON.stringify({ keys: calls === 1 ? [old.jwk] : [old.jwk, rotated.jwk] }));
    }) as unknown as typeof fetch;
    const opts = { nonce: NONCE, audiences: [WEB], fetchImpl, now: NOW };
    expect(await verifyIdToken("google", idToken(old.privateKey, google, "old"), opts)).not.toBeNull();
    expect(await verifyIdToken("google", idToken(rotated.privateKey, google, "new"), opts)).not.toBeNull();
    expect(calls).toBe(2);
  });
});

describe("Glyf sessions", () => {
  it("round-trip, and refuse a tampered, expired or foreign one", () => {
    const token = issueSession("google:1234", { secret: "s3cret", now: NOW })!;
    expect(verifySession(token, { secret: "s3cret", now: NOW })).toBe("google:1234");
    expect(verifySession(token, { secret: "another-secret", now: NOW })).toBeNull();
    expect(verifySession(token, { secret: "s3cret", now: NOW + 181 * 86_400_000 })).toBeNull();
    const [h, , s] = token.split(".");
    const swapped = b64({ iss: "glyf", sub: "apple:someone-else", iat: SEC, exp: SEC + 3600 });
    expect(verifySession(`${h}.${swapped}.${s}`, { secret: "s3cret", now: NOW })).toBeNull();
    expect(issueSession("google:1234", { secret: "" })).toBeNull();
  });
});

describe("sign-in config", () => {
  it("shares public client ids only, once sessions can be issued", () => {
    expect(signInConfig({ GOOGLE_CLIENT_ID: WEB, GOOGLE_IOS_CLIENT_ID: IOS, SESSION_SECRET: "x" }))
      .toEqual({ google: { webClientId: WEB, iosClientId: IOS }, apple: true });
    expect(signInConfig({ GOOGLE_CLIENT_ID: WEB })).toEqual({ google: null, apple: false });
    expect(JSON.stringify(signInConfig({ GOOGLE_CLIENT_ID: WEB, SESSION_SECRET: "never-shared" })))
      .not.toContain("never-shared");
  });
});

describe("POST /auth/session", () => {
  const nonce = "n".repeat(24);

  function app(queries: { text: string; params?: unknown[] }[]) {
    const sql: SqlQuery = async (text, params) => {
      queries.push({ text, params });
      return [];
    };
    const f = Fastify();
    authRoutes(f, {
      users: new Users(sql),
      verify: async (provider, token, n) => (token === "a-verified-provider-id-token" && n === nonce
        ? { provider, sub: "1234", email: "asha@gmail.com", name: provider === "google" ? "Asha Rao" : undefined }
        : null),
      issue: (id) => `session-for-${id}`,
    });
    return f;
  }

  it("turns a verified token into a session and saves the person", async () => {
    const queries: { text: string; params?: unknown[] }[] = [];
    const res = await app(queries).inject({
      method: "POST", url: "/auth/session",
      payload: { provider: "google", idToken: "a-verified-provider-id-token", nonce, device: { platform: "android", locale: "en-IN" } },
    });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({
      ok: true, token: "session-for-google:1234",
      user: { id: "google:1234", provider: "google", email: "asha@gmail.com", name: "Asha Rao" },
    });
    const upsert = queries.find(q => q.text.includes("insert into glyf_users"));
    expect(upsert?.params?.slice(0, 5)).toEqual(["google:1234", "asha@gmail.com", "Asha Rao", "google", "android"]);
  });

  it("takes the name Apple gave the phone, and only for Apple", async () => {
    const queries: { text: string; params?: unknown[] }[] = [];
    const f = app(queries);
    const apple = await f.inject({
      method: "POST", url: "/auth/session",
      payload: { provider: "apple", idToken: "a-verified-provider-id-token", nonce, name: "Asha Rao" },
    });
    expect(apple.json().user).toMatchObject({ id: "apple:1234", name: "Asha Rao" });
    const google = await f.inject({
      method: "POST", url: "/auth/session",
      payload: { provider: "google", idToken: "a-verified-provider-id-token", nonce, name: "Someone Else" },
    });
    expect(google.json().user.name).toBe("Asha Rao");
  });

  it("refuses a token that does not verify, and a malformed request", async () => {
    const f = app([]);
    const bad = await f.inject({
      method: "POST", url: "/auth/session",
      payload: { provider: "google", idToken: "a-token-nobody-signed-here", nonce },
    });
    expect(bad.statusCode).toBe(401);
    const malformed = await f.inject({ method: "POST", url: "/auth/session", payload: { provider: "github" } });
    expect(malformed.statusCode).toBe(400);
  });
});

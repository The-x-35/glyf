import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createPrivateKey, sign, X509Certificate } from "node:crypto";
import Fastify from "fastify";
import { beforeAll, describe, expect, it } from "vitest";
import { AppleSignatureError, planOf, verifyAppleJws, type AppleTransaction } from "../src/lib/appstore.js";
import { billingRoutes } from "../src/routes/billing.js";
import { Users, type SqlQuery } from "../src/lib/users.js";

const b64url = (b: Buffer | string) => Buffer.from(b).toString("base64url");
const DAY = 24 * 3600 * 1000;

/** A throwaway root → intermediate → leaf chain shaped like Apple's (P-256,
 *  Apple's marker extensions), made with openssl so the real checks run. */
function makeChain() {
  const dir = mkdtempSync(join(tmpdir(), "glyf-appstore-"));
  const run = (...args: string[]) => execFileSync("openssl", args, { cwd: dir, stdio: "pipe" });
  for (const name of ["root", "int", "leaf"]) run("ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", `${name}.key`);
  run("req", "-new", "-x509", "-key", "root.key", "-out", "root.pem", "-days", "3650", "-subj", "/CN=Test Root");
  writeFileSync(join(dir, "int.ext"), "basicConstraints=critical,CA:true\n1.2.840.113635.100.6.2.1=ASN1:NULL\n");
  writeFileSync(join(dir, "leaf.ext"), "1.2.840.113635.100.6.11.1=ASN1:NULL\n");
  run("req", "-new", "-key", "int.key", "-out", "int.csr", "-subj", "/CN=Test Intermediate");
  run("x509", "-req", "-in", "int.csr", "-CA", "root.pem", "-CAkey", "root.key", "-CAcreateserial", "-out", "int.pem", "-days", "3650", "-extfile", "int.ext");
  run("req", "-new", "-key", "leaf.key", "-out", "leaf.csr", "-subj", "/CN=Test Leaf");
  run("x509", "-req", "-in", "leaf.csr", "-CA", "int.pem", "-CAkey", "int.key", "-CAcreateserial", "-out", "leaf.pem", "-days", "3650", "-extfile", "leaf.ext");
  const cert = (n: string) => new X509Certificate(readFileSync(join(dir, `${n}.pem`)));
  return { leaf: cert("leaf"), int: cert("int"), root: cert("root"), key: createPrivateKey(readFileSync(join(dir, "leaf.key"))) };
}

function signJws(payload: object, chain: ReturnType<typeof makeChain>, x5c = [chain.leaf, chain.int, chain.root]) {
  const h = b64url(JSON.stringify({ alg: "ES256", x5c: x5c.map(c => c.raw.toString("base64")) }));
  const p = b64url(JSON.stringify(payload));
  const sig = sign("sha256", Buffer.from(`${h}.${p}`), { key: chain.key, dsaEncoding: "ieee-p1363" });
  return `${h}.${p}.${b64url(sig)}`;
}

const tx = (over: Partial<AppleTransaction> = {}): AppleTransaction => ({
  transactionId: "2000000001", originalTransactionId: "2000000001", bundleId: "com.arpit.glyf",
  productId: "com.arpit.glyf.plus.monthly", expiresDate: Date.now() + 30 * DAY, environment: "Sandbox", ...over,
});

describe("Apple's signed transactions", () => {
  let chain: ReturnType<typeof makeChain>;
  beforeAll(() => { chain = makeChain(); });

  it("takes a transaction whose chain ends in the pinned root", () => {
    const got = verifyAppleJws<AppleTransaction>(signJws(tx(), chain), { rootFingerprint: chain.root.fingerprint256 });
    expect(got.productId).toBe("com.arpit.glyf.plus.monthly");
  });

  it("refuses anything Apple didn't sign", () => {
    const good = signJws(tx(), chain);
    // Any other root, Apple's pin included, is not this chain's.
    expect(() => verifyAppleJws(good)).toThrow(AppleSignatureError);
    // A payload changed after signing.
    const [h, , s] = good.split(".");
    const forged = `${h}.${b64url(JSON.stringify(tx({ productId: "com.arpit.glyf.max.yearly" })))}.${s}`;
    expect(() => verifyAppleJws(forged, { rootFingerprint: chain.root.fingerprint256 })).toThrow("bad signature");
    // A chain with a certificate missing.
    expect(() => verifyAppleJws(signJws(tx(), chain, [chain.leaf, chain.root]), { rootFingerprint: chain.root.fingerprint256 }))
      .toThrow(AppleSignatureError);
    expect(() => verifyAppleJws("not.a-jws")).toThrow(AppleSignatureError);
  });

  it("takes StoreKit testing's local signature only in development", () => {
    const local = signJws(tx({ environment: "Xcode" }), chain, [chain.leaf]);
    expect(() => verifyAppleJws(local)).toThrow("StoreKit testing outside development");
    expect(verifyAppleJws<AppleTransaction>(local, { allowXcode: true }).environment).toBe("Xcode");
  });

  it("grants only this app's running subscriptions", () => {
    expect(planOf(tx(), "com.arpit.glyf")?.plan).toBe("plus");
    expect(planOf(tx({ productId: "com.arpit.glyf.max.yearly" }), "com.arpit.glyf")?.plan).toBe("max");
    expect(planOf(tx({ bundleId: "com.other.app" }), "com.arpit.glyf")).toBeNull();
    expect(planOf(tx({ productId: "com.arpit.glyf.lifetime" }), "com.arpit.glyf")).toBeNull();
    expect(planOf(tx({ revocationDate: Date.now() }), "com.arpit.glyf")).toBeNull();
    expect(planOf(tx({ expiresDate: Date.now() - 1000 }), "com.arpit.glyf")).toBeNull();
  });
});

/** Just enough Postgres for the purchase queries. */
function memoryDb() {
  const purchases = new Map<string, Record<string, unknown>>();
  const people = new Map<string, Record<string, unknown>>();
  const sql: SqlQuery = async (text, params = []) => {
    const t = text.replace(/\s+/g, " ").trim();
    const p = params as string[];
    if (/^(create|alter|do)\b/i.test(t)) return [];
    if (t.startsWith("insert into glyf_purchases")) {
      const had = purchases.get(p[0]);
      if (had && had.user_id !== p[1]) return [];
      purchases.set(p[0], { user_id: p[1], product_id: p[2], plan: p[3], expires_at: p[4], environment: p[5] });
      return [{ user_id: p[1] }];
    }
    if (t.startsWith("select user_id from glyf_purchases")) {
      const had = purchases.get(p[0]);
      return had ? [{ user_id: had.user_id }] : [];
    }
    if (t.startsWith("select plan, expires_at from glyf_purchases")) {
      return [...purchases.values()]
        .filter(r => r.user_id === p[0] && typeof r.expires_at === "string" && Date.parse(r.expires_at) > Date.now())
        .sort((a, b) => Number(b.plan === "max") - Number(a.plan === "max")
          || Date.parse(b.expires_at as string) - Date.parse(a.expires_at as string))
        .slice(0, 1).map(r => ({ plan: r.plan, expires_at: r.expires_at }));
    }
    if (t.startsWith("insert into glyf_users (user_id, plan, plan_expires_at)")) {
      people.set(p[0], { plan: p[1], plan_expires_at: p[2] });
      return [];
    }
    if (t.startsWith("select plan, plan_expires_at from glyf_users")) {
      const had = people.get(p[0]);
      return had ? [had] : [];
    }
    throw new Error(`unexpected sql: ${t.slice(0, 60)}`);
  };
  return { users: new Users(sql) };
}

describe("POST /billing/apple", () => {
  function setup() {
    const { users } = memoryDb();
    const app = Fastify();
    billingRoutes(app, {
      users,
      verifySessionToken: async t => (t.startsWith("user:") ? t.slice(5) : null),
      // The signature check has its own tests: here a "JWS" is the payload.
      verifySigned: jws => JSON.parse(Buffer.from(jws, "base64url").toString("utf8")),
    });
    const send = (who: string, ...txs: AppleTransaction[]) => app.inject({
      method: "POST", url: "/billing/apple", headers: { authorization: `Bearer user:${who}` },
      payload: { transactions: txs.map(t => b64url(JSON.stringify(t)).padEnd(20, "A")) },
    });
    return { app, users, send };
  }

  it("puts a verified purchase's plan on the account", async () => {
    const { users, send } = setup();
    const res = await send("google:1", tx());
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ ok: true, plan: "plus" });
    expect(await users.plan("google:1")).toBe("plus");
  });

  it("keeps Max over Plus, and free once everything has run out", async () => {
    const { users, send } = setup();
    await send("google:2", tx({ originalTransactionId: "a" }), tx({ originalTransactionId: "b", productId: "com.arpit.glyf.max.monthly" }));
    expect(await users.plan("google:2")).toBe("max");
    const lapsed = await send("google:3", tx({ originalTransactionId: "c", expiresDate: Date.now() - DAY }));
    expect(lapsed.json().plan).toBe("free");
    expect(await users.plan("google:3")).toBe("free");
  });

  it("never lets a second account use someone else's subscription", async () => {
    const { users, send } = setup();
    await send("google:4", tx({ originalTransactionId: "shared" }));
    const other = await send("apple:5", tx({ originalTransactionId: "shared" }));
    expect(other.statusCode).toBe(409);
    expect(await users.plan("apple:5")).toBe("free");
    expect(await users.plan("google:4")).toBe("plus");
  });

  it("refuses without a session, and anything for another app", async () => {
    const { app, send } = setup();
    const res = await app.inject({ method: "POST", url: "/billing/apple", payload: { transactions: ["x".repeat(30)] } });
    expect(res.statusCode).toBe(401);
    expect((await send("google:6", tx({ bundleId: "com.other.app" }))).statusCode).toBe(400);
  });

  it("follows Apple's renewal notices for a subscription the app has sent", async () => {
    const { app, users, send } = setup();
    await send("google:7", tx({ originalTransactionId: "renews", expiresDate: Date.now() + DAY }));
    const renewed = tx({ originalTransactionId: "renews", productId: "com.arpit.glyf.max.yearly", expiresDate: Date.now() + 365 * DAY });
    const note = { notificationType: "DID_CHANGE_RENEWAL_PREF", data: { signedTransactionInfo: b64url(JSON.stringify(renewed)) } };
    const res = await app.inject({ method: "POST", url: "/billing/apple/notifications", payload: { signedPayload: b64url(JSON.stringify(note)) } });
    expect(res.statusCode).toBe(200);
    expect(await users.plan("google:7")).toBe("max");
    // A refund ends it.
    const refunded = { ...renewed, revocationDate: Date.now() };
    await app.inject({ method: "POST", url: "/billing/apple/notifications",
      payload: { signedPayload: b64url(JSON.stringify({ notificationType: "REFUND", data: { signedTransactionInfo: b64url(JSON.stringify(refunded)) } })) } });
    expect(await users.plan("google:7")).toBe("free");
  });
});

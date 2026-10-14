import Fastify from "fastify";
import { describe, expect, it } from "vitest";
import {
  CryptoPayments, USDC_MAINNET, base58Decode, base58Encode, findPayment, httpRpc, isSolanaAddress,
  newReference, received, solanaPayUrl, usdcUnits, type Rpc,
} from "../src/lib/cryptopay.js";
import { cryptoPayRoutes } from "../src/routes/cryptopay.js";
import { Users, type SqlQuery } from "../src/lib/users.js";

const DAY = 24 * 3600 * 1000;
const TREASURY = base58Encode(Uint8Array.from({ length: 32 }, (_, i) => i + 7));
const PAYER = base58Encode(Uint8Array.from({ length: 32 }, (_, i) => 200 - i));

/** Just enough Postgres for payment requests, purchases and plans. */
function memoryDb() {
  const payments = new Map<string, Record<string, unknown>>();
  const purchases = new Map<string, Record<string, unknown>>();
  const people = new Map<string, Record<string, unknown>>();
  let failPurchases = false;
  const sql: SqlQuery = async (text, params = []) => {
    const t = text.replace(/\s+/g, " ").trim();
    const p = params as unknown[];
    if (/^(create|alter|do)\b/i.test(t)) return [];
    if (t.startsWith("insert into glyf_crypto_payments")) {
      payments.set(p[0] as string, {
        reference: p[0], user_id: p[1], plan: p[2], period: p[3], amount: p[4], mint: p[5], treasury: p[6],
        signature: null, expires_at: null,
      });
      return [];
    }
    if (t.startsWith("select reference, user_id, plan, period, amount")) {
      const row = payments.get(p[0] as string);
      return row ? [row] : [];
    }
    if (t.startsWith("update glyf_crypto_payments set signature = $2")) {
      const row = payments.get(p[0] as string);
      if (!row || row.signature !== null) return [];
      if ([...payments.values()].some(r => r.signature === p[1])) {
        throw new Error('duplicate key value violates unique constraint "glyf_crypto_payments_signature_key"');
      }
      row.signature = p[1];
      row.expires_at = p[2];
      return [{ reference: p[0] }];
    }
    if (t.startsWith("insert into glyf_purchases")) {
      if (failPurchases) throw new Error("database went away");
      const had = purchases.get(p[0] as string);
      if (had && had.user_id !== p[1]) return [];
      purchases.set(p[0] as string, { user_id: p[1], product_id: p[2], plan: p[3], expires_at: p[4], environment: p[5] });
      return [{ user_id: p[1] }];
    }
    if (t.startsWith("select user_id from glyf_purchases")) {
      const row = purchases.get(p[0] as string);
      return row ? [{ user_id: row.user_id }] : [];
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
  return {
    sql, payments, purchases,
    breakPurchases: (on = true) => { failPurchases = on; },
  };
}

/** A pretend Solana: transactions by the references they carry. */
function fakeSolana() {
  const byRef = new Map<string, string[]>();
  const txs = new Map<string, unknown>();
  const calls: string[] = [];
  let n = 0;
  const rpc: Rpc = async (method, params) => {
    calls.push(method);
    if (method === "getSignaturesForAddress") {
      // Newest first, the way a node answers.
      return [...(byRef.get(params[0] as string) ?? [])].reverse().map(signature => ({ signature, err: null }));
    }
    if (method === "getTransaction") return txs.get(params[0] as string) ?? null;
    throw new Error(`unexpected rpc ${method}`);
  };
  /** A USDC transfer of [units] to [to], carrying [refs]. */
  function pay(refs: string[], units: bigint, opts: { to?: string; mint?: string; failed?: boolean } = {}) {
    const signature = `sig${++n}${"x".repeat(60)}`;
    const to = opts.to ?? TREASURY;
    const mint = opts.mint ?? USDC_MAINNET;
    txs.set(signature, {
      meta: {
        err: opts.failed ? { InstructionError: [1, "Custom"] } : null,
        preTokenBalances: [
          { owner: PAYER, mint, uiTokenAmount: { amount: "100000000" } },
          { owner: to, mint, uiTokenAmount: { amount: "1000000" } },
        ],
        postTokenBalances: [
          { owner: PAYER, mint, uiTokenAmount: { amount: String(100_000_000n - units) } },
          { owner: to, mint, uiTokenAmount: { amount: String(1_000_000n + units) } },
        ],
      },
    });
    for (const r of refs) byRef.set(r, [...(byRef.get(r) ?? []), signature]);
    return signature;
  }
  return { rpc, pay, calls };
}

function setup(opts: { treasury?: string; rpc?: Rpc | null } = {}) {
  const db = memoryDb();
  const chain = fakeSolana();
  const users = new Users(db.sql);
  const app = Fastify();
  cryptoPayRoutes(app, {
    users,
    payments: new CryptoPayments(db.sql),
    verifySessionToken: async t => (t.startsWith("user:") ? t.slice(5) : null),
    treasury: opts.treasury ?? TREASURY,
    mint: USDC_MAINNET,
    rpc: opts.rpc === undefined ? chain.rpc : opts.rpc,
  });
  const auth = (who: string) => ({ authorization: `Bearer user:${who}` });
  const request = (who: string, plan: string, period: string) => app.inject({
    method: "POST", url: "/billing/crypto/request", headers: auth(who), payload: { plan, period } });
  const verify = (who: string, reference: string) => app.inject({
    method: "POST", url: "/billing/crypto/verify", headers: auth(who), payload: { reference } });
  return { app, db, chain, users, auth, request, verify };
}

describe("crypto payment helpers", () => {
  it("base58 round-trips, leading zeros and all", () => {
    for (const bytes of [new Uint8Array(32), Uint8Array.from({ length: 32 }, (_, i) => i), Uint8Array.from([0, 0, 255, 1])]) {
      expect([...base58Decode(base58Encode(bytes))!]).toEqual([...bytes]);
    }
    expect(base58Encode(new Uint8Array(32))).toBe("11111111111111111111111111111111");
    expect(isSolanaAddress(USDC_MAINNET)).toBe(true);
    expect(isSolanaAddress("not an address")).toBe(false);
    expect(isSolanaAddress("0OIl")).toBe(false);
  });

  it("makes a new 32-byte reference each time", () => {
    const a = newReference(), b = newReference();
    expect(isSolanaAddress(a)).toBe(true);
    expect(a).not.toBe(b);
  });

  it("prices in USDC base units", () => {
    expect(usdcUnits(2)).toBe(2_000_000n);
    expect(usdcUnits(50)).toBe(50_000_000n);
  });

  it("writes a Solana Pay transfer request", () => {
    const url = solanaPayUrl({ recipient: TREASURY, amount: 5, mint: USDC_MAINNET, reference: "REF", label: "Glyf", message: "Glyf Max, 1 month" });
    expect(url.startsWith(`solana:${TREASURY}?`)).toBe(true);
    const q = new URL(url.replace("solana:", "https://x/")).searchParams;
    expect(q.get("amount")).toBe("5");
    expect(q.get("spl-token")).toBe(USDC_MAINNET);
    expect(q.get("reference")).toBe("REF");
    expect(q.get("message")).toBe("Glyf Max, 1 month");
    expect(url).not.toContain("+");
  });

  it("counts only what the treasury gained in that token", () => {
    const meta = {
      preTokenBalances: [{ owner: TREASURY, mint: USDC_MAINNET, uiTokenAmount: { amount: "10" } },
        { owner: TREASURY, mint: "other", uiTokenAmount: { amount: "0" } }],
      postTokenBalances: [{ owner: TREASURY, mint: USDC_MAINNET, uiTokenAmount: { amount: "2000010" } },
        { owner: TREASURY, mint: "other", uiTokenAmount: { amount: "999999999" } }],
    };
    expect(received(meta, TREASURY, USDC_MAINNET)).toBe(2_000_000n);
    // A first payment to a new token account has no balance before.
    expect(received({ postTokenBalances: meta.postTokenBalances }, TREASURY, USDC_MAINNET)).toBe(2_000_010n);
  });

  it("finds the payment, skipping failed and short ones", async () => {
    const chain = fakeSolana();
    const ref = newReference();
    const p = { reference: ref, treasury: TREASURY, mint: USDC_MAINNET, amount: 2_000_000n };
    expect(await findPayment(chain.rpc, p)).toEqual({ status: "pending" });
    chain.pay([ref], 2_000_000n, { failed: true });
    expect((await findPayment(chain.rpc, p)).status).toBe("pending");
    chain.pay([ref], 1_000_000n);
    expect((await findPayment(chain.rpc, p)).status).toBe("short");
    const good = chain.pay([ref], 2_000_000n);
    expect(await findPayment(chain.rpc, p)).toMatchObject({ status: "paid", signature: good });
  });

  it("ignores USDC sent somewhere else and other tokens", async () => {
    const chain = fakeSolana();
    const ref = newReference();
    chain.pay([ref], 5_000_000n, { to: PAYER });
    chain.pay([ref], 5_000_000n, { mint: "So11111111111111111111111111111111111111112" });
    expect((await findPayment(chain.rpc, { reference: ref, treasury: TREASURY, mint: USDC_MAINNET, amount: 2_000_000n })).status)
      .toBe("pending");
  });

  it("talks JSON-RPC to the node", async () => {
    const sent: unknown[] = [];
    const rpc = httpRpc("https://rpc.example/?api-key=k", (async (_url: string, init: RequestInit) => {
      sent.push(JSON.parse(String(init.body)));
      return new Response(JSON.stringify({ jsonrpc: "2.0", id: 1, result: [{ signature: "s", err: null }] }));
    }) as unknown as typeof fetch);
    expect(await rpc("getSignaturesForAddress", ["R"])).toEqual([{ signature: "s", err: null }]);
    expect(sent[0]).toMatchObject({ method: "getSignaturesForAddress", params: ["R"] });
    const failing = httpRpc("https://rpc.example/", (async () =>
      new Response(JSON.stringify({ error: { message: "rate limited" } }))) as unknown as typeof fetch);
    await expect(failing("getTransaction", [])).rejects.toThrow("rate limited");
  });
});

describe("/billing/crypto", () => {
  it("is off without a treasury or a node, on with both", async () => {
    for (const [treasury, rpc] of [["", undefined], ["nope", undefined], [TREASURY, null]] as const) {
      const { app, auth, request } = setup({ treasury, rpc });
      const config = await app.inject({ method: "GET", url: "/billing/crypto", headers: auth("google:1") });
      expect(config.json()).toEqual({ ok: true, enabled: false });
      expect((await request("google:1", "plus", "month")).statusCode).toBe(503);
    }
    const { app, auth } = setup();
    const on = (await app.inject({ method: "GET", url: "/billing/crypto", headers: auth("google:1") })).json();
    expect(on).toMatchObject({ ok: true, enabled: true, token: "USDC", mint: USDC_MAINNET,
      prices: { plus: { month: 2, year: 20 }, max: { month: 5, year: 50 } } });
  });

  it("needs a session", async () => {
    const { app } = setup();
    expect((await app.inject({ method: "GET", url: "/billing/crypto" })).statusCode).toBe(401);
    expect((await app.inject({ method: "POST", url: "/billing/crypto/request", payload: { plan: "plus", period: "month" } })).statusCode).toBe(401);
    expect((await app.inject({ method: "POST", url: "/billing/crypto/verify", payload: { reference: newReference() } })).statusCode).toBe(401);
  });

  it("hands out a Solana Pay request at the plan's price", async () => {
    const { request, db } = setup();
    const res = await request("google:1", "max", "year");
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body).toMatchObject({ ok: true, recipient: TREASURY, mint: USDC_MAINNET, amount: "50", label: "Glyf" });
    expect(isSolanaAddress(body.reference)).toBe(true);
    expect(body.url).toContain(`reference=${body.reference}`);
    expect(body.url).toContain("amount=50");
    expect(db.payments.get(body.reference)).toMatchObject({ user_id: "google:1", plan: "max", period: "year", amount: "50000000" });
    expect((await request("google:1", "gold", "month")).statusCode).toBe(400);
    expect((await request("google:1", "plus", "week")).statusCode).toBe(400);
  });

  it("waits until the transfer lands, then puts the plan on the account", async () => {
    const { request, verify, chain, users, db } = setup();
    const { reference } = (await request("google:2", "plus", "month")).json();
    const waiting = await verify("google:2", reference);
    expect(waiting.statusCode).toBe(202);
    expect(waiting.json()).toEqual({ ok: false, pending: true });
    expect(await users.plan("google:2")).toBe("free");

    const sig = chain.pay([reference], 2_000_000n);
    const paid = await verify("google:2", reference);
    expect(paid.statusCode).toBe(200);
    const body = paid.json();
    expect(body).toMatchObject({ ok: true, plan: "plus", paidPlan: "plus", period: "month", signature: sig });
    const days = (Date.parse(body.expiresAt) - Date.now()) / DAY;
    expect(days).toBeGreaterThan(29.9);
    expect(days).toBeLessThan(30.1);
    expect(await users.plan("google:2")).toBe("plus");
    expect(db.purchases.get(`sol:${sig}`)).toMatchObject({ product_id: "sol.plus.month", environment: "solana" });
  });

  it("is idempotent: asking again never adds days", async () => {
    const { request, verify, chain } = setup();
    const { reference } = (await request("google:3", "max", "month")).json();
    chain.pay([reference], 5_000_000n);
    const first = (await verify("google:3", reference)).json();
    const again = (await verify("google:3", reference)).json();
    expect(again.expiresAt).toBe(first.expiresAt);
    // And Solana isn't asked once the request is paid.
    const asked = chain.calls.length;
    const both = await Promise.all([verify("google:3", reference), verify("google:3", reference)]);
    for (const r of both) expect(r.json().expiresAt).toBe(first.expiresAt);
    expect(chain.calls.length).toBe(asked);
  });

  it("stacks a second payment after the first", async () => {
    const { request, verify, chain } = setup();
    const a = (await request("google:4", "plus", "month")).json().reference;
    const b = (await request("google:4", "plus", "year")).json().reference;
    chain.pay([a], 2_000_000n);
    chain.pay([b], 20_000_000n);
    await verify("google:4", a);
    const body = (await verify("google:4", b)).json();
    const days = (Date.parse(body.expiresAt) - Date.now()) / DAY;
    expect(days).toBeGreaterThan(394.9);
    expect(days).toBeLessThan(395.1);
  });

  it("refuses a short payment", async () => {
    const { request, verify, chain, users } = setup();
    const { reference } = (await request("google:5", "max", "month")).json();
    chain.pay([reference], 2_000_000n);
    const res = await verify("google:5", reference);
    expect(res.statusCode).toBe(402);
    expect(await users.plan("google:5")).toBe("free");
  });

  it("counts one transaction once, even when it carries two references", async () => {
    const { request, verify, chain } = setup();
    const a = (await request("google:6", "plus", "month")).json().reference;
    const b = (await request("google:6", "plus", "month")).json().reference;
    chain.pay([a, b], 2_000_000n);
    expect((await verify("google:6", a)).statusCode).toBe(200);
    const twice = await verify("google:6", b);
    expect(twice.statusCode).toBe(409);
    expect(twice.json().error).toBe("That payment was already used");
  });

  it("keeps each request to the account that made it", async () => {
    const { request, verify, chain, users } = setup();
    const { reference } = (await request("google:7", "max", "year")).json();
    chain.pay([reference], 50_000_000n);
    expect((await verify("apple:8", reference)).statusCode).toBe(404);
    expect(await users.plan("apple:8")).toBe("free");
    expect((await verify("google:7", newReference())).statusCode).toBe(404);
    expect((await verify("google:7", "short")).statusCode).toBe(400);
  });

  it("finishes the plan on the next try when saving it failed", async () => {
    const { request, verify, chain, db, users } = setup();
    const { reference } = (await request("google:9", "plus", "month")).json();
    chain.pay([reference], 2_000_000n);
    db.breakPurchases();
    expect((await verify("google:9", reference)).statusCode).toBe(503);
    const ends = db.payments.get(reference)?.expires_at;
    expect(ends).toBeTruthy();
    db.breakPurchases(false);
    const body = (await verify("google:9", reference)).json();
    expect(body).toMatchObject({ ok: true, plan: "plus" });
    expect(body.expiresAt).toBe(new Date(ends as string).toISOString());
    expect(await users.plan("google:9")).toBe("plus");
  });
});

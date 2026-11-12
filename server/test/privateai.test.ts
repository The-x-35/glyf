import Fastify from "fastify";
import { privateKeyToAccount } from "viem/accounts";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { env } from "../src/env.js";
import {
  aiContext, NEARAI_API, privateAIHooks, privateAIRoutes, ReceiptVerifier, receiptsFor, sha256, withNearAI,
  type NearAIReceipt,
} from "../src/lib/privateai.js";
import { MemoryKV } from "../src/lib/store.js";
import { completeStreaming, resetCooldowns } from "../src/providers/openrouter.js";

/** A phone that asks for private AI is answered by NEAR AI Cloud and by
 *  nothing else; every other phone keeps the usual chain. Each NEAR answer
 *  leaves a receipt that is checked against NEAR's signature and the
 *  model's attestation. */

const TEE = privateKeyToAccount("0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d");
const STRANGER = privateKeyToAccount("0x8b3a350cf5c34c9194ca85829a2df0ec3153be0318b5e2d3348e872092edffba");

function sse(id: string, text: string): string {
  return `data: ${JSON.stringify({ id, choices: [{ delta: { content: text } }] })}\n\n`
    + `data: ${JSON.stringify({ id, choices: [{ delta: {}, finish_reason: "stop" }] })}\n\ndata: [DONE]\n\n`;
}

describe("private AI on NEAR AI Cloud", () => {
  const saved = { mockAI: env.mockAI, key: env.nearAIKey, or: env.openrouterKey, gemini: env.geminiKey,
    fast: env.fastModels, nearModels: env.nearAIModels };
  let calls: { url: string; auth: string; body: string; model: string; kwargs?: unknown }[] = [];

  beforeEach(() => {
    env.mockAI = false;
    env.openrouterKey = "or-key";
    env.geminiKey = "";
    env.nearAIKey = "near-key";
    env.fastModels = ["test/usual"];
    env.nearAIModels = ["nearai:test/private", "nearai:test/private-2"];
    calls = [];
    resetCooldowns();
    vi.stubGlobal("fetch", vi.fn(async (url: string, init: { body: string; headers: Record<string, string> }) => {
      const body = JSON.parse(init.body) as { model: string; chat_template_kwargs?: unknown };
      calls.push({ url, auth: init.headers.Authorization, body: init.body, model: body.model,
        ...(body.chat_template_kwargs ? { kwargs: body.chat_template_kwargs } : {}) });
      if (body.model === "test/private") return new Response("busy", { status: 503 });
      return new Response(sse("chatcmpl-near-1", "Paris"), { status: 200, headers: { "content-type": "text/event-stream" } });
    }));
  });

  afterEach(() => {
    Object.assign(env, { mockAI: saved.mockAI, nearAIKey: saved.key, openrouterKey: saved.or, geminiKey: saved.gemini,
      fastModels: saved.fast, nearAIModels: saved.nearModels });
    vi.unstubAllGlobals();
    resetCooldowns();
  });

  it("sends an asking phone to NEAR AI only, down its own chain, with thinking off, and keeps a receipt", async () => {
    const kv = new MemoryKV();
    const { text, ids } = await withNearAI(async () => {
      const r = await completeStreaming("fast", [{ role: "user", content: "capital of France" }], { onToken: () => {} });
      return { text: r.text, ids: [...(aiContext()?.requests ?? [])] };
    }, { kv, user: "google:someone" });
    expect(text).toBe("Paris");
    expect(calls.map(c => c.model)).toEqual(["test/private", "test/private-2"]);
    expect(calls.every(c => c.url === `${NEARAI_API}/chat/completions` && c.auth === "Bearer near-key")).toBe(true);
    expect(calls[1].kwargs).toEqual({ enable_thinking: false });
    expect(ids).toEqual(["chatcmpl-near-1"]);
    expect(receiptsFor(kv, "google:someone")).toEqual([{ chatId: "chatcmpl-near-1", model: "test/private-2",
      requestHash: sha256(calls[1].body), responseHash: sha256(sse("chatcmpl-near-1", "Paris")), at: expect.any(Number),
      status: "pending" }]);
  });

  it("leaves every other phone on the usual chain", async () => {
    await completeStreaming("fast", [{ role: "user", content: "hi" }], { onToken: () => {} });
    expect(calls.map(c => [c.url, c.model])).toEqual([["https://openrouter.ai/api/v1/chat/completions", "test/usual"]]);
  });

  it("ignores the ask while the server has no NEAR AI key", async () => {
    env.nearAIKey = "";
    await withNearAI(() => completeStreaming("fast", [{ role: "user", content: "hi" }], { onToken: () => {} }));
    expect(calls.map(c => c.model)).toEqual(["test/usual"]);
  });

  it("reads the ask from the X-Glyf-AI header", async () => {
    const app = Fastify();
    privateAIHooks(app, new MemoryKV());
    app.get("/who", async () => ({ near: aiContext()?.near ?? null }));
    expect((await app.inject({ url: "/who", headers: { "x-glyf-ai": "near" } })).json()).toEqual({ near: true });
    expect((await app.inject({ url: "/who", headers: { "x-glyf-ai": "0g" } })).json()).toEqual({ near: false });
    expect((await app.inject({ url: "/who" })).json()).toEqual({ near: false });
  });
});

describe("NEAR AI receipts", () => {
  const MODEL = "Qwen/Qwen3.6-35B-A3B-FP8";
  const receipt = (over: Partial<NearAIReceipt> = {}): NearAIReceipt => ({ chatId: "chatcmpl-1", model: MODEL,
    requestHash: "a".repeat(64), responseHash: "b".repeat(64), at: 1, status: "pending", ...over });

  /** NEAR AI's signature and attestation endpoints, signing with `signer`. */
  async function fakeNearAI(opts: { signer?: typeof TEE; text?: string; kind?: string; attested?: string[]; missing?: boolean } = {}) {
    const signer = opts.signer ?? TEE;
    const text = opts.text ?? `${MODEL}:${"a".repeat(64)}:${"b".repeat(64)}`;
    const signature = await signer.signMessage({ message: text });
    const asked: string[] = [];
    const fetchImpl = (async (url: string, init: { headers: Record<string, string> }) => {
      asked.push(String(url));
      const u = new URL(String(url));
      if (u.pathname.startsWith("/v1/signature/")) {
        expect(init.headers.authorization).toBe("Bearer near-key");
        if (opts.missing) return new Response(JSON.stringify({ detail: "not found" }), { status: 404 });
        return new Response(JSON.stringify({ text, signature, signing_address: TEE.address, signing_algo: "ecdsa",
          signature_kind: opts.kind ?? "provider_tee" }));
      }
      if (u.pathname === "/v1/attestation/report") {
        expect(u.searchParams.get("model")).toBe(MODEL);
        expect(u.searchParams.get("signing_algo")).toBe("ecdsa");
        expect(u.searchParams.get("nonce")).toMatch(/^[0-9a-f]{64}$/);
        return new Response(JSON.stringify({ gateway_attestation: { signing_address: STRANGER.address },
          model_attestations: (opts.attested ?? [TEE.address]).map(a => ({ signing_address: a, signing_algo: "ecdsa" })) }));
      }
      throw new Error(`unexpected ${url}`);
    }) as unknown as typeof fetch;
    return { asked, verifier: new ReceiptVerifier({ fetchImpl, key: () => "near-key" }), fetchImpl };
  }

  it("verifies an answer whose TEE signed this very request and response with an attested key", async () => {
    const { verifier, asked } = await fakeNearAI();
    const r = await verifier.verify(receipt());
    expect(r.status).toBe("verified");
    expect(r.signature).toMatchObject({ kind: "provider_tee", algo: "ecdsa", signingAddress: TEE.address,
      signerOk: true, hashesMatch: true, attested: true });
    expect(asked[0]).toBe(`${NEARAI_API}/signature/chatcmpl-1?model=${encodeURIComponent(MODEL)}&signing_algo=ecdsa`);
    // The report is kept: a second receipt asks for the signature only.
    await verifier.verify(receipt({ chatId: "chatcmpl-2" }));
    expect(asked.filter(u => u.includes("/attestation/"))).toHaveLength(1);
  });

  it("fails a signature over other bytes, from a key that isn't attested, or not by its claimed signer", async () => {
    const other = await fakeNearAI({ text: `${MODEL}:${"c".repeat(64)}:${"b".repeat(64)}` });
    expect(await other.verifier.verify(receipt())).toMatchObject({ status: "failed",
      reason: "The signature is for a different request or answer", signature: { hashesMatch: false, signerOk: true } });
    const unattested = await fakeNearAI({ attested: [STRANGER.address] });
    expect(await unattested.verifier.verify(receipt())).toMatchObject({ status: "failed",
      reason: "The signer isn't in the model's attestation" });
    const forged = await fakeNearAI({ signer: STRANGER });
    expect(await forged.verifier.verify(receipt())).toMatchObject({ status: "failed", reason: "The signature isn't the signer's" });
  });

  it("checks a gateway signature against the gateway's attestation", async () => {
    const { verifier } = await fakeNearAI({ kind: "gateway", text: `${"a".repeat(64)}:${"b".repeat(64)}` });
    // The gateway attests STRANGER, but TEE signed: not the gateway's key.
    expect((await verifier.verify(receipt())).signature?.attested).toBe(false);
  });

  it("keeps asking for a signature that isn't there yet, then gives up", async () => {
    const { verifier } = await fakeNearAI({ missing: true });
    let r = receipt();
    for (let i = 0; i < 2; i++) {
      r = await verifier.verify(r);
      expect(r.status).toBe("pending");
    }
    expect(await verifier.verify(r)).toMatchObject({ status: "unavailable", reason: "No signature for this answer", tries: 3 });
  });

  it("lists an account's receipts, checks the pending ones and saves what it found", async () => {
    const { fetchImpl } = await fakeNearAI();
    const kv = new MemoryKV();
    kv.put("nearaireceipts", "google:someone", [receipt()]);
    const app = Fastify();
    app.addHook("onRequest", async req => { req.glyfUser = req.headers["x-user"] as string | undefined; });
    privateAIRoutes(app, kv, { fetchImpl, key: () => "near-key" });
    const res = await app.inject({ url: "/ai/receipts", headers: { "x-user": "google:someone" } });
    expect(res.json()).toMatchObject({ ok: true, provider: "NEAR AI Cloud", verifyUrl: "https://cloud.near.ai/verify",
      receipts: [{ id: "chatcmpl-1", verified: true, chatId: "chatcmpl-1", model: MODEL, status: "verified" }] });
    expect(receiptsFor(kv, "google:someone")[0].status).toBe("verified");
    expect((await app.inject({ url: "/ai/receipts" })).statusCode).toBe(401);
    // No key on the server: listed as they are, nothing asked.
    const bare = Fastify();
    bare.addHook("onRequest", async req => { req.glyfUser = "google:other"; });
    const kv2 = new MemoryKV();
    kv2.put("nearaireceipts", "google:other", [receipt()]);
    privateAIRoutes(bare, kv2, { fetchImpl: (() => { throw new Error("no calls"); }) as unknown as typeof fetch, key: () => "" });
    expect((await bare.inject({ url: "/ai/receipts" })).json().receipts[0]).toMatchObject({ verified: null, status: "pending" });
  });
});

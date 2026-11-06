import Fastify from "fastify";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { env } from "../src/env.js";
import { aiContext, privateAIHooks, receiptsFor, withZeroG } from "../src/lib/privateai.js";
import { MemoryKV } from "../src/lib/store.js";
import { completeStreaming, resetCooldowns } from "../src/providers/openrouter.js";

/** A phone that asks for private AI is answered by 0G's Private Computer and
 *  by nothing else; every other phone keeps the usual chain. */

function sse(id: string, text: string): Response {
  const body = `data: ${JSON.stringify({ id, choices: [{ delta: { content: text } }] })}\n\n`
    + `data: ${JSON.stringify({ id, choices: [{ delta: {} }], x_0g_trace: { request_id: "zg-req-9", provider: "0xabc",
      tee_verified: true, billing: { total_cost_usd_micro: "33" } } })}\n\ndata: [DONE]\n\n`;
  return new Response(body, { status: 200, headers: { "content-type": "text/event-stream" } });
}

describe("private AI on 0G", () => {
  const saved = { mockAI: env.mockAI, zg: env.zeroGKey, or: env.openrouterKey, gemini: env.geminiKey,
    fast: env.fastModels, zgModels: env.zeroGModels };
  let calls: { url: string; auth: string; model: string; trust?: string; tee?: boolean }[] = [];

  beforeEach(() => {
    env.mockAI = false;
    env.openrouterKey = "or-key";
    env.geminiKey = "";
    env.zeroGKey = "zg-key";
    env.fastModels = ["test/usual"];
    env.zeroGModels = ["zerog:test/private", "zerog:test/private-2"];
    calls = [];
    resetCooldowns();
    vi.stubGlobal("fetch", vi.fn(async (url: string, init: { body: string; headers: Record<string, string> }) => {
      const body = JSON.parse(init.body) as { model: string; verify_tee?: boolean };
      calls.push({ url, auth: init.headers.Authorization, model: body.model,
        ...(init.headers["X-0G-Provider-Trust-Mode"] ? { trust: init.headers["X-0G-Provider-Trust-Mode"], tee: body.verify_tee } : {}) });
      return body.model === "test/private" ? new Response("busy", { status: 503 }) : sse("req-123", "Paris");
    }));
  });

  afterEach(() => {
    Object.assign(env, { mockAI: saved.mockAI, zeroGKey: saved.zg, openrouterKey: saved.or, geminiKey: saved.gemini,
      fastModels: saved.fast, zeroGModels: saved.zgModels });
    vi.unstubAllGlobals();
    resetCooldowns();
  });

  it("sends an asking phone to 0G only, down 0G's own chain, and keeps its request id", async () => {
    const kv = new MemoryKV();
    const { text, ids } = await withZeroG(async () => {
      const r = await completeStreaming("fast", [{ role: "user", content: "capital of France" }], { onToken: () => {} });
      return { text: r.text, ids: [...(aiContext()?.requests ?? [])] };
    }, { kv, user: "google:someone" });
    expect(text).toBe("Paris");
    expect(calls.map(c => c.model)).toEqual(["test/private", "test/private-2"]);
    expect(calls.every(c => c.url === "https://router-api.0g.ai/v1/chat/completions" && c.auth === "Bearer zg-key"
      && c.trust === "private" && c.tee === true)).toBe(true);
    expect(ids).toEqual(["zg-req-9"]);
    expect(receiptsFor(kv, "google:someone")).toEqual([{ requestId: "zg-req-9", model: "test/private-2",
      provider: "0xabc", teeVerified: true, costUsdMicro: 33, at: expect.any(Number) }]);
  });

  it("leaves every other phone on the usual chain", async () => {
    await completeStreaming("fast", [{ role: "user", content: "hi" }], { onToken: () => {} });
    expect(calls).toEqual([{ url: "https://openrouter.ai/api/v1/chat/completions", auth: "Bearer or-key", model: "test/usual" }]);
  });

  it("ignores the ask while the server has no 0G key", async () => {
    env.zeroGKey = "";
    await withZeroG(() => completeStreaming("fast", [{ role: "user", content: "hi" }], { onToken: () => {} }));
    expect(calls.map(c => c.model)).toEqual(["test/usual"]);
  });

  it("reads the ask from the X-Glyf-AI header", async () => {
    const app = Fastify();
    privateAIHooks(app, new MemoryKV());
    app.get("/who", async () => ({ zeroG: aiContext()?.zeroG ?? null }));
    expect((await app.inject({ url: "/who", headers: { "x-glyf-ai": "0g" } })).json()).toEqual({ zeroG: true });
    expect((await app.inject({ url: "/who" })).json()).toEqual({ zeroG: false });
  });
});

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import Fastify from "fastify";
import { env } from "../src/env.js";
import { aiHealth, AI_HEALTH_TTL_MS, resetAiHealthForTests } from "../src/lib/aihealth.js";
import { resetCooldowns } from "../src/providers/openrouter.js";
import { healthRoutes } from "../src/routes/health.js";

/** GET /health?deep=1 makes one real (here: faked) completion through the
 *  fast chain and says which model answered, or why each one didn't. */

const chunk = (t: string) => `data: ${JSON.stringify({ choices: [{ delta: { content: t } }] })}\n\n`;

function answer(text: string): Response {
  const enc = new TextEncoder();
  return new Response(new ReadableStream<Uint8Array>({
    start(c) {
      c.enqueue(enc.encode(chunk(text)));
      c.enqueue(enc.encode("data: [DONE]\n\n"));
      c.close();
    },
  }), { status: 200 });
}

describe("the AI health check", () => {
  const saved = { mockAI: env.mockAI, fast: env.fastModels, key: env.openrouterKey, gemini: env.geminiKey };
  let sent: { model: string; max_tokens?: number }[];

  beforeEach(() => {
    env.mockAI = false;
    env.openrouterKey = "test-key";
    env.geminiKey = "";
    sent = [];
    resetAiHealthForTests();
    resetCooldowns();
  });

  afterEach(() => {
    env.mockAI = saved.mockAI;
    env.fastModels = saved.fast;
    env.openrouterKey = saved.key;
    env.geminiKey = saved.gemini;
    vi.unstubAllGlobals();
    resetAiHealthForTests();
    resetCooldowns();
  });

  /** Each model answers with its scripted status (200 = "OK"). */
  function models(script: Record<string, number>) {
    const fetch = vi.fn(async (_url: string, init: { body: string }) => {
      const body = JSON.parse(init.body) as { model: string; max_tokens?: number };
      sent.push(body);
      const status = script[body.model] ?? 500;
      return status === 200 ? answer("OK") : new Response("nope", { status });
    });
    vi.stubGlobal("fetch", fetch);
    return fetch;
  }

  function app() {
    const f = Fastify();
    healthRoutes(f);
    return f;
  }

  it("names the model that answered, the latency and the ones that failed first", async () => {
    env.fastModels = ["test/refused", "test/works", "test/never-reached"];
    models({ "test/refused": 401, "test/works": 200 });
    const res = await app().inject({ method: "GET", url: "/health?deep=1" });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.ok).toBe(true);
    expect(body.ai).toMatchObject({
      ok: true, mock: false, tier: "fast", model: "test/works", cached: false,
      failures: [{ model: "test/refused", status: 401 }],
      chain: ["test/refused", "test/works", "test/never-reached"],
    });
    expect(typeof body.ai.latencyMs).toBe("number");
    // The plain report is still there beside it.
    expect(body).toHaveProperty("hasOpenRouterKey", true);
    // The probe is tiny: a few tokens, never the tier's 1500.
    expect(sent.map(s => s.max_tokens)).toEqual([5, 5]);
    expect(JSON.stringify(body)).not.toContain("test-key");
  });

  it("answers 503 with each model's failure when none replies", async () => {
    env.fastModels = ["test/a", "test/b"];
    models({ "test/a": 401, "test/b": 402 });
    const res = await app().inject({ method: "GET", url: "/health?deep=1" });
    expect(res.statusCode).toBe(503);
    expect(res.json().ok).toBe(false);
    expect(res.json().ai).toMatchObject({
      ok: false,
      failures: [{ model: "test/a", status: 401 }, { model: "test/b", status: 402 }],
    });
  });

  it("calls a model at most once a minute however often it is asked", async () => {
    env.fastModels = ["test/works"];
    const fetch = models({ "test/works": 200 });
    const f = app();
    const [a, b] = await Promise.all([
      f.inject({ method: "GET", url: "/health?deep=1" }),
      f.inject({ method: "GET", url: "/health?deep=1" }),
    ]);
    const c = await f.inject({ method: "GET", url: "/health?deep=1" });
    expect([a, b, c].map(r => r.statusCode)).toEqual([200, 200, 200]);
    expect(c.json().ai.cached).toBe(true);
    expect(fetch).toHaveBeenCalledTimes(1);

    // A minute later it looks again.
    let t = Date.now() + AI_HEALTH_TTL_MS + 1;
    await aiHealth(() => t++);
    expect(fetch).toHaveBeenCalledTimes(2);
  });

  it("reports a refused model's cool-down on the next fresh check", async () => {
    env.fastModels = ["test/refused", "test/works"];
    models({ "test/refused": 401, "test/works": 200 });
    await aiHealth();
    resetAiHealthForTests();
    const again = await aiHealth();
    expect(again.coolingDown).toEqual(["test/refused"]);
    expect(again.model).toBe("test/works");
  });

  it("leaves plain /health alone: no model call, same shape", async () => {
    env.fastModels = ["test/works"];
    const fetch = models({ "test/works": 200 });
    const res = await app().inject({ method: "GET", url: "/health" });
    expect(res.statusCode).toBe(200);
    expect(res.json()).not.toHaveProperty("ai");
    expect(res.json()).toHaveProperty("ok", true);
    expect(fetch).not.toHaveBeenCalled();
  });

  it("says mock and calls nothing in mock mode", async () => {
    env.mockAI = true;
    const fetch = models({});
    const res = await app().inject({ method: "GET", url: "/health?deep=1" });
    expect(res.statusCode).toBe(200);
    expect(res.json().ai).toMatchObject({ ok: true, mock: true, model: "mock" });
    expect(fetch).not.toHaveBeenCalled();
  });
});

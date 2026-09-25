import { afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import { env } from "../src/env.js";
import { OptionStream, parseRewriteOptions, type RewriteOption } from "../src/lib/act.js";
import { completeStreaming, resetCooldowns } from "../src/providers/openrouter.js";
import { signedInApp } from "./helpers.js";

/** Hold space and chip taps answer as they are written: each version of a
 *  message shows the moment the model finishes it, not after all six. */

beforeAll(() => {
  env.mockAI = true;
  process.env.MOCK_AI = "true";
});

const styles = [
  { id: "basic", label: "Basic" },
  { id: "work", label: "Professional" },
  { id: "shorter", label: "Shorter" },
];

describe("picking versions out of a reply as it streams", () => {
  it("lets each version through the moment its closing quote arrives, in order", () => {
    const got: RewriteOption[] = [];
    const live = new OptionStream(styles, "ya ok will send the deck before 6 tmrw", o => got.push(o));
    const reply = '```json\n{"basic":"Yes, OK. I will send the deck before 6 tomorrow.",' +
      '"work":"Sure, I\'ll send the deck before 6 \\"sharp\\" tomorrow.","shorter":"Deck before 6 tomorrow."}\n```';
    // Tokens split wherever the model likes, even inside a key or an escape.
    for (let i = 0; i < reply.length; i += 7) {
      live.push(reply.slice(i, i + 7));
      if (i < 40) expect(got).toEqual([]);
    }
    expect(got.map(o => o.id)).toEqual(["basic", "work", "shorter"]);
    expect(got[1]).toEqual({ id: "work", label: "Professional", text: "Sure, I'll send the deck before 6 \"sharp\" tomorrow." });
  });

  it("keeps back what the whole reply would drop", () => {
    const got: RewriteOption[] = [];
    const live = new OptionStream(styles, "call at 5 today", o => got.push(o));
    live.push('{"basic":"Call at 5 today.","hinglish":"5 baje call karo","work":"Please call me today.",' +
      '"shorter":"","basic":"again"}');
    // An unasked style, a version that lost the 5, an empty one, a repeat.
    expect(got).toEqual([{ id: "basic", label: "Basic", text: "Call at 5 today." }]);
  });

  it("starts over when the model is dropped midway", () => {
    const got: RewriteOption[] = [];
    const live = new OptionStream(styles, "see you there", o => got.push(o));
    live.push('{"basic":"See you there."');
    live.reset();
    live.push('{"basic":"See you there!","work":"I will see you there."}');
    expect(got.map(o => o.text)).toEqual(["See you there.", "See you there!", "I will see you there."]);
  });

  it("reads the finished versions of a reply that was cut off", () => {
    expect(parseRewriteOptions('{"basic":"See you at 6.","work":"I will see you at 6.","shorter":"See y', styles)
      .map(o => o.id)).toEqual(["basic", "work"]);
  });
});

describe("POST /act as a stream", () => {
  const sse = (payload: string) => payload.split("\n\n").filter(Boolean).map(frame => {
    const [, event] = frame.match(/^event: (\w+)/) ?? [];
    const [, data] = frame.match(/\ndata: (.*)$/s) ?? [];
    return { event, data: data ? JSON.parse(data) : null };
  });

  it("sends each version as it is written, then the whole result", async () => {
    const app = signedInApp();
    const res = await app.inject({ method: "POST", url: "/act",
      payload: { text: "ya ok will send the deck before 6 tmrw", deviceId: "stream-test-0001",
        intent: "rewrite", stream: true } });
    expect(res.headers["content-type"]).toContain("text/event-stream");
    const frames = sse(res.payload);
    expect(frames.filter(f => f.event === "option").map(f => f.data.id)).toEqual(["basic", "work", "shorter"]);
    const done = frames.at(-1)!;
    expect(done.event).toBe("done");
    expect(done.data).toMatchObject({ ok: true, intent: "rewrite" });
    expect(done.data.options.map((o: RewriteOption) => o.id)).toEqual(["basic", "work", "shorter"]);
    expect(typeof done.data.remaining).toBe("number");
  });

  it("streams what the chip's Write it for me writes", async () => {
    const app = signedInApp();
    const res = await app.inject({ method: "POST", url: "/act",
      payload: { text: "write a toast for my sister's wedding", deviceId: "stream-test-0002",
        intent: "write", stream: true } });
    const frames = sse(res.payload);
    const written = frames.filter(f => f.event === "text").map(f => f.data.t).join("");
    const done = frames.at(-1)!;
    expect(done.event).toBe("done");
    expect(done.data.intent).toBe("write");
    expect(written.trim()).toBe(done.data.text);
  });

  it("still answers in one JSON reply when the keyboard doesn't ask for a stream", async () => {
    const app = signedInApp();
    const res = await app.inject({ method: "POST", url: "/act",
      payload: { text: "ya ok will send the deck before 6 tmrw", deviceId: "stream-test-0003", intent: "rewrite" } });
    expect(res.json()).toMatchObject({ ok: true, intent: "rewrite" });
  });
});

describe("a model dropped mid-answer", () => {
  const saved = { mockAI: env.mockAI, fast: env.fastModels, key: env.openrouterKey };
  afterEach(() => {
    env.mockAI = saved.mockAI;
    env.fastModels = saved.fast;
    env.openrouterKey = saved.key;
    vi.unstubAllGlobals();
    resetCooldowns();
  });

  it("tells the listener to discard what it said before the next model starts", async () => {
    env.mockAI = false;
    env.fastModels = ["test/stalls", "test/answers"];
    env.openrouterKey = "k";
    const chunk = (t: string) => `data: ${JSON.stringify({ choices: [{ delta: { content: t } }] })}\n\n`;
    vi.stubGlobal("fetch", vi.fn(async (_url: string, init: { body: string; signal: AbortSignal }) => {
      const model = JSON.parse(init.body).model as string;
      const enc = new TextEncoder();
      const body = new ReadableStream<Uint8Array>({
        start(controller) {
          if (model === "test/stalls") {
            // Says enough to reach the person, then goes quiet.
            controller.enqueue(enc.encode(chunk("This first model starts to answer and then ")));
            init.signal.addEventListener("abort", () => controller.error(new Error("aborted")));
          } else {
            controller.enqueue(enc.encode(chunk("The second model answers in full.")));
            controller.enqueue(enc.encode("data: [DONE]\n\n"));
            controller.close();
          }
        },
      });
      return new Response(body, { status: 200 });
    }));
    const heard: string[] = [];
    let restarts = 0;
    const res = await completeStreaming("fast", [{ role: "user", content: "hi" }], {
      onToken: t => heard.push(t),
      onRestart: () => { restarts += 1; heard.length = 0; },
      stallMs: 60,
    });
    expect(restarts).toBe(1);
    expect(res.text).toBe("The second model answers in full.");
    expect(heard.join("")).toBe("The second model answers in full.");
  });
});

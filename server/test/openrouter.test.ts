import { describe, expect, it } from "vitest";
import { env } from "../src/env.js";
import {
  VerdictGate, endpointFor, isClassifierVerdict, noteRateLimited, readyModels, requestOptions, resetCooldowns,
} from "../src/providers/openrouter.js";

/** Free routers can land on content-safety models that answer every prompt
 *  with a verdict. The gate must drop those without leaking a token, and must
 *  never delay or alter a real answer. */

const run = (tokens: string[]) => {
  const out: string[] = [];
  const gate = new VerdictGate(t => out.push(t));
  for (const t of tokens) gate.push(t);
  const verdict = gate.finish(tokens.join(""));
  return { verdict, streamed: out.join("") };
};

describe("isClassifierVerdict", () => {
  it("recognises moderation verdicts", () => {
    expect(isClassifierVerdict("User Safety: safe")).toBe(true);
    expect(isClassifierVerdict("  Agent Safety: unsafe\nCategories: S1")).toBe(true);
    expect(isClassifierVerdict("unsafe")).toBe(true);
  });

  it("leaves real answers alone, even ones about safety", () => {
    expect(isClassifierVerdict("Safe travels! See you at 9.")).toBe(false);
    expect(isClassifierVerdict("I have gone there yesterday.")).toBe(false);
    expect(isClassifierVerdict("Is it safe to swim here?")).toBe(false);
  });
});

describe("VerdictGate", () => {
  it("swallows a short verdict entirely", () => {
    expect(run(["User ", "Safety", ": ", "safe"])).toEqual({ verdict: true, streamed: "" });
  });

  it("swallows a long verdict once the window shows it", () => {
    const r = run(["User Safety: unsafe\n", "Safety Categories: ", "Violence"]);
    expect(r).toEqual({ verdict: true, streamed: "" });
  });

  it("streams a real answer in full and in order", () => {
    const tokens = ["I went ", "there ", "yesterday", " and it was ", "great."];
    expect(run(tokens)).toEqual({ verdict: false, streamed: tokens.join("") });
  });

  it("releases a short real answer at the end", () => {
    expect(run(["Sure", "!"])).toEqual({ verdict: false, streamed: "Sure!" });
  });
});

describe("endpointFor", () => {
  it("routes provider prefixes and leaves OpenRouter ids (with :free) alone", () => {
    const saved = { ...env };
    env.openrouterKey = "or"; env.groqKey = "gq"; env.geminiKey = "";
    expect(endpointFor("groq:llama-3.1-8b-instant")).toMatchObject(
      { model: "llama-3.1-8b-instant", key: "gq", openrouter: false });
    expect(endpointFor("google/gemma-4-31b-it:free")).toMatchObject(
      { model: "google/gemma-4-31b-it:free", key: "or", openrouter: true });
    expect(endpointFor("openrouter:openrouter/free")?.model).toBe("openrouter/free");
    // No Gemini key: skipped so the chain moves on.
    expect(endpointFor("gemini:gemini-2.5-flash-lite")).toBeNull();
    Object.assign(env, saved);
  });
});

describe("more providers", () => {
  it("routes mistral, inception and cerebras prefixes when their keys exist", () => {
    const saved = { ...env };
    env.mistralKey = "ms"; env.inceptionKey = ""; env.cerebrasKey = "cb"; env.openrouterKey = "";
    expect(endpointFor("mistral:mistral-small-2603")).toMatchObject(
      { url: "https://api.mistral.ai/v1/chat/completions", model: "mistral-small-2603", key: "ms" });
    expect(endpointFor("cerebras:gpt-oss-120b")?.url).toBe("https://api.cerebras.ai/v1/chat/completions");
    expect(endpointFor("inception:mercury-2.5")).toBeNull();
    Object.assign(env, saved);
  });
});

describe("requestOptions", () => {
  const ep = (url: string, model: string, openrouter = false) => ({ url, key: "k", model, openrouter });
  const groq = "https://api.groq.com/openai/v1/chat/completions";
  const gemini = "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions";

  it("keeps reasoning models quick on the fast tier", () => {
    expect(requestOptions(ep(groq, "openai/gpt-oss-20b"), "fast")).toMatchObject({ reasoning_effort: "low", max_tokens: 1500 });
    expect(requestOptions(ep(groq, "openai/gpt-oss-120b"), "smart")).toMatchObject({ reasoning_effort: "medium", max_tokens: 4000 });
    expect(requestOptions(ep(groq, "qwen/qwen3.8-27b"), "fast")).toMatchObject({ reasoning_effort: "none" });
    expect(requestOptions(ep(gemini, "gemini-2.5-flash"), "fast")).toMatchObject({ reasoning_effort: "none" });
  });

  it("leaves models without thinking alone", () => {
    expect(requestOptions(ep(gemini, "gemini-2.5-flash-lite"), "fast")).toEqual({ max_tokens: 1500 });
    expect(requestOptions(ep("https://api.mistral.ai/v1/chat/completions", "mistral-small-2603"), "fast"))
      .toEqual({ max_tokens: 1500 });
  });

  it("asks OpenRouter to keep thinking out of the answer", () => {
    expect(requestOptions(ep("https://openrouter.ai/api/v1/chat/completions", "openrouter/free", true), "fast"))
      .toMatchObject({ reasoning: { exclude: true } });
    expect(requestOptions(ep("https://openrouter.ai/api/v1/chat/completions", "openai/gpt-oss-20b", true), "fast"))
      .toMatchObject({ reasoning: { effort: "low", exclude: true } });
  });

  it("keeps the strip's reads short, steady, unthinking and away from providers that keep them", () => {
    const or = (m: string) => ep("https://openrouter.ai/api/v1/chat/completions", m, true);
    expect(requestOptions(or("google/gemini-2.5-flash-lite"), "suggest")).toEqual({
      max_tokens: 200, temperature: 0, provider: { data_collection: "deny" }, reasoning: { enabled: false } });
    expect(requestOptions(or("openai/gpt-oss-20b"), "suggest"))
      .toMatchObject({ provider: { data_collection: "deny" }, reasoning: { effort: "low", exclude: true } });
    const direct = requestOptions(ep(gemini, "gemini-2.5-flash"), "suggest");
    expect(direct).toMatchObject({ max_tokens: 200, temperature: 0, reasoning_effort: "none" });
    expect(direct).not.toHaveProperty("provider");
  });
});

describe("rate-limit cooldown", () => {
  it("skips a model that just hit its limit, then brings it back", () => {
    resetCooldowns();
    const chain = ["gemini:a", "groq:b", "groq:c"];
    noteRateLimited("gemini:a", "30", 1_000);
    expect(readyModels(chain, 1_000)).toEqual(["groq:b", "groq:c"]);
    expect(readyModels(chain, 31_001)).toEqual(chain);
  });

  it("defaults to a minute, caps at ten, and never empties the chain", () => {
    resetCooldowns();
    noteRateLimited("x", null, 0);
    noteRateLimited("y", "100000", 0);
    expect(readyModels(["x", "y"], 59_000)).toEqual(["x", "y"]);  // all cooling: try them anyway
    expect(readyModels(["x", "y", "z"], 59_000)).toEqual(["z"]);
    expect(readyModels(["x", "y"], 61_000).includes("x")).toBe(true);
    expect(readyModels(["y", "z"], 599_000)).toEqual(["z"]);
    expect(readyModels(["y", "z"], 600_001)).toEqual(["y", "z"]);
    resetCooldowns();
  });
});

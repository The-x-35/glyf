import { beforeAll, describe, expect, it } from "vitest";
import { env } from "../src/env.js";
import { READING_PROMPT, parseReading } from "../src/lib/reading.js";
import { signedInApp } from "./helpers.js";

beforeAll(() => {
  env.mockAI = true;
});

describe("reading a pause in typing", () => {
  const kinds = ["address", "phone", "upi"] as const;

  it("takes the action and the saved kind the model names", () => {
    expect(parseReading('{"intent":"places","field":"none"}', "any good cafes around", kinds))
      .toEqual({ intent: "places", field: null });
    expect(parseReading('```json\n{"intent":"rewrite","field":"address"}\n```', "cool just drop it off at", kinds))
      .toEqual({ intent: "rewrite", field: "address" });
    expect(parseReading('{"intent":"write"}', "can you help me with a birthday message", []))
      .toEqual({ intent: "write", field: null });
  });

  it("offers nothing it can't back", () => {
    // Email isn't saved, "field" isn't an action, and there is no JSON at all.
    expect(parseReading('{"intent":"field","field":"email"}', "you can mail me at", kinds)).toBeNull();
    expect(parseReading('{"intent":"launch_rocket"}', "go", kinds)).toBeNull();
    expect(parseReading("Sure! Here you go.", "go", kinds)).toBeNull();
    // Asking someone for theirs never offers this person's own.
    expect(parseReading('{"intent":"rewrite","field":"address"}', "whats your address btw i need to send the invite", kinds))
      .toEqual({ intent: "rewrite", field: null });
  });

  it("sends the kinds saved, never a value, and no field question when nothing is saved", () => {
    expect(READING_PROMPT("ship it to", ["address", "upi"])).toContain("field: one of address, upi");
    expect(READING_PROMPT("see you there then", [])).not.toContain("field");
  });
});

describe("POST /suggest", () => {
  const ask = (app: ReturnType<typeof signedInApp>, text: string, extra: Record<string, unknown> = {}) =>
    app.inject({ method: "POST", url: "/suggest", payload: { text, deviceId: "suggest-test-0001", ...extra } });

  it("offers a tidy-up for a message and nothing for a half-typed one", async () => {
    const app = signedInApp();
    expect((await ask(app, "ok will send the deck before six tmrw")).json().suggestion)
      .toMatchObject({ intent: "rewrite", label: "Tidy this up", action: "act" });
    expect((await ask(app, "hey how are")).json().suggestion).toBeNull();
    expect((await ask(app, "write a toast for my sister's wedding")).json().suggestion?.label).toBe("Write it for me");
  });

  it("never spends a run: suggestions have their own allowance", async () => {
    const runs = env.freeRunsPerDay;
    const suggestions = env.freeSuggestionsPerDay;
    env.freeRunsPerDay = 1;
    env.freeSuggestionsPerDay = 2;
    try {
      const app = signedInApp();
      expect((await ask(app, "ok will send the deck before six")).statusCode).toBe(200);
      expect((await ask(app, "fine the deck goes out at seven then")).statusCode).toBe(200);
      const third = await ask(app, "alright the deck goes out at eight");
      expect(third.statusCode).toBe(429);
      expect(third.json().error).toContain("suggestions");
      // The day's one run is still there for the person who holds space.
      const act = await app.inject({ method: "POST", url: "/act", payload: { text: "sunset", deviceId: "suggest-test-0001" } });
      expect(act.statusCode).toBe(200);
    } finally {
      env.freeRunsPerDay = runs;
      env.freeSuggestionsPerDay = suggestions;
    }
  });

  it("shows no chip when no model answers, but still what the rules know", async () => {
    const saved = { mockAI: env.mockAI, models: env.suggestModels, key: env.cerebrasKey };
    env.mockAI = false;
    env.suggestModels = ["cerebras:none"];
    env.cerebrasKey = "";
    try {
      const app = signedInApp();
      expect((await ask(app, "ya ok will send the deck before 6 tmrw")).json().suggestion).toBeNull();
      expect((await ask(app, "any good italian places in koramangala")).json().suggestion?.label).toBe("Show me places");
      expect((await ask(app, "sure, ship it to", { kinds: ["address"] })).json().suggestion)
        .toMatchObject({ intent: "detail", field: "address" });
    } finally {
      env.mockAI = saved.mockAI;
      env.suggestModels = saved.models;
      env.cerebrasKey = saved.key;
    }
  });
});

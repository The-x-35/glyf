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

  it("offers the AI's answer on a question, with or without its \"?\", but not on today's news", async () => {
    const app = signedInApp();
    for (const text of ["who is the ceo of tesla", "why is the sky blue?"]) {
      expect((await ask(app, text)).json().suggestion, text).toMatchObject({ intent: "answer", label: "AI answer", action: "act" });
    }
    expect((await ask(app, "who won the game last night")).json().suggestion).toBeNull();
    expect((await ask(app, "are you coming tonight?")).json().suggestion?.label).not.toBe("AI answer");
    // A question for someone where the writer is (audit, 2026-10-01).
    for (const text of ["is the store open", "whats the wifi password", "where are the keys"]) {
      expect((await ask(app, text)).json().suggestion?.label, text).not.toBe("AI answer");
    }
  });

  it("offers no tidy-up on a short casual line that reads fine", async () => {
    const app = signedInApp();
    for (const text of ["what time works for you", "running late, be there in 10"]) {
      expect((await ask(app, text)).json().suggestion?.label, text).not.toBe("Tidy this up");
    }
  });

  it("never spends a run: suggestions have their own allowance", async () => {
    const runs = env.freeRunsPerDay;
    const suggestions = env.freeSuggestionsPerDay;
    env.freeRunsPerDay = 1;
    env.freeSuggestionsPerDay = 2;
    try {
      const app = signedInApp();
      expect((await ask(app, "The deck goes out before six.")).statusCode).toBe(200);
      expect((await ask(app, "Fine, the deck goes out at seven then.")).statusCode).toBe(200);
      const third = await ask(app, "Alright, the deck goes out at eight.");
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

  it("counts only reads by the model: the rules and the cache are free", async () => {
    const suggestions = env.freeSuggestionsPerDay;
    env.freeSuggestionsPerDay = 1;
    try {
      const app = signedInApp();
      for (let i = 0; i < 3; i++) {
        expect((await ask(app, "any good italian places in koramangala")).statusCode).toBe(200);
      }
      // A message full of shorthand is a tidy-up by rule: no read spent.
      expect((await ask(app, "ok will send the deck b4 six dont worry")).statusCode).toBe(200);
      expect((await ask(app, "The deck goes out before six.")).statusCode).toBe(200);
      expect((await ask(app, "The deck goes out before six.")).statusCode).toBe(200);
      expect((await ask(app, "Fine, the deck goes out at seven then.")).statusCode).toBe(429);
    } finally {
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
      // Shorthand is a tidy-up without any model; a clean sentence needs one.
      expect((await ask(app, "ya ok will send the deck before 6 tmrw")).json().suggestion)
        .toMatchObject({ intent: "rewrite", label: "Tidy this up" });
      expect((await ask(app, "The report is ready for review tomorrow morning.")).json().suggestion).toBeNull();
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

describe("tidy by rule", () => {
  it("knows a message that needs tidying without a model", async () => {
    const { needsTidy } = await import("../src/lib/act.js");
    for (const t of ["ya ok will send the deck b4 6 dont worry about it", "hey sorry i cant make it today will call u later",
      "thx for the gift loved it sooo much", "bro the meeting got moved to 4 tell everyone"]) {
      expect(needsTidy(t), t).toBe(true);
    }
    // Questions, places, sums, clean sentences and half-typed ones go on to the rules and the model.
    for (const t of ["who won the f1 race today", "lets meet at the Blue Tokai in Indiranagar", "any good cafes near me",
      "3480/4 is what each of us pays", "Thanks so much, see you tomorrow.", "ok see u"]) {
      expect(needsTidy(t), t).toBe(false);
    }
  });

  it("calls a message rough for shorthand, a lowercase i, stretched letters or a long run-on", async () => {
    const { roughEnough } = await import("../src/lib/act.js");
    for (const t of ["ok will send the deck before six tmrw", "i think so", "sooo good", "bro the meeting got moved to 4 tell everyone"]) {
      expect(roughEnough(t), t).toBe(true);
    }
    for (const t of ["what time works for you", "running late, be there in 10", "see you at the station", "Thanks, see you soon"]) {
      expect(roughEnough(t), t).toBe(false);
    }
  });

  it("knows a question for someone where the writer is", async () => {
    const { localAsk } = await import("../src/lib/act.js");
    for (const t of ["is the store open", "Whats the WiFi password?", "where are the keys"]) expect(localAsk(t), t).toBe(true);
    for (const t of ["who is the ceo of tesla", "when does the louvre open", "can dogs eat grapes"]) expect(localAsk(t), t).toBe(false);
  });

  it("offers no tidy-up for a message already written with care", async () => {
    const { readsTidy } = await import("../src/lib/act.js");
    for (const t of ["Thanks so much for dinner last night, it was lovely.", "I will be there at 6.", "Are you coming tonight?"]) {
      expect(readsTidy(t), t).toBe(true);
    }
    for (const t of ["i will be there at 6.", "Ok will send it tmrw.", "Sooo good!", "Meeting moved to 3pm", "Hey , are you there?"]) {
      expect(readsTidy(t), t).toBe(false);
    }
  });
});

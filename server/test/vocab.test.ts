import { signedInApp } from "./helpers.js";
import { beforeAll, describe, expect, it } from "vitest";
import { env } from "../src/env.js";
import { cleanWord, parsePack } from "../src/lib/vocab.js";

describe("vocab packs", () => {
  beforeAll(() => {
    env.mockAI = true; // model calls burn zero quota
  });

  it("keeps words a keyboard can hold", () => {
    expect(cleanWord("acha")).toBe("acha");
    expect(cleanWord("  Google  Docs ")).toBe("Google Docs");
    expect(cleanWord("don't")).toBe("don't");
    expect(cleanWord("follow-up")).toBe("follow-up");
    expect(cleanWord("नमस्ते")).toBe("नमस्ते");
    expect(cleanWord("1234")).toBeNull();
    expect(cleanWord("me@glyf.so")).toBeNull();
    expect(cleanWord("https://x.com")).toBeNull();
    expect(cleanWord("a b c d")).toBeNull();
    expect(cleanWord("x".repeat(40))).toBeNull();
    expect(cleanWord(42)).toBeNull();
  });

  it("parses a model reply, dedupes and drops junk", () => {
    const pack = parsePack(
      'Sure! {"name": "Cardio Pune", "words": ["ECG", "ecg", "Ruby Hall", "acha", "http://x", 7], "phrases": ["BP is stable", "ok"]}',
      "fallback");
    expect(pack).toEqual({ name: "Cardio Pune", words: ["ECG", "Ruby Hall", "acha"], phrases: ["BP is stable"] });
    expect(parsePack("no json here", "x")).toBeNull();
    expect(parsePack('{"words": []}', "x")).toBeNull();
    expect(parsePack('{"words": ["yaar"]}', "Hinglish")?.name).toBe("Hinglish");
  });

  it("POST /vocab/generate returns a reviewed-shape pack and validates input", async () => {
    const app = signedInApp();
    const ok = await app.inject({
      method: "POST", url: "/vocab/generate",
      payload: { description: "Cardiologist in Pune who texts Hinglish", deviceId: "vocab-dev-0001" },
    });
    expect(ok.statusCode).toBe(200);
    const body = ok.json();
    expect(body.ok).toBe(true);
    expect(body.words).toContain("Cardiologist");
    expect(Array.isArray(body.phrases)).toBe(true);

    const bad = await app.inject({ method: "POST", url: "/vocab/generate", payload: { description: "", deviceId: "x" } });
    expect(bad.statusCode).toBe(400);
  });
});

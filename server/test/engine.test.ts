import { describe, expect, it } from "vitest";
import { loadRegistry, runGlyf, interpolate } from "../src/lib/glyfengine.js";
import { GlyfDefSchema } from "../src/schemas/glyfdef.js";
import { TTLCache } from "../src/lib/cache.js";
import { MemoryMeter } from "../src/lib/meter.js";

describe("registry (§10.9)", () => {
  it("loads every shipped def and each declares discloses", () => {
    const defs = loadRegistry();
    expect(defs.size).toBeGreaterThanOrEqual(20);
    for (const def of defs.values()) {
      expect(def.discloses.length).toBeGreaterThan(0);
      for (const d of def.discloses) expect(d.length).toBeGreaterThan(0);
    }
  });

  it("rejects a def without discloses", () => {
    const bad = {
      id: "x", version: 1, name: "x", input: "field",
      requires: { fullAccess: true, connectors: [], wallet: false },
      discloses: [],
      steps: [{ id: "s1", type: "llm", prompt: "p", out: "final" }],
      output: { mode: "preview", from: "final" },
    };
    expect(() => GlyfDefSchema.parse(bad)).toThrow();
  });

  it("parses chain/conditional steps (format supports them from day one)", () => {
    const chained = {
      id: "chain", version: 1, name: "chain", input: "field",
      requires: { fullAccess: true, connectors: ["notion"], wallet: false },
      discloses: ["your Notion workspace"],
      steps: [
        { id: "s1", type: "llm", prompt: "p", out: "draft" },
        { id: "s2", type: "tool", tool: "notion.search", args: { query: "{{draft}}" }, out: "docs" },
        { id: "s3", type: "if", cond: "{{docs.length}} > 0", then: ["s4"], else: ["s5"] },
        { id: "s4", type: "format", template: "{{docs}}", out: "final" },
        { id: "s5", type: "format", template: "No match", out: "final" },
      ],
      output: { mode: "preview", from: "final" },
    };
    expect(() => GlyfDefSchema.parse(chained)).not.toThrow();
  });
});

describe("engine", () => {
  it("interpolates vars", () => {
    expect(interpolate("a {{x}} c {{missing}}", { x: "b" })).toBe("a b c ");
  });

  it("runs llm + format chains, streaming only the output step", async () => {
    const def = GlyfDefSchema.parse({
      id: "t", version: 1, name: "t", input: "field",
      requires: { fullAccess: true, connectors: [], wallet: false },
      discloses: ["x"],
      vars: { greet: "hi" },
      steps: [
        { id: "s1", type: "llm", prompt: "{{greet}} {{input}}", out: "draft" },
        { id: "s2", type: "format", template: "<{{draft}}>", out: "final" },
      ],
      output: { mode: "preview", from: "final" },
    });
    const streamed: string[] = [];
    const result = await runGlyf({
      def, input: "world", vars: {},
      complete: async (_tier, prompt, onToken) => {
        onToken("LLM:");
        return `LLM:${prompt}`;
      },
      onToken: t => streamed.push(t),
    });
    expect(result).toBe("<LLM:hi world>");
    // s1 is not the output step — nothing streams from it.
    expect(streamed).toEqual([]);
  });

  it("caller vars override def vars", async () => {
    const def = GlyfDefSchema.parse({
      id: "t2", version: 1, name: "t", input: "field",
      requires: { fullAccess: true, connectors: [], wallet: false },
      discloses: ["x"],
      vars: { target: "English" },
      steps: [{ id: "s1", type: "format", template: "to {{target}}", out: "final" }],
      output: { mode: "preview", from: "final" },
    });
    const out = await runGlyf({
      def, input: "", vars: { target: "Hindi" },
      complete: async () => "", onToken: () => {},
    });
    expect(out).toBe("to Hindi");
  });

  it("ask without an answer fails closed with the question", async () => {
    const def = GlyfDefSchema.parse({
      id: "t3", version: 1, name: "t", input: "field",
      requires: { fullAccess: true, connectors: [], wallet: false },
      discloses: ["x"],
      steps: [{ id: "s1", type: "ask", question: "Which tone?", out: "final" }],
      output: { mode: "preview", from: "final" },
    });
    await expect(runGlyf({
      def, input: "", vars: {}, complete: async () => "", onToken: () => {},
    })).rejects.toThrow(/needs input/);
  });
});

describe("cache (§8.4)", () => {
  it("stores, expires, and keys deterministically", () => {
    const c = new TTLCache(1000);
    const k = TTLCache.key(["a", "b"]);
    expect(TTLCache.key(["a", "b"])).toBe(k);
    expect(TTLCache.key(["a", "c"])).not.toBe(k);
    const now = Date.now();
    c.set(k, "v", now);
    expect(c.get(k, now + 500)).toBe("v");
    expect(c.get(k, now + 1500)).toBeUndefined();
  });
});

describe("meter (§6.16)", () => {
  it("counts down, refuses at zero, resets next day", () => {
    const m = new MemoryMeter(2);
    const d1 = new Date("2026-09-11T10:00:00Z");
    expect(m.consume("dev", d1)).toBe(1);
    expect(m.consume("dev", d1)).toBe(0);
    expect(m.consume("dev", d1)).toBe(-1);
    expect(m.remaining("dev", d1)).toBe(0);
    const d2 = new Date("2026-09-12T10:00:00Z");
    expect(m.remaining("dev", d2)).toBe(2);
    expect(m.consume("other", d1)).toBe(1);
  });
});

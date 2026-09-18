import { signedInApp } from "./helpers.js";
import { beforeAll, describe, expect, it } from "vitest";
import { env } from "../src/env.js";
import { evalCond, interpolate, runGlyf } from "../src/lib/glyfengine.js";
import { GlyfDefSchema } from "../src/schemas/glyfdef.js";
import { loadTools } from "../src/lib/tools.js";
import { MemoryKV } from "../src/lib/store.js";
import { GlyfLibrary, validateUserDef, ensureInputWired } from "../src/lib/userglyfs.js";

process.env.MOCK_AI = "true";
beforeAll(() => { env.mockAI = true; });

const fakeLLM = async (_t: string, prompt: string, on: (t: string) => void) => {
  on("LLM");
  return `LLM:${prompt.slice(0, 30)}`;
};

function def(steps: unknown[], from = "final", vars: Record<string, string> = {}) {
  return GlyfDefSchema.parse({
    id: "t", version: 1, name: "t", input: "field",
    requires: { fullAccess: true, connectors: [], wallet: false },
    discloses: ["x"], vars, steps,
    output: { mode: "preview", from },
  });
}

describe("engine: conditionals + map + tools (§6.8 — the differentiator)", () => {
  it("evalCond covers comparisons, contains, truthiness", () => {
    const ctx = { n: "5", s: "hello world", empty: "", arr: '["a"]' };
    expect(evalCond("{{n}} > 3", ctx)).toBe(true);
    expect(evalCond("{{n}} <= 4", ctx)).toBe(false);
    expect(evalCond("{{s}} contains WORLD", ctx)).toBe(true);
    expect(evalCond("{{s}} == 'hello world'", ctx)).toBe(true);
    expect(evalCond("{{empty}}", ctx)).toBe(false);
    expect(evalCond("{{arr.length}} > 0", ctx)).toBe(true);
    expect(evalCond("{{missing}}", ctx)).toBe(false);
  });

  it("dotted interpolation reaches into JSON values", () => {
    const ctx = { docs: '[{"title":"Plan","url":"u1"}]' };
    expect(interpolate("{{docs.0.title}} — {{docs.0.url}}", ctx)).toBe("Plan — u1");
    expect(interpolate("{{docs.length}}", ctx)).toBe("1");
  });

  it("if branches run only the selected steps (the spec's canonical chain)", async () => {
    const d = def([
      { id: "s1", type: "format", template: '[{"title":"Doc","url":"u"}]', out: "docs" },
      { id: "s2", type: "if", cond: "{{docs.length}} > 0", then: ["s3"], else: ["s4"] },
      { id: "s3", type: "format", template: "{{docs.0.title}} — {{docs.0.url}}", out: "final" },
      { id: "s4", type: "format", template: "No match found", out: "final" },
    ]);
    expect(await runGlyf({ def: d, input: "", vars: {}, complete: fakeLLM, onToken: () => {} }))
      .toBe("Doc — u");

    const empty = def([
      { id: "s1", type: "format", template: "[]", out: "docs" },
      { id: "s2", type: "if", cond: "{{docs.length}} > 0", then: ["s3"], else: ["s4"] },
      { id: "s3", type: "format", template: "hit", out: "final" },
      { id: "s4", type: "format", template: "No match found", out: "final" },
    ]);
    expect(await runGlyf({ def: empty, input: "", vars: {}, complete: fakeLLM, onToken: () => {} }))
      .toBe("No match found");
  });

  it("map applies steps per item and collects results", async () => {
    const d = def([
      { id: "s1", type: "format", template: '["a","b","c"]', out: "list" },
      { id: "s2", type: "map", over: "list", steps: ["s3"], out: "mapped" },
      { id: "s3", type: "format", template: "<{{item}}>", out: "one" },
      { id: "s4", type: "format", template: "{{mapped}}", out: "final" },
    ]);
    expect(await runGlyf({ def: d, input: "", vars: {}, complete: fakeLLM, onToken: () => {} }))
      .toBe('["<a>","<b>","<c>"]');
  });

  it("ask resolves from vars or fails with the question", async () => {
    const d = def([
      { id: "s1", type: "ask", question: "Which city?", out: "city" },
      { id: "s2", type: "format", template: "city={{city}}", out: "final" },
    ]);
    expect(await runGlyf({ def: d, input: "", vars: { city: "Pune" }, complete: fakeLLM, onToken: () => {} }))
      .toBe("city=Pune");
    await expect(runGlyf({ def: d, input: "", vars: {}, complete: fakeLLM, onToken: () => {} }))
      .rejects.toThrow(/needs input: Which city\?/);
  });

  it("tool steps run registry tools (mocked) and reject unknown tools", async () => {
    const d = def([
      { id: "s1", type: "tool", tool: "weather.now", args: { place: "{{input}}" }, out: "final" },
    ]);
    const out = await runGlyf({ def: d, input: "Pune", vars: {}, complete: fakeLLM, onToken: () => {} });
    expect(out).toContain("Pune");
    expect(out).toContain("MOCK");

    const bad = def([
      { id: "s1", type: "tool", tool: "evil.exfil", args: {}, out: "final" },
    ]);
    await expect(runGlyf({ def: bad, input: "", vars: {}, complete: fakeLLM, onToken: () => {} }))
      .rejects.toThrow(/registry only/);
  });
});

describe("tool registry (§6.11)", () => {
  it("every tool declares discloses + limits", () => {
    const tools = loadTools();
    expect(tools.size).toBeGreaterThanOrEqual(7);
    for (const t of tools.values()) {
      expect(t.discloses.length).toBeGreaterThan(0);
      expect(t.rateLimit.perMin).toBeGreaterThan(0);
      expect(t.timeoutMs).toBeGreaterThan(0);
    }
  });
});

describe("builder input wiring", () => {
  it("appends {{input}} to the first llm step when the model forgot it", () => {
    const def = GlyfDefSchema.parse({
      id: "user.draft", version: 1, name: "Warm reply", icon: "message",
      input: "field",
      requires: { fullAccess: true, connectors: [], wallet: false },
      discloses: ["the text in your current field"],
      vars: {},
      steps: [{ id: "s1", type: "llm", model: "fast",
        prompt: "Reply warmly to the user's message. Only output the reply.",
        out: "final" }],
      output: { mode: "preview", from: "final" },
    });
    const wired = ensureInputWired(def);
    expect(wired.steps[0]).toMatchObject({ type: "llm" });
    expect(JSON.stringify(wired.steps[0])).toContain("{{input}}");
  });

  it("leaves defs alone when input is already referenced or not needed", () => {
    const withInput = GlyfDefSchema.parse({
      id: "user.draft", version: 1, name: "Echo", icon: "sparkles",
      input: "field",
      requires: { fullAccess: true, connectors: [], wallet: false },
      discloses: ["the text in your current field"],
      vars: {},
      steps: [{ id: "s1", type: "llm", model: "fast",
        prompt: "Rewrite: {{input}}", out: "final" }],
      output: { mode: "preview", from: "final" },
    });
    const before = JSON.stringify(withInput);
    expect(JSON.stringify(ensureInputWired(withInput))).toBe(before);

    const noInput = GlyfDefSchema.parse({
      id: "user.draft", version: 1, name: "Time", icon: "clock",
      input: "none",
      requires: { fullAccess: true, connectors: [], wallet: false },
      discloses: ["nothing"],
      vars: {},
      steps: [{ id: "s1", type: "tool", tool: "time.now",
        args: { timezone: "UTC" }, out: "final" }],
      output: { mode: "preview", from: "final" },
    });
    const before2 = JSON.stringify(noInput);
    expect(JSON.stringify(ensureInputWired(noInput))).toBe(before2);
  });
});

describe("user glyfs + hub (§6.8/§6.9)", () => {
  const lib = () => new GlyfLibrary(new MemoryKV());

  const userDef = {
    id: "user.draft", version: 1, name: "Shout", icon: "sparkles", input: "field",
    requires: { fullAccess: true, connectors: [], wallet: false },
    discloses: ["the text in your current field"],
    vars: {},
    steps: [{ id: "s1", type: "format", template: "{{input}}!!!", out: "final" }],
    output: { mode: "preview", from: "final" },
  };

  it("save → mine → resolve → publish → install → resolve-for-installer", () => {
    const l = lib();
    const saved = l.save("device-aaaaaaaa", userDef);
    expect("id" in saved && saved.id.startsWith("user.")).toBe(true);
    const id = (saved as { id: string }).id;

    expect(l.mine("device-aaaaaaaa")).toHaveLength(1);
    expect(l.resolve("device-aaaaaaaa", id)?.name).toBe("Shout");
    expect(l.resolve("device-bbbbbbbb", id)).toBeUndefined();

    expect(l.publish("device-aaaaaaaa", id)).toBeNull();
    expect(l.hubList()).toHaveLength(1);

    const installed = l.install("device-bbbbbbbb", id);
    expect("def" in installed).toBe(true);
    expect(l.resolve("device-bbbbbbbb", id)?.name).toBe("Shout");
    expect(l.hubList()[0].installs).toBe(1);
  });

  it("moderation: wallet glyfs and unknown tools are refused (§6.9/§11.5)", () => {
    expect(validateUserDef(GlyfDefSchema.parse({
      ...userDef, requires: { fullAccess: true, connectors: [], wallet: true },
    }))).toMatch(/wallet/);

    expect(validateUserDef(GlyfDefSchema.parse({
      ...userDef,
      steps: [{ id: "s1", type: "tool", tool: "exfil.everything", args: {}, out: "final" }],
    }))).toMatch(/registry/);

    expect(validateUserDef(GlyfDefSchema.parse(userDef))).toBeNull();
  });

  it("cannot save over someone else's glyf", () => {
    const l = lib();
    const id = (l.save("device-aaaaaaaa", userDef) as { id: string }).id;
    const stolen = l.save("device-bbbbbbbb", { ...userDef, id });
    expect("error" in stolen).toBe(true);
  });
});

describe("oauth broker (§6.11)", () => {
  it("google start fails closed without credentials, without naming server settings", async () => {
    delete process.env.GOOGLE_CLIENT_ID;
    const app = signedInApp();
    const res = await app.inject({
      method: "GET",
      url: "/oauth/google/start?deviceId=test-dev-00000001&scopes=calendar,gmail",
    });
    expect(res.statusCode).toBe(503);
    expect(res.json().error).toBe("Google sign-in isn't available yet");
    expect(res.json().error).not.toContain("GOOGLE_CLIENT_ID");
  });

  it("start builds a consent URL with exactly the chosen scopes when configured", async () => {
    process.env.GOOGLE_CLIENT_ID = "test-client";
    process.env.GOOGLE_CLIENT_SECRET = "test-secret";
    const app = signedInApp();
    const res = await app.inject({
      method: "GET",
      url: "/oauth/google/start?deviceId=test-dev-00000001&scopes=calendar",
    });
    expect(res.statusCode).toBe(200);
    const url = new URL(res.json().url);
    expect(url.host).toBe("accounts.google.com");
    const scope = url.searchParams.get("scope") ?? "";
    expect(scope).toContain("calendar.events");
    expect(scope).toContain("openid"); // identity always rides along
    expect(scope).not.toContain("gmail");
    expect(url.searchParams.get("code_challenge_method")).toBe("S256");
    delete process.env.GOOGLE_CLIENT_ID;
    delete process.env.GOOGLE_CLIENT_SECRET;
  });

  it("status reports per-device connection state", async () => {
    const app = signedInApp();
    const res = await app.inject({
      method: "GET", url: "/connectors/status?deviceId=test-dev-00000001",
    });
    expect(res.statusCode).toBe(200);
    const google = res.json().providers.find((p: { id: string }) => p.id === "google");
    expect(google.connected).toBe(false);
    expect(google.scopes).toEqual([]);
  });
});

describe("routes: builder + hub + connector + telemetry", () => {
  it("builder/generate (mock) returns a valid def; test runs it; save+publish+install round-trips", async () => {
    const app = signedInApp();
    const gen = await app.inject({
      method: "POST", url: "/builder/generate",
      payload: { description: "make text sound like a pirate", deviceId: "test-dev-00000001" },
    });
    expect(gen.statusCode).toBe(200);
    const def = gen.json().def;
    expect(def.discloses.length).toBeGreaterThan(0);

    const test = await app.inject({
      method: "POST", url: "/builder/test",
      payload: { def, input: "hello there", vars: {}, deviceId: "test-dev-00000001" },
    });
    expect(test.statusCode).toBe(200);
    expect(test.json().text).toContain("MOCK");

    const save = await app.inject({
      method: "POST", url: "/glyfs",
      payload: { deviceId: "test-dev-00000001", def },
    });
    expect(save.statusCode).toBe(200);
    const id = save.json().id;

    const pub = await app.inject({
      method: "POST", url: "/hub/publish",
      payload: { glyfId: id, deviceId: "test-dev-00000001" },
    });
    expect(pub.statusCode).toBe(200);

    const list = await app.inject({ method: "GET", url: "/hub/list" });
    expect(list.json().glyfs.some((g: { id: string }) => g.id === id)).toBe(true);

    const install = await app.inject({
      method: "POST", url: "/hub/install",
      payload: { glyfId: id, deviceId: "test-dev-00000002" },
    });
    expect(install.statusCode).toBe(200);

    // The installer can now RUN it through /glyf/run.
    const run = await app.inject({
      method: "POST", url: "/glyf/run",
      payload: { glyfId: id, input: "ahoy", vars: {}, deviceId: "test-dev-00000002" },
    });
    expect(run.payload).toContain("event: done");
  });

  it("a phone claiming pro gets no more runs than its plan allows (§6.16)", async () => {
    env.freeRunsPerDay = 1;
    const app = signedInApp();
    const run = (pro: boolean) => app.inject({
      method: "POST", url: "/glyf/run",
      payload: { glyfId: "rewrite.tighten", input: "x", vars: {}, deviceId: "pro-dev-00000001", pro },
    });
    await run(false);
    const blocked = await run(false);
    expect(blocked.payload).toContain("used up");
    // The cap belongs to the account, not to a flag in the request body.
    const claiming = await run(true);
    expect(claiming.payload).toContain("used up");
    env.freeRunsPerDay = 40;
  });

  it("keyless.weather glyf runs the tool through /glyf/run (W key path)", async () => {
    const app = signedInApp();
    const res = await app.inject({
      method: "POST", url: "/glyf/run",
      payload: { glyfId: "keyless.weather", input: "Pune", vars: {}, deviceId: "test-dev-00000003" },
    });
    expect(res.payload).toContain("Pune");
    expect(res.payload).toContain("event: done");
  });

  it("mockcal serves the ConnectorSurface (§6.12)", async () => {
    const app = signedInApp();
    const res = await app.inject({ method: "GET", url: "/connector/mockcal/events?q=design" });
    const body = res.json();
    expect(body.events).toHaveLength(1);
    expect(body.events[0].title).toContain("Design");
  });

  it("telemetry ingests events and reports the funnel", async () => {
    const app = signedInApp();
    const post = await app.inject({
      method: "POST", url: "/telemetry",
      payload: {
        deviceId: "test-dev-00000004",
        events: [{ event: "glyf_fired", ts: new Date().toISOString() }],
      },
    });
    expect(post.json().accepted).toBe(1);
    const funnel = await app.inject({ method: "GET", url: "/telemetry/funnel" });
    expect(funnel.json().events.glyf_fired).toBeDefined();
  });

  it("oauth start without credentials fails cleanly (§6.11 skeleton)", async () => {
    const app = signedInApp();
    const res = await app.inject({ method: "GET", url: "/oauth/google/start" });
    expect(res.statusCode).toBe(503);
    expect(res.json().error).not.toContain("server/.env");
  });
});

import { signedInApp } from "./helpers.js";
import { beforeAll, describe, expect, it } from "vitest";
import { env } from "../src/env.js";

beforeAll(() => {
  env.mockAI = true; // §8.4 — route tests burn zero quota
});

describe("routes", () => {
  it("GET /health reports mock mode without echoing secrets", async () => {
    const app = signedInApp();
    const res = await app.inject({ method: "GET", url: "/health" });
    const body = res.json();
    expect(body.ok).toBe(true);
    expect(body.mockAI).toBe(true);
    expect(JSON.stringify(body)).not.toContain("sk-or-");
  });

  it("GET /glyf/catalog lists defs with disclosures", async () => {
    const app = signedInApp();
    const res = await app.inject({ method: "GET", url: "/glyf/catalog" });
    const body = res.json();
    expect(body.glyfs.length).toBeGreaterThanOrEqual(9);
    for (const g of body.glyfs) expect(g.discloses.length).toBeGreaterThan(0);
  });

  it("POST /glyf/run streams token + done frames in mock mode", async () => {
    const app = signedInApp();
    const res = await app.inject({
      method: "POST",
      url: "/glyf/run",
      payload: {
        glyfId: "rewrite.polite",
        input: "send me the file now",
        vars: {},
        deviceId: "test-device-0001",
      },
    });
    expect(res.statusCode).toBe(200);
    expect(res.headers["content-type"]).toContain("text/event-stream");
    expect(res.payload).toContain("event: token");
    expect(res.payload).toContain("event: done");
    expect(res.payload).toContain("MOCK polite");
    expect(res.payload).toContain('"remaining":');
  });

  it("unknown glyf id → SSE error frame", async () => {
    const app = signedInApp();
    const res = await app.inject({
      method: "POST",
      url: "/glyf/run",
      payload: { glyfId: "nope", input: "", vars: {}, deviceId: "test-device-0001" },
    });
    expect(res.payload).toContain("event: error");
  });

  it("meter runs out → error frame + /meter reflects it", async () => {
    env.freeRunsPerDay = 2;
    const app = signedInApp();
    const run = () => app.inject({
      method: "POST",
      url: "/glyf/run",
      payload: { glyfId: "rewrite.tighten", input: "hello", vars: {}, deviceId: "meter-dev-01" },
    });
    await run();
    await run();
    const third = await run();
    expect(third.payload).toContain("Daily free runs used up");
    const meter = await app.inject({ method: "GET", url: "/meter/meter-dev-01" });
    expect(meter.json().remaining).toBe(0);
    env.freeRunsPerDay = 40;
  });

  it("translate goes between the person's two languages (mock echoes the prompt)", async () => {
    const app = signedInApp();
    const res = await app.inject({
      method: "POST",
      url: "/glyf/run",
      payload: {
        glyfId: "glyf.translate",
        input: "good morning",
        vars: { primary: "English", secondary: "Hindi" },
        deviceId: "test-device-0002",
      },
    });
    // The mock echoes the glyf's tag: the translate def ran end to end.
    expect(res.payload).toContain("translate: ");
  });
});

describe("keyboard search suite (/tools/run)", () => {
  beforeAll(() => {
    process.env.MOCK_AI = "true"; // runTool reads process.env directly
  });

  it("runs web.search and returns JSON rows", async () => {
    const app = signedInApp();
    const res = await app.inject({
      method: "POST",
      url: "/tools/run",
      payload: { id: "web.search", args: { query: "glass" }, deviceId: "t-1" },
    });
    expect(res.statusCode).toBe(200);
    const rows = JSON.parse(res.json().result);
    expect(rows.length).toBeGreaterThan(0);
    expect(rows[0].title).toContain("glass");
    expect(rows.at(-1).url).toContain("google.com/search");
  });

  it("runs yt.search and maps.search rows", async () => {
    const app = signedInApp();
    for (const id of ["yt.search", "maps.search"]) {
      const res = await app.inject({
        method: "POST",
        url: "/tools/run",
        payload: { id, args: { query: "cafe" }, deviceId: "t-1" },
      });
      expect(res.statusCode).toBe(200);
      const rows = JSON.parse(res.json().result);
      expect(rows[0].url).toContain("http");
    }
  });

  it("refuses oauth tools and unknown ids", async () => {
    const app = signedInApp();
    const oauth = await app.inject({
      method: "POST",
      url: "/tools/run",
      payload: { id: "calendar.today", args: {}, deviceId: "t-1" },
    });
    expect(oauth.statusCode).toBe(403);
    const unknown = await app.inject({
      method: "POST",
      url: "/tools/run",
      payload: { id: "nope.nope", args: {}, deviceId: "t-1" },
    });
    expect(unknown.statusCode).toBe(404);
  });
});

describe("waitlist", () => {
  it("accepts, dedupes, counts, and validates emails", async () => {
    const app = signedInApp();
    const ok = await app.inject({
      method: "POST", url: "/waitlist",
      payload: { email: "Hi@Example.com" },
    });
    expect(ok.statusCode).toBe(200);
    const again = await app.inject({
      method: "POST", url: "/waitlist",
      payload: { email: "hi@example.com" },
    });
    expect(again.json().ok).toBe(true);
    const count = await app.inject({ method: "GET", url: "/waitlist/count" });
    expect(count.json().count).toBeGreaterThanOrEqual(1);
    const bad = await app.inject({
      method: "POST", url: "/waitlist", payload: { email: "nope" },
    });
    expect(bad.statusCode).toBe(400);
  });
});

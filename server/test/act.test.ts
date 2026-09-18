import { signedInApp } from "./helpers.js";
import { afterEach, beforeAll, describe, expect, it } from "vitest";
import { env } from "../src/env.js";
import { listInsert, parsePlan, parseRewriteOptions, planByRules, rewriteStyles } from "../src/lib/act.js";
import type { PlaceCard } from "../src/lib/searchcards.js";
import { renderPage } from "../src/lib/pages.js";

/** Hold space → act on the typed intent. Rules route the obvious cases for
 *  free; the model only decides the rest, and nothing is invented. */

beforeAll(() => {
  env.mockAI = true;               // model calls burn zero quota
  process.env.MOCK_AI = "true";    // search providers answer from fixtures
});

describe("planByRules", () => {
  it("routes place lists, single places, videos and computed answers", () => {
    expect(planByRules("coffee near me")?.intent).toBe("places");
    expect(planByRules("nearest ATM")?.intent).toBe("place");
    expect(planByRules("SF best italian restaurant")?.intent).toBe("places");
    expect(planByRules("lofi beats playlist")?.intent).toBe("video");
    expect(planByRules("12*7")?.intent).toBe("answer");
    expect(planByRules("100 usd to inr")?.intent).toBe("answer");
    expect(planByRules("sunset")?.intent).toBe("answer");
  });

  it("leaves ambiguous text to the model", () => {
    expect(planByRules("Times Square Starbucks")).toBeNull();
    expect(planByRules("World Cup today")).toBeNull();
    expect(planByRules("running late dont order without me")).toBeNull();
    expect(planByRules("   ")).toBeNull();
  });
});

describe("parsePlan", () => {
  it("reads the first JSON object even when the model adds prose", () => {
    expect(parsePlan('Sure! {"intent":"place","query":"Starbucks Times Square"} done', "x"))
      .toEqual({ intent: "place", query: "Starbucks Times Square" });
  });

  it("rejects unknown intents and falls back to the typed query", () => {
    expect(parsePlan('{"intent":"launch_rocket","query":"x"}', "x")).toBeNull();
    expect(parsePlan('{"intent":"answer"}', "World Cup today"))
      .toEqual({ intent: "answer", query: "World Cup today" });
    expect(parsePlan("no json here", "x")).toBeNull();
  });
});

describe("listInsert", () => {
  it("drops one numbered line per place, each with its maps link", () => {
    const places: PlaceCard[] = [
      { kind: "place", id: "a", title: "Flour + Water", rating: 4.8, address: "Mission, SF",
        url: "https://maps.google.com/?q=a" },
      { kind: "place", id: "b", title: "Acquerello", url: "https://maps.google.com/?q=b" },
    ];
    expect(listInsert("SF best italian", places)).toBe(
      "SF best italian\n1. Flour + Water · 4.8★ · Mission, SF\nhttps://maps.google.com/?q=a\n" +
      "2. Acquerello\nhttps://maps.google.com/?q=b");
  });
});

describe("POST /act", () => {
  const post = async (text: string, extra: Record<string, unknown> = {}) => {
    const app = signedInApp();
    const res = await app.inject({
      method: "POST", url: "/act",
      payload: { text, deviceId: "test-device-act", ...extra },
    });
    return { status: res.statusCode, body: res.json() };
  };

  const freeRuns = env.freeRunsPerDay;
  afterEach(() => { env.freeRunsPerDay = freeRuns; });

  it("turns a place list request into place cards and a pasteable list", async () => {
    const { status, body } = await post("coffee near me");
    expect(status).toBe(200);
    expect(body.intent).toBe("places");
    expect(body.cards.map((c: PlaceCard) => c.kind)).toEqual(["place", "place"]);
    // Dev publishes the list as a live page on this server.
    expect(body.page).toMatch(/^http:\/\/127\.0\.0\.1:\d+\/p\/[\w-]{12}$/);
    expect(body.insert).toBe(`coffee near me\n${body.page}`);
  });

  it("serves the live page with every place, escaped, and 404s unknown ids", async () => {
    const app = signedInApp();
    const res = await app.inject({ method: "POST", url: "/act",
      payload: { text: "coffee near me", deviceId: "test-device-page" } });
    const id = String(res.json().page).split("/p/")[1];
    const page = await app.inject({ method: "GET", url: `/p/${id}` });
    expect(page.statusCode).toBe(200);
    expect(page.headers["content-type"]).toContain("text/html");
    expect(page.body).toContain("Blue Tokai Coffee");
    expect(page.body).toContain("Third Wave Coffee");
    expect(page.body).toContain("Made with");
    expect((await app.inject({ method: "GET", url: "/p/nope-not-a-page" })).statusCode).toBe(404);
  });

  it("returns a video card pasted Gboard-style", async () => {
    const { body } = await post("lofi beats video");
    expect(body.intent).toBe("video");
    expect(body.insert).toBe("https://youtu.be/jfKfPfyJRdk\n🎥 lofi hip hop radio — beats to relax/study to");
  });

  it("answers computable questions from the web vertical", async () => {
    const { body } = await post("sunset");
    expect(body.intent).toBe("answer");
    expect(body.insert).toBe("6:13 PM — Sunset · today");
  });

  it("tidies an ordinary message instead of looking anything up", async () => {
    const { body } = await post("hey im late dont order without me");
    expect(body.intent).toBe("rewrite");
    expect(body.cards).toEqual([]);
    expect(body.text).toContain("hey im late dont order without me");
    expect(body.insert).toBe(body.text);
  });

  it("is metered like any other AI run", async () => {
    env.freeRunsPerDay = 1;
    const app = signedInApp();
    const send = () => app.inject({ method: "POST", url: "/act",
      payload: { text: "sunset", deviceId: "metered-device-act" } });
    expect((await send()).statusCode).toBe(200);
    const blocked = await send();
    expect(blocked.statusCode).toBe(429);
    expect(blocked.json().error).toContain("used up");
  });

  it("serves static maps only for real coordinates, and only with a key", async () => {
    const app = signedInApp();
    const saved = process.env.GEOAPIFY_KEY;
    delete process.env.GEOAPIFY_KEY;
    const noKey = await app.inject({ method: "GET", url: "/search/staticmap?lat=40.75&lon=-73.98" });
    expect(noKey.statusCode).toBe(404);
    process.env.GEOAPIFY_KEY = "test-key";
    const bad = await app.inject({ method: "GET", url: "/search/staticmap?lat=91&lon=https://evil" });
    expect(bad.statusCode).toBe(404);
    if (saved === undefined) delete process.env.GEOAPIFY_KEY; else process.env.GEOAPIFY_KEY = saved;
  });

  it("rejects empty text without logging it", async () => {
    const { status } = await post("");
    expect(status).toBe(400);
  });
});

describe("renderPage", () => {
  it("escapes what it shows and never lets a card URL become script", () => {
    const html = renderPage({ title: "<script>x</script>", createdAt: 0, places: [
      { kind: "place", id: "1", title: "A&B <b>", url: "javascript:alert(1)" },
    ] });
    expect(html).not.toContain("<script>x");
    expect(html).toContain("&lt;script&gt;");
    expect(html).toContain("A&amp;B &lt;b&gt;");
    expect(html).not.toContain("javascript:");
  });
});


describe("rewrite options", () => {
  it("offers Hinglish only where people write it", () => {
    expect(rewriteStyles({ country: "IN" }).map(s => s.id)).toContain("hinglish");
    expect(rewriteStyles({ country: "US" }).map(s => s.id)).not.toContain("hinglish");
  });
  it("reads the versions in row order and drops empty ones", () => {
    const styles = rewriteStyles({ country: "US" });
    const out = parseRewriteOptions(
      'here: {"work":"I will send it by 6 PM.","basic":"ya ok, will send it by 6","polite":"","shorter":"By 6."}',
      styles);
    expect(out.map(o => o.label)).toEqual(["Basic", "Professional", "Shorter"]);
  });
});

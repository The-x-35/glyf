import { describe, expect, it } from "vitest";
import { composeInsert } from "../src/lib/searchcards.js";
import { evaluateMath, instantAnswer, isLive } from "../src/lib/answers.js";
import { env } from "../src/env.js";
import { aiAnswer, formatDistance, formatDuration, nameMatch, placeQuery, search } from "../src/lib/search.js";
import { clockIn, sunTimes } from "../src/lib/sun.js";

/** §6.12 search suite — the pure logic behind the Search / YouTube / Maps
 *  tabs. Both keyboards port these functions by hand, so these tests are the
 *  contract the three implementations are held to. */

describe("composeInsert (paste format)", () => {
  const video = {
    title: "lofi hip hop radio",
    url: "https://youtu.be/jfKfPfyJRdk",
    emoji: "🎥",
  };

  it("pastes link then emoji-prefixed title, Gboard-style", () => {
    expect(composeInsert(video, "titleAndLink"))
      .toBe("https://youtu.be/jfKfPfyJRdk\n🎥 lofi hip hop radio");
  });

  it("pastes only the URL when the user picked link-only", () => {
    expect(composeInsert(video, "linkOnly")).toBe("https://youtu.be/jfKfPfyJRdk");
  });

  it("adds a place's address as a third line", () => {
    const place = {
      title: "Blue Tokai Coffee",
      url: "https://maps.google.com/?q=x",
      emoji: "📍",
      extra: "45 Church St, Bengaluru",
    };
    expect(composeInsert(place, "titleAndLink")).toBe(
      "https://maps.google.com/?q=x\n📍 Blue Tokai Coffee\n45 Church St, Bengaluru");
    // …but never in link-only mode.
    expect(composeInsert(place, "linkOnly")).toBe("https://maps.google.com/?q=x");
  });

  it("omits the emoji prefix for a plain web link", () => {
    expect(composeInsert(
      { title: "Sunset times", url: "https://timeanddate.com" }, "titleAndLink"))
      .toBe("https://timeanddate.com\nSunset times");
  });

  it("falls back to the bare URL when there is no title", () => {
    expect(composeInsert({ title: "   ", url: "https://x.dev" }, "titleAndLink"))
      .toBe("https://x.dev");
  });
});

describe("evaluateMath", () => {
  it("evaluates with correct precedence and associativity", () => {
    expect(evaluateMath("2+2")).toBe(4);
    expect(evaluateMath("2+3*4")).toBe(14);
    expect(evaluateMath("(2+3)*4")).toBe(20);
    expect(evaluateMath("2^3^2")).toBe(512);       // right-associative
    expect(evaluateMath("1250*4")).toBe(5000);
    expect(evaluateMath("-5+3")).toBe(-2);
    expect(evaluateMath("10 / 4")).toBe(2.5);
    expect(evaluateMath("1,000+1")).toBe(1001);
  });

  it("declines anything that is not a calculation", () => {
    // A bare number is not worth a card.
    expect(evaluateMath("42")).toBeNull();
    expect(evaluateMath("best pizza")).toBeNull();
    expect(evaluateMath("")).toBeNull();
    expect(evaluateMath("2+")).toBeNull();
    expect(evaluateMath("(2+3")).toBeNull();
    expect(evaluateMath("2++")).toBeNull();
  });

  it("never divides by zero and never executes the input", () => {
    expect(evaluateMath("1/0")).toBeNull();
    // The query arrives straight from a keyboard: no identifiers, ever.
    expect(evaluateMath("process.exit(1)")).toBeNull();
    expect(evaluateMath("require('fs')")).toBeNull();
  });
});

describe("sunTimes", () => {
  it("computes a plausible sunset for a known place and date", () => {
    // Bengaluru (12.97N, 77.59E) on 2026-09-14 — sunset is ~18:2x IST.
    const t = sunTimes(12.97, 77.59, new Date("2026-09-14T06:00:00Z"));
    expect(t.sunset).not.toBeNull();
    const clock = clockIn(t.sunset!, "Asia/Kolkata");
    expect(clock).toMatch(/^6:\d\d PM$/);
  });

  it("puts sunrise before sunset, and golden hour before sunset", () => {
    const t = sunTimes(51.5, -0.12, new Date("2026-06-21T12:00:00Z"));
    expect(t.sunrise!.getTime()).toBeLessThan(t.sunset!.getTime());
    expect(t.goldenHour!.getTime()).toBeLessThan(t.sunset!.getTime());
  });

  it("reports the midnight sun instead of inventing a sunset", () => {
    // Longyearbyen in midsummer: the sun never sets.
    const t = sunTimes(78.22, 15.65, new Date("2026-06-21T12:00:00Z"));
    expect(t.polar).toBe("day");
    expect(t.sunset).toBeNull();
    // …and polar night in midwinter.
    expect(sunTimes(78.22, 15.65, new Date("2026-12-21T12:00:00Z")).polar)
      .toBe("night");
  });

  it("answers sunset from the time zone's city when no location is shared", async () => {
    const card = await instantAnswer("sunset time today", { tz: "Asia/Kolkata" });
    expect(card?.id).toBe("sunset");
    expect(card?.value).toMatch(/\d{1,2}:\d{2}/);
    expect(card?.sub).toContain("New Delhi");
    // Sent as the answer itself, never as a search link.
    expect(card?.say).toMatch(/^Sunset in New Delhi is at \d{1,2}:\d{2} [AP]M 🌇$/);
    expect(composeInsert(card!, "titleAndLink")).toBe(card!.say);
    // An unknown zone and no location: no guess at all.
    expect(await instantAnswer("sunset time today", { tz: "Antarctica/Troll" })).toBeNull();
    // A shared location wins and names no city.
    const here = await instantAnswer("what time is sunset", { lat: 19.07, lon: 72.87, tz: "Asia/Kolkata" });
    expect(here?.sub).toBe("Sunset · today");
  });

  it("tracks the seasons — a London summer day is longer than a winter one", () => {
    const summer = sunTimes(51.5, -0.12, new Date("2026-06-21T12:00:00Z"));
    const winter = sunTimes(51.5, -0.12, new Date("2026-12-21T12:00:00Z"));
    const length = (t: typeof summer) => t.sunset!.getTime() - t.sunrise!.getTime();
    expect(length(summer)).toBeGreaterThan(length(winter) + 6 * 3600_000);
  });
});

describe("formatters", () => {
  it("renders ISO-8601 durations the way YouTube does", () => {
    expect(formatDuration("PT4M13S")).toBe("4:13");
    expect(formatDuration("PT1H2M14S")).toBe("1:02:14");
    expect(formatDuration("PT45S")).toBe("0:45");
    expect(formatDuration("PT2H")).toBe("2:00:00");
    expect(formatDuration("not a duration")).toBe("");
  });

  it("renders distance in the unit a human would say", () => {
    expect(formatDistance(350)).toBe("350 m");
    expect(formatDistance(1200)).toBe("1.2 km");
    expect(formatDistance(23000)).toBe("23 km");
  });
});

describe("placeQuery", () => {
  it("takes an area out of a place search", () => {
    expect(placeQuery("best biryani near indiranagar")).toEqual(
      { what: "biryani", where: "indiranagar", nearby: false });
    expect(placeQuery("hotels in goa")).toEqual({ what: "hotels", where: "goa", nearby: false });
    expect(placeQuery("good cafes around Koramangala?")).toEqual(
      { what: "cafes", where: "Koramangala", nearby: false });
  });

  it("knows 'nearest' and 'near me' mean around the caller", () => {
    expect(placeQuery("nearest atm")).toEqual({ what: "atm", nearby: true });
    expect(placeQuery("cafes near me")).toEqual({ what: "cafes", nearby: true });
    expect(placeQuery("closest pharmacy open now")).toMatchObject({ nearby: true });
  });

  it("leaves a place's own name alone", () => {
    expect(placeQuery("Times Square Starbucks")).toEqual({ what: "Times Square Starbucks", nearby: false });
    expect(placeQuery("Phoenix Marketcity")).toEqual({ what: "Phoenix Marketcity", nearby: false });
  });
});

describe("nameMatch", () => {
  it("ranks the place named in the query above shops inside it", () => {
    expect(nameMatch("Phoenix Marketcity", "Phoenix Marketcity Bangalore"))
      .toBeGreaterThan(nameMatch("Starbucks", "Phoenix Marketcity Bangalore"));
    expect(nameMatch("Aramane Donne Biryani", "biryani")).toBe(1);
    expect(nameMatch("Taj Hotel", "hotels")).toBe(1);
  });
});

describe("the web tab without a search key", () => {
  it("knows which searches a model must not answer from memory", () => {
    expect(isLive("ipl score today")).toBe(true);
    expect(isLive("bitcoin price")).toBe(true);
    expect(isLive("capital of peru")).toBe(false);
  });

  it("turns the model's two lines into a headline and a sentence", async () => {
    const card = await aiAnswer("capital of peru",
      async () => "Lima\nLima is the capital and largest city of Peru.");
    expect(card).toMatchObject({ kind: "answer", art: "define", value: "Lima" });
    expect(card?.sub).toBe("Lima is the capital and largest city of Peru.");
    // A tap sends the sentence, not a search link.
    expect(composeInsert(card!, "titleAndLink")).toBe("Lima is the capital and largest city of Peru.");
  });

  it("shows nothing rather than a guess", async () => {
    expect(await aiAnswer("weather in pune", async () => "Sunny")).toBeNull();
    expect(await aiAnswer("capital of peru", async () => "NO")).toBeNull();
    expect(await aiAnswer("capital of peru", async () => { throw new Error("down"); })).toBeNull();
  });

  it("answers with the model and drops the Google row; a live search keeps it", async () => {
    const before = {
      mock: env.mockAI, flag: process.env.MOCK_AI,
      brave: process.env.BRAVE_SEARCH_KEY, serper: process.env.SERPER_API_KEY,
    };
    env.mockAI = true;              // the model answers "MOCK …" and burns nothing
    process.env.MOCK_AI = "false";  // …while the search rungs run for real
    delete process.env.BRAVE_SEARCH_KEY;
    delete process.env.SERPER_API_KEY;
    try {
      const answered = await search("web", "who painted the mona lisa");
      expect(answered.provider).toBe("ai");
      expect(answered.cards.map(c => c.kind)).toEqual(["answer"]);

      const live = await search("web", "ipl score today");
      expect(live.provider).toBe("none");
      expect(live.cards.map(c => c.id)).toEqual(["tail"]);

      // /act writes its own answer, so it asks for lookups only.
      const lookups = await search("web", "who painted the mona lisa", {}, { model: false });
      expect(lookups.provider).toBe("none");
    } finally {
      env.mockAI = before.mock;
      if (before.flag === undefined) delete process.env.MOCK_AI; else process.env.MOCK_AI = before.flag;
      if (before.brave !== undefined) process.env.BRAVE_SEARCH_KEY = before.brave;
      if (before.serper !== undefined) process.env.SERPER_API_KEY = before.serper;
    }
  });
});

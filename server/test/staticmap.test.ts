import { afterEach, beforeEach, describe, expect, it } from "vitest";
import { drawAhead, drawMap, forgetMaps, mapAsk } from "../src/lib/staticmap.js";

/** A stand-in Geoapify that records what it was asked and answers after a
 *  moment, as the real one does (two to four seconds). */
function fakeGeoapify(ok = true) {
  const asked: string[] = [];
  const fetcher = (async (url: string | URL | Request) => {
    asked.push(String(url));
    await new Promise(r => setTimeout(r, 20));
    return new Response(ok ? new Uint8Array([0xff, 0xd8, 0xff]) : "no", {
      status: ok ? 200 : 500,
      headers: { "content-type": "image/jpeg" },
    });
  }) as typeof fetch;
  return { asked, fetcher };
}

describe("place card maps", () => {
  let saved: string | undefined;
  beforeEach(() => {
    saved = process.env.GEOAPIFY_KEY;
    process.env.GEOAPIFY_KEY = "test-key";
    forgetMaps();
  });
  afterEach(() => {
    if (saved === undefined) delete process.env.GEOAPIFY_KEY; else process.env.GEOAPIFY_KEY = saved;
    forgetMaps();
  });

  it("draws a map once, however many ask for it while it is being drawn", async () => {
    const geo = fakeGeoapify();
    const ask = mapAsk({ lat: "12.971937", lon: "77.641916", w: "300", h: "300" })!;
    const [a, b] = await Promise.all([drawMap(ask, geo.fetcher), drawMap(ask, geo.fetcher)]);
    const again = await drawMap(ask, geo.fetcher);
    expect(geo.asked).toHaveLength(1);
    expect(a?.type).toBe("image/jpeg");
    expect(b).toBe(a);
    expect(again).toBe(a);
    expect(geo.asked[0]).toContain("style=positron");
  });

  it("keeps the light and the dark map apart", async () => {
    const geo = fakeGeoapify();
    await drawMap(mapAsk({ lat: "1", lon: "2" })!, geo.fetcher);
    await drawMap(mapAsk({ lat: "1", lon: "2", dark: "1" })!, geo.fetcher);
    expect(geo.asked).toHaveLength(2);
    expect(geo.asked[1]).toContain("style=dark-matter");
  });

  it("does not keep a map Geoapify failed to draw", async () => {
    const failing = fakeGeoapify(false);
    const ask = mapAsk({ lat: "1", lon: "2" })!;
    expect(await drawMap(ask, failing.fetcher)).toBeNull();
    const working = fakeGeoapify();
    expect(await drawMap(ask, working.fetcher)).not.toBeNull();
    expect(working.asked).toHaveLength(1);
  });

  it("draws a search's first six maps ahead, in the keyboard's theme", async () => {
    const geo = fakeGeoapify();
    const cards = [
      { thumb: "https://i.ytimg.com/vi/x/hq.jpg" },
      { thumb: "/search/photo?ref=places%2Fa%2Fphotos%2Fb" },
      ...Array.from({ length: 8 }, (_, i) => ({ thumb: `/search/staticmap?lat=12.9${i}&lon=77.6&w=300&h=300` })),
      {},
    ];
    expect(drawAhead(cards, true, geo.fetcher)).toBe(6);
    expect(geo.asked).toHaveLength(6);
    expect(geo.asked.every(u => u.includes("style=dark-matter") && u.includes("width=300"))).toBe(true);
    // The phone's own ask for the first one then waits on that draw.
    await drawMap(mapAsk({ lat: "12.90", lon: "77.6", w: "300", h: "300", dark: "1" })!, geo.fetcher);
    expect(geo.asked).toHaveLength(6);
  });

  it("refuses a spot that is not a real one", () => {
    expect(mapAsk({ lat: "91", lon: "0" })).toBeNull();
    expect(mapAsk({ lat: "12", lon: "https://evil" })).toBeNull();
    expect(mapAsk({})).toBeNull();
    expect(mapAsk({ lat: "1", lon: "2", w: "5000", h: "1" })).toMatchObject({ w: 800, h: 80 });
  });

  it("draws nothing without a key", async () => {
    delete process.env.GEOAPIFY_KEY;
    const geo = fakeGeoapify();
    expect(await drawMap(mapAsk({ lat: "1", lon: "2" })!, geo.fetcher)).toBeNull();
    expect(geo.asked).toHaveLength(0);
  });
});

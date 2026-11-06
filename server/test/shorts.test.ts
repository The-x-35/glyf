import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import Fastify from "fastify";
import { composeInsert } from "../src/lib/searchcards.js";
import {
  durationSeconds, search, searchProviders, shortsQuery, shortsURL, SHORTS_MAX_SECONDS,
} from "../src/lib/search.js";
import { suggest } from "../src/lib/suggest.js";
import { searchRoutes } from "../src/routes/search.js";

/** The Shorts tab (2026-11-06): YouTube search.list with videoDuration=short,
 *  then videos.list to keep only what is really a Short (≤ 3 min), vertical
 *  first, linked as youtube.com/shorts/<id>. YouTube is faked here. */

interface FakeVideo { id: string; duration: string; w?: number; h?: number; live?: string; title?: string }

function fakeYouTube(videos: FakeVideo[]) {
  const calls: URL[] = [];
  const fetchMock = vi.fn(async (input: string | URL) => {
    const url = new URL(String(input));
    calls.push(url);
    const ok = (body: unknown) => new Response(JSON.stringify(body), {
      status: 200, headers: { "content-type": "application/json" },
    });
    if (url.pathname.endsWith("/youtube/v3/search")) {
      return ok({
        items: videos.map(v => ({
          id: { videoId: v.id },
          snippet: { title: `${v.title ?? v.id} &amp; co`, channelTitle: "Searched" },
        })),
      });
    }
    if (url.pathname.endsWith("/youtube/v3/videos")) {
      const wanted = new Set((url.searchParams.get("id") ?? "").split(","));
      return ok({
        items: videos.filter(v => wanted.has(v.id)).map(v => ({
          id: v.id,
          contentDetails: { duration: v.duration },
          snippet: {
            title: v.title ?? v.id, channelTitle: "Catzilla",
            liveBroadcastContent: v.live ?? "none",
            thumbnails: {
              high: { url: `https://i.ytimg.com/vi/${v.id}/hqdefault.jpg` },
              standard: { url: `https://i.ytimg.com/vi/${v.id}/sddefault.jpg` },
            },
          },
          // YouTube sends these as strings.
          player: v.w ? { embedWidth: String(v.w), embedHeight: String(v.h) } : {},
        })),
      });
    }
    return new Response("not faked", { status: 404 });
  });
  vi.stubGlobal("fetch", fetchMock);
  return { calls, fetchMock };
}

describe("shorts helpers", () => {
  it("reads YouTube's ISO durations as seconds", () => {
    expect(durationSeconds("PT27S")).toBe(27);
    expect(durationSeconds("PT3M")).toBe(180);
    expect(durationSeconds("PT3M1S")).toBe(181);
    expect(durationSeconds("PT1H2M14S")).toBe(3734);
    expect(durationSeconds("P0D")).toBeNull();
    expect(durationSeconds("")).toBeNull();
  });

  it("asks YouTube with #shorts unless the user already typed it", () => {
    expect(shortsQuery("cat")).toBe("cat #shorts");
    expect(shortsQuery("cat #shorts")).toBe("cat #shorts");
    expect(shortsQuery("cat #Short")).toBe("cat #Short");
  });

  it("links into the Shorts player", () => {
    expect(shortsURL("ih7q2SE5M18")).toBe("https://www.youtube.com/shorts/ih7q2SE5M18");
    expect(SHORTS_MAX_SECONDS).toBe(180);
  });

  it("pastes a Short like a video: link, then the 🎥 title", () => {
    expect(composeInsert({
      title: "Ranking Chaotic Cat Moments", url: shortsURL("GVES6-kBzRE"), emoji: "🎥",
    }, "titleAndLink")).toBe("https://www.youtube.com/shorts/GVES6-kBzRE\n🎥 Ranking Chaotic Cat Moments");
    expect(composeInsert({
      title: "Ranking Chaotic Cat Moments", url: shortsURL("GVES6-kBzRE"), emoji: "🎥",
    }, "linkOnly")).toBe("https://www.youtube.com/shorts/GVES6-kBzRE");
  });
});

describe("search(\"shorts\") against a faked YouTube", () => {
  const saved = { mock: process.env.MOCK_AI, key: process.env.YOUTUBE_API_KEY };
  beforeEach(() => {
    process.env.MOCK_AI = "false";
    process.env.YOUTUBE_API_KEY = "test-key";
  });
  afterEach(() => {
    vi.unstubAllGlobals();
    if (saved.mock === undefined) delete process.env.MOCK_AI; else process.env.MOCK_AI = saved.mock;
    if (saved.key === undefined) delete process.env.YOUTUBE_API_KEY; else process.env.YOUTUBE_API_KEY = saved.key;
  });

  it("keeps only ≤ 3 min, non-live videos, vertical first, as shorts links", async () => {
    const { calls } = fakeYouTube([
      { id: "land1", duration: "PT40S", w: 1138, h: 640 },     // short but landscape
      { id: "long1", duration: "PT3M34S", w: 360, h: 640 },    // vertical, too long
      { id: "vert1", duration: "PT20S", w: 360, h: 640, title: "Cat water" },
      { id: "edge1", duration: "PT3M", w: 360, h: 640 },       // exactly three minutes
      { id: "live1", duration: "PT0S", w: 360, h: 640, live: "live" },
      { id: "nodim", duration: "PT15S" },                      // aspect unknown
    ]);
    const out = await search("shorts", "cats filter test", { country: "US" });
    expect(out.vertical).toBe("shorts");
    expect(out.provider).toBe("youtube-data-api");
    const shorts = out.cards.filter(c => c.kind === "short");
    expect(shorts.map(c => c.id)).toEqual(["vert1", "edge1", "land1", "nodim"]);
    const first = shorts[0] as Extract<typeof shorts[number], { kind: "short" }>;
    expect(first).toMatchObject({
      kind: "short", videoId: "vert1", title: "Cat water", channel: "Catzilla",
      duration: "0:20", seconds: 20, portrait: true, emoji: "🎥",
      url: "https://www.youtube.com/shorts/vert1",
      thumb: "https://i.ytimg.com/vi/vert1/sddefault.jpg",
    });
    expect((shorts[2] as { portrait?: boolean }).portrait).toBe(false);
    expect("portrait" in shorts[3]).toBe(false);
    // The YouTube results link closes the list.
    expect(out.cards.at(-1)).toMatchObject({ kind: "link", id: "tail", title: "More Shorts on YouTube" });

    const searchCall = calls.find(u => u.pathname.endsWith("/search"))!;
    expect(searchCall.searchParams.get("videoDuration")).toBe("short");
    expect(searchCall.searchParams.get("type")).toBe("video");
    expect(searchCall.searchParams.get("q")).toBe("cats filter test #shorts");
    expect(searchCall.searchParams.get("regionCode")).toBe("US");
    const videosCall = calls.find(u => u.pathname.endsWith("/videos"))!;
    expect(videosCall.searchParams.get("part")).toBe("contentDetails,snippet,player");
    expect(videosCall.searchParams.get("maxHeight")).toBe("640");
  });

  it("caches a query so a repeat costs no quota", async () => {
    const { fetchMock } = fakeYouTube([{ id: "c1", duration: "PT9S", w: 360, h: 640 }]);
    const a = await search("shorts", "cache me shorts");
    const b = await search("shorts", "Cache me shorts ");
    expect(b).toEqual(a);
    expect(fetchMock).toHaveBeenCalledTimes(2);   // one search.list + one videos.list
    // …and the YouTube tab keeps its own entry for the same words.
    fakeYouTube([]);
    const yt = await search("yt", "cache me shorts");
    expect(yt.vertical).toBe("yt");
  });

  it("shows only the YouTube link when YouTube fails or there is no key", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => new Response("quota", { status: 403 })));
    const failed = await search("shorts", "quota gone");
    expect(failed.provider).toBe("none");
    expect(failed.cards.map(c => c.id)).toEqual(["tail"]);
    expect(failed.cards[0].url).toBe("https://www.youtube.com/results?search_query=quota%20gone%20%23shorts");

    delete process.env.YOUTUBE_API_KEY;
    const keyless = await search("shorts", "no key at all");
    expect(keyless.cards.map(c => c.id)).toEqual(["tail"]);
    expect(searchProviders().shorts).toBe("none");
  });
});

describe("the Shorts tab's routes", () => {
  it("accepts the shorts vertical on POST /search and /search/suggest", async () => {
    const saved = process.env.MOCK_AI;
    process.env.MOCK_AI = "true";   // the fixed cards; no network
    const app = Fastify();
    const guard = { spend: async () => ({ ok: true }) } as never;
    const kv = { get: () => undefined } as never;
    searchRoutes(app, kv, guard);
    const res = await app.inject({
      method: "POST", url: "/search",
      payload: { vertical: "shorts", query: "cats", deviceId: "dev-1" },
    });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.vertical).toBe("shorts");
    expect(body.cards[0]).toMatchObject({ kind: "short", url: "https://www.youtube.com/shorts/ih7q2SE5M18", emoji: "🎥" });

    const land = await app.inject({ method: "GET", url: "/search/suggest?vertical=shorts&deviceId=dev-1" });
    expect(land.statusCode).toBe(200);
    expect(land.json().cards.every((c: { kind: string }) => c.kind === "query")).toBe(true);

    const bad = await app.inject({ method: "GET", url: "/search/suggest?vertical=reels" });
    expect(bad.statusCode).toBe(400);
    await app.close();
    if (saved === undefined) delete process.env.MOCK_AI; else process.env.MOCK_AI = saved;
  });

  it("opens on trending searches, never an empty tab", async () => {
    const saved = process.env.MOCK_AI;
    process.env.MOCK_AI = "false";
    vi.stubGlobal("fetch", vi.fn(async () => new Response(
      "<rss><channel><item><title>World Series</title></item><item><title>Taylor Swift</title></item></channel></rss>",
      { status: 200 })));
    try {
      const out = await suggest("shorts", { country: "ZZ" });
      expect(out.provider).toBe("google-trends");
      expect(out.cards.map(c => c.title)).toEqual(["World Series", "Taylor Swift"]);
      expect(out.cards.every(c => c.kind === "query")).toBe(true);

      vi.stubGlobal("fetch", vi.fn(async () => new Response("down", { status: 503 })));
      const cold = await suggest("shorts", { country: "ZY" });
      expect(cold.provider).toBe("starter");
      expect(cold.cards.length).toBeGreaterThan(0);
    } finally {
      vi.unstubAllGlobals();
      if (saved === undefined) delete process.env.MOCK_AI; else process.env.MOCK_AI = saved;
    }
  });
});

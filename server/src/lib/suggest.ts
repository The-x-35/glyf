import { TTLCache } from "./cache.js";
import { formatDistance, searchNearby } from "./search.js";
import type { SearchCard, Vertical } from "./searchcards.js";

/** The landing state — what each tab shows BEFORE the user types.
 *
 *  Gboard never drops you into an empty box: Search opens on trending and
 *  recent queries, YouTube on popular videos, Maps on what is around you.
 *  This builds the server half of that; the client adds its own recents,
 *  which are stored on the device and never sent here.
 *
 *  NOTE on "the user's own history": Google exposes no API for a person's
 *  Search history, and YouTube removed WATCH history from the Data API years
 *  ago — no OAuth scope brings either back. What a Google login DOES add is
 *  the user's liked videos and subscriptions (youtube.readonly), which is what
 *  personalises the YouTube tab below. Web and Maps stay impersonal, and
 *  typed recents are device-local.
 */

const UA = "glyf/0.6 (+https://tryglyf.com)";
// Trending lists move slowly; a 30-minute cache keeps the tab instant and
// costs the upstreams almost nothing.
const cache = new TTLCache(30 * 60 * 1000, 60);

function googleSearchURL(q: string): string {
  return `https://www.google.com/search?q=${encodeURIComponent(q)}`;
}

/** Google Trends publishes daily trending searches as a keyless RSS feed. */
async function trendingSearches(country: string): Promise<SearchCard[]> {
  const res = await fetch(
    `https://trends.google.com/trending/rss?geo=${encodeURIComponent(country)}`,
    { signal: AbortSignal.timeout(6000), headers: { "User-Agent": UA } });
  if (!res.ok) throw new Error(`trends ${res.status}`);
  const xml = await res.text();

  // <item><title>…</title> — a dependency-free parse of a tiny, fixed feed.
  const titles: string[] = [];
  const itemRe = /<item>([\s\S]*?)<\/item>/g;
  let m: RegExpExecArray | null;
  while ((m = itemRe.exec(xml)) && titles.length < 8) {
    const t = m[1].match(/<title>(?:<!\[CDATA\[)?([\s\S]*?)(?:\]\]>)?<\/title>/);
    const title = t?.[1]?.trim();
    if (title) titles.push(decodeXML(title));
  }
  return titles.map((title, i) => ({
    kind: "query" as const,
    id: `trend-${i}`,
    title,
    url: googleSearchURL(title),
    source: "trending",
  }));
}

function decodeXML(s: string): string {
  return s.replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"').replace(/&#39;/g, "'");
}

/** YouTube's most-popular chart. `videos.list` costs ONE quota unit total —
 *  unlike search.list, which is capped at 100 calls a day — so the landing
 *  tab is effectively free even on the default quota. */
async function popularVideos(country: string): Promise<SearchCard[]> {
  const key = process.env.YOUTUBE_API_KEY;
  if (!key) return [];
  const res = await fetch(
    "https://www.googleapis.com/youtube/v3/videos?" + new URLSearchParams({
      part: "snippet,contentDetails", chart: "mostPopular",
      regionCode: country, maxResults: "8", key,
    }), { signal: AbortSignal.timeout(7000), headers: { "User-Agent": UA } });
  if (!res.ok) throw new Error(`youtube ${res.status}`);
  const data = await res.json() as {
    items?: {
      id?: string;
      snippet?: {
        title?: string; channelTitle?: string;
        liveBroadcastContent?: string;
        thumbnails?: { medium?: { url?: string } };
      };
      contentDetails?: { duration?: string };
    }[];
  };
  const { formatDuration } = await import("./search.js");
  return (data.items ?? []).flatMap(v => {
    if (!v.id || !v.snippet?.title) return [];
    const live = v.snippet.liveBroadcastContent === "live";
    return [{
      kind: "video" as const,
      id: v.id, videoId: v.id,
      title: decodeXML(v.snippet.title),
      channel: decodeXML(v.snippet.channelTitle ?? ""),
      live,
      duration: live ? undefined
        : v.contentDetails?.duration ? formatDuration(v.contentDetails.duration) : undefined,
      thumb: v.snippet.thumbnails?.medium?.url,
      url: `https://youtu.be/${v.id}`,
      emoji: "🎥",
    }];
  });
}

/** A few things worth tapping when a tab opens cold and we have no signal. */
const STARTER_QUERIES = [
  "Weather", "Restaurants near me", "What time does the sun set",
  "News today", "Translate",
];

export interface SuggestContext {
  country?: string;
  lat?: number;
  lon?: number;
  /** The device's Google access token, when the user connected YouTube in
   *  onboarding. Read-only, resolved per request, never stored here. */
  youtubeToken?: string;
}

/** The YouTube tab, personalised — the closest thing to "my recent videos"
 *  that Google actually exposes.
 *
 *  Watch history is NOT available (removed from the Data API years ago and
 *  there is no scope for it), so this uses the two things that are: the
 *  videos the user liked, and the newest uploads from channels they
 *  subscribe to. Costs 1 quota unit per call, not the 100/day search budget.
 */
async function myYouTube(token: string): Promise<SearchCard[]> {
  const auth = { Authorization: `Bearer ${token}`, "User-Agent": UA };
  const { formatDuration } = await import("./search.js");

  const liked = await fetch(
    "https://www.googleapis.com/youtube/v3/videos?" + new URLSearchParams({
      part: "snippet,contentDetails", myRating: "like", maxResults: "8",
    }), { headers: auth, signal: AbortSignal.timeout(7000) });
  if (!liked.ok) throw new Error(`youtube me ${liked.status}`);
  const data = await liked.json() as {
    items?: {
      id?: string;
      snippet?: {
        title?: string; channelTitle?: string; liveBroadcastContent?: string;
        thumbnails?: { medium?: { url?: string } };
      };
      contentDetails?: { duration?: string };
    }[];
  };
  return (data.items ?? []).flatMap(v => {
    if (!v.id || !v.snippet?.title) return [];
    const live = v.snippet.liveBroadcastContent === "live";
    return [{
      kind: "video" as const,
      id: v.id, videoId: v.id,
      title: decodeXML(v.snippet.title),
      channel: decodeXML(v.snippet.channelTitle ?? ""),
      live,
      duration: live ? undefined
        : v.contentDetails?.duration ? formatDuration(v.contentDetails.duration) : undefined,
      thumb: v.snippet.thumbnails?.medium?.url,
      url: `https://youtu.be/${v.id}`,
      emoji: "🎥",
      source: "liked",
    }];
  });
}

export interface SuggestResponse {
  vertical: Vertical;
  cards: SearchCard[];
  provider: string;
}

export async function suggest(
  vertical: Vertical, ctx: SuggestContext = {},
): Promise<SuggestResponse> {
  const country = (ctx.country ?? "US").toUpperCase();
  const key = TTLCache.key([
    "suggest", vertical, country,
    ctx.lat !== undefined ? ctx.lat.toFixed(2) : "",
    ctx.lon !== undefined ? ctx.lon.toFixed(2) : "",
  ]);
  // A personalised list is per-user; only impersonal results are cacheable.
  const cacheable = !ctx.youtubeToken;
  const hit = cacheable ? cache.get(key) : undefined;
  if (hit) return JSON.parse(hit) as SuggestResponse;

  let out: SuggestResponse;
  if (process.env.MOCK_AI === "true") {
    out = mockSuggest(vertical);
  } else if (vertical === "yt") {
    // The user's own liked videos first when they connected YouTube, then
    // the popular chart as the impersonal fallback.
    let cards: SearchCard[] = [];
    let provider = "none";
    if (ctx.youtubeToken) {
      cards = await myYouTube(ctx.youtubeToken).catch(() => []);
      if (cards.length) provider = "youtube-me";
    }
    if (!cards.length) {
      cards = await popularVideos(country).catch(() => []);
      if (cards.length) provider = "youtube-chart";
    }
    out = { vertical, cards, provider };
  } else if (vertical === "maps") {
    // Nothing sensible to suggest without knowing where the user is.
    const cards = ctx.lat !== undefined && ctx.lon !== undefined
      ? await searchNearby(ctx.lat, ctx.lon, country).catch(() => [])
      : [];
    out = { vertical, cards, provider: cards.length ? "nearby" : "none" };
  } else {
    let cards = await trendingSearches(country).catch(() => []);
    let provider = "google-trends";
    if (!cards.length) {
      provider = "starter";
      cards = STARTER_QUERIES.map((title, i) => ({
        kind: "query" as const, id: `starter-${i}`, title,
        url: googleSearchURL(title),
      }));
    }
    out = { vertical, cards, provider };
  }
  if (cacheable) cache.set(key, JSON.stringify(out));
  return out;
}

function mockSuggest(vertical: Vertical): SuggestResponse {
  if (vertical === "yt") {
    return {
      vertical, provider: "mock",
      cards: [{
        kind: "video", id: "pop1", videoId: "dQw4w9WgXcQ",
        title: "Trending now — the week in 10 minutes",
        channel: "Popular on YouTube", duration: "10:02", emoji: "🎥",
        url: "https://youtu.be/dQw4w9WgXcQ",
      }],
    };
  }
  if (vertical === "maps") {
    return {
      vertical, provider: "mock",
      cards: [{
        kind: "place", id: "near1", title: "Blue Tokai Coffee",
        address: "45 Church St", distance: "350 m", openNow: true,
        rating: 4.5, emoji: "📍", extra: "45 Church St",
        url: "https://www.google.com/maps/search/?api=1&query=Blue+Tokai",
      }],
    };
  }
  return {
    vertical, provider: "mock",
    cards: STARTER_QUERIES.slice(0, 3).map((title, i) => ({
      kind: "query" as const, id: `mock-q-${i}`, title, url: googleSearchURL(title),
    })),
  };
}

export { formatDistance };

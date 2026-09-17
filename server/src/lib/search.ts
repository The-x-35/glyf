import { instantAnswer, type AnswerContext } from "./answers.js";
import { TTLCache } from "./cache.js";
import type {
  AnswerCard, LinkCard, PlaceCard, SearchCard, SearchResponse, VideoCard,
  Vertical,
} from "./searchcards.js";

/** The search suite's engine: one function per vertical, each a chain of
 *  providers that degrades instead of failing.
 *
 *  Keys are OPTIONAL everywhere. With none set the suite still returns real
 *  results (DuckDuckGo instant answers, OpenStreetMap places, keyless answer
 *  cards); adding a key upgrades that vertical in place with no client
 *  change. `provider` in the response says which rung actually answered.
 */

const UA = "glyf/0.6 (+https://tryglyf.com)";

// Search results are shared across users and go stale slowly, so a short
// cache both speeds up repeat queries and protects a metered API key from
// being burned by the same query typed twice.
const cache = new TTLCache(10 * 60 * 1000, 400);

async function json<T>(
  url: string, timeoutMs: number, headers: Record<string, string> = {},
): Promise<T> {
  const res = await fetch(url, {
    signal: AbortSignal.timeout(timeoutMs),
    headers: { "User-Agent": UA, accept: "application/json", ...headers },
  });
  if (!res.ok) throw new Error(`upstream ${res.status}`);
  return res.json() as Promise<T>;
}

export interface SearchContext extends AnswerContext {
  /** Two-letter region for locale-aware results ("IN", "US"). */
  country?: string;
}

function hostOf(url: string): string {
  try { return new URL(url).hostname.replace(/^www\./, ""); } catch { return ""; }
}

function googleSearchURL(q: string): string {
  return `https://www.google.com/search?q=${encodeURIComponent(q)}`;
}

// ── web ───────────────────────────────────────────────────────────────────

async function braveWeb(q: string, ctx: SearchContext): Promise<LinkCard[]> {
  const key = process.env.BRAVE_SEARCH_KEY;
  if (!key) return [];
  const params = new URLSearchParams({ q, count: "6", safesearch: "moderate" });
  if (ctx.country) params.set("country", ctx.country);
  const data = await json<{
    web?: { results?: {
      title?: string; url?: string; description?: string;
      thumbnail?: { src?: string }; meta_url?: { hostname?: string };
    }[] };
  }>(`https://api.search.brave.com/res/v1/web/search?${params}`, 6000, {
    "X-Subscription-Token": key,
    "Accept-Encoding": "gzip",
  });
  return (data.web?.results ?? [])
    .filter(r => r.url && r.title)
    .slice(0, 6)
    .map((r, i) => ({
      kind: "link" as const,
      id: `brave-${i}`,
      title: stripTags(r.title!),
      url: r.url!,
      snippet: r.description ? stripTags(r.description) : undefined,
      domain: r.meta_url?.hostname?.replace(/^www\./, "") ?? hostOf(r.url!),
      thumb: r.thumbnail?.src,
    }));
}

/** Serper returns a real Google SERP — including the answer box and knowledge
 *  panel Gboard shows — in one call.
 *
 *  Google's own Custom Search JSON API is closed to new customers (and is
 *  being retired in 2027), so this is the practical way to put actual Google
 *  results in the keyboard. */
interface SerperResult {
  answer: AnswerCard | null;
  links: LinkCard[];
}

async function serperWeb(q: string, ctx: SearchContext): Promise<SerperResult> {
  const key = process.env.SERPER_API_KEY;
  if (!key) return { answer: null, links: [] };
  const res = await fetch("https://google.serper.dev/search", {
    method: "POST",
    signal: AbortSignal.timeout(7000),
    headers: { "X-API-KEY": key, "content-type": "application/json" },
    body: JSON.stringify({
      q, num: 10,
      ...(ctx.country ? { gl: ctx.country.toLowerCase() } : {}),
    }),
  });
  if (!res.ok) throw new Error(`serper ${res.status}`);
  const data = await res.json() as {
    answerBox?: {
      title?: string; answer?: string; snippet?: string;
      snippetHighlighted?: string[]; link?: string;
    };
    knowledgeGraph?: {
      title?: string; type?: string; description?: string;
      descriptionLink?: string; imageUrl?: string;
    };
    organic?: {
      title?: string; link?: string; snippet?: string;
      position?: number; imageUrl?: string;
    }[];
  };

  let answer: AnswerCard | null = null;
  const box = data.answerBox;
  if (box && (box.answer || box.snippetHighlighted?.[0] || box.snippet)) {
    const value = box.answer ?? box.snippetHighlighted?.[0] ?? "";
    answer = {
      kind: "answer", id: "serper-answer",
      art: "none",
      title: box.title ?? q,
      value: value || (box.title ?? q),
      sub: value && box.snippet && box.snippet !== value ? box.snippet : box.title,
      source: box.link ? hostOf(box.link) : "google.com",
      url: box.link ?? googleSearchURL(q),
    };
  } else if (data.knowledgeGraph?.description) {
    const kg = data.knowledgeGraph;
    answer = {
      kind: "answer", id: "serper-kg", art: "define",
      title: kg.title ?? q,
      value: kg.title ?? q,
      sub: [kg.type, kg.description].filter(Boolean).join(" · "),
      source: kg.descriptionLink ? hostOf(kg.descriptionLink) : "google.com",
      url: kg.descriptionLink ?? googleSearchURL(q),
    };
  }

  const links = (data.organic ?? [])
    .filter(r => r.link && r.title)
    .slice(0, 6)
    .map((r, i) => ({
      kind: "link" as const,
      id: `g-${i}`,
      title: r.title!,
      url: r.link!,
      snippet: r.snippet,
      domain: hostOf(r.link!),
      thumb: r.imageUrl,
    }));
  return { answer, links };
}

function stripTags(s: string): string {
  return s.replace(/<[^>]*>/g, "").trim();
}

async function searchWeb(q: string, ctx: SearchContext): Promise<SearchResponse> {
  const cards: SearchCard[] = [];

  // Locally-computable answers (a calculation, today's sunset) beat anything
  // upstream: instant, free, and always available.
  let answer = await instantAnswer(q, ctx).catch(() => null);

  // No key configured = an answers-only tab: the computed cards still work
  // and the tail row hands off to Google. Never a fabricated result list.
  let provider = "none";
  let links: LinkCard[] = [];
  try {
    const serper = await serperWeb(q, ctx);
    if (serper.links.length || serper.answer) {
      provider = "google";
      links = serper.links;
      answer ??= serper.answer;
    }
  } catch { /* fall through */ }
  if (!links.length) {
    try {
      links = await braveWeb(q, ctx);
      if (links.length) provider = "brave";
    } catch { /* fall through */ }
  }
  if (answer) cards.push(answer);
  cards.push(...links);
  // A tail row is always present, so the suite is never a dead end.
  cards.push({
    kind: "link", id: "tail",
    title: `See all results for “${q}”`,
    url: googleSearchURL(q), domain: "google.com",
  });
  return { vertical: "web", query: q, cards, provider };
}

// ── youtube ───────────────────────────────────────────────────────────────

/** ISO-8601 PT1H2M14S → 1:02:14 */
export function formatDuration(iso: string): string {
  const m = iso.match(/^P(?:(\d+)D)?T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?$/);
  if (!m) return "";
  const d = Number(m[1] ?? 0), h = Number(m[2] ?? 0) + d * 24;
  const min = Number(m[3] ?? 0), s = Number(m[4] ?? 0);
  const pad = (n: number) => String(n).padStart(2, "0");
  return h > 0 ? `${h}:${pad(min)}:${pad(s)}` : `${min}:${pad(s)}`;
}

async function youtubeAPI(q: string, ctx: SearchContext): Promise<VideoCard[]> {
  const key = process.env.YOUTUBE_API_KEY;
  if (!key) return [];
  const search = await json<{
    items?: {
      id?: { videoId?: string };
      snippet?: {
        title?: string; channelTitle?: string;
        liveBroadcastContent?: string;
        thumbnails?: { medium?: { url?: string }; high?: { url?: string } };
      };
    }[];
  }>("https://www.googleapis.com/youtube/v3/search?" + new URLSearchParams({
    part: "snippet", type: "video", maxResults: "6", q, key,
    ...(ctx.country ? { regionCode: ctx.country } : {}),
  }), 7000);

  const base = (search.items ?? [])
    .filter(v => v.id?.videoId)
    .map(v => ({
      kind: "video" as const,
      id: v.id!.videoId!,
      videoId: v.id!.videoId!,
      title: decodeEntities(v.snippet?.title ?? "Video"),
      channel: decodeEntities(v.snippet?.channelTitle ?? ""),
      live: v.snippet?.liveBroadcastContent === "live",
      thumb: v.snippet?.thumbnails?.medium?.url ?? v.snippet?.thumbnails?.high?.url,
      url: `https://youtu.be/${v.id!.videoId}`,
      emoji: "🎥",
    }));
  if (!base.length) return [];

  // One extra call turns the whole page into durations — the detail that
  // makes the card read as YouTube rather than a link list.
  try {
    const details = await json<{
      items?: { id?: string; contentDetails?: { duration?: string };
        snippet?: { liveBroadcastContent?: string } }[];
    }>("https://www.googleapis.com/youtube/v3/videos?" + new URLSearchParams({
      part: "contentDetails,snippet", id: base.map(v => v.videoId).join(","), key,
    }), 6000);
    const byId = new Map((details.items ?? []).map(d => [d.id, d]));
    for (const v of base) {
      const d = byId.get(v.videoId);
      const live = d?.snippet?.liveBroadcastContent === "live";
      v.live = v.live || live;
      if (!live && d?.contentDetails?.duration) {
        (v as VideoCard).duration = formatDuration(d.contentDetails.duration);
      }
    }
  } catch { /* durations are a nicety, never a failure */ }
  return base;
}

function decodeEntities(s: string): string {
  return s
    .replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<").replace(/&gt;/g, ">");
}

async function searchYouTube(q: string, ctx: SearchContext): Promise<SearchResponse> {
  let cards: VideoCard[] = [];
  let provider = "none";
  try {
    cards = await youtubeAPI(q, ctx);
    if (cards.length) provider = "youtube-data-api";
  } catch { /* fall through */ }
  const tail: LinkCard = {
    kind: "link", id: "tail",
    title: cards.length ? `More on YouTube for “${q}”` : `Search YouTube for “${q}”`,
    url: `https://www.youtube.com/results?search_query=${encodeURIComponent(q)}`,
    domain: "youtube.com",
  };
  return { vertical: "yt", query: q, cards: [...cards, tail], provider };
}

// ── maps ──────────────────────────────────────────────────────────────────

function haversine(aLat: number, aLon: number, bLat: number, bLon: number): number {
  const R = 6371000, toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(bLat - aLat), dLon = toRad(bLon - aLon);
  const s = Math.sin(dLat / 2) ** 2
    + Math.cos(toRad(aLat)) * Math.cos(toRad(bLat)) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(s));
}

export function formatDistance(metres: number): string {
  if (metres < 950) return `${Math.round(metres / 10) * 10} m`;
  return `${(metres / 1000).toFixed(metres < 9500 ? 1 : 0)} km`;
}

/** The share URL Google Maps itself produces — name for humans, place id so
 *  the app opens the exact listing rather than re-searching. */
function mapsURL(name: string, placeId?: string): string {
  const params = new URLSearchParams({ api: "1", query: name });
  if (placeId) params.set("query_place_id", placeId);
  return `https://www.google.com/maps/search/?${params}`;
}

async function googlePlaces(q: string, ctx: SearchContext): Promise<PlaceCard[]> {
  const key = process.env.GOOGLE_PLACES_KEY;
  if (!key) return [];
  const body: Record<string, unknown> = { textQuery: q, pageSize: 6 };
  if (ctx.lat !== undefined && ctx.lon !== undefined) {
    body.locationBias = {
      circle: { center: { latitude: ctx.lat, longitude: ctx.lon }, radius: 15000 },
    };
  }
  const res = await fetch("https://places.googleapis.com/v1/places:searchText", {
    method: "POST",
    signal: AbortSignal.timeout(7000),
    headers: {
      "content-type": "application/json",
      "X-Goog-Api-Key": key,
      "X-Goog-FieldMask": [
        "places.id", "places.displayName", "places.formattedAddress",
        "places.rating", "places.userRatingCount",
        "places.currentOpeningHours.openNow", "places.location",
        "places.photos.name", "places.googleMapsUri",
      ].join(","),
    },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`places ${res.status}`);
  const data = await res.json() as {
    places?: {
      id?: string; displayName?: { text?: string }; formattedAddress?: string;
      rating?: number; userRatingCount?: number;
      currentOpeningHours?: { openNow?: boolean };
      location?: { latitude?: number; longitude?: number };
      photos?: { name?: string }[]; googleMapsUri?: string;
    }[];
  };
  return (data.places ?? []).flatMap(p => {
    const name = p.displayName?.text;
    if (!name) return [];
    const lat = p.location?.latitude, lon = p.location?.longitude;
    const photo = p.photos?.[0]?.name;
    return [{
      kind: "place" as const,
      id: p.id ?? name,
      title: name,
      address: p.formattedAddress,
      rating: p.rating,
      ratingCount: p.userRatingCount,
      openNow: p.currentOpeningHours?.openNow,
      lat, lon,
      distance: lat !== undefined && lon !== undefined
        && ctx.lat !== undefined && ctx.lon !== undefined
        ? formatDistance(haversine(ctx.lat, ctx.lon, lat, lon)) : undefined,
      // Proxied so the API key never reaches a client.
      thumb: photo ? `/search/photo?ref=${encodeURIComponent(photo)}` : undefined,
      url: p.googleMapsUri ?? mapsURL(name, p.id),
      emoji: "📍",
      extra: p.formattedAddress,
    }];
  });
}

/** Geoapify — the no-credit-card Places provider.
 *
 *  Same OpenStreetMap data underneath as Nominatim, but as a real hosted
 *  service: 3,000 requests/day free, 5 req/s, commercial use permitted with
 *  a "Powered by Geoapify" attribution, and no billing account to open. That
 *  makes it the one place provider we can ship without a card.
 *
 *  What it does NOT have is ratings or open-now — those exist only in
 *  Google's and Yelp's data, not in OSM. Cards degrade to name + distance +
 *  address, which the renderers already handle.
 */
const GEOAPIFY_CATEGORIES: [RegExp, string][] = [
  [/\b(coffee|cafe|café|espresso|barista)\b/i, "catering.cafe"],
  [/\b(restaurant|food|dinner|lunch|eat)\b/i, "catering.restaurant"],
  [/\b(bar|pub|brewery|beer)\b/i, "catering.bar"],
  [/\b(atm|cash)\b/i, "service.financial.atm"],
  [/\b(bank)\b/i, "service.financial.bank"],
  [/\b(pharmacy|chemist|medical store)\b/i, "healthcare.pharmacy"],
  [/\b(hospital|clinic|doctor)\b/i, "healthcare.hospital"],
  [/\b(petrol|gas station|fuel|diesel)\b/i, "service.vehicle.fuel"],
  [/\b(hotel|stay|lodge)\b/i, "accommodation.hotel"],
  [/\b(gym|fitness)\b/i, "sport.fitness"],
  [/\b(park|garden)\b/i, "leisure.park"],
  [/\b(supermarket|grocery|groceries)\b/i, "commercial.supermarket"],
  [/\b(bakery|bread)\b/i, "commercial.food_and_drink.bakery"],
];

interface GeoapifyFeature {
  properties?: {
    name?: string; formatted?: string; address_line2?: string;
    lat?: number; lon?: number; place_id?: string; distance?: number;
  };
}

function geoapifyCard(f: GeoapifyFeature, ctx: SearchContext): PlaceCard[] {
  const p = f.properties;
  const name = p?.name || p?.formatted?.split(",")[0];
  if (!p || !name) return [];
  const address = p.address_line2 || p.formatted;
  const metres = p.distance ?? (
    p.lat !== undefined && p.lon !== undefined
      && ctx.lat !== undefined && ctx.lon !== undefined
      ? haversine(ctx.lat, ctx.lon, p.lat, p.lon) : undefined);
  return [{
    kind: "place" as const,
    id: p.place_id ?? `${p.lat},${p.lon}`,
    title: name,
    address,
    lat: p.lat, lon: p.lon,
    distance: metres !== undefined ? formatDistance(metres) : undefined,
    url: mapsURL(`${name} ${address ?? ""}`.trim()),
    emoji: "📍",
    extra: address,
  }];
}

async function geoapifyPlaces(q: string, ctx: SearchContext): Promise<PlaceCard[]> {
  const key = process.env.GEOAPIFY_KEY;
  if (!key) return [];
  const here = ctx.lat !== undefined && ctx.lon !== undefined;
  const pq = placeQuery(q);
  const term = pq.where || pq.nearby ? pq.what : q;

  // "biryani near indiranagar": find the area first, then search around it.
  let around = here && pq.nearby ? { lat: ctx.lat!, lon: ctx.lon! } : undefined;
  if (pq.where) {
    const area = new URLSearchParams({ text: pq.where, limit: "1", apiKey: key });
    if (here) area.set("bias", `proximity:${ctx.lon},${ctx.lat}`);
    const found = await json<{ features?: GeoapifyFeature[] }>(
      `https://api.geoapify.com/v1/geocode/search?${area}`, 7000).catch(() => null);
    const p = found?.features?.[0]?.properties;
    if (p?.lat !== undefined && p?.lon !== undefined) around = { lat: p.lat, lon: p.lon };
  }
  // Distances are always from the caller, not from the area searched.
  const cards = (features: GeoapifyFeature[]) => features.flatMap(f => geoapifyCard(
    pq.where && f.properties ? { properties: { ...f.properties, distance: undefined } } : f, ctx));

  // "coffee near me" is a CATEGORY query — Places answers it properly and
  // returns the distance for us. A named place goes to geocoding instead.
  const category = GEOAPIFY_CATEGORIES.find(([re]) => re.test(term))?.[1];
  if (around && category) {
    const data = await json<{ features?: GeoapifyFeature[] }>(
      "https://api.geoapify.com/v2/places?" + new URLSearchParams({
        categories: category,
        filter: `circle:${around.lon},${around.lat},3000`,
        bias: `proximity:${around.lon},${around.lat}`,
        limit: "8", apiKey: key,
      }), 7000);
    const rows = cards(data.features ?? []);
    if (rows.length) return rows;
  }

  const params = new URLSearchParams({ text: term, limit: "8", apiKey: key });
  const bias = around ?? (here ? { lat: ctx.lat!, lon: ctx.lon! } : undefined);
  if (bias) params.set("bias", `proximity:${bias.lon},${bias.lat}`);
  if (around) params.set("filter", `circle:${around.lon},${around.lat},5000`);
  const data = await json<{ features?: GeoapifyFeature[] }>(
    `https://api.geoapify.com/v1/geocode/search?${params}`, 7000);
  return cards(data.features ?? []).slice(0, 6);
}

/** "coffee near me" is a category query, not a name query. OSM has no such
 *  concept, so the keyless path maps the common ones onto OSM tags and asks
 *  Overpass for what is actually around the caller — otherwise Nominatim
 *  happily returns a shop in Singapore literally named "Coffee Near Me". */
const OSM_TAGS: [RegExp, string][] = [
  [/\b(coffee|cafe|café|espresso|barista)\b/i, 'amenity=cafe'],
  [/\b(restaurant|food|dinner|lunch|eat)\b/i, 'amenity=restaurant'],
  [/\b(bar|pub|brewery|beer)\b/i, 'amenity=bar'],
  [/\b(atm|cash)\b/i, 'amenity=atm'],
  [/\b(bank)\b/i, 'amenity=bank'],
  [/\b(pharmacy|chemist|medical store)\b/i, 'amenity=pharmacy'],
  [/\b(hospital|clinic|doctor)\b/i, 'amenity=hospital'],
  [/\b(petrol|gas station|fuel|diesel)\b/i, 'amenity=fuel'],
  [/\b(hotel|stay|lodge)\b/i, 'tourism=hotel'],
  [/\b(gym|fitness)\b/i, 'leisure=fitness_centre'],
  [/\b(park|garden)\b/i, 'leisure=park'],
  [/\b(supermarket|grocery|groceries)\b/i, 'shop=supermarket'],
  [/\b(bakery|bread)\b/i, 'shop=bakery'],
  [/\b(salon|barber|haircut)\b/i, 'shop=hairdresser'],
  [/\b(school)\b/i, 'amenity=school'],
  [/\b(parking)\b/i, 'amenity=parking'],
];

const NEARBY = /\b(near|around|close to)\s+(me|here|by)\b|\bnearby\b|\bnear me\b/i;

export interface PlaceQuery {
  /** What to look for: "biryani", "atm", or the whole name for a named place. */
  what: string;
  /** An area named in the query: "indiranagar" in "biryani near indiranagar". */
  where?: string;
  /** Asked for what is around the caller: "near me", "nearest". */
  nearby: boolean;
}

/** OSM searches match names, so "best biryani near indiranagar" has to be
 *  taken apart first: find Indiranagar, then look for biryani around it.
 *  A plain name ("Times Square Starbucks") comes back as it was. */
export function placeQuery(q: string): PlaceQuery {
  const raw = q.trim().replace(/\s+/g, " ");
  const nearby = NEARBY.test(raw) || /\b(nearest|closest)\b/i.test(raw);
  let t = raw.replace(NEARBY, " ").replace(/\b(nearest|closest)\b/gi, " ").replace(/\s+/g, " ").trim();
  let where: string | undefined;
  const m = t.match(/^(.+?)\s+(?:near|in|around|close to)\s+(.+)$/i);
  if (m && !/^(me|here|by)$/i.test(m[2].trim())) {
    t = m[1];
    where = m[2].replace(/[?.!]+$/, "").trim();
  }
  if (!where && !nearby) return { what: raw, nearby: false };
  const what = t
    .replace(/\b(best|top|good|great|nice|cheap|cheapest|popular|famous|recommended|must[- ]try|some|any|decent|the|a|an)\b/gi, " ")
    .replace(/\b(places?|spots?|options?|joints?)\b(?=.)/gi, " ")
    .replace(/[?.!]+$/, "")
    .replace(/\s+/g, " ").trim();
  return { what: what || t.trim() || raw, where, nearby };
}

/** Opt-in: the public Overpass instance regularly takes 13s and then returns
 *  a timeout remark, which is worse than no result inside a keyboard. Set
 *  OVERPASS_API_BASE to a instance you control to turn nearby-by-category on
 *  for the keyless path; with a Places key this never runs. */
async function overpassNearby(
  q: string, lat: number, lon: number,
): Promise<PlaceCard[]> {
  const base = process.env.OVERPASS_API_BASE;
  if (!base) return [];
  const tag = OSM_TAGS.find(([re]) => re.test(q))?.[1];
  if (!tag) return [];
  const [k, v] = tag.split("=");
  const query = `[out:json][timeout:5];`
    + `nwr(around:2000,${lat},${lon})["${k}"="${v}"]["name"];`
    + `out center 25;`;
  const res = await fetch(base.replace(/\/$/, ""), {
    method: "POST",
    signal: AbortSignal.timeout(6000),
    headers: { "User-Agent": UA, "content-type": "application/x-www-form-urlencoded" },
    body: `data=${encodeURIComponent(query)}`,
  });
  if (!res.ok) throw new Error(`overpass ${res.status}`);
  const data = await res.json() as {
    elements?: {
      id?: number; lat?: number; lon?: number;
      center?: { lat: number; lon: number };
      tags?: Record<string, string>;
    }[];
  };
  return (data.elements ?? [])
    .flatMap(e => {
      const name = e.tags?.name;
      const pLat = e.lat ?? e.center?.lat, pLon = e.lon ?? e.center?.lon;
      if (!name || pLat === undefined || pLon === undefined) return [];
      const address = [e.tags?.["addr:housenumber"], e.tags?.["addr:street"],
        e.tags?.["addr:suburb"], e.tags?.["addr:city"]].filter(Boolean).join(", ");
      return [{
        card: {
          kind: "place" as const,
          id: `osm-${e.id ?? name}`,
          title: name,
          address: address || undefined,
          lat: pLat, lon: pLon,
          distance: formatDistance(haversine(lat, lon, pLat, pLon)),
          url: mapsURL(`${name} ${address}`.trim()),
          emoji: "📍",
          extra: address || undefined,
        },
        metres: haversine(lat, lon, pLat, pLon),
      }];
    })
    .sort((a, b) => a.metres - b.metres)
    .slice(0, 6)
    .map(x => x.card);
}

/** OSM's usage policy caps the public Nominatim at ONE request per second and
 *  forbids systematic/auto-complete querying. We only ever query on an
 *  explicit submit, but many users share this server's IP — so serialise to
 *  stay inside the policy rather than get the whole backend blocked.
 *  This is a development-grade fallback; production wants a Places key. */
let nominatimGate: Promise<void> = Promise.resolve();
function nominatimSlot(): Promise<void> {
  const wait = nominatimGate;
  nominatimGate = wait.then(() => new Promise(r => setTimeout(r, 1100)));
  return wait;
}

interface NominatimPlace {
  display_name: string; name?: string; lat: string; lon: string;
  address?: Record<string, string>;
  /** [south, north, west, east] */
  boundingbox?: string[];
}

/** How much of what was asked for is in a place's own name. A shop inside
 *  "Phoenix Marketcity" has the mall in its address, not in its name. */
export function nameMatch(name: string, what: string): number {
  const words = what.toLowerCase().split(/[^\p{L}\p{N}]+/u).filter(w => w.length > 1);
  if (words.length === 0) return 0;
  const n = name.toLowerCase();
  return words.filter(w => n.includes(w.replace(/s$/, ""))).length / words.length;
}

/** "SBI ATM, HAL Old Airport Road, NR Colony, …, Karnataka, 560075, India" is
 *  what OSM calls an address. A person would write "HAL Old Airport Road,
 *  Kodihalli, Bengaluru 560075". */
export function shortAddress(p: NominatimPlace): string {
  const a = p.address;
  if (!a) return p.display_name.split(",").slice(1, 4).join(",").trim();
  const street = [a.house_number, a.road].filter(Boolean).join(" ");
  const area = a.neighbourhood ?? a.suburb ?? a.quarter ?? a.city_district;
  const city = a.city ?? a.town ?? a.village ?? a.county;
  const parts = [street, area, [city, a.postcode].filter(Boolean).join(" ")]
    .map(x => x?.trim()).filter((x): x is string => !!x);
  return [...new Set(parts)].join(", ");
}

async function nominatimSearch(params: URLSearchParams): Promise<NominatimPlace[]> {
  await nominatimSlot();
  return json(`https://nominatim.openstreetmap.org/search?${params}`, 8000);
}

async function nominatimPlaces(q: string, ctx: SearchContext): Promise<PlaceCard[]> {
  const here = ctx.lat !== undefined && ctx.lon !== undefined;
  const pq = placeQuery(q);
  // "near me" is an instruction to us, not part of the name to match.
  let term = pq.where || pq.nearby ? pq.what : q.replace(NEARBY, " ").replace(/\s+/g, " ").trim() || q;

  if (here && pq.nearby && !pq.where) {
    const near = await overpassNearby(term, ctx.lat!, ctx.lon!).catch(() => []);
    if (near.length) return near;
  }
  // Nominatim matches names, but it also knows OSM's categories by their
  // own words: "coffee" finds nothing near Bandra, "cafe" finds its cafes.
  if (pq.nearby || pq.where) {
    const tag = OSM_TAGS.find(([re]) => re.test(term))?.[1];
    if (tag) term = tag.split("=")[1].replace(/_/g, " ");
  }

  // The point to search around, and how tightly (degrees).
  let center = here ? { lat: ctx.lat!, lon: ctx.lon! } : undefined;
  let d = pq.nearby ? 0.05 : 0.6;
  let bounded = pq.nearby;
  if (pq.where) {
    const area = new URLSearchParams({ format: "jsonv2", limit: "1", q: pq.where });
    if (here) {
      area.set("viewbox", `${ctx.lon! - 1},${ctx.lat! + 1},${ctx.lon! + 1},${ctx.lat! - 1}`);
    }
    const spot = (await nominatimSearch(area).catch(() => []))[0];
    if (spot) {
      center = { lat: Number(spot.lat), lon: Number(spot.lon) };
      // A neighbourhood is searched tightly, a city or a state across itself.
      const [south, north, west, east] = (spot.boundingbox ?? []).map(Number);
      const span = Number.isFinite(south + north + west + east)
        ? Math.max(north - south, east - west) / 2 : 0;
      d = Math.min(0.6, Math.max(0.03, span));
      bounded = true;
    } else {
      term = q;
    }
  }

  const params = new URLSearchParams({
    format: "jsonv2", limit: "8", q: term, addressdetails: "1",
  });
  if (center) {
    // Bounded when the caller asked for somewhere, a soft nudge otherwise.
    params.set("viewbox", `${center.lon - d},${center.lat + d},${center.lon + d},${center.lat - d}`);
    if (bounded) params.set("bounded", "1");
  }
  let data = await nominatimSearch(params);
  // "Phoenix Marketcity Bangalore": OSM spells the city Bengaluru, so only a
  // shop with the mall in its address matched. Try again without the city.
  const words = term.split(" ");
  if (!pq.where && !pq.nearby && words.length >= 3 && !data.some(p => nameMatch(p.name ?? "", term) >= 0.5)) {
    params.set("q", words.slice(0, -1).join(" "));
    const retry = await nominatimSearch(params).catch(() => []);
    if (retry.some(p => nameMatch(p.name ?? "", term) >= 0.5)) data = [...retry, ...data];
  }

  const rows = data.map(p => {
    const lat = Number(p.lat), lon = Number(p.lon);
    const name = p.name?.trim() || p.display_name.split(",")[0].trim();
    const address = shortAddress(p);
    return {
      metres: center ? haversine(center.lat, center.lon, lat, lon) : 0,
      card: {
        kind: "place" as const,
        id: `osm-${lat},${lon}`,
        title: name,
        address,
        lat, lon,
        // Distance is from the caller, even when the search was around an area.
        distance: here ? formatDistance(haversine(ctx.lat!, ctx.lon!, lat, lon)) : undefined,
        url: mapsURL(`${name} ${address}`.trim()),
        emoji: "📍",
        extra: address,
      },
    };
  });
  // A mall or landmark OSM only knows as part of its shops' addresses
  // ("Starbucks, Phoenix Marketcity Bangalore, Whitefield Main Road"): the
  // place asked for is that address, so offer it by its own name.
  if (!pq.where && !pq.nearby && rows.length && !rows.some(r => nameMatch(r.card.title, term) >= 0.5)) {
    const phrase = term.toLowerCase();
    const host = data.find(p => p.display_name.toLowerCase().includes(phrase));
    if (host) {
      const at = host.display_name.toLowerCase().indexOf(phrase);
      const title = host.display_name.slice(at, at + term.length);
      const address = host.display_name.slice(at + term.length).split(",")
        .map(x => x.trim()).filter(Boolean).slice(0, 3).join(", ");
      const lat = Number(host.lat), lon = Number(host.lon);
      rows.unshift({
        metres: center ? haversine(center.lat, center.lon, lat, lon) : 0,
        card: {
          kind: "place" as const, id: `osm-host-${lat},${lon}`, title, address, lat, lon,
          distance: here ? formatDistance(haversine(ctx.lat!, ctx.lon!, lat, lon)) : undefined,
          url: mapsURL(`${title} ${address}`.trim()), emoji: "📍", extra: address,
        },
      });
    }
  }

  // The place that is called what was asked for first, then the closest.
  const what = pq.where || pq.nearby ? pq.what : term;
  rows.sort((a, b) => nameMatch(b.card.title, what) - nameMatch(a.card.title, what)
    || (center ? a.metres - b.metres : 0));
  return rows.slice(0, 6).map(r => r.card);
}

async function searchMaps(q: string, ctx: SearchContext): Promise<SearchResponse> {
  let cards: PlaceCard[] = [];
  let provider = "openstreetmap";
  try {
    cards = await googlePlaces(q, ctx);
    if (cards.length) provider = "google-places";
  } catch { /* fall through */ }
  if (!cards.length) {
    try {
      cards = await geoapifyPlaces(q, ctx);
      if (cards.length) provider = "geoapify";
    } catch { /* fall through */ }
  }
  // OSM's usage policy makes Nominatim unshippable as a production path
  // (1 req/s for the entire server). It stays as a development convenience.
  if (!cards.length && process.env.NODE_ENV !== "production") {
    cards = await nominatimPlaces(q, ctx).catch(() => []);
  }
  const tail: LinkCard = {
    kind: "link", id: "tail",
    title: `See “${q}” on Maps`,
    url: mapsURL(q), domain: "google.com",
  };
  return { vertical: "maps", query: q, cards: [...cards, tail], provider };
}

// ── entry point ───────────────────────────────────────────────────────────

/** Fixed cards for MOCK_AI runs: one of every kind, so the UI tests exercise
 *  the real renderers without depending on an upstream or a network. */
function mockSearch(vertical: Vertical, q: string): SearchResponse {
  const cards: SearchCard[] = vertical === "yt" ? [
    {
      kind: "video", id: "mock-v1", videoId: "jfKfPfyJRdk",
      title: "lofi hip hop radio — beats to relax/study to",
      channel: "Lofi Girl", live: true, emoji: "🎥",
      url: "https://youtu.be/jfKfPfyJRdk",
    },
    {
      kind: "video", id: "mock-v2", videoId: "n61ULEU7CO0",
      title: "Midnight Drive — synthwave mix",
      channel: "Nightride FM", duration: "1:02:14", emoji: "🎥",
      url: "https://youtu.be/n61ULEU7CO0",
    },
  ] : vertical === "maps" ? [
    {
      kind: "place", id: "mock-p1", title: "Blue Tokai Coffee",
      address: "45 Church St, Bengaluru", distance: "350 m",
      openNow: true, rating: 4.5, ratingCount: 1203, emoji: "📍",
      extra: "45 Church St, Bengaluru",
      url: "https://www.google.com/maps/search/?api=1&query=Blue+Tokai+Coffee",
    },
    {
      kind: "place", id: "mock-p2", title: "Third Wave Coffee",
      address: "12 Indiranagar, Bengaluru", distance: "600 m",
      rating: 4.6, emoji: "📍", extra: "12 Indiranagar, Bengaluru",
      url: "https://www.google.com/maps/search/?api=1&query=Third+Wave+Coffee",
    },
  ] : [
    {
      kind: "answer", id: "mock-a1", art: "sun", title: "Sunset",
      value: "6:13 PM", sub: "Sunset · today", url: googleSearchURL(q),
    },
    {
      kind: "link", id: "mock-l1", title: "Golden hour begins 5:41 PM",
      domain: "timeanddate.com", url: "https://timeanddate.com/sun",
    },
  ];
  return { vertical, query: q, cards, provider: "mock" };
}

export async function search(
  vertical: Vertical, query: string, ctx: SearchContext = {},
): Promise<SearchResponse> {
  const q = query.trim();
  if (!q) throw new Error("needs a search");
  if (process.env.MOCK_AI === "true") return mockSearch(vertical, q);
  const key = TTLCache.key([
    vertical, q.toLowerCase(),
    ctx.lat !== undefined ? ctx.lat.toFixed(2) : "", // ~1km buckets
    ctx.lon !== undefined ? ctx.lon.toFixed(2) : "",
    ctx.country ?? "",
  ]);
  const hit = cache.get(key);
  if (hit) return JSON.parse(hit) as SearchResponse;

  const out = vertical === "yt" ? await searchYouTube(q, ctx)
    : vertical === "maps" ? await searchMaps(q, ctx)
    : await searchWeb(q, ctx);
  // Brave's terms allow only "transient storage required for operation" —
  // no result cache. Every other provider we use permits a short one.
  if (out.provider !== "brave") cache.set(key, JSON.stringify(out));
  return out;
}

/** What is physically around the caller — the Maps tab's landing state.
 *
 *  Places' Nearby Search is the only provider here: it is the one that knows
 *  a café is open right now and what people rate it, and the keyless
 *  alternatives established elsewhere in this file are either forbidden for
 *  this shape of query (Nominatim) or too slow to sit in a keyboard
 *  (Overpass). With no key the tab simply waits for a typed query.
 */
export async function searchNearby(
  lat: number, lon: number, country?: string,
): Promise<PlaceCard[]> {
  const key = process.env.GOOGLE_PLACES_KEY;
  if (!key) {
    // Geoapify has no "everything around me" call, so ask for the couple of
    // categories people actually open a map for and merge by distance.
    const ctx: SearchContext = { lat, lon, country };
    const sets = await Promise.all([
      geoapifyPlaces("cafe near me", ctx).catch(() => []),
      geoapifyPlaces("restaurant near me", ctx).catch(() => []),
    ]);
    return sets.flat()
      .filter(p => p.lat !== undefined && p.lon !== undefined)
      .sort((a, b) =>
        haversine(lat, lon, a.lat!, a.lon!) - haversine(lat, lon, b.lat!, b.lon!))
      .slice(0, 8);
  }
  const res = await fetch("https://places.googleapis.com/v1/places:searchNearby", {
    method: "POST",
    signal: AbortSignal.timeout(7000),
    headers: {
      "content-type": "application/json",
      "X-Goog-Api-Key": key,
      "X-Goog-FieldMask": [
        "places.id", "places.displayName", "places.formattedAddress",
        "places.rating", "places.userRatingCount",
        "places.currentOpeningHours.openNow", "places.location",
        "places.photos.name", "places.googleMapsUri",
      ].join(","),
    },
    body: JSON.stringify({
      includedTypes: ["restaurant", "cafe", "supermarket", "pharmacy", "park"],
      maxResultCount: 8,
      rankPreference: "DISTANCE",
      ...(country ? { regionCode: country } : {}),
      locationRestriction: {
        circle: { center: { latitude: lat, longitude: lon }, radius: 2000 },
      },
    }),
  });
  if (!res.ok) throw new Error(`nearby ${res.status}`);
  const data = await res.json() as {
    places?: {
      id?: string; displayName?: { text?: string }; formattedAddress?: string;
      rating?: number; userRatingCount?: number;
      currentOpeningHours?: { openNow?: boolean };
      location?: { latitude?: number; longitude?: number };
      photos?: { name?: string }[]; googleMapsUri?: string;
    }[];
  };
  return (data.places ?? []).flatMap(p => {
    const name = p.displayName?.text;
    if (!name) return [];
    const pLat = p.location?.latitude, pLon = p.location?.longitude;
    const photo = p.photos?.[0]?.name;
    return [{
      kind: "place" as const,
      id: p.id ?? name,
      title: name,
      address: p.formattedAddress,
      rating: p.rating,
      ratingCount: p.userRatingCount,
      openNow: p.currentOpeningHours?.openNow,
      lat: pLat, lon: pLon,
      distance: pLat !== undefined && pLon !== undefined
        ? formatDistance(haversine(lat, lon, pLat, pLon)) : undefined,
      thumb: photo ? `/search/photo?ref=${encodeURIComponent(photo)}` : undefined,
      url: p.googleMapsUri ?? mapsURL(name, p.id),
      emoji: "📍",
      extra: p.formattedAddress,
    }];
  });
}

/** Which verticals are running on a real key — surfaced by /search/status so
 *  the app can tell the user what is configured without exposing the keys. */
export function searchProviders(): Record<Vertical, string> {
  return {
    web: process.env.BRAVE_SEARCH_KEY ? "brave"
      : process.env.SERPER_API_KEY ? "google"
      : "answers-only",
    yt: process.env.YOUTUBE_API_KEY ? "youtube-data-api" : "none",
    maps: process.env.GOOGLE_PLACES_KEY ? "google-places"
      : process.env.GEOAPIFY_KEY ? "geoapify"
      : process.env.NODE_ENV !== "production" ? "openstreetmap-dev" : "none",
  };
}

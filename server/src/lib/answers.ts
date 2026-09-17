import type { AnswerCard } from "./searchcards.js";
import { clockIn, sunTimes } from "./sun.js";

/** Gboard's web tab leads with an answer, not a link — sunset time, today's
 *  temperature, a calculation, a definition. This module produces that card.
 *
 *  Ordered cheapest-first. Arithmetic, sunset and the local clock are COMPUTED
 *  here: no key, no network, no upstream licence, and an answer before the
 *  search request would even have left the device. The rest use keyless public
 *  APIs, and weather uses the same Google Maps Platform key as Places.
 *  A detector returning null just means the tab leads with links instead.
 */

const UA = "glyf/0.6 (+https://tryglyf.com)";

async function json<T>(url: string, timeoutMs = 4500): Promise<T> {
  const res = await fetch(url, {
    signal: AbortSignal.timeout(timeoutMs),
    headers: { "User-Agent": UA, accept: "application/json" },
  });
  if (!res.ok) throw new Error(`upstream ${res.status}`);
  return res.json() as Promise<T>;
}

export interface AnswerContext {
  lat?: number;
  lon?: number;
  /** IANA zone for the caller, when the client knows it. */
  tz?: string;
}

// ── arithmetic ────────────────────────────────────────────────────────────
// A real parser, not eval(): the query string reaches this code straight
// from a keyboard, so it must never be executed.

/** Recursive-descent over + - * / % ^ and parentheses. Returns null on any
 *  character it does not recognise, which is how non-math queries opt out. */
export function evaluateMath(input: string): number | null {
  const src = input.replace(/[,\s]/g, "").replace(/×/g, "*").replace(/÷/g, "/");
  if (!/^[0-9.+\-*/%^()]+$/.test(src) || !/[0-9]/.test(src)) return null;
  // A bare number is not a calculation worth a card.
  if (/^-?[0-9.]+$/.test(src)) return null;

  let i = 0;
  const peek = () => src[i];
  const eat = (c: string) => { if (src[i] === c) { i++; return true; } return false; };

  function expr(): number | null {           // + -
    let left = term();
    if (left === null) return null;
    for (;;) {
      if (eat("+")) { const r = term(); if (r === null) return null; left += r; }
      else if (eat("-")) { const r = term(); if (r === null) return null; left -= r; }
      else return left;
    }
  }
  function term(): number | null {           // * / %
    let left = power();
    if (left === null) return null;
    for (;;) {
      if (eat("*")) { const r = power(); if (r === null) return null; left *= r; }
      else if (eat("/")) {
        const r = power();
        if (r === null || r === 0) return null;
        left /= r;
      } else if (eat("%")) { const r = power(); if (r === null || r === 0) return null; left %= r; }
      else return left;
    }
  }
  function power(): number | null {          // ^ (right-associative)
    const base = unary();
    if (base === null) return null;
    if (eat("^")) {
      const exp = power();
      if (exp === null) return null;
      return base ** exp;
    }
    return base;
  }
  function unary(): number | null {
    if (eat("-")) { const v = unary(); return v === null ? null : -v; }
    if (eat("+")) return unary();
    return atom();
  }
  function atom(): number | null {
    if (eat("(")) {
      const v = expr();
      if (v === null || !eat(")")) return null;
      return v;
    }
    const start = i;
    while (i < src.length && /[0-9.]/.test(src[i])) i++;
    if (i === start) return null;
    const n = Number(src.slice(start, i));
    return Number.isFinite(n) ? n : null;
  }

  const value = expr();
  if (value === null || i !== src.length || !Number.isFinite(value)) return null;
  return value;
}

function tidyNumber(n: number): string {
  const rounded = Math.round(n * 1e6) / 1e6;
  return rounded.toLocaleString("en-US", { maximumFractionDigits: 6 });
}

function mathAnswer(q: string): AnswerCard | null {
  // "15% of 200" — the one natural-language form worth special-casing.
  const pct = q.match(/^([\d.]+)\s*%\s*of\s*([\d,.]+)$/i);
  if (pct) {
    const value = (Number(pct[1]) / 100) * Number(pct[2].replace(/,/g, ""));
    if (Number.isFinite(value)) {
      return {
        kind: "answer", id: "calc", art: "calc",
        title: q, value: tidyNumber(value), sub: `${pct[1]}% of ${pct[2]}`,
        say: `${pct[1]}% of ${pct[2]} is ${tidyNumber(value)}`,
        url: `https://www.google.com/search?q=${encodeURIComponent(q)}`,
      };
    }
  }
  const value = evaluateMath(q);
  if (value === null) return null;
  return {
    kind: "answer", id: "calc", art: "calc",
    title: q, value: tidyNumber(value), sub: q.replace(/\s+/g, " ").trim(),
    say: `${q.replace(/\s+/g, " ").trim()} = ${tidyNumber(value)}`,
    url: `https://www.google.com/search?q=${encodeURIComponent(q)}`,
  };
}

// ── sun ───────────────────────────────────────────────────────────────────

/** Computed on the spot from the caller's coordinates — no API, no key, no
 *  licence, no latency. A named place ("sunset in Paris") needs a geocoder we
 *  deliberately do not have, so it falls through to the web provider's own
 *  answer box instead. */
/** Where a time zone's clocks are set from, for a caller who has not shared
 *  a location: the zone's own city (or its capital, where one zone covers a
 *  whole country). The card names the city, so nobody mistakes it for theirs. */
const ZONE_CITIES: Record<string, [number, number, string]> = {
  "Asia/Kolkata": [28.6139, 77.209, "New Delhi"],
  "Asia/Calcutta": [28.6139, 77.209, "New Delhi"],
  "Asia/Dubai": [25.2048, 55.2708, "Dubai"],
  "Asia/Singapore": [1.3521, 103.8198, "Singapore"],
  "Asia/Tokyo": [35.6762, 139.6503, "Tokyo"],
  "Asia/Shanghai": [31.2304, 121.4737, "Shanghai"],
  "Asia/Hong_Kong": [22.3193, 114.1694, "Hong Kong"],
  "Asia/Seoul": [37.5665, 126.978, "Seoul"],
  "Asia/Jakarta": [-6.2088, 106.8456, "Jakarta"],
  "Asia/Bangkok": [13.7563, 100.5018, "Bangkok"],
  "Asia/Karachi": [24.8607, 67.0011, "Karachi"],
  "Asia/Dhaka": [23.8103, 90.4125, "Dhaka"],
  "Asia/Kathmandu": [27.7172, 85.324, "Kathmandu"],
  "Asia/Colombo": [6.9271, 79.8612, "Colombo"],
  "Asia/Manila": [14.5995, 120.9842, "Manila"],
  "Asia/Riyadh": [24.7136, 46.6753, "Riyadh"],
  "Europe/London": [51.5072, -0.1276, "London"],
  "Europe/Paris": [48.8566, 2.3522, "Paris"],
  "Europe/Berlin": [52.52, 13.405, "Berlin"],
  "Europe/Madrid": [40.4168, -3.7038, "Madrid"],
  "Europe/Rome": [41.9028, 12.4964, "Rome"],
  "Europe/Amsterdam": [52.3676, 4.9041, "Amsterdam"],
  "Europe/Dublin": [53.3498, -6.2603, "Dublin"],
  "Europe/Lisbon": [38.7223, -9.1393, "Lisbon"],
  "Europe/Moscow": [55.7558, 37.6173, "Moscow"],
  "Europe/Istanbul": [41.0082, 28.9784, "Istanbul"],
  "Africa/Lagos": [6.5244, 3.3792, "Lagos"],
  "Africa/Nairobi": [-1.2921, 36.8219, "Nairobi"],
  "Africa/Cairo": [30.0444, 31.2357, "Cairo"],
  "Africa/Johannesburg": [-26.2041, 28.0473, "Johannesburg"],
  "America/New_York": [40.7128, -74.006, "New York"],
  "America/Chicago": [41.8781, -87.6298, "Chicago"],
  "America/Denver": [39.7392, -104.9903, "Denver"],
  "America/Los_Angeles": [34.0522, -118.2437, "Los Angeles"],
  "America/Toronto": [43.6532, -79.3832, "Toronto"],
  "America/Vancouver": [49.2827, -123.1207, "Vancouver"],
  "America/Mexico_City": [19.4326, -99.1332, "Mexico City"],
  "America/Sao_Paulo": [-23.5505, -46.6333, "São Paulo"],
  "America/Bogota": [4.711, -74.0721, "Bogotá"],
  "America/Argentina/Buenos_Aires": [-34.6037, -58.3816, "Buenos Aires"],
  "Australia/Sydney": [-33.8688, 151.2093, "Sydney"],
  "Australia/Melbourne": [-37.8136, 144.9631, "Melbourne"],
  "Pacific/Auckland": [-36.8485, 174.7633, "Auckland"],
};

function sunAnswer(q: string, ctx: AnswerContext): AnswerCard | null {
  if (!/\bsun\s?(set|rise)\b|\bgolden hour\b/i.test(q)) return null;
  // A place named in the query is not necessarily where the caller is.
  if (/\b(?:in|at)\s+[a-zÀ-ɏ]/i.test(q)) return null;
  let lat = ctx.lat, lon = ctx.lon, city: string | null = null;
  if (lat === undefined || lon === undefined) {
    const zone = ctx.tz ? ZONE_CITIES[ctx.tz] : undefined;
    if (!zone) return null;
    [lat, lon, city] = zone;
  }

  const times = sunTimes(lat, lon);
  const golden = /golden hour/i.test(q);
  const rise = /sun\s?rise/i.test(q);

  if (times.polar) {
    return {
      kind: "answer", id: "sun", art: "sun",
      title: times.polar === "day" ? "Midnight sun" : "Polar night",
      value: times.polar === "day" ? "No sunset" : "No sunrise",
      sub: "The sun stays "
        + (times.polar === "day" ? "up all day here" : "down all day here"),
      url: googleQ(q),
    };
  }
  const when = golden ? times.goldenHour : rise ? times.sunrise : times.sunset;
  if (!when) return null;
  const label = golden ? "Golden hour" : rise ? "Sunrise" : "Sunset";
  const clock = clockIn(when, ctx.tz);
  const place = city ? ` in ${city}` : "";
  return {
    kind: "answer", id: rise ? "sunrise" : "sunset", art: "sun",
    title: label,
    say: golden ? `Golden hour${place} starts at ${clock} ✨`
      : rise ? `Sunrise${place} is at ${clock} 🌅` : `Sunset${place} is at ${clock} 🌇`,
    value: clock,
    sub: city ? `${label} in ${city} · today` : `${label} · today`,
    url: googleQ(q),
  };
}

function googleQ(q: string): string {
  return `https://www.google.com/search?q=${encodeURIComponent(q)}`;
}

// ── weather ───────────────────────────────────────────────────────────────

const WEATHER_WORDS: Record<string, string> = {
  CLEAR: "Clear", MOSTLY_CLEAR: "Mostly clear", PARTLY_CLOUDY: "Partly cloudy",
  MOSTLY_CLOUDY: "Mostly cloudy", CLOUDY: "Cloudy", RAIN: "Rain",
  LIGHT_RAIN: "Light rain", HEAVY_RAIN: "Heavy rain", SNOW: "Snow",
  THUNDERSTORM: "Thunderstorm", FOG: "Fog", WIND: "Windy",
};

/** Google's Weather API — same Maps Platform key as Places, 10k calls free a
 *  month. Without a key the weather card is simply absent; the web provider's
 *  own answer box usually covers it. */
async function weatherAnswer(q: string, ctx: AnswerContext): Promise<AnswerCard | null> {
  if (!/\bweather\b|\btemperature\b|how (hot|cold)\b|\braining\b/i.test(q)) return null;
  if (ctx.lat === undefined || ctx.lon === undefined) return null;
  if (/\b(?:in|at)\s+[a-zÀ-ɏ]/i.test(q)) return null;
  const key = process.env.GOOGLE_WEATHER_KEY || process.env.GOOGLE_PLACES_KEY;
  if (!key) return null;

  const data = await json<{
    temperature?: { degrees?: number };
    feelsLikeTemperature?: { degrees?: number };
    weatherCondition?: { type?: string; description?: { text?: string } };
  }>("https://weather.googleapis.com/v1/currentConditions:lookup?" + new URLSearchParams({
    key, "location.latitude": String(ctx.lat), "location.longitude": String(ctx.lon),
    unitsSystem: "METRIC",
  })).catch(() => null);

  const t = data?.temperature?.degrees;
  if (t === undefined) return null;
  const type = data?.weatherCondition?.type ?? "";
  const word = data?.weatherCondition?.description?.text
    ?? WEATHER_WORDS[type] ?? "Now";
  const feels = data?.feelsLikeTemperature?.degrees;
  return {
    kind: "answer", id: "weather", art: "weather",
    title: "Weather",
    say: `It's ${Math.round(t)}°${word === "Now" ? "" : ` and ${word.toLowerCase()}`} right now`,
    value: `${Math.round(t)}°`,
    sub: `${word}${feels !== undefined ? ` · feels ${Math.round(feels)}°` : ""}`,
    url: googleQ(q),
  };
}

/** Only the caller's own clock. "Time in Tokyo" needs a place lookup we do
 *  not do here — the web provider answers that one. */
function timeAnswer(q: string, ctx: AnswerContext): AnswerCard | null {
  if (!/^(what('s| is)? the )?time\b|^current time\b/i.test(q)) return null;
  if (/\b(?:in|at)\s+[a-zÀ-ɏ]/i.test(q)) return null;
  const tz = ctx.tz;
  if (!tz) return null;
  let value: string, day: string;
  try {
    value = new Intl.DateTimeFormat("en-US", { timeStyle: "short", timeZone: tz }).format(new Date());
    day = new Intl.DateTimeFormat("en-US", { weekday: "long", timeZone: tz }).format(new Date());
  } catch { return null; }
  return {
    kind: "answer", id: "time", art: "none",
    title: "Time", value, sub: day, url: googleQ(q), say: `It's ${value}`,
  };
}

async function currencyAnswer(q: string): Promise<AnswerCard | null> {
  const m = q.match(/^([\d,.]+)\s*([a-z]{3})\s*(?:in|to|=)\s*([a-z]{3})$/i);
  if (!m) return null;
  const amount = Number(m[1].replace(/,/g, ""));
  const from = m[2].toUpperCase(), to = m[3].toUpperCase();
  if (!Number.isFinite(amount)) return null;
  const data = await json<{ rates?: Record<string, number> }>(
    `https://api.frankfurter.dev/v1/latest?amount=${amount}&from=${from}&to=${to}`).catch(() => null);
  const value = data?.rates?.[to];
  if (value === undefined) return null;
  return {
    kind: "answer", id: "fx", art: "calc",
    title: `${amount} ${from} to ${to}`,
    say: `${tidyNumber(amount)} ${from} is ${tidyNumber(value)} ${to}`,
    value: `${tidyNumber(value)} ${to}`,
    sub: `${tidyNumber(amount)} ${from} · today's rate`,
    source: "frankfurter.app",
    url: `https://www.google.com/search?q=${encodeURIComponent(q)}`,
  };
}

/** Definitions come from Wikipedia's summary endpoint below rather than a
 *  dictionary API: the well-known free one (dictionaryapi.dev) is returning
 *  522s, and a dead upstream costs a real stall before the fallback runs.
 *  A configured web provider's own answer box covers proper definitions. */
async function wikiAnswer(q: string): Promise<AnswerCard | null> {
  const m = q.match(/^(?:what|who|where)\s+(?:is|was|are|were)\s+(?:an?\s+|the\s+)?(.+?)\??$/i);
  if (!m) return null;
  const topic = m[1].trim();
  if (topic.length < 2 || topic.length > 60) return null;
  const data = await json<{ title?: string; extract?: string; content_urls?: {
    desktop?: { page?: string } }; thumbnail?: { source?: string }; type?: string }>(
    `https://en.wikipedia.org/api/rest_v1/page/summary/${encodeURIComponent(topic)}`).catch(() => null);
  if (!data?.extract || data.type === "disambiguation") return null;
  return {
    kind: "answer", id: "wiki", art: "define",
    title: data.title ?? topic,
    value: data.title ?? topic,
    sub: data.extract.split(/(?<=\.)\s/)[0].slice(0, 200),
    source: "en.wikipedia.org",
    url: data.content_urls?.desktop?.page
      ?? `https://en.wikipedia.org/wiki/${encodeURIComponent(topic)}`,
  };
}

/** Runs the detectors in order of confidence and returns the first hit.
 *  Cheap string tests gate every network call, so a plain query like
 *  "best running shoes" costs nothing. */
export async function instantAnswer(
  query: string, ctx: AnswerContext = {},
): Promise<AnswerCard | null> {
  const q = query.trim().replace(/\s+/g, " ");
  if (!q) return null;
  // Local first: these cost nothing and cannot fail.
  for (const local of [mathAnswer(q), sunAnswer(q, ctx), timeAnswer(q, ctx)]) {
    if (local) return local;
  }
  const hitWeather = await weatherAnswer(q, ctx).catch(() => null);
  if (hitWeather) return hitWeather;
  for (const d of [currencyAnswer, wikiAnswer]) {
    const hit = await d(q).catch(() => null);
    if (hit) return hit;
  }
  return null;
}

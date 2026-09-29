import type { AnswerCard } from "./searchcards.js";
import { TTLCache } from "./cache.js";
import { Rates, type TokenQuote } from "./rates.js";
import { clockIn, sunTimes } from "./sun.js";
import { convertUnits } from "./units.js";

/** Gboard's web tab leads with an answer, not a link — sunset time, today's
 *  temperature, a calculation, a definition. This module produces that card.
 *
 *  Ordered cheapest-first. Arithmetic, sunset and the local clock are COMPUTED
 *  here: no key, no network, no upstream licence, and an answer before the
 *  search request would even have left the device. The rest use keyless public
 *  APIs: a named place and the weather come from Open-Meteo, money from the
 *  ECB's daily rates and Jupiter (lib/rates.ts).
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
  /** Two-letter region: which "Paris" is meant, °F or °C. */
  country?: string;
}

/** Live facts a model must not invent: they change faster than it knows.
 *  Both the web tab and /act hold this line, so it lives with the answers. */
export function isLive(text: string): boolean {
  return /\b(score|scores|fixture|fixtures|schedule|price|prices|stock|weather|forecast|news|today|tonight|tomorrow|yesterday|now|current|latest|live|exchange rates?|forex|sunset|sunrise|golden hour)\b/i
    .test(text) || moneyAsked(text) !== null || liveAsk(text) !== null;
}

/** Happening now, so nothing a model knows can answer it: today's score, the
 *  news, a live price, the weather. Everything else the AI answers from what
 *  it knows (2026-09-29): "who is the ceo of tesla" is Elon Musk, not a
 *  Google link. Narrower than `isLive`, which still guards the web tab's
 *  cache and the model's written messages. */
export function rightNow(text: string): boolean {
  return /\b(scores?|live|right now|today'?s?|tonight'?s?|this (?:morning|afternoon|evening|week)|yesterday'?s?|last night'?s?|news|headlines?|breaking|stock price|share price|trading at|exchange rates?|forex|forecast|weather)\b/i
    .test(text) || moneyAsked(text) !== null || liveAsk(text) !== null;
}

// ── what was asked: the time, the sun, the weather ────────────────────────

export type LiveKind = "time" | "sunset" | "sunrise" | "golden" | "weather" | "rain";

export interface LiveAsk {
  kind: LiveKind;
  /** A place named in the ask ("tokyo" in "time in tokyo"); absent means
   *  wherever the caller is. */
  place?: string;
  /** 0 for today (or now), 1 for tomorrow. */
  day: 0 | 1;
}

/** Words that make a "place" someone's own business, not somewhere on a
 *  map: "time in my life", "weather at your end". */
const NOT_A_PLACE = /\b(i|me|my|mine|we|us|our|you|u|your|ur|he|she|his|her|they|their|it|this|that|there|here|the day|life|world|general|between|is|was|are|were|be|been|looks?|seems?|feels?|sucks?|so|very|too|really|great|good|bad|nice|perfect|lovely|today|tomorrow)\b/;

/** Adjectives people put before "weather" when they are talking about it,
 *  not asking: "perfect weather", "crazy weather". */
const WEATHER_TALK = /^(nice|perfect|great|good|bad|lovely|crazy|beautiful|amazing|awful|terrible|horrible|weird|such|what|what a|this|that|the|hot|cold|rainy|sunny|cloudy|stormy|gloomy|pleasant|cool|warm|mad|insane|wild|shitty|shit|fine|decent|summer|winter|monsoon|spring|autumn|fall)$/;

/** Reads a question about the time, the sun or the weather, asked the way a
 *  search is ("sunset in paris", "will it rain tomorrow", "what time is it in
 *  tokyo"), and says which one and where. Null for anything else, including
 *  a message that merely mentions one ("caption for my sunset photo"). */
export function liveAsk(text: string): LiveAsk | null {
  let t = text.toLowerCase().replace(/[’‘`]/g, "'").replace(/\s+/g, " ").replace(/[?!.,\s]+$/, "").trim();
  if (!t || t.length > 80) return null;
  let day: 0 | 1 = 0;
  let place: string | undefined;
  const lead = t.match(/^(today'?s|tomorrow'?s|tmrw'?s)\s+/);
  if (lead) {
    if (lead[1].startsWith("tom") || lead[1].startsWith("tmrw")) day = 1;
    t = t.slice(lead[0].length);
  }
  // "weather in pune tomorrow" and "weather tomorrow in pune" alike.
  for (let i = 0; i < 3; i++) {
    const when = t.match(/\s+(today|tomorrow|tmrw|tmr|tonight|now|right now|rn|currently|this evening|this morning|at the moment)$/);
    if (when) {
      if (/^(tomorrow|tmrw|tmr)$/.test(when[1])) day = 1;
      t = t.slice(0, when.index).trim();
      continue;
    }
    const where = place === undefined ? t.match(/\s+(?:in|at|for)\s+([\p{L}][\p{L}\d .,'-]{0,40})$/u) : null;
    if (where && !/^(today|tomorrow|tonight|now|the moment)$/.test(where[1].trim())) {
      place = where[1].replace(/[.,\s]+$/, "").trim();
      t = t.slice(0, where.index).trim();
      continue;
    }
    break;
  }
  t = t.replace(/\s+for$/, "");

  let kind: LiveKind | null = null;
  if (/^(?:(?:what'?s|whats|what is)\s+)?(?:the\s+)?(?:current\s+|local\s+|exact\s+)?time(?:\s+is\s+it)?(?:\s+there)?$|^what\s+time\s+is\s+it(?:\s+there)?$/.test(t)) {
    kind = "time";
  } else {
    const sun = t.match(/^(?:(?:what\s+time\s+is|when\s+is|when'?s|whens|what'?s|whats|what\s+is)\s+)?(?:the\s+)?(sunset|sunrise|golden\s+hour)(?:\s+time)?$/)
      ?? t.match(/^(?:what\s+time|when)\s+(?:does|will|is)\s+(?:the\s+)?sun\s*(set|rise|setting|rising)$/);
    if (sun) {
      kind = /rise/.test(sun[1]) ? "sunrise" : /golden/.test(sun[1]) ? "golden" : "sunset";
    } else if (/^(?:(?:what'?s|whats|what\s+is|how'?s|hows|how\s+is)\s+)?(?:the\s+)?(?:current\s+)?(?:weather|forecast|temperature|temp|weather\s+forecast|weather\s+report)(?:\s+like)?(?:\s+(?:forecast|report|update))?$/.test(t)) {
      kind = "weather";
    } else if (/^(?:(?:will|is|does|would)\s+it\s+(?:going\s+to\s+|gonna\s+)?(?:rain|snow|raining|snowing|be\s+(?:hot|cold|sunny|cloudy|rainy|windy|humid|warm))|is\s+it\s+(?:hot|cold|warm|sunny|cloudy|windy|humid)|(?:any\s+)?(?:chance\s+of\s+)?(?:rain|snow)(?:\s+forecast)?|how\s+(?:hot|cold|warm|humid)\s+is\s+it)$/.test(t)) {
      kind = /rain|snow/.test(t) ? "rain" : "weather";
    } else if (place === undefined) {
      // "weather bangalore", "bangalore weather": the place without "in".
      const after = t.match(/^(?:weather|forecast|temperature)\s+([\p{L}][\p{L} .'-]{1,40})$/u);
      const before = t.match(/^([\p{L}][\p{L} .'-]{1,30}?)\s+(?:weather|forecast)$/u);
      if (after) { kind = "weather"; place = after[1].trim(); }
      else if (before && !WEATHER_TALK.test(before[1].trim())) { kind = "weather"; place = before[1].trim(); }
    }
  }
  if (!kind) return null;
  if (place !== undefined && (NOT_A_PLACE.test(place) || place.split(" ").length > 4)) return null;
  return place ? { kind, place, day } : { kind, day };
}

// ── where a named place is ────────────────────────────────────────────────

export interface Place {
  /** Absent for the caller's own location, which has no name to say. */
  name?: string;
  lat: number;
  lon: number;
  /** IANA zone of the place, when known. */
  tz?: string;
}

/** Regions the geocoder knows only by a town in them: said as asked. */
const REGION_NAMES: Record<string, string> = { goa: "Goa", ncr: "Delhi NCR" };

/** Names the geocoder only knows by their other spelling. */
const PLACE_ALIASES: Record<string, string> = {
  bangalore: "Bengaluru", blr: "Bengaluru", bombay: "Mumbai", madras: "Chennai", calcutta: "Kolkata",
  gurgaon: "Gurugram", poona: "Pune", mysore: "Mysuru", trivandrum: "Thiruvananthapuram", cochin: "Kochi",
  baroda: "Vadodara", pondicherry: "Puducherry", pondy: "Puducherry", benares: "Varanasi", banaras: "Varanasi",
  allahabad: "Prayagraj", mangalore: "Mangaluru", belgaum: "Belagavi", hubli: "Hubballi", goa: "Panjim",
  panaji: "Panjim", ncr: "New Delhi", peking: "Beijing", saigon: "Ho Chi Minh City",
  nyc: "New York", "new york city": "New York", sf: "San Francisco", "san fran": "San Francisco",
  la: "Los Angeles", vegas: "Las Vegas", dc: "Washington", "washington dc": "Washington",
  "washington d.c": "Washington", philly: "Philadelphia",
};

interface GeoHit {
  name: string; latitude: number; longitude: number; timezone?: string;
  country_code?: string; population?: number; feature_code?: string;
}

const places = new TTLCache(24 * 3600 * 1000, 500);

function fold(s: string): string {
  return s.normalize("NFD").replace(/\p{M}/gu, "").toLowerCase();
}

/** The place people mean by a name: the biggest one, a capital over a
 *  village, and the caller's own country when two are close. "Paris" is in
 *  France for someone in Texas; "Kochi" in Kerala for someone in India. */
export function pickPlace(name: string, hits: GeoHit[], country?: string): GeoHit | null {
  const want = fold(name);
  let best: GeoHit | null = null;
  let bestScore = -Infinity;
  for (const h of hits) {
    if (!Number.isFinite(h.latitude) || !Number.isFinite(h.longitude)) continue;
    const fc = h.feature_code ?? "";
    const score = Math.log10((h.population ?? 0) + 10)
      + (fc === "PPLC" ? 1.5 : fc === "PPLA" ? 1 : fc === "PPLA2" ? 0.5 : 0)
      + (country && h.country_code?.toUpperCase() === country.toUpperCase() ? 1 : 0)
      + (fold(h.name) === want ? 1 : 0);
    if (score > bestScore) { best = h; bestScore = score; }
  }
  return best;
}

/** A named place on the map, through Open-Meteo's keyless geocoder (the one
 *  the Weather glyf uses). Tries the name as typed, then the part before a
 *  comma ("indiranagar" of "indiranagar, bangalore"). Null when nothing fits. */
export async function geocodePlace(raw: string, country?: string): Promise<Place | null> {
  const name = raw.trim().replace(/\s+/g, " ");
  if (!name || name.length > 60) return null;
  const key = `${name.toLowerCase()}|${country ?? ""}`;
  const hit = places.get(key);
  if (hit !== undefined) return hit === "" ? null : JSON.parse(hit) as Place;
  const tries = [...new Set([name, name.split(/,/)[0].trim()].filter(s => s.length >= 2))];
  let found: Place | null = null;
  let answered = true;
  for (const t of tries) {
    const q = PLACE_ALIASES[t.toLowerCase()] ?? t;
    const data = await json<{ results?: GeoHit[] }>(
      `https://geocoding-api.open-meteo.com/v1/search?count=10&language=en&format=json&name=${encodeURIComponent(q)}`,
    ).catch(() => null);
    if (!data) answered = false;
    const best = pickPlace(q, data?.results ?? [], country);
    if (best) {
      found = { name: REGION_NAMES[t.toLowerCase()] ?? best.name, lat: best.latitude, lon: best.longitude, tz: best.timezone };
      break;
    }
  }
  // A miss is remembered only when the geocoder said so, not when it was down.
  if (found || answered) places.set(key, found ? JSON.stringify(found) : "");
  return found;
}

/** Where to answer for: the place named, else the caller (when their saved
 *  location fits their time zone), else their zone's own city. */
async function placeFor(named: string | undefined, ctx: AnswerContext): Promise<Place | null> {
  if (named) return geocodePlace(named, ctx.country);
  if (ctx.lat !== undefined && ctx.lon !== undefined && locationFitsZone(ctx.lon, ctx.tz)) {
    return { lat: ctx.lat, lon: ctx.lon, tz: ctx.tz };
  }
  const zone = ctx.tz ? ZONE_CITIES[ctx.tz] : undefined;
  return zone ? { name: zone[2], lat: zone[0], lon: zone[1], tz: ctx.tz } : null;
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
  // "15% tip on 64": the tip, and what that comes to.
  const tip = q.match(/^([\d.]+)\s*%\s*tip\s*(?:on|for|of)\s*([$€£₹]?)\s*([\d,.]+)$/i);
  if (tip) {
    const bill = Number(tip[3].replace(/,/g, ""));
    const value = (Number(tip[1]) / 100) * bill;
    if (Number.isFinite(value)) {
      const money = (n: number) => tip[2] + n.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
      return {
        kind: "answer", id: "calc", art: "calc",
        title: q, value: money(value), sub: `${money(bill + value)} in all`,
        say: `${tip[1]}% tip on ${tip[2]}${tip[3]} is ${money(value)} (${money(bill + value)} in all)`,
        url: `https://www.google.com/search?q=${encodeURIComponent(q)}`,
      };
    }
  }
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

// ── days until ────────────────────────────────────────────────────────────

/** Days everyone counts to, by month and day (Thanksgiving is worked out). */
const DAYS: Array<[RegExp, string, (year: number) => [number, number]]> = [
  [/^christmas eve$/, "Christmas Eve", () => [12, 24]],
  [/^(?:christmas|xmas|christmas day)$/, "Christmas", () => [12, 25]],
  [/^new year'?s eve$/, "New Year's Eve", () => [12, 31]],
  [/^(?:new year'?s?|new year'?s day|the new year)$/, "New Year's Day", () => [1, 1]],
  [/^halloween$/, "Halloween", () => [10, 31]],
  [/^valentine'?s(?: day)?$/, "Valentine's Day", () => [2, 14]],
  [/^(?:the )?(?:4th|fourth) of july$|^independence day$/, "the Fourth of July", () => [7, 4]],
  [/^thanksgiving$/, "Thanksgiving", year => {
    const first = new Date(Date.UTC(year, 10, 1)).getUTCDay();   // Nov 1st's weekday
    return [11, 1 + ((4 - first + 7) % 7) + 21];                  // the fourth Thursday
  }],
];
const MONTHS = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"];
const DAYS_ASK = /^(?:how\s+many\s+(days?|weeks?)\s+(?:are\s+)?(?:left\s+)?(?:until|till|til|to|before)|(days?|weeks?)\s+(?:left\s+)?(?:until|till|til|to)|how\s+long\s+(?:is\s+it\s+)?(?:until|till|til|to))\s+(.+?)\s*\??$/i;

/** The day asked about: [label, month, day, unit], or null. */
export function daysAsked(text: string): { label: string; month: number; day: number; weeks: boolean } | null {
  const m = text.trim().toLowerCase().replace(/[’‘]/g, "'").replace(/\s+/g, " ").match(DAYS_ASK);
  if (!m) return null;
  const weeks = /^weeks?$/.test(m[1] ?? m[2] ?? "");
  const what = m[3].replace(/^(?:the\s+)?/, "").replace(/[?!.]+$/, "").trim();
  const now = new Date().getUTCFullYear();
  for (const [re, label, date] of DAYS) {
    if (re.test(what) || re.test(`the ${what}`)) {
      const [month, day] = date(now);
      return { label, month, day, weeks };
    }
  }
  // "dec 25", "december 25", "25 dec", "25th of december"
  const md = what.match(/^([a-z]+)\.?\s+(\d{1,2})(?:st|nd|rd|th)?$/) ?? null;
  const dm = what.match(/^(\d{1,2})(?:st|nd|rd|th)?\s+(?:of\s+)?([a-z]+)\.?$/) ?? null;
  const monthName = md?.[1] ?? dm?.[2];
  const dayText = md?.[2] ?? dm?.[1];
  if (!monthName || !dayText) return null;
  const month = MONTHS.indexOf(monthName.slice(0, 3)) + 1;
  const day = Number(dayText);
  if (month < 1 || day < 1 || day > 31) return null;
  const pretty = `${monthName[0].toUpperCase()}${monthName.slice(1, 3)} ${day}`;
  return { label: pretty, month, day, weeks };
}

/** "How many days until Christmas": counted from today where the caller is. */
function daysAnswer(q: string, ctx: AnswerContext): AnswerCard | null {
  const asked = daysAsked(q);
  if (!asked) return null;
  const zone = ctx.tz ?? "UTC";
  const parts = Object.fromEntries(new Intl.DateTimeFormat("en-US", { timeZone: zone, year: "numeric", month: "numeric", day: "numeric" })
    .formatToParts(new Date()).map(p => [p.type, p.value]));
  const today = Date.UTC(Number(parts.year), Number(parts.month) - 1, Number(parts.day));
  let year = Number(parts.year);
  let target = Date.UTC(year, asked.month - 1, asked.day);
  if (target < today) {
    year += 1;
    const again = DAYS.find(([, label]) => label === asked.label);
    const [month, day] = again ? again[2](year) : [asked.month, asked.day];
    target = Date.UTC(year, month - 1, day);
  }
  const days = Math.round((target - today) / 86_400_000);
  const when = new Date(target).toLocaleDateString("en-US", { timeZone: "UTC", weekday: "long", month: "long", day: "numeric" });
  const count = asked.weeks && days >= 7
    ? `${Math.floor(days / 7)} week${Math.floor(days / 7) === 1 ? "" : "s"}${days % 7 ? ` and ${days % 7} day${days % 7 === 1 ? "" : "s"}` : ""}`
    : `${days} day${days === 1 ? "" : "s"}`;
  const say = days === 0 ? `${asked.label} is today` : `${count} until ${asked.label}`;
  return {
    kind: "answer", id: "days", art: "calc",
    title: q, value: days === 0 ? "Today" : count, sub: when, say,
    url: `https://www.google.com/search?q=${encodeURIComponent(q)}`,
  };
}

/** "5 km in miles": worked out here (lib/units.ts), never a model's
 *  "approximately". */
function unitAnswer(q: string): AnswerCard | null {
  const u = convertUnits(q);
  if (!u) return null;
  return {
    kind: "answer", id: "units", art: "calc",
    title: q, value: u.to, sub: u.from, say: u.say,
    url: `https://www.google.com/search?q=${encodeURIComponent(q)}`,
  };
}

// ── sun ───────────────────────────────────────────────────────────────────

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

/** Hours ahead of UTC a zone's clocks are right now, or null for an
 *  unknown zone. */
function zoneOffsetHours(tz: string, at = new Date()): number | null {
  try {
    const parts = new Intl.DateTimeFormat("en-US", {
      timeZone: tz, hourCycle: "h23",
      year: "numeric", month: "numeric", day: "numeric", hour: "numeric", minute: "numeric",
    }).formatToParts(at);
    const n = (type: string) => Number(parts.find(p => p.type === type)?.value);
    const local = Date.UTC(n("year"), n("month") - 1, n("day"), n("hour"), n("minute"));
    return (local - Date.UTC(at.getUTCFullYear(), at.getUTCMonth(), at.getUTCDate(),
      at.getUTCHours(), at.getUTCMinutes())) / 3_600_000;
  } catch {
    return null;
  }
}

/** A place whose sun keeps a clock hours away from the caller's zone is not
 *  where the caller is now: a location saved before a flight, say. Answering
 *  for it would give San Francisco's sunset in Bangkok time ("9:03 AM"). */
export function locationFitsZone(lon: number, tz: string | undefined, at = new Date()): boolean {
  if (!tz) return true;
  const offset = zoneOffsetHours(tz, at);
  if (offset === null) return true;
  const gap = Math.abs(offset - lon / 15) % 24;
  // Real zones sit up to three hours off their longitude (western China).
  return Math.min(gap, 24 - gap) <= 3.5;
}

/** Computed on the spot — no API, no key, no licence — for where it was
 *  asked about: a named place ("sunset in Paris", in Paris's own clock), or
 *  the caller (their zone's city when they share no location). */
async function sunAnswer(q: string, ask: LiveAsk, ctx: AnswerContext): Promise<AnswerCard | null> {
  const where = await placeFor(ask.place, ctx);
  if (!where) return null;
  // A named place keeps its own clock; the caller's answer is in theirs.
  const tz = ask.place ? where.tz ?? ctx.tz : ctx.tz;
  const times = sunTimes(where.lat, where.lon, new Date(Date.now() + ask.day * 86_400_000));
  const golden = ask.kind === "golden";
  const rise = ask.kind === "sunrise";
  const city = where.name ?? null;
  const when = ask.day ? "tomorrow" : "today";

  if (times.polar) {
    return {
      kind: "answer", id: "sun", art: "sun",
      title: times.polar === "day" ? "Midnight sun" : "Polar night",
      value: times.polar === "day" ? "No sunset" : "No sunrise",
      sub: "The sun stays "
        + (times.polar === "day" ? `up all day ${city ? `in ${city}` : "here"}` : `down all day ${city ? `in ${city}` : "here"}`),
      url: googleQ(q),
    };
  }
  const at = golden ? times.goldenHour : rise ? times.sunrise : times.sunset;
  if (!at) return null;
  const label = golden ? "Golden hour" : rise ? "Sunrise" : "Sunset";
  const clock = clockIn(at, tz);
  const place = city ? ` in ${city}` : "";
  // Another zone's clock says so: "7:28 PM local time" is Paris's, not theirs.
  const local = ask.place && tz && tz !== ctx.tz ? " local time" : "";
  const day = ask.day ? " tomorrow" : "";
  return {
    kind: "answer", id: rise ? "sunrise" : "sunset", art: "sun",
    title: label,
    say: golden ? `Golden hour${place}${day} starts at ${clock}${local} ✨`
      : rise ? `Sunrise${place}${day} is at ${clock}${local} 🌅` : `Sunset${place}${day} is at ${clock}${local} 🌇`,
    value: clock,
    sub: city ? `${label} in ${city} · ${when}` : `${label} · ${when}`,
    url: googleQ(q),
  };
}

function googleQ(q: string): string {
  return `https://www.google.com/search?q=${encodeURIComponent(q)}`;
}

// ── weather ───────────────────────────────────────────────────────────────

/** WMO weather codes, as Open-Meteo reports them. */
const WMO: Record<number, string> = {
  0: "Clear", 1: "Mostly clear", 2: "Partly cloudy", 3: "Cloudy", 45: "Fog", 48: "Fog",
  51: "Light drizzle", 53: "Drizzle", 55: "Heavy drizzle", 56: "Freezing drizzle", 57: "Freezing drizzle",
  61: "Light rain", 63: "Rain", 65: "Heavy rain", 66: "Freezing rain", 67: "Freezing rain",
  71: "Light snow", 73: "Snow", 75: "Heavy snow", 77: "Snow",
  80: "Light showers", 81: "Showers", 82: "Heavy showers", 85: "Snow showers", 86: "Heavy snow showers",
  95: "Thunderstorms", 96: "Thunderstorms with hail", 99: "Thunderstorms with hail",
};

interface Forecast {
  current?: { temperature_2m?: number; apparent_temperature?: number; weather_code?: number };
  daily?: {
    weather_code?: (number | null)[]; temperature_2m_max?: (number | null)[];
    temperature_2m_min?: (number | null)[]; precipitation_probability_max?: (number | null)[];
  };
}

/** Open-Meteo, keyless — the same service the Weather glyf reads. Now, or
 *  tomorrow; a named place or where the caller is. °F in the US. */
async function weatherAnswer(q: string, ask: LiveAsk, ctx: AnswerContext): Promise<AnswerCard | null> {
  const where = await placeFor(ask.place, ctx);
  if (!where) return null;
  const fahrenheit = ctx.country?.toUpperCase() === "US";
  const unit = fahrenheit ? "°F" : "°C";
  const data = await json<Forecast>("https://api.open-meteo.com/v1/forecast?" + new URLSearchParams({
    latitude: where.lat.toFixed(4), longitude: where.lon.toFixed(4),
    current: "temperature_2m,apparent_temperature,weather_code",
    daily: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max",
    timezone: "auto", forecast_days: "2",
    ...(fahrenheit ? { temperature_unit: "fahrenheit" } : {}),
  })).catch(() => null);
  if (!data) return null;
  const r = Math.round;
  const d = ask.day;
  const hi = data.daily?.temperature_2m_max?.[d] ?? undefined;
  const lo = data.daily?.temperature_2m_min?.[d] ?? undefined;
  const pct = data.daily?.precipitation_probability_max?.[d] ?? undefined;
  const code = data.daily?.weather_code?.[d] ?? undefined;
  const range = typeof hi === "number" && typeof lo === "number" ? `${r(lo)}–${r(hi)}${unit}` : "";
  const at = where.name ? ` in ${where.name}` : "";
  const title = where.name ? `Weather in ${where.name}` : "Weather";
  const when = d ? "tomorrow" : "today";

  if (ask.kind === "rain") {
    if (typeof pct !== "number") return null;
    const what = /snow/i.test(q) ? "Snow" : "Rain";
    const likely = pct >= 60 ? "likely" : pct >= 30 ? "possible" : "unlikely";
    return {
      kind: "answer", id: "weather", art: "weather", title,
      say: `${what} is ${likely}${at} ${when} (${pct}% chance)${range ? `, ${range}` : ""}`,
      value: `${pct}%`,
      sub: [`Chance of ${what.toLowerCase()} ${when}`, range].filter(Boolean).join(" · "),
      source: "open-meteo.com", url: googleQ(q),
    };
  }
  const rainy = typeof pct === "number" && pct >= 30 ? `${pct}% chance of rain` : "";
  if (d === 1) {
    if (!range) return null;
    const word = typeof code === "number" ? WMO[code] ?? "" : "";
    return {
      kind: "answer", id: "weather", art: "weather", title,
      say: `Tomorrow${at}: ${[word.toLowerCase(), range, rainy].filter(Boolean).join(", ")}`,
      value: `${r(hi as number)}°`,
      sub: [word, `${range} tomorrow`, rainy].filter(Boolean).join(" · "),
      source: "open-meteo.com", url: googleQ(q),
    };
  }
  const t = data.current?.temperature_2m;
  if (typeof t !== "number") return null;
  const now = typeof data.current?.weather_code === "number" ? WMO[data.current.weather_code] ?? "" : "";
  const feels = data.current?.apparent_temperature;
  // "28°C and cloudy", but "12°C with light rain".
  const sky = !now ? "" : /^(clear|mostly clear|partly cloudy|cloudy)$/i.test(now)
    ? ` and ${now.toLowerCase()}` : ` with ${now.toLowerCase()}`;
  const later = [range ? `${range} today` : "", rainy].filter(Boolean).join(", ");
  return {
    kind: "answer", id: "weather", art: "weather", title,
    say: `It's ${r(t)}${unit}${sky}${at} right now${later ? ` (${later})` : ""}`,
    value: `${r(t)}°`,
    sub: [now, typeof feels === "number" ? `feels ${r(feels)}°` : "", range ? `${range} today` : ""]
      .filter(Boolean).join(" · "),
    source: "open-meteo.com", url: googleQ(q),
  };
}

// ── the clock ─────────────────────────────────────────────────────────────

/** The caller's clock, or a named place's ("time in Tokyo"). */
async function timeAnswer(q: string, ask: LiveAsk, ctx: AnswerContext): Promise<AnswerCard | null> {
  let tz = ctx.tz;
  let name: string | undefined;
  if (ask.place) {
    const where = await geocodePlace(ask.place, ctx.country);
    if (!where?.tz) return null;
    tz = where.tz;
    name = where.name;
  }
  if (!tz) return null;
  let value: string, day: string, theirDay = "";
  const now = new Date();
  try {
    value = new Intl.DateTimeFormat("en-US", { timeStyle: "short", timeZone: tz }).format(now);
    day = new Intl.DateTimeFormat("en-US", { weekday: "long", timeZone: tz }).format(now);
    if (ctx.tz) theirDay = new Intl.DateTimeFormat("en-US", { weekday: "long", timeZone: ctx.tz }).format(now);
  } catch { return null; }
  // "It's 1:15 AM in Tokyo, Tuesday" when the day there is not theirs.
  const other = name && theirDay && theirDay !== day ? `, ${day}` : "";
  return {
    kind: "answer", id: "time", art: "none",
    title: name ? `Time in ${name}` : "Time", value, sub: name ? `${day} · ${name}` : day,
    url: googleQ(q), say: `It's ${value}${name ? ` in ${name}` : ""}${other}`,
  };
}

// ── money ─────────────────────────────────────────────────────────────────

/** What people call money, by symbol, code or name (singular; a plural "s"
 *  is taken off before looking). */
const FIAT: Record<string, string> = {
  "$": "USD", "us$": "USD", usd: "USD", dollar: "USD", buck: "USD", "us dollar": "USD", "american dollar": "USD",
  "€": "EUR", eur: "EUR", euro: "EUR",
  "£": "GBP", gbp: "GBP", pound: "GBP", "british pound": "GBP", "pound sterling": "GBP", sterling: "GBP", quid: "GBP",
  "₹": "INR", inr: "INR", rupee: "INR", "indian rupee": "INR", rs: "INR",
  "¥": "JPY", jpy: "JPY", yen: "JPY", "japanese yen": "JPY",
  cny: "CNY", yuan: "CNY", rmb: "CNY", renminbi: "CNY", "chinese yuan": "CNY",
  aud: "AUD", "a$": "AUD", "australian dollar": "AUD", cad: "CAD", "c$": "CAD", "canadian dollar": "CAD",
  sgd: "SGD", "s$": "SGD", "singapore dollar": "SGD", hkd: "HKD", "hk$": "HKD", "hong kong dollar": "HKD",
  nzd: "NZD", "new zealand dollar": "NZD", chf: "CHF", franc: "CHF", "swiss franc": "CHF",
  krw: "KRW", "₩": "KRW", won: "KRW", "korean won": "KRW", "south korean won": "KRW",
  thb: "THB", "฿": "THB", baht: "THB", "thai baht": "THB", myr: "MYR", ringgit: "MYR", "malaysian ringgit": "MYR",
  idr: "IDR", rupiah: "IDR", "indonesian rupiah": "IDR", php: "PHP", "₱": "PHP", "philippine peso": "PHP",
  mxn: "MXN", peso: "MXN", "mexican peso": "MXN", brl: "BRL", "r$": "BRL", real: "BRL", reais: "BRL", "brazilian real": "BRL",
  zar: "ZAR", rand: "ZAR", "south african rand": "ZAR", lira: "TRY", "turkish lira": "TRY", "₺": "TRY",
  sek: "SEK", krona: "SEK", kronor: "SEK", "swedish krona": "SEK", nok: "NOK", "norwegian krone": "NOK",
  dkk: "DKK", "danish krone": "DKK", pln: "PLN", zloty: "PLN", "zł": "PLN", czk: "CZK", koruna: "CZK",
  huf: "HUF", forint: "HUF", ils: "ILS", "₪": "ILS", shekel: "ILS", "israeli shekel": "ILS",
  aed: "AED", dirham: "AED", "uae dirham": "AED", sar: "SAR", riyal: "SAR", "saudi riyal": "SAR",
  isk: "ISK", ron: "RON", bgn: "BGN",
};
/** Coins priced by Jupiter, by ticker or name. */
const COINS: Record<string, string> = {
  sol: "SOL", solana: "SOL", btc: "BTC", bitcoin: "BTC", eth: "ETH", ethereum: "ETH", ether: "ETH",
  usdc: "USDC", usdt: "USDT", tether: "USDT", bonk: "BONK", jup: "JUP", jupiter: "JUP", wif: "WIF",
  doge: "DOGE", dogecoin: "DOGE", xrp: "XRP", bnb: "BNB", pyth: "PYTH", jto: "JTO",
};
const COIN_CODES = new Set(Object.values(COINS));
const AMOUNT_WORDS: Record<string, number> = {
  a: 1, an: 1, one: 1, two: 2, three: 3, four: 4, five: 5, ten: 10, hundred: 100, thousand: 1000,
};
const MULTIPLIERS: Record<string, number> = {
  k: 1e3, thousand: 1e3, m: 1e6, mn: 1e6, million: 1e6, bn: 1e9, billion: 1e9,
  lakh: 1e5, lakhs: 1e5, lac: 1e5, crore: 1e7, crores: 1e7, cr: 1e7,
};

function moneyUnit(raw: string): string | null {
  const u = raw.trim().replace(/\s+/g, " ").replace(/\.$/, "");
  if (!u) return null;
  const hit = FIAT[u] ?? COINS[u];
  if (hit) return hit;
  const one = u.endsWith("s") ? u.slice(0, -1) : "";
  return (one && (FIAT[one] ?? COINS[one])) || null;
}

export interface MoneyAsk {
  amount: number;
  /** ISO code or coin ticker: "EUR", "SOL". */
  from: string;
  to: string;
}

/** "50 euros in dollars", "$100 in inr", "how much is 1 sol in euros",
 *  "usd to inr": an amount of money asked in another money. Null for
 *  anything else ("meet at 5 in the lobby", "10 km in miles"). */
export function moneyAsked(text: string): MoneyAsk | null {
  let t = text.toLowerCase().replace(/[’‘]/g, "'").replace(/\s+/g, " ").replace(/[?!]+$/, "").trim();
  if (!t || t.length > 60) return null;
  t = t.replace(/^(?:how much is|how much are|how much would|what is|what's|whats|what are|convert)\s+/, "")
    .replace(/^(?:the\s+)?(?:price|value|rate)\s+of\s+/, "")
    .replace(/\s+(?:today|now|right now)$/, "");
  const parts = t.match(/^(.+?)\s+(?:in|to|into|=|in terms of)\s+(.+)$/);
  if (!parts) return null;
  // "sol price in inr" is "1 sol in inr".
  const left = parts[1].trim().replace(/\s+(?:price|rate|value)$/, "");
  const to = moneyUnit(parts[2].replace(/^the\s+/, ""));
  if (!to) return null;
  let amount = 1;
  let from = moneyUnit(left);
  if (!from) {
    const m = left.match(/^([$€£₹¥₩₱฿₪]|us\$|a\$|c\$|s\$|hk\$|r\$|rs\.?)?\s*(\d[\d,]*(?:\.\d+)?|a|an|one|two|three|four|five|ten|hundred|thousand)\s*(k|mn|m|bn|thousand|million|billion|lakhs?|lac|crores?|cr)?\s*([$€£₹¥₩₱฿₪]|[a-z$][a-z$. ]{0,24})?$/);
    if (!m) return null;
    amount = /\d/.test(m[2]) ? Number(m[2].replace(/,/g, "")) : AMOUNT_WORDS[m[2]];
    if (m[3]) amount *= MULTIPLIERS[m[3]] ?? 1;
    from = (m[4] ? moneyUnit(m[4]) : null) ?? (m[1] ? moneyUnit(m[1]) : null);
  }
  if (!from || from === to || !Number.isFinite(amount) || amount <= 0) return null;
  return { amount, from, to };
}

const money = new Rates();

/** An amount as a person writes it: 58.43, 9,588.12, 0.4213 (a coin). */
function moneyText(n: number, code: string): string {
  if (COIN_CODES.has(code)) {
    return n >= 1 ? n.toLocaleString("en-US", { maximumFractionDigits: 4 })
      : n.toLocaleString("en-US", { maximumSignificantDigits: 4 });
  }
  if (n > 0 && n < 0.01) return n.toLocaleString("en-US", { maximumSignificantDigits: 3 });
  return n.toLocaleString("en-US", { maximumFractionDigits: 2 });
}

/** Today's rates, never a model's memory of them: fiat from the ECB's daily
 *  table, coins from Jupiter's live price. */
async function currencyAnswer(q: string): Promise<AnswerCard | null> {
  const ask = moneyAsked(q);
  if (!ask) return null;
  const quotes: TokenQuote[] = [];
  const usdOf = async (code: string): Promise<number | null> => {
    if (COIN_CODES.has(code)) {
      const quote = await money.tokenQuote(code).catch(() => null);
      if (quote) quotes.push(quote);
      return quote?.usd ?? null;
    }
    const table = await money.fiatTable();
    const perDollar = table?.rates[code];
    return perDollar ? 1 / perDollar : null;
  };
  const [from, to] = await Promise.all([usdOf(ask.from), usdOf(ask.to)]);
  if (!from || !to) return null;
  const value = ask.amount * from / to;
  const amount = moneyText(ask.amount, ask.from);
  const result = moneyText(value, ask.to);
  const coins = quotes.length > 0;
  return {
    kind: "answer", id: "fx", art: "calc",
    title: `${amount} ${ask.from} to ${ask.to}`,
    say: `${amount} ${ask.from} is ${result} ${ask.to}`,
    value: `${result} ${ask.to}`,
    sub: `${amount} ${ask.from} · ${coins ? "live price" : "today's rate"}`,
    source: coins ? "Jupiter" : "ECB",
    url: `https://www.google.com/search?q=${encodeURIComponent(q)}`,
  };
}

/** Definitions come from Wikipedia's summary endpoint below rather than a
 *  dictionary API: the well-known free one (dictionaryapi.dev) is returning
 *  522s, and a dead upstream costs a real stall before the fallback runs.
 *  A configured web provider's own answer box covers proper definitions. */
async function wikiAnswer(q: string): Promise<AnswerCard | null> {
  const m = q.match(/^(?:what|who|where)(?:'s|’s|s|\s+(?:is|was|are|were))\s+(?:an?\s+|the\s+)?(.+?)\??$/i);
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
  // Local first: a sum costs nothing and cannot fail.
  const sum = mathAnswer(q);
  if (sum) return sum;
  const units = unitAnswer(q);
  if (units) return units;
  const days = daysAnswer(q, ctx);
  if (days) return days;
  // The time, the sun and the weather: computed, or Open-Meteo. Asked about
  // one and it can't be had, there is no other answer to give for it.
  const ask = liveAsk(q);
  if (ask) {
    const card = ask.kind === "time" ? timeAnswer(q, ask, ctx)
      : ask.kind === "weather" || ask.kind === "rain" ? weatherAnswer(q, ask, ctx)
      : sunAnswer(q, ask, ctx);
    return card.catch(() => null);
  }
  // Wikipedia no longer answers here: the AI does, from what it knows
  // (Arpit, 2026-09-29: "we wont be having any search for now, use ai only
  // for all that too"). Only exact, computed answers come before it.
  return await currencyAnswer(q).catch(() => null);
}

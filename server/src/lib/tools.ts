import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { z } from "zod";
import { registryDir } from "./paths.js";
import { priceAsked } from "./act.js";
import { geocodePlace } from "./answers.js";
import { Rates } from "./rates.js";
import { BlockedUrlError, safeFetchText, type SafeResponse } from "./safefetch.js";

/** §6.11 — the tool registry. Keyless tools ship now (no user auth, no API
 *  keys); OAuth tools activate in M6 when provider credentials exist. Every
 *  tool MUST declare `discloses` (rendered verbatim before install) — the
 *  schema enforces it and a test locks it. */

export const ToolMetaSchema = z.object({
  id: z.string().min(1),
  label: z.string().min(1),
  auth: z.string(),                 // "none" | "oauth:<provider>"
  inputs: z.array(z.object({
    name: z.string(),
    type: z.string(),
    required: z.boolean().default(false),
  })),
  output: z.string(),
  scopes: z.array(z.string()).default([]),
  discloses: z.string().min(1),
  rateLimit: z.object({ perMin: z.number().int().positive() }),
  timeoutMs: z.number().int().positive(),
});
export type ToolMeta = z.infer<typeof ToolMetaSchema>;

let cache: Map<string, ToolMeta> | null = null;

export function loadTools(dir = registryDir("tools")): Map<string, ToolMeta> {
  if (cache) return cache;
  const tools = new Map<string, ToolMeta>();
  for (const file of readdirSync(dir).filter(f => f.endsWith(".json")).sort()) {
    const meta = ToolMetaSchema.parse(JSON.parse(readFileSync(join(dir, file), "utf8")));
    tools.set(meta.id, meta);
  }
  cache = tools;
  return tools;
}

export function toolExists(id: string): boolean {
  return loadTools().has(id);
}

// Simple per-tool rate limiting (§6.11 rateLimit.perMin).
const hits = new Map<string, number[]>();
function rateLimited(meta: ToolMeta): boolean {
  const now = Date.now();
  const arr = (hits.get(meta.id) ?? []).filter(t => now - t < 60_000);
  arr.push(now);
  hits.set(meta.id, arr);
  return arr.length > meta.rateLimit.perMin;
}

async function fetchJSON(
  url: string, timeoutMs: number, headers: Record<string, string> = {},
): Promise<unknown> {
  const res = await fetch(url, {
    signal: AbortSignal.timeout(timeoutMs),
    headers: { "User-Agent": "glyf-dev/0.5 (keyboard tool)", ...headers },
  });
  if (!res.ok) throw new Error(`upstream ${res.status}`);
  return res.json();
}

/** Stock prices for stocks.quote, cached like the strip's cashtags. */
const stockRates = new Rates();

/** Executes a registry tool. Returns a STRING for the step context —
 *  human-readable where the result is terminal, JSON where chains continue.
 *  `connections` maps provider → access token (built per-device by the run
 *  route from the broker's store; tokens never leave the server). */
/** A tool saying no in words meant for the person ("No quote for 'xyz'"),
 *  shown as it is; a failure of the service behind it stays ours. */
function refuse(message: string): Error {
  return Object.assign(new Error(message.charAt(0).toUpperCase() + message.slice(1)), { userFacing: true });
}

export async function runTool(
  id: string,
  args: Record<string, string>,
  connections: Record<string, string>,
): Promise<string> {
  const meta = loadTools().get(id);
  if (!meta) throw new Error(`unknown tool '${id}'`);
  let token = "";
  if (meta.auth !== "none") {
    const provider = meta.auth.replace("oauth:", "");
    token = connections[provider] ?? "";
    if (!token) {
      throw refuse(`Connect ${provider[0].toUpperCase()}${provider.slice(1)} in the Glyf app first`);
    }
  }
  if (rateLimited(meta)) throw refuse("Too many at once. Try again in a minute");
  if (process.env.MOCK_AI === "true") return mockTool(id, args);

  switch (id) {
    // ── OAuth-backed (activate per-user after Connect) ──────────────────
    case "calendar.today": {
      const now = new Date();
      const start = new Date(now); start.setHours(0, 0, 0, 0);
      const end = new Date(now); end.setHours(23, 59, 59, 999);
      const data = await fetchJSON(
        "https://www.googleapis.com/calendar/v3/calendars/primary/events?" +
        new URLSearchParams({
          timeMin: start.toISOString(), timeMax: end.toISOString(),
          singleEvents: "true", orderBy: "startTime", maxResults: "10",
        }).toString(), meta.timeoutMs, { authorization: `Bearer ${token}` }) as {
          items?: { summary?: string; start?: { dateTime?: string; date?: string } }[];
        };
      const rows = (data.items ?? []).map(e => {
        const t = e.start?.dateTime
          ? new Intl.DateTimeFormat("en-US", { timeStyle: "short" })
              .format(new Date(e.start.dateTime))
          : "all day";
        return `${t} — ${e.summary ?? "(no title)"}`;
      });
      return rows.length ? rows.join("\n") : "Nothing on the calendar today";
    }
    case "notion.search": {
      const res = await fetch("https://api.notion.com/v1/search", {
        method: "POST",
        signal: AbortSignal.timeout(meta.timeoutMs),
        headers: {
          authorization: `Bearer ${token}`,
          "content-type": "application/json",
          "Notion-Version": "2022-06-28",
        },
        body: JSON.stringify({ query: args.query ?? "", page_size: 5 }),
      });
      if (!res.ok) throw refuse(`Notion said ${res.status} — try reconnecting`);
      const data = await res.json() as {
        results?: { url?: string; properties?: Record<string, {
          title?: { plain_text?: string }[] }>; title?: { plain_text?: string }[] }[];
      };
      const rows = (data.results ?? []).map(r => {
        const fromProps = Object.values(r.properties ?? {})
          .find(p => p.title)?.title?.[0]?.plain_text;
        const title = fromProps ?? r.title?.[0]?.plain_text ?? "Untitled";
        return JSON.stringify({ title, url: r.url ?? "" });
      });
      return `[${rows.join(",")}]`;
    }
    case "weather.now": {
      // What was in the field is rarely just a place: "hey are you coming
      // tonight" used to go to the geocoder whole and fail. Try the text as
      // a place, then any place named inside it, then where the phone is.
      // The geocoder the hold-space answers use: "bangalore" is Bengaluru
      // (not Bangalore Town in Sindh), the biggest Paris is the one meant.
      type Hit = { latitude: number; longitude: number; name: string };
      let hit: Hit | undefined;
      for (const name of placeCandidates(args.place ?? "")) {
        const place = await geocodePlace(name);
        if (place) { hit = { latitude: place.lat, longitude: place.lon, name: place.name ?? name }; break; }
      }
      const lat = Number(args.lat), lon = Number(args.lon);
      if (!hit && args.lat && args.lon && Number.isFinite(lat) && Number.isFinite(lon)) {
        hit = { latitude: lat, longitude: lon, name: "Here" };
      }
      if (!hit) {
        throw new ToolError("Which place? Hold W on a city name, or turn on Nearby search in the Glyf app.");
      }
      const wx = await fetchJSON(
        `https://api.open-meteo.com/v1/forecast?latitude=${hit.latitude}&longitude=${hit.longitude}` +
        `&current=temperature_2m,apparent_temperature,weather_code,wind_speed_10m` +
        `&daily=temperature_2m_max,temperature_2m_min&timezone=auto&forecast_days=1`,
        meta.timeoutMs) as {
          current: { temperature_2m: number; apparent_temperature: number; weather_code: number; wind_speed_10m: number };
          daily: { temperature_2m_max: number[]; temperature_2m_min: number[] };
        };
      const desc = weatherCode(wx.current.weather_code);
      return `${hit.name}: ${desc}, ${Math.round(wx.current.temperature_2m)}°C ` +
        `(feels ${Math.round(wx.current.apparent_temperature)}°C), ` +
        `today ${Math.round(wx.daily.temperature_2m_min[0])}–${Math.round(wx.daily.temperature_2m_max[0])}°C`;
    }
    case "quote.crypto": {
      // The strip's own prices (Jupiter, lib/rates.ts): "$sol", "sol",
      // "solana", "price of bonk" all find the coin; a stock works too.
      const asked = args.symbol?.trim() ? coinAsked(args.symbol) : "bitcoin";
      if (!asked) throw refuse("Type a coin, like $sol or bitcoin");
      const quote = await stockRates.tokenQuote(asked);
      if (!quote) throw refuse(`No price for '${asked}'`);
      const change = quote.change24h;
      return `${quote.ticker ?? quote.symbol} ${dollars(quote.usd)}` +
        (typeof change === "number" ? ` (${change >= 0 ? "+" : ""}${change.toFixed(1)}% in 24h)` : "");
    }
    case "fx.convert": {
      const amount = Number(args.amount || "1");
      const from = (args.from || "USD").toUpperCase();
      const to = (args.to || "INR").toUpperCase();
      const data = await fetchJSON(
        `https://api.frankfurter.dev/v1/latest?base=${encodeURIComponent(from)}&symbols=${encodeURIComponent(to)}`,
        meta.timeoutMs) as { rates: Record<string, number> };
      const rate = data.rates[to];
      if (!rate) throw refuse(`no rate ${from}→${to}`);
      return `${amount} ${from} = ${(amount * rate).toLocaleString("en-US", { maximumFractionDigits: 2 })} ${to}`;
    }
    case "url.unfurl": {
      const url = args.url;
      if (!/^https?:\/\//.test(url ?? "")) throw refuse("needs a full URL");
      // A pasted link is someone else's choice of address: lib/safefetch.ts
      // keeps it off the server's own network on every hop.
      let res: SafeResponse;
      try {
        res = await safeFetchText(url, {
          timeoutMs: meta.timeoutMs,
          headers: { "User-Agent": "glyf-dev/0.5 (unfurl)" },
          maxBytes: 60_000,
        });
      } catch (err) {
        if (err instanceof BlockedUrlError) throw refuse("can't preview that link");
        throw err;
      }
      const html = res.text.slice(0, 60_000);
      const pick = (re: RegExp) => html.match(re)?.[1]?.trim();
      const title = pick(/<meta[^>]+property=["']og:title["'][^>]+content=["']([^"']+)/i)
        ?? pick(/<title[^>]*>([^<]+)<\/title>/i) ?? url;
      const desc = pick(/<meta[^>]+property=["']og:description["'][^>]+content=["']([^"']+)/i)
        ?? pick(/<meta[^>]+name=["']description["'][^>]+content=["']([^"']+)/i) ?? "";
      return JSON.stringify({ title, description: desc, url });
    }
    case "time.now": {
      const tz = args.timezone || "Asia/Kolkata";
      return new Intl.DateTimeFormat("en-US", {
        timeZone: tz, dateStyle: "full", timeStyle: "short",
      }).format(new Date());
    }

    // ── Keyless expansion (all free, no API keys) ───────────────────────
    case "wiki.summary": {
      // "who is taylor swift" is asking about Taylor Swift: the question
      // goes, the topic stays. Not a page by that exact name, Wikipedia's
      // own search finds the one meant.
      const topic = wikiTopic(args.topic || "");
      if (!topic) throw refuse("Type a topic, like Taylor Swift");
      type Summary = { title?: string; extract?: string; type?: string };
      const summary = (title: string) => fetchJSON(
        `https://en.wikipedia.org/api/rest_v1/page/summary/${encodeURIComponent(title.replaceAll(" ", "_"))}`,
        meta.timeoutMs).catch(() => null) as Promise<Summary | null>;
      let data = await summary(topic);
      if (!data?.extract || data.type === "disambiguation") {
        const found = await fetchJSON("https://en.wikipedia.org/w/api.php?" + new URLSearchParams({
          action: "opensearch", search: topic, limit: "1", namespace: "0", format: "json",
        }).toString(), meta.timeoutMs).catch(() => null) as [string, string[]] | null;
        const title = found?.[1]?.[0];
        if (title) data = await summary(title);
      }
      if (!data?.extract || data.type === "disambiguation") throw refuse(`No Wikipedia page for '${topic}'`);
      return `${data.title ?? topic}: ${sentences(data.extract, 600)}`;
    }
    case "dict.define": {
      const word = (args.word || "").trim().split(/\s+/)[0];
      if (!word) throw refuse("needs a word");
      const data = await fetchJSON(
        `https://api.dictionaryapi.dev/api/v2/entries/en/${encodeURIComponent(word)}`,
        meta.timeoutMs) as {
          word: string; phonetic?: string;
          meanings: { partOfSpeech: string; definitions: { definition: string }[] }[];
        }[];
      const entry = data[0];
      if (!entry) throw refuse(`no definition for '${word}'`);
      const senses = entry.meanings.slice(0, 2).map(m =>
        `(${m.partOfSpeech}) ${m.definitions[0]?.definition ?? ""}`).join(" · ");
      return `${entry.word}${entry.phonetic ? ` ${entry.phonetic}` : ""} — ${senses}`;
    }
    case "word.synonyms": {
      const word = (args.word || "").trim().split(/\s+/)[0];
      if (!word) throw refuse("needs a word");
      const data = await fetchJSON(
        `https://api.datamuse.com/words?rel_syn=${encodeURIComponent(word)}&max=8`,
        meta.timeoutMs) as { word: string }[];
      if (!data.length) throw refuse(`no synonyms for '${word}'`);
      return data.map(w => w.word).join(", ");
    }
    case "stocks.quote": {
      // Jupiter's verified tokenized shares on Solana (xStocks) track the
      // stock; stooq's free CSV, used before, is gone (404 since 2026-09).
      const raw = (args.symbol || "AAPL").trim().replace(/\.us$/i, "");
      const quote = await stockRates.tokenQuote(raw);
      if (!quote) throw refuse(`no quote for '${args.symbol}'`);
      const change = quote.change24h;
      return `${quote.ticker ?? quote.symbol} $${quote.usd.toFixed(2)}` +
        (typeof change === "number" ? ` (${change >= 0 ? "+" : ""}${change.toFixed(1)}% in 24h)` : "");
    }
    case "air.quality": {
      const place = args.place || "Bengaluru";
      const geo = await fetchJSON(
        `https://geocoding-api.open-meteo.com/v1/search?count=1&name=${encodeURIComponent(place)}`,
        meta.timeoutMs) as { results?: { latitude: number; longitude: number; name: string }[] };
      const hit = geo.results?.[0];
      if (!hit) throw refuse(`couldn't find '${place}'`);
      const aq = await fetchJSON(
        `https://air-quality-api.open-meteo.com/v1/air-quality?latitude=${hit.latitude}` +
        `&longitude=${hit.longitude}&current=us_aqi,pm2_5`, meta.timeoutMs) as {
          current: { us_aqi: number; pm2_5: number };
        };
      const aqi = aq.current.us_aqi;
      const band = aqi <= 50 ? "good" : aqi <= 100 ? "moderate"
        : aqi <= 150 ? "unhealthy for sensitive groups" : aqi <= 200 ? "unhealthy"
        : "hazardous";
      return `${hit.name} AQI ${aqi} (${band}), PM2.5 ${aq.current.pm2_5} µg/m³`;
    }
    // ── Keyboard search suite (Gboard-style surface; JSON-array rows) ────
    case "web.search": {
      const q = (args.query || "").trim();
      if (!q) throw refuse("needs a search");
      const rows: { title: string; snippet?: string; url: string }[] = [];
      try {
        const data = await fetchJSON(
          `https://api.duckduckgo.com/?format=json&no_html=1&skip_disambig=1&q=${encodeURIComponent(q)}`,
          meta.timeoutMs) as {
            Heading?: string; AbstractText?: string; AbstractURL?: string;
            RelatedTopics?: { Text?: string; FirstURL?: string }[];
          };
        if (data.Heading && data.AbstractText) {
          rows.push({ title: data.Heading, snippet: data.AbstractText, url: data.AbstractURL ?? "" });
        }
        for (const t of (data.RelatedTopics ?? []).slice(0, 4)) {
          if (t.Text && t.FirstURL) rows.push({ title: t.Text, url: t.FirstURL });
        }
      } catch { /* instant answers are best-effort; the search link below always works */ }
      rows.push({
        title: `Search the web for “${q}”`,
        url: `https://www.google.com/search?q=${encodeURIComponent(q)}`,
      });
      return JSON.stringify(rows);
    }
    case "yt.search": {
      const q = (args.query || "").trim();
      if (!q) throw refuse("needs a search");
      const key = process.env.YOUTUBE_API_KEY;
      const link = `https://www.youtube.com/results?search_query=${encodeURIComponent(q)}`;
      if (!key) {
        // Keyless fallback: still useful — inserts a working search link.
        return JSON.stringify([{ title: `Search YouTube for “${q}”`, url: link }]);
      }
      const data = await fetchJSON(
        "https://www.googleapis.com/youtube/v3/search?" + new URLSearchParams({
          part: "snippet", type: "video", maxResults: "5", q, key,
        }).toString(), meta.timeoutMs) as {
          items?: { id?: { videoId?: string }; snippet?: { title?: string; channelTitle?: string } }[];
        };
      const rows = (data.items ?? [])
        .filter(v => v.id?.videoId)
        .map(v => ({
          title: v.snippet?.title ?? "Video",
          snippet: v.snippet?.channelTitle ?? "",
          url: `https://youtu.be/${v.id!.videoId}`,
        }));
      return JSON.stringify(rows.length ? rows : [{ title: `Search YouTube for “${q}”`, url: link }]);
    }
    case "maps.search": {
      const q = (args.query || "").trim();
      if (!q) throw refuse("needs a search");
      const data = await fetchJSON(
        `https://nominatim.openstreetmap.org/search?format=jsonv2&limit=4&q=${encodeURIComponent(q)}`,
        meta.timeoutMs) as { display_name: string; lat: string; lon: string }[];
      const rows = data.map(p => ({
        title: p.display_name.split(",").slice(0, 2).join(",").trim(),
        snippet: p.display_name,
        url: `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(`${p.lat},${p.lon}`)}`,
      }));
      rows.push({
        title: `Search Maps for “${q}”`,
        snippet: "",
        url: `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(q)}`,
      });
      return JSON.stringify(rows);
    }
    case "places.search": {
      const q = (args.query || "").trim();
      if (!q) throw refuse("needs a search");
      // Geoapify first (the Maps tab's search): it knows businesses and
      // reads "pizza in Brooklyn" as a kind of place in an area. Nominatim
      // only geocodes names, so it found nothing there and sent "pizza" to
      // a village in Nigeria (prod check, 21 Oct 2026).
      if (process.env.GEOAPIFY_KEY) {
        const { geoapifyPlaces } = await import("./search.js");
        const found = await geoapifyPlaces(q, {}).catch(() => []);
        if (found.length) {
          return found.slice(0, 3).map(p =>
            `${p.title}${p.address ? `, ${p.address}` : ""} (maps: ${p.url})`).join("\n");
        }
      }
      const data = await fetchJSON(
        `https://nominatim.openstreetmap.org/search?format=jsonv2&limit=3&q=${encodeURIComponent(q)}`,
        meta.timeoutMs) as { display_name: string; lat: string; lon: string }[];
      if (!data.length) throw refuse(`nothing found for '${q}'`);
      return data.map(p =>
        `${p.display_name} (maps: https://www.openstreetmap.org/?mlat=${p.lat}&mlon=${p.lon})`)
        .join("\n");
    }
    case "route.eta": {
      const geocode = async (q: string) => {
        const g = await fetchJSON(
          `https://geocoding-api.open-meteo.com/v1/search?count=1&name=${encodeURIComponent(q)}`,
          meta.timeoutMs) as { results?: { latitude: number; longitude: number; name: string }[] };
        const hit = g.results?.[0];
        if (!hit) throw refuse(`couldn't find '${q}'`);
        return hit;
      };
      const a = await geocode(args.from || "");
      const b = await geocode(args.to || "");
      const r = await fetchJSON(
        `https://router.project-osrm.org/route/v1/driving/${a.longitude},${a.latitude};${b.longitude},${b.latitude}?overview=false`,
        meta.timeoutMs) as { routes?: { duration: number; distance: number }[] };
      const route = r.routes?.[0];
      if (!route) throw refuse("no route found");
      const mins = Math.round(route.duration / 60);
      const h = Math.floor(mins / 60);
      return `${a.name} → ${b.name}: ${(route.distance / 1000).toFixed(0)} km, ` +
        `about ${h ? `${h}h ${mins % 60}m` : `${mins} min`} by road`;
    }
    case "holidays.next": {
      const country = (args.country || "IN").toUpperCase().slice(0, 2);
      const data = await fetchJSON(
        `https://date.nager.at/api/v3/NextPublicHolidays/${country}`,
        meta.timeoutMs) as { date: string; localName: string }[];
      if (!data.length) throw refuse(`no holiday data for '${country}'`);
      return data.slice(0, 3).map(h => `${h.date}: ${h.localName}`).join("\n");
    }
    case "books.search": {
      const q = (args.query || "").trim();
      if (!q) throw refuse("needs a title or author");
      const data = await fetchJSON(
        `https://openlibrary.org/search.json?limit=3&q=${encodeURIComponent(q)}`,
        meta.timeoutMs) as {
          docs: { title: string; author_name?: string[]; first_publish_year?: number }[];
        };
      if (!data.docs.length) throw refuse(`no books found for '${q}'`);
      return data.docs.map(b =>
        `${b.title} — ${b.author_name?.[0] ?? "unknown"}${b.first_publish_year ? ` (${b.first_publish_year})` : ""}`)
        .join("\n");
    }
    case "news.tech": {
      const data = await fetchJSON(
        "https://hn.algolia.com/api/v1/search?tags=front_page&hitsPerPage=5",
        meta.timeoutMs) as { hits: { title: string; url?: string; points: number }[] };
      return data.hits.map(h => `${h.title} (${h.points}▲)`).join("\n");
    }
    case "sports.next": {
      const team = (args.team || "").trim();
      if (!team) throw refuse("needs a team name");
      const t = await fetchJSON(
        `https://www.thesportsdb.com/api/v1/json/123/searchteams.php?t=${encodeURIComponent(team)}`,
        meta.timeoutMs) as { teams?: { idTeam: string; strTeam: string }[] };
      const hit = t.teams?.[0];
      if (!hit) throw refuse(`couldn't find team '${team}'`);
      const ev = await fetchJSON(
        `https://www.thesportsdb.com/api/v1/json/123/eventsnext.php?id=${hit.idTeam}`,
        meta.timeoutMs) as { events?: { strEvent: string; dateEvent: string; strTime?: string }[] };
      const next = ev.events?.[0];
      if (!next) return `${hit.strTeam}: no upcoming fixtures listed`;
      return `${next.strEvent} — ${next.dateEvent}${next.strTime ? ` ${next.strTime.slice(0, 5)} UTC` : ""}`;
    }
    case "joke.random": {
      const res = await fetch("https://icanhazdadjoke.com/", {
        signal: AbortSignal.timeout(meta.timeoutMs),
        headers: { accept: "application/json", "User-Agent": "glyf-dev/0.5" },
      });
      const data = await res.json() as { joke?: string };
      if (!data.joke) throw refuse("the joke well is dry");
      return data.joke;
    }
    case "quote.inspire": {
      const data = await fetchJSON("https://zenquotes.io/api/random",
        meta.timeoutMs) as { q: string; a: string }[];
      const q = data[0];
      if (!q) throw refuse("no quote today");
      return `“${q.q}” — ${q.a}`;
    }
    case "advice.random": {
      const data = await fetchJSON("https://api.adviceslip.com/advice",
        meta.timeoutMs) as { slip?: { advice: string } };
      if (!data.slip) throw refuse("no advice available");
      return data.slip.advice;
    }
    case "fact.random": {
      const data = await fetchJSON(
        "https://uselessfacts.jsph.pl/api/v2/facts/random?language=en",
        meta.timeoutMs) as { text?: string };
      if (!data.text) throw refuse("no fact available");
      return data.text;
    }
    case "urban.define": {
      const term = (args.term || "").trim();
      if (!term) throw refuse("needs a term");
      const data = await fetchJSON(
        `https://api.urbandictionary.com/v0/define?term=${encodeURIComponent(term)}`,
        meta.timeoutMs) as { list: { definition: string; thumbs_up: number }[] };
      const top = data.list.sort((a, b) => b.thumbs_up - a.thumbs_up)[0];
      if (!top) throw refuse(`no slang entry for '${term}'`);
      return `${term}: ${top.definition.replaceAll("[", "").replaceAll("]", "").slice(0, 280)}`;
    }
    case "country.info": {
      const name = (args.country || "").trim();
      if (!name) throw refuse("needs a country");
      const data = await fetchJSON(
        `https://restcountries.com/v3.1/name/${encodeURIComponent(name)}?fields=name,capital,population,currencies,region`,
        meta.timeoutMs) as {
          name: { common: string }; capital?: string[]; population: number;
          region: string; currencies?: Record<string, { name: string; symbol?: string }>;
        }[];
      const c = data[0];
      if (!c) throw refuse(`couldn't find '${name}'`);
      const currency = Object.values(c.currencies ?? {})[0];
      return `${c.name.common} — capital ${c.capital?.[0] ?? "?"}, ` +
        `${(c.population / 1e6).toFixed(1)}M people, ${c.region}` +
        (currency ? `, currency ${currency.name}${currency.symbol ? ` (${currency.symbol})` : ""}` : "");
    }
    case "repo.info": {
      const repo = (args.repo || "").trim().replace(/^https?:\/\/github\.com\//, "");
      if (!/^[\w.-]+\/[\w.-]+$/.test(repo)) throw refuse("needs owner/repo");
      const data = await fetchJSON(`https://api.github.com/repos/${repo}`,
        meta.timeoutMs, { accept: "application/vnd.github+json" }) as {
          full_name: string; description?: string; stargazers_count: number;
          language?: string; html_url: string;
        };
      return `${data.full_name} ★${data.stargazers_count.toLocaleString("en-US")}` +
        `${data.language ? ` · ${data.language}` : ""}` +
        `${data.description ? ` — ${data.description}` : ""} ${data.html_url}`;
    }
    case "food.info": {
      const q = (args.food || "").trim();
      if (!q) throw refuse("needs a food");
      const data = await fetchJSON(
        "https://world.openfoodfacts.org/cgi/search.pl?search_simple=1&action=process&json=1&page_size=1" +
        `&search_terms=${encodeURIComponent(q)}`, meta.timeoutMs) as {
          products?: { product_name?: string; nutriscore_grade?: string;
            nutriments?: { [k: string]: number | undefined } }[];
        };
      const p = data.products?.[0];
      if (!p?.product_name) throw refuse(`no food data for '${q}'`);
      const kcal = p.nutriments?.["energy-kcal_100g"];
      return `${p.product_name}: ${kcal ? `${Math.round(kcal)} kcal/100g` : "energy n/a"}` +
        `${p.nutriscore_grade ? `, Nutri-Score ${p.nutriscore_grade.toUpperCase()}` : ""}`;
    }
    case "recipes.search": {
      const q = (args.dish || "").trim();
      if (!q) throw refuse("needs a dish");
      const data = await fetchJSON(
        `https://www.themealdb.com/api/json/v1/1/search.php?s=${encodeURIComponent(q)}`,
        meta.timeoutMs) as {
          meals?: { strMeal: string; strArea: string; strInstructions: string }[];
        };
      const meal = data.meals?.[0];
      if (!meal) throw refuse(`no recipe for '${q}'`);
      return `${meal.strMeal} (${meal.strArea}): ${meal.strInstructions.slice(0, 400)}…`;
    }
    default:
      throw refuse(`tool '${id}' has no executor`);
  }
}

/** The coin or stock in what was typed: "$sol", "SOL", "solana", "price of
 *  bonk", "what's btc at". */
export function coinAsked(text: string): string | null {
  const t = text.trim();
  const cashtag = t.match(/\$([A-Za-z][A-Za-z0-9]{1,13})\b/);
  if (cashtag) return cashtag[1];
  const asked = priceAsked(t);
  if (asked) return asked;
  const words = t.replace(/[?!.]+$/, "").trim().split(/\s+/);
  return words.length === 1 && Rates.tickerOf(words[0]) ? words[0] : null;
}

/** The subject of a question: "who is taylor swift?" → "taylor swift". */
export function wikiTopic(text: string): string {
  return text.trim().replace(/\s+/g, " ")
    .replace(/^(?:tell me about|tell me more about|info on|information (?:on|about)|wiki(?:pedia)?:?|search wikipedia for|look up)\s+/i, "")
    .replace(/^(?:who|what|where|when)(?:'s|’s|s|\s+(?:is|are|was|were))\s+/i, "")
    .replace(/^(?:a|an|the)\s+/i, "")
    .replace(/\s+(?:please|pls|plz)$/i, "")
    .replace(/[?!.]+$/, "")
    .trim()
    .slice(0, 100);
}

/** Whole sentences up to about `max` characters. */
function sentences(text: string, max: number): string {
  if (text.length <= max) return text;
  const cut = text.slice(0, max);
  const end = cut.lastIndexOf(". ");
  return end > max / 3 ? cut.slice(0, end + 1) : `${cut.trimEnd()}…`;
}

/** $117.98, or $0.00001234 for a coin worth a fraction of a cent. */
function dollars(n: number): string {
  if (n >= 1) return `$${n.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
  return `$${n.toPrecision(4).replace(/0+$/, "")}`;
}

/** A tool's refusal that the person can act on, worded for them; the run
 *  route shows these as they are, unlike the errors we own. */
export class ToolError extends Error {
  readonly userFacing = true;
}

/** Names that could be a place, most likely first: the text itself when it
 *  is short and plain, whatever follows "in"/"at", then capitalised words. */
export function placeCandidates(text: string): string[] {
  const out: string[] = [];
  const clean = text.replace(/[?!.,;:]+\s*$/g, "").trim();
  if (!clean) return out;
  const words = clean.split(/\s+/);
  if (words.length <= 4 && !/[?!.,;:]/.test(clean)) out.push(clean);
  const after = clean.match(/\b(?:in|at|for|to)\s+([A-Z][\p{L}'-]*(?:\s+[A-Z][\p{L}'-]*){0,2})/u);
  if (after && !out.includes(after[1])) out.push(after[1]);
  for (const w of words) {
    const bare = w.replace(/[^\p{L}'-]/gu, "");
    if (/^[A-Z][\p{L}'-]{2,}$/u.test(bare) && !out.includes(bare)) out.push(bare);
  }
  return out.slice(0, 4);
}

/** §8.4-style determinism for tests: canned tool outputs in mock mode. */
function mockTool(id: string, args: Record<string, string>): string {
  switch (id) {
    case "weather.now":
      return `${args.place || "Bengaluru"}: MOCK clear sky, 24°C (feels 25°C), today 21–29°C`;
    case "quote.crypto":
      return `${(args.symbol || "sol").toUpperCase()} $123.45 (+2.5% 24h) MOCK`;
    case "fx.convert":
      return `${args.amount || 1} ${args.from || "USD"} = MOCK 83.12 ${args.to || "INR"}`;
    case "url.unfurl":
      return JSON.stringify({ title: "MOCK page", description: "mock unfurl", url: args.url });
    case "time.now":
      return "MOCK Friday, September 12, 2026 at 12:00 PM";
    case "wiki.summary":
      return `${args.topic || "Topic"}: MOCK encyclopedia summary in two sentences.`;
    case "dict.define":
      return `${args.word || "word"} /wɜːd/ — (noun) MOCK a unit of language.`;
    case "word.synonyms":
      return "MOCK, term, expression, phrase";
    case "stocks.quote":
      return `${(args.symbol || "AAPL").toUpperCase()} $123.45 (+1.2% today, MOCK)`;
    case "air.quality":
      return `${args.place || "Bengaluru"} AQI 42 (good), PM2.5 9 µg/m³ MOCK`;
    case "places.search":
      return `MOCK Cafe, 42 Glass Lane (maps: https://osm.example/1)`;
    case "web.search":
      return JSON.stringify([
        { title: `${args.query || "Topic"}`, snippet: "MOCK instant answer.", url: "https://example.com/a" },
        { title: `Search the web for “${args.query || "topic"}”`, url: "https://www.google.com/search?q=mock" },
      ]);
    case "yt.search":
      return JSON.stringify([
        { title: "MOCK Video One", snippet: "Mock Channel", url: "https://youtu.be/mock1" },
        {
          title: `Search YouTube for “${args.query || "topic"}”`,
          url: "https://www.youtube.com/results?search_query=mock",
        },
      ]);
    case "maps.search":
      return JSON.stringify([
        { title: "MOCK Cafe", snippet: "42 Glass Lane, Mock City", url: "https://www.google.com/maps/search/?api=1&query=12.9,77.6" },
      ]);
    case "route.eta":
      return `${args.from || "A"} → ${args.to || "B"}: 12 km, about 25 min by road MOCK`;
    case "holidays.next":
      return "2026-10-02: MOCK Gandhi Jayanti";
    case "books.search":
      return "MOCK Book — An Author (2020)";
    case "news.tech":
      return "MOCK headline one (321▲)\nMOCK headline two (123▲)";
    case "sports.next":
      return "MOCK FC vs United — 2026-09-20 19:30 UTC";
    case "recipes.search":
      return `${args.dish || "Dish"} (MOCK): stir, simmer, serve…`;
    case "joke.random":
      return "MOCK: Why did the keyboard go to therapy? Too many issues to press.";
    case "quote.inspire":
      return "“MOCK the day.” — Anon";
    case "advice.random":
      return "MOCK advice: ship it.";
    case "fact.random":
      return "MOCK fact: honey never spoils.";
    case "urban.define":
      return `${args.term || "term"}: MOCK slang meaning.`;
    case "country.info":
      return `${args.country || "India"} — capital MOCK City, 1.4M people, Asia`;
    case "repo.info":
      return `${args.repo || "owner/repo"} ★12,345 · Swift — MOCK repo`;
    case "food.info":
      return `${args.food || "Food"}: 250 kcal/100g, Nutri-Score B MOCK`;
    case "calendar.today":
      return "9:30 AM — MOCK Standup\n2:00 PM — MOCK Design review";
    case "notion.search":
      return `[{"title":"MOCK Page","url":"https://notion.so/mock"}]`;
    default:
      return `MOCK ${id}`;
  }
}

function weatherCode(code: number): string {
  const map: Record<number, string> = {
    0: "clear sky", 1: "mostly clear", 2: "partly cloudy", 3: "overcast",
    45: "fog", 48: "fog", 51: "light drizzle", 61: "light rain", 63: "rain",
    65: "heavy rain", 71: "light snow", 80: "showers", 95: "thunderstorm",
  };
  return map[code] ?? "mixed conditions";
}

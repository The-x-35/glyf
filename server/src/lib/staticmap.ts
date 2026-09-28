/** The little maps on place cards (routes/search.ts serves them; both
 *  keyboards show one where a place has no photo of its own). Geoapify takes
 *  two to four seconds to draw each new map, so a drawn map is kept a while,
 *  a second ask for one still being drawn waits on that same draw, and a maps
 *  search starts drawing its first few before the phone asks for them. */

export type MapImage = { type: string; body: Buffer };

/** One map: the spot, the size in points, and the theme. */
export type MapAsk = { lat: number; lon: number; w: number; h: number; dark: boolean };

/** Half an hour, and at most 300 maps (about 25 MB). */
const KEEP_MS = 30 * 60_000;
const MAX_KEPT = 300;
/** How many of a search's maps are drawn ahead: the rows a keyboard shows
 *  without scrolling, and a couple more. */
const AHEAD = 6;

const kept = new Map<string, { at: number; image: Promise<MapImage | null> }>();

const clamp = (v: unknown, lo: number, hi: number, fallback: number) => {
  const n = Math.round(Number(v));
  return Number.isFinite(n) ? Math.min(Math.max(n, lo), hi) : fallback;
};

/** A map request's numbers as the route reads them, or null when the spot
 *  is not a real one. Only numbers cross the wire, never a caller's URL. */
export function mapAsk(q: { lat?: unknown; lon?: unknown; w?: unknown; h?: unknown; dark?: unknown }): MapAsk | null {
  const lat = Number(q.lat), lon = Number(q.lon);
  if (!Number.isFinite(lat) || !Number.isFinite(lon) || Math.abs(lat) > 90 || Math.abs(lon) > 180) return null;
  return { lat, lon, w: clamp(q.w, 120, 800, 600), h: clamp(q.h, 80, 500, 240), dark: q.dark === "1" };
}

/** The map, drawn once and then kept: null when Geoapify could not draw it
 *  (a failure is not kept, so the next ask tries again). */
export function drawMap(ask: MapAsk, fetcher: typeof fetch = fetch): Promise<MapImage | null> {
  const key = process.env.GEOAPIFY_KEY;
  if (!key) return Promise.resolve(null);
  const at = `lonlat:${ask.lon.toFixed(6)},${ask.lat.toFixed(6)}`;
  const id = `${at} ${ask.w}x${ask.h} ${ask.dark ? "dark" : "light"}`;
  const now = Date.now();
  const hit = kept.get(id);
  if (hit && now - hit.at < KEEP_MS) {
    // The most recently used goes to the back; the oldest leaves first.
    kept.delete(id);
    kept.set(id, hit);
    return hit.image;
  }
  const style = ask.dark ? "dark-matter" : "positron";
  const image = fetcher(
    `https://maps.geoapify.com/v1/staticmap?style=${style}&width=${ask.w}&height=${ask.h}` +
    `&center=${at}&zoom=15.5&scaleFactor=2&marker=${at};color:%23ea4335;size:medium&apiKey=${key}`,
    { signal: AbortSignal.timeout(8000) },
  ).then(async res => res.ok
    ? { type: res.headers.get("content-type") ?? "image/png", body: Buffer.from(await res.arrayBuffer()) }
    : null,
  ).catch(() => null);
  const entry = { at: now, image };
  kept.set(id, entry);
  void image.then(drawnMap => { if (!drawnMap && kept.get(id) === entry) kept.delete(id); });
  while (kept.size > MAX_KEPT) {
    const oldest = kept.keys().next().value;
    if (oldest === undefined) break;
    kept.delete(oldest);
  }
  return image;
}

/** Starts drawing the first maps of a search's cards in the theme the
 *  keyboard said it will ask for, so they are ready (or on their way) when
 *  its requests arrive. */
export function drawAhead(cards: ReadonlyArray<object>, dark: boolean,
                          fetcher: typeof fetch = fetch): number {
  let started = 0;
  for (const card of cards) {
    if (started >= AHEAD) break;
    // Answer and tail cards have no picture at all.
    const thumb = (card as { thumb?: unknown }).thumb;
    if (typeof thumb !== "string" || !thumb.startsWith("/search/staticmap?")) continue;
    const q = Object.fromEntries(new URLSearchParams(thumb.slice(thumb.indexOf("?") + 1)));
    const ask = mapAsk({ ...q, dark: dark ? "1" : "0" });
    if (!ask) continue;
    void drawMap(ask, fetcher);
    started++;
  }
  return started;
}

/** Tests start from nothing kept. */
export function forgetMaps(): void {
  kept.clear();
}

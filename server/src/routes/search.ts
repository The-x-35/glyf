import type { FastifyInstance } from "fastify";
import { connKey } from "./connector.js";
import type { Guard } from "../lib/guard.js";
import type { KV } from "../lib/store.js";
import { z } from "zod";
import { search, searchProviders } from "../lib/search.js";
import { drawAhead, drawMap, mapAsk } from "../lib/staticmap.js";
import { suggest } from "../lib/suggest.js";

/** The search suite's own endpoint. `/tools/run` stays as it is — glyf chains
 *  consume flat strings — while the keyboard's Search / YouTube / Shorts / Maps tabs
 *  need typed cards with thumbnails, ratings and durations.
 *
 *  Lookups cost nothing and never touch the plan meter; the web tab's model
 *  answer, when nothing else answered, counts as a run like any other. */

const BodySchema = z.object({
  vertical: z.enum(["web", "yt", "maps", "shorts"]),
  query: z.string().min(1).max(200),
  deviceId: z.string().min(1).max(80),
  /** Optional coarse location — the containing app asks for permission and
   *  caches it; the keyboard forwards it so "near me" means something. It is
   *  never stored server-side, only used for this request. */
  lat: z.number().min(-90).max(90).optional(),
  lon: z.number().min(-180).max(180).optional(),
  country: z.string().length(2).optional(),
  tz: z.string().max(64).optional(),
  /** Whether the keyboard is dark, so a maps search can draw its places'
   *  maps in the theme the keyboard will ask for before it asks. */
  dark: z.boolean().optional(),
});

export function searchRoutes(app: FastifyInstance, kv: KV, guard: Guard): void {
  /** The device's live Google token, or undefined. Never leaves the server. */
  const googleToken = (deviceId?: string): string | undefined => {
    if (!deviceId) return undefined;
    const conn = kv.get<{ access_token: string; expires_at: number }>(
      "connections", connKey(deviceId, "google"));
    return conn && conn.expires_at > Date.now() ? conn.access_token : undefined;
  };

  app.post("/search", async (req, reply) => {
    const parsed = BodySchema.safeParse(req.body);
    if (!parsed.success) {
      // The issues say which FIELD was wrong; the body would carry the user's
      // query, which has no business in a log file.
      req.log.warn({ issues: parsed.error.issues.map(i => ({ path: i.path, code: i.code })) }, "search bad request");
      return reply.code(400).send({ error: "bad request" });
    }
    const { vertical, query, deviceId, lat, lon, country, tz, dark } = parsed.data;
    try {
      const result = await search(vertical, query, {
        lat, lon, country: country?.toUpperCase(), tz,
      }, {
        // Asked only once nothing else has answered; a plan with no run
        // left gets the Google row instead of a guess.
        model: async () => (await guard.spend(req, deviceId)).ok,
      });
      if (vertical === "maps" && dark !== undefined) drawAhead(result.cards, dark);
      return { ok: true, ...result };
    } catch (err) {
      // What broke is ours to read in the log; the phone gets a plain line.
      req.log.warn({ vertical, err: err instanceof Error ? err.message : String(err) }, "search failed");
      return reply.code(502).send({ ok: false, error: "Search isn't working right now. Try again." });
    }
  });

  /** Places photos are behind the API key, so the key stays here and the
   *  clients fetch the image from us instead. */
  app.get("/search/photo", async (req, reply) => {
    const ref = (req.query as { ref?: string }).ref ?? "";
    const key = process.env.GOOGLE_PLACES_KEY;
    // Only ever proxy a Places photo resource name — never an arbitrary URL.
    if (!key || !/^places\/[\w-]+\/photos\/[\w-]+$/.test(ref)) {
      return reply.code(404).send({ error: "no photo" });
    }
    const upstream = await fetch(
      `https://places.googleapis.com/v1/${ref}/media?maxHeightPx=256&maxWidthPx=256&key=${key}`,
      { signal: AbortSignal.timeout(6000), redirect: "follow" },
    ).catch(() => null);
    if (!upstream?.ok) return reply.code(502).send({ error: "photo failed" });
    reply.header("content-type", upstream.headers.get("content-type") ?? "image/jpeg");
    reply.header("cache-control", "public, max-age=86400");
    return reply.send(Buffer.from(await upstream.arrayBuffer()));
  });

  /** A place card's map, for a place with no photo (both keyboards). Only
   *  numbers cross the wire, never a caller's URL, and Geoapify's key stays
   *  here. No key → 404 and the card keeps its pin. Drawn maps are kept a
   *  while (lib/staticmap.ts). */
  app.get("/search/staticmap", async (req, reply) => {
    const ask = mapAsk(req.query as Record<string, unknown>);
    if (!process.env.GEOAPIFY_KEY || !ask) return reply.code(404).send({ error: "no map" });
    const image = await drawMap(ask);
    if (!image) return reply.code(502).send({ error: "map failed" });
    reply.header("content-type", image.type);
    reply.header("cache-control", "public, max-age=86400");
    return reply.send(image.body);
  });

  /** The landing state: what a tab shows before anything is typed —
   *  trending searches, popular videos, or places around the caller. The
   *  client merges its own on-device recents above these. */
  app.get("/search/suggest", async (req, reply) => {
    const q = req.query as Record<string, string | undefined>;
    const vertical = q.vertical ?? "web";
    if (vertical !== "web" && vertical !== "yt" && vertical !== "maps" && vertical !== "shorts") {
      return reply.code(400).send({ error: "bad vertical" });
    }
    const num = (v: string | undefined) => {
      const n = Number(v);
      return Number.isFinite(n) ? n : undefined;
    };
    try {
      const out = await suggest(vertical, {
        country: q.country?.slice(0, 2).toUpperCase(),
        lat: num(q.lat), lon: num(q.lon),
        youtubeToken: vertical === "yt" ? googleToken(q.deviceId) : undefined,
      });
      return { ok: true, ...out };
    } catch (err) {
      req.log.warn({ vertical, err: err instanceof Error ? err.message : String(err) }, "search suggest failed");
      return reply.code(502).send({ ok: false, error: "Suggestions aren't available right now." });
    }
  });

  /** What is actually wired up, without leaking the keys themselves. */
  app.get("/search/status", async () => ({ ok: true, providers: searchProviders() }));
}

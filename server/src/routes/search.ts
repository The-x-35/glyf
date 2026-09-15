import type { FastifyInstance } from "fastify";
import { connKey } from "./connector.js";
import type { KV } from "../lib/store.js";
import { z } from "zod";
import { search, searchProviders } from "../lib/search.js";
import { suggest } from "../lib/suggest.js";

/** The search suite's own endpoint. `/tools/run` stays as it is — glyf chains
 *  consume flat strings — while the keyboard's Search / YouTube / Maps tabs
 *  need typed cards with thumbnails, ratings and durations.
 *
 *  No LLM cost, so runs never touch the plan meter. */

const BodySchema = z.object({
  vertical: z.enum(["web", "yt", "maps"]),
  query: z.string().min(1).max(200),
  deviceId: z.string().min(1).max(80),
  /** Optional coarse location — the containing app asks for permission and
   *  caches it; the keyboard forwards it so "near me" means something. It is
   *  never stored server-side, only used for this request. */
  lat: z.number().min(-90).max(90).optional(),
  lon: z.number().min(-180).max(180).optional(),
  country: z.string().length(2).optional(),
  tz: z.string().max(64).optional(),
});

export function searchRoutes(app: FastifyInstance, kv: KV): void {
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
      req.log.warn({ issues: parsed.error.issues }, "search bad request");
      return reply.code(400).send({ error: "bad request" });
    }
    const { vertical, query, lat, lon, country, tz } = parsed.data;
    try {
      const result = await search(vertical, query, {
        lat, lon, country: country?.toUpperCase(), tz,
      });
      return { ok: true, ...result };
    } catch (err) {
      return reply.code(502).send({
        ok: false,
        error: err instanceof Error ? err.message : "search failed",
      });
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

  /** A static map for a place result (Android draws it; iOS snapshots
   *  MapKit itself). Only two numbers cross the wire — never a caller URL —
   *  and Geoapify's key stays here. No key → 404 and the card keeps its pin. */
  app.get("/search/staticmap", async (req, reply) => {
    const q = req.query as { lat?: string; lon?: string; w?: string; h?: string; dark?: string };
    const lat = Number(q.lat), lon = Number(q.lon);
    const key = process.env.GEOAPIFY_KEY;
    if (!key || !Number.isFinite(lat) || !Number.isFinite(lon)
        || Math.abs(lat) > 90 || Math.abs(lon) > 180) {
      return reply.code(404).send({ error: "no map" });
    }
    const clamp = (v: unknown, lo: number, hi: number, fallback: number) => {
      const n = Math.round(Number(v));
      return Number.isFinite(n) ? Math.min(Math.max(n, lo), hi) : fallback;
    };
    const w = clamp(q.w, 120, 800, 600), h = clamp(q.h, 80, 500, 240);
    const style = q.dark === "1" ? "dark-matter" : "positron";
    const at = `lonlat:${lon.toFixed(6)},${lat.toFixed(6)}`;
    const upstream = await fetch(
      `https://maps.geoapify.com/v1/staticmap?style=${style}&width=${w}&height=${h}` +
      `&center=${at}&zoom=15.5&scaleFactor=2&marker=${at};color:%23ea4335;size:medium&apiKey=${key}`,
      { signal: AbortSignal.timeout(6000) },
    ).catch(() => null);
    if (!upstream?.ok) return reply.code(502).send({ error: "map failed" });
    reply.header("content-type", upstream.headers.get("content-type") ?? "image/png");
    reply.header("cache-control", "public, max-age=86400");
    return reply.send(Buffer.from(await upstream.arrayBuffer()));
  });

  /** The landing state: what a tab shows before anything is typed —
   *  trending searches, popular videos, or places around the caller. The
   *  client merges its own on-device recents above these. */
  app.get("/search/suggest", async (req, reply) => {
    const q = req.query as Record<string, string | undefined>;
    const vertical = q.vertical ?? "web";
    if (vertical !== "web" && vertical !== "yt" && vertical !== "maps") {
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
      return reply.code(502).send({
        ok: false,
        error: err instanceof Error ? err.message : "suggest failed",
      });
    }
  });

  /** What is actually wired up, without leaking the keys themselves. */
  app.get("/search/status", async () => ({ ok: true, providers: searchProviders() }));
}

import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { env } from "../env.js";
import { act } from "../lib/act.js";
import type { Guard } from "../lib/guard.js";
import { createPage, getPage, renderPage } from "../lib/pages.js";
import type { KV } from "../lib/store.js";

/** POST /act — hold space: act on the typed intent (see lib/act.ts).
 *  Metered like a glyf run: it is the user asking the AI to do something. */

const ActSchema = z.object({
  text: z.string().min(1).max(2000),
  deviceId: z.string().min(1).max(80),
  plan: z.enum(["free", "plus", "max"]).default("free"),
  /** Coarse location, forwarded from the app's cached fix; never stored. */
  lat: z.number().min(-90).max(90).optional(),
  lon: z.number().min(-180).max(180).optional(),
  country: z.string().length(2).optional(),
  tz: z.string().max(64).optional(),
  /** Shareable vault details, when the writer allows it (see ActOptions). */
  profile: z.record(z.string().max(40), z.string().max(400)).optional(),
  /** Set when a suggestion chip was tapped: do what the chip said. */
  intent: z.enum(["place", "places", "answer", "video", "rewrite"]).optional(),
});

/** Where shared pages live. Unset in dev → this server, which is enough to
 *  open the link on the same machine; production sets PUBLIC_BASE_URL. */
function pageBase(): string | undefined {
  const base = process.env.PUBLIC_BASE_URL?.replace(/\/+$/, "");
  if (base) return base;
  return process.env.NODE_ENV === "production" ? undefined : `http://127.0.0.1:${env.port}`;
}

export function actRoutes(app: FastifyInstance, guard: Guard, kv: KV): void {
  app.get("/p/:id", async (req, reply) => {
    const page = getPage(kv, (req.params as { id: string }).id);
    if (!page) return reply.code(404).type("text/html").send("<h1>Not found</h1>");
    reply.header("cache-control", "public, max-age=300");
    return reply.type("text/html").send(renderPage(page));
  });

  app.post("/act", async (req, reply) => {
    const parsed = ActSchema.safeParse(req.body);
    if (!parsed.success) {
      // Issues name the bad FIELD; the body is the user's text and stays out of logs.
      req.log.warn({ issues: parsed.error.issues }, "act bad request");
      return reply.code(400).send({ ok: false, error: "Bad request" });
    }
    const { text, deviceId, plan, lat, lon, country, tz, profile, intent } = parsed.data;

    const gate = await guard.spend(req, deviceId);
    if (!gate.ok) return reply.code(429).send({ ok: false, error: gate.message });
    const remaining = gate.remaining;

    const started = Date.now();
    try {
      const base = pageBase();
      const result = await act(text, { lat, lon, country: country?.toUpperCase(), tz }, {
        profile,
        intent,
        publish: base ? (title, places) => `${base}/p/${createPage(kv, title, places)}` : undefined,
      });
      // §12: events and timings only — never the typed text.
      req.log.info({ deviceId, intent: result.intent, provider: result.provider,
        cards: result.cards.length, inputChars: text.length, ms: Date.now() - started }, "act");
      return { ok: true, remaining, ...result };
    } catch (err) {
      req.log.warn({ deviceId, err: err instanceof Error ? err.message : String(err) }, "act failed");
      return reply.code(502).send({ ok: false, error: "Couldn't do that right now. Tap to retry." });
    }
  });
}

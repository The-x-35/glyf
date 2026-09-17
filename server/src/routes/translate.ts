import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { TTLCache } from "../lib/cache.js";
import { translate } from "../lib/translate.js";

/** POST /translate — the translate strip: detects the language, picks the
 *  direction, translates (see lib/translate.ts). It runs on every finished
 *  word, so answers are cached and it is not metered like a run. */

const TranslateSchema = z.object({
  text: z.string().min(1).max(600),
  deviceId: z.string().min(1).max(80),
  primary: z.string().min(2).max(40).default("English"),
  secondary: z.string().min(2).max(40).default("Hindi"),
  target: z.string().min(2).max(40).optional(),
});

export function translateRoutes(app: FastifyInstance): void {
  const cache = new TTLCache(10 * 60_000, 500);

  app.post("/translate", async (req, reply) => {
    const parsed = TranslateSchema.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ ok: false, error: "Bad request" });
    const { text, primary, secondary, target } = parsed.data;
    const key = TTLCache.key(["translate", text.trim(), primary, secondary, target ?? ""]);
    const cached = cache.get(key);
    if (cached) return { ok: true, ...JSON.parse(cached) };
    try {
      const result = await translate({ text, primary, secondary, target });
      cache.set(key, JSON.stringify(result));
      // Events only: never the text.
      req.log.info({ detected: result.detected, target: result.target }, "translate");
      return { ok: true, ...result };
    } catch (err) {
      req.log.warn({ err: err instanceof Error ? err.message : String(err) }, "translate failed");
      return reply.code(502).send({ ok: false, error: "Couldn't translate right now" });
    }
  });
}

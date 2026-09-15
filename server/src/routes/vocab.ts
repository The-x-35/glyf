import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { env } from "../env.js";
import { planCap, type MeterStore } from "../lib/meter.js";
import { generatePack } from "../lib/vocab.js";

/** POST /vocab/generate — words for the keyboard from a description of how
 *  someone writes. Metered like a glyf run. The description is never logged. */
const Body = z.object({
  description: z.string().min(3).max(500),
  deviceId: z.string().min(1).max(80),
  plan: z.enum(["free", "plus", "max"]).default("free"),
});

export function vocabRoutes(app: FastifyInstance, meter: MeterStore): void {
  app.post("/vocab/generate", async (req, reply) => {
    const parsed = Body.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ ok: false, error: "Bad request" });
    const { description, deviceId, plan } = parsed.data;
    const remaining = meter.consume(deviceId, new Date(), planCap(plan, env.freeRunsPerDay));
    if (remaining < 0) {
      return reply.code(429).send({ ok: false, error: plan === "free" ? "Daily free runs used up" : "Daily runs used up" });
    }
    const started = Date.now();
    try {
      const pack = await generatePack(description);
      req.log.info({ deviceId, words: pack.words.length, phrases: pack.phrases.length, ms: Date.now() - started }, "vocab_generate");
      return { ok: true, remaining, ...pack };
    } catch (err) {
      req.log.warn({ deviceId, err: err instanceof Error ? err.message : String(err) }, "vocab_generate failed");
      return reply.code(502).send({ ok: false, error: "Couldn't make words right now. Try again." });
    }
  });
}

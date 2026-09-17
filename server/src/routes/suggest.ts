import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { plan, type ActIntent } from "../lib/act.js";
import { TTLCache } from "../lib/cache.js";

/**
 * POST /suggest — read what someone is typing and say what Glyf could DO
 * about it, in one chip.
 *
 * This is the website's coach, on the phone: the demo watches the thread and
 * points at the one control that finishes the job. Here the same planner that
 * powers hold-space classifies the text, so a question offers to be looked
 * up, a list of places offers a map, and a rough message offers a tidy-up.
 *
 * Rules answer most of it for nothing; the model is only asked when they
 * cannot, and answers are cached, so a pause in typing is cheap.
 */

const SuggestSchema = z.object({
  text: z.string().min(4).max(600),
  deviceId: z.string().min(1).max(80),
});

/** What the chip says, and what the keyboard runs when it is tapped. */
const LABELS: Record<ActIntent, { label: string; action: string }> = {
  place: { label: "Find it on the map", action: "act" },
  places: { label: "Show me places", action: "act" },
  answer: { label: "Look it up", action: "act" },
  video: { label: "Find the video", action: "act" },
  rewrite: { label: "Tidy this up", action: "act" },
};

/** Suggestions are a nicety, never a nag: below this, say nothing. */
function worthSuggesting(text: string, intent: ActIntent): boolean {
  const t = text.trim();
  if (t.length < 8) return false;
  // A half-typed word is not an intent yet.
  if (intent === "rewrite" && t.split(/\s+/).length < 4) return false;
  // "Look it up" only repeated what holding space already does.
  if (intent === "answer") return false;
  return true;
}

export function suggestRoutes(app: FastifyInstance): void {
  const cache = new TTLCache(60_000, 200);   // stores JSON, like the run cache

  app.post("/suggest", async (req, reply) => {
    const parsed = SuggestSchema.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ ok: false, error: "Bad request" });
    const text = parsed.data.text.trim();

    const key = TTLCache.key(["suggest", text.toLowerCase()]);
    const cached = cache.get(key);
    const planned = cached
      ? JSON.parse(cached) as { intent: ActIntent; query: string }
      : await plan(text);
    if (!cached) cache.set(key, JSON.stringify(planned));
    if (!worthSuggesting(text, planned.intent)) {
      return { ok: true, suggestion: null };
    }
    const chip = LABELS[planned.intent];
    // Events only: the text itself never reaches the log.
    req.log.info({ intent: planned.intent }, "suggest");
    return {
      ok: true,
      suggestion: {
        intent: planned.intent,
        label: chip.label,
        action: chip.action,
        query: planned.query.slice(0, 200),
      },
    };
  });
}

import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { planByRules, type ActIntent } from "../lib/act.js";
import type { Guard } from "../lib/guard.js";
import { TTLCache } from "../lib/cache.js";
import { DETAIL_KINDS, detailByRules, type DetailKind } from "../lib/details.js";
import { readTyping } from "../lib/reading.js";

/**
 * POST /suggest — read what someone is typing and say what Glyf could DO
 * about it, in one chip.
 *
 * This is the website's coach, on the phone: the demo watches the thread and
 * points at the one control that finishes the job. A list of places offers a
 * map, a rough message offers a tidy-up, and a sentence heading into one of
 * their own saved details offers it.
 *
 * Rules answer what they can for nothing; otherwise one call to the
 * suggestion chain (SUGGEST_MODELS, small and cheap) reads the sentence.
 * Nobody asked for this read, so it never spends one of their runs: it has
 * its own allowance (Guard.suggest), and only a read by the model counts
 * against it. Tapping the chip is a run.
 */

const SuggestSchema = z.object({
  text: z.string().min(4).max(600),
  deviceId: z.string().min(1).max(80),
  /** Kinds of detail saved in the keyboard's vault. Never the values. */
  kinds: z.array(z.string().max(16)).max(20).optional(),
});

/** What the chip says, and what the keyboard runs when it is tapped. */
const LABELS: Record<ActIntent, { label: string; action: string }> = {
  place: { label: "Find it on the map", action: "act" },
  places: { label: "Show me places", action: "act" },
  answer: { label: "Look it up", action: "act" },
  video: { label: "Find the video", action: "act" },
  rewrite: { label: "Tidy this up", action: "act" },
  write: { label: "Write it for me", action: "act" },
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

type Suggestion = { intent: string; label: string; action: string; query: string; field?: DetailKind } | null;

function suggestionFor(text: string, intent: ActIntent | null, field: DetailKind | null, query = text): Suggestion {
  // About to share one of their own details? The keyboard fills it in.
  if (field) return { intent: "detail", field, label: field, action: "vault", query: "" };
  if (!intent || !worthSuggesting(text, intent)) return null;
  const chip = LABELS[intent];
  return { intent, label: chip.label, action: chip.action, query: query.slice(0, 200) };
}

export function suggestRoutes(app: FastifyInstance, guard: Guard): void {
  const cache = new TTLCache(60_000, 200);   // stores JSON, like the run cache

  app.post("/suggest", async (req, reply) => {
    const parsed = SuggestSchema.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ ok: false, error: "Bad request" });
    const text = parsed.data.text.trim();
    const kinds = [...new Set(parsed.data.kinds ?? [])].filter((k): k is DetailKind =>
      (DETAIL_KINDS as readonly string[]).includes(k)).sort();

    const key = TTLCache.key(["suggest", text.toLowerCase(), kinds.join(",")]);
    const hit = cache.get(key);
    let suggestion: Suggestion;
    if (hit !== undefined) {
      suggestion = JSON.parse(hit) as Suggestion;
    } else {
      const field = detailByRules(text, kinds);
      const byRules = field ? null : planByRules(text);
      if (field || byRules) {
        suggestion = suggestionFor(text, byRules?.intent ?? null, field, byRules?.query);
      } else {
        const gate = await guard.suggest(req, parsed.data.deviceId);
        if (!gate.ok) return reply.code(429).send({ ok: false, error: gate.message });
        const read = await readTyping(text, kinds);
        suggestion = suggestionFor(text, read?.intent ?? null, read?.field ?? null);
      }
      cache.set(key, JSON.stringify(suggestion));
    }
    // Events only: the text itself never reaches the log.
    if (suggestion) req.log.info({ intent: suggestion.intent, field: suggestion.field }, "suggest");
    return { ok: true, suggestion };
  });
}

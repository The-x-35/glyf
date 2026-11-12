import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { checkPlan, localAsk, needsTidy, planByRules, readsTidy, roughEnough, type ActIntent } from "../lib/act.js";
import { rightNow } from "../lib/answers.js";
import type { Guard } from "../lib/guard.js";
import { TTLCache } from "../lib/cache.js";
import { DETAIL_KINDS, detailNamed, type DetailKind } from "../lib/details.js";
import { readTyping } from "../lib/reading.js";
import { mayAct, type Action } from "../lib/actions.js";

/**
 * POST /suggest — read what someone is typing and say what Glyf could DO
 * about it, in one chip.
 *
 * This is the website's coach, on the phone: the demo watches the thread and
 * points at the one control that finishes the job. A list of places offers a
 * map, a rough message offers a tidy-up, and a sentence heading into one of
 * their own saved details offers it.
 *
 * Rules answer what they can for nothing, "Tidy this up" included (a
 * message full of shorthand needs no model to say so); otherwise one call
 * to the suggestion chain (small and cheap) reads the sentence.
 * Nobody asked for this read, so it never spends one of their runs: it has
 * its own allowance (Guard.suggest), and only a read by the model counts
 * against it. Tapping the chip is a run.
 */

const SuggestSchema = z.object({
  text: z.string().min(4).max(600),
  deviceId: z.string().min(1).max(80),
  /** Kinds of detail saved in the keyboard's vault. Never the values. */
  kinds: z.array(z.string().max(16)).max(20).optional(),
  /** A phone that can open a tool prefilled (lib/actions.ts). Old phones
   *  never send it, and get exactly the answers they always did. */
  actions: z.boolean().optional(),
});

/** What the chip says, and what the keyboard runs when it is tapped. */
const LABELS: Record<ActIntent, { label: string; action: string }> = {
  place: { label: "Find it on the map", action: "act" },
  places: { label: "Show me places", action: "act" },
  // A question, with or without its "?": the AI answers it (Arpit,
  // 2026-09-29: "have a strip like ai answer ? on all questions type").
  answer: { label: "AI answer", action: "act" },
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
  // Already tidy: nothing to offer.
  if (intent === "rewrite" && (readsTidy(t) || !roughEnough(t))) return false;
  // Today's score or the news: the AI can't know, so no chip that would
  // only say "Nothing found".
  if (intent === "answer" && rightNow(t)) return false;
  // Asked of someone where the writer is ("is the store open", "whats the
  // wifi password"): no AI chip, whatever the model read (audit, 2026-10-01).
  if (intent === "answer" && localAsk(t)) return false;
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

    const wantsActions = parsed.data.actions === true;
    const key = TTLCache.key(["suggest", text.toLowerCase(), kinds.join(","), wantsActions ? "a" : ""]);
    const hit = cache.get(key);
    let suggestion: Suggestion;
    let action: Action | null = null;
    if (hit !== undefined) {
      if (wantsActions) ({ suggestion, action } = JSON.parse(hit) as { suggestion: Suggestion; action: Action | null });
      else suggestion = JSON.parse(hit) as Suggestion;
    } else {
      const named = detailNamed(text);
      const field = named && kinds.includes(named) ? named : null;
      let asked = false;
      const byRules = field ? null : planByRules(text);
      if (field || byRules) {
        suggestion = suggestionFor(text, byRules?.intent ?? null, field, byRules?.query);
      } else if (named) {
        // The words ask for a detail this person never saved ("my sol
        // address is", no wallet): nothing to offer, and no model guessing
        // their home address instead.
        suggestion = null;
      } else if (needsTidy(text)) {
        suggestion = suggestionFor(text, "rewrite", null);
      } else {
        const gate = await guard.suggest(req, parsed.data.deviceId);
        if (!gate.ok) return reply.code(429).send({ ok: false, error: gate.message });
        const read = await readTyping(text, kinds, wantsActions);
        // The same second look hold space gives the router's word: "can u
        // send me the invoice" is a message to tidy, not something to write.
        const intent = read?.intent ? checkPlan({ intent: read.intent, query: text }, text).intent : null;
        suggestion = suggestionFor(text, intent, read?.field ?? null);
        action = read?.action ?? null;
        asked = true;
      }
      // The rules had a chip, but the words may still be a tool's job ("can
      // we do dinner fri 8pm" reads as a message to tidy, and is a plan).
      if (wantsActions && !asked && !field && !named && mayAct(text)) {
        const gate = await guard.suggest(req, parsed.data.deviceId);
        if (gate.ok) action = (await readTyping(text, kinds, true))?.action ?? null;
      }
      cache.set(key, JSON.stringify(wantsActions ? { suggestion, action } : suggestion));
    }
    // Events only: the text itself never reaches the log.
    if (suggestion || action) req.log.info({ intent: suggestion?.intent, field: suggestion?.field, tool: action?.tool }, "suggest");
    return wantsActions ? { ok: true, suggestion, action } : { ok: true, suggestion };
  });
}

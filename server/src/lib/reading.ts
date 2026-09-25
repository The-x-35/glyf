import { completeStreaming } from "../providers/openrouter.js";
import { env } from "../env.js";
import { ACT_INTENTS, mockPlan, type ActIntent } from "./act.js";
import { asksForTheirs, type DetailKind } from "./details.js";

/**
 * What the strip's chip reads when the rules can't say: one call to the
 * suggestion chain (SUGGEST_MODELS), a few words of JSON back.
 *
 * Both questions go in the same call: what would Glyf do with the sentence,
 * and is it leading into one of the person's own saved details. Asked apart
 * they cost two calls a pause; the kinds are sent, never the values.
 */

export interface Reading {
  intent: ActIntent | null;
  field: DetailKind | null;
}

export const READING_PROMPT = (text: string, kinds: readonly string[]) =>
  `Someone paused while typing on their phone keyboard. Say what would help most with what they typed.
Reply with one line of JSON and nothing else, like {"intent":"rewrite"${kinds.length ? `,"field":"none"` : ""}}
intent is one of:
place: they name one specific place to share, "lets meet at Blue Tokai Indiranagar"
places: they want options or recommendations, "any good italian places in koramangala"
answer: it needs a live fact: scores, schedules, prices, news, "who is"
video: they mention a video, song or trailer
write: they ask for something to be written or worked out, "write a birthday message for my mom"
rewrite: an ordinary message to someone, nothing to look up${kinds.length ? `
field: one of ${kinds.join(", ")} when the message leads straight into sharing their OWN one ("drop it off at", "here's how to reach me", "pay me on"), else "none". Asking someone for theirs is "none"` : ""}
Typed: """${text.replace(/"""/g, "'")}"""`;

/** The first JSON object in a reply, checked against what can be offered.
 *  Null when it names nothing usable: then there is no chip. */
export function parseReading(reply: string, text: string, kinds: readonly DetailKind[]): Reading | null {
  const match = reply.match(/\{[\s\S]*?\}/);
  if (!match) return null;
  try {
    const obj = JSON.parse(match[0]) as { intent?: unknown; field?: unknown };
    const intent = typeof obj.intent === "string" && ACT_INTENTS.includes(obj.intent as ActIntent)
      ? obj.intent as ActIntent : null;
    const named = typeof obj.field === "string" ? obj.field.toLowerCase() : "";
    const field = (kinds as readonly string[]).includes(named) && !asksForTheirs(text)
      ? named as DetailKind : null;
    return intent || field ? { intent, field } : null;
  } catch {
    return null;
  }
}

/** Null when no model answered in time or said nothing usable: a chip is a
 *  guess worth showing only when something actually made it. */
export async function readTyping(text: string, kinds: readonly DetailKind[]): Promise<Reading | null> {
  if (env.mockAI) return { intent: mockPlan(text).intent, field: null };
  try {
    const res = await completeStreaming("suggest",
      [{ role: "user", content: READING_PROMPT(text, kinds) }], { onToken: () => {}, stallMs: 2500 });
    return parseReading(res.text, text, kinds);
  } catch {
    return null;
  }
}

import { completeStreaming } from "../providers/openrouter.js";
import { env } from "../env.js";
import { ACT_INTENTS, mockPlan, type ActIntent } from "./act.js";
import { asksForTheirs, type DetailKind } from "./details.js";
import { ACTION_GUIDE, checkAction, groundAction, mockAction, type Action } from "./actions.js";

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
  /** A tool to open with values filled in (lib/actions.ts), only when the
   *  phone asked for actions. */
  action?: Action | null;
}

export const READING_PROMPT = (text: string, kinds: readonly string[], actions = false) =>
  `Someone paused while typing on their phone keyboard. Say what would help most with what they typed.
Reply with one line of JSON and nothing else, like {"intent":"rewrite"${kinds.length ? `,"field":"none"` : ""}}${actions
    ? ` or {"intent":"rewrite","action":{"tool":"meet.link","params":{}}}` : ""}
intent is one of:
place: they name one specific place to share, "lets meet at Blue Tokai Indiranagar"
places: they want options or recommendations, "any good italian places in koramangala"
answer: a question for a fact or an explanation, with or without a question mark: "who is the ceo of tesla", "why is the sky blue", "how many ounces in a cup" (a question to the person they are writing to is rewrite)
video: they want a video, song or trailer found, "dune part 2 trailer"
write: they ask for something to be written or worked out, "write a birthday message for my mom"
rewrite: an ordinary message to someone, even one that mentions food, a video, a place or the weather ("had a great dinner with u, thanks", "did u see the video i sent"), nothing to look up${kinds.length ? `
field: one of ${kinds.join(", ")} when the message leads straight into sharing their OWN one ("drop it off at", "here's how to reach me", "pay me on"), else "none". Asking someone for theirs is "none"` : ""}${actions ? `\n${ACTION_GUIDE}` : ""}
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

/** The first whole JSON object in a reply, nested ones included. */
export function firstObject(reply: string): string | null {
  const start = reply.indexOf("{");
  if (start < 0) return null;
  let depth = 0;
  let quoted = false;
  for (let i = start; i < reply.length; i++) {
    const ch = reply[i];
    if (quoted) {
      if (ch === "\\") i++;
      else if (ch === '"') quoted = false;
    } else if (ch === '"') quoted = true;
    else if (ch === "{") depth++;
    else if (ch === "}" && --depth === 0) return reply.slice(start, i + 1);
  }
  return null;
}

/** parseReading plus the action, checked (an invalid one is dropped, the
 *  rest of the reading kept). */
export function parseActionReading(reply: string, text: string, kinds: readonly DetailKind[]): Reading | null {
  const json = firstObject(reply);
  if (!json) return null;
  let obj: { intent?: unknown; field?: unknown; action?: unknown };
  try { obj = JSON.parse(json); } catch { return null; }
  const action = groundAction(checkAction(obj.action), text);
  const base = parseReading(JSON.stringify({ intent: obj.intent, field: obj.field }), text, kinds);
  if (!base && !action) return null;
  return { intent: base?.intent ?? null, field: base?.field ?? null, action };
}

/** Null when no model answered in time or said nothing usable: a chip is a
 *  guess worth showing only when something actually made it. */
export async function readTyping(text: string, kinds: readonly DetailKind[], actions = false): Promise<Reading | null> {
  if (env.mockAI) {
    const reading: Reading = { intent: mockPlan(text).intent, field: null };
    return actions ? { ...reading, action: mockAction(text) } : reading;
  }
  try {
    const res = await completeStreaming("suggest",
      [{ role: "user", content: READING_PROMPT(text, kinds, actions) }], { onToken: () => {}, stallMs: 2500 });
    return actions ? parseActionReading(res.text, text, kinds) : parseReading(res.text, text, kinds);
  } catch {
    return null;
  }
}

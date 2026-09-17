import { completeStreaming } from "../providers/openrouter.js";
import { env } from "../env.js";

/**
 * Is the person about to type one of their own saved details?
 *
 * The keyboard keeps the vault; the server never sees a value. It gets the
 * sentence being typed (the same text every suggestion reads) and the KINDS of
 * detail this person saved, and names the kind the sentence is leading into.
 * The keyboard then offers its own saved value in the strip.
 *
 * Words first: "here's my number", "gpay me on", "ship it to". The model is
 * only asked when the words are not enough, and only about kinds they saved.
 */

export const DETAIL_KINDS = ["address", "phone", "email", "upi", "name", "wallet", "link", "social", "gst"] as const;
export type DetailKind = typeof DETAIL_KINDS[number];

/** First-person phrasing only: "what's your address?" asks someone else. */
const RULES: [RegExp, DetailKind][] = [
  [/\b(my|our)\s+(home\s+|delivery\s+|shipping\s+|office\s+|current\s+)?(address|addy|location)\b/, "address"],
  [/\b(ship|deliver|send|courier|post)\s+(it|them|the\s+\w+|this)?\s*(to|at)\s*:?\s*$/, "address"],
  [/\b(i\s+(live|stay)\s+(at|in)|come\s+(over\s+)?to|pick\s+me\s+up\s+(from|at))\s*:?\s*$/, "address"],
  [/\b(my|our)\s+(phone|mobile|cell|contact|whatsapp)?\s*(number|no\.?|num)\b/, "phone"],
  [/\b(call|text|whatsapp|ping|reach)\s+me\s+(on|at)\s*:?\s*$/, "phone"],
  [/\b(my|our)\s+(e-?mail|mail\s*id|gmail)\b/, "email"],
  [/\b(e-?mail|mail)\s+me\s+(on|at)\s*:?\s*$/, "email"],
  [/\b(my|our)\s+(upi|vpa|gpay|google\s+pay|phonepe|paytm)(\s+(id|number|handle))?\b/, "upi"],
  [/\b(gpay|google\s+pay|phonepe|paytm|upi|pay|transfer|send\s+(the\s+)?(money|amount|it))\s+(me\s+)?(on|at|to)\s*:?\s*$/, "upi"],
  [/\b(my\s+name\s+is|i\s+am\s+called|this\s+is|name\s*:)\s*$/, "name"],
  [/\b(my|our)\s+(sol(ana)?|crypto|usdc|phantom)?\s*wallet(\s+address)?\b/, "wallet"],
  [/\b(my|our)\s+(website|portfolio|site|link|calendly)\b/, "link"],
  [/\b(my|our)\s+(insta(gram)?|ig|twitter|x\s+handle|linkedin|handle)\b/, "social"],
  [/\b(my|our)\s+gst(in)?(\s+(number|no\.?))?\b|\bgst(in)?\s*(number|no\.?)?\s*(is|:)\s*$/, "gst"],
];

/** The last clause, where the sentence is going. */
function lastClause(text: string): string {
  const parts = text.toLowerCase().split(/[.!?\n]/);
  return (parts[parts.length - 1] ?? "").trim();
}

export function detailByRules(text: string, kinds: readonly string[]): DetailKind | null {
  const clause = lastClause(text);
  if (!clause || /\b(your|ur|his|her|their)\b/.test(clause.split(/\s+/).slice(-6).join(" "))) return null;
  for (const [re, kind] of RULES) {
    const m = re.exec(clause);
    if (!m || !kinds.includes(kind)) continue;
    // The detail has not been typed yet: little after the phrase.
    const after = clause.slice(m.index + m[0].length).replace(/^[\s:,-]*(is|are|=)?[\s:,-]*/, "");
    if (after.length <= 3) return kind;
  }
  return null;
}

export async function detailByModel(text: string, kinds: readonly DetailKind[]): Promise<DetailKind | null> {
  if (env.mockAI || kinds.length === 0) return null;
  const prompt = "[[suggest.detail]]\n" +
    "Someone is typing a message on their phone. Decide whether the next thing they will type is " +
    "one of their OWN details from this list: " + kinds.join(", ") + ".\n" +
    "Only name one when the message clearly leads into sharing it (\"sure, send it to\", " +
    "\"here's how to reach me\", \"you can pay me on\"). A question to someone else is not one. " +
    "Reply with JSON only: {\"field\":\"<one of the list, or none>\"}\n\nMessage: " + text;
  try {
    const res = await completeStreaming("fast", [{ role: "user", content: prompt }],
      { onToken: () => {}, stallMs: 3000 });
    const m = res.text.match(/"field"\s*:\s*"([a-z]+)"/i);
    const field = m?.[1]?.toLowerCase();
    return field && (kinds as readonly string[]).includes(field) ? field as DetailKind : null;
  } catch {
    return null;
  }
}

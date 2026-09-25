import { completeStreaming } from "../providers/openrouter.js";
import { env } from "../env.js";

/**
 * AI-made vocabulary packs: someone describes how they write ("cardiologist
 * in Pune, texts in Hinglish, plays BGMI") and gets words for the keyboard to
 * know — spelled the way they'd type them — to review before saving. Only
 * the description is sent; nothing typed ever is.
 */

export interface VocabPack {
  name: string;
  words: string[];
  phrases: string[];
}

const MAX_WORDS = 150;
const MAX_PHRASES = 20;

/** A word the keyboard can hold: letters (any script), apostrophes, hyphens,
 *  dots inside abbreviations, at most two spaces. No digits-only tokens,
 *  no URLs, no emails. */
export function cleanWord(raw: unknown): string | null {
  if (typeof raw !== "string") return null;
  const w = raw.normalize("NFC").trim().replace(/\s+/g, " ");
  if (!w || w.length > 32) return null;
  if (/[@/:\\#<>{}\[\]|=+*"`^~$%]/.test(w)) return null;
  if (!/\p{L}/u.test(w)) return null;
  if ((w.match(/ /g) ?? []).length > 2) return null;
  return w;
}

export function cleanPhrase(raw: unknown): string | null {
  if (typeof raw !== "string") return null;
  const p = raw.normalize("NFC").trim().replace(/\s+/g, " ");
  if (!p || p.length > 60 || !p.includes(" ")) return null;
  if (/[@/:\\#<>{}\[\]|=+*"`^~$%]/.test(p) || !/\p{L}/u.test(p)) return null;
  return p;
}

type RawPack = { name?: unknown; words?: unknown; phrases?: unknown };

function parseObject(reply: string): RawPack | null {
  const match = reply.match(/\{[\s\S]*\}/);
  if (!match) return null;
  try {
    return JSON.parse(match[0]);
  } catch {
    return null;
  }
}

/** A reply the length limit cut off mid-list is still mostly words: keep
 *  every complete string in the lists it reached. */
function salvage(reply: string): RawPack | null {
  const list = (key: string): string[] => {
    const start = reply.search(new RegExp(`"${key}"\\s*:\\s*\\[`));
    if (start < 0) return [];
    const rest = reply.slice(reply.indexOf("[", start) + 1);
    const end = rest.indexOf("]");
    const body = end >= 0 ? rest.slice(0, end) : rest;
    const out: string[] = [];
    for (const m of body.matchAll(/"((?:[^"\\\n]|\\.)*)"/g)) {
      try {
        out.push(JSON.parse(`"${m[1]}"`));
      } catch {
        // a broken escape: skip that one
      }
    }
    return out;
  };
  const words = list("words");
  if (words.length === 0) return null;
  const name = reply.match(/"name"\s*:\s*"((?:[^"\\\n]|\\.)*)"/)?.[1];
  return { name, words, phrases: list("phrases") };
}

/** Pulls the pack out of a model reply, keeping only what a keyboard can use. */
export function parsePack(reply: string, fallbackName: string): VocabPack | null {
  const obj = parseObject(reply) ?? salvage(reply);
  if (!obj) return null;
  const seen = new Set<string>();
  const words: string[] = [];
  for (const raw of Array.isArray(obj.words) ? obj.words : []) {
    const w = cleanWord(raw);
    if (!w || seen.has(w.toLowerCase())) continue;
    seen.add(w.toLowerCase());
    words.push(w);
    if (words.length === MAX_WORDS) break;
  }
  const phrases: string[] = [];
  for (const raw of Array.isArray(obj.phrases) ? obj.phrases : []) {
    const p = cleanPhrase(raw);
    if (p && !phrases.includes(p)) phrases.push(p);
    if (phrases.length === MAX_PHRASES) break;
  }
  if (words.length === 0) return null;
  const name = typeof obj.name === "string" && obj.name.trim() ? obj.name.trim().slice(0, 32) : fallbackName;
  return { name, words, phrases };
}

const PROMPT = (description: string) => `Someone describes how they write on their phone. List words their keyboard must know so it never "corrects" them away and can suggest them.
Include: jargon, names of tools, brands, places, slang, and words from other languages they mix in — spelled exactly how they would type them in Latin letters (e.g. Hinglish "acha", "yaar").
Skip common English words any dictionary has.
Reply with JSON only: {"name": "2-3 word pack name", "words": ["..."], "phrases": ["short phrases they often type"]}
Up to ${MAX_WORDS} words, ${MAX_PHRASES} phrases.
Description: """${description.replace(/"""/g, "'")}"""`;

export async function generatePack(description: string): Promise<VocabPack> {
  const fallbackName = description.trim().split(/\s+/).slice(0, 3).join(" ").slice(0, 32) || "My words";
  if (env.mockAI) {
    // Offline tests: the description's own longer words, deterministically.
    const words = [...new Set(description.split(/[^\p{L}'-]+/u).filter(w => w.length > 3))];
    return { name: fallbackName, words: words.length ? words : ["glyf"], phrases: [] };
  }
  const res = await completeStreaming("fast", [{ role: "user", content: PROMPT(description) }], { onToken: () => {} });
  const pack = parsePack(res.text, fallbackName);
  if (!pack) throw new Error("no usable words");
  return pack;
}

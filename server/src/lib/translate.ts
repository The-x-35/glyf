import { env } from "../env.js";
import { completeStreaming } from "../providers/openrouter.js";

/**
 * Translate the way Google Translate does on a phone: nobody picks the source
 * language, and nobody should have to pick the target every time either.
 *
 * The keyboard sends the two languages the person uses (the phone's first
 * language and their other one). Whatever they type is detected; text in the
 * first language goes to the other one, anything else comes back to the
 * first. Tapping the direction on the strip sends an explicit target instead.
 */

export interface TranslateRequest {
  text: string;
  /** The phone's first language, e.g. "English". */
  primary: string;
  /** The person's other language, e.g. "Hindi". */
  secondary: string;
  /** Set when the person flipped the direction by hand. */
  target?: string;
}

export interface TranslateResult {
  detected: string;
  target: string;
  translation: string;
}

/** Scripts that name their language outright, so no model is needed to tell. */
const SCRIPTS: [RegExp, string][] = [
  [/[ऀ-ॿ]/, "Hindi"],
  [/[ঀ-৿]/, "Bengali"],
  [/[਀-੿]/, "Punjabi"],
  [/[઀-૿]/, "Gujarati"],
  [/[஀-௿]/, "Tamil"],
  [/[ఀ-౿]/, "Telugu"],
  [/[ಀ-೿]/, "Kannada"],
  [/[ഀ-ൿ]/, "Malayalam"],
  [/[؀-ۿ]/, "Arabic"],
  [/[Ѐ-ӿ]/, "Russian"],
  [/[぀-ヿ]/, "Japanese"],
  [/[가-힯]/, "Korean"],
  [/[一-鿿]/, "Chinese"],
  [/[฀-๿]/, "Thai"],
  [/[Ͱ-Ͽ]/, "Greek"],
  [/[֐-׿]/, "Hebrew"],
];

export function scriptLanguage(text: string): string | null {
  for (const [re, name] of SCRIPTS) if (re.test(text)) return name;
  return null;
}

/** The direction, given what was detected. */
export function chooseTarget(detected: string, req: TranslateRequest): string {
  if (req.target) return req.target;
  return detected.toLowerCase() === req.primary.toLowerCase() ? req.secondary : req.primary;
}

const PROMPT = (req: TranslateRequest) => req.target ? `[[translate:to]]
Translate the message into ${req.target}, whatever language it is in. Romanised Hindi or Hinglish counts as Hindi. Keep the tone and register. Write the translation in the target language's own script (Hindi in Devanagari).
Reply with JSON only: {"detected":"<language of the message, in English>","target":"${req.target}","translation":"<the ${req.target} translation>"}

Message:
${req.text}` : `[[translate:auto]]
Detect the language of the message. If it is ${req.primary}, translate it into ${req.secondary}. Otherwise translate it into ${req.primary}.
Romanised Hindi or Hinglish counts as Hindi. Keep the tone and register. Write the translation in the target language's own script (Hindi in Devanagari).
Reply with JSON only: {"detected":"<language name in English>","target":"<language name in English>","translation":"<the translation>"}

Message:
${req.text}`;

/** "Hindi (Hinglish)", "Romanized Hindi", "hinglish" are all Hindi on the
 *  strip; "Chinese (Simplified)" is Chinese. */
export function languageName(raw: string): string {
  const name = raw.replace(/\(.*?\)/g, " ").replace(/\s+/g, " ").trim();
  if (/hinglish|roman(i[sz]ed)? hindi/i.test(raw)) return "Hindi";
  return name.charAt(0).toUpperCase() + name.slice(1);
}

export function parseTranslation(reply: string, req: TranslateRequest): TranslateResult | null {
  const match = reply.match(/\{[\s\S]*\}/);
  if (!match) return null;
  try {
    const obj = JSON.parse(match[0]) as Partial<TranslateResult>;
    if (typeof obj.translation !== "string" || !obj.translation.trim()) return null;
    const detected = typeof obj.detected === "string" && obj.detected.trim()
      ? languageName(obj.detected) : "Unknown";
    return {
      detected,
      // A direction picked by hand is the direction, whatever the model says.
      target: req.target ?? (typeof obj.target === "string" && obj.target.trim()
        ? languageName(obj.target) : chooseTarget(detected, req)),
      translation: obj.translation.trim(),
    };
  } catch {
    return null;
  }
}

export async function translate(req: TranslateRequest): Promise<TranslateResult> {
  const text = req.text.trim();
  if (env.mockAI) {
    const detected = scriptLanguage(text) ?? "English";
    const target = chooseTarget(detected, req);
    return { detected, target, translation: `[${target}] ${text}` };
  }
  const res = await completeStreaming("fast", [{ role: "user", content: PROMPT({ ...req, text }) }],
    { onToken: () => {}, stallMs: 4000 });
  const parsed = parseTranslation(res.text, req);
  if (!parsed) throw new Error("translation unreadable");
  // A script that names its language beats the model's guess.
  const script = scriptLanguage(text);
  if (script && !req.target) {
    parsed.detected = script;
    parsed.target = chooseTarget(script, req);
  }
  return parsed;
}

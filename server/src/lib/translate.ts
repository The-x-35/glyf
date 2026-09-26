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

/** Words that only romanised Hindi uses (never "to", "do", "main"). */
const HINGLISH = new Set(("hai hain hoon hu tha thi kya kyu kyun nahi nahin haan mein mujhe tujhe tum aap hum " +
  "yaar bhai kal aaj parso abhi baad pehle karo karna karne kar gaya gayi raha rahi rahe wala wali wale ke ka " +
  "ki ko se bhi toh ek kuch kaise kaisa kahan kab kaun accha acha theek thik chalo milte milenge milna baje " +
  "shaam subah raat ghar khana jaldi bahut bohot sab apna apni mera meri tera teri uska uski woh wo yeh ye " +
  "lekin aur magar phir fir kyunki jab tab bas chahiye sakta sakti sakte lagta dekho bolo batao pata aana jana").split(" "));
const ENGLISH = new Set(("the a an is are was were am be been to of and in on at for with you your i we they he " +
  "she it this that will can would should have has had does did not see after before tomorrow today tonight " +
  "meeting please thanks thank what when where how why just about there here my me our them").split(" "));

/** English or romanised Hindi, told from the words themselves; null when
 *  the words don't say (Spanish, French…), and the model decides. The
 *  model alone read "kal milte hain" as English one time in three. */
export function latinLanguage(text: string): "English" | "Hindi" | null {
  const words = text.toLowerCase().match(/[a-z']+/g) ?? [];
  let hindi = 0;
  let english = 0;
  for (const w of words) {
    if (HINGLISH.has(w)) hindi++;
    else if (ENGLISH.has(w)) english++;
  }
  if (hindi >= 2 && hindi > english) return "Hindi";
  if (english >= 2 && english >= 2 * hindi) return "English";
  return null;
}

/** The direction, given what was detected. */
export function chooseTarget(detected: string, req: TranslateRequest): string {
  if (req.target) return req.target;
  return detected.toLowerCase() === req.primary.toLowerCase() ? req.secondary : req.primary;
}

const PROMPT = (req: TranslateRequest) => req.target ? `[[translate:to]]
Translate the message into ${req.target}, whatever language it is in. Romanised Hindi or Hinglish counts as Hindi. Keep the tone and register, and leave nothing out: time words too ("kal" with a future verb is tomorrow). When the translation is into Hindi, write it in Devanagari script.
Reply with JSON only: {"detected":"<language of the message, in English>","target":"${req.target}","translation":"<the ${req.target} translation>"}

Message:
${req.text}` : `[[translate:auto]]
Detect the language of the message. If it is ${req.primary}, translate it into ${req.secondary}. Otherwise translate it into ${req.primary}.
Romanised Hindi or Hinglish counts as Hindi. Keep the tone and register, and leave nothing out: time words too ("kal" with a future verb is tomorrow). When the translation is into Hindi, write it in Devanagari script.
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
  // A script, or words, that name the language decide the direction here;
  // the model is then only asked to translate into it.
  const known = scriptLanguage(text) ?? latinLanguage(text);
  const target = req.target ?? (known ? chooseTarget(known, req) : undefined);
  const asked = { ...req, text, target };
  const res = await completeStreaming("fast", [{ role: "user", content: PROMPT(asked) }],
    { onToken: () => {}, stallMs: 4000 });
  const parsed = parseTranslation(res.text, asked);
  if (!parsed) throw new Error("translation unreadable");
  if (known && !req.target) {
    parsed.detected = known;
    parsed.target = target as string;
  }
  return parsed;
}

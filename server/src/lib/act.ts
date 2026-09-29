import { AsyncLocalStorage } from "node:async_hooks";
import { completeStreaming } from "../providers/openrouter.js";
import { env } from "../env.js";
import { daysAsked, isLive, liveAsk, moneyAsked, rightNow } from "./answers.js";
import { asksForTheirs } from "./details.js";
import { search, type SearchContext } from "./search.js";
import { composeInsert, type AnswerCard, type PlaceCard, type SearchCard } from "./searchcards.js";
import { NAMES, Rates } from "./rates.js";
import { latinLanguage, otherLatinLanguage, scriptLanguage } from "./translate.js";
import { convertUnits } from "./units.js";

/** A run is paid for the first time a request asks the model, and only
 *  then: a sum, a conversion, a price, the time, the weather or a place list
 *  asks no model and costs nothing ("2+5" spent one of the day's runs).
 *  routes/act.ts hands each request its payment; tests run without one. */
const billing = new AsyncLocalStorage<() => Promise<void>>();

/** Thrown when the model is needed and no run is left today. */
export class RunRefused extends Error {}

async function payForModel(): Promise<void> {
  await billing.getStore()?.();
}

/**
 * Hold space → act on what the user typed (the Acti Bar move, Glyf's way).
 *
 * The typed text IS the intent: "Times Square Starbucks" should come back as
 * a place, "SF best italian restaurant" as a short list, "World Cup today" as
 * an answer, "lofi beats" as a video, and an ordinary message as a cleaner
 * version of itself. Obvious intents are routed by rules and never pay for a
 * model call; the rest get one fast, JSON-only routing call.
 *
 * Everything shown comes from a real lookup through the search providers or
 * a model rewrite of the user's own words — never an invented fact. When no
 * provider can answer, the result is an honest "see it on Google" card.
 */

export type ActIntent = "place" | "places" | "answer" | "video" | "rewrite" | "write";
export const ACT_INTENTS: readonly ActIntent[] = ["place", "places", "answer", "video", "rewrite", "write"];

export interface ActPlan {
  intent: ActIntent;
  /** What to look up — the typed text, tidied. */
  query: string;
}

export interface ActResult {
  intent: ActIntent;
  /** Header over the result: a place name, the list topic, "Rewrite". */
  title: string;
  /** Cards the keyboard renders with the search suite's own rows. */
  cards: SearchCard[];
  /** Prose result (rewrite, answer summary), when there is one. */
  text?: string;
  /** What Insert drops into the field, replacing the typed intent. */
  insert: string;
  /** Live mini-app page for a list result, when one was published. */
  page?: string;
  /** A rewrite comes back as several versions, the website's rows. */
  options?: RewriteOption[];
  provider: string;
}

export interface RewriteOption {
  id: string;
  label: string;
  text: string;
}

/** The versions a rewrite offers, in the order the rows show them. Hinglish
 *  only where people write it. */
export function rewriteStyles(ctx: SearchContext): { id: string; label: string; how: string }[] {
  const styles = [
    { id: "basic", label: "Basic", how: "the same message written properly: capital letters, punctuation, spelling and grammar fixed, and texting shorthand spelled out (u → you, pls → please, cant → can't, sooo → so); keep their words, tone and any emoji" },
    { id: "work", label: "Professional", how: "professional and clear, for work" },
    { id: "polite", label: "Polite", how: "warm and courteous" },
    { id: "shorter", label: "Shorter", how: "at most half as long and under 30 words, one or two short sentences, keeping every fact" },
    { id: "emoji", label: "Emoji", how: "the basic version, friendly, with a few emoji that fit added" },
  ];
  const indian = ctx.country === "IN" || ctx.tz === "Asia/Kolkata" || ctx.tz === "Asia/Calcutta";
  if (indian) styles.splice(4, 0, { id: "hinglish", label: "Hinglish", how: "casual Hinglish in Roman script" });
  return styles;
}

/** One finished `"style":"text"` pair in a model's JSON, open or closed. */
const PAIR = /"([a-z]+)"\s*:\s*"((?:[^"\\]|\\.)*)"/g;

/** Reads the model's JSON of versions; missing or empty ones are dropped. A
 *  reply cut off before its closing brace still gives the versions it
 *  finished, the same ones a stream of it showed. */
export function parseRewriteOptions(reply: string, styles: { id: string; label: string }[]): RewriteOption[] {
  let obj: Record<string, unknown> = {};
  const match = reply.match(/\{[\s\S]*\}/);
  try {
    obj = match ? JSON.parse(match[0]) as Record<string, unknown> : {};
  } catch {
    obj = {};
  }
  if (Object.keys(obj).length === 0 && reply.includes("{")) {
    for (const m of reply.matchAll(PAIR)) {
      try {
        obj[m[1]] ??= JSON.parse(`"${m[2]}"`) as string;
      } catch {
        // A pair the model mangled is one version fewer, not an error.
      }
    }
  }
  return styles
    .map(st => ({ id: st.id, label: st.label, text: typeof obj[st.id] === "string" ? unmarked(obj[st.id] as string) : "" }))
    .filter(o => o.text.length > 0);
}

/** A version as it is sent: no markdown emphasis around words. */
function unmarked(text: string): string {
  return text.replace(/\*\*([^*\n]+)\*\*/g, "$1").replace(/__([^_\n]+)__/g, "$1").trim();
}

/** Picks each version out of the model's JSON the moment its closing quote
 *  arrives, so the rows appear one by one while the rest is still being
 *  written. Only what the full reply would keep is let through: a style
 *  that was asked for, not empty, with every number the writer typed. */
export class OptionStream {
  private text = "";
  private from = 0;
  private readonly sent = new Set<string>();

  constructor(
    private readonly styles: { id: string; label: string }[],
    private readonly typed: string,
    private readonly emit: (o: RewriteOption) => void,
  ) {}

  push(token: string): void {
    this.text += token;
    const re = new RegExp(PAIR.source, "g");
    re.lastIndex = this.from;
    let m: RegExpExecArray | null;
    while ((m = re.exec(this.text))) {
      this.from = re.lastIndex;
      const style = this.styles.find(st => st.id === m![1]);
      if (!style || this.sent.has(style.id)) continue;
      this.sent.add(style.id);
      let value = "";
      try {
        value = unmarked(JSON.parse(`"${m[2]}"`) as string);
      } catch {
        continue;
      }
      if (value && keepsNumbers(this.typed, value) && keepsExact(this.typed, value)) {
        this.emit({ id: style.id, label: style.label, text: value });
      }
    }
  }

  /** The model was dropped midway: the next one's versions start over. */
  reset(): void {
    this.text = "";
    this.from = 0;
    this.sent.clear();
  }
}

/** A plain (non-JSON) reply can stand in as the one rewrite, but only when
 *  it reads as the message and not as the model talking ABOUT the message.
 *  Free models sometimes answer with their working ("We need to rewrite the
 *  message in each style, preserving facts…"), and that must never be
 *  offered for insertion. */
export function looksLikeRewrite(text: string, typed: string): boolean {
  const t = text.trim();
  if (!t || t.includes("{") || t.includes("}")) return false;
  if (t.length > typed.length * 4 + 120) return false;
  const opening = t.slice(0, 80).toLowerCase();
  if (/^(we need|we should|we have|here (is|are)|here's|sure[,!.]|okay[,!.]|ok[,!.]|let's|i (will|can|need|'ll|have)|the (message|user|text|writer)|first,|to rewrite|rewrit)/.test(opening)) {
    return false;
  }
  if (/\b(rewrite|rewriting|rewritten|json|preserving facts|the message below|in each style|each of these styles)\b/i.test(t)) {
    return false;
  }
  return true;
}

const NUMBER_WORDS = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
  "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen", "twenty"];
const ORDINAL_WORDS = ["zeroth", "first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth",
  "tenth", "eleventh", "twelfth", "thirteenth", "fourteenth", "fifteenth", "sixteenth", "seventeenth", "eighteenth",
  "nineteenth", "twentieth"];

/** The numbers a writer typed as facts: times, amounts, counts. Digits
 *  glued to letters are shorthand, not facts ("b4", "gr8", "2day", a masked
 *  [[S1]]), except a time or amount ("5pm", "10k"). A lone 2 or 4 before a
 *  word is usually "to" or "for" ("4 u"), and a lone 1 is often "a" ("1 min"). */
function typedNumbers(typed: string): string[] {
  const t = typed.replace(/(?<=\d),(?=\d)/g, "");
  const out = new Set<string>();
  for (const m of t.matchAll(/(?<![A-Za-z\d])(\d+)(?=(am|pm|k|hrs?|h|mins?)?(?![A-Za-z\d]))/gi)) {
    const n = m[1];
    if (["1", "2", "4"].includes(n) && /^\s+[A-Za-z]/.test(t.slice((m.index ?? 0) + n.length))) continue;
    out.add(n);
  }
  return [...out];
}

/** Whether a version still carries every number the writer typed, as digits
 *  or in words ("before 6" or "before six", "on the 3" or "on the third").
 *  Prompts ask for this, but a model can still read "b4 6" as "before you". */
export function keepsNumbers(typed: string, version: string): boolean {
  const v = version.toLowerCase().replace(/(?<=\d)[,\s](?=\d)/g, "");
  return typedNumbers(typed).every(n => {
    if (v.includes(n)) return true;
    const i = Number(n);
    return i <= 20 && new RegExp(`\\b(${NUMBER_WORDS[i]}|${ORDINAL_WORDS[i]})\\b`).test(v);
  });
}

const LINK = /\bhttps?:\/\/[^\s<>"]+|\bwww\.[^\s<>"]+|[\w.+-]+@[\w-]+(?:\.[\w-]+)+/gi;

/** Links and email addresses in what was typed, as typed. */
function typedExact(typed: string): string[] {
  const out = new Set<string>();
  for (const m of typed.matchAll(LINK)) out.add(m[0].replace(/[.,;:!?)\]]+$/, ""));
  return [...out];
}

/** Whether a version copies every link and email address letter for
 *  letter: one retyped by a model ("docs.google.com/d/1AbC…") goes nowhere. */
export function keepsExact(typed: string, version: string): boolean {
  return typedExact(typed).every(x => version.includes(x));
}

export interface ActOptions {
  /** Publishes a list as a live mini-app page and returns its public URL. */
  publish?: (title: string, places: PlaceCard[]) => string | undefined;
  /**
   * The shareable half of the writer's vault — name, email, phone, address,
   * UPI, links — sent only when they have left "Let AI use your details" on.
   * It exists so "send them my address" or a form that wants an email can be
   * answered without them typing it again. Nothing secret-shaped can be in
   * here: the vault refuses to store cards, IDs, OTPs and keys.
   */
  profile?: Record<string, string>;
  /** What a tapped suggestion chip promised; skips routing when set. */
  intent?: ActIntent;
  /** Pays for the run, called before the model is first asked; throws
   *  RunRefused when none is left. Without it the model is free (tests). */
  pay?: () => Promise<void>;
  /** For a streamed /act: each version the moment it is written, the
   *  written text as it comes, and a reset when a model is dropped midway. */
  stream?: ActStream;
}

export interface ActStream {
  option?: (o: RewriteOption) => void;
  text?: (t: string) => void;
  reset?: () => void;
}

/** The profile as prompt lines, or "" when there is nothing to say. */
export function profileBlock(profile?: Record<string, string>): string {
  const entries = Object.entries(profile ?? {}).filter(([, v]) => v?.trim());
  if (entries.length === 0) return "";
  const lines = entries.map(([k, v]) => `${k}: ${v}`).join("\n");
  return `\n\nDetails about the writer, to use ONLY where the message asks ` +
    `for them (never volunteer them):\n${lines}`;
}

/** Where people go: with "best" or "any" in front, a search for places. */
const VENUES = "restaurants?|cafes?|cafés|coffee shops?|bars?|pubs?|hotels?|hostels?|resorts?|gyms?|" +
  "pharmac(?:y|ies)|hospitals?|clinics?|atms?|banks?|parks?|museums?|malls?|bakery|bakeries|salons?|spas?|" +
  "places|spots|joints|clubs|breweries|brewery|cinemas?|theat(?:er|re)s?|beaches|stores|shops|dhabas?|eateries|diners?|" +
  "dentists?|doctors?|vets?|plumbers?|electricians?|mechanics?|barbers?|barbershops?|laundromats?|dry cleaners?|" +
  "supermarkets?|grocery stores?|gas stations?|florists?|bookstores?|nail salons?|car washes?";
/** What people eat: a search only with somewhere to look ("best biryani
 *  near indiranagar"); "best dinner ever" is a message. */
const DISHES = "coffee|pizza|sushi|burgers?|food|brunch|breakfast|lunch|dinner|dessert|ice cream|biryani|dosa|" +
  "ramen|tacos?|momos?|street food|cocktails?|drinks|chai|noodles|thali";
const CUISINES = "italian|chinese|indian|thai|mexican|japanese|korean|vietnamese|french|spanish|greek|" +
  "lebanese|turkish|south indian|north indian|vegan|vegetarian";

/** The calculation inside a question about one, or null: "what's 18% of
 *  2450?" gives "18% of 2450", "how much is 12 x 12" gives "12 * 12". Only a
 *  percentage phrase or digits joined by operators count, so a message that
 *  merely contains numbers ("meet at 5, table for 4") is left alone. */
export function mathQuestion(text: string): string | null {
  const q = text.trim()
    .replace(/^(what('|’)?s|what is|how much is|calculate|calc|solve)\s+/i, "")
    .replace(/[\s?=!.]+$/, "")
    .trim();
  if (/^[\d.,]+\s*%\s*of\s*[\d.,]+$/i.test(q)) return q;
  // "15% tip on 64": the tip, worked out, with the total.
  if (/^[\d.]+\s*%\s*tip\s*(?:on|for|of)\s*[$€£₹]?\s*[\d.,]+$/i.test(q)) return q;
  const expr = q.replace(/(\d)\s*[x×]\s*(?=\d)/gi, "$1 * ");
  if (/\d\s*[+\-*/÷^%]\s*[\d(]/.test(expr) && /^[\d\s.,+\-*/÷^()%]+$/.test(expr)) return expr;
  return null;
}

/** "price of sol", "sol price", "how much is bitcoin", "aapl stock price",
 *  "$tsla": the coin or stock asked about, else null. */
export function priceAsked(text: string): string | null {
  const t = text.trim().toLowerCase().replace(/\s+/g, " ").replace(/[?!.]+$/, "").trim();
  const asset = String.raw`\$?([a-z][a-z0-9]{1,13})`;
  const tail = String.raw`(?:\s+(?:stock|share|coin|token|crypto))?(?:\s+(?:price|rate))?(?:\s+(?:today|now|right now|rn))?`;
  const forms = [
    new RegExp(`^(?:what(?:'s|s| is)\\s+)?(?:the\\s+)?(?:current\\s+|live\\s+|latest\\s+)?price\\s+of\\s+(?:one\\s+|1\\s+)?${asset}${tail}$`),
    new RegExp(`^(?:what(?:'s|s| is)\\s+)?(?:the\\s+)?${asset}(?:\\s+(?:stock|share|coin|token))?\\s+(?:price|rate)(?:\\s+(?:today|now|right now|rn))?$`),
    new RegExp(`^how\\s+much\\s+is\\s+(?:one\\s+|1\\s+|a\\s+)?${asset}${tail}$`),
    new RegExp(`^(?:what(?:'s|s| is)\\s+)?${asset}\\s+(?:trading at|at|worth)(?:\\s+(?:today|now|right now))?$`),
    new RegExp(`^\\$([a-z][a-z0-9]{1,13})$`),
  ];
  for (const re of forms) {
    const m = re.exec(t);
    if (!m) continue;
    // A word is an asset only when it plainly is one: "$" or "stock"/"coin"
    // said, or a coin or company everyone knows. "how much is rent" is no
    // coin called RENT.
    const said = /\$|\b(stock|share|coin|token|crypto)\b/.test(t);
    if (said || KNOWN_ASSETS.has(m[1].toUpperCase())) return m[1];
  }
  return null;
}

const KNOWN_ASSETS = new Set([
  ...Object.keys(NAMES), ...Object.values(NAMES),
  "SOL", "BTC", "ETH", "USDC", "USDT", "JUP", "BONK", "WIF", "JTO", "PYTH", "RAY", "DOGE", "XRP", "BNB",
  "AAPL", "TSLA", "NVDA", "MSFT", "GOOGL", "GOOG", "AMZN", "META", "NFLX", "COIN", "MSTR", "PLTR", "HOOD",
  "GME", "AMD", "INTC", "SPY", "QQQ",
]);

const priceRates = new Rates();

/** A dollar price as the market quotes it: $117.98, $0.0001234. */
function usd(n: number): string {
  if (n >= 1) return `$${n.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
  return `$${n.toPrecision(4).replace(/0+$/, "")}`;
}

/** The live price of what was asked about (Jupiter, the same quote the
 *  strip's $sol chip shows), or null when it is no coin or stock it knows. */
async function priceAnswer(typed: string): Promise<ActResult | null> {
  const asked = priceAsked(typed);
  if (!asked) return null;
  const q = await priceRates.tokenQuote(asked).catch(() => null);
  if (!q) return null;
  const ticker = q.ticker ?? q.symbol;
  const line = q.stock ? `${ticker} is ${usd(q.usd)}` : `1 ${ticker} = ${usd(q.usd)}`;
  const change = typeof q.change24h === "number" && q.change24h !== 0
    ? ` · ${q.change24h > 0 ? "+" : ""}${q.change24h.toFixed(1)}% today` : "";
  const card: AnswerCard = { kind: "answer", id: `price-${ticker}`, title: `${ticker} price`,
    value: usd(q.usd), sub: `${q.name}${change}`, art: "none", source: "Jupiter",
    url: `https://jup.ag/tokens/${q.mint}`, say: line };
  return { intent: "answer", title: card.title, cards: [card], insert: line, provider: "jupiter" };
}

/** Asked for by the thing itself, no "write" in front: "leave application
 *  for 2 days", "resignation letter", "birthday wish for my sister". */
const DOCUMENT_ASK = /^(?:a |an |my |happy )?(?:(?:sick |casual |medical )?leave (?:application|letter|mail|email|request)|resignation(?: letter| mail| email)?|cover letter|(?:birthday|anniversary|wedding|farewell|retirement|thank[- ]you|condolence|congratulations?|get well soon|new year|diwali|christmas|eid) (?:wish(?:es)?|message|msg|text|note|card|speech|post|caption|quote)s?|(?:apology|complaint|appreciation|reference|recommendation|invitation|sick) (?:message|msg|text|dm|email|mail|note|letter|reply)|(?:email|mail|letter|application|essay|speech|poem|story|bio|caption)s? (?:to|for|on|about)\b)/;

/** A letter named as the whole ask. "my leave application got approved lets
 *  party" names one too, but tells what happened to it: a message. */
function documentAsk(lower: string): boolean {
  if (!DOCUMENT_ASK.test(lower) || lower.split(" ").length > 16) return false;
  if (/\b(got|get|gets|getting|was|were|is|are|am|has been|have been|had|approved|sent|submitted|rejected|accepted|granted|came|went|received|did|done|finished|ready)\b/.test(lower)) {
    return false;
  }
  return !/\b(u|ur|you|your|yours|you're|youre)\b/.test(lower.replace(/thank[- ]you/g, ""));
}

/** Things people ask to have written. */
const ARTIFACTS = "captions?|bio|poems?|story|stories|essays?|names?|ideas?|slogans?|taglines?|messages?|msg|notes?|" +
  "e-?mails?|mails?|letters?|posts?|tweets?|threads?|toast|speech|jokes?|quotes?|wish|wishes|greetings?|repl(?:y|ies)|" +
  "response|summary|outline|itinerary|agenda|recipe|script|lyrics|hashtags?|titles?|headlines?|descriptions?|" +
  "cover letter|resume|cv|apology|invite|invitation|checklist|to-?do list|list|questions|tips|excuses?|" +
  "pickup lines?|compliments?|rhymes?|song|limerick|haiku|riddles?|paragraphs?|sentences?|shayari|status|" +
  "comebacks?|roast|puns?";
const MAKE_ASK = new RegExp("^(?:please |pls |plz )?(?:make|create|generate|give me|suggest|brainstorm|come up with|think of)\\s+" +
  "(?:me\\s+|us\\s+)?(?:(?:a|an|the|some|few|\\d+|one|two|three|four|five|six|seven|eight|nine|ten|more|another|good|" +
  "nice|cool|funny|cute|short|quick|catchy|creative|clever|witty|romantic|sweet|heartfelt|formal|professional|polite)\\s+){0,3}" +
  `(?:[\\p{L}'-]+\\s+){0,2}(?:${ARTIFACTS})\\b`, "u");

/** Asked to write something: "write an essay on dogs", "give me 5 captions",
 *  "plan a 3 day trip to goa". "give me a call when you're free", "make sure
 *  you come" and "plan for tomorrow is set" are messages. */
function writeAsked(lower: string): boolean {
  if (/^(?:please |pls |plz )?(?:write|draft|compose)\b(?!\s+(?:back|soon|later|to me|me back|it down|that down|this down)\b)/.test(lower)) {
    return true;
  }
  if (MAKE_ASK.test(lower)) return true;
  if (/^list\s+(?:\d+|some|the|all|top|a few|few|three|five|ten)\b/.test(lower)) return true;
  if (/^plan\s+(?:a|an|my|our|the|\d+|me|us|some)\b/.test(lower)) return true;
  if (/^(?:explain|summari[sz]e|translate|rephrase|paraphrase|expand|shorten|outline)\b/.test(lower)
      && !/\b(u|ur|you|your|yourself)\b/.test(lower)) {
    return true;
  }
  // "translate thank you so much to hindi": what is to be translated may
  // well say "you".
  if (/^translate\b.+\b(?:to|into|in)\s+\p{L}+$/u.test(lower)) return true;
  if (translationAsked(lower)) return true;
  // "text to my boss saying im sick today" was tidied into "Text my boss
  // saying I'm sick today." (audit 2026-09-29).
  if (SAYING_ASK.test(lower)) return true;
  return documentAsk(lower);
}

const LANGUAGES = "english|spanish|french|german|italian|portuguese|japanese|chinese|mandarin|cantonese|korean|hindi|" +
  "arabic|russian|turkish|dutch|greek|hebrew|swedish|norwegian|danish|finnish|polish|czech|ukrainian|romanian|" +
  "hungarian|vietnamese|thai|indonesian|malay|tagalog|filipino|bengali|bangla|urdu|tamil|telugu|punjabi|marathi|" +
  "gujarati|kannada|malayalam|swahili|persian|farsi|latin|irish|welsh|catalan|nepali|sinhala|burmese|khmer|amharic|zulu";

/** "how do you say thank you in japanese", "what's hello in french",
 *  "good morning in spanish": words wanted in another language. Audit
 *  2026-09-29: the first was tidied as a message. "i'm fluent in spanish"
 *  and "the movie is in french" say something about a language. */
export function translationAsked(lower: string): boolean {
  return translationOf(lower) !== null;
}

/** The words and the language of a translation asked for, so the model is
 *  handed "Translate into Japanese: thank you" (asked "how do you say thank
 *  you in japanese" it wrote "thank you in japanese is arigatou"). */
export function translationOf(text: string): { words: string; language: string } | null {
  const t = text.toLowerCase().replace(/[’‘]/g, "'").replace(/\s+/g, " ").replace(/[?!.]+$/, "").trim();
  const asked = t.match(new RegExp(String.raw`^(?:how (?:do|would|can|should) (?:you|i|u|we|one) say|how to say|how is|what(?:'s| is)|whats|say|translate)\s+["“']?(.{1,200}?)["”']?\s+(?:in|to|into)\s+(${LANGUAGES})$`));
  if (asked && (!/^(?:what|whats|how is)/.test(t) || asked[1].split(" ").length <= 6)) {
    return { words: asked[1], language: asked[2] };
  }
  const bare = t.match(new RegExp(String.raw`^["“']?([\p{L}' ]{1,30}?)["”']?\s+in\s+(${LANGUAGES})$`, "u"));
  if (!bare || bare[1].split(" ").length > 4) return null;
  if (/\b(i|i'm|im|we|we're|he|she|they|it's|its|is|are|was|were|be|speak|speaks|speaking|spoke|fluent|learn|learning|taught|teach|written|dubbed|class|classes|course|lessons?|movie|film|show|series|song|songs|book|books|subtitles?|news|degree|major|exam|test)\b/.test(bare[1])) {
    return null;
  }
  return { words: bare[1], language: bare[2] };
}

/** "text to my boss saying im sick today", "email hr asking for 2 days off",
 *  "message my landlord about the broken heater": what to say, and to whom.
 *  "text me when you're home" is a message. */
const SAYING_ASK = /^(?:please |pls |plz )?(?:(?:a|an|my) )?(?:text|message|msg|dm|email|e-mail|mail|note|reply|whatsapp|sms|letter)s?(?: (?:to|for))? (?!(?:me|you|u|us|ya)\b)[\p{L}'-]+(?: [\p{L}'-]+){0,3}? (?:saying|that says|telling|asking|about|to say|explaining|letting)\b/u;

/** People talking to or about each other. A message mentions food, videos
 *  and the weather all the time; a search is typed as bare words. "near
 *  me" and "send me the trailer" are how searches are typed, so those
 *  "me"s are taken out before looking. */
const PEOPLE = /\b(i|i'm|im|i've|ive|i'll|i'd|me|my|mine|myself|we|we're|we've|we'll|we'd|us|our|ours|u|ur|you|you're|youre|you've|you'll|you'd|your|yours|ya|yall|y'all|let's|lets|he|she|him|her|his|hers|they|them|their|theirs)\b/;
const SEARCH_ME = /\b(?:near|around|for|to|from|with)\s+me\b|^(?:send|show|give|find|get|play|tell)\s+me\b/g;
/** What happened and what ought to: "was great", "got approved", "should go". */
const NARRATIVE = /\b(was|were|wasn't|weren't|had|hadn't|got|gotten|did|didn't|went|came|sent|saw|seen|been|ate|watched|heard|told|said|loved|enjoyed|liked|approved|reached|finished|missed|should|shall|gotta|gonna|wanna|would|could|might|must)\b/;
/** The small words around a chat. */
const SMALL_TALK = /\b(thanks|thank you|thx|tnx|ty|lol|lmao|lmfao|rofl|haha\w*|hehe\w*|omg|congrats|sorry|sry|pls|plz|please|hey|hi|hello|yo|bro|dude|yaar|bhai|okay|ok|kk|yeah|yep|yup|nope|sure)\b|!|\p{Extended_Pictographic}/u;
/** How a question starts, to a person or to Glyf. */
const QUESTION_START = /^(what|what's|whats|who|who's|whos|where|where's|wheres|when|when's|whens|why|how|how's|hows|which|is|isn't|are|aren't|am|was|were|can|can't|could|do|does|don't|doesn't|did|didn't|will|won't|would|should|shall|have|has|may|might|any)\b/;

/** A song or a film's name, which may well hold a "you" or a "me" ("ed
 *  sheeran shape of you", "all of me"): short, no story, no small talk, no
 *  "is", and at most one such word, never the first. */
export function titleLike(lower: string): boolean {
  const words = lower.split(" ");
  if (words.length > 8 || NARRATIVE.test(lower) || SMALL_TALK.test(lower)) return false;
  if (/\b(is|are|am|isn't|aren't|was|were)\b/.test(lower)) return false;
  const people = words.filter(w => PEOPLE.test(w));
  return people.length <= 1 && !PEOPLE.test(words[0] ?? "");
}

/** "please", "pls", "kindly" before an ask to find, show or write. */
const COURTESY = /^(?:please|pls|plz|kindly)[,\s]+(?=(?:find|show|search|look up|recommend|suggest|get|give|tell|play|write|draft|translate)\b)/i;

/** Typed the way a search is: short, and nobody talking to anybody. */
export function searchLike(text: string): boolean {
  const lower = text.toLowerCase().replace(/[’‘]/g, "'").replace(/\s+/g, " ").trim();
  if (!lower || lower.split(" ").length > 10) return false;
  const bare = lower.replace(SEARCH_ME, " ");
  if (PEOPLE.test(bare) || NARRATIVE.test(lower) || SMALL_TALK.test(lower)) return false;
  // "the pizza here is good" says something; "which is the best pizza" asks.
  return !(/\b(is|are|am|isn't|aren't|looks|seems|tastes|smells|sounds)\b/.test(lower) && !QUESTION_START.test(lower));
}

/** Cheap first pass. Returns null when the text needs the model to decide.
 *  Only asks are routed here: a sum, a price, money to convert, something
 *  to write, the time or the weather asked for, and searches typed as
 *  searches. A message that mentions dinner or a video goes to the model. */
export function planByRules(text: string): ActPlan | null {
  // "please find me a good sushi place in brooklyn": the courtesy is not
  // small talk, the ask after it is what counts.
  const t = text.trim().replace(/\s+/g, " ").replace(COURTESY, "").replace(/[,\s]+(?:please|pls|plz)[.!]*$/i, "");
  if (!t) return null;
  const lower = t.toLowerCase().replace(/[’‘]/g, "'");

  // Arithmetic and conversions have computed answers on the web vertical.
  if (/\d/.test(t) && /^[\d\s.,+\-*/×÷^()%=]+$/.test(t)) return { intent: "answer", query: t };
  // The same sums asked in words ("18% of 2450", "what is 12*12?", "how
  // much is 2450/4") are still sums: left to the model they read as a
  // message and come back tidied instead of answered.
  const sum = mathQuestion(t);
  if (sum) return { intent: "answer", query: sum };
  // "5 km in miles": a conversion, worked out, never written by a model.
  if (convertUnits(t)) return { intent: "answer", query: t };
  // "how many days until christmas": counted on the calendar.
  if (daysAsked(t)) return { intent: "answer", query: t };
  // Money in other money ("50 euros in dollars", "1 sol in euros"): today's
  // rate, never a model's memory of one.
  if (moneyAsked(t)) return { intent: "answer", query: t };
  // A price asked for: the live quote, not a message to tidy.
  if (priceAsked(t)) return { intent: "answer", query: t };
  // Asked to write something, before anything it mentions: a caption for a
  // sunset photo is a caption, not the time of sunset.
  if (writeAsked(lower)) return { intent: "write", query: t };
  // The time, the sun or the weather, asked for as such.
  if (liveAsk(t)) return { intent: "answer", query: t };

  // "where can i get good tacos in austin": asked of anyone, the places
  // are the answer.
  const whereTo = lower.match(/^where (?:(?:can|could|should|do) (?:i|we|u|you|one) |to )(?:get|find|buy|eat|grab|have|go for)\s+(.+?)\??$/);
  if (whereTo && (new RegExp(`\\b(${VENUES}|${DISHES}|${CUISINES})\\b`).test(whereTo[1]) || /\b(?:in|near|around)\s+\p{L}/u.test(whereTo[1]))) {
    return { intent: "places", query: t };
  }

  // Below, a few words anywhere decide, so only text typed as a search.
  if (!searchLike(lower)) return null;
  if (/\b(near me|nearby|around me|around here|near here|close by|closest|nearest|in the area)\b/.test(lower)) {
    // "cafes near me" wants options; "nearest ATM" wants the one.
    return { intent: /\b(nearest|closest)\b/.test(lower) ? "place" : "places", query: t };
  }
  const listy = /\b(best|top|good|great|nice|cheap|cheapest|popular|famous|recommended|must[- ]try|affordable|decent|any)\b/.test(lower);
  const venue = new RegExp(`\\b(${VENUES})\\b`).test(lower);
  const dish = new RegExp(`\\b(${DISHES}|${CUISINES})\\b`).test(lower);
  const located = /\b(?:in|near|around|at|close to)\s+\p{L}/u.test(lower);
  if ((listy && (venue || (dish && located))) || (venue && located && /s\b/.test(lower))) {
    return { intent: "places", query: t };
  }
  if (/\b(videos?|trailers?|music videos?|songs?|lyrics|playlists?|tutorials?|livestream|live stream|full match|highlights|teaser)\b/.test(lower)) {
    return { intent: "video", query: t };
  }
  // "how to make pancakes", typed on its own: the video that shows it.
  if (/^how to\s+\S/.test(lower)) return { intent: "video", query: t };
  // "who is the ceo of tesla", "why is the sky blue": a question for a fact,
  // with or without its "?", answered by the AI with no router call first.
  if (infoQuestion(lower)) return { intent: "answer", query: t };
  return null;
}

/** A question for a fact or an explanation, asked of nobody in particular:
 *  "who is the ceo of tesla", "why is the sky blue", "can dogs eat grapes?".
 *  Not one asked of the person in the chat ("are you coming?", "where is the
 *  party tonight", "what time is the meeting tmrw"), about the writer ("can
 *  i come over"), or small talk ("whats up"). Those go on to the model. */
export function infoQuestion(text: string): boolean {
  const lower = text.toLowerCase().replace(/[’‘]/g, "'").replace(/\s+/g, " ").trim();
  if (lower.split(" ").length < 3) return false;
  if (!(QUESTION_START.test(lower) || /\?$/.test(lower))) return false;
  if (CHITCHAT.test(lower) || SECOND_PERSON.test(lower) || ADDRESSED.test(lower) || OWN_PLANS.test(lower)) return false;
  // "does it hurt?", "is that true": short, and about something in the chat.
  if (lower.split(" ").length <= 4 && /\b(it|this|that|these|those|there)\b/.test(lower)) return false;
  return !PEOPLE.test(lower.replace(SEARCH_ME, " "));
}

/** Pulls the first JSON object out of a model reply and validates it. */
export function parsePlan(reply: string, fallbackQuery: string): ActPlan | null {
  const match = reply.match(/\{[\s\S]*?\}/);
  if (!match) return null;
  try {
    const obj = JSON.parse(match[0]) as { intent?: string; query?: string };
    if (!obj.intent || !ACT_INTENTS.includes(obj.intent as ActIntent)) return null;
    const query = typeof obj.query === "string" && obj.query.trim() ? obj.query.trim() : fallbackQuery;
    return { intent: obj.intent as ActIntent, query: query.slice(0, 200) };
  } catch {
    return null;
  }
}

const ROUTER_PROMPT = (text: string) => `You route what someone typed on their phone keyboard to ONE action.
Reply with JSON only, no prose: {"intent":"place|places|answer|video|rewrite|write","query":"..."}
place   — one specific place they name, or ask the way to: "Times Square Starbucks", "lets meet at Blue Tokai Indiranagar at 6", "how do i get to Indiranagar metro station". query: just the place, e.g. "Blue Tokai Indiranagar".
places  — recommendations, several places: "SF best italian restaurant". query: what and where.
answer  — a question for a fact to look up or work out: "whats the capital of australia", "who won the match", "how many ml in a cup". query: the question.
video   — they want a video or a song found: "dune part 2 trailer", "lofi beats playlist", an artist and a song ("ed sheeran shape of you", "arijit singh tum hi ho"), a how-to typed on its own ("how to make pancakes", "how to tie a tie"). query: what to search on YouTube.
write   — they ask for something to BE written or worked out for them: "write an essay on dogs", "draft a leave email", "5 captions for this photo", "explain quantum computing".
rewrite — a message to someone, even one that mentions food, a video, a song, a place, the weather or a time: "had a great dinner with u last night, thanks", "did u see the video i sent u", "this song is stuck in my head", "the pizza here is good", "are you free for lunch tomorrow?", "sorry cant make it, my son has a fever". A request or a question to the person they are writing to ("can u send me the invoice", "are you free", "can you come") is a message.
Typed: """${text.replace(/"""/g, "'")}"""`;

/** Deterministic offline routing for tests: questions look things up,
 *  everything else is a message to tidy. */
export function mockPlan(text: string): ActPlan {
  const t = text.trim();
  if (/^(write|draft|compose|explain)\b/i.test(t)) return { intent: "write", query: t };
  return { intent: t.endsWith("?") ? "answer" : "rewrite", query: t };
}

/** What a request for writing names; a message that names none of these
 *  ("can u send me the invoice asap") is a request to a person. */
const WRITE_WORDS = new RegExp(`\\b(write|draft|compose|explain|summar\\w*|translate|rephrase|${ARTIFACTS})\\b`);
/** Asking Glyf to find something, rather than talking about it. */
const FIND_WORDS = /\b(find|search|look up|show me|send me|play|watch|recommend|suggest|where can|where to|where is|any good|tell me|do you know)\b/;
/** Told as having happened: "had a great dinner at Toit, thanks". */
const PAST = /\b(was|were|had|went|came|saw|ate|loved|enjoyed|got|did)\b/;
/** Nothing but a greeting or a reply: "ok", "whats up", "thanks!". */
const CHITCHAT = /^(?:ok(?:ay)?|k+|kk|hi+|hey+|hello|yo|sup|wass?up|what'?s up|whats up|wyd|hru|how (?:are|r) (?:you|u)|how'?s it going|good (?:morning|night|evening|afternoon)|gm|gn|thanks?|thank you|thx|ty|lol|haha\w*|yes|yeah|yep|no|nope|sure|cool|nice|great|done|np|no worries|see (?:you|u|ya)(?: soon| later)?|bye|cya|ttyl|lmk|brb|omw)(?:\s+(?:bro|dude|man|yaar|bhai|mate|buddy))?[\s!?.]*$/;

/** A second look at what the router said, for the misreads a small model
 *  makes: a request to a person read as something to write ("can u send me
 *  the invoice"), a remark read as a search ("this song is stuck in my
 *  head", "had dinner at Toit last night"), a question to a friend read as
 *  one to look up ("r u free tmrw"), a greeting read as a question ("whats
 *  up"). Each of those is a message. */
/** Talking to someone: "you" in English, "tu", "tum", "aap" in Hindi. */
const SECOND_PERSON = /\b(u|ur|you|your|yours|you're|youre|ya|tu|tum|tumhe|tumko|tumne|tumhara|tumhari|tumhare|tera|teri|tere|aap|aapko|aapne|aapka|aapki|aapke)\b/;
/** A message that opens or ends by naming who it is for. */
const ADDRESSED = /^(?:bhai|bro|bruh|yaar|dude|mom|mum|maa|papa|dad|didi|bhaiya|babe|baby|hey|hi|hello|yo|oye|arre)\b|\b(?:bhai|bro|yaar|dude|babe|bhaiya|didi)[?!.]*$/;

/** Asked about the writer's own plans ("what time is the meeting tmrw",
 *  "where is the party tonight", "who is coming"): nothing on the web knows.
 *  Audit 2026-09-29: the first came back as an empty answer. */
const OWN_PLANS = new RegExp(String.raw`\b(?:the|our|my|ur|your|this|tonight'?s|tomorrow'?s|tmrw'?s)\s+` +
  String.raw`(?:meeting|meet|party|call|dinner|lunch|brunch|breakfast|appointment|appt|flight|reservation|booking|` +
  String.raw`interview|class|practice|rehearsal|wedding|event|plan|plans|trip|standup|stand-up|shift|session|date|` +
  String.raw`hangout|get together|get-together|pickup|pick up|drop off|shoot|exam|gig|reunion|sleepover|potluck|` +
  String.raw`bus|train|metro|subway|uber|lyft|cab|taxi|ride|delivery|order|package|parcel)\b` +
  String.raw`|\bwho(?:'s| is| all is| all are| are)\s+(?:coming|joining|going|in|bringing)\b`);

export function checkPlan(p: ActPlan, text: string): ActPlan {
  const lower = text.toLowerCase().replace(/[’‘]/g, "'").replace(/\s+/g, " ").trim();
  const message: ActPlan = { intent: "rewrite", query: text.trim() };
  // "whats up" is a greeting, not a question about the news.
  if (p.intent !== "write" && CHITCHAT.test(lower)) return message;
  const finding = FIND_WORDS.test(lower);
  switch (p.intent) {
    case "write":
      return WRITE_WORDS.test(lower) ? p : message;
    case "video":
      return searchLike(lower) || finding || titleLike(lower) ? p : message;
    case "places":
      return searchLike(lower) || finding ? p : message;
    case "place":
      return PAST.test(lower) && !finding ? message : p;
    case "answer":
      // Said to someone, in English or Hindi: "where r u", "bhai kidhar hai
      // tu" is asked of a friend, never of Glyf (it once answered "I am an AI
      // without a physical location"). And their own plans: only the people
      // in the chat know when the meeting is.
      // "where is the party tonight" too, though "where is" can be a search.
      if (OWN_PLANS.test(lower) && !/\b(find|search|look up|show me|recommend|suggest)\b/.test(lower)) return message;
      return (SECOND_PERSON.test(lower) || ADDRESSED.test(lower)) && !finding ? message : p;
    default:
      return p;
  }
}

async function planWithModel(text: string): Promise<ActPlan> {
  await payForModel();
  if (env.mockAI) return mockPlan(text);
  try {
    const res = await completeStreaming("fast",
      [{ role: "user", content: ROUTER_PROMPT(text) }], { onToken: () => {}, stallMs: 4000 });
    const routed = parsePlan(res.text, text.trim());
    return routed ? checkPlan(routed, text) : { intent: "rewrite", query: text.trim() };
  } catch {
    return { intent: "rewrite", query: text.trim() };
  }
}

export function plan(text: string): Promise<ActPlan> {
  const byRules = planByRules(text) ?? (needsTidy(text) ? { intent: "rewrite" as const, query: text.trim() } : null);
  return byRules ? Promise.resolve(byRules) : planWithModel(text);
}

/** The message a rewrite is for: after a leading instruction ("make this
 *  sound professional:", "fix grammar:", "rewrite:"), or all of it. A note
 *  with a colon ("note: meeting at 5") is all message. */
export function rewriteTarget(text: string): string {
  const m = text.match(/^\s*(?:please\s+|pls\s+|plz\s+)?(make|rewrite|rephrase|reword|fix|tidy|clean up|polish|improve|correct|proofread|shorten)\b([^:\n]{0,50}):\s*(\S[\s\S]*)$/i);
  if (!m || `${m[1]}${m[2]}`.trim().split(/\s+/).length > 8) return text;
  return m[3].trim();
}

/** Texting shorthand and missing apostrophes: the words a tidy-up fixes. */
const SHORTHAND = /\b(u|ur|pls|plz|thx|tnx|b4|tmrw|tmr|tomo|2day|2nite|gonna|wanna|gotta|cuz|coz|abt|idk|rn|ppl|msg|kk|ya|yea|nah|dont|cant|wont|didnt|doesnt|isnt|wasnt|arent|im|ive|youre|theyre|thats|whats|lets|shouldnt|couldnt|wouldnt|havent)\b/i;
/** Written with care already: a capital to start, a stop to end, no
 *  shorthand, no lowercase "i". "Tidy this up" on it is noise
 *  ("Thanks so much for dinner last night, it was lovely." was offered one). */
export function readsTidy(text: string): boolean {
  const t = text.trim().replace(/\s+/g, " ");
  return /^[\p{Lu}\d"“‘'(]/u.test(t) && /[.!?…)"”’']$/.test(t) && !SHORTHAND.test(t)
    && !/(^|\s)i(\s|'|’|$)/.test(t) && !/([a-z])\1{2,}/i.test(t) && !/\s[,.!?]/.test(t);
}

/** Anything a model should read first: a question, a place, a live fact,
 *  a video. Those can want the map, an answer or a search, not a tidy-up. */
const LOOKUP = /\?|\b(where|who|when|which|what time|how much|how many|price|cost|score|near|nearby|meet at|at the|video|song|movie|weather|open now)\b/i;

/** Written in English, as far as the words say: the shorthand and "i"
 *  rules below are English's own. Hinglish, Spanish or Tamil go to the
 *  model, which can tell a message from a question in any of them. */
function readsAsEnglish(text: string): boolean {
  return !scriptLanguage(text) && latinLanguage(text) !== "Hindi" && !otherLatinLanguage(text);
}

/** A chat message that plainly wants tidying, known without a model: a
 *  sentence of four words or more with texting shorthand, a lowercase "i",
 *  stretched letters ("sooo") or a long run with no capital and no stop.
 *  Math, places and questions never land here: the rules and the model
 *  handle those ("whats the capital of australia" wants an answer, not a
 *  capital W). Instant, where asking a model costs most of a second. */
export function needsTidy(text: string): boolean {
  // A link's "?" is not a question.
  const t = text.trim().replace(LINK, " link ").replace(/\s+/g, " ");
  const words = t.split(" ");
  if (words.length < 4 || LOOKUP.test(t) || /\d\s*[-+*/×÷^%]\s*\d/.test(t)) return false;
  if (QUESTION_START.test(t.toLowerCase().replace(/[’‘]/g, "'")) || !readsAsEnglish(t)) return false;
  return SHORTHAND.test(t) || /(^|\s)i(\s|'|$)/.test(t) || /([a-z])\1{2,}/i.test(t)
    || (/^[a-z]/.test(t) && words.length >= 6 && !/[.!?]$/.test(t));
}

/** Nothing live came back. Say so, keep the Google card to open, and put
 *  nothing in the message: a search link pasted into a chat helps no one. */
function nothingFound(intent: ActIntent, typed: string, query: string, provider: string): ActResult {
  return { intent, title: typed, cards: [googleCard(query)], text: "Nothing found for that.",
    insert: "", provider };
}

function googleCard(query: string): SearchCard {
  return {
    kind: "query", id: `google:${query}`, title: `See “${query}” on Google`,
    url: `https://www.google.com/search?q=${encodeURIComponent(query)}`, source: "handoff",
  };
}

/** A short list the recipient can act on: one line per place, each with its
 *  maps link. */
export function listInsert(title: string, places: PlaceCard[]): string {
  const lines = places.map((p, i) => {
    const bits = [p.title];
    if (typeof p.rating === "number") bits.push(`${p.rating.toFixed(1)}★`);
    if (p.address) bits.push(p.address);
    return `${i + 1}. ${bits.join(" · ")}\n${p.url}`;
  });
  return [title, ...lines].join("\n");
}

/** Live facts a model must not invent — the same line the web tab holds. */
export { isLive };

/** The day and the hour where the writer is, so "tomorrow" in a leave email
 *  is the right date and nothing is dated a year the model remembers. */
export function todayLine(tz?: string, now = new Date()): string {
  let zone = "UTC";
  try {
    if (tz) {
      new Intl.DateTimeFormat("en-US", { timeZone: tz });
      zone = tz;
    }
  } catch { /* an unknown zone reads as UTC */ }
  const day = (d: Date) => new Intl.DateTimeFormat("en-US", {
    timeZone: zone, weekday: "long", day: "numeric", month: "long", year: "numeric" }).format(d);
  const time = new Intl.DateTimeFormat("en-US", { timeZone: zone, hour: "numeric", minute: "2-digit" }).format(now);
  return `Today is ${day(now)}, ${time} where the writer is; tomorrow is ${day(new Date(now.getTime() + 86_400_000))}.`;
}

/** A model declining in words meant for the person asking, which must never
 *  be pasted into their chat as if they had written it. */
const REFUSAL = /^(?:(?:i'?m sorry|i am sorry|sorry|unfortunately)[,.!]?\s+(?:but\s+)?i\s+(?:can(?:'|no)t|cannot|won'?t|am unable|'m unable|am not able|'m not able)|i\s+(?:can(?:'|no)t|cannot|won'?t|am unable to|'m unable to|am not able to|'m not able to)\s+(?:help|assist|write|create|draft|do|comply|provide|fulfil|produce|generate|make)|i must decline|as an ai\b|as an? (?:ai|language model)\b|i(?:'m| am) (?:just )?an? (?:ai|language model|virtual assistant)\b|i (?:don'?t|do not) have (?:a physical|a body|personal|real-time|feelings)\b)/i;

/** The model's own lines around what it wrote: "Sure! Here's a caption:". */
const OPENER_LINE = /^(?:(?:sure|certainly|of course|absolutely|okay|ok)[,!.]?\s*)?(?:here(?:'s| is| are)|below is|i(?:'ve| have) (?:written|drafted))\b[^\n]*:$|^(?:sure|certainly|of course|absolutely)[,!.]?$/i;

/** A slot left for a detail the model didn't know: "[Your Name]", "[Date]". */
const PLACEHOLDER = /\[[^\]\n]{1,40}\](?!\()|<(?:your|recipient|manager|name|date|company)[^>\n]{0,30}>|\((?:your|insert|recipient'?s?|manager'?s?|company'?s?) [^)\n]{0,30}\)/i;

export function hasPlaceholder(text: string): boolean {
  return PLACEHOLDER.test(text);
}

/** What a model wrote, as the person would send it: no opener or sign-off
 *  to them, no markdown, the writer's own name where a slot was left for it. */
export function tidyWritten(raw: string, profile?: Record<string, string>): string {
  let t = raw.replace(/\r/g, "").trim().replace(/^```\w*\n?([\s\S]*?)\n?```$/, "$1").trim();
  const lines = t.split("\n");
  while (lines.length > 1 && OPENER_LINE.test(lines[0].trim())) {
    lines.shift();
    while (lines.length > 0 && !lines[0].trim()) lines.shift();
  }
  t = lines.join("\n")
    .replace(/^(?:sure|certainly|of course|absolutely)[,!.]?\s+(?=here\b|below\b)/i, "")
    .replace(/^here(?:'s| is| are)\b[^:\n]{0,80}:\s*/i, "")
    // Notes to the writer after the thing itself.
    .replace(/\n+\s*(?:\(?note:|feel free to|let me know if|i hope this helps|hope this helps|you can (?:adjust|customi[sz]e|personali[sz]e|tweak|edit))[\s\S]*$/i, "")
    .replace(/\*\*([^*\n]+)\*\*/g, "$1").replace(/__([^_\n]+)__/g, "$1").replace(/^#{1,6}\s+/gm, "")
    .trim();
  if (/^["“][^"“”]+["”]$/.test(t)) t = t.slice(1, -1).trim();
  const name = profile?.name?.trim();
  if (name) t = t.replace(/\[(?:your|my|sender'?s?)\s+(?:full\s+)?name\]/gi, name);
  return t;
}

/** Last resort for a slot a second try still left: a greeting keeps its
 *  word ("Dear [Name]," → "Hello,"), a line that was only slots goes, and a
 *  slot inside a sentence is taken out. */
export function dropPlaceholders(text: string): string {
  return text
    .replace(/^(dear|hi|hello|hey)\s+\[[^\]\n]{1,40}\]\s*,?/gim, (_m, g: string) => (/^dear$/i.test(g) ? "Hello," : `${g},`))
    .split("\n").filter(line => !/^\s*(?:\[[^\]\n]{1,40}\][\s,.;:-]*)+$/.test(line)).join("\n")
    // "on leave on [Date] for" → "on leave for": the slot goes with its word.
    .replace(/\s+(?:on|at|in|by|to|for|from|with|of)\s+\[[^\]\n]{1,40}\](?!\()/gi, "")
    .replace(/\s*\[[^\]\n]{1,40}\](?!\()/g, "")
    .replace(/ +([,.;:!?])/g, "$1").replace(/[ \t]{2,}/g, " ")
    // "Subject: Leave Application - [Your Name]" leaves a dash behind.
    .replace(/[ \t]+[-–—]+[ \t]*$/gm, "")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

/** Holds a written reply's first line until it is clear it is the thing
 *  itself: an opener ("Here's a caption:") is dropped and a refusal never
 *  shows; the rest streams as it comes. */
class OpenerGate {
  private held = "";
  private open = false;
  private blocked = false;

  constructor(private readonly forward: (t: string) => void) {}

  push(token: string): void {
    if (this.blocked) return;
    if (this.open) {
      this.forward(token.replace(/\*\*/g, ""));
      return;
    }
    this.held += token;
    const nl = this.held.indexOf("\n");
    if (nl < 0 && this.held.length < 120) return;
    const first = (nl < 0 ? this.held : this.held.slice(0, nl)).trim();
    if (REFUSAL.test(first)) {
      this.blocked = true;
      return;
    }
    const rest = OPENER_LINE.test(first)
      ? (nl < 0 ? "" : this.held.slice(nl + 1).replace(/^\s+/, ""))
      : this.held.replace(/^\s+/, "")
        .replace(/^(?:sure|certainly|of course|absolutely)[,!.]?\s+(?=here\b|below\b)/i, "")
        .replace(/^here(?:'s| is| are)\b[^:\n]{0,80}:\s*/i, "");
    this.open = true;
    this.held = "";
    if (rest) this.forward(rest.replace(/\*\*/g, ""));
  }

  /** The reply ended while still held (a short caption): let it through. */
  flush(): void {
    if (this.open || this.blocked || !this.held.trim()) return;
    if (REFUSAL.test(this.held.trim().split("\n")[0])) {
      this.blocked = true;
      return;
    }
    this.open = true;
    const text = tidyWritten(this.held);
    this.held = "";
    if (text) this.forward(text);
  }

  reset(): void {
    this.held = "";
    this.open = false;
    this.blocked = false;
  }
}

const WRITE_PROMPT =
  "Write exactly what is asked for, ready to send as it is, in the language the request is written in; a " +
  "translation is in the language asked for, and is only the translated words (in that language's own script, " +
  "with how to say it in Latin letters in brackets when that script is not Latin). " +
  "Keep every detail it gives, as given: numbers, durations, dates, names and reasons (\"for 2 days\" says 2 days). " +
  "No preamble (no \"Here is\", no \"Sure\"), no notes after it, no markdown (no **bold**, no # headings), " +
  "and no placeholders like [Name] or [Date]: where a detail isn't known, write around it (sign off without " +
  "a name, say \"tomorrow\" rather than a date). Never add a detail the request doesn't give: no amount, " +
  "date, deadline, time, place or name of your own (\"pay me back\" is not \"$500 by Friday\"). " +
  "Keep it to what was asked; if no length is given, a few short " +
  "paragraphs at most, and a caption, a wish or a text message is one to three lines. Never state a live fact " +
  "you can't know, such as a price, an exchange rate, a score or the weather. If what is asked is a threat, " +
  "harassment or blackmail, write instead a calm, firm, respectful message asking for the same thing with no " +
  "threat in it; never reply with a refusal or an explanation.";

// Measured 2026-09-29 (env.answerModels): given today's date as "now", a
// model invents the latest winner ("the Chiefs won Super Bowl LX in 2026");
// given the date only for ages, it names the last one it knows, dated.
const ANSWER_PROMPT =
  "Answer this in one to three short sentences, plainly, with no preamble and no markdown, in the language it is " +
  "asked in. Answer only what is asked: no names or history it doesn't ask for. Answer from what you know for " +
  "certain. A fact that can change (who runs a company, who holds a title) is the latest you know. For the latest " +
  "winner of something, name the last one you are certain of and when it happened; what you know may be a year or " +
  "two old, so never guess a newer one. Reply with the single word UNKNOWN only if it is about what is happening " +
  "right now (today's scores, today's news, a live price) or you have no idea.";

/** A small model's remarks about its own answer, never part of one: "This
 *  information is well-established and not time-sensitive. No current
 *  events change this fact." (audit 2026-09-29, after "who is the ceo of
 *  tesla"). */
const SELF_TALK = /\b(?:well[- ]established|time[- ]sensitive|current events|as of my (?:last|knowledge)|knowledge cut-?off|(?:i|we) (?:don't|do not|cannot|can't) (?:have|browse|access)|real[- ]time (?:data|information|access)|this (?:information|fact|answer) (?:is|may|might|does|was))\b/i;

export function dropSelfTalk(text: string): string {
  const sentences = text.match(/[^.!?\n]+(?:[.!?]+|$)\s*/g) ?? [text];
  const kept = sentences.filter(s => !SELF_TALK.test(s));
  return kept.length ? kept.join("").trim() : text.trim();
}

/** The model writes the thing (or answers the question) and it goes
 *  straight in the message, tidied: no opener, no markdown, no [Name]. */
async function written(
  typed: string, kind: "write" | "answer", ctx: SearchContext, opts: ActOptions, provider: string,
): Promise<ActResult> {
  // Asking someone for theirs ("send me your address") needs none of the
  // writer's own details.
  const profile = asksForTheirs(typed) ? undefined : opts.profile;
  // A translation is asked for plainly, whatever words it came in.
  const translation = kind === "write" ? translationOf(typed) : null;
  const asked = translation
    ? `Translate into ${translation.language[0].toUpperCase()}${translation.language.slice(1)}, written as it would be sent: ${translation.words}`
    : typed;
  // The ask goes last, after the instructions and the day.
  const prompt = (extra: string) => (kind === "write" ? WRITE_PROMPT : ANSWER_PROMPT) + extra
    + `\n\n${kind === "answer"
      ? `Only for working out an age or how long ago something was: ${todayLine(ctx.tz).replace(/^Today/, "today")}`
      : todayLine(ctx.tz)}` + profileBlock(profile) + `\n\n${kind === "write" ? "Asked for" : "Question"}: ${asked}`;
  const gate = kind === "write" && opts.stream?.text ? new OpenerGate(opts.stream.text) : null;
  const draft = async (extra = ""): Promise<string> => {
    try {
      const reply = await modelText(prompt(extra), 5000, gate
        ? { onToken: t => gate.push(t), onRestart: () => { gate.reset(); opts.stream?.reset?.(); } } : undefined,
        kind === "answer" ? "answer" : "fast");
      gate?.flush();
      return reply;
    } catch {
      return "";
    }
  };
  let text = tidyWritten(await draft(), profile);
  if (kind === "answer") text = dropSelfTalk(text);
  if (kind === "write" && REFUSAL.test(text)) {
    // Declined, most likely for a threat: what can be sent instead is the
    // same ask, calmly. Declined again, nothing goes in the message.
    gate?.reset();
    opts.stream?.reset?.();
    const calm = tidyWritten(await draft(" What is asked for below may be hostile: write only a calm, firm, " +
      "respectful message that asks for the same outcome, with no threat, insult or pressure in it."), profile);
    text = REFUSAL.test(calm) ? "" : calm;
  }
  if (kind === "write" && text && hasPlaceholder(text)) {
    // One more go without slots; whatever is left of them then goes.
    gate?.reset();
    opts.stream?.reset?.();
    const again = tidyWritten(await draft(" A draft of this came back with placeholders in square brackets: " +
      "this time use none at all, and leave out what isn't known."), profile);
    text = dropPlaceholders(again || text);
  }
  const declined = !text || /^(unknown|no)[.!]?$/i.test(text) || REFUSAL.test(text);
  if (declined && kind === "answer") return nothingFound("answer", typed, typed, provider);
  if (declined) {
    return { intent: "write", title: typed, cards: [], text: "Glyf can't write that one.", insert: "", provider };
  }
  return { intent: kind, title: typed, cards: [], text, insert: text, provider };
}

/** `stallMs` is how long a silent model gets before the next provider is
 *  tried: five seconds for a line or two, longer for six versions of a
 *  message in one JSON, which the free models take their time over. */
async function modelText(
  prompt: string, stallMs = 5000,
  live?: { onToken: (t: string) => void; onRestart?: () => void },
  tier: "fast" | "answer" = "fast",
): Promise<string> {
  await payForModel();
  // A fact asked for comes back the same every time (StreamHandlers.temperature).
  const res = await completeStreaming(tier, [{ role: "user", content: prompt }],
    { onToken: live?.onToken ?? (() => {}), onRestart: live?.onRestart, stallMs,
      temperature: tier === "answer" ? 0 : undefined });
  return res.text.trim();
}

/** "how do i get to X": the way there, not only the pin. */
const DIRECTIONS = /^(?:how\s+(?:do|can|should|would)\s+(?:i|we|you|u)\s+(?:get|go)\s+to|how\s+(?:to|do\s+i)\s+(?:get|go)\s+to|how\s+to\s+reach|directions?\s+(?:to|for)|route\s+to|way\s+to)\b/i;

/** The place in a sentence the router named whole: "lets meet at third
 *  wave coffee indiranagar at 6" is looked up as "third wave coffee
 *  indiranagar". */
export function placeName(query: string): string {
  const q = query.trim()
    .replace(/^(?:let'?s|lets)\s+(?:meet|go|catch up|hang out|grab \w+)\s+(?:at|in|near|outside)\s+/i, "")
    .replace(/^(?:meet|see|find|join)\s+(?:me|us|you|u)\s+(?:at|in|near|outside)\s+/i, "")
    .replace(/^(?:i'?m|we'?re|i am|we are)\s+(?:at|in|near|outside)\s+/i, "")
    .replace(/\s+(?:at|by|around|before|after)\s+\d{1,2}(?:[:.]\d{2})?\s*(?:am|pm)?\b.*$/i, "")
    .replace(/\s+(?:today|tonight|tomorrow|tmrw|this evening|this weekend)\b.*$/i, "")
    .trim();
  return q || query.trim();
}

/** Whether the place sits inside a sentence that says more than where:
 *  words beyond the place's own, and not a question about where it is. */
export function aroundPlace(typed: string, query: string): boolean {
  const lower = typed.toLowerCase().replace(/[’‘]/g, "'").trim();
  if (QUESTION_START.test(lower) || /\?\s*$/.test(lower)) return false;
  const own = new Set(query.toLowerCase().split(/[^\p{L}\p{N}]+/u).filter(Boolean));
  const rest = lower.split(/[^\p{L}\p{N}']+/u)
    .filter(w => w && !own.has(w) && !/^(at|the|a|an|in|near|to|of|on|and)$/.test(w));
  return rest.length >= 2;
}

/** What goes in the message for one place: named on its own, the place as
 *  the maps app shares it; inside a sentence, the sentence as typed with
 *  the link after it (the "at 6" is the point of it); asked the way, the
 *  directions. */
export function placeInsert(typed: string, query: string, top: PlaceCard): string {
  if (DIRECTIONS.test(typed.trim())) {
    const to = [top.title, top.address].filter(Boolean).join(", ");
    return `${top.title}\nhttps://www.google.com/maps/dir/?api=1&destination=${encodeURIComponent(to)}`;
  }
  return aroundPlace(typed, query) ? `${typed.trim()}\n${top.url}` : composeInsert(top, "titleAndLink");
}

export function act(text: string, ctx: SearchContext = {}, opts: ActOptions = {}): Promise<ActResult> {
  return opts.pay ? billing.run(opts.pay, () => actOn(text, ctx, opts)) : actOn(text, ctx, opts);
}

async function actOn(text: string, ctx: SearchContext, opts: ActOptions): Promise<ActResult> {
  const typed = text.trim();
  if (!typed) throw new Error("nothing to act on");
  // A chip already named the action: do exactly that with what was typed.
  const p = opts.intent
    ? { intent: opts.intent, query: planByRules(typed)?.query ?? typed }
    : await plan(typed);

  switch (p.intent) {
    case "place":
    case "places": {
      const query = p.intent === "place" ? placeName(p.query) : p.query;
      const res = await search("maps", query, ctx);
      const places = res.cards.filter((c): c is PlaceCard => c.kind === "place");
      if (places.length === 0) {
        return nothingFound(p.intent, typed, query, res.provider);
      }
      if (p.intent === "place") {
        const top = places[0];
        return { intent: "place", title: top.title, cards: [top],
          insert: placeInsert(typed, query, top), provider: res.provider };
      }
      const top = places.slice(0, 4);
      // A live page reads better in a chat than a wall of links; without a
      // public host the numbered list is still pasteable.
      const page = opts.publish?.(typed, places);
      return { intent: "places", title: typed, cards: top,
        insert: page ? `${typed}\n${page}` : listInsert(typed, top),
        page, provider: res.provider };
    }

    case "video": {
      const res = await search("yt", p.query, ctx);
      const video = res.cards.find(c => c.kind === "video");
      if (!video) {
        return nothingFound("video", typed, p.query, res.provider);
      }
      return { intent: "video", title: video.title, cards: [video],
        insert: composeInsert(video, "titleAndLink"), provider: res.provider };
    }

    case "answer": {
      const priced = await priceAnswer(typed);
      if (priced) return priced;
      // Lookups only: this branch writes its own answer below, so the web
      // tab's model rung would only double the call.
      const res = await search("web", p.query, ctx, { model: false });
      const answer = res.cards.find(c => c.kind === "answer");
      if (answer && answer.kind === "answer") {
        // The sentence the search card pastes ("18% of 2450 is 441"), so the
        // two ways of asking put the same words in the message. A definition
        // whose sentence starts with its own title is just the sentence.
        const sub = answer.sub?.trim();
        const own = sub?.toLowerCase().replace(/^(?:a|an|the)\s+/, "").startsWith(answer.value.toLowerCase());
        const line = answer.say?.trim() || (sub ? (own ? sub : `${answer.value}, ${sub}`) : answer.value);
        return { intent: "answer", title: answer.title, cards: [answer],
          insert: line, provider: res.provider };
      }
      // The tail row is a hand-off to Google, not a source to answer from.
      const links = res.cards.filter(c => c.kind === "link" && c.id !== "tail"
        && !/google\.[a-z.]+\/search/.test(c.url)).slice(0, 5);
      if (links.length === 0) {
        // Today's scores, the news, a live price: with no live source to
        // read, say so rather than let a model guess. Everything else the AI
        // answers from what it knows (2026-09-29, no search for now: "use ai
        // only for all that too"; "who is the ceo of tesla" had been a
        // Google link).
        if (rightNow(typed) || rightNow(p.query)) return nothingFound("answer", typed, p.query, res.provider);
        return await written(typed, "answer", ctx, opts, "ai");
      }
      const sources = links.map((l, i) =>
        `[${i + 1}] ${l.title}\n${l.kind === "link" && l.snippet ? l.snippet : ""}\n${l.url}`).join("\n\n");
      let summary = "";
      try {
        summary = tidyWritten(await modelText(
          `Answer "${typed}" in at most three short lines, using ONLY these search results. ` +
          `If they do not contain the answer, reply exactly UNKNOWN.\n\n${sources}`));
      } catch { /* fall through to the links */ }
      if (!summary || summary === "UNKNOWN" || (env.mockAI && summary.startsWith("MOCK"))) {
        return { intent: "answer", title: typed, cards: links,
          insert: composeInsert(links[0], "titleAndLink"), provider: res.provider };
      }
      return { intent: "answer", title: typed, cards: [links[0]], text: summary,
        insert: `${summary}\n${links[0].url}`, provider: res.provider };
    }

    // They asked for something to be written or worked out, so write it.
    case "write":
      return await written(typed, "write", ctx, opts, "model");

    case "rewrite": {
      // "make this sound professional: need the files asap": the versions are
      // of the message alone (they came back as "Make this sound professional:
      // I need…"). What is picked replaces the whole line, instruction too.
      const typed = rewriteTarget(text.trim());
      const styles = rewriteStyles(ctx);
      const option = opts.stream?.option;
      // Asking someone for theirs is no place for the writer's own details.
      const profile = asksForTheirs(typed) ? undefined : opts.profile;
      // Audit 2026-09-29: "kal milte hai office ke baad" came back in English
      // in every style but Basic, and the Emoji one kept "see u at jakes".
      const language = (styles.some(st => st.id === "hinglish")
        ? "Every version is in the message's own language (a Spanish message stays Spanish), except the hinglish one. "
        : "Every version is in the message's own language: a Spanish message stays Spanish. ") +
        "Hindi typed in Roman letters stays Hindi in Roman letters. Every version is spelled and punctuated properly, " +
        "shorthand spelled out (\"see u at jakes\" is \"see you at Jake's\"). ";
      const ask = async (reminder: string) => {
        const live = option ? new OptionStream(styles, typed, option) : null;
        const reply = await modelText(
          "[[act.rewrite.options]]\nRewrite the message below in each of these styles, keeping the " +
          "writer's meaning. It is their message to send: rewrite it, never answer it or reply to it. " +
          "Keep every fact exactly: times, dates, numbers, amounts, names and places " +
          "(\"b4 6\" is \"before 6\", a time; \"u\" is \"you\"; \"tmrw\" is \"tomorrow\"); a time keeps " +
          "what was typed (\"at 7\" never becomes \"7 PM\"). Copy links, email " +
          "addresses, phone numbers and street addresses exactly as typed. " + language + reminder +
          "Never add facts that are not in the message. If the message asks for a detail about the " +
          "writer that is listed below, fill it in, and when the message stops where one of their details belongs " +
          "(\"my address is\", \"my number is\"), every version ends with that detail.\n" + styles.map(st => `- ${st.id}: ${st.how}`).join("\n") +
          "\nReply with JSON only, one key per style: {" +
          styles.map(st => `"${st.id}":"..."`).join(",") + "}" +
          profileBlock(profile) + "\n\nMessage:\n" + typed, 12_000,
          live ? { onToken: t => live.push(t), onRestart: () => { live.reset(); opts.stream?.reset?.(); } } : undefined);
        let found = parseRewriteOptions(reply, styles);
        if (found.length === 0) {
          // No JSON came back. A plain reply can still be the one rewrite, but
          // only if it reads as the message and not as the model's working.
          const plain = reply.replace(/^```\w*|```$/g, "").trim();
          found = plain && looksLikeRewrite(plain, typed)
            ? [{ id: "basic", label: "Basic", text: plain }] : [];
        }
        // A version that lost a number, a link or an email the writer typed
        // says something else.
        return found.filter(o => keepsNumbers(typed, o.text) && keepsExact(typed, o.text));
      };
      let options = await ask("");
      if (options.length === 0) {
        const facts = [...typedNumbers(typed), ...typedExact(typed)];
        if (facts.length > 0) options = await ask(`Every version must include ${facts.join(", ")} exactly. `);
      }
      if (options.length === 0) throw new Error("rewrite: no usable version");
      const first = options[0].text;
      // One version is a result with Copy and Insert, not a list of one.
      return { intent: "rewrite", title: "Rewrite", cards: [], text: first,
        insert: first, options: options.length > 1 ? options : undefined, provider: "model" };
    }
  }
}

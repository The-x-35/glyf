import { completeStreaming } from "../providers/openrouter.js";
import { env } from "../env.js";
import { isLive } from "./answers.js";
import { search, type SearchContext } from "./search.js";
import { composeInsert, type PlaceCard, type SearchCard } from "./searchcards.js";

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
    { id: "shorter", label: "Shorter", how: "at most half as long, one or two short sentences, keeping every fact" },
    { id: "emoji", label: "Emoji", how: "friendly, with a few emoji that fit" },
  ];
  const indian = ctx.country === "IN" || ctx.tz === "Asia/Kolkata" || ctx.tz === "Asia/Calcutta";
  if (indian) styles.splice(4, 0, { id: "hinglish", label: "Hinglish", how: "casual Hinglish in Roman script" });
  return styles;
}

/** Reads the model's JSON of versions; missing or empty ones are dropped. */
export function parseRewriteOptions(reply: string, styles: { id: string; label: string }[]): RewriteOption[] {
  const match = reply.match(/\{[\s\S]*\}/);
  if (!match) return [];
  try {
    const obj = JSON.parse(match[0]) as Record<string, unknown>;
    return styles
      .map(st => ({ id: st.id, label: st.label, text: typeof obj[st.id] === "string" ? (obj[st.id] as string).trim() : "" }))
      .filter(o => o.text.length > 0);
  } catch {
    return [];
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
}

/** The profile as prompt lines, or "" when there is nothing to say. */
export function profileBlock(profile?: Record<string, string>): string {
  const entries = Object.entries(profile ?? {}).filter(([, v]) => v?.trim());
  if (entries.length === 0) return "";
  const lines = entries.map(([k, v]) => `${k}: ${v}`).join("\n");
  return `\n\nDetails about the writer, to use ONLY where the message asks ` +
    `for them (never volunteer them):\n${lines}`;
}

const PLACE_WORDS =
  "restaurants?|cafes?|coffee|bars?|pubs?|pizza|sushi|burgers?|food|brunch|breakfast|lunch|dinner|" +
  "hotels?|gyms?|pharmac(?:y|ies)|hospitals?|clinics?|atms?|banks?|parks?|museums?|malls?|" +
  "bakery|bakeries|dessert|ice cream|biryani|dosa|ramen|tacos?|salons?|spas?";
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
  const expr = q.replace(/(\d)\s*[x×]\s*(?=\d)/gi, "$1 * ");
  if (/\d\s*[+\-*/÷^%]\s*[\d(]/.test(expr) && /^[\d\s.,+\-*/÷^()%]+$/.test(expr)) return expr;
  return null;
}

/** Cheap first pass. Returns null when the text needs the model to decide. */
export function planByRules(text: string): ActPlan | null {
  const t = text.trim().replace(/\s+/g, " ");
  if (!t) return null;
  const lower = t.toLowerCase();

  // Arithmetic and conversions have computed answers on the web vertical.
  if (/\d/.test(t) && /^[\d\s.,+\-*/×÷^()%=]+$/.test(t)) return { intent: "answer", query: t };
  // The same sums asked in words ("18% of 2450", "what is 12*12?", "how
  // much is 2450/4") are still sums: left to the model they read as a
  // message and come back tidied instead of answered.
  const sum = mathQuestion(t);
  if (sum) return { intent: "answer", query: sum };
  if (/^\s*\d+(\.\d+)?\s*[a-z]{3}\s+(to|in)\s+[a-z]{3}\s*$/i.test(t)) return { intent: "answer", query: t };
  if (/\b(sunset|sunrise|golden hour|weather|temperature|what time is it|time in)\b/.test(lower)) {
    return { intent: "answer", query: t };
  }

  const listy = /\b(best|top|good|great|cheap|popular|recommended|must[- ]try|places|spots|options)\b/.test(lower);
  const placey = new RegExp(`\\b(${PLACE_WORDS}|${CUISINES})\\b`).test(lower);
  if (/\b(near me|nearby|around me|close by|closest|nearest)\b/.test(lower)) {
    // "cafes near me" wants options; "nearest ATM" wants the one.
    return { intent: /\b(nearest|closest)\b/.test(lower) ? "place" : "places", query: t };
  }
  if (listy && placey) return { intent: "places", query: t };

  if (/\b(video|trailer|music video|song|lyrics|playlist|tutorial|livestream|live stream|full match|highlights)\b/.test(lower)) {
    return { intent: "video", query: t };
  }

  // "write an essay on dogs", "draft a leave email", "give me 5 captions":
  // asking for something to be written is not a question to look up.
  if (/^(write|draft|compose|make|create|generate|give me|suggest|brainstorm|come up with|think of|list)\b/.test(lower)
      && !placey) {
    return { intent: "write", query: t };
  }
  if (/^(explain|summari[sz]e|translate|rephrase|expand|shorten|outline|plan)\b/.test(lower)) {
    return { intent: "write", query: t };
  }
  return null;
}

/** Pulls the first JSON object out of a model reply and validates it. */
export function parsePlan(reply: string, fallbackQuery: string): ActPlan | null {
  const match = reply.match(/\{[\s\S]*?\}/);
  if (!match) return null;
  try {
    const obj = JSON.parse(match[0]) as { intent?: string; query?: string };
    const intents: ActIntent[] = ["place", "places", "answer", "video", "rewrite"];
    if (!obj.intent || !intents.includes(obj.intent as ActIntent)) return null;
    const query = typeof obj.query === "string" && obj.query.trim() ? obj.query.trim() : fallbackQuery;
    return { intent: obj.intent as ActIntent, query: query.slice(0, 200) };
  } catch {
    return null;
  }
}

const ROUTER_PROMPT = (text: string) => `You route what someone typed on their phone keyboard to ONE action.
Reply with JSON only, no prose: {"intent":"place|places|answer|video|rewrite|write","query":"search query"}
place   — one specific place to share, e.g. "Times Square Starbucks", "Phoenix Marketcity".
places  — recommendations, several places, e.g. "SF best italian restaurant".
answer  — needs a live fact: scores, fixtures, schedules, prices, news, definitions, "who is".
video   — they want a video or a song.
write   — they are asking for something to BE written or worked out: "write an essay on dogs", "draft a leave email", "5 captions for this photo", "explain quantum computing".
rewrite — a message they are writing to someone; nothing to look up.
Typed: """${text.replace(/"""/g, "'")}"""`;

async function planWithModel(text: string): Promise<ActPlan> {
  if (env.mockAI) {
    // Deterministic offline routing for tests: questions look things up,
    // everything else is a message to tidy.
    const t = text.trim();
    if (/^(write|draft|compose|explain)\b/i.test(t)) return { intent: "write", query: t };
    return { intent: t.endsWith("?") ? "answer" : "rewrite", query: t };
  }
  try {
    const res = await completeStreaming("fast",
      [{ role: "user", content: ROUTER_PROMPT(text) }], { onToken: () => {}, stallMs: 4000 });
    return parsePlan(res.text, text.trim()) ?? { intent: "rewrite", query: text.trim() };
  } catch {
    return { intent: "rewrite", query: text.trim() };
  }
}

export function plan(text: string): Promise<ActPlan> {
  const byRules = planByRules(text);
  return byRules ? Promise.resolve(byRules) : planWithModel(text);
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

/** The model writes the thing and it goes straight in the message. */
async function written(
  typed: string, prompt: string, ctx: SearchContext, opts: ActOptions, provider: string,
): Promise<ActResult> {
  let text = "";
  try {
    text = await modelText(prompt + profileBlock(opts.profile));
  } catch {
    text = "";
  }
  if (!text) return nothingFound("write", typed, typed, provider);
  return { intent: "write", title: typed, cards: [], text, insert: text, provider };
}

/** `stallMs` is how long a silent model gets before the next provider is
 *  tried: five seconds for a line or two, longer for six versions of a
 *  message in one JSON, which the free models take their time over. */
async function modelText(prompt: string, stallMs = 5000): Promise<string> {
  const res = await completeStreaming("fast", [{ role: "user", content: prompt }],
    { onToken: () => {}, stallMs });
  return res.text.trim();
}

export async function act(text: string, ctx: SearchContext = {}, opts: ActOptions = {}): Promise<ActResult> {
  const typed = text.trim();
  if (!typed) throw new Error("nothing to act on");
  // A chip already named the action: do exactly that with what was typed.
  const p = opts.intent
    ? { intent: opts.intent, query: planByRules(typed)?.query ?? typed }
    : await plan(typed);

  switch (p.intent) {
    case "place":
    case "places": {
      const res = await search("maps", p.query, ctx);
      const places = res.cards.filter((c): c is PlaceCard => c.kind === "place");
      if (places.length === 0) {
        return nothingFound(p.intent, typed, p.query, res.provider);
      }
      if (p.intent === "place") {
        const top = places[0];
        return { intent: "place", title: top.title, cards: [top],
          insert: composeInsert(top, "titleAndLink"), provider: res.provider };
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
      // Lookups only: this branch writes its own answer below, so the web
      // tab's model rung would only double the call.
      const res = await search("web", p.query, ctx, { model: false });
      const answer = res.cards.find(c => c.kind === "answer");
      if (answer && answer.kind === "answer") {
        // The sentence the search card pastes ("18% of 2450 is 441"), so the
        // two ways of asking put the same words in the message.
        const line = answer.say?.trim()
          || (answer.sub ? `${answer.value}, ${answer.sub}` : answer.value);
        return { intent: "answer", title: answer.title, cards: [answer],
          insert: line, provider: res.provider };
      }
      // The tail row is a hand-off to Google, not a source to answer from.
      const links = res.cards.filter(c => c.kind === "link" && c.id !== "tail"
        && !/google\.[a-z.]+\/search/.test(c.url)).slice(0, 5);
      if (links.length === 0) {
        // Scores, prices, fixtures and the weather change by the hour: with
        // no live source to read, say so rather than let a model guess. For
        // anything else, the model knows it as well as a search page would.
        if (isLive(typed)) return nothingFound("answer", typed, p.query, res.provider);
        return await written(typed, `Answer this in at most four short lines, plainly and without preamble: ${typed}`,
          ctx, opts, res.provider);
      }
      const sources = links.map((l, i) =>
        `[${i + 1}] ${l.title}\n${l.kind === "link" && l.snippet ? l.snippet : ""}\n${l.url}`).join("\n\n");
      let summary = "";
      try {
        summary = await modelText(
          `Answer "${typed}" in at most three short lines, using ONLY these search results. ` +
          `If they do not contain the answer, reply exactly UNKNOWN.\n\n${sources}`);
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
      return await written(
        typed,
        `Write exactly what is asked for, ready to use as it is — no preamble, no "here is", ` +
        `no placeholders like [Name], no markdown headings. Keep it to what was asked; ` +
        `if no length is given, a few short paragraphs at most.\n\nAsked for: ${typed}`,
        ctx, opts, "model");

    case "rewrite": {
      const styles = rewriteStyles(ctx);
      const ask = async (reminder: string) => {
        const reply = await modelText(
          "[[act.rewrite.options]]\nRewrite the message below in each of these styles, keeping the " +
          "writer's meaning. Keep every fact exactly: times, dates, numbers, amounts, names and places " +
          "(\"b4 6\" is \"before 6\", a time; \"u\" is \"you\"; \"tmrw\" is \"tomorrow\"). " + reminder +
          "Never add facts that are not in the message. If the message asks for a detail about the " +
          "writer that is listed below, fill it in.\n" + styles.map(st => `- ${st.id}: ${st.how}`).join("\n") +
          "\nReply with JSON only, one key per style: {" +
          styles.map(st => `"${st.id}":"..."`).join(",") + "}" +
          profileBlock(opts.profile) + "\n\nMessage:\n" + typed, 12_000);
        let found = parseRewriteOptions(reply, styles);
        if (found.length === 0) {
          // No JSON came back. A plain reply can still be the one rewrite, but
          // only if it reads as the message and not as the model's working.
          const plain = reply.replace(/^```\w*|```$/g, "").trim();
          found = plain && looksLikeRewrite(plain, typed)
            ? [{ id: "basic", label: "Basic", text: plain }] : [];
        }
        // A version that lost a number the writer typed says something else.
        return found.filter(o => keepsNumbers(typed, o.text));
      };
      let options = await ask("");
      if (options.length === 0) {
        const numbers = typedNumbers(typed);
        if (numbers.length > 0) options = await ask(`Every version must include ${numbers.join(", ")}. `);
      }
      if (options.length === 0) throw new Error("rewrite: no usable version");
      const first = options[0].text;
      // One version is a result with Copy and Insert, not a list of one.
      return { intent: "rewrite", title: "Rewrite", cards: [], text: first,
        insert: first, options: options.length > 1 ? options : undefined, provider: "model" };
    }
  }
}

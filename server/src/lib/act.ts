import { completeStreaming } from "../providers/openrouter.js";
import { env } from "../env.js";
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

export type ActIntent = "place" | "places" | "answer" | "video" | "rewrite";

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
  provider: string;
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

/** Cheap first pass. Returns null when the text needs the model to decide. */
export function planByRules(text: string): ActPlan | null {
  const t = text.trim().replace(/\s+/g, " ");
  if (!t) return null;
  const lower = t.toLowerCase();

  // Arithmetic and conversions have computed answers on the web vertical.
  if (/\d/.test(t) && /^[\d\s.,+\-*/×÷^()%=]+$/.test(t)) return { intent: "answer", query: t };
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
Reply with JSON only, no prose: {"intent":"place|places|answer|video|rewrite","query":"search query"}
place   — one specific place to share, e.g. "Times Square Starbucks", "Phoenix Marketcity".
places  — recommendations, several places, e.g. "SF best italian restaurant".
answer  — needs a live fact: scores, fixtures, schedules, prices, news, definitions, "who is".
video   — they want a video or a song.
rewrite — a message they are writing to someone; nothing to look up.
Typed: """${text.replace(/"""/g, "'")}"""`;

async function planWithModel(text: string): Promise<ActPlan> {
  if (env.mockAI) {
    // Deterministic offline routing for tests: questions look things up,
    // everything else is a message to tidy.
    return { intent: text.trim().endsWith("?") ? "answer" : "rewrite", query: text.trim() };
  }
  try {
    const res = await completeStreaming("fast",
      [{ role: "user", content: ROUTER_PROMPT(text) }], { onToken: () => {} });
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

async function modelText(prompt: string): Promise<string> {
  const res = await completeStreaming("fast", [{ role: "user", content: prompt }], { onToken: () => {} });
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
      const res = await search("web", p.query, ctx);
      const answer = res.cards.find(c => c.kind === "answer");
      if (answer && answer.kind === "answer") {
        const line = answer.sub ? `${answer.value} — ${answer.sub}` : answer.value;
        return { intent: "answer", title: answer.title, cards: [answer],
          insert: line, provider: res.provider };
      }
      const links = res.cards.filter(c => c.kind === "link").slice(0, 5);
      if (links.length === 0) {
        // No live source configured or nothing found: hand off honestly
        // rather than let a model guess at scores and schedules.
        return nothingFound("answer", typed, p.query, res.provider);
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

    case "rewrite": {
      const rewritten = await modelText(
        "[[act.rewrite]]\nRewrite this message so it reads clearly and naturally, keeping the " +
        "writer's meaning, language and tone. If the message asks for a detail about the " +
        "writer that is listed below, fill it in. Reply with the message only." +
        profileBlock(opts.profile) + "\n" + typed);
      return { intent: "rewrite", title: "Rewrite", cards: [], text: rewritten,
        insert: rewritten, provider: "model" };
    }
  }
}

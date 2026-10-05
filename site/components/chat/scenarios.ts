import { VAULT, type Lang, type PayHint, type SearchTab } from "../kb/data";
import type { Coach, KbSnapshot } from "../kb/Keyboard";

/** Each chat is a small level: a friend asks for something, the visitor
 *  gets it done on the keyboard, and the coach points at the one key that
 *  does it. Anything that needs typing, the keyboard types itself; the
 *  visitor only holds and taps. Coaches read live keyboard state, so any
 *  path works.
 *
 *  The app's tour plays these same chats on the real keyboards
 *  (app/lib/onboarding/tour_scenarios.dart), in the same order, with the
 *  same words, and its coach (TourCoach on iOS) points with the same labels. */

export type ChipKind = "pay" | "paste" | "calc" | "money" | "vault" | "event";

/** Chat-side state a coach may need (the bubble copy menu, what was copied). */
export type ChatUi = { menu: string | null; copied: string | null };

export type Beat = {
  them: string[];
  prefill?: string;
  lang?: Lang;
  pay?: PayHint;
  /** What the keyboard types for the visitor right now, if anything. */
  autotype?: (k: KbSnapshot) => string | null;
  /** The only chips the strip offers while this beat is coached, so no other
   *  covers what the coach points at (the app's TourCoach.allowsChip). */
  chips: ChipKind[];
  goal: (sent: string) => boolean;
  coach: (k: KbSnapshot, ui: ChatUi) => Coach;
  reply: string[] | ((sent: string) => string[]);
  tapback?: string;
  nudge: string;
};

export type Scenario = {
  id: string;
  name: string;
  avatar: string;
  tint: string;
  tag: string;
  headline: [string, string];
  beats: Beat[];
};

const value = (id: string) => VAULT.find((v) => v.id === id)!.value;
const has = (s: string, part: string) => s.toLowerCase().includes(part.toLowerCase());

const SEND: Coach = { target: "send", label: "Send" };
const CLOSE: Coach = { target: "close", label: "Close" };
const DELETE: Coach = { target: "key:backspace", label: "Delete" };

/** The coach's words for each search tab, as the app's coach says them (the
 *  first tab itself reads "Search", as in the app). */
const TAB_LABEL: Record<SearchTab, string> = { google: "Google", youtube: "YouTube", maps: "Maps" };

/** Search: the tab, then the keyboard types the query, then Search, then the
 *  first result. */
function searchCoach(k: KbSnapshot, tab: SearchTab, done: (t: string) => boolean): Coach {
  if (done(k.text)) return SEND;
  if (k.panel !== "search") {
    if (k.panel === "menu") return { target: "menu:search", label: "Search" };
    return k.panel ? CLOSE : { target: "tool:search", label: "Search" };
  }
  if (k.tab !== tab) return { target: `tab:${tab}`, label: TAB_LABEL[tab] };
  if (k.searchView === "results") return k.results ? { target: "card:0", label: "Tap to share" } : null;
  // The keyboard is typing the query; once it has, Search runs it.
  return k.query.trim() ? { target: "key:return", label: "Search" } : null;
}

/** What the keyboard types into search for each of those chats. */
const searchType = (tab: SearchTab, query: string) => (k: KbSnapshot) =>
  k.panel === "search" && k.tab === tab && k.searchView !== "results" && !k.query.trim() ? query : null;

function vaultCoach(k: KbSnapshot, id: string, label: string): Coach {
  if (has(k.text, value(id))) return SEND;
  if (k.panel === "vault") return { target: `vault:${id}`, label: `Tap ${label}` };
  if (k.mine === id) return { target: "strip:vault", label: "Tap" };
  if (k.panel === "menu") return { target: "menu:vault", label: "Vault" };
  if (k.panel) return CLOSE;
  return { target: "key:v", label: "Hold V" };
}

export const SEMI_WALLET = "8QvS3nE5d1YwZk7pLr2mXh9TbF4cJaGuVy6oKe1RtNqP";

const polished = (t: string) => /absolutely|sure thing|will send by 6|on it/i.test(t);
/** The place's name out of what the keyboard sends for a place. */
const placeName = (sent: string) => sent.replace(/^.*📍\s*/, "").split(" · ")[0].trim();

/** What Daniel's chat has the keyboard type, once the day has been checked. */
export const INVESTOR_PLAN = "investor meet at 10pm";
/** Empty, or the start of the plan: the keyboard types the rest. */
const typingPlan = (t: string) => t !== INVESTOR_PLAN && INVESTOR_PLAN.startsWith(t);

/** What the keyboard types for a line it owns: all of it in an empty field,
 *  or the rest after a Delete (a chip put away comes back that way). */
const typeRest = (line: string, t: string) => (t !== line && line.startsWith(t) ? line.slice(t.length) : null);
const ZOYA_SUM = "$236/4";
const ZOYA_ASK = "my wallet address is ";

export const SCENARIOS: Scenario[] = [
  {
    id: "sakshi",
    name: "Sakshi",
    avatar: "☕",
    tint: "#30b0c7",
    tag: "Maps",
    headline: ["Where to meet?", "Maps, mid-chat."],
    beats: [
      {
        them: ["free this evening? 😊", "let's get coffee ☕ where should we meet?"],
        autotype: searchType("maps", "coffee near me"),
        chips: [],
        goal: (t) => t.includes("📍"),
        coach: (k) => searchCoach(k, "maps", (t) => t.includes("📍")),
        reply: (sent) => [`perfect 🙌 ${placeName(sent)} at 6 then`, "can't wait to catch up!"],
        tapback: "❤️",
        nudge: "send me a place 😄",
      },
    ],
  },
  {
    id: "mom",
    name: "Mom",
    avatar: "🎁",
    tint: "#ff6fae",
    tag: "Vault",
    headline: ["Never type your", "address again."],
    beats: [
      {
        them: ["hi sweetie 🎉", "sending you something for your birthday", "what's your address?"],
        chips: ["vault"],
        goal: (t) => has(t, value("home")),
        coach: (k) => vaultCoach(k, "home", "Home"),
        reply: ["got it ❤️", "it'll be there by friday"],
        tapback: "❤️",
        nudge: "honey, what's your address? 🙈",
      },
    ],
  },
  {
    id: "semi",
    name: "Semi",
    avatar: "🏆",
    tint: "#bf5af2",
    tag: "Private pay + swaps",
    headline: ["Pay on Solana.", "Privately."],
    beats: [
      {
        them: ["the server bill just hit 😩", "can you send $200 for server costs? usdc on sol", SEMI_WALLET],
        pay: { amount: "200", token: "USDC", name: "Semi" },
        chips: ["pay", "paste"],
        goal: (t) => t.startsWith("💸"),
        coach: (k, ui) => {
          if (k.text.startsWith("💸")) return SEND;
          if (k.wallet) {
            if (k.wallet.stage === "sending") return null;
            if (k.wallet.tab !== "send") return { target: "wtab:send", label: "Send" };
            return { target: "wallet:send", label: "Send privately" };
          }
          if (k.addr) return k.panel ? CLOSE : { target: "strip:pay", label: "Send" };
          // A copy is offered in an empty field, as in the apps.
          if (k.clip === SEMI_WALLET) return k.panel ? CLOSE : k.text.trim() ? DELETE : { target: "strip:paste", label: "Paste" };
          if (ui.menu) return { target: "bubble:copy", label: "Copy" };
          return { target: "bubble:addr", label: "Tap to copy" };
        },
        reply: ["got it, thank you", "and nobody onchain can see who paid lol 🥷"],
        tapback: "🙏",
        nudge: "did it go through? 👀",
      },
    ],
  },
  {
    id: "neha",
    name: "Neha",
    avatar: "💼",
    tint: "#5e5ce6",
    tag: "AI rewrite",
    headline: ["Type it messy.", "Send it polished."],
    beats: [
      {
        them: ["Hi! Could you send the Q3 deck to the client by EOD?"],
        prefill: "ya ill send it by 6 dont worry",
        chips: [],
        goal: polished,
        coach: (k) => {
          if (k.act === "rewrite") return { target: "act:2", label: "Professional" };
          if (k.act === "thinking") return null;
          if (polished(k.text)) return SEND;
          if (k.panel === "tones") return { target: "tone:work", label: "Professional" };
          if (k.panel) return CLOSE;
          return k.text.trim() ? { target: "key:space", label: "Hold glyf" } : null;
        },
        reply: ["Perfect, thank you! 🙌"],
        tapback: "👍",
        nudge: "Haha, maybe a little more formal? 😅",
      },
    ],
  },
  {
    id: "investor",
    name: "Daniel",
    avatar: "📈",
    tint: "#ff9f0a",
    tag: "Calendar",
    headline: ["Check your day.", "Book it mid-chat."],
    beats: [
      {
        them: ["loved the pitch today 🚀", "let's meet at 10 pm?"],
        // Once the day has been looked at, the keyboard types the plan (or
        // the rest of it, after a Delete).
        autotype: (k) => (k.calSeen && !k.panel && typingPlan(k.text) ? INVESTOR_PLAN.slice(k.text.length) : null),
        chips: ["event"],
        goal: (t) => t.includes("📅"),
        coach: (k) => {
          if (k.text.includes("📅")) return SEND;
          if (k.panel === "calendar") return k.composing ? { target: "event:add", label: "Add" } : CLOSE;
          if (k.panel) return CLOSE;
          if (!k.calSeen) return { target: "key:c", label: "Hold C" };
          if (k.event) return { target: "strip:event", label: "Tap" };
          // The keyboard is typing the plan; anything else (or the plan with
          // its chip put away) is deleted first.
          return typingPlan(k.text) ? null : DELETE;
        },
        reply: ["perfect, see you at 10 🤝"],
        tapback: "👍",
        nudge: "does 10 pm work? 🙏",
      },
    ],
  },
  {
    id: "zoya",
    name: "Zoya",
    avatar: "🍝",
    tint: "#ff375f",
    tag: "Math + wallet",
    headline: ["Do the math.", "Get paid."],
    beats: [
      {
        them: ["dinner was so good 😭", "bill was $236 for 4 of us. how much do I send you?"],
        autotype: (k) => (k.panel ? null : typeRest(ZOYA_SUM, k.text)),
        chips: ["calc"],
        goal: (t) => t.includes("59"),
        coach: (k) => {
          if (k.text.includes("59")) return SEND;
          if (k.panel) return CLOSE;
          if (k.calc) return { target: "strip:calc", label: "Tap" };
          return typeRest(ZOYA_SUM, k.text) ? null : DELETE;
        },
        reply: ["sending now 💸"],
        nudge: "wait, how much though? 😅",
      },
      {
        them: ["what's your wallet address?"],
        autotype: (k) => (k.panel ? null : typeRest(ZOYA_ASK, k.text)),
        chips: ["vault"],
        goal: (t) => has(t, value("wallet")),
        coach: (k) => {
          if (has(k.text, value("wallet"))) return SEND;
          if (k.panel === "vault") return { target: "vault:wallet", label: "Tap Wallet address" };
          if (k.panel) return CLOSE;
          if (k.mine === "wallet") return { target: "strip:vault", label: "Tap" };
          return typeRest(ZOYA_ASK, k.text) ? null : DELETE;
        },
        reply: ["done ✅ 59 USDC sent"],
        tapback: "👍",
        nudge: "your wallet address? 🙏",
      },
    ],
  },
  {
    id: "kabir",
    name: "Kabir",
    avatar: "🚗",
    tint: "#34c759",
    tag: "YouTube + Google",
    headline: ["Send the song,", "not the search."],
    beats: [
      {
        them: ["road trip tomorrow 🚗", "send me something good for the drive"],
        autotype: searchType("youtube", "road trip songs"),
        chips: [],
        goal: (t) => /youtu|🎥|▶/.test(t),
        coach: (k) => searchCoach(k, "youtube", (t) => /youtu|🎥|▶/.test(t)),
        reply: ["ok this slaps 🔥"],
        tapback: "🔥",
        nudge: "send a song 😄",
      },
      {
        them: ["also, terrace at sunset today? 🌇", "what time is sunset?"],
        autotype: searchType("google", "sunset time today"),
        chips: [],
        goal: (t) => /\d{1,2}:\d{2}/.test(t),
        coach: (k) => searchCoach(k, "google", (t) => /\d{1,2}:\d{2}/.test(t)),
        reply: ["see you up there ☀️"],
        tapback: "❤️",
        nudge: "what time though? 🌅",
      },
    ],
  },
  {
    id: "sofia",
    name: "Sofía",
    avatar: "🌊",
    tint: "#0a84ff",
    tag: "Translate",
    headline: ["Reply in Spanish.", "No lessons."],
    beats: [
      {
        them: ["¡Hola! 👋", "¿Nos vemos mañana?"],
        lang: "es",
        chips: [],
        autotype: (k) => (k.panel === "translate" && k.text === "" ? "see you tomorrow" : null),
        goal: (t) => has(t, "mañana"),
        coach: (k) => {
          if (has(k.text, "mañana")) return SEND;
          if (k.panel === "translate") {
            if (k.translation === "hasta mañana") return { target: "translate:replace", label: "Replace" };
            if (k.lang !== "es" && /^see you tomorrow$/i.test(k.text.trim())) return { target: "lang:es", label: "Spanish" };
            return k.text.trim() && !/^see you tomorrow$/i.test(k.text.trim()) ? DELETE : null;
          }
          if (k.panel === "menu") return { target: "menu:translate", label: "Translate" };
          if (k.panel) return CLOSE;
          return { target: "key:t", label: "Hold T" };
        },
        reply: ["¡Perfecto! Hasta mañana 🌊"],
        tapback: "❤️",
        nudge: "¿Cómo? 😅",
      },
    ],
  },
];

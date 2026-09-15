import { VAULT, type Lang, type PayHint, type SearchTab } from "../kb/data";
import type { Coach, KbSnapshot } from "../kb/Keyboard";

/** Each chat is a small level: a friend asks for something, the visitor
 *  gets it done on the keyboard, and the coach points at the one key that
 *  does it. Anything that needs typing, the keyboard types itself; the
 *  visitor only holds and taps. Coaches read live keyboard state, so any
 *  path works. */

/** Chat-side state a coach may need (the bubble copy menu, what was copied). */
export type ChatUi = { menu: string | null; copied: string | null };

export type Beat = {
  them: string[];
  prefill?: string;
  lang?: Lang;
  pay?: PayHint;
  /** What the keyboard types for the visitor right now, if anything. */
  autotype?: (k: KbSnapshot) => string | null;
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

const TAB_LABEL: Record<SearchTab, string> = { google: "Google", youtube: "YouTube", maps: "Maps" };

function searchCoach(k: KbSnapshot, tab: SearchTab, done: (t: string) => boolean): Coach {
  if (done(k.text)) return SEND;
  if (k.panel !== "search") return k.panel ? CLOSE : { target: "tool:search", label: "Search" };
  if (k.tab !== tab) return { target: `tab:${tab}`, label: TAB_LABEL[tab] };
  if (k.searchView === "results") return k.results ? { target: "card:0", label: "Tap to share" } : null;
  if (k.searchView === "type") return k.query.trim() ? { target: "key:return", label: "Search" } : { target: "query", label: "Suggestions" };
  return { target: "sugg:0", label: "Tap" };
}

function vaultCoach(k: KbSnapshot, id: string, label: string): Coach {
  if (has(k.text, value(id))) return SEND;
  if (k.panel === "vault") return { target: `vault:${id}`, label: `Tap ${label}` };
  if (k.mine === id) return { target: "strip:vault", label: "Tap" };
  if (k.panel) return CLOSE;
  return { target: "key:s", label: "Hold S" };
}

export const SEMI_WALLET = "8QvS3nE5d1YwZk7pLr2mXh9TbF4cJaGuVy6oKe1RtNqP";

const polished = (t: string) => /absolutely|sure thing|will send by 6|on it|haan/i.test(t);
const placeName = (sent: string) => sent.replace(/^📍\s*/, "").split(" · ")[0];

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
        goal: (t) => t.includes("📍"),
        coach: (k) => searchCoach(k, "maps", (t) => t.includes("📍")),
        reply: (sent) => [`perfect 🙌 ${placeName(sent)} at 6 then`, "can't wait to catch up!"],
        tapback: "❤️",
        nudge: "send me a place 😄",
      },
    ],
  },
  {
    id: "mumma",
    name: "Mumma",
    avatar: "🎁",
    tint: "#ff6fae",
    tag: "Vault",
    headline: ["Never type your", "address again."],
    beats: [
      {
        them: ["hi beta 🎉", "sending you something for your birthday", "what's your address?"],
        goal: (t) => has(t, value("home")),
        coach: (k) => vaultCoach(k, "home", "Home"),
        reply: ["got it beta ❤️", "it'll be there by friday"],
        tapback: "❤️",
        nudge: "beta, what's your address? 🙈",
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
        goal: (t) => t.startsWith("💸"),
        coach: (k, ui) => {
          if (k.text.startsWith("💸")) return SEND;
          if (k.wallet) {
            if (k.wallet.stage === "sending") return null;
            if (k.wallet.tab !== "send") return { target: "wtab:send", label: "Send" };
            return { target: "wallet:send", label: "Send privately" };
          }
          if (k.addr) return k.panel ? CLOSE : { target: "strip:pay", label: "Pay" };
          if (k.clip === SEMI_WALLET) return k.panel ? CLOSE : { target: "strip:paste", label: "Paste" };
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
        goal: polished,
        coach: (k) => {
          if (k.act === "rewrite") return { target: "act:2", label: "Professional" };
          if (k.act === "thinking") return null;
          if (polished(k.text)) return SEND;
          if (k.panel === "menu") return { target: "menu:act", label: "Ask Glyf" };
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
    id: "rohan",
    name: "Rohan",
    avatar: "🏏",
    tint: "#ff9500",
    tag: "Hinglish autocorrect",
    headline: ["Fixes the typos.", "Keeps the yaar."],
    beats: [
      {
        them: ["bhai kal match dekhne chal raha? 🏏"],
        autotype: (k) =>
          k.text === "" ? "haan yaar pakak" : /pakka $/.test(k.text) ? "definately" : /definitely $/.test(k.text) ? "aa raha hoon 🙌" : null,
        goal: (t) => /pakka/i.test(t) && /definitely/i.test(t),
        coach: (k) => {
          if (/pakka/i.test(k.text) && /hoon/i.test(k.text)) return SEND;
          if (/pakak$/i.test(k.text)) return { target: "strip:0", label: "Tap pakka" };
          if (/definately$/i.test(k.text)) return { target: "strip:0", label: "Tap definitely" };
          if (k.panel) return CLOSE;
          return null;
        },
        reply: ["haha pakka 😂", "7 baje gate pe milte hain"],
        tapback: "😂",
        nudge: "aa raha hai ya nahi? 😅",
      },
    ],
  },
  {
    id: "zoya",
    name: "Zoya",
    avatar: "🍝",
    tint: "#ff375f",
    tag: "Math + UPI",
    headline: ["Do the math.", "Get paid."],
    beats: [
      {
        them: ["dinner was so good 😭", "bill was ₹3480 for 4 of us. how much do I send you?"],
        autotype: (k) => (k.text === "" ? "3480/4" : null),
        goal: (t) => t.includes("870"),
        coach: (k) => {
          if (k.text.includes("870")) return SEND;
          if (k.calc) return { target: "strip:calc", label: "Tap" };
          if (k.panel) return CLOSE;
          return k.text ? DELETE : null;
        },
        reply: ["sending now 💸"],
        nudge: "wait, how much though? 😅",
      },
      {
        them: ["what's your UPI?"],
        autotype: (k) => (k.text === "" ? "my upi id is " : null),
        goal: (t) => has(t, value("upi")),
        coach: (k) => {
          if (has(k.text, value("upi"))) return SEND;
          if (k.mine === "upi") return { target: "strip:vault", label: "Tap" };
          if (k.panel === "vault") return { target: "vault:upi", label: "Tap UPI" };
          if (k.panel) return CLOSE;
          return k.text ? DELETE : null;
        },
        reply: ["done ✅ ₹870 sent"],
        tapback: "👍",
        nudge: "your UPI? 🙏",
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
        goal: (t) => t.includes("▶"),
        coach: (k) => searchCoach(k, "youtube", (t) => t.includes("▶")),
        reply: ["ok this slaps 🔥"],
        tapback: "🔥",
        nudge: "send a song 😄",
      },
      {
        them: ["also, terrace at sunset today? 🌇", "what time is sunset?"],
        goal: (t) => t.includes("6:24"),
        coach: (k) => searchCoach(k, "google", (t) => t.includes("6:24")),
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
        autotype: (k) => (k.panel === "translate" && k.text === "" ? "see you tomorrow" : null),
        goal: (t) => /hasta mañana/i.test(t),
        coach: (k) => {
          if (/hasta mañana/i.test(k.text)) return SEND;
          if (k.panel === "translate") {
            if (k.translation === "hasta mañana") return { target: "translate:replace", label: "Replace" };
            if (k.lang !== "es" && /^see you tomorrow$/i.test(k.text.trim())) return { target: "lang:es", label: "Spanish" };
            return k.text ? DELETE : null;
          }
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

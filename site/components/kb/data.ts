/** What the demo keyboard knows. Sample content only — the apps pull live
 *  results; this page shows how the keys behave. Everything here is pure. */

export type Spotlight = "all" | "you" | "ai" | "search" | "calc" | "typing";

/* ── Solana: spot an address, pay it privately, swap ────── */

const SOL_ADDR = /(?:^|\s)([1-9A-HJ-NP-Za-km-z]{32,44})(?=\s|$)/;

/** The first Solana-looking address in the text, if any. */
export function solAddress(text: string): string | null {
  return text.match(SOL_ADDR)?.[1] ?? null;
}

export const shortAddr = (a: string) => `${a.slice(0, 4)}…${a.slice(-4)}`;

export type PayHint = { amount: string; token: "USDC" | "SOL"; name?: string };

export const WALLET_BALANCE = { USDC: "1,240.18", SOL: "8.42" };
export const SWAP_RATE = 142.27; // illustrative SOL→USDC quote

export type Panel =
  | null
  | "menu"
  | "search"
  | "vault"
  | "clip"
  | "emoji"
  | "tones"
  | "act"
  | "skills"
  | "translate"
  | "chips"
  | "wallet";

export type SearchTab = "google" | "youtube" | "maps";
export type Lang = "hi" | "es" | "fr";

export type Card = {
  kind: "answer" | "link" | "video" | "place";
  title: string;
  meta: string;
  insert: string;
  hue?: number;
  badge?: string;
  /** Answer cards: an illustration, a supporting line and a row of facts. */
  visual?: "sunset" | "sunrise" | "weather" | "clock";
  sub?: string;
  facts?: [string, string][];
  hm?: [number, number];
};

export type ActResult =
  | { kind: "cards"; label: string; cards: Card[] }
  | { kind: "list"; title: string; items: string[] }
  | { kind: "rewrite"; options: { id: string; label: string; text: string }[] }
  | { kind: "refuse" };

export const ROWS_ABC = [
  ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
  ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
  ["z", "x", "c", "v", "b", "n", "m"],
];

export const ROWS_123 = [
  ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
  ["-", "/", "+", "×", "(", ")", "₹", "@", ";", "="],
  [".", ",", "?", "!", "'", "%", "&"],
];

/** Centre of every key in key-widths, for the ignition ripple. */
export function keyPositions(mode: "abc" | "123") {
  const rows = mode === "abc" ? ROWS_ABC : ROWS_123;
  const p: Record<string, [number, number]> = {};
  rows[0].forEach((k, i) => (p[`0-${k}`] = [i + 0.5, 0]));
  rows[1].forEach((k, i) => (p[`1-${k}`] = [i + (mode === "abc" ? 1 : 0.5), 1]));
  p["2-shift"] = [0.75, 2];
  rows[2].forEach((k, i) => (p[`2-${k}`] = [i + 2, 2]));
  p["2-backspace"] = [9.25, 2];
  p["3-mode"] = [0.75, 3];
  p["3-emoji"] = [2, 3];
  p["3-space"] = [5, 3];
  p["3-."] = [8, 3];
  p["3-return"] = [9.25, 3];
  return p;
}

export const POS = { abc: keyPositions("abc"), "123": keyPositions("123") };

export function rowOf(k: string): number {
  if (k === "space" || k === "mode" || k === "emoji" || k === "return") return 3;
  if (k === "shift" || k === "backspace") return 2;
  const i = ROWS_ABC.findIndex((r) => r.includes(k));
  return i < 0 ? 0 : i;
}

/** Letters with a skill bound — hold them. */
export const SKILLS: Record<string, { name: string; hint: string }> = {
  p: { name: "Proofread", hint: "Fixes grammar, keeps your voice" },
  t: { name: "Translate", hint: "Live, as you type" },
  r: { name: "Rewrite", hint: "Pick a tone" },
  s: { name: "Vault", hint: "Everything about you" },
  w: { name: "Weather", hint: "Live conditions" },
};

export const HOLD_MS = 420;
export const SPACE_HOLD_MS = 500;

export const DRAFT = "hey im 5 mins late dont order without me";

/** Canned rewrites for the drafts the page seeds; anything else gets rules. */
const CANNED_SRC: [string, Record<string, string>][] = [
  [
    "hey im 5 mins late dont order without me",
    {
      polite: "Hey! Running about five minutes late — please go ahead and order for me.",
      shorter: "5 min late — order for me.",
      work: "Apologies, I'm running five minutes late. Please go ahead and order without me.",
      hinglish: "Yaar 5 min late hoon, mere liye order kar dena.",
      emoji: "Running 5 late 🏃💨 order for me 🙏",
    },
  ],
  [
    "ya ill send it by 6 dont worry",
    {
      polite: "Sure thing! I'll send it over by 6 — thanks for the reminder.",
      shorter: "Will send by 6.",
      work: "Absolutely — I'll share the Q3 deck with the client by 6 PM today.",
      hinglish: "Haan, 6 baje tak bhej dunga, tension mat lo.",
      emoji: "On it! Sending by 6 📊✅",
    },
  ],
];

export const TONES = [
  { id: "polite", label: "Polite" },
  { id: "shorter", label: "Shorter" },
  { id: "work", label: "Professional" },
  { id: "hinglish", label: "Hinglish" },
  { id: "emoji", label: "Emoji" },
];

export const VAULT = [
  { id: "name", label: "Name", value: "Arpit Singh" },
  { id: "home", label: "Home", value: "123, A-block, Delhi 110001" },
  { id: "upi", label: "UPI", value: "arpit@okbank" },
  { id: "wallet", label: "Solana", value: "4j8FqYuNix7RfFgKmiRZnCE1acNnTarqm1SbZYdQZmFA" },
  { id: "insta", label: "Instagram", value: "instagram.com/Arpitx35" },
  { id: "x", label: "X", value: "x.com/Arpitx35" },
  { id: "linkedin", label: "LinkedIn", value: "linkedin.com/in/Arpitx35" },
  { id: "email", label: "Email", value: "arpit@tryglyf.com" },
  { id: "phone", label: "Phone", value: "+91 98765 43210" },
];

export type VaultItem = (typeof VAULT)[number];

export const short = (v: VaultItem) => (v.id === "wallet" ? `${v.value.slice(0, 4)}…${v.value.slice(-4)}` : v.value);

export const SHORTHAND: Record<string, string> = {
  home: VAULT[1].value,
  upi: VAULT[2].value,
  mail: VAULT[7].value,
  sig: "Cheers, Arpit",
};

/** "my upi is " → your UPI ID, ready on the strip. */
const CONTEXT: [RegExp, string][] = [
  [/\b(my name is|name:|this is)\s*$/i, "name"],
  [/\b(address|deliver(?: it)? to|send (?:it |the \w+ )?to|ship (?:it )?to|come to|pick me up (?:from|at))\s*(?:is\s*)?:?\s*$/i, "home"],
  [/\b(upi|gpay|google pay|phonepe|paytm)(?:\s*id)?\s*(?:is\s*)?:?\s*$/i, "upi"],
  [/\bpay me (?:at|on)\s*$/i, "upi"],
  [/\b(wallet|sol|solana|phantom|usdc|crypto)(?:\s*(?:address|addy|wallet))?\s*(?:is\s*)?:?\s*$/i, "wallet"],
  [/\b(insta|instagram|ig)(?:\s*(?:handle|id))?\s*(?:is\s*)?:?\s*$/i, "insta"],
  [/\b(twitter|on x|x handle)\s*(?:is\s*)?:?\s*$/i, "x"],
  [/\blinkedin\s*(?:is\s*)?:?\s*$/i, "linkedin"],
  [/\b(e-?mail|mail)(?:\s*id)?\s*(?:is\s*)?:?\s*$/i, "email"],
  [/\b(number|phone|mobile|whatsapp|call me (?:at|on))\s*(?:is\s*)?:?\s*$/i, "phone"],
];

export function contextual(text: string): VaultItem | null {
  if (!/[\s:]$/.test(text)) return null;
  for (const [re, id] of CONTEXT) if (re.test(text)) return VAULT.find((v) => v.id === id) ?? null;
  return null;
}

/* ── Math, mid-sentence ─────────────────────────────────── */

const NUM = String.raw`(?:[₹$€£]\s?)?\d[\d,]*(?:\.\d+)?%?`;
const CALC_RE = new RegExp(String.raw`(\(?\s*${NUM}\s*\)?(?:\s*(?:[-+*/×÷^]|\bx\b|\bof\b)\s*\(?\s*${NUM}\s*\)?)+)(\s*=)?\s*$`, "i");

function evaluate(expr: string): number | null {
  const src = expr
    .toLowerCase()
    .replace(/\bof\b/g, "*")
    .replace(/\bx\b/g, "*")
    .replace(/×/g, "*")
    .replace(/÷/g, "/")
    .replace(/[₹$€£,\s]/g, "");
  const t = src.match(/\d+(?:\.\d+)?%?|[-+*/^()]/g) ?? [];
  if (t.join("") !== src) return null;
  let i = 0;
  const peek = () => t[i];
  const unary = (): number => {
    if (peek() === "-") return i++, -unary();
    if (peek() === "(") {
      i++;
      const v = sum();
      if (t[i++] !== ")") throw 0;
      return v;
    }
    const tok = t[i++];
    if (!tok || !/^\d/.test(tok)) throw 0;
    return tok.endsWith("%") ? parseFloat(tok) / 100 : parseFloat(tok);
  };
  const power = (): number => {
    const v = unary();
    return peek() === "^" ? (i++, Math.pow(v, power())) : v;
  };
  const product = (): number => {
    let v = power();
    while (peek() === "*" || peek() === "/") v = t[i++] === "*" ? v * power() : v / power();
    return v;
  };
  const sum = (): number => {
    let v = product();
    while (peek() === "+" || peek() === "-") v = t[i++] === "+" ? v + product() : v - product();
    return v;
  };
  try {
    const v = sum();
    return i === t.length && Number.isFinite(v) ? v : null;
  } catch {
    return null;
  }
}

export type Calc = { value: string; start: number; eq: boolean };

export function calc(text: string): Calc | null {
  const m = text.match(CALC_RE);
  if (!m || m.index === undefined) return null;
  const eq = !!m[2];
  if (!eq && !/[+*/×÷^%]|\bx\b|\bof\b/i.test(m[1])) return null;
  const v = evaluate(m[1]);
  if (v === null) return null;
  const cur = m[1].match(/[₹$€£]/)?.[0] ?? "";
  const value = cur + new Intl.NumberFormat("en-IN", { maximumFractionDigits: 2 }).format(v);
  return { value, start: m.index + (m[0].length - m[0].trimStart().length), eq };
}

export const WEATHER = "It's 24° and cloudy in Bengaluru — rain after 6 PM ☔";

/** Clipboard history. Links open in a new tab instead of pasting. */
export const CLIPS = ["https://youtu.be/dQw4w9WgXcQ?si=ms6HzsvNvsPeLhH_", "meet.google.com/xk2-pqr-7ty", "Flight PNR · QR7GH2", "the figma link from standup"];
export const CLIP_AGE = ["Just now", "2 min", "1 hr", "Yesterday"];
export const isLink = (text: string) => /^https?:\/\//.test(text);

export const EMOJI = ["😂", "❤️", "🔥", "🙏", "🎉", "😭", "💀", "✨", "🥹", "👀", "💯", "🤝", "😎", "🫶", "🙌", "☕", "🍕", "🏃", "😴", "🤔", "👍", "🥳", "😅", "🌧️"];

/* ── Autocorrect: confident fixes only; names and slang are left alone ── */

const FIXES: Record<string, string> = {
  teh: "the", hte: "the", adn: "and", recieve: "receive", dont: "don't", im: "I'm", i: "I",
  cant: "can't", wont: "won't", didnt: "didn't", doesnt: "doesn't", isnt: "isn't", ive: "I've",
  thnaks: "thanks", becuase: "because", definately: "definitely", waht: "what", taht: "that",
  tommorow: "tomorrow", tomorow: "tomorrow", seperate: "separate", untill: "until", wierd: "weird",
  // Hinglish typos — the pack knows the words, so it fixes them and leaves yaar alone.
  pakak: "pakka", yaaar: "yaar", thik: "theek", kese: "kaise", bhot: "bahut", hna: "haan",
};

export function autocorrect(word: string, learned: Set<string>): string | null {
  const lower = word.toLowerCase();
  if (learned.has(lower)) return null;
  const fix = FIXES[lower];
  if (!fix || fix === word) return null;
  if (word[0] !== lower[0] && fix[0] === fix[0].toLowerCase()) return fix[0].toUpperCase() + fix.slice(1);
  return fix;
}

const WORDS = [
  "the", "thanks", "thank", "that", "there", "this", "today", "tomorrow", "tonight", "time", "late", "later",
  "order", "on", "our", "okay", "running", "right", "reply", "really", "see", "send", "soon", "sure", "sorry",
  "minutes", "meeting", "message", "maybe", "coffee", "coming", "call", "can", "without", "with", "what",
  "where", "when", "why", "will", "hey", "hello", "have", "help", "home", "how", "near", "now", "need",
  "yaar", "you", "your", "yes", "good", "great", "going", "get", "address", "about", "again", "already",
  "birthday", "bring", "before", "done", "dinner", "lunch", "leaving", "love", "let's", "please", "plan",
  "place", "just", "know", "free", "from", "for", "friday", "weekend", "work", "wait", "want", "definitely",
  "pakka", "haan", "bhai", "kal", "aaj", "chal", "raha", "hoon", "accha", "theek", "nahi", "kaise", "kya", "bahut", "abhi",
];

export function suggest(word: string, learned: Set<string>): string[] {
  const w = word.toLowerCase();
  if (!w) return [];
  const out: string[] = [];
  const fix = autocorrect(word, learned);
  if (fix) out.push(fix);
  for (const x of WORDS) {
    if (out.length >= 2) break;
    if (x.startsWith(w) && x !== w && !out.includes(x)) out.push(x);
  }
  return out;
}

/* ── AI ─────────────────────────────────────────────────── */

const norm = (s: string) =>
  s.toLowerCase().replace(/minutes/g, "mins").replace(/[^a-z0-9\s]/g, "").replace(/\s+/g, " ").trim();

/** A canned family matches its draft or any of its own rewrites. */
function cannedFor(s: string): Record<string, string> | null {
  const n = norm(s);
  for (const [draft, tones] of CANNED_SRC) if (norm(draft) === n || Object.values(tones).some((t) => norm(t) === n)) return tones;
  return null;
}

export function proofread(s: string): string {
  let t = ` ${s} `
    .replace(/\s+/g, " ")
    .replace(/ (teh|hte) /gi, " the ")
    .replace(/ im /gi, " I'm ")
    .replace(/ i /g, " I ")
    .replace(/ (dont|cant|wont|didnt|isnt)/gi, (m) => m.slice(0, -1) + "'" + m.slice(-1))
    .replace(/ u /gi, " you ")
    .replace(/ r /gi, " are ")
    .replace(/ ur /gi, " your ")
    .replace(/ pls /gi, " please ")
    .replace(/ thx /gi, " thanks ")
    .replace(/ mins /gi, " minutes ")
    .replace(/ gonna /gi, " going to ")
    .replace(/ wanna /gi, " want to ")
    .trim();
  if (!t) return "";
  t = t.replace(/(^|[.!?]\s+)([a-z])/g, (_, a, b) => a + b.toUpperCase());
  return /[.!?…]$/.test(t) ? t : t + ".";
}

const IMPERATIVE = /^(send|call|share|bring|tell|let|come|check|order|book|pick|text|meet|remind|help|wait|give|get|buy|grab|save|keep)\b/i;

export function rewrite(text: string, tone: string): string {
  const canned = cannedFor(text);
  if (canned) return canned[tone] ?? text;
  const base = proofread(text);
  const bare = base.replace(/[.!?]+$/, "");
  if (!bare) return text;
  const lower = bare[0].toLowerCase() + bare.slice(1);
  switch (tone) {
    case "polite":
      return IMPERATIVE.test(bare) ? `Hey! Could you ${lower}, please? Thank you!` : `Hey! ${bare} — hope that's okay!`;
    case "shorter": {
      const shorter = bare
        .replace(/\b(just|really|very|actually|basically|literally|totally|honestly|kind of|sort of|i think|please)\b\s*/gi, "")
        .replace(/\s+/g, " ")
        .trim();
      return (shorter || bare) + ".";
    }
    case "work": {
      const clean = bare.replace(/\b(yaar|lol|bro|dude)\b,?\s*/gi, "").replace(/\s+/g, " ").trim();
      return /^(hi|hello|dear)\b/i.test(clean) ? `${clean}.` : `Hi, ${clean[0].toLowerCase() + clean.slice(1)}.`;
    }
    case "hinglish":
      return `${bare}, yaar.`;
    case "emoji": {
      const t = text.toLowerCase();
      const e = /late|run/.test(t) ? "🏃" : /food|order|dinner|lunch|pizza/.test(t) ? "🍕" : /coffee/.test(t) ? "☕" : /thank/.test(t) ? "🙏" : /love|miss/.test(t) ? "❤️" : /party|birthday/.test(t) ? "🎉" : "✨";
      return `${bare} ${e}`;
    }
  }
  return base;
}

type Phrase = { en: string } & Record<Lang, string>;

const PHRASES: Phrase[] = [
  { en: "see you tomorrow", hi: "कल मिलते हैं", es: "hasta mañana", fr: "à demain" },
  { en: "see you soon", hi: "जल्द मिलते हैं", es: "hasta pronto", fr: "à bientôt" },
  { en: "see you", hi: "फिर मिलते हैं", es: "nos vemos", fr: "à plus" },
  { en: "on my way", hi: "रास्ते में हूँ", es: "voy en camino", fr: "je suis en route" },
  { en: "running late", hi: "मुझे देर हो रही है", es: "voy tarde", fr: "je suis en retard" },
  { en: "thank you so much", hi: "बहुत-बहुत धन्यवाद", es: "muchas gracias", fr: "merci beaucoup" },
  { en: "thank you", hi: "धन्यवाद", es: "gracias", fr: "merci" },
  { en: "good morning", hi: "सुप्रभात", es: "buenos días", fr: "bonjour" },
  { en: "good night", hi: "शुभ रात्रि", es: "buenas noches", fr: "bonne nuit" },
  { en: "happy birthday", hi: "जन्मदिन मुबारक हो", es: "feliz cumpleaños", fr: "joyeux anniversaire" },
  { en: "where are you", hi: "तुम कहाँ हो?", es: "¿dónde estás?", fr: "où es-tu ?" },
  { en: "how are you", hi: "आप कैसे हैं?", es: "¿cómo estás?", fr: "comment ça va ?" },
  { en: "call me", hi: "मुझे कॉल करो", es: "llámame", fr: "appelle-moi" },
  { en: "hello", hi: "नमस्ते", es: "hola", fr: "bonjour" },
  { en: "yes", hi: "हाँ", es: "sí", fr: "oui" },
  { en: "see", hi: "देखो", es: "mira", fr: "regarde" },
];

export const LANGS: { id: Lang; label: string }[] = [
  { id: "hi", label: "Hindi" },
  { id: "es", label: "Spanish" },
  { id: "fr", label: "French" },
];

export function translate(text: string, lang: Lang): string | null {
  const t = norm(text);
  if (!t) return null;
  const exact = PHRASES.find((p) => p.en === t);
  if (exact) return exact[lang];
  const prefix = PHRASES.filter((p) => t.startsWith(p.en)).sort((a, b) => b.en.length - a.en.length)[0];
  return prefix ? `${prefix[lang]} …` : null;
}

/* ── Search ─────────────────────────────────────────────── */

const cap = (s: string) => s.charAt(0).toUpperCase() + s.slice(1);
const hash = (s: string) => [...s].reduce((h, c) => (h * 31 + c.charCodeAt(0)) >>> 0, 7);

function placesFor(q: string): Card[] {
  const t = q.toLowerCase();
  const pick = (name: string, meta: string): Card => ({ kind: "place", title: name, meta, insert: `📍 ${name} · ${meta.split(" · ")[1]}`, hue: hash(name) % 360 });
  if (/pizza/.test(t)) return [pick("Little Oven Pizzeria", "4.5 ★ · 900 m · Open"), pick("Slice Theory", "4.3 ★ · 1.4 km · Open")];
  if (/biryani/.test(t)) return [pick("Monsoon Biryani House", "4.4 ★ · 1.2 km · Open"), pick("Dum & Co.", "4.2 ★ · 2 km · Open")];
  if (/dinner|lunch|restaurant|brunch|breakfast/.test(t)) return [pick("The Green Terrace", "4.5 ★ · 700 m · Open"), pick("Banana Leaf Kitchen", "4.4 ★ · 1.1 km · Open")];
  if (/bar|pub|beer|drinks/.test(t)) return [pick("Hops & Barley", "4.3 ★ · 1.1 km · Open"), pick("The Rooftop Room", "4.1 ★ · 1.8 km · Open")];
  if (/coffee|caf/.test(t)) return [pick("Bean & Byte Café", "4.6 ★ · 350 m · Open"), pick("Filter Kaapi Co.", "4.5 ★ · 600 m · Open")];
  const what = cap(q.replace(/\b(near me|nearby|around here|where|find|a|the)\b/gi, "").trim() || "Places");
  return [pick(`${what} spot`, "4.4 ★ · 800 m · Open"), pick(`${what} & Co.`, "4.2 ★ · 1.3 km · Open")];
}

function videosFor(q: string): Card[] {
  const t = q.toLowerCase();
  if (/road trip|drive|songs/.test(t))
    return [
      { kind: "video", title: "Road trip hits — non-stop highway mix", meta: "Open Roads · 4.2M views", insert: "▶ Road trip hits — non-stop highway mix", hue: 16, badge: "1:02:10" },
      { kind: "video", title: "Indie drive playlist 2026", meta: "Night Shift · 910K views", insert: "▶ Indie drive playlist 2026", hue: 200, badge: "48:22" },
    ];
  if (/lofi|study|focus/.test(t))
    return [
      { kind: "video", title: "Lofi beats to study to — 3 hour mix", meta: "Quiet Hours · 2.1M views", insert: "▶ Lofi beats to study to — 3 hour mix", hue: 265, badge: "3:02:14" },
      { kind: "video", title: "Rainy café jazz for deep focus", meta: "Slow Mornings · 880K views", insert: "▶ Rainy café jazz for deep focus", hue: 28, badge: "1:12:40" },
    ];
  const topic = cap(q.replace(/\b(video|videos|watch|on youtube|youtube)\b/gi, "").trim() || q);
  return [
    { kind: "video", title: topic, meta: "Top result · YouTube", insert: `▶ ${topic}`, hue: hash(topic) % 360, badge: "12:08" },
    { kind: "video", title: `${topic}, explained`, meta: "YouTube", insert: `▶ ${topic}, explained`, hue: (hash(topic) + 140) % 360, badge: "8:31" },
  ];
}

const ZONES: Record<string, string> = {
  london: "Europe/London", "new york": "America/New_York", nyc: "America/New_York", tokyo: "Asia/Tokyo",
  dubai: "Asia/Dubai", singapore: "Asia/Singapore", sydney: "Australia/Sydney", "san francisco": "America/Los_Angeles",
  delhi: "Asia/Kolkata", mumbai: "Asia/Kolkata", bengaluru: "Asia/Kolkata", paris: "Europe/Paris", berlin: "Europe/Berlin",
};

function answersFor(q: string): Card[] {
  const t = q.toLowerCase();
  if (/sunset/.test(t))
    return [
      {
        kind: "answer", visual: "sunset", title: "6:24 PM", meta: "Sunset · Bengaluru", sub: "Golden hour starts 5:52 PM",
        facts: [["Sunrise", "6:08 AM"], ["Daylight", "12h 16m"], ["Last light", "6:47 PM"]], insert: "Sunset's at 6:24 PM 🌇",
      },
    ];
  if (/sunrise/.test(t))
    return [
      {
        kind: "answer", visual: "sunrise", title: "6:08 AM", meta: "Sunrise · Bengaluru", sub: "First light 5:45 AM",
        facts: [["Sunset", "6:24 PM"], ["Daylight", "12h 16m"]], insert: "Sunrise is at 6:08 AM 🌅",
      },
    ];
  if (/weather|rain|temperature/.test(t))
    return [
      {
        kind: "answer", visual: "weather", title: "24°", meta: "Weather · Bengaluru", sub: "Cloudy · rain likely after 6 PM",
        facts: [["High", "27°"], ["Low", "19°"], ["Rain", "70%"]], insert: WEATHER,
      },
    ];
  const zone = Object.keys(ZONES).find((z) => t.includes(z));
  if (zone && /time/.test(t)) {
    const date = new Date();
    const now = new Intl.DateTimeFormat("en-IN", { hour: "numeric", minute: "2-digit", timeZone: ZONES[zone] }).format(date);
    const parts = new Intl.DateTimeFormat("en-GB", { hour: "numeric", minute: "numeric", hour12: false, timeZone: ZONES[zone] }).formatToParts(date);
    const hm: [number, number] = [Number(parts.find((p) => p.type === "hour")?.value ?? 0), Number(parts.find((p) => p.type === "minute")?.value ?? 0)];
    return [{ kind: "answer", visual: "clock", title: now, meta: `Time · ${cap(zone)}`, sub: "Right now", hm, insert: `It's ${now} in ${cap(zone)} right now` }];
  }
  return [
    { kind: "link", title: cap(q), meta: "google.com · Search", insert: `🔎 google.com/search?q=${encodeURIComponent(q)}` },
    { kind: "link", title: `Images of ${q}`, meta: "google.com · Images", insert: `🔎 google.com/search?tbm=isch&q=${encodeURIComponent(q)}` },
  ];
}

export const SEARCH_SUGGEST: Record<SearchTab, string[]> = {
  google: ["Sunset time today", "Weather today", "Time in London"],
  youtube: ["Road trip songs", "Lofi to study", "Cricket highlights"],
  maps: ["Cafés near me", "Pizza nearby", "Parks near me"],
};

export function searchCards(tab: SearchTab, q: string): Card[] {
  const query = q.trim();
  if (!query) return [];
  if (tab === "youtube") return videosFor(query);
  if (tab === "maps") return placesFor(query);
  return answersFor(query);
}

/* ── Hold glyf: read the text, pick what to do ──────────── */

export function hasSecret(s: string): boolean {
  return /(?:\d[ -]?){13,19}/.test(s) || /\b(password|passcode|pin|otp|cvv)\b\s*(is|:)?\s*\S+/i.test(s);
}

function listItems(s: string): string[] {
  const after = s.includes(":") ? s.slice(s.indexOf(":") + 1) : s.replace(/^.*?\b(list|groceries|grocery|to-?do|shopping|pack(ing)?|buy)\b/i, "");
  return after
    .split(/,|\band\b|\n/i)
    .map((x) => x.trim())
    .filter(Boolean)
    .slice(0, 6)
    .map(cap);
}

export function classify(raw: string): ActResult {
  const text = raw.trim();
  const t = text.toLowerCase();
  if (hasSecret(text)) return { kind: "refuse" };
  if (/(near me|nearby|coffee|caf[eé]|dinner|lunch|breakfast|brunch|restaurant|pizza|biryani|\bpub\b|\bbar\b|drinks)/.test(t))
    return { kind: "cards", label: "Places", cards: placesFor(text) };
  if (/(video|watch|song|music|lofi|playlist|trailer|youtube|tutorial)/.test(t)) return { kind: "cards", label: "Videos", cards: videosFor(text) };
  const items = listItems(text);
  if (/\b(list|groceries|grocery|to-?do|shopping|packing)\b/.test(t) && items.length >= 2)
    return { kind: "list", title: cap((t.match(/\b(groceries|grocery|to-?do|shopping|packing|list)\b/) ?? ["List"])[0]), items };
  if (/\?$/.test(t) || /^(what|when|who|how|where|why|is|are|does|do|can|will|should)\b/.test(t) || /(weather|sunset|sunrise|time in)/.test(t))
    return { kind: "cards", label: "Answer", cards: answersFor(text.replace(/\?+$/, "")) };
  return {
    kind: "rewrite",
    options: TONES.slice(0, 4).map((x) => ({ id: x.id, label: x.label, text: rewrite(text, x.id) })),
  };
}

export const TRY_CHIPS = ["coffee near me", "when is sunset?", "lofi to study", "groceries: milk, eggs and bread"];

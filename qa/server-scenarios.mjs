// Everyday situations run against the live Glyf server, with real models.
// Each one is a thing a person types and what Glyf should do with it.
// Usage: node qa/server-scenarios.mjs [baseURL]
import { readFileSync, writeFileSync } from "node:fs";

const BASE = process.argv[2] ?? "http://127.0.0.1:8787";
// Every route but a few open ones needs a Glyf session since the gate went
// in: GLYF_TOKEN=<session> node qa/server-scenarios.mjs
const AUTH = process.env.GLYF_TOKEN ? { authorization: `Bearer ${process.env.GLYF_TOKEN}` } : {};
const DEVICE = "qa-scenarios";
const IN = { country: "IN", tz: "Asia/Kolkata", lat: 12.9719, lon: 77.6412 };

async function post(path, body) {
  const started = Date.now();
  const res = await fetch(BASE + path, {
    method: "POST",
    headers: { "content-type": "application/json", ...AUTH },
    body: JSON.stringify({ deviceId: DEVICE, ...body }),
  });
  const json = await res.json().catch(() => ({}));
  return { status: res.status, ms: Date.now() - started, json };
}

const act = (text, extra = {}) => post("/act", { text, plan: "max", ...IN, ...extra });
const hasAny = (s, words) => words.some(w => s.toLowerCase().includes(w));

const scenarios = [
  // --- Hold space on a message you are writing: versions to pick from ---
  { id: "S01", area: "Rewrite", title: "Rough reply to a manager: 'ya ok will send deck b4 6'",
    run: () => act("ya ok will send deck b4 6"),
    check: r => r.json.intent === "rewrite" && (r.json.options ?? []).length >= 4
      && r.json.options.some(o => o.label === "Professional")
      // "b4 6" is a time: every version keeps it.
      && r.json.options.every(o => /\b6\b/.test(o.text)),
    show: r => (r.json.options ?? []).map(o => `${o.label}: ${o.text}`).join(" | ") },
  { id: "S02", area: "Rewrite", title: "Apology for being late: 'sry running late traffic is crazy'",
    run: () => act("sry running late traffic is crazy"),
    check: r => r.json.intent === "rewrite" && (r.json.options ?? []).some(o => o.label === "Polite"),
    show: r => (r.json.options ?? []).slice(0, 3).map(o => `${o.label}: ${o.text}`).join(" | ") },
  { id: "S03", area: "Rewrite", title: "Hinglish offered in India: 'kal meeting shift kar do please'",
    run: () => act("kal meeting shift kar do please 4 baje"),
    check: r => (r.json.options ?? []).some(o => o.label === "Hinglish"),
    show: r => (r.json.options ?? []).map(o => o.label).join(", ") },
  { id: "S04", area: "Rewrite", title: "No Hinglish row for someone in the US",
    run: () => act("can u send me the invoice asap", { country: "US", tz: "America/New_York" }),
    check: r => (r.json.options ?? []).length > 0 && !(r.json.options ?? []).some(o => o.label === "Hinglish"),
    show: r => (r.json.options ?? []).map(o => o.label).join(", ") },
  { id: "S05", area: "Rewrite", title: "Shorter version is actually shorter",
    run: () => act("hey just wanted to check if you had a chance to look at the proposal i sent over last week because we need to decide by friday"),
    check: r => { const o = r.json.options ?? []; const s = o.find(x => x.id === "shorter"), b = o.find(x => x.id === "basic");
      return !!s && !!b && s.text.length < b.text.length; },
    show: r => (r.json.options ?? []).filter(o => ["basic", "shorter"].includes(o.id)).map(o => `${o.label}(${o.text.length}): ${o.text}`).join(" | ") },
  { id: "S06", area: "Rewrite", title: "A rewrite never pastes a Google link",
    run: () => act("tidy this up pls its for the client"),
    check: r => !/google\.com\/search/.test(JSON.stringify(r.json)),
    show: r => r.json.intent + ": " + (r.json.insert ?? "").slice(0, 80) },
  { id: "S07", area: "Rewrite", title: "Chip intent forced to rewrite keeps the whole sentence",
    run: () => act("who is coming tonight lmk", { intent: "rewrite" }),
    check: r => r.json.intent === "rewrite" && (r.json.options ?? []).length >= 4,
    show: r => (r.json.options ?? []).slice(0, 2).map(o => `${o.label}: ${o.text}`).join(" | ") },
  { id: "S08", area: "Vault in AI", title: "Friend asks for your address; your saved address fills in",
    run: () => act("sure my address is", { intent: "rewrite", profile: { address: "42 Glass Lane, Indiranagar, Bengaluru 560038", name: "Arpit" } }),
    check: r => (r.json.options ?? []).some(o => o.text.includes("Glass Lane")),
    show: r => (r.json.options ?? [])[0]?.text ?? "" },
  { id: "S09", area: "Vault in AI", title: "Details are never volunteered where nobody asked",
    run: () => act("see you at the game tonight", { intent: "rewrite", profile: { address: "42 Glass Lane, Indiranagar", phone: "+91 98765 43210" } }),
    check: r => !(r.json.options ?? []).some(o => o.text.includes("Glass Lane") || o.text.includes("98765")),
    show: r => (r.json.options ?? [])[0]?.text ?? "" },

  // --- Hold space on a question or a place: Glyf finds it ---
  { id: "S10", area: "Places", title: "'best biryani near indiranagar' gives a list of places",
    run: () => act("best biryani near indiranagar"),
    check: r => r.json.intent === "places" && (r.json.cards ?? []).filter(c => c.kind === "place").length >= 2
      && (r.json.cards ?? []).some(c => /biryani/i.test(c.title)),
    show: r => (r.json.cards ?? []).slice(0, 3).map(c => `${c.title} (${c.distance ?? "?"})`).join(" · ") || (r.json.text ?? "") },
  { id: "S11", area: "Places", title: "'nearest atm' gives the one place",
    run: () => act("nearest atm"),
    check: r => r.json.intent === "place" && (r.json.cards ?? [])[0]?.kind === "place"
      && /atm/i.test((r.json.cards ?? [])[0]?.title ?? ""),
    show: r => r.json.intent + ": " + ((r.json.cards ?? [])[0]?.title ?? r.json.text ?? "") + " " + ((r.json.cards ?? [])[0]?.distance ?? "") },
  { id: "S12", area: "Places", title: "'cafes near me' uses the phone's rough location",
    run: () => act("cafes near me"),
    check: r => r.json.intent === "places" && (r.json.cards ?? []).filter(c => c.kind === "place").length >= 2,
    show: r => (r.json.cards ?? []).slice(0, 3).map(c => c.title).join(" · ") || (r.json.text ?? "") },
  { id: "S13", area: "Video", title: "'send me the dune part 2 trailer' finds the video",
    run: () => act("send me the dune part 2 trailer"),
    check: r => r.json.intent === "video" && (r.json.cards ?? [])[0]?.kind === "video" && /dune/i.test(r.json.cards[0].title),
    show: r => ((r.json.cards ?? [])[0]?.title ?? r.json.text ?? "") },
  { id: "S14", area: "Answers", title: "'weather in bangalore tomorrow' is a live answer, not a guess",
    run: () => act("weather in bangalore tomorrow"),
    check: r => (r.json.cards ?? []).some(c => c.kind === "answer") ? true
      : (r.json.insert ?? "") === "" ? "blocked: live weather needs a web search or weather key" : false,
    show: r => `${r.json.intent}: ${r.json.text ?? (r.json.cards ?? [])[0]?.title ?? ""} | insert="${(r.json.insert ?? "").slice(0, 50)}"` },
  { id: "S15", area: "Answers", title: "Nothing found inserts nothing (no link pasted)",
    run: () => act("zxqv plorb wibble score today"),
    check: r => r.json.ok !== true || (r.json.insert ?? "") === "" || !/google\.com\/search/.test(r.json.insert ?? ""),
    show: r => `${r.json.intent}: insert="${(r.json.insert ?? "").slice(0, 40)}" text=${r.json.text ?? ""}` },
  { id: "S16", area: "Answers", title: "Maths in a question: '18% of 2450' answers 441",
    run: () => act("18% of 2450"),
    check: r => JSON.stringify(r.json).includes("441"),
    show: r => (r.json.text ?? (r.json.cards ?? [])[0]?.value ?? r.json.insert ?? "") },

  // --- Translate, Google style ---
  { id: "S21", area: "Translate", title: "Hinglish 'kal milte hain office ke baad' comes out in English",
    run: () => post("/translate", { text: "kal milte hain office ke baad", primary: "English", secondary: "Hindi" }),
    check: r => r.json.detected === "Hindi" && r.json.target === "English",
    show: r => `${r.json.detected} → ${r.json.target}: ${r.json.translation}` },
  { id: "S22", area: "Translate", title: "English goes to your other language (Hindi)",
    run: () => post("/translate", { text: "see you after office tomorrow", primary: "English", secondary: "Hindi" }),
    check: r => r.json.target === "Hindi" && /[ऀ-ॿ]/.test(r.json.translation ?? ""),
    show: r => `${r.json.detected} → ${r.json.target}: ${r.json.translation}` },
  { id: "S23", area: "Translate", title: "Devanagari detected without asking the model",
    run: () => post("/translate", { text: "मुझे कल छुट्टी चाहिए", primary: "English", secondary: "Hindi" }),
    check: r => r.json.detected === "Hindi" && r.json.target === "English",
    show: r => `${r.json.detected} → ${r.json.target}: ${r.json.translation}` },
  { id: "S24", area: "Translate", title: "Tamil message comes back in English",
    run: () => post("/translate", { text: "நாளை சந்திப்போம்", primary: "English", secondary: "Hindi" }),
    check: r => r.json.detected === "Tamil" && r.json.target === "English",
    show: r => `${r.json.detected} → ${r.json.target}: ${r.json.translation}` },
  { id: "S25", area: "Translate", title: "Tapping the direction to Spanish sends it to Spanish",
    run: () => post("/translate", { text: "happy birthday, have a great year", primary: "English", secondary: "Hindi", target: "Spanish" }),
    check: r => r.json.target === "Spanish" && hasAny(r.json.translation ?? "", ["feliz", "cumpleaños", "año"]),
    show: r => `${r.json.detected} → ${r.json.target}: ${r.json.translation}` },
  { id: "S26", area: "Translate", title: "A Spanish-speaking phone: Spanish text goes to English second language",
    run: () => post("/translate", { text: "nos vemos mañana en la oficina", primary: "Spanish", secondary: "English" }),
    check: r => r.json.detected === "Spanish" && r.json.target === "English",
    show: r => `${r.json.detected} → ${r.json.target}: ${r.json.translation}` },

  // --- Search from the keyboard ---
  { id: "S27", area: "Search", title: "Web search for 'ipl points table'",
    run: () => post("/search", { vertical: "web", query: "ipl points table", ...IN }),
    check: r => r.status !== 200 ? false : (r.json.cards ?? []).some(c => c.id !== "tail")
      ? true : "blocked: web results need BRAVE_SEARCH_KEY",
    show: r => (r.json.cards ?? []).slice(0, 2).map(c => c.title).join(" · ") },
  { id: "S28", area: "Search", title: "YouTube search for 'arijit singh live'",
    run: () => post("/search", { vertical: "yt", query: "arijit singh live", ...IN }),
    check: r => r.status === 200 && (r.json.cards ?? []).filter(c => c.kind === "video").length >= 2,
    show: r => (r.json.cards ?? []).slice(0, 2).map(c => c.title).join(" · ") },
  { id: "S29", area: "Search", title: "Maps search for 'third wave coffee'",
    run: () => post("/search", { vertical: "maps", query: "third wave coffee", ...IN }),
    check: r => r.status === 200 && (r.json.cards ?? []).some(c => c.kind === "place" && /third wave/i.test(c.title)),
    show: r => (r.json.cards ?? []).slice(0, 2).map(c => `${c.title} (${c.address ?? ""})`).join(" · ") },

  // --- Build your own glyf ---
  { id: "S30", area: "Builder", title: "Tap 'Say no, politely' and a glyf is made",
    run: () => post("/builder/generate", { description: "Say no, politely" }),
    check: r => r.status === 200 && typeof r.json.def?.name === "string" && (r.json.def?.steps ?? []).length > 0,
    show: r => `${r.json.def?.name}: ${(r.json.def?.steps ?? []).length} step(s)` },
  { id: "S31", area: "Builder", title: "Tap 'Turn it into a LinkedIn post' and it is made",
    run: () => post("/builder/generate", { description: "Turn it into a LinkedIn post" }),
    check: r => r.status === 200 && typeof r.json.def?.name === "string",
    show: r => r.json.def?.name ?? JSON.stringify(r.json).slice(0, 80) },
  { id: "S32", area: "Builder", title: "The preview runs the new glyf on a sample message",
    run: async () => {
      const g = await post("/builder/generate", { description: "Reply in Hinglish" });
      return post("/builder/test", { def: g.json.def, input: "hey can u send the report tmrw morning thx" });
    },
    check: r => r.status === 200 && (r.json.text ?? "").length > 10,
    show: r => (r.json.text ?? "").slice(0, 120) },
  { id: "S33", area: "Builder", title: "A description too short to build is refused cleanly",
    run: () => post("/builder/generate", { description: "a" }),
    check: r => r.status >= 400 && r.status < 500,
    show: r => `${r.status} ${JSON.stringify(r.json).slice(0, 80)}` },

  // --- Private payments ---
  { id: "S34", area: "Pay", title: "Wallet config is there for the app's Privy login",
    run: async () => { const res = await fetch(BASE + "/wallet/config", { headers: AUTH }); return { status: res.status, json: await res.json() }; },
    check: r => r.status === 200 && r.json.ready === true && r.json.privyAppId.length > 5,
    show: r => `ready: ${r.json.ready}, cluster: ${r.json.cluster}` },

  // --- Safety ---
  { id: "S35", area: "Safety", title: "A card number is hidden from the model and comes back exactly in every version",
    run: () => act("my card is 4111 1111 1111 1111 exp 12/29 cvv 123 pls pay the bill", { intent: "rewrite" }),
    check: r => (r.json.options ?? []).length >= 4 && r.json.options.every(o => o.text.includes("4111 1111 1111 1111"))
      && !JSON.stringify(r.json).includes("[[S"),
    show: r => (r.json.options ?? []).slice(0, 2).map(o => `${o.label}: ${o.text}`).join(" | ") },
  { id: "S36", area: "Safety", title: "Bad requests get a 400, not a crash",
    run: () => post("/act", { text: "" }),
    check: r => r.status === 400,
    show: r => `${r.status}` },
  // --- More everyday ones ---
  { id: "S37", area: "Safety", title: "An OTP in a message survives every rewrite untouched",
    run: () => act("otp is 482913 dont share it with anyone ok", { intent: "rewrite" }),
    check: r => (r.json.options ?? []).length >= 4 && r.json.options.every(o => o.text.includes("482913")),
    show: r => (r.json.options ?? []).slice(0, 2).map(o => `${o.label}: ${o.text}`).join(" | ") },
  { id: "S38", area: "Safety", title: "Translating a message keeps the account number exactly",
    run: () => post("/translate", { text: "mera account number 4111111111111111 hai, paise bhej do", primary: "English", secondary: "Hindi" }),
    check: r => (r.json.translation ?? "").includes("4111111111111111") && !(r.json.translation ?? "").includes("[[S"),
    show: r => `${r.json.detected} → ${r.json.target}: ${r.json.translation}` },
  { id: "S39", area: "Answers", title: "'100 usd to inr' converts at today's rate",
    run: () => act("100 usd to inr"),
    check: r => (r.json.cards ?? []).some(c => c.kind === "answer" && /INR/.test(c.value ?? "")) && /INR/.test(r.json.insert ?? ""),
    show: r => r.json.insert ?? "" },
  { id: "S40", area: "Answers", title: "'what is a black hole' answers from Wikipedia",
    run: () => act("what is a black hole"),
    check: r => (r.json.cards ?? []).some(c => c.kind === "answer") && /black hole/i.test(r.json.insert ?? ""),
    show: r => (r.json.insert ?? "").slice(0, 120) },
  { id: "S41", area: "Answers", title: "'sunset' gives today's sunset where you are",
    run: () => act("sunset"),
    check: r => (r.json.cards ?? []).some(c => c.kind === "answer") && /\d{1,2}:\d{2}/.test(r.json.insert ?? ""),
    show: r => r.json.insert ?? "" },
  { id: "S42", area: "Video", title: "'lofi beats playlist' finds a video to send",
    run: () => act("lofi beats playlist"),
    check: r => r.json.intent === "video" && /youtu/.test(r.json.insert ?? ""),
    show: r => (r.json.insert ?? "").replace(/\n/g, " / ") },
  { id: "S43", area: "Places", title: "'hotels in goa' lists hotels in Goa",
    run: () => act("good hotels in goa"),
    check: r => r.json.intent === "places" && (r.json.cards ?? []).filter(c => c.kind === "place").length >= 2,
    show: r => (r.json.cards ?? []).slice(0, 3).map(c => `${c.title} (${c.address ?? ""})`).join(" · ") },
  { id: "S44", area: "Rewrite", title: "Emoji-heavy banter keeps its meaning",
    run: () => act("omg 😂😂 that was sooo funny cant breathe", { intent: "rewrite" }),
    check: r => (r.json.options ?? []).some(o => o.id === "emoji" && /\p{Extended_Pictographic}/u.test(o.text))
      && (r.json.options ?? []).some(o => /funny|hilarious|laugh/i.test(o.text)),
    show: r => (r.json.options ?? []).slice(0, 3).map(o => `${o.label}: ${o.text}`).join(" | ") },
  { id: "S45", area: "Speed", title: "A normal rewrite comes back in under 6 seconds",
    run: () => act("hey r u free for a call at 5 today", { intent: "rewrite" }),
    check: r => r.ms < 6000 && (r.json.options ?? []).length >= 4,
    show: r => `${r.ms} ms` },
  { id: "S46", area: "Rewrite", title: "A long rambling message still gets every version",
    run: () => act("so basically what happened was i reached the venue at like 7 and nobody was there and then i called rahul and he said the event got moved to the other hall which nobody told us about and by the time we found it the first session was already over so can we please get the recording or at least the slides because we did pay for the full day"),
    check: r => (r.json.options ?? []).length >= 4 && r.json.options.find(o => o.id === "shorter")?.text.length < 200,
    show: r => (r.json.options ?? []).filter(o => o.id === "shorter" || o.id === "professional").map(o => `${o.label}: ${o.text}`).join(" | ") },
  { id: "S48", area: "Builder", title: "'Fix my grammar' becomes a glyf that works on a sample",
    run: async () => {
      const g = await post("/builder/generate", { description: "Fix my grammar and spelling" });
      return post("/builder/test", { def: g.json.def, input: "i has went to the store yesterday and buyed milk" });
    },
    check: r => r.status === 200 && /went|bought/i.test(r.json.text ?? "") && !/buyed/i.test(r.json.text ?? ""),
    show: r => (r.json.text ?? "").slice(0, 120) },
  { id: "S49", area: "Translate", title: "Mixed Hinglish with English words detected as Hindi",
    run: () => post("/translate", { text: "meeting postpone ho gayi hai, kal 4 baje rakhte hain", primary: "English", secondary: "Hindi" }),
    check: r => r.json.detected === "Hindi" && r.json.target === "English" && /tomorrow/i.test(r.json.translation ?? ""),
    show: r => `${r.json.detected} → ${r.json.target}: ${r.json.translation}` },
  { id: "S50", area: "Places", title: "A place's own name finds that place",
    run: () => act("Phoenix Marketcity Bangalore", { intent: "place" }),
    check: r => r.json.intent === "place" && /phoenix/i.test((r.json.cards ?? [])[0]?.title ?? ""),
    show: r => `${(r.json.cards ?? [])[0]?.title ?? r.json.text} (${(r.json.cards ?? [])[0]?.address ?? ""})` },
];

const only = process.env.ONLY ? new Set(process.env.ONLY.split(",")) : null;
const results = [];
for (const s of scenarios.filter(x => !only || only.has(x.id))) {
  let r, verdict = "fail", note = "";
  try {
    r = await s.run();
    const c = s.check(r);
    verdict = c === true ? "pass" : typeof c === "string" ? c : "fail";
    note = s.show ? s.show(r) : "";
  } catch (e) {
    note = "error: " + (e?.message ?? String(e));
  }
  results.push({ id: s.id, area: s.area, title: s.title, verdict, ms: r?.ms ?? null, status: r?.status ?? null, note });
  console.log(`${verdict.toUpperCase()} ${s.id} [${s.area}] ${s.title} (${r?.ms ?? "?"} ms)\n     ${note}`);
}
const out = new URL("./results/server.json", import.meta.url);
if (!only) writeFileSync(out, JSON.stringify(results, null, 1));
else if (process.env.MERGE) {
  // A rerun of some scenarios replaces just those, marked as reruns.
  const saved = JSON.parse(readFileSync(out, "utf8"));
  for (const r of results) {
    const i = saved.findIndex(x => x.id === r.id);
    const entry = { ...r, note: `${r.note} (rerun)` };
    if (i >= 0) saved[i] = entry; else saved.push(entry);
  }
  writeFileSync(out, JSON.stringify(saved, null, 1));
}
const count = v => results.filter(r => v(r.verdict)).length;
console.log(`\n${count(v => v === "pass")} pass, ${count(v => v === "fail")} fail, ${count(v => v.startsWith("blocked"))} blocked of ${results.length}`);

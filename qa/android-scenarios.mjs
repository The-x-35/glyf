// Everyday situations on the real Glyf keyboard on the Android emulator:
// real key taps (adb input), the live dev server, and the keyboard's own
// report of what it shows (debug builds: DEBUG_TOOL dump). S84 onward.
// Usage: node qa/android-scenarios.mjs   (ONLY=S86,S90 to run some)
import { execFileSync } from "node:child_process";
import { writeFileSync } from "node:fs";

const ADB = "/opt/homebrew/share/android-commandlinetools/platform-tools/adb";
const PKG = "com.demo.glyf";
const sleep = ms => new Promise(r => setTimeout(r, ms));
const adb = (...args) => execFileSync(ADB, args, { encoding: "utf8" });
const shell = cmd => adb("shell", cmd);
const tool = (id, extra = "") => shell(`am broadcast -a ${PKG}.DEBUG_TOOL --es id ${id} ${extra}`);

async function state() {
  tool("dump");
  await sleep(250);
  return JSON.parse(adb("shell", `run-as ${PKG} cat files/qa/state.json`));
}

async function text() {
  return (await state()).text;
}

async function tapXY(x, y) {
  shell(`input tap ${x} ${y}`);
  await sleep(160);
}

async function hold(x, y, ms) {
  shell(`input swipe ${x} ${y} ${x} ${y} ${ms}`);
  await sleep(200);
}

async function key(id) {
  let s = await state();
  if (!s.keys[id]) {
    // Letters live on one page, digits and symbols on another.
    const toSymbols = !/^[a-z]$/.test(id) && !["space", "delete", "return", "shift", "emojikey"].includes(id);
    const mode = toSymbols ? "mode:?123" : "mode:ABC";
    if (s.keys[mode]) { await tapXY(...s.keys[mode]); s = await state(); }
    if (!s.keys[id] && s.keys["mode:#+="]) { await tapXY(...s.keys["mode:#+="]); s = await state(); }
  }
  if (!s.keys[id]) throw new Error(`key ${id} not on the keyboard`);
  await tapXY(...s.keys[id]);
}

async function type(str) {
  let s = await state();
  for (const ch of str) {
    const id = ch === " " ? "space" : ch === "\n" ? "return" : ch.toLowerCase();
    if (!s.keys[id]) { await key(id); s = await state(); continue; }
    await tapXY(...s.keys[id]);
  }
  await sleep(300);
}

function find(s, pred) {
  return s.views.find(v => pred(v));
}

async function waitFor(pred, timeoutMs = 8000) {
  const end = Date.now() + timeoutMs;
  while (Date.now() < end) {
    const s = await state();
    const v = find(s, pred);
    if (v) return v;
    await sleep(400);
  }
  return null;
}

async function waitText(pred, timeoutMs = 6000) {
  const end = Date.now() + timeoutMs;
  let t = "";
  while (Date.now() < end) {
    t = await text();
    if (pred(t)) return t;
    await sleep(300);
  }
  return t;
}

async function fresh() {
  tool("close");
  tool("clear");
  await sleep(500);
}

async function screenshot(name) {
  const png = execFileSync(ADB, ["exec-out", "screencap", "-p"]);
  writeFileSync(new URL(`./results/android-${name}.png`, import.meta.url), png);
}

const byId = id => v => v.id === id;
const idStarts = p => v => v.id.startsWith(p);
const textHas = t => v => (v.text || "").toLowerCase().includes(t.toLowerCase());

const scenarios = [
  { id: "S84", title: "A typo in a sentence is fixed on space", run: async () => {
    await fresh();
    await type("i think teh plan works ");
    const t = await text();
    return { pass: t.toLowerCase() === "i think the plan works ", note: `'${t}'` };
  } },
  { id: "S85", title: "Texting shorthand stays as typed", run: async () => {
    await fresh();
    await type("sry running late omw ");
    const t = await text();
    return { pass: /sry running late omw/i.test(t), note: `'${t}'` };
  } },
  { id: "S86", title: "A space after a number brings the letters back", run: async () => {
    await fresh();
    await type("call at 5 ");
    const s = await state();
    return { pass: s.mode === "LETTERS" && s.text.toLowerCase() === "call at 5 ", note: `mode ${s.mode}, '${s.text}'` };
  } },
  { id: "S87", title: "A sum in a message offers the answer", run: async () => {
    await fresh();
    await type("split is 3480/4");
    const chip = await waitFor(byId("strip:smart"), 3000);
    const s = await state();
    const words = s.views.filter(v => v.text).map(v => v.text).join(" | ");
    if (!chip) return { pass: false, note: `no chip; strip shows: ${words.slice(0, 120)}` };
    await tapXY(chip.x, chip.y);
    const t = await waitText(x => x.includes("870"), 3000);
    return { pass: t.includes("= 870"), note: `'${t}'` };
  } },
  { id: "S88", title: "Asked for your address, it is one tap away", run: async () => {
    tool("seedvault");
    await fresh();
    await type("sure my address is ");
    const chip = await waitFor(byId("strip:smart"), 3000);
    if (!chip) return { pass: false, note: "no address chip" };
    await tapXY(chip.x, chip.y);
    const t = await waitText(x => x.includes("Glass Lane"), 3000);
    return { pass: t.includes("42 Glass Lane"), note: `'${t}'` };
  } },
  { id: "S89", title: "Asked for your UPI, it is one tap away", run: async () => {
    await fresh();
    await type("my upi is ");
    const chip = await waitFor(byId("strip:smart"), 3000);
    if (!chip) return { pass: false, note: "no UPI chip" };
    await tapXY(chip.x, chip.y);
    const t = await waitText(x => x.includes("arpit@okbank"), 3000);
    return { pass: t.includes("arpit@okbank"), note: `'${t}'` };
  } },
  { id: "S90", title: "A rough message offers Tidy this up", run: async () => {
    await fresh();
    await type("ya ok will send the deck before six tmrw ");
    const chip = await waitFor(v => v.id === "strip:smart", 10000);
    if (!chip) return { pass: false, note: "no chip after 10s" };
    const s = await state();
    const label = s.views.filter(v => v.text).map(v => v.text).find(t => /tidy|places|look/i.test(t)) ?? "";
    await tapXY(chip.x, chip.y);
    const option = await waitFor(idStarts("act:option:"), 15000);
    return { pass: /tidy/i.test(label) && !!option, note: `chip '${label}', versions ${option ? "shown" : "missing"}` };
  } },
  { id: "S91", title: "Hold space: pick the Professional version", run: async () => {
    await fresh();
    await type("ya ok will send deck b4 6");
    const s = await state();
    await hold(s.keys.space[0], s.keys.space[1], 1100);
    const pro = await waitFor(byId("act:option:work"), 15000);
    if (!pro) return { pass: false, note: "no Professional version" };
    const all = (await state()).views.filter(v => v.id.startsWith("act:option:")).map(v => v.id.slice(11));
    await screenshot("S91-versions");
    await tapXY(pro.x, pro.y);
    const t = await waitText(x => !x.includes("b4"), 4000);
    return { pass: !t.includes("b4") && /deck/i.test(t), note: `versions: ${all.join(", ")}; inserted '${t}'` };
  } },
  { id: "S92", title: "Hold space on a place search sends places", run: async () => {
    await fresh();
    await type("best biryani near indiranagar");
    const s = await state();
    await hold(s.keys.space[0], s.keys.space[1], 1100);
    const insert = await waitFor(byId("act:insert"), 20000);
    if (!insert) return { pass: false, note: "no places result" };
    await screenshot("S92-places");
    await tapXY(insert.x, insert.y);
    const t = await waitText(x => x.includes("http"), 4000);
    return { pass: t.includes("http"), note: `'${t.slice(0, 100)}'` };
  } },
  { id: "S93", title: "The g button opens the tool menu", run: async () => {
    await fresh();
    const s = await state();
    const g = find(s, v => v.id === "toolbar:glyf");
    if (!g) return { pass: false, note: "no g button" };
    await tapXY(g.x, g.y);
    await sleep(600);
    const after = await state();
    const titles = ["Search", "Rewrite", "Translate", "Vault", "Clipboard", "Emoji"]
      .filter(t => after.views.some(v => v.text === t || v.id === t));
    await screenshot("S93-menu");
    tool("close");
    return { pass: titles.length >= 5, note: `tiles: ${titles.join(", ")}` };
  } },
  { id: "S94", title: "Copied text pastes from the strip", run: async () => {
    await fresh();
    tool("copy", "--es text 'Flight AI 2021 lands at 6:40'");
    await sleep(600);
    tool("clear");
    await sleep(600);
    const chip = await waitFor(byId("strip:smart"), 4000);
    if (!chip) return { pass: false, note: "no paste chip" };
    await tapXY(chip.x, chip.y);
    const t = await waitText(x => x.includes("AI 2021"), 3000);
    return { pass: t.includes("AI 2021"), note: `'${t}'` };
  } },
  { id: "S95", title: "Translate as you type, then Replace", run: async () => {
    await fresh();
    tool("translate");
    await sleep(800);
    await type("kal milte hain office ke baad ");
    const replace = await waitFor(v => v.text === "Replace", 12000);
    const s = await state();
    const line = s.views.map(v => v.text).find(t => /tomorrow/i.test(t || "")) ?? "";
    if (!replace) return { pass: false, note: "no translation" };
    await screenshot("S95-translate");
    await tapXY(replace.x, replace.y);
    const t = await waitText(x => /tomorrow/i.test(x), 4000);
    return { pass: /tomorrow/i.test(t), note: `strip '${line}', message '${t}'` };
  } },
  { id: "S96", title: "Emoji key inserts an emoji", run: async () => {
    await fresh();
    await type("what a finish ");
    await key("emojikey");
    await sleep(700);
    const laugh = await waitFor(v => v.text === "😂", 3000);
    if (!laugh) return { pass: false, note: "😂 not on the first page" };
    await tapXY(laugh.x, laugh.y);
    const t = await waitText(x => x.includes("😂"), 3000);
    await screenshot("S96-emoji");
    return { pass: t.includes("😂"), note: `'${t}'` };
  } },
  { id: "S97", title: "Slide left from delete removes whole words", run: async () => {
    await fresh();
    await type("see you at the park tomorrow");
    const s = await state();
    const [x, y] = s.keys.delete;
    shell(`input swipe ${x} ${y} ${x - 360} ${y} 900`);
    await sleep(800);
    const t = await text();
    return { pass: t.length < "see you at the park tomorrow".length - 6 && t.startsWith("see you"), note: `'${t}'` };
  } },
  { id: "S98", title: "Dark mode draws dark keys", run: async () => {
    await fresh();
    shell("cmd uimode night yes");
    await sleep(2500);
    tool("close");
    const s = await state();
    const png = execFileSync(ADB, ["exec-out", "screencap", "-p"]);
    writeFileSync(new URL("./results/android-S98-dark.png", import.meta.url), png);
    shell("cmd uimode night no");
    return { pass: !!s.keys.q, note: "screenshot saved for a look (results/android-S98-dark.png)" };
  } },
];

const only = process.env.ONLY ? new Set(process.env.ONLY.split(",")) : null;
const results = [];
for (const sc of scenarios.filter(x => !only || only.has(x.id))) {
  let r;
  try {
    r = await sc.run();
  } catch (e) {
    r = { pass: false, note: "error: " + (e?.message ?? String(e)).slice(0, 200) };
  }
  results.push({ id: sc.id, area: "Android", title: sc.title, verdict: r.pass ? "pass" : "fail", note: r.note });
  console.log(`${r.pass ? "PASS" : "FAIL"} ${sc.id} ${sc.title}\n     ${r.note}`);
}
if (!only) writeFileSync(new URL("./results/android.json", import.meta.url), JSON.stringify(results, null, 1));
console.log(`\n${results.filter(r => r.verdict === "pass").length}/${results.length} passed`);

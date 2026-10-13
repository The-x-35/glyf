// Everyday situations on the real Glyf keyboard on the Android emulator:
// real key taps (adb input), the live dev server, and the keyboard's own
// report of what it shows (debug builds: DEBUG_TOOL dump). S84 onward.
// Usage: node qa/android-scenarios.mjs   (ONLY=S86,S90 to run some)
import { execFileSync } from "node:child_process";
import { writeFileSync } from "node:fs";

const ADB = "/opt/homebrew/share/android-commandlinetools/platform-tools/adb";
const PKG = "com.arpit.glyf";
const sleep = ms => new Promise(r => setTimeout(r, ms));
const adb = (...args) => execFileSync(ADB, args, { encoding: "utf8" });
const shell = cmd => adb("shell", cmd);
const tool = (id, extra = "") => shell(`am broadcast -a ${PKG}.DEBUG_TOOL --es id ${id} ${extra}`);

const readState = () => {
  try { return JSON.parse(adb("shell", `run-as ${PKG} cat files/qa/state.json`)); } catch { return {}; }
};

async function state() {
  // A dump newer than the last one, not one "recent" by the Mac's clock: the
  // emulator's clock drifts (9 s behind on 2026-09-26), which made every
  // fresh dump look stale.
  const before = readState().at || 0;
  tool("dump");
  // Up to 6 s: after a light/dark switch the keyboard rebuilds its view on
  // the emulator's software renderer before it gets to the dump.
  for (let i = 0; i < 24; i++) {
    await sleep(250);
    const s = readState();
    // No newer file means the Glyf keyboard didn't answer: another keyboard
    // is active, or it crashed. Its keys would be taps into nothing.
    if (s.at && s.at > before) return s;
  }
  throw new Error("the Glyf keyboard didn't answer (not the active keyboard, or it crashed)");
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
    // The second symbols page ("+", "=") goes back to the digits by "123".
    const mode = toSymbols ? (s.keys["mode:?123"] ? "mode:?123" : "mode:123") : "mode:ABC";
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
    // A space after a number brings the letters back (S86), so the keys
    // read before it are no longer where they were ("b4 6" typed "b4 y").
    if (id === "space" && s.mode !== "LETTERS") s = await state();
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

// Taps a keyboard control and waits for its effect on the message. The
// emulator drops an injected tap now and then (most often the first one
// after something new appears), so when nothing happened and the control is
// still there, it is tapped once more; the note says so, in case the
// keyboard itself is what needs two taps.
async function tapFor(view, effect, ms = 3000) {
  await tapXY(view.x, view.y);
  let t = await waitText(effect, ms);
  if (effect(t)) return { t, retried: false };
  const again = view.id ? await waitFor(byId(view.id), 500) : null;
  if (!again) return { t, retried: false };
  await tapXY(again.x, again.y);
  t = await waitText(effect, ms);
  return { t, retried: true };
}
const second = r => r.retried ? " (took a second tap)" : "";

// The same for a control that opens something in the keyboard: tapped once
// more when nothing opened and the control is still there.
async function tapOpen(view, pred, ms = 3000) {
  await tapXY(view.x, view.y);
  const v = await waitFor(pred, ms);
  if (v) return v;
  const again = view.id ? await waitFor(byId(view.id), 500) : null;
  if (!again) return null;
  await tapXY(again.x, again.y);
  return await waitFor(pred, ms);
}

async function fresh() {
  tool("close");
  tool("clear");
  await sleep(500);
}

// A hand-over only counts if the clipboard changes, so when it already holds
// the same kind of item, put a line of text there first. (The emulator shares
// its clipboard with the Mac, so this is done only when needed.)
async function freshClip(label) {
  if ((await state()).clipLabel === label) {
    tool("copy", "--es text 'before the hand-over'");
    await sleep(300);
  }
}

async function screenshot(name) {
  const png = execFileSync(ADB, ["exec-out", "screencap", "-p"]);
  writeFileSync(new URL(`./results/android-${name}.png`, import.meta.url), png);
}

// S98's steps, run with screenshots switched on.
async function screenshotInClipboard() {
  await fresh();
  // A real capture of the screen, saved where the phone saves screenshots
  // and indexed the way the system indexes one (the emulator ignores the
  // screenshot key combination).
  const name = `Screenshot_${new Date().toISOString().replace(/\D/g, "").slice(0, 14)}.png`;
  shell(`screencap -p /sdcard/Pictures/Screenshots/${name}`);
  shell("content call --uri content://media/ --method scan_volume --arg external_primary");
  await sleep(2500);
  tool("clipboard");
  const shot = await waitFor(v => v.id === "Screenshot", 6000);
  if (!shot) return { pass: false, note: "no screenshot card in the clipboard" };
  await screenshot("S98-clipboard");
  await tapXY(shot.x, shot.y);
  await sleep(1200);
  const s = await state();
  // The copied picture must not come back as "text": the strip's paste
  // chip once showed the screenshot's PNG bytes, 200,000 characters of them.
  const junk = s.views.find(v => (v.text || "").length > 1000);
  if (junk) return { pass: false, note: `a ${junk.text.length}-character label appeared (${junk.id || "no id"})` };
  // A text box takes no images, so it is copied for pasting, as Gboard does.
  return { pass: s.clipMime.startsWith("image/") || s.clipMime === "text/uri-list",
    note: `tapped the screenshot: clipboard now holds ${s.clipMime || "nothing"} (${s.clipLabel})` };
}

// The calendar allowed (read and write) and switched on, as Connected tools →
// Calendar leaves it. Permissions granted here are revoked when the run ends.
async function calendarOn() {
  for (const perm of ["android.permission.READ_CALENDAR", "android.permission.WRITE_CALENDAR"]) {
    const granted = new RegExp(`${perm.split(".").pop()}: granted=true`).test(shell(`dumpsys package ${PKG} | grep "${perm}: granted"`));
    if (!granted) {
      shell(`pm grant ${PKG} ${perm}`);
      atEnd.push(() => shell(`pm revoke ${PKG} ${perm}`));
    }
  }
  tool("calendaron");
  // Google Calendar and Meet off unless a scenario connects the stand-in.
  tool("googlefake");
  await sleep(300);
}

// Work to do once every scenario has run. Revoking a permission makes Android
// kill the app (and the keyboard with it), so it can't happen mid-run.
const atEnd = [];

// Turns on the photo permission and "screenshots in the clipboard" for a run,
// and returns a function that puts both back as they were: the setting at
// once, the permission when the whole run is over.
async function screenshotsOn() {
  const perm = "android.permission.READ_MEDIA_IMAGES";
  const granted = /READ_MEDIA_IMAGES: granted=true/.test(shell(`dumpsys package ${PKG} | grep "${perm}: granted"`));
  const file = "files/bridge/settings.json";
  const before = adb("shell", `run-as ${PKG} cat ${file}`);
  const settings = JSON.parse(before);
  const write = text => writeSettings(text);
  if (!granted) shell(`pm grant ${PKG} ${perm}`);
  if (settings.clipboardScreenshots === false) write(JSON.stringify({ ...settings, clipboardScreenshots: true }));
  if (!granted) atEnd.push(() => shell(`pm revoke ${PKG} ${perm}`));
  return async () => {
    if (settings.clipboardScreenshots === false) write(before);
  };
}

// The stand-in Cal.com (qa/fake-scheduling.mjs), on this Mac.
const FAKE = "http://127.0.0.1:8796";
// The stand-in Google (qa/fake-google.mjs): this Mac reads its log on
// 127.0.0.1, the emulator reaches it on 10.0.2.2.
const FAKE_GOOGLE = "http://127.0.0.1:8797";
const FAKE_GOOGLE_FOR_PHONE = "http://10.0.2.2:8797";

// New Event's rows scroll when the panel is short, and a row below the fold
// still has a place in the dump: drag the rows up from the Starts row (always
// in view, on the labels' side, away from the switches), then read again.
async function rowInView(id) {
  const from = await waitFor(byId("event:starts:time"), 3000) || await waitFor(byId("event:starts:date"), 1000);
  const header = await waitFor(byId("event:add"), 1000);
  if (!from || !header) return await waitFor(byId(id), 2000);
  const w = Number(shell("wm size").match(/(\d+)x(\d+)/)[1]);
  const x = Math.round(w * 0.25);
  shell(`input swipe ${x} ${from.y} ${x} ${header.y} 400`);
  await sleep(700);
  return await waitFor(byId(id), 2000);
}

const byId = id => v => v.id === id;
const idStarts = p => v => v.id.startsWith(p);
const textHas = t => v => (v.text || "").toLowerCase().includes(t.toLowerCase());

// Where a tap types a chip's saved value: a details chip (two saved values,
// or your email and Temp mail, 2026-10-01) holds each value on a part of its
// own, so the first part; any other chip anywhere on it.
const firstValue = (s, chip) => find(s, byId("strip:smart:choice:0")) || chip;

// Every tool, by the id the strip's icon and the menu's tile carry.
const TOOL_IDS = ["search", "rewrite", "translate", "vault", "calendar", "tempmail", "clipboard", "gifs",
  "ask", "dictation", "glyfs", "pay", "games", "settings"];

// A tool opens from the strip when it is there, else from the g menu, which
// holds only what the strip doesn't (S199). A g tap over suggestions brings
// the tools back instead, so either is taken once it shows.
async function openTool(id) {
  const s = await state();
  const onStrip = find(s, byId(id));
  if (onStrip) { await tapXY(onStrip.x, onStrip.y); return true; }
  const g = find(s, byId("toolbar:glyf"));
  if (!g) return false;
  await tapXY(g.x, g.y);
  const v = await waitFor(x => x.id === `shell:tile:${id}` || x.id === id, 3000);
  if (!v) return false;
  await tapXY(v.x, v.y);
  return true;
}

// A row below the fold of a panel that scrolls still has a place in the
// dump: drag the panel up (in its middle, away from the gesture bar) until
// the row is clear of the foot, or as far as the panel goes.
async function inView(id) {
  const [w, h] = shell("wm size").match(/(\d+)x(\d+)/).slice(1).map(Number);
  let last = null;
  for (let i = 0; i < 8; i++) {
    const v = find(await state(), byId(id));
    if (!v) return null;
    if (v.y < h - 240 || v.y === last) return v;
    last = v.y;
    shell(`input swipe ${Math.round(w / 2)} ${h - 420} ${Math.round(w / 2)} ${h - 820} 350`);
    await sleep(700);
  }
  return null;
}

// The vault's "+" floats in the panel's corner; what it adds (note, detail,
// shorthand) shows only once it is tapped.
async function vaultAdd(what) {
  const plus = await waitFor(byId("vault:add"), 3000);
  return plus ? await tapOpen(plus, byId(`vault:new:${what}`)) : null;
}

// The card a line of text sits in (a panel's rows carry their ids on the
// card, their words on its children).
// The card holding [text]: in a list, the one at its height; in a grid (the
// vault's three to a row), the one it sits inside.
const cardOf = (s, prefix, text) => {
  const t = s.views.find(v => v.text === text);
  return t && s.views.find(v => v.id.startsWith(prefix) && Math.abs(v.y - t.y) < v.h / 2 &&
    Math.abs(v.x - t.x) < v.w / 2);
};
// Where a card comes in reading order: row by row, left to right.
const readingPos = v => Math.round(v.y / 20) * 100000 + v.x;

// Settings the app would write, set for one scenario and put back after it.
const SETTINGS = "files/bridge/settings.json";
const readSettings = () => adb("shell", `run-as ${PKG} cat ${SETTINGS}`);
// Written beside it, then swapped in, as the app writes it: the keyboard
// looks at its settings every 0.4 s, and a file caught half-written (`cat >`
// empties it first) reads as missing, which puts the defaults in its place
// (2026-10-01: a run lost tempMailBase that way, and the phone's deviceId).
function writeSettings(text) {
  execFileSync(ADB, ["shell", `run-as ${PKG} sh -c 'cat > ${SETTINGS}.qa && mv ${SETTINGS}.qa ${SETTINGS}'`],
    { input: text });
}

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
    const r = await tapFor(chip, x => x.includes("870"));
    return { pass: r.t.includes("= 870"), note: `'${r.t}'${second(r)}` };
  } },
  { id: "S88", title: "Asked for your address, it is one tap away", run: async () => {
    // The vault keeps whatever it already holds; seedvault only adds an
    // address and a wallet address where there are none, so the check is that the
    // chip puts a saved value after the words, not which value.
    tool("seedvault");
    await fresh();
    await type("sure my address is ");
    const chip = await waitFor(byId("strip:smart"), 3000);
    if (!chip) return { pass: false, note: "no address chip" };
    const r = await tapFor(firstValue(await state(), chip), x => x.length > "sure my address is ".length + 4);
    return { pass: /^sure my address is \S/i.test(r.t) && /\d/.test(r.t), note: `'${r.t}'${second(r)}` };
  } },
  { id: "S89", title: "Asked for your wallet address, it is one tap away", run: async () => {
    tool("seedvault");
    await fresh();
    await type("my wallet address is ");
    const chip = await waitFor(byId("strip:smart"), 3000);
    if (!chip) return { pass: false, note: "no wallet chip" };
    const r = await tapFor(firstValue(await state(), chip), x => /[1-9A-HJ-NP-Za-km-z]{32,44}/.test(x));
    return { pass: /^my wallet address is [1-9A-HJ-NP-Za-km-z]{32,44}/i.test(r.t), note: `'${r.t}'${second(r)}` };
  } },
  { id: "S90", title: "A rough message offers Tidy this up", run: async () => {
    await fresh();
    await type("ya ok will send the deck before six tmrw ");
    const chip = await waitFor(v => v.id === "strip:smart", 10000);
    if (!chip) return { pass: false, note: "no chip after 10s" };
    const s = await state();
    const label = s.views.filter(v => v.text).map(v => v.text).find(t => /tidy|places|look/i.test(t)) ?? "";
    await tapXY(chip.x, chip.y);
    // The free models behind the dev server can take 15 s or more, so the
    // wait is generous and the note says how long it took.
    const t0 = Date.now();
    const option = await waitFor(idStarts("act:option:"), 25000);
    const secs = ((Date.now() - t0) / 1000).toFixed(1);
    return { pass: /tidy/i.test(label) && !!option,
      note: `chip '${label}', versions ${option ? `shown after ${secs}s` : `missing after ${secs}s`}` };
  } },
  { id: "S91", title: "Hold space: pick the Professional version", run: async () => {
    await fresh();
    await type("ya ok will send deck b4 6");
    const s = await state();
    await hold(s.keys.space[0], s.keys.space[1], 1100);
    const pro = await waitFor(byId("act:option:work"), 25000);
    if (!pro) return { pass: false, note: "no Professional version after 25s" };
    const all = (await state()).views.filter(v => v.id.startsWith("act:option:")).map(v => v.id.slice(11));
    await screenshot("S91-versions");
    const r = await tapFor(pro, x => !x.includes("b4"), 4000);
    return { pass: !r.t.includes("b4") && /deck/i.test(r.t), note: `versions: ${all.join(", ")}; inserted '${r.t}'${second(r)}` };
  } },
  { id: "S92", title: "Hold space on a place search sends places", run: async () => {
    await fresh();
    await type("best biryani near indiranagar");
    const s = await state();
    await hold(s.keys.space[0], s.keys.space[1], 1100);
    const insert = await waitFor(byId("act:insert"), 20000);
    if (!insert) return { pass: false, note: "no places result" };
    await screenshot("S92-places");
    const r = await tapFor(insert, x => x.includes("http"), 4000);
    return { pass: r.t.includes("http"), note: `'${r.t.slice(0, 100)}'${second(r)}` };
  } },
  { id: "S93", title: "The g button opens the tool menu", run: async () => {
    await fresh();
    const s = await state();
    const g = find(s, v => v.id === "toolbar:glyf");
    if (!g) return { pass: false, note: "no g button" };
    await tapXY(g.x, g.y);
    await sleep(600);
    const after = await state();
    const tiles = after.views.filter(v => v.id.startsWith("shell:tile:")).map(v => v.id.slice(11));
    await screenshot("S93-menu");
    tool("close");
    // The strip keeps Search, Clipboard, Vault, Voice and Translate; the
    // menu has the rest (S199 checks that nothing is in both).
    const want = ["rewrite", "calendar", "gifs", "glyfs"];
    return { pass: want.every(t => tiles.includes(t)), note: `tiles: ${tiles.join(", ")}` };
  } },
  { id: "S94", title: "Copied text pastes from the strip", run: async () => {
    await fresh();
    tool("copy", "--es text 'Flight AI 2021 lands at 6:40'");
    await sleep(600);
    tool("clear");
    await sleep(600);
    const chip = await waitFor(byId("strip:smart"), 4000);
    if (!chip) return { pass: false, note: "no paste chip" };
    const r = await tapFor(chip, x => x.includes("AI 2021"));
    return { pass: r.t.includes("AI 2021"), note: `'${r.t}'${second(r)}` };
  } },
  { id: "S95", title: "Translate as you type, then Replace", run: async () => {
    await fresh();
    tool("translate");
    await sleep(800);
    await type("kal milte hain office ke baad ");
    // Replace is on the strip from the start, dimmed until the translation
    // arrives; tapping it earlier does nothing, so wait for the words.
    const arrived = await waitFor(v => /tomorrow/i.test(v.text || ""), 12000);
    const line = arrived?.text ?? "";
    const replace = find(await state(), v => v.text === "Replace");
    if (!arrived || !replace) return { pass: false, note: arrived ? "no Replace" : "no translation" };
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
  // The emoji board's Stickers, GIFs and Emoticons (2026-09-24). GIFs need a
  // KLIPY key on the server, or KLIPY_BASE_URL at qa/fake-klipy.mjs with
  // `adb reverse tcp:8798 tcp:8798` so the emulator reaches it.
  { id: "S106", title: "Emoticons type straight into the message", run: async () => {
    await fresh();
    await type("see you ");
    await key("emojikey");
    const mode = await waitFor(byId("emoji:mode:emoticons"), 3000);
    if (!mode) return { pass: false, note: "no emoticons glyph on the board" };
    await tapXY(mode.x, mode.y);
    const classic = await waitFor(byId("emoji:chip:classic"), 3000);
    if (classic) await tapXY(classic.x, classic.y);
    const first = await waitFor(byId("emoji:emoticon:0"), 3000);
    if (!first) return { pass: false, note: "no emoticons" };
    await tapXY(first.x, first.y);
    const t = await waitText(x => x.includes(first.text), 3000);
    return { pass: t.endsWith(" " + first.text) || t.includes(" " + first.text), note: `'${t}'` };
  } },
  { id: "S107", title: "The GIF tab shows GIFs and hands one over", run: async () => {
    await fresh();
    await key("emojikey");
    const mode = await waitFor(byId("emoji:mode:gifs"), 3000);
    if (!mode) return { pass: false, note: "no GIF glyph on the board" };
    await tapXY(mode.x, mode.y);
    const gif = await waitFor(byId("emoji:media:0"), 12000);
    if (!gif) {
      const s = await state();
      return { pass: false, note: `no GIFs; the board says '${(find(s, byId("emoji:status")) || {}).text || ""}'` };
    }
    await screenshot("S107-gifs");
    await freshClip("GIF");
    await tapXY(gif.x, gif.y);
    await sleep(2500);
    const s = await state();
    // The Glyf app's own field takes no images, so the GIF is copied.
    return { pass: s.clipMime === "image/gif" && s.clipLabel === "GIF", note: `clipboard now holds ${s.clipMime} (${s.clipLabel})` };
  } },
  { id: "S108", title: "The Stickers tab shows stickers and hands one over", run: async () => {
    await fresh();
    await key("emojikey");
    const mode = await waitFor(byId("emoji:mode:stickers"), 3000);
    if (!mode) return { pass: false, note: "no sticker glyph on the board" };
    await tapXY(mode.x, mode.y);
    const sticker = await waitFor(byId("emoji:media:0"), 12000);
    if (!sticker) return { pass: false, note: "no stickers" };
    await freshClip("Sticker");
    await tapXY(sticker.x, sticker.y);
    await sleep(3000);
    const s = await state();
    return { pass: s.clipMime.startsWith("image/") && s.clipLabel === "Sticker", note: `clipboard now holds ${s.clipMime} (${s.clipLabel})` };
  } },
  // New Event in the keyboard's calendar (2026-09-24): the phone's calendar
  // provider, a local "Glyf" calendar when the phone has no account.
  { id: "S111", title: "New Event from the keyboard's calendar lands in the calendar", run: async () => {
    await calendarOn();
    await fresh();
    tool("calendar");
    const plus = await waitFor(byId("calendar:new"), 4000);
    if (!plus) return { pass: false, note: "no + on the calendar" };
    const title = await tapOpen(plus, byId("event:title"));
    if (!title) return { pass: false, note: "New Event didn't open" };
    if (!(await tapOpen(title, byId("event:title:field")))) return { pass: false, note: "no title strip" };
    await type("lunch with sam tomorrow 1pm");
    const hint = (find(await state(), byId("event:hint")) || {}).text || "";
    await key("return");
    const starts = await waitFor(byId("event:starts:time"), 3000);
    // Share in chat off: this one is for the day's list.
    const share = await rowInView("event:share");
    if (!share) return { pass: false, note: "no Share in chat row" };
    await tapXY(share.x, share.y);
    await sleep(300);
    const add = await waitFor(byId("event:add"), 2000);
    if (!add) return { pass: false, note: `no Add; hint '${hint}'` };
    await tapXY(add.x, add.y);
    if (!(await waitFor(v => v.text === "Lunch with sam", 5000))) {
      return { pass: false, note: `the event isn't in the day's list; starts '${starts?.text}', hint '${hint}'` };
    }
    // The list scrolls the new event into view. Earlier runs left events
    // with the same name on that day, scrolled out of sight now but still in
    // the dump, so tap the one between the day's header and its buttons.
    await sleep(800);
    const s = await state();
    const top = (find(s, byId("calendar:new")) || { y: 0 }).y;
    const bottom = (find(s, byId("calendar:free")) || find(s, byId("calendar:connect")) || { y: 1e9 }).y;
    const row = s.views.find(v => v.text === "Lunch with sam" && v.y > top + 40 && v.y < bottom - 40);
    if (!row) return { pass: false, note: "the new event isn't in view" };
    await screenshot("S111-added");
    const r = await tapFor(row, x => x.includes("Lunch with sam"), 3000);
    return { pass: (starts?.text || "").includes("1:00") && r.t.includes("Lunch with sam"),
      note: `starts '${starts?.text}', hint '${hint}', message '${r.t}'${second(r)}` };
  } },
  { id: "S112", title: "A plan in a message offers Add to calendar, and the event follows the plan into the message", run: async () => {
    await calendarOn();
    await fresh();
    await type("dinner friday 8pm");
    const chip = await waitFor(byId("strip:smart"), 4000);
    if (!chip) return { pass: false, note: "no chip for a plan" };
    const words = (await state()).views.map(v => v.text).find(t => /Dinner/.test(t || "")) || "";
    await tapXY(chip.x, chip.y);
    const add = await waitFor(byId("event:add"), 4000);
    if (!add) return { pass: false, note: `chip '${words}' didn't open New Event` };
    const starts = (find(await state(), byId("event:starts:time")) || {}).text || "";
    // Share in chat is on from a plan too (2026-10-01: "creating a calendar
    // event should also send its meeting link in chat with calendar
    // details"); without Google there is no call link to send.
    const share = await rowInView("event:share");
    const r = await tapFor(add, x => x.includes("📅 Dinner"), 6000);
    return { pass: starts.includes("8:00") && share?.selected === true &&
        /^dinner friday 8pm 📅 Dinner · .*8:00/i.test(r.t) && !r.t.includes("http"),
      note: `chip '${words}', starts '${starts}', Share in chat ${share ? (share.selected ? "on" : "off") : "missing"}; message '${r.t}'${second(r)}` };
  } },
  // Call links, Book a time and invites (2026-09-24). S118 to S120 need the
  // stand-in Cal.com and Resend (qa/fake-scheduling.mjs on 8796) behind the
  // dev server; they never book or mail anyone real.
  { id: "S117", title: "Without Google, the camera sends no other kind of call link", run: async () => {
    await calendarOn();
    await fresh();
    tool("calendar");
    const call = await waitFor(byId("calendar:call"), 4000);
    if (!call) return { pass: false, note: "no call button on the calendar" };
    await tapXY(call.x, call.y);
    await sleep(2500);
    // Call links are Google Meet only: the keyboard asks for Google instead.
    const t = await text();
    const still = await waitFor(byId("calendar:call"), 1000);
    return { pass: t === "" && !!still, note: `message '${t}'; calendar ${still ? "still open" : "closed"}` };
  } },
  { id: "S118", title: "Book a time on your own page for someone, with a guest", run: async () => {
    await fetch(`${FAKE}/_reset`);
    await useFakeCalcom();
    tool("bookinglink", "--es text cal.com/fake-host/30min");
    try {
      await calendarOn();
      await fresh();
      tool("calendar");
      const book = await waitFor(byId("calendar:book"), 4000);
      if (!book) return { pass: false, note: "no Book a time on the calendar" };
      if (!(await tapOpen(book, byId("booking:back")))) return { pass: false, note: "Book a time didn't open" };
      let slot = await waitFor(byId("booking:slot:0"), 10000);
      // Late in the day there may be nothing left today.
      for (let i = 0; i < 3 && !slot; i++) {
        const next = await waitFor(byId("booking:next"), 2000);
        if (next) await tapXY(next.x, next.y);
        slot = await waitFor(byId("booking:slot:0"), 8000);
      }
      if (!slot) return { pass: false, note: `no open time; the panel says '${(find(await state(), byId("booking:status")) || {}).text}'` };
      if (!(await tapOpen(slot, byId("booking:who:field")))) return { pass: false, note: "no who field" };
      await type("sam lee sam@example.com ria@example.com");
      const hint = (find(await state(), byId("booking:who:hint")) || {}).text || "";
      await key("return");
      const go = await waitFor(byId("booking:book"), 4000);
      if (!go) return { pass: false, note: `no Book it; hint '${hint}'` };
      const r = await tapFor(go, x => x.includes("Booked for"), 10000);
      const booked = (await (await fetch(`${FAKE}/_log`)).json()).bookings.at(-1) || {};
      const ok = r.t.includes("Booked for") && r.t.includes("sam@example.com") &&
        booked.attendee?.email === "sam@example.com" && booked.attendee?.name?.toLowerCase() === "sam lee" &&
        JSON.stringify(booked.guests) === JSON.stringify(["ria@example.com"]);
      await screenshot("S118-booked");
      return { pass: ok, note: `hint '${hint}'; booked ${booked.attendee?.name} <${booked.attendee?.email}> + ${booked.guests}; message '${r.t}'${second(r)}` };
    } finally {
      tool("bookinglink");
    }
  } },
  { id: "S120", title: "Someone's booking page in a message offers Book", run: async () => {
    await fetch(`${FAKE}/_reset`);
    await useFakeCalcom();
    await calendarOn();
    await fresh();
    // Committed straight into the field (autocorrect would split a link
    // typed key by key); the strip reads the message all the same.
    // `input text` drops a key now and then ("…/intr"): type it again.
    const want = "grab a time cal.com/sam-lee/intro";
    let typed = "";
    for (let i = 0; i < 4 && typed !== want; i++) {
      if (i > 0) { tool("clear"); await sleep(500); }
      shell("input text 'grab%sa%stime%scal.com/sam-lee/intro'");
      typed = await waitText(x => x === want, 3000);
    }
    // Four tries that each dropped a key are the emulator's typing, not the chip.
    if (typed !== want) return { pass: false, note: `the link never arrived whole: '${typed}'` };
    const chip = await waitFor(v => v.id === "strip:smart", 5000);
    const words = (await state()).views.map(v => v.text).find(t => /A time on/.test(t || "")) || "";
    if (!chip || !words) return { pass: false, note: `no Book chip (strip says '${words}')` };
    if (!(await tapOpen(chip, byId("booking:back")))) return { pass: false, note: `chip '${words}' didn't open Book a time` };
    let slot = await waitFor(byId("booking:slot:0"), 10000);
    for (let i = 0; i < 3 && !slot; i++) {
      const next = await waitFor(byId("booking:next"), 2000);
      if (next) await tapXY(next.x, next.y);
      slot = await waitFor(byId("booking:slot:0"), 8000);
    }
    if (!slot) return { pass: false, note: `chip '${words}' opened no open times` };
    await tapXY(slot.x, slot.y);
    // Their page: it books you, from the vault's name and email, unless the
    // vault has no email (then it asks).
    if (await waitFor(byId("booking:who:field"), 1500)) {
      await type("ria k ria@example.com");
      await key("return");
    }
    const go = await waitFor(byId("booking:book"), 4000);
    if (!go) return { pass: false, note: "no Book it" };
    const r = await tapFor(go, x => x.includes("Booked for"), 10000);
    const booked = (await (await fetch(`${FAKE}/_log`)).json()).bookings.at(-1) || {};
    return { pass: r.t.includes("/intro Booked for") && booked.username === "sam-lee" && booked.eventTypeSlug === "intro",
      note: `chip '${words}'; booked on ${booked.username}/${booked.eventTypeSlug} as ${booked.attendee?.name} <${booked.attendee?.email}>; message '${r.t}'${second(r)}` };
  } },
  // Google Calendar and Meet (2026-09-24), against qa/fake-google.mjs: the
  // keyboard talks to "Google" itself, so no real account is touched.
  { id: "S125", title: "A Meet link from the calendar, with Google connected", run: async () => {
    await fetch(`${FAKE_GOOGLE}/_reset`);
    await calendarOn();
    tool("googlefake", `--es text ${FAKE_GOOGLE_FOR_PHONE}`);
    try {
      await fresh();
      tool("calendar");
      const call = await waitFor(byId("calendar:call"), 4000);
      if (!call) return { pass: false, note: "no call button on the calendar" };
      const r = await tapFor(call, x => x.includes("https://meet.google.com/"), 6000);
      const made = (await (await fetch(`${FAKE_GOOGLE}/_log`)).json()).spaces.length;
      return { pass: /Join me on a call: https:\/\/meet\.google\.com\//.test(r.t) && made >= 1,
        note: `message '${r.t}'; Meet links made ${made}${second(r)}` };
    } finally {
      tool("googlefake");
    }
  } },
  { id: "S126", title: "New Event with a guest goes to Google Calendar, which invites them", run: async () => {
    await fetch(`${FAKE_GOOGLE}/_reset`);
    await calendarOn();
    tool("googlefake", `--es text ${FAKE_GOOGLE_FOR_PHONE}`);
    try {
      await fresh();
      tool("calendar");
      const plus = await waitFor(byId("calendar:new"), 4000);
      if (!plus) return { pass: false, note: "no + on the calendar" };
      const title = await tapOpen(plus, byId("event:title"));
      if (!title) return { pass: false, note: "New Event didn't open" };
      if (!(await tapOpen(title, byId("event:title:field")))) return { pass: false, note: "no title strip" };
      await type("review friday 3pm");
      await key("return");
      const invitees = await waitFor(byId("event:invitees"), 3000);
      if (!invitees) return { pass: false, note: "no Invitees row with Google connected" };
      if (!(await tapOpen(invitees, byId("event:invitees:field")))) return { pass: false, note: "no invitees strip" };
      await type("sam@example.com");
      await key("return");
      // Video call is on from the start when Meet can make the link (2026-10-01).
      const video = await rowInView("event:video");
      if (!video) return { pass: false, note: "no Video call row" };
      if (!video.selected) return { pass: false, note: "Video call started off with Google connected" };
      const add = await waitFor(byId("event:add"), 3000);
      if (!add) return { pass: false, note: "no Add" };
      // Share in chat is on from +: the event lands in the message too.
      const r = await tapFor(add, x => x.includes("Review") && x.includes("https://meet.google.com/"), 8000);
      const last = (await (await fetch(`${FAKE_GOOGLE}/_log`)).json()).events.at(-1) || {};
      const guests = (last.body?.attendees || []).map(a => a.email);
      const ok = JSON.stringify(guests) === JSON.stringify(["sam@example.com"]) &&
        last.query?.sendUpdates === "all" && !!last.body?.conferenceData?.createRequest &&
        r.t.includes("Review") && r.t.includes("https://meet.google.com/");
      return { pass: ok, note: `event '${last.body?.summary}' for ${guests}, sendUpdates=${last.query?.sendUpdates}; message '${r.t}'${second(r)}` };
    } finally {
      tool("googlefake");
    }
  } },
  { id: "S127", title: "Without Google, New Event goes into the message", run: async () => {
    await calendarOn();
    await fresh();
    tool("calendar");
    const plus = await waitFor(byId("calendar:new"), 4000);
    if (!plus) return { pass: false, note: "no + on the calendar" };
    const title = await tapOpen(plus, byId("event:title"));
    if (!title) return { pass: false, note: "New Event didn't open" };
    const invitees = find(await state(), byId("event:invitees"));
    const video = find(await state(), byId("event:video"));
    if (!(await tapOpen(title, byId("event:title:field")))) return { pass: false, note: "no title strip" };
    await type("lunch with sam tomorrow 1pm");
    await key("return");
    const add = await waitFor(byId("event:add"), 3000);
    if (!add) return { pass: false, note: "no Add" };
    const r = await tapFor(add, x => x.includes("📅 Lunch with sam"), 6000);
    return { pass: !invitees && !video && r.t.includes("📅 Lunch with sam"),
      note: `${invitees ? "an Invitees row showed without Google; " : ""}${video ? "a Video call row showed without Google; " : ""}message '${r.t}'${second(r)}` };
  } },
  { id: "S137", title: "Without Google, the Meet key says where to connect it", run: async () => {
    tool("googlefake");
    tool("bind", "--es text m=connector:meet");
    try {
      await fresh();
      const s = await state();
      if (!s.keys.m) return { pass: false, note: "no M key" };
      await hold(s.keys.m[0], s.keys.m[1], 900);
      let notice = "";
      for (let i = 0; i < 8 && !notice; i++) { notice = (await state()).notice || ""; if (!notice) await sleep(200); }
      await screenshot("S137-notice");
      const t = (await state()).text;
      return { pass: notice === "Connect Google Meet in Glyf › Connected tools" && !t.includes("meet.google.com"),
        note: `notice '${notice}', message '${t}'` };
    } finally {
      tool("bind", "--es text m=");
    }
  } },
  { id: "S128", title: "A key held for a Meet link", run: async () => {
    await fetch(`${FAKE_GOOGLE}/_reset`);
    tool("googlefake", `--es text ${FAKE_GOOGLE_FOR_PHONE}`);
    tool("bind", "--es text m=connector:meet");
    try {
      await fresh();
      const s = await state();
      if (!s.keys.m) return { pass: false, note: "no M key" };
      await hold(s.keys.m[0], s.keys.m[1], 900);
      const t = await waitText(x => x.includes("https://meet.google.com/"), 8000);
      return { pass: /Join me on a call: https:\/\/meet\.google\.com\//.test(t), note: `message '${t}'` };
    } finally {
      tool("bind", "--es text m=");
      tool("googlefake");
    }
  } },
  { id: "S97", title: "Slide left from delete removes whole words", run: async () => {
    await fresh();
    await type("see you at the park tomorrow");
    const s = await state();
    const [x, y] = s.keys.delete;
    // Down, eight moves, up, sent one by one: `input swipe` can reach the
    // keyboard as a plain tap when the emulator coalesces its moves, and a
    // tap on delete removes one letter.
    shell(`input motionevent DOWN ${x} ${y}`);
    for (let i = 1; i <= 8; i++) {
      await sleep(70);
      shell(`input motionevent MOVE ${x - i * 45} ${y}`);
    }
    await sleep(150);
    shell(`input motionevent UP ${x - 360} ${y}`);
    await sleep(800);
    const t = await text();
    return { pass: t.length < "see you at the park tomorrow".length - 6 && /^see you/i.test(t), note: `'${t}'` };
  } },
  { id: "S98", title: "A screenshot you just took is in the clipboard", run: async () => {
    // Screenshots show only with the photo permission and the setting on;
    // both are switched on for this run and put back as they were after.
    const restore = await screenshotsOn();
    try { return await screenshotInClipboard(); } finally { await restore(); }
  } },
  { id: "S101", title: "Dark mode keys are dark, light mode keys are light", run: async () => {
    await fresh();
    const lum = async () => {
      const s = await state();
      const png = execFileSync(ADB, ["exec-out", "screencap", "-p"], { maxBuffer: 64e6 });
      const file = new URL("./results/android-lum.png", import.meta.url);
      writeFileSync(file, png);
      const [x, y] = s.keys.q;
      return Number(execFileSync("python3", ["-c",
        `from PIL import Image; im=Image.open('${file.pathname}').convert('RGB'); r,g,b=im.getpixel((${x - 30},${y + 30})); print((0.299*r+0.587*g+0.114*b)/255)`],
        { encoding: "utf8" }).trim());
    };
    try {
      shell("cmd uimode night yes");
      await sleep(3000);
      tool("close"); tool("clear");
      await sleep(800);
      const dark = await lum();
      shell("cmd uimode night no");
      await sleep(3000);
      tool("close"); tool("clear");
      await sleep(800);
      const light = await lum();
      return { pass: dark < 0.35 && light > 0.85, note: `key face ${dark.toFixed(2)} dark, ${light.toFixed(2)} light` };
    } finally {
      // Whatever happened, the phone goes back to light.
      shell("cmd uimode night no");
    }
  } },
  { id: "S130", title: "The strip starts with Glyf's key, the app icon's mark, light and dark", run: async () => {
    await fresh();
    // The key is drawn 41 by 30dp in the middle of its 52dp view
    // (GlyfKeyView): sample its face beside the letter and the middle of its
    // dot, where the app icon has it (GlyfMark.drawMark).
    const look = async () => {
      const s = await state();
      const g = find(s, v => v.id === "toolbar:glyf");
      if (!g) return null;
      const dp = g.w / 52, kh = 30 * dp, kw = Math.round(kh * 1.367);
      const left = g.x - kw / 2, top = g.y - kh / 2;
      const face = [Math.round(left + 5 * dp), Math.round(g.y)];
      const h = (kh - kh * 0.083 * 2) / 1.6565;
      const letterX = left + kw / 2 - h * 0.6699 / 2, letterY = g.y - h * 1.6565 / 2 + h * 0.6565;
      const dot = [Math.round(letterX + h * 1.0379), Math.round(letterY - h * 0.4927)];
      const png = execFileSync(ADB, ["exec-out", "screencap", "-p"], { maxBuffer: 64e6 });
      const file = new URL("./results/android-key.png", import.meta.url);
      writeFileSync(file, png);
      const [f, d] = JSON.parse(execFileSync("python3", ["-c",
        `from PIL import Image; import json; im=Image.open('${file.pathname}').convert('RGB'); print(json.dumps([im.getpixel((${face})), im.getpixel((${dot}))]))`],
        { encoding: "utf8" }).trim());
      return { face: (0.299 * f[0] + 0.587 * f[1] + 0.114 * f[2]) / 255, dot: d,
        violet: d[2] > 200 && d[0] > 80 && d[0] < 175 && d[1] < 140, g };
    };
    const light = await look();
    if (!light) return { pass: false, note: "no Glyf key on the strip" };
    await screenshot("S130-light");
    await tapXY(light.g.x, light.g.y);
    await sleep(600);
    const menu = (await state()).views.some(v => v.id.startsWith("shell:tile:"));
    tool("close");
    let dark;
    try {
      shell("cmd uimode night yes");
      await sleep(3000);
      tool("close"); tool("clear");
      await sleep(800);
      dark = await look();
      await screenshot("S130-dark");
    } finally {
      shell("cmd uimode night no");
    }
    // The logo follows the theme: the white icon on a light sheet, its dark twin on a dark one.
    const ok = (x, isDark) => x && (isDark ? x.face < 0.15 : x.face > 0.85) && x.violet;
    const fmt = x => x ? `face ${x.face.toFixed(2)}, dot ${x.dot.join(" ")}` : "no key";
    return { pass: ok(light, false) && ok(dark, true) && menu,
      note: `light: ${fmt(light)}; dark: ${fmt(dark)}; tap opens the menu: ${menu}` };
  } },
  { id: "S133", title: "Snake from the g menu turns with a swipe", run: async () => {
    const board = await openGame("snake");
    if (!board) return { pass: false, note: "g menu → Games → Snake didn't open" };
    const ready = board.desc;
    shell(`input swipe ${board.x} ${board.y + 60} ${board.x} ${board.y - 90} 120`);
    await sleep(1000);
    const moving = find(await state(), v => v.id === "games:board")?.desc ?? "";
    await screenshot("S133-snake");
    await tapXY(board.x, board.y);
    await sleep(500);
    const paused = find(await state(), v => v.id === "games:board")?.desc ?? "";
    tool("close");
    return { pass: ready.startsWith("ready") && moving.includes("playing") && moving.includes("heading up")
      && paused.startsWith("paused"), note: `'${ready}' → swipe up → '${moving}' → tap → '${paused}'` };
  } },
  { id: "S134", title: "Chomp eats its way along the maze", run: async () => {
    const board = await openGame("chomp");
    if (!board) return { pass: false, note: "g menu → Games → Chomp didn't open" };
    const ready = board.desc;
    await tapXY(board.x, board.y);
    await sleep(2000);
    const running = find(await state(), v => v.id === "games:board")?.desc ?? "";
    shell(`input swipe ${board.x} ${board.y - 60} ${board.x} ${board.y + 90} 120`);
    await sleep(800);
    await screenshot("S134-chomp");
    const score = Number((running.match(/score (\d+)/) ?? [])[1] ?? 0);
    const back = find(await state(), v => v.id === "games:back");
    if (back) await tapXY(back.x, back.y);
    await sleep(500);
    const picker = !!find(await state(), v => v.id === "games:chomp");
    tool("close");
    return { pass: ready.includes("lives 3") && score > 0 && picker,
      note: `'${ready}' → tap, 2s → '${running}'; back shows the games: ${picker}` };
  } },
];

// g menu → Games (scrolling the grid to the tile, as a thumb would) → a game.
// --- 2026-09-28 audit: the user's own reports, on Android ---
scenarios.push(
  { id: "S164", title: "$sol shows SOL's price, never your wallet", run: async () => {
    await fresh();
    await type("$sol");
    const deadline = Date.now() + 8000;
    let label = "";
    while (Date.now() < deadline) {
      const s = await state();
      label = s.views.filter(v => v.text).map(v => v.text).find(t => /SOL =|wallet|[1-9A-HJ-NP-Za-km-z]{32,}/i.test(t)) ?? "";
      if (/SOL =/.test(label)) break;
      await sleep(400);
    }
    return { pass: /1 SOL = \$\d/.test(label), note: `strip: '${label}'` };
  } },
  { id: "S165", title: "$appl shows Apple's price as AAPL", run: async () => {
    await fresh();
    await type("$appl");
    const deadline = Date.now() + 8000;
    let label = "";
    while (Date.now() < deadline) {
      const s = await state();
      label = s.views.filter(v => v.text).map(v => v.text).find(t => /= \$/.test(t)) ?? "";
      if (label) break;
      await sleep(400);
    }
    return { pass: /1 AAPL = \$\d/.test(label), note: `strip: '${label}'` };
  } },
  { id: "S166", title: "Search never changes the keyboard's height", run: async () => {
    await fresh();
    let s = await state();
    const q0 = s.keys.q?.[1];
    if (q0 === undefined) return { pass: false, note: "no keys" };
    if (!await openTool("search")) return { pass: false, note: "no Search on the strip or in the menu" };
    const close = await waitFor(byId("search:close"), 3000);
    if (!close) return { pass: false, note: "search did not open" };
    await sleep(1500);   // the suggestions arrive
    s = await state();
    const q1 = s.keys.q?.[1];
    const row1 = find(s, v => v.id === "search:close")?.y;
    await type("coffee");
    s = await state();
    const q2 = s.keys.q?.[1];
    const go = find(s, v => v.id === "search:go");
    if (go) await tapXY(go.x, go.y);
    await waitFor(idStarts("search:card:"), 12000);
    const row3 = find(await state(), v => v.id === "search:close")?.y;
    await screenshot("S166-results");
    tool("close");
    const same = (a, b) => a !== undefined && b !== undefined && Math.abs(a - b) <= 2;
    return { pass: same(q0, q1) && same(q1, q2) && same(row1, row3),
      note: `q key y ${q0} → ${q1} → ${q2}; search row y ${row1} → ${row3} (results)` };
  } },
  { id: "S167", title: "Maps results come with a picture of each place", run: async () => {
    // "near me" needs where the phone is: the app keeps one rough fix
    // (Profile › Nearby search); the emulator has none, so it gets one here
    // and the old settings come back afterwards.
    const file = "files/bridge/settings.json";
    const before = adb("shell", `run-as ${PKG} cat ${file}`);
    const write = text => writeSettings(text);
    const had = JSON.parse(before);
    if (had.lastLat === undefined) {
      write(JSON.stringify({ ...had, lastLat: 12.9719, lastLon: 77.6412 }));
      atEnd.push(() => write(before));
    }
    await fresh();
    if (!await openTool("search")) return { pass: false, note: "no Search on the strip or in the menu" };
    const maps = await waitFor(byId("search:tab:maps"), 3000);
    if (!maps) return { pass: false, note: "no Maps tab" };
    await tapXY(maps.x, maps.y);
    await type("coffee near me");
    const go = find(await state(), v => v.id === "search:go");
    if (go) await tapXY(go.x, go.y);
    const card = await waitFor(idStarts("search:card:"), 12000);
    await sleep(3000);   // the pictures load
    await screenshot("S167-maps");
    tool("close");
    return { pass: !!card, note: card ? "place cards shown; pictures in the screenshot" : "no place cards" };
  } },
  { id: "S189", title: "Hold space on 2+5: the answer is there at once, worked out on the phone", run: async () => {
    // "i wanna do math 2+5 its taking long, we dont need ai for this" (2026-09-29).
    await fresh();
    await type("2+5");
    const s = await state();
    const t0 = Date.now();
    await hold(s.keys.space[0], s.keys.space[1], 1100);
    const insert = await waitFor(byId("act:insert"), 4000);
    const ms = Date.now() - t0;
    if (!insert) return { pass: false, note: "no answer" };
    await screenshot("S189-sum");
    const r = await tapFor(insert, x => x.includes("= 7"), 3000);
    // The hold itself is 1.1 s; the answer needs none of the network after it.
    return { pass: r.t.includes("2+5 = 7") && ms < 3500, note: `'${r.t}', answer up ${ms} ms after the hold began${second(r)}` };
  } },
  { id: "S190", title: "A correction slid away and typed again stays as typed, and is learned", run: async () => {
    // "i type cutee ... its not learning" (2026-09-29): going back into a
    // correction and typing the original again is a no, and the word is kept.
    tool("forgetword", "--es text helloo");
    await fresh();
    await type("so helloo ");
    const corrected = await text();
    if (!/so hello $/i.test(corrected)) return { pass: false, note: `expected 'helloo' corrected to 'hello', got '${corrected}'` };
    // Slide left from delete by one word (as in S97).
    const s = await state();
    const [x, y] = s.keys.delete;
    shell(`input motionevent DOWN ${x} ${y}`);
    for (let i = 1; i <= 4; i++) {
      await sleep(70);
      shell(`input motionevent MOVE ${x - i * 45} ${y}`);
    }
    await sleep(150);
    shell(`input motionevent UP ${x - 180} ${y}`);
    await sleep(800);
    const slid = await text();
    await type("helloo ");
    const kept = await text();
    await fresh();
    await type("helloo ");
    const learned = await text();
    tool("forgetword", "--es text helloo");   // the next run starts clean
    return { pass: /helloo $/i.test(kept) && /^helloo $/i.test(learned),
      note: `'${corrected}' → slid to '${slid}' → typed again '${kept}' → next time '${learned}'` };
  } },
);

// --- 2026-09-29: the g menu, My glyfs and the vault (user: "remove items in
// menu that are in top bar", "my glyfs and keys are showing same thing",
// "shorthand needs to be part of vault", "why cant we add details") ---
scenarios.push(
  { id: "S199", title: "The g menu holds only what the strip doesn't, and GIFs opens the GIF tab", run: async () => {
    await fresh();
    let s = await state();
    const strip = TOOL_IDS.filter(id => find(s, byId(id)));
    const g = find(s, byId("toolbar:glyf"));
    if (!g || !strip.length) return { pass: false, note: `no g button, or the strip shows no tools (${strip.join(", ")})` };
    await tapXY(g.x, g.y);
    await waitFor(idStarts("shell:tile:"), 3000);
    s = await state();
    const tiles = s.views.filter(v => v.id.startsWith("shell:tile:")).map(v => v.id.slice(11));
    const both = tiles.filter(t => strip.includes(t));
    const nowhere = TOOL_IDS.filter(t => !strip.includes(t) && !tiles.includes(t));
    const retired = tiles.filter(t => ["emoji", "keys", "shorthand"].includes(t));
    await screenshot("S199-menu");
    const gifs = find(s, byId("shell:tile:gifs"));
    if (!gifs) { tool("close"); return { pass: false, note: `no GIFs tile; menu: ${tiles.join(", ")}` }; }
    await tapXY(gifs.x, gifs.y);
    const tab = await waitFor(v => v.id === "emoji:mode:gifs" && v.selected, 4000);
    const media = await waitFor(idStarts("emoji:media:"), 12000);
    await screenshot("S199-gifs");
    tool("close");
    return { pass: !both.length && !nowhere.length && !retired.length && !!tab,
      note: `strip: ${strip.join(", ")}; menu: ${tiles.join(", ")}` +
        (both.length ? `; in both: ${both.join(", ")}` : "") +
        (nowhere.length ? `; in neither: ${nowhere.join(", ")}` : "") +
        (retired.length ? `; retired tiles: ${retired.join(", ")}` : "") +
        `; GIFs opens ${tab ? "the GIF tab" : "something else"}${media ? " with GIFs" : " (none loaded)"}` };
  } },
  { id: "S200", title: "My glyfs shows what each key holds, and there is no Keys tile", run: async () => {
    // A glyf built in the app and on no key, listed after the keys; the
    // settings come back as they were afterwards.
    const before = readSettings();
    const had = JSON.parse(before);
    writeSettings(JSON.stringify({ ...had, customTitles: { ...(had.customTitles || {}), "user.qa-unbound": "QA glyf" } }));
    try {
      await sleep(1000);   // the keyboard looks at its settings every 0.4 s
      await fresh();
      let s = await state();
      const g = find(s, byId("toolbar:glyf"));
      if (!g) return { pass: false, note: "no g button" };
      await tapXY(g.x, g.y);
      const tile = await waitFor(byId("shell:tile:glyfs"), 3000);
      s = await state();
      const keysTile = !!find(s, byId("shell:tile:keys"));
      if (!tile) return { pass: false, note: "no My glyfs tile" };
      await tapXY(tile.x, tile.y);
      await waitFor(byId("glyfs:build"), 3000);
      s = await state();
      await screenshot("S200-my-glyfs");
      const bindings = had.bindings || {};
      const letters = "qwertyuiopasdfghjklzxcvbnm".split("").filter(l => bindings[l]);
      // Each key's row says which letter to hold.
      const holds = letters.filter(l => {
        const card = find(s, byId(`glyfs:key:${l}`));
        return card && s.views.some(v => v.text === `Hold ${l.toUpperCase()}` && Math.abs(v.y - card.y) < card.h / 2);
      });
      const y = id => find(s, byId(id))?.y ?? -1;
      const keyYs = letters.map(l => y(`glyfs:key:${l}`));
      const own = cardOf(s, "glyfs:own:", "QA glyf");
      const ordered = own && Math.max(...keyYs) < own.y && own.y < y("glyfs:build");
      // A tap does what holding the key does: the vault's letter opens the vault.
      const vaultKey = letters.find(l => bindings[l] === "surface:vault");
      let opened = "no key holds the vault";
      if (vaultKey) {
        const row = await inView(`glyfs:key:${vaultKey}`);
        if (row) await tapXY(row.x, row.y);
        opened = (await waitFor(byId("vault:add"), 3000)) ? "the vault" : "nothing";
      }
      tool("close");
      return { pass: !keysTile && letters.length > 0 && holds.length === letters.length && !!ordered &&
          (!vaultKey || opened === "the vault"),
        note: `keys held: ${letters.map(l => `${l.toUpperCase()}=${bindings[l]}`).join(", ")}; rows with Hold X: ` +
          `${holds.map(l => l.toUpperCase()).join(", ")}; unbound glyf after them: ${!!ordered}; ` +
          `Keys tile: ${keysTile}; tapping Hold ${(vaultKey || "?").toUpperCase()} opened ${opened}` };
    } finally {
      writeSettings(before);
      await sleep(600);
    }
  } },
  { id: "S201", title: "The vault shows shorthand, and an email added from the keys is offered for 'my email is'", run: async () => {
    const email = "qa.keys@example.com";
    tool("snippet", "--es text ';qapanel=Shorthand from the vault'");
    // The email added here has to be the only one: any saved already is set
    // aside (kept in the vault, marked) and put back at the end.
    tool("stash", "--es text email");
    tool("dropdetail", `--es text ${email}`);
    try {
      await fresh();
      if (!await openTool("vault")) return { pass: false, note: "no Vault on the strip or in the menu" };
      await waitFor(byId("vault:add"), 3000);
      let s = await state();
      const short = cardOf(s, "vault:shorthand:", ";qapanel");
      if (!short) return { pass: false, note: "no shorthand in the vault panel" };
      // Details first, then shorthand, then notes, in reading order (the
      // vault is three cards to a row).
      const ps = p => s.views.filter(idStarts(p)).map(readingPos);
      const between = Math.max(-1, ...ps("vault:card:")) < readingPos(short) &&
        readingPos(short) < Math.min(Infinity, ...ps("vault:note:"));
      await screenshot("S201-vault");
      const row = await inView(short.id);
      const typed = row ? await tapFor(row, x => x.includes("Shorthand from the vault")) : { t: "" };
      // New detail → Email, through the "+": what it adds stays hidden until
      // it is tapped, and the × or a tap on the cards behind puts it away.
      await fresh();
      await openTool("vault");
      const plus = await waitFor(byId("vault:add"), 3000);
      if (!plus) return { pass: false, note: "no + in the vault panel" };
      const hiddenFirst = !(await state()).views.some(idStarts("vault:new:"));
      await tapXY(plus.x, plus.y);
      await waitFor(byId("vault:new:shorthand"), 3000);
      s = await state();
      const shown = s.views.filter(idStarts("vault:new:")).map(v => v.text);
      const asClose = find(s, byId("vault:add"))?.desc === "Close";
      await screenshot("S201-plus-open");
      const away = async () => { await sleep(500); return !(await state()).views.some(idStarts("vault:new:")); };
      await tapXY(plus.x, plus.y);
      const byX = await away();
      await tapXY(plus.x, plus.y);
      const dim = await waitFor(byId("vault:add:dim"), 3000);
      // Left of the options, on the cards.
      if (dim) await tapXY(dim.x - Math.round(dim.w / 4), dim.y);
      const byCards = await away();
      const plusOk = hiddenFirst && shown.join(", ") === "New note, New detail, New shorthand" && asClose && byX && byCards;
      const add = await vaultAdd("detail");
      if (!add) return { pass: false, note: "the + offers no New detail" };
      await tapXY(add.x, add.y);
      const kind = await waitFor(byId("vault:kind:email"), 3000);
      if (!kind) return { pass: false, note: "New detail offers no Email" };
      const kinds = (await state()).views.filter(idStarts("vault:kind:")).map(v => v.text);
      await tapXY(kind.x, kind.y);
      if (!await waitFor(byId("vaultedit:field"), 3000)) return { pass: false, note: "no strip to type the email in" };
      await type(email);
      const field = find(await state(), byId("vaultedit:field"))?.text;
      await screenshot("S201-detail-strip");
      const save = find(await state(), byId("vaultedit:save"));
      await tapXY(save.x, save.y);
      await waitFor(byId("vault:add"), 3000);
      await sleep(400);   // the panel scrolls to what was just saved
      const saved = cardOf(await state(), "vault:card:", email);
      const screenH = Number(shell("wm size").match(/(\d+)x(\d+)/)[2]);
      const inSight = !!saved && saved.y + saved.h / 2 < screenH - 180;
      await screenshot("S201-saved");
      // At once: the strip offers it for "my email is".
      tool("close");
      await fresh();
      await type("sure my email is ");
      const chip = await waitFor(byId("strip:smart"), 4000);
      const offered = !!find(await state(), v => v.text === email);
      await screenshot("S201-chip");
      // Your email sits beside Temp mail (2026-10-01): tap the email itself.
      const r = chip ? await tapFor(firstValue(await state(), chip), x => x.includes(email))
        : { t: await text(), retried: false };
      return { pass: !!short && between && typed.t.includes("Shorthand from the vault") && plusOk && field === email &&
          inSight && offered && r.t.trim().toLowerCase() === `sure my email is ${email}`,
        note: `shorthand card between details and notes: ${between}; tapped it: '${typed.t}'; ` +
          `+: hidden until tapped ${hiddenFirst}, then '${shown.join(", ")}' with the + as ${asClose ? "Close" : "?"}, ` +
          `put away by the × ${byX} and by the cards ${byCards}; ` +
          `kinds: ${kinds.join(", ")}; strip read '${field}'; saved card: ${saved ? (inSight ? "in view" : "below the fold") : "missing"}; ` +
          `chip offered it: ${offered}; '${r.t}'${second(r)}` };
    } finally {
      tool("close");
      tool("dropdetail", `--es text ${email}`);
      tool("unstash");
      tool("snippet", "--es text ';qapanel='");
      await sleep(500);
    }
  } },
  { id: "S202", title: "A shorthand added from the keys expands when typed", run: async () => {
    tool("snippet", "--es text ';qazz='");   // starts clean
    try {
      await fresh();
      if (!await openTool("vault")) return { pass: false, note: "no Vault on the strip or in the menu" };
      const add = await vaultAdd("shorthand");
      if (!add) return { pass: false, note: "the vault's + offers no New shorthand" };
      await tapXY(add.x, add.y);
      // iOS's strip: the shortcut and what it types out side by side, the
      // shortcut first; return goes on to the second.
      const first = await waitFor(byId("vaultedit:shortcut"), 3000);
      if (!first) return { pass: false, note: "no strip to type the shortcut in" };
      const start = first.text;           // the ; is there already
      await type("qazz\n");
      const shortcut = find(await state(), byId("vaultedit:shortcut"));
      await type("see you soon");
      await screenshot("S202-expansion-strip");
      const save = find(await state(), byId("vaultedit:save"));
      await tapXY(save.x, save.y);
      await waitFor(byId("vault:add"), 3000);
      const card = cardOf(await state(), "vault:shorthand:", ";qazz");
      tool("close");
      await fresh();
      await type("ok ;qazz ");
      const t = await waitText(x => /see you soon/i.test(x), 3000);
      return { pass: start === ";" && shortcut.text === ";qazz" && !!card && /^ok see you soon $/i.test(t),
        note: `strip started '${start}', shortcut '${shortcut.text}', card in the vault: ${!!card}; typed 'ok ;qazz ' → '${t}'` };
    } finally {
      tool("close");
      tool("snippet", "--es text ';qazz='");
      await sleep(500);
    }
  } },
  // What a chip says: its own text, or the text views drawn inside it (the
  // smart chip is a row holding a label).
  { id: "S209", title: "A sum shows its answer in the strip as it is typed, no hold", run: async () => {
    // "why am i needing to hold space, suggest it in strip right" (2026-09-29).
    const seen = [];
    let ok = true;
    // Every operator on the keys (Arpit, 2026-09-29: "not working on 2-3 ... all maths symbols").
    for (const [typed, shown] of [["2+5", "2+5 = 7"], ["12*12", "12*12 = 144"], ["100-15%", "100-15% = 85"],
      ["150-45", "150-45 = 105"], ["24/7", "24/7 = 3.43"], ["2-3", "2-3 = -1"], ["2x3", "2x3 = 6"], ["5>3", "5>3 = true"]]) {
      await fresh();
      await type(typed);
      const chip = await waitFor(byId("strip:smart"), 3000);
      const label = chip ? chipLabel(await state(), chip) : "none";
      seen.push(`${typed} → ${label}`);
      if (!label.includes(shown)) ok = false;
    }
    await screenshot("S209-sum");
    return { pass: ok, note: seen.join("; ") };
  } },
  { id: "S210", title: "A phone number, a date or a count shows no sum", run: async () => {
    const seen = [];
    let ok = true;
    for (const typed of ["call me at 555-1234", "born 29/09/2024", "page 2 of 10"]) {
      await fresh();
      await type(typed);
      await sleep(900);
      const s = await state();
      const chip = find(s, byId("strip:smart"));
      const label = chip ? chipLabel(s, chip) : "";
      seen.push(`${typed} → ${chip ? label || "(a chip with no label)" : "no chip"}`);
      if (chip && (/=/.test(label) || !label)) ok = false;
    }
    return { pass: ok, note: seen.join("; ") };
  } },
  { id: "S213", title: "A question offers AI answer in the strip, and a tap answers it", run: async () => {
    // "have a strip like ai answer ? on all questions type" (2026-09-29).
    await fresh();
    await type("what is polynomial");
    const chip = await waitFor(byId("strip:smart"), 8000);
    const label = chip ? chipLabel(await state(), chip) : "none";
    if (!chip || !label.includes("AI answer")) return { pass: false, note: `strip shows '${label}'` };
    await screenshot("S213-chip");
    await tapXY(chip.x, chip.y);
    const insert = await waitFor(byId("act:insert"), 15000);
    if (!insert) return { pass: false, note: `chip '${label}', no answer after the tap` };
    await screenshot("S213-answer");
    const r = await tapFor(insert, x => /polynomial/i.test(x) && x.length > 30, 4000);
    return { pass: /polynomial/i.test(r.t) && r.t.length > 30, note: `chip '${label}' → '${r.t.slice(0, 120)}'${second(r)}` };
  } },
);

// --- 2026-09-30: a ✕ on every strip chip ---
scenarios.push(
  { id: "S215", title: "A chip's ✕ waves it off for those words, a new sum brings one back, and Insert never dismisses", run: async () => {
    // "we should add some button to dismiss it, like a cross on left or something, figure out" (2026-09-30).
    await fresh();
    await type("2+5");
    const chip = await waitFor(byId("strip:smart"), 3000);
    if (!chip) return { pass: false, note: "no chip for 2+5" };
    let s = await state();
    const close = find(s, byId("strip:smart:close"));
    if (!close) return { pass: false, note: `the chip '${chipLabel(s, chip)}' has no ✕` };
    const target = `${close.w}x${close.h}`;
    await screenshot("S215-chip");
    await tapXY(close.x, close.y);
    await sleep(1200);   // past a pass of the strip, which must not bring it back
    s = await state();
    const gone = !find(s, byId("strip:smart"));
    // Back to what the strip shows without a chip: the tools, or words.
    const strip = TOOL_IDS.some(id => find(s, byId(id))) ? "tools" : s.views.some(idStarts("suggest:")) ? "words" : "nothing";
    const kept = s.text;
    // More of the sum is a new sum: its chip comes.
    await type("0");
    const again = await waitFor(byId("strip:smart"), 3000);
    const label = again ? chipLabel(await state(), again) : "none";
    // Insert, pressed on the word itself beside the ✕, inserts; it never dismisses.
    const verb = again && find(await state(), v => v.text === "Insert" &&
      Math.abs(v.y - again.y) < again.h / 2 && Math.abs(v.x - again.x) < again.w / 2);
    const r = verb ? await tapFor({ ...verb, id: "" }, x => x.includes("= 52"))
      : { t: await text(), retried: false };
    return { pass: gone && strip !== "nothing" && kept === "2+5" && label.includes("2+50 = 52") && r.t.includes("2+50 = 52"),
      note: `✕ ${target}px; after it: chip gone ${gone}, strip shows ${strip}, text '${kept}'; typed 0 → '${label}'; Insert → '${r.t}'${second(r)}` };
  } },
);

// --- 2026-09-30: temp mail in the keyboard, on mail.tm, against a stand-in ---
// The keyboard calls mail.tm itself (shared/tempmail/RULES.md). Start
// qa/fake-mailtm.mjs (8798); the run points the keyboard at it with the
// setting tempMailBase (the emulator reaches the Mac on 10.0.2.2) and puts the
// setting back at the end. S217 and S218 use the address S216 made when it is
// there, and S218 deletes it.
const FAKE_TEMPMAIL = "http://127.0.0.1:8798";

// The keyboard pointed at the stand-in for this run (once), and back after.
let fakeMailTmOn = false;
async function useFakeMailTm() {
  if (fakeMailTmOn) return;
  const before = readSettings();
  writeSettings(JSON.stringify({ ...JSON.parse(before), tempMailBase: "http://10.0.2.2:8798" }));
  atEnd.push(() => {
    const now = JSON.parse(readSettings());
    const had = JSON.parse(before);
    if (had.tempMailBase === undefined) delete now.tempMailBase; else now.tempMailBase = had.tempMailBase;
    writeSettings(JSON.stringify(now));
  });
  fakeMailTmOn = true;
  await sleep(900);   // the keyboard looks at its settings every 0.4 s
}

// Since 2026-10-14 the keyboard calls Cal.com itself (CalBooking.kt), so the
// stand-in Cal.com is named in the setting calcomBase for the run, and put
// back after, the way tempMailBase is.
let fakeCalcomOn = false;
async function useFakeCalcom() {
  if (fakeCalcomOn) return;
  const before = readSettings();
  writeSettings(JSON.stringify({ ...JSON.parse(before), calcomBase: "http://10.0.2.2:8796/v2" }));
  atEnd.push(() => {
    const now = JSON.parse(readSettings());
    const had = JSON.parse(before);
    if (had.calcomBase === undefined) delete now.calcomBase; else now.calcomBase = had.calcomBase;
    writeSettings(JSON.stringify(now));
  });
  fakeCalcomOn = true;
  await sleep(900);   // the keyboard looks at its settings every 0.4 s
}

// The Temp mail panel's address, made if there is none; the panel is left open.
async function tempAddress() {
  await useFakeMailTm();
  await fresh();
  tool("tempmail");
  let addr = await waitFor(byId("tempmail:address"), 3000);
  if (!addr) {
    const create = await waitFor(byId("tempmail:create"), 3000);
    if (!create) return null;
    await tapXY(create.x, create.y);
    addr = await waitFor(byId("tempmail:address"), 12000);
  }
  return addr?.text ?? null;
}

// A mail into the stand-in's inbox for [email] (the server reads its code).
async function injectMail(email, subject, text) {
  const r = await fetch(`${FAKE_TEMPMAIL}/_inject`, { method: "POST", body: JSON.stringify({ email, subject, text }) });
  return r.ok;
}

// The strip's chip once its words hold [part], or null.
async function chipWith(part, ms) {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    const s = await state();
    const chip = find(s, byId("strip:smart"));
    if (chip && chipLabel(s, chip).includes(part)) return { chip, label: chipLabel(s, chip) };
    await sleep(500);
  }
  return null;
}

scenarios.push(
  { id: "S216", title: "Temp mail: the g menu makes an address, and Insert types it", run: async () => {
    // "option to enter temporary mail ... so user can get temporary mails directly inside their keyboards" (2026-09-30).
    await useFakeMailTm();
    tool("tempmailclear");   // this one makes the address
    await fresh();
    const g = find(await state(), byId("toolbar:glyf"));
    if (!g) return { pass: false, note: "no g button" };
    await tapXY(g.x, g.y);
    const tile = await waitFor(byId("menu:tempmail"), 3000);
    if (!tile) return { pass: false, note: "no Temp mail in the g menu" };
    await tapXY(tile.x, tile.y);
    const create = await waitFor(byId("tempmail:create"), 3000);
    if (!create) return { pass: false, note: "the panel offers no Create address" };
    await screenshot("S216-empty");
    await tapXY(create.x, create.y);
    const addr = await waitFor(byId("tempmail:address"), 12000);
    if (!addr) return { pass: false, note: `no address came (notice '${(await state()).notice}')` };
    const watching = find(await state(), byId("tempmail:watching"))?.text ?? "";
    const credit = find(await state(), byId("tempmail:credit"))?.text ?? "";
    await screenshot("S216-address");
    const insert = find(await state(), byId("tempmail:insert"));
    // The panel stays after Insert (2026-10-01), so a retried tap would type
    // it twice: the check is for this address, whichever domain it is on.
    const r = await tapFor(insert, x => x.includes(addr.text));
    return { pass: /^[a-z]+[0-9a-f]{6}@glyf-temp\.example$/.test(addr.text) && r.t.trim() === addr.text &&
        /^Watching · 1[45]:\d\d left$/.test(watching) && credit === "via mail.tm",
      note: `address made, '${watching}', '${credit}'; Insert typed '${r.t}'${second(r)}` };
  } },
  { id: "S217", title: "Temp mail: a code that arrives shows on the strip, and Insert types just the code", run: async () => {
    const address = await tempAddress();
    if (!address) return { pass: false, note: `no address (notice '${(await state()).notice}')` };
    await fresh();   // the panel closed: a new mail comes to the strip
    if (!await injectMail(address, "Your Acme code", "Your verification code is 482913.")) {
      return { pass: false, note: "the stand-in took no mail (is qa/fake-tempmail.mjs running?)" };
    }
    const t0 = Date.now();
    const got = await chipWith("482913", 16000);
    const secs = ((Date.now() - t0) / 1000).toFixed(1);
    if (!got) return { pass: false, note: `no code on the strip after ${secs}s` };
    await screenshot("S217-code-chip");
    const r = await tapFor(got.chip, x => x.includes("482913"));
    return { pass: got.label.includes("482913 · Acme") && r.t === "482913" && Number(secs) <= 12,
      note: `strip '${got.label}' after ${secs}s; Insert typed '${r.t}'${second(r)}` };
  } },
  { id: "S218", title: "Temp mail: the inbox lists the mail, opening it shows its text and code, and Delete ends the address", run: async () => {
    const address = await tempAddress();
    if (!address) return { pass: false, note: `no address (notice '${(await state()).notice}')` };
    const had = find(await state(), byId("tempmail:row:0"));
    if (!had) await injectMail(address, "Your Acme code", "Your verification code is 482913.");
    const row = await waitFor(byId("tempmail:row:0"), 14000);
    if (!row) return { pass: false, note: "the inbox shows no mail" };
    let s = await state();
    const rowWords = s.views.filter(v => v.text && Math.abs(v.y - row.y) < row.h / 2).map(v => v.text).join(" | ");
    const pill = find(s, byId("tempmail:rowcode:0"));
    await screenshot("S218-inbox");
    await tapXY(row.x, row.y - Math.round(row.h / 4));   // the row, above its code pill
    const code = await waitFor(byId("tempmail:code"), 3000);
    s = await state();
    const body = find(s, byId("tempmail:text"))?.text ?? "";
    await screenshot("S218-mail");
    const back = find(s, byId("panel:back"));
    if (back) await tapXY(back.x, back.y);
    const del = await waitFor(byId("tempmail:delete"), 3000);
    if (del) await tapXY(del.x, del.y);
    const ended = await waitFor(byId("tempmail:create"), 4000);
    tool("close");
    return { pass: /Acme/.test(rowWords) && /482913/.test(pill?.text ?? "") && code?.text === "482913" &&
        body.includes("verification code is 482913") && !!ended,
      note: `row '${rowWords}', pill '${pill?.text ?? "none"}'; opened: code '${code?.text ?? "none"}', text '${body.slice(0, 60)}'; after Delete: ${ended ? "Create address" : "still an address"}` };
  } },
);

// --- 2026-10-01: every saved email, Temp mail beside them, Insert stays, events carry their call link ---
// "when i type email it should show my email id from vault / and if i added 2
// mail ids i should see both / and i should also see a temp mail option /
// when i click insert in temp mail i should not redirect back to keyboard,
// should stay here / also creating a calendar event should also send its
// meeting link in chat with calendar details"
scenarios.push(
  { id: "S219", title: "Two saved emails: typing email shows both and Temp mail, and a tap types the one tapped", run: async () => {
    const first = "qa.work@example.com";
    const other = "qa.home@example.com";
    // These two must be the only emails: any saved already is set aside
    // (kept in the vault, marked) and put back at the end.
    tool("stash", "--es text email");
    tool("adddetail", `--es text 'email|QA Work|${first}'`);
    tool("adddetail", `--es text 'email|QA Home|${other}'`);
    try {
      await fresh();
      await type("email");
      const chip = await waitFor(byId("strip:smart:choice:1"), 4000);
      let s = await state();
      const card = find(s, byId("strip:smart"));
      if (!chip || !card) return { pass: false, note: `no details chip; strip shows '${card ? chipLabel(s, card) : "nothing"}'` };
      const close = find(s, byId("strip:smart:close"));
      const parts = ["strip:smart:choice:0", "strip:smart:choice:1", "strip:smart:choice:temp"].map(id => find(s, byId(id)));
      const [p0, p1, temp] = parts;
      const words = v => v ? chipLabel(s, v).trim() : "";
      // A row of chips (2026-10-01: "it should be 2-3 diff strips not all in
      // one strip"): the ✕ first, then a chip for each email and one for Temp
      // (an envelope and its word), apart from each other and level with
      // Glyf's key.
      const ordered = !!close && parts.every(Boolean) && close.x < p0.x && p0.x < p1.x && p1.x < temp.x;
      const gaps = parts.every(Boolean) ? [p1.x - p1.w / 2 - (p0.x + p0.w / 2), temp.x - temp.w / 2 - (p1.x + p1.w / 2)] : [];
      const apart = gaps.length === 2 && gaps.every(g => g >= 20);
      const g = find(s, byId("toolbar:glyf"));
      const level = !!g && parts.every(v => v && Math.abs(v.y - g.y) <= 3);
      const widths = parts.filter(Boolean).map(v => v.w);
      const noVerb = !s.views.some(v => v.text === "Insert" && Math.abs(v.y - card.y) < card.h / 2);
      await screenshot("S219-chip");
      const r = await tapFor(p1, x => x.includes(other));
      return { pass: words(p0) === first && words(p1) === other && words(temp) === "Temp" && temp?.desc === "Temp mail" &&
          ordered && apart && level && noVerb && r.t.trim().toLowerCase() === `email ${other}`,
        note: `chips '${words(p0)}' | '${words(p1)}' | '${words(temp)}' (${temp?.desc}); widths ${widths.join("/")}px, ` +
          `gaps ${gaps.join("/")}px, ✕ first ${ordered}, level with g ${level}, no Insert ${noVerb}; ` +
          `tapped the second: '${r.t}'${second(r)}` };
    } finally {
      tool("dropdetail", `--es text ${first}`);
      tool("dropdetail", `--es text ${other}`);
      tool("unstash");
      await sleep(500);
    }
  } },
  { id: "S220", title: "Temp mail: every Insert types into the message and the panel stays open", run: async () => {
    await useFakeMailTm();
    tool("tempmailclear");   // a new address, with an empty inbox
    try {
      const address = await tempAddress();
      if (!address) return { pass: false, note: `no address (notice '${(await state()).notice}')` };
      const seen = [];
      // Taps an Insert and watches from that moment (the notice lasts 2.4 s,
      // about two dumps on a busy Mac): the message becomes [want], "Added to
      // the message" shows, and the panel ([id]) is still open. A second tap
      // only when the first changed nothing: one more on a panel that stays
      // would type it twice.
      const insertStays = async (what, view, want, id) => {
        const was = (await state()).text;
        await tapXY(view.x, view.y);
        let s = null, noticed = false, again = false;
        const start = Date.now();
        while (Date.now() - start < 7000) {
          s = await state();
          noticed ||= s.notice === "Added to the message";
          if (s.text === want && noticed) break;
          if (!again && s.text === was && Date.now() - start > 2500) {
            again = true;
            await tapXY(view.x, view.y);
          }
          await sleep(150);
        }
        const open = !!find(s, byId(id));
        const ok = s.text === want && noticed && open;
        seen.push(`${what}: ${s.text === want ? "typed" : "not typed"}, notice ${noticed ? "seen" : "not seen"}, ` +
          `panel ${open ? "open" : "closed"}${again ? " (took a second tap)" : ""}`);
        return ok;
      };
      // The address.
      const insert = await waitFor(byId("tempmail:insert"), 3000);
      const addressOk = await insertStays("address", insert, address, "tempmail:address");
      await screenshot("S220-after-insert");
      // A mail with a code and a link: the code pill in the inbox.
      if (!await injectMail(address, "Confirm your Acme account",
          "Your verification code is 482913. Or confirm here: https://acme.example/verify?t=qa220")) {
        return { pass: false, note: "the stand-in took no mail (is qa/fake-mailtm.mjs running?)" };
      }
      const pill = await waitFor(byId("tempmail:rowcode:0"), 16000);
      if (!pill) return { pass: false, note: `no mail in the inbox; ${seen.join("; ")}` };
      const pillOk = await insertStays("inbox code", pill, `${address}482913`, "tempmail:row:0");
      // The mail opened: its code's Insert, then Insert link.
      const row = find(await state(), byId("tempmail:row:0"));
      await tapXY(row.x, row.y - Math.round(row.h / 4));   // the row, above its code pill
      const codeInsert = await waitFor(byId("tempmail:code:insert"), 3000);
      if (!codeInsert) return { pass: false, note: `the mail didn't open; ${seen.join("; ")}` };
      const codeOk = await insertStays("code", codeInsert, `${address}482913482913`, "tempmail:code");
      const link = await waitFor(byId("tempmail:link"), 2000);
      const linkOk = !!link && await insertStays("link", link,
        `${address}482913482913https://acme.example/verify?t=qa220`, "tempmail:code");
      await screenshot("S220-mail-open");
      return { pass: addressOk && pillOk && codeOk && linkOk,
        note: `${seen.join("; ")}; message '${await text()}'` };
    } finally {
      tool("close");
      tool("tempmailclear");
    }
  } },
  { id: "S221", title: "New Event with Google Meet connected puts the event and its call link in the message", run: async () => {
    await fetch(`${FAKE_GOOGLE}/_reset`);
    await calendarOn();
    const notes = [];
    let ok = true;
    // With Google Calendar and Meet the event goes to Google, which makes the
    // call; with Meet alone it goes to the phone's calendar with a Meet link.
    // Either way nothing is turned on by hand.
    for (const [scopes, title] of [["", "Sync with ria"], ["meet", "Catch up with sam"]]) {
      tool("googlefake", `--es text ${FAKE_GOOGLE_FOR_PHONE}${scopes ? ` --es scopes ${scopes}` : ""}`);
      try {
        await fresh();
        tool("calendar");
        const plus = await waitFor(byId("calendar:new"), 4000);
        if (!plus) return { pass: false, note: "no + on the calendar" };
        const titleRow = await tapOpen(plus, byId("event:title"));
        if (!titleRow) return { pass: false, note: "New Event didn't open" };
        if (!(await tapOpen(titleRow, byId("event:title:field")))) return { pass: false, note: "no title strip" };
        await type(`${title.toLowerCase()} friday 4pm`);
        await key("return");
        const video = await rowInView("event:video");
        const share = await waitFor(byId("event:share"), 1500);
        const add = await waitFor(byId("event:add"), 3000);
        if (!add) return { pass: false, note: "no Add" };
        const before = (await (await fetch(`${FAKE_GOOGLE}/_log`)).json());
        const r = await tapFor(add, x => x.includes(`📅 ${title}`) && x.includes("https://meet.google.com/"), 10000);
        const log = await (await fetch(`${FAKE_GOOGLE}/_log`)).json();
        const viaGoogle = !scopes ? !!log.events.at(-1)?.body?.conferenceData?.createRequest
          : log.spaces.length > before.spaces.length && log.events.length === before.events.length;
        const shape = new RegExp(`^📅 ${title} · .*4:00.* · https://meet\\.google\\.com/\\S+$`).test(r.t);
        if (scopes === "" ) await screenshot("S221-message");
        const pass = video?.selected === true && share?.selected === true && shape && viaGoogle;
        if (!pass) ok = false;
        notes.push(`${scopes || "calendar+meet"}: Video call ${video ? (video.selected ? "on" : "off") : "missing"}, ` +
          `Share in chat ${share ? (share.selected ? "on" : "off") : "missing"}, ${viaGoogle ? "link made" : "no link made"}; '${r.t}'${second(r)}`);
      } finally {
        tool("googlefake");
      }
    }
    return { pass: ok, note: notes.join("; ") };
  } },
);

scenarios.push(
  { id: "S222", title: "A measurement shows in the other system, one chip each, and a tap adds it in brackets", run: async () => {
    await fresh();
    await type("lets 10 inch");
    const chip = await waitFor(byId("strip:smart:choice:1"), 4000);
    const s = await state();
    const parts = ["strip:smart:choice:0", "strip:smart:choice:1"].map(id => find(s, byId(id)));
    const words = parts.map(v => v ? chipLabel(s, v).trim() : "");
    await screenshot("S222-chip");
    if (!chip || !parts[0]) return { pass: false, note: `no unit chips; strip shows '${words.join(" | ")}'` };
    const r = await tapFor(parts[0], x => x.includes("("));
    return { pass: words[0] === "25.4 cm" && words[1] === "0.254 m" && r.t.trim().toLowerCase() === "lets 10 inch (25.4 cm)",
      note: `chips '${words[0]}' | '${words[1]}'; tapped the first: '${r.t}'${second(r)}` };
  } },
  { id: "S223", title: "A bill split shows what each pays", run: async () => {
    await fresh();
    await type("split 120 4 ways");
    const chip = await waitFor(byId("strip:smart:choice:0"), 4000);
    const s = await state();
    const word = chip ? chipLabel(s, find(s, byId("strip:smart:choice:0"))).trim() : "";
    await screenshot("S223-chip");
    return { pass: word === "30 each", note: `chip '${word}'` };
  } },
  { id: "S224", title: "A ;date shortcut is replaced by the date", run: async () => {
    await fresh();
    await type("today is ;date");
    const chip = await waitFor(byId("strip:smart:choice:0"), 4000);
    if (!chip) return { pass: false, note: "no date chip" };
    const s = await state();
    const word = chipLabel(s, find(s, byId("strip:smart:choice:0"))).trim();
    const r = await tapFor(find(s, byId("strip:smart:choice:0")), x => !x.includes(";date"));
    const ok = /^\w{3}(,)? /.test(word) && r.t.trim().toLowerCase() === `today is ${word}`.toLowerCase();
    return { pass: ok, note: `chip '${word}'; tapped: '${r.t}'${second(r)}` };
  } },
  { id: "S225", title: "Style in the g menu: Bold restyles the message", run: async () => {
    await fresh();
    await type("hello world");
    // Style is new: a menu order saved before it puts it last, below the
    // fold of the grid, so the grid is swiped up until its tile shows.
    let s = await state();
    const g = find(s, byId("toolbar:glyf"));
    if (!g) return { pass: false, note: "no g key" };
    // The first tap after typing can be dropped: tap g until the grid shows.
    for (let i = 0; i < 3; i++) {
      await tapXY(g.x, g.y);
      if (await waitFor(v => (v.id || "").startsWith("shell:tile:"), 2500)) break;
    }
    const screenH = Number(shell("wm size").match(/(\d+)x(\d+)/)[2]);
    let opened = false;
    for (let i = 0; i < 6 && !opened; i++) {
      s = await state();
      const tile = find(s, byId("shell:tile:style"));
      if (tile && tile.y + tile.h / 2 < screenH - 170) { await tapXY(tile.x, tile.y); opened = true; break; }
      shell(`input swipe ${g.x + 200} ${screenH - 300} ${g.x + 200} ${screenH - 700} 300`);
      await sleep(600);
    }
    if (!opened) return { pass: false, note: "no Style tile in the menu" };
    const bold = await waitFor(byId("shell:style:bold"), 4000);
    await screenshot("S225-panel");
    if (!bold) return { pass: false, note: "no Bold row" };
    const r = await tapFor(bold, x => x.includes("\u{1D5F9}"));
    const want = "\u{1D5DB}\u{1D5F2}\u{1D5F9}\u{1D5F9}\u{1D5FC} \u{1D604}\u{1D5FC}\u{1D5FF}\u{1D5F9}\u{1D5F1}";
    const lower = "\u{1D5F5}\u{1D5F2}\u{1D5F9}\u{1D5F9}\u{1D5FC} \u{1D604}\u{1D5FC}\u{1D5FF}\u{1D5F9}\u{1D5F1}";
    return { pass: r.t.trim() === want || r.t.trim() === lower, note: `after Bold: '${r.t}'${second(r)}` };
  } },
);

// --- What launchers work out (Arpit, 2026-10-03: "find more things from raycast etc too") ---
scenarios.push(
  { id: "S226", title: "A link loses its trackers in one tap", run: async () => {
    await fresh();
    // Committed straight into the field, as S120's link: autocorrect would
    // split a link typed key by key. `input text` drops a key now and then.
    const want = "check https://youtu.be/abc123?si=xyz789";
    let typed = "";
    for (let i = 0; i < 4 && typed !== want; i++) {
      if (i > 0) { tool("clear"); await sleep(500); }
      shell("input text 'check%shttps://youtu.be/abc123?si=xyz789'");
      typed = await waitText(x => x === want, 3000);
    }
    if (typed !== want) return { pass: false, note: `the link never arrived whole: '${typed}'` };
    const chip = await waitFor(byId("strip:smart:choice:0"), 5000);
    const s = await state();
    const word = chip ? chipLabel(s, find(s, byId("strip:smart:choice:0"))).trim() : "";
    await screenshot("S226-chip");
    if (word !== "Remove tracking") return { pass: false, note: `chip '${word}'` };
    const r = await tapFor(find(s, byId("strip:smart:choice:0")), x => !x.includes("si="));
    return { pass: r.t.trim() === "check https://youtu.be/abc123", note: `chip '${word}'; tapped: '${r.t}'${second(r)}` };
  } },
  { id: "S227", title: "A face by its name: /shrug", run: async () => {
    await fresh();
    await type("ok /shrug");
    const chip = await waitFor(byId("strip:smart:choice:0"), 4000);
    if (!chip) return { pass: false, note: "no face chip" };
    const s = await state();
    const word = chipLabel(s, find(s, byId("strip:smart:choice:0"))).trim();
    const r = await tapFor(find(s, byId("strip:smart:choice:0")), x => x.includes("ツ"));
    return { pass: word === "¯\\_(ツ)_/¯" && r.t.trim().toLowerCase() === "ok ¯\\_(ツ)_/¯",
      note: `chip '${word}'; tapped: '${r.t}'${second(r)}` };
  } },
  { id: "S228", title: "Cups of flour in grams", run: async () => {
    await fresh();
    await type("2 cups flour");
    const chip = await waitFor(byId("strip:smart:choice:1"), 4000);
    const s = await state();
    const parts = ["strip:smart:choice:0", "strip:smart:choice:1"].map(id => find(s, byId(id)));
    const words = parts.map(v => v ? chipLabel(s, v).trim() : "");
    await screenshot("S228-chip");
    if (!chip || !parts[0]) return { pass: false, note: `no weight chips; strip shows '${words.join(" | ")}'` };
    const r = await tapFor(parts[0], x => x.includes("("));
    return { pass: words[0] === "240 g" && words[1] === "8.47 oz" && r.t.trim().toLowerCase() === "2 cups flour (240 g)",
      note: `chips '${words[0]}' | '${words[1]}'; tapped the first: '${r.t}'${second(r)}` };
  } },
  { id: "S229", title: "A shift on the clock, worked out", run: async () => {
    await fresh();
    await type("shift 9:30-5:15");
    const chip = await waitFor(byId("strip:smart:choice:0"), 4000);
    const s = await state();
    const word = chip ? chipLabel(s, find(s, byId("strip:smart:choice:0"))).trim() : "";
    return { pass: word === "7 h 45 min", note: `chip '${word}' for '${s.text}'` };
  } },
  { id: "S230", title: "A coin flipped from the strip", run: async () => {
    await fresh();
    await type("flip a coin");
    const chip = await waitFor(byId("strip:smart:choice:0"), 4000);
    if (!chip) return { pass: false, note: "no coin chip" };
    const s = await state();
    const word = chipLabel(s, find(s, byId("strip:smart:choice:0"))).trim();
    const r = await tapFor(find(s, byId("strip:smart:choice:0")), x => x.includes("🪙"));
    return { pass: ["🪙 Heads", "🪙 Tails"].includes(word) && r.t.trim().toLowerCase() === `flip a coin ${word}`.toLowerCase(),
      note: `chip '${word}'; tapped: '${r.t}'${second(r)}` };
  } },
  { id: "S231", title: "Style: UPPERCASE, with the message's count", run: async () => {
    await fresh();
    await type("hello world");
    let s = await state();
    const g = find(s, byId("toolbar:glyf"));
    if (!g) return { pass: false, note: "no g key" };
    for (let i = 0; i < 3; i++) {
      await tapXY(g.x, g.y);
      if (await waitFor(v => (v.id || "").startsWith("shell:tile:"), 2500)) break;
    }
    const screenH = Number(shell("wm size").match(/(\d+)x(\d+)/)[2]);
    let opened = false;
    for (let i = 0; i < 6 && !opened; i++) {
      s = await state();
      const tile = find(s, byId("shell:tile:style"));
      if (tile && tile.y + tile.h / 2 < screenH - 170) { await tapXY(tile.x, tile.y); opened = true; break; }
      shell(`input swipe ${g.x + 200} ${screenH - 300} ${g.x + 200} ${screenH - 700} 300`);
      await sleep(600);
    }
    if (!opened) return { pass: false, note: "no Style tile in the menu" };
    // UPPERCASE sits under the styles: the panel is swiped up until it shows.
    let upper = null;
    for (let i = 0; i < 6 && !upper; i++) {
      s = await state();
      const row = find(s, byId("shell:style:upper"));
      if (row && row.y + row.h / 2 < screenH - 170) { upper = row; break; }
      shell(`input swipe ${g.x + 200} ${screenH - 300} ${g.x + 200} ${screenH - 700} 300`);
      await sleep(600);
    }
    const count = s.views.map(v => v.text || "").find(t => t.includes("words ·")) || "";
    await screenshot("S231-panel");
    if (!upper) return { pass: false, note: `no UPPERCASE row (count '${count}')` };
    const r = await tapFor(upper, x => x === "HELLO WORLD");
    return { pass: r.t.trim() === "HELLO WORLD" && count === "2 words · 11 characters",
      note: `count '${count}'; after UPPERCASE: '${r.t}'${second(r)}` };
  } },
  { id: "S232", title: "Shorthand with blanks: {day} filled in, {cursor} where typing goes on", run: async () => {
    tool("snippet", "--es text ';s232=Today is {day}'");
    tool("snippet", "--es text ';s232b=Hi {cursor}, thanks!'");
    atEnd.push(() => { tool("snippet", "--es text ';s232='"); tool("snippet", "--es text ';s232b='"); });
    await fresh();
    const day = shell("date +%A").trim();
    await type("ok ;s232 ");
    const first = await waitText(x => x.toLowerCase().includes(`today is ${day.toLowerCase()}`), 3000);
    await fresh();
    await type(";s232b ");
    await type("sam");
    const second2 = await waitText(x => x.toLowerCase() === "hi sam, thanks!", 3000);
    return { pass: first.toLowerCase().includes(`today is ${day.toLowerCase()}`) && !first.includes("{") &&
        second2.toLowerCase() === "hi sam, thanks!",
      note: `{day}: '${first}'; {cursor}: '${second2}'` };
  } },
  { id: "S233", title: "An hourly rate as a year and a month", run: async () => {
    await fresh();
    await type("$45/hr");
    const chip = await waitFor(byId("strip:smart:choice:1"), 4000);
    const s = await state();
    const parts = ["strip:smart:choice:0", "strip:smart:choice:1"].map(id => find(s, byId(id)));
    const words = parts.map(v => v ? chipLabel(s, v).trim() : "");
    if (!chip || !parts[0]) return { pass: false, note: `no pay chips; strip shows '${words.join(" | ")}' for '${s.text}'` };
    const r = await tapFor(parts[0], x => x.includes("("));
    return { pass: words[0] === "$93,600/yr" && words[1] === "$7,800/mo" && r.t.trim() === "$45/hr ($93,600/yr)",
      note: `chips '${words[0]}' | '${words[1]}'; tapped the first: '${r.t}'${second(r)}` };
  } },
);

scenarios.push(
  { id: "S234", title: "Emoji search finds 🥹 for 'tears' (every emoji Apple's board has)", run: async () => {
    await fresh();
    await key("emojikey");
    const mode = await waitFor(byId("emoji:mode:emoji"), 3000);
    if (mode) await tapXY(mode.x, mode.y);
    const search = await waitFor(byId("emoji:search"), 3000);
    if (!search) return { pass: false, note: "no emoji search" };
    await tapXY(search.x, search.y);
    await type("tears");
    const first = await waitFor(byId("emoji:suggestion:0"), 4000);
    const s = await state();
    const word = first ? (find(s, byId("emoji:suggestion:0")).text || "") : "";
    await screenshot("S234-tears");
    if (word !== "🥹") return { pass: false, note: `first result '${word}'` };
    const r = await tapFor(find(s, byId("emoji:suggestion:0")), x => x.includes("🥹"));
    return { pass: r.t.includes("🥹"), note: `first result '${word}'; typed '${r.t}'${second(r)}` };
  } },
  { id: "S235", title: "Not now on 'What Glyf sends': a pause sends nothing, so S90's message gets no Tidy this up", run: async () => {
    // Google Play's prominent disclosure: the sentence goes to the server on
    // a pause only after the person agreed (aiSuggest). Here they said Not now.
    const before = adb("shell", `run-as ${PKG} cat ${SETTINGS}`);
    writeSettings(JSON.stringify({ ...JSON.parse(before), aiSuggest: false }));
    try {
      await fresh();
      await type("ya ok will send the deck before six tmrw ");
      // S90 sees its chip within 10 s; give this one as long.
      const chip = await waitFor(v => v.id === "strip:smart", 10000);
      const s = await state();
      const label = chip ? s.views.filter(v => v.text).map(v => v.text).join(" ") : "";
      return { pass: !chip || !/tidy|places|look/i.test(label),
        note: chip ? `a chip showed: '${label.slice(0, 80)}'` : "no AI suggestion after 10 s" };
    } finally {
      writeSettings(before);
      tool("close");
    }
  } },
  { id: "S236", title: "Report in the AI panel flags what the AI wrote and says thanks; a sum the phone worked out has none", run: async () => {
    // Google Play's AI-Generated Content policy: an AI result can be reported
    // without leaving the app.
    await fresh();
    await type("2+5");
    let s = await state();
    await hold(s.keys.space[0], s.keys.space[1], 1100);
    await waitFor(byId("act:insert"), 4000);
    const onSum = !!find(await state(), byId("act:report"));
    tool("close");
    await fresh();
    await type("ya ok will send deck b4 6");
    s = await state();
    await hold(s.keys.space[0], s.keys.space[1], 1100);
    if (!await waitFor(byId("act:option:work"), 25000)) return { pass: false, note: "no versions after 25s" };
    // Report comes with ↻, once the last version is in.
    const flag = await waitFor(byId("act:report"), 15000);
    if (!flag) return { pass: false, note: "no Report in the panel" };
    let notice = "";
    for (let attempt = 0; attempt < 2 && !/Reported/.test(notice); attempt++) {
      await tapXY(flag.x, flag.y);
      for (let i = 0; i < 12 && !/Reported/.test(notice); i++) { await sleep(400); notice = (await state()).notice || ""; }
    }
    tool("close");
    return { pass: /Reported/.test(notice) && !onSum,
      note: `notice '${notice}'; Report on the sum: ${onSum ? "shown" : "none"}` };
  } },
  { id: "S238", title: "A typo after I offers haven and haven't, never the names Haven or Hagen", run: async () => {
    // Arpit's screenshot (2026-10-05): "I hsven" offered "hsven", Haven, Hagen.
    await fresh();
    await type("i hsven");
    const s = await state();
    const words = s.views.filter(v => v.text && v.y < s.keys.q[1]).map(v => v.text);
    return { pass: words.includes("haven") && words.includes("haven't") && !words.includes("Haven") && !words.includes("Hagen"),
      note: `strip: ${words.join(" | ")}` };
  } },
  { id: "S239", title: "The word before decides the fix: 'they wer' is 'they were'", run: async () => {
    await fresh();
    await type("they wer ");
    const t = await text();
    return { pass: t.toLowerCase() === "they were ", note: `'${t}'` };
  } },
  { id: "S240", title: "The two words before choose the next: 'on my ' offers way", run: async () => {
    await fresh();
    await type("on my ");
    const s = await state();
    const words = s.views.filter(v => v.text && v.y < s.keys.q[1]).map(v => v.text);
    return { pass: words.includes("way"), note: `strip: ${words.join(" | ")}` };
  } },
);

function chipLabel(s, chip) {
  if (chip.text) return chip.text;
  const inside = v => v !== chip && v.text && Math.abs(v.x - chip.x) <= chip.w / 2 && Math.abs(v.y - chip.y) <= chip.h / 2;
  return s.views.filter(inside).map(v => v.text).join(" ");
}

async function openGame(game) {
  await fresh();
  let s = await state();
  const g = find(s, v => v.id === "toolbar:glyf");
  if (!g) return null;
  await tapXY(g.x, g.y);
  await sleep(600);
  // The grid scrolls inside the panel: swipe it up until the tile's bottom
  // clears the gesture bar at the foot of the screen.
  const screenH = Number(shell("wm size").match(/(\d+)x(\d+)/)[2]);
  for (let i = 0; i < 5; i++) {
    s = await state();
    const tile = find(s, v => v.id === "shell:tile:games");
    if (!tile) return null;
    if (tile.y + tile.h / 2 < screenH - 170) { await tapXY(tile.x, tile.y); break; }
    shell(`input swipe ${g.x + 200} ${screenH - 300} ${g.x + 200} ${screenH - 700} 300`);
    await sleep(600);
  }
  await sleep(600);
  s = await state();
  const card = find(s, v => v.id === `games:${game}`);
  if (!card) return null;
  await tapXY(card.x, card.y);
  await sleep(600);
  return find(await state(), v => v.id === "games:board");
}

// As someone who agreed on the app's "What Glyf sends": the strip's AI
// suggestions (S90 and others) and saved details in AI requests only go out
// after that. S235 checks the other answer.
{
  const now = JSON.parse(adb("shell", `run-as ${PKG} cat ${SETTINGS}`));
  if (now.aiSuggest !== true || now.aiUsesVault === false || !now.aiConsent) {
    writeSettings(JSON.stringify({ ...now, aiSuggest: true, aiUsesVault: true, aiConsent: now.aiConsent || "qa" }));
  }
}

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
for (const job of atEnd) job();
if (!only) writeFileSync(new URL("./results/android.json", import.meta.url), JSON.stringify(results, null, 1));
console.log(`\n${results.filter(r => r.verdict === "pass").length}/${results.length} passed`);

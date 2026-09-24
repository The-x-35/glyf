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
  const asked = Date.now();
  tool("dump");
  // Up to 6 s: after a light/dark switch the keyboard rebuilds its view on
  // the emulator's software renderer before it gets to the dump.
  for (let i = 0; i < 24; i++) {
    await sleep(250);
    const s = JSON.parse(adb("shell", `run-as ${PKG} cat files/qa/state.json`));
    // An older file means the Glyf keyboard didn't answer: another keyboard
    // is active, or it crashed. Its keys would be taps into nothing.
    if (!s.at || s.at >= asked - 2000) return s;
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
  const write = text => execFileSync(ADB, ["shell", `run-as ${PKG} sh -c 'cat > ${file}'`], { input: text });
  if (!granted) shell(`pm grant ${PKG} ${perm}`);
  if (settings.clipboardScreenshots === false) write(JSON.stringify({ ...settings, clipboardScreenshots: true }));
  if (!granted) atEnd.push(() => shell(`pm revoke ${PKG} ${perm}`));
  return async () => {
    if (settings.clipboardScreenshots === false) write(before);
  };
}

// The stand-in Cal.com and Resend (qa/fake-scheduling.mjs), on this Mac.
const FAKE = "http://127.0.0.1:8796";

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
    const r = await tapFor(chip, x => x.includes("870"));
    return { pass: r.t.includes("= 870"), note: `'${r.t}'${second(r)}` };
  } },
  { id: "S88", title: "Asked for your address, it is one tap away", run: async () => {
    // The vault keeps whatever it already holds; seedvault only adds an
    // address and a UPI id where there are none, so the check is that the
    // chip puts a saved value after the words, not which value.
    tool("seedvault");
    await fresh();
    await type("sure my address is ");
    const chip = await waitFor(byId("strip:smart"), 3000);
    if (!chip) return { pass: false, note: "no address chip" };
    const r = await tapFor(chip, x => x.length > "sure my address is ".length + 4);
    return { pass: /^sure my address is \S/i.test(r.t) && /\d/.test(r.t), note: `'${r.t}'${second(r)}` };
  } },
  { id: "S89", title: "Asked for your UPI, it is one tap away", run: async () => {
    tool("seedvault");
    await fresh();
    await type("my upi is ");
    const chip = await waitFor(byId("strip:smart"), 3000);
    if (!chip) return { pass: false, note: "no UPI chip" };
    const r = await tapFor(chip, x => x.includes("@"));
    return { pass: /^my upi is \S+@\S+/i.test(r.t), note: `'${r.t}'${second(r)}` };
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
  { id: "S112", title: "A plan in a message offers Add to calendar", run: async () => {
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
    await tapXY(add.x, add.y);
    const row = await waitFor(v => v.text === "Dinner", 5000);
    const t = await text();
    return { pass: !!row && starts.includes("8:00") && t.toLowerCase().trim() === "dinner friday 8pm",
      note: `chip '${words}', starts '${starts}', message '${t}'` };
  } },
  // Call links, Book a time and invites (2026-09-24). S118 to S120 need the
  // stand-in Cal.com and Resend (qa/fake-scheduling.mjs on 8796) behind the
  // dev server; they never book or mail anyone real.
  { id: "S117", title: "A call link from the keyboard's calendar", run: async () => {
    await calendarOn();
    await fresh();
    tool("calendar");
    const call = await waitFor(byId("calendar:call"), 4000);
    if (!call) return { pass: false, note: "no call button on the calendar" };
    const r = await tapFor(call, x => /Join me on a call: https:\/\/\S+/.test(x), 6000);
    return { pass: /Join me on a call: https:\/\/\S+/.test(r.t), note: `message '${r.t}'${second(r)}` };
  } },
  { id: "S118", title: "Book a time on your own page for someone, with a guest", run: async () => {
    await fetch(`${FAKE}/_reset`);
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
  { id: "S119", title: "New Event with an invitee emails the invite", run: async () => {
    await calendarOn();
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
    if (!invitees) return { pass: false, note: "no Invitees row" };
    if (!(await tapOpen(invitees, byId("event:invitees:field")))) return { pass: false, note: "no invitees strip" };
    await type("sam@example.com");
    await key("return");
    const shown = await waitFor(textHas("sam@example.com"), 3000);
    const before = (await (await fetch(`${FAKE}/_log`)).json()).emails.length;
    const add = await waitFor(byId("event:add"), 3000);
    if (!add) return { pass: false, note: "no Add" };
    await tapXY(add.x, add.y);
    let mailed = null;
    for (let i = 0; i < 20 && !mailed; i++) {
      await sleep(500);
      const emails = (await (await fetch(`${FAKE}/_log`)).json()).emails;
      if (emails.length > before) mailed = emails.at(-1);
    }
    if (!mailed) return { pass: false, note: `no invite was sent; invitees row '${shown?.text}'` };
    const row = await waitFor(v => v.text === "Review", 5000);
    const ics = mailed.ics || "";
    return { pass: JSON.stringify(mailed.to) === JSON.stringify(["sam@example.com"]) &&
      ics.includes("SUMMARY:Review") && ics.includes("METHOD:REQUEST") && !!row,
      note: `invitees row '${shown?.text}'; mailed '${mailed.subject}' to ${mailed.to}; row ${row ? "shown" : "missing"}` };
  } },
  { id: "S120", title: "Someone's booking page in a message offers Book", run: async () => {
    await fetch(`${FAKE}/_reset`);
    await calendarOn();
    await fresh();
    // Committed straight into the field (autocorrect would split a link
    // typed key by key); the strip reads the message all the same.
    // `input text` drops a key now and then ("…/intr"): type it again.
    const want = "grab a time cal.com/sam-lee/intro";
    for (let i = 0; i < 2; i++) {
      shell("input text 'grab%sa%stime%scal.com/sam-lee/intro'");
      if ((await waitText(x => x === want, 3000)) === want) break;
      tool("clear");
      await sleep(500);
    }
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
for (const job of atEnd) job();
if (!only) writeFileSync(new URL("./results/android.json", import.meta.url), JSON.stringify(results, null, 1));
console.log(`\n${results.filter(r => r.verdict === "pass").length}/${results.length} passed`);

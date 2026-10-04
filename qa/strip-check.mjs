// Types lines on the Android emulator's Glyf keyboard and prints what the
// suggestion strip shows after each (debug builds: DEBUG_TOOL dump).
// Usage: node qa/strip-check.mjs "I hsven" "I've ben" ...   (OUT=dir saves screenshots)
import { execFileSync } from "node:child_process";
import { writeFileSync } from "node:fs";

const ADB = "/opt/homebrew/share/android-commandlinetools/platform-tools/adb";
const PKG = "com.arpit.glyf";
const sleep = ms => new Promise(r => setTimeout(r, ms));
const adb = (...args) => execFileSync(ADB, args, { encoding: "utf8" });
const tool = (id, extra = "") => adb("shell", `am broadcast -a ${PKG}.DEBUG_TOOL --es id ${id} ${extra}`);
const readState = () => {
  try { return JSON.parse(adb("shell", `run-as ${PKG} cat files/qa/state.json`)); } catch { return {}; }
};

async function state() {
  const before = readState().at || 0;
  tool("dump");
  for (let i = 0; i < 24; i++) {
    await sleep(250);
    const s = readState();
    if (s.at && s.at > before) return s;
  }
  throw new Error("the Glyf keyboard didn't answer (not the active keyboard, or it crashed)");
}

async function type(str) {
  // Lowercase letters and spaces; the field capitalizes a sentence's start.
  const s = await state();
  for (const ch of str.toLowerCase()) {
    const id = ch === " " ? "space" : ch;
    if (!s.keys[id]) throw new Error(`no key ${id}`);
    adb("shell", `input tap ${s.keys[id][0]} ${s.keys[id][1]}`);
    await sleep(160);
  }
  await sleep(600);
}

for (const line of process.argv.slice(2)) {
  tool("close");
  tool("clear");
  await sleep(500);
  await type(line);
  const s = await state();
  const strip = s.views.filter(v => v.id && v.id.startsWith("strip:") && v.text).map(v => `${v.id.replace("strip:", "")}=${v.text}`);
  console.log(`'${line}' -> field '${s.text}' | ${strip.join(" | ") || s.views.filter(v => v.text && v.y < (s.keys.q?.[1] ?? 9999)).map(v => v.text).join(" | ")}`);
  if (process.env.OUT) {
    const png = execFileSync(ADB, ["exec-out", "screencap", "-p"]);
    writeFileSync(`${process.env.OUT}/${line.replace(/[^a-z0-9]+/gi, "_")}.png`, png);
  }
}

#!/usr/bin/env node
/**
 * Renders tools/promo/scene.html to an MP4, one frame at a time.
 *
 * The scene draws frame f and only frame f when you call `seek(f)`, so this
 * walks the timeline rather than recording a clock: every frame gets however
 * long it needs, and the result is identical on a fast machine and a busy
 * one. Recording in real time is what makes promo clips stutter.
 *
 *   node tools/promo/render.mjs [--out path.mp4] [--scale 1] [--from 0] [--to N]
 *   node tools/promo/render.mjs --still 300 --out frame.png
 *
 * Needs Playwright's chromium (already in this repo's toolchain) and ffmpeg.
 */

import { chromium } from "playwright";
import { spawn } from "node:child_process";
import { mkdtemp, rm, mkdir } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const SCENE = "file://" + path.join(HERE, "scene.html");
const ROOT = path.resolve(HERE, "../..");

const argv = process.argv.slice(2);
const flag = (name, dflt) => {
  const i = argv.indexOf("--" + name);
  return i === -1 ? dflt : argv[i + 1];
};
const OUT = path.resolve(flag("out", path.join(ROOT, "site/public/brands/glyf-waitlist.mp4")));
const SCALE = Number(flag("scale", 1));
const STILL = flag("still", null);

const run = (cmd, args) =>
  new Promise((ok, no) => {
    const p = spawn(cmd, args, { stdio: ["ignore", "inherit", "inherit"] });
    p.on("close", c => (c === 0 ? ok() : no(new Error(`${cmd} exited ${c}`))));
  });

const main = async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({
    viewport: { width: 1080, height: 1920 },
    deviceScaleFactor: SCALE,
  });
  await page.goto(SCENE);
  await page.waitForSelector("body[data-ready]");
  await page.evaluate(() => document.fonts.ready);
  const { total, fps } = await page.evaluate(() => ({ total: window.TOTAL, fps: window.FPS }));

  if (STILL !== null) {
    await page.evaluate(f => window.seek(f), Number(STILL));
    await page.screenshot({ path: OUT });
    await browser.close();
    console.log("wrote", path.relative(ROOT, OUT), `(frame ${STILL})`);
    return;
  }

  const from = Number(flag("from", 0));
  const to = Number(flag("to", total));
  const dir = await mkdtemp(path.join(tmpdir(), "glyf-film-"));
  const started = Date.now();
  for (let f = from; f < to; f++) {
    await page.evaluate(n => window.seek(n), f);
    await page.screenshot({
      path: path.join(dir, String(f - from).padStart(5, "0") + ".png"),
      animations: "disabled",
    });
    if ((f - from) % 60 === 0) {
      const done = f - from + 1, all = to - from;
      const per = (Date.now() - started) / done;
      process.stdout.write(
        `\r  frame ${done}/${all}  ${((done / all) * 100).toFixed(0)}%  ` +
        `eta ${Math.round((per * (all - done)) / 1000)}s   `);
    }
  }
  process.stdout.write("\r" + " ".repeat(56) + "\r");
  await browser.close();

  await mkdir(path.dirname(OUT), { recursive: true });
  // yuv420p and an even frame size: without both, the file plays on a Mac and
  // on nothing else. -crf 16 keeps the flat greys of the keyboard clean, which
  // is where banding shows first.
  await run("ffmpeg", [
    "-y", "-framerate", String(fps),
    "-i", path.join(dir, "%05d.png"),
    "-c:v", "libx264", "-preset", "slow", "-crf", "16",
    "-pix_fmt", "yuv420p", "-movflags", "+faststart",
    "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2",
    OUT,
  ]);
  await rm(dir, { recursive: true, force: true });
  console.log("wrote", path.relative(ROOT, OUT), `${to - from} frames at ${fps}fps`);
};

main().catch(e => {
  console.error(e);
  process.exit(1);
});

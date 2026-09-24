import { afterEach, describe, expect, it } from "vitest";
import { buildApp } from "../src/index.js";
import { notoCatalogue, notoItem, searchNoto } from "../src/routes/media.js";
import { signedInApp } from "./helpers.js";

const saved = { key: process.env.KLIPY_APP_KEY, base: process.env.KLIPY_BASE_URL };

afterEach(() => {
  if (saved.key === undefined) delete process.env.KLIPY_APP_KEY; else process.env.KLIPY_APP_KEY = saved.key;
  if (saved.base === undefined) delete process.env.KLIPY_BASE_URL; else process.env.KLIPY_BASE_URL = saved.base;
});

describe("GET /media/config", () => {
  it("hands a signed-in phone the KLIPY key, which KLIPY wants called from the phone", async () => {
    process.env.KLIPY_APP_KEY = "test-app-key";
    delete process.env.KLIPY_BASE_URL;
    const res = await signedInApp().inject({ method: "GET", url: "/media/config" });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({
      klipy: { key: "test-app-key", base: "https://api.klipy.com/api/v1/", contentFilter: "high" },
      emojiStickers: true,
    });
  });

  it("says GIFs are off, and stickers still on, without a key", async () => {
    delete process.env.KLIPY_APP_KEY;
    const res = await signedInApp().inject({ method: "GET", url: "/media/config" });
    expect(res.json()).toEqual({ klipy: null, emojiStickers: true });
  });

  it("never gives the key to someone without a session", async () => {
    process.env.KLIPY_APP_KEY = "test-app-key";
    const res = await buildApp().inject({ method: "GET", url: "/media/config" });
    expect(res.statusCode).toBe(401);
    expect(res.body).not.toContain("test-app-key");
  });

  it("points the phone at a test double only when told to", async () => {
    process.env.KLIPY_APP_KEY = "demo";
    process.env.KLIPY_BASE_URL = "http://127.0.0.1:8799/api/v1";
    const res = await signedInApp().inject({ method: "GET", url: "/media/config" });
    expect(res.json().klipy.base).toBe("http://127.0.0.1:8799/api/v1/");
  });
});

describe("Noto animated emoji stickers", () => {
  it("bundles the catalogue, base emoji only, most popular first", () => {
    const all = notoCatalogue();
    expect(all.length).toBeGreaterThan(500);
    expect(all[0].c).toBe("1f600");
    expect(all.some(s => /_1f3f[b-f]/.test(s.c))).toBe(false);
  });

  it("finds a feeling through the emoji that show it", () => {
    expect(searchNoto("laughing").slice(0, 3).map(s => s.c)).toContain("1f602");
    expect(searchNoto("thank you").map(s => s.c)).toContain("1f64f");
    expect(searchNoto("hello").map(s => s.c)).toContain("1f44b");
    expect(searchNoto("wow").length).toBeGreaterThan(2);
    expect(searchNoto("food").every(s => s.g === "food" || s.t.length > 0)).toBe(true);
    expect(searchNoto("zzzqqq")).toEqual([]);
  });

  it("previews the small still and sends the animated GIF", () => {
    const item = notoItem({ c: "1f602", t: ["joy"], g: "smileys" });
    expect(item.preview).toBe("https://fonts.gstatic.com/s/e/notoemoji/latest/1f602/128.png");
    expect(item.url).toBe("https://fonts.gstatic.com/s/e/notoemoji/latest/1f602/512.gif");
    expect(item.title).toBe("joy");
  });

  it("pages through a search and credits Google", async () => {
    const app = signedInApp();
    const first = (await app.inject({ method: "GET", url: "/media/emoji-stickers" })).json();
    expect(first.items).toHaveLength(30);
    expect(first.next).toBe("2");
    expect(first.attribution).toContain("CC BY 4.0");
    const second = (await app.inject({ method: "GET", url: "/media/emoji-stickers?page=2" })).json();
    expect(second.items[0].id).not.toBe(first.items[0].id);
    const love = (await app.inject({ method: "GET", url: "/media/emoji-stickers?q=love" })).json();
    expect(love.items.length).toBeGreaterThan(3);
  });
});

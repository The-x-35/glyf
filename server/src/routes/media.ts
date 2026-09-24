import type { FastifyInstance } from "fastify";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { registryDir } from "../lib/paths.js";

/**
 * GIFs and stickers for the keyboard's emoji board (Gboard's tabs).
 *
 * GIFs and most stickers come from KLIPY, the free GIF API built by Tenor's
 * founders after Google closed Tenor's API (June 30, 2026). KLIPY's terms
 * want every API call and every file load to come from the person's device,
 * not from a proxy, so this server does not search KLIPY: it hands a
 * signed-in phone the app key (`GET /media/config`) and the keyboard calls
 * KLIPY itself. The key never ships inside the app, can be rotated here, and
 * only reaches someone with a Glyf session. `KLIPY_BASE_URL` points the
 * phones somewhere else (a fake for tests); it is never set in production.
 *
 * Stickers also work with no key at all: Google's Noto Animated Emoji (CC BY
 * 4.0), served from Google's font CDN, listed from a catalogue bundled here
 * (`registry/stickers/noto.json`, most popular first, skin-tone variants
 * left out). The grid shows the 128px still, and the 512px animated GIF is
 * what gets pasted. The licence asks for credit, which the board shows.
 */

interface NotoSticker {
  /** Codepoint path segment, e.g. "1f602" or "2764_fe0f_200d_1f525". */
  c: string;
  /** Short names, e.g. ["joy"] or ["folded-hands", "pray", "thank-you"]. */
  t: string[];
  /** Category: smileys, animals, food, activities, objects, symbols, travel, people, flags. */
  g: string;
}

export interface StickerItem {
  id: string;
  title: string;
  preview: string;
  pw: number;
  ph: number;
  url: string;
  w: number;
  h: number;
}

const NOTO_CDN = "https://fonts.gstatic.com/s/e/notoemoji/latest";
export const NOTO_ATTRIBUTION = "Noto Emoji by Google · CC BY 4.0";
const PAGE = 30;

let catalogue: NotoSticker[] | null = null;
export function notoCatalogue(): NotoSticker[] {
  if (!catalogue) {
    catalogue = JSON.parse(readFileSync(join(registryDir("stickers"), "noto.json"), "utf8")) as NotoSticker[];
  }
  return catalogue;
}

/** The words people search stickers with, in the catalogue's own names.
 *  Its names are sparse (about one per emoji), so a feeling is spread over
 *  the emoji that show it. */
const SYNONYMS: Record<string, string[]> = {
  hello: ["wave"], hi: ["wave"], hey: ["wave"], bye: ["wave"],
  wow: ["surprised", "hushed", "astonished", "mind-blown", "open-mouth", "star-struck", "exploding-head"],
  omg: ["scream", "mind-blown", "astonished", "flushed"],
  love: ["heart", "heart-eyes", "heart-face", "kissing-heart", "love-letter"],
  laughing: ["joy", "laughing", "rofl", "rolling-on-the-floor-laughing", "grin", "sweat-smile"],
  haha: ["joy", "laughing", "rofl", "rolling-on-the-floor-laughing", "grin"],
  lol: ["joy", "laughing", "rofl", "rolling-on-the-floor-laughing"],
  happy: ["smile", "grin", "blush", "warm-smile", "joy", "partying-face"],
  sad: ["sad", "cry", "loudly-crying", "pensive", "disappointed", "worried", "pleading"],
  cry: ["cry", "loudly-crying", "happy-cry"],
  angry: ["angry", "rage", "steam", "cursing", "triumph"],
  party: ["partying-face", "party-popper", "confetti", "balloon", "tada"],
  celebrate: ["partying-face", "party-popper", "confetti", "clap", "fireworks"],
  "thank you": ["thank-you", "folded-hands", "pray", "heart-hands"],
  thanks: ["thank-you", "folded-hands", "pray", "heart-hands"],
  please: ["please", "pleading", "folded-hands"],
  sleepy: ["sleep", "sleepy", "yawn", "zzz"],
  tired: ["sleep", "sleepy", "yawn", "weary", "tired"],
  "thumbs up": ["thumbs-up", "+1", "ok", "clap"], yes: ["thumbs-up", "+1", "ok", "check"],
  no: ["thumbs-down", "-1", "cross", "x", "no"], ok: ["ok", "thumbs-up", "+1"],
  cool: ["sunglasses", "cool", "smirk"], think: ["thinking-face", "monocle"],
  birthday: ["birthday-cake", "partying-face", "party-popper", "gift", "balloon"],
  fire: ["fire", "lit"], hot: ["fire", "hot-face"], cold: ["cold-face", "snowflake"],
  kiss: ["kissing", "kissing-heart", "kiss"], hug: ["hug-face", "hugging"],
  sick: ["sick", "nauseated", "mask", "thermometer", "sneeze"],
  money: ["money-face", "money-with-wings", "dollar"], scared: ["scream", "fearful", "anxious"],
  dance: ["dancer", "man-dancing"], music: ["musical-notes", "microphone", "headphone"],
};

const CATEGORY_WORDS: Record<string, string> = {
  food: "food", drink: "food", animal: "animals", animals: "animals", pet: "animals",
  nature: "animals", sport: "activities", sports: "activities", travel: "travel",
  flag: "flags", flags: "flags", object: "objects", objects: "objects", symbol: "symbols",
  symbols: "symbols", face: "smileys", faces: "smileys", smiley: "smileys", smileys: "smileys",
};

/** Words a name answers to: "loudly-crying" answers "loudly", "crying"
 *  and the whole name. */
function words(name: string): string[] {
  return [name, ...name.split(/[-_]/)];
}

/** Stickers for a search, best first; empty `q` is the whole catalogue by
 *  popularity (the "trending" of a fixed set). */
export function searchNoto(q: string): NotoSticker[] {
  const all = notoCatalogue();
  const query = q.trim().toLowerCase();
  if (!query) return all;
  const wanted = new Set<string>([query, ...query.split(/\s+/)]);
  for (const w of [...wanted]) for (const s of SYNONYMS[w] ?? []) wanted.add(s);
  const category = query.split(/\s+/).map(w => CATEGORY_WORDS[w]).find(Boolean);
  const scored: { s: NotoSticker; score: number; rank: number }[] = [];
  all.forEach((s, rank) => {
    let score = 0;
    for (const tag of s.t) {
      if (wanted.has(tag)) score = Math.max(score, 3);
      else if (words(tag).some(w => wanted.has(w))) score = Math.max(score, 2);
      else if ([...wanted].some(w => w.length >= 3 && tag.startsWith(w))) score = Math.max(score, 1);
    }
    if (category && s.g === category) score = Math.max(score, 1);
    if (score > 0) scored.push({ s, score, rank });
  });
  scored.sort((a, b) => b.score - a.score || a.rank - b.rank);
  return scored.map(x => x.s);
}

export function notoItem(s: NotoSticker): StickerItem {
  const title = (s.t[0] ?? "emoji").replace(/-/g, " ");
  return {
    id: `noto:${s.c}`,
    title,
    preview: `${NOTO_CDN}/${s.c}/128.png`, pw: 128, ph: 128,
    url: `${NOTO_CDN}/${s.c}/512.gif`, w: 512, h: 512,
  };
}

export function mediaRoutes(app: FastifyInstance): void {

  /** What the keyboard needs to fetch media itself. */
  app.get("/media/config", async () => {
    const key = process.env.KLIPY_APP_KEY?.trim();
    const base = (process.env.KLIPY_BASE_URL?.trim() || "https://api.klipy.com/api/v1/")
      .replace(/\/*$/, "/");
    return {
      // KLIPY: GIFs and stickers, called from the phone (its terms).
      klipy: key ? { key, base, contentFilter: "high" } : null,
      // Animated emoji stickers need no key.
      emojiStickers: true,
    };
  });

  /** Noto Animated Emoji as stickers: trending (empty q) or a search. */
  app.get<{ Querystring: { q?: string; page?: string } }>("/media/emoji-stickers", async req => {
    const q = (req.query.q ?? "").slice(0, 60);
    const page = Math.max(1, Math.min(Number(req.query.page ?? 1) || 1, 100));
    const hits = searchNoto(q);
    const start = (page - 1) * PAGE;
    return {
      items: hits.slice(start, start + PAGE).map(notoItem),
      next: start + PAGE < hits.length ? String(page + 1) : null,
      attribution: NOTO_ATTRIBUTION,
    };
  });
}

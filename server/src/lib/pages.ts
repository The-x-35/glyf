import { randomBytes } from "node:crypto";
import type { PlaceCard } from "./searchcards.js";
import type { KV } from "./store.js";

/**
 * Live mini-app pages: a list result ("SF best italian restaurant") becomes a
 * small shareable web page, and the keyboard drops its link into the chat
 * instead of a wall of text (Acti's "drop a live mini-app").
 *
 * The page holds only what the user chose to share — the places and the
 * title they typed — under an unguessable id. Nothing about the sender.
 */

export interface MiniPage {
  title: string;
  places: PlaceCard[];
  createdAt: number;
}

const COLLECTION = "pages";

export function createPage(kv: KV, title: string, places: PlaceCard[], now = Date.now()): string {
  const id = randomBytes(9).toString("base64url"); // 12 chars, not enumerable
  kv.put<MiniPage>(COLLECTION, id, { title: title.slice(0, 120), places: places.slice(0, 8), createdAt: now });
  return id;
}

export function getPage(kv: KV, id: string): MiniPage | undefined {
  if (!/^[\w-]{8,24}$/.test(id)) return undefined;
  return kv.get<MiniPage>(COLLECTION, id);
}

const escape = (s: string) =>
  s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;").replace(/'/g, "&#39;");

/** Only http(s) links reach an href — a card URL is data, never script. */
const safeHref = (url: string) => (/^https?:\/\//i.test(url) ? escape(url) : "#");

export function renderPage(page: MiniPage): string {
  const cards = page.places.map((p, i) => {
    const meta = [
      typeof p.rating === "number" ? `★ ${p.rating.toFixed(1)}${p.ratingCount ? ` · ${p.ratingCount.toLocaleString("en")}` : ""}` : "",
      p.distance ?? "",
      p.openNow === true ? "Open now" : p.openNow === false ? "Closed" : "",
    ].filter(Boolean).map(escape).join(" · ");
    return `
    <a class="card" href="${safeHref(p.url)}" rel="noopener">
      <span class="num">${i + 1}</span>
      <span class="body">
        <b>${escape(p.title)}</b>
        ${meta ? `<i>${meta}</i>` : ""}
        ${p.address ? `<em>${escape(p.address)}</em>` : ""}
      </span>
      <span class="go">Maps ›</span>
    </a>`;
  }).join("");

  return `<!doctype html>
<html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${escape(page.title)}</title>
<meta property="og:title" content="${escape(page.title)}">
<meta property="og:description" content="${page.places.length} places · made with Glyf">
<style>
  :root { color-scheme: light dark; --bg:#f5f5f7; --card:#fff; --ink:#1d1d1f; --soft:#6e6e73; --line:rgba(0,0,0,.08); }
  @media (prefers-color-scheme: dark) { :root { --bg:#000; --card:#1c1c1e; --ink:#f5f5f7; --soft:#a1a1a6; --line:rgba(255,255,255,.12); } }
  * { box-sizing:border-box; margin:0 }
  body { background:var(--bg); color:var(--ink); font:16px/1.4 -apple-system, "SF Pro Text", Inter, system-ui, sans-serif; }
  main { max-width:560px; margin:0 auto; padding:40px 18px 32px; }
  h1 { font-size:32px; font-weight:600; letter-spacing:-.03em; line-height:1.1; }
  p.sub { color:var(--soft); margin-top:8px; }
  .list { margin-top:24px; display:grid; gap:10px; }
  .card { display:flex; align-items:center; gap:14px; padding:16px; border-radius:18px; background:var(--card);
          border:1px solid var(--line); color:inherit; text-decoration:none; }
  .num { flex:none; width:30px; height:30px; border-radius:9px; background:var(--ink); color:var(--bg);
         display:grid; place-items:center; font-weight:600; font-size:14px; }
  .body { flex:1; min-width:0; display:grid; gap:2px; }
  .body b { font-weight:600; letter-spacing:-.01em; }
  .body i, .body em { font-style:normal; font-size:14px; color:var(--soft); overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
  .go { flex:none; font-size:14px; color:var(--soft); }
  footer { margin-top:28px; font-size:13px; color:var(--soft); text-align:center; }
  footer a { color:inherit; font-weight:600; text-decoration:none; }
  footer .dot { display:inline-block; width:.3em; height:.3em; border-radius:50%; background:#7c5cff; transform:translateY(-.6em); margin-left:.1em; }
</style></head>
<body><main>
  <h1>${escape(page.title)}</h1>
  <p class="sub">${page.places.length} place${page.places.length === 1 ? "" : "s"}</p>
  <div class="list">${cards}</div>
  <footer>Made with <a href="https://tryglyf.com">glyf<span class="dot"></span></a></footer>
</main></body></html>`;
}

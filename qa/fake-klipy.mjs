// A stand-in for KLIPY's API, for testing the keyboard's GIF and sticker
// tabs without a KLIPY key. It answers the paths the keyboard calls, in
// KLIPY's own response shape (read from KLIPY's iOS demo app and the
// gif-picker-react provider), and serves a folder of small GIFs as the files.
//
//   FIXTURES=<dir with gifs/*.gif and stickers/*.gif> PORT=8798 node qa/fake-klipy.mjs
//   then start the Glyf server with
//   KLIPY_APP_KEY=demo KLIPY_BASE_URL=http://127.0.0.1:8798/api/v1/
//
// File names are the searchable titles ("haha-cat.gif" answers "haha" and
// "cat"). Every list also carries one ad item, which the keyboard must skip.
// Never deploy this; it exists only so a simulator can exercise the real
// client code end to end.
import { createServer } from "node:http";
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";

const DIR = process.env.FIXTURES;
const PORT = Number(process.env.PORT ?? 8798);
if (!DIR) { console.error("set FIXTURES"); process.exit(1); }

const HOST = `http://127.0.0.1:${PORT}`;
const shared = new Map(); // `${kind}:${customer}` -> [slug]
const log = [];

function gifSize(buf) {
  // GIF logical screen size: little-endian at bytes 6..9.
  return { width: buf.readUInt16LE(6), height: buf.readUInt16LE(8) };
}

function catalogue(kind) {
  const dir = join(DIR, kind);
  return readdirSync(dir).filter(f => f.endsWith(".gif")).sort().map((f, i) => {
    const buf = readFileSync(join(dir, f));
    const { width, height } = gifSize(buf);
    const slug = f.replace(/\.gif$/, "");
    const url = `${HOST}/files/${kind}/${f}`;
    const format = { url, width, height, size: statSync(join(dir, f)).size };
    const variant = { gif: format, ...(kind === "stickers" ? { png: format } : { jpg: format }) };
    return {
      id: 1000 + i, slug, title: slug.replace(/-/g, " "),
      file: { hd: variant, md: variant, sm: variant, xs: variant },
      tags: slug.split("-"), type: kind === "gifs" ? "gif" : "sticker",
    };
  });
}

const AD = { type: "ad", content: "<div>ad</div>", width: 300, height: 250 };

function page(items, url) {
  const p = Math.max(1, Number(url.searchParams.get("page") ?? 1));
  const per = Math.min(50, Math.max(8, Number(url.searchParams.get("per_page") ?? 24)));
  const slice = items.slice((p - 1) * per, p * per);
  return { result: true, data: {
    data: [...slice.slice(0, 2), AD, ...slice.slice(2)],
    current_page: p, per_page: per, has_next: p * per < items.length,
  } };
}

function send(res, status, body, type = "application/json") {
  res.writeHead(status, { "content-type": type });
  res.end(type === "application/json" ? JSON.stringify(body) : body);
}

createServer((req, res) => {
  const url = new URL(req.url, HOST);
  const parts = url.pathname.split("/").filter(Boolean);
  log.push(`${req.method} ${url.pathname}${url.search}`);
  console.log(`${req.method} ${url.pathname}${url.search}`);

  if (parts[0] === "files" && parts.length === 3) {
    try { return send(res, 200, readFileSync(join(DIR, parts[1], parts[2])), "image/gif"); }
    catch { return send(res, 404, { result: false }); }
  }
  if (parts[0] === "_log") return send(res, 200, log);
  // /api/v1/{key}/...
  if (parts[0] !== "api" || parts[1] !== "v1" || parts[2] !== "demo") {
    return send(res, 401, { result: false, errors: { message: "bad app key" } });
  }
  const [kind, action, arg] = parts.slice(3);
  if (kind === "autocomplete") {
    const q = decodeURIComponent(action ?? "");
    return send(res, 200, { result: true, data: [q, `${q} cat`, `${q} dog`, `${q} funny`] });
  }
  if (kind !== "gifs" && kind !== "stickers") return send(res, 404, { result: false });
  const items = catalogue(kind);
  const customer = url.searchParams.get("customer_id") ?? "";
  switch (action) {
    case "trending": return send(res, 200, page(items, url));
    case "search": {
      const q = (url.searchParams.get("q") ?? "").toLowerCase();
      const hits = items.filter(i => i.slug.includes(q) || i.tags.some(t => q.includes(t)));
      return send(res, 200, page(hits, url));
    }
    case "recent": {
      const slugs = shared.get(`${kind}:${arg}`) ?? [];
      return send(res, 200, page(slugs.map(s => items.find(i => i.slug === s)).filter(Boolean), url));
    }
    case "share": {
      let body = "";
      req.on("data", c => { body += c; });
      req.on("end", () => {
        const who = JSON.parse(body || "{}").customer_id ?? customer;
        const key = `${kind}:${who}`;
        shared.set(key, [arg, ...(shared.get(key) ?? []).filter(s => s !== arg)]);
        send(res, 200, { result: true });
      });
      return;
    }
    case "categories":
      return send(res, 200, { result: true, data: { locale: "en", categories: [] } });
  }
  send(res, 404, { result: false });
}).listen(PORT, "127.0.0.1", () => console.log(`fake KLIPY on ${HOST}`));

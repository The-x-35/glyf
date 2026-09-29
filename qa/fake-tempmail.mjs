// A stand-in for Temp-Mail.io's API (https://docs.temp-mail.io), for device
// scenarios before there is a key, or without spending one. Start it, then run
// the local server with TEMP_MAIL_BASE_URL=http://127.0.0.1:8798 and any
// TEMP_MAIL_API_KEY. Never point Railway at it.
//
//   node qa/fake-tempmail.mjs            listens on 8798
//
// Scenarios drop a mail into an address with
//   curl -X POST 127.0.0.1:8798/_inject -d '{"email":"…","subject":"…","text":"…"}'
// and read what exists with GET /_state.

import { createServer } from "node:http";
import { randomBytes } from "node:crypto";

const PORT = Number(process.env.PORT ?? 8798);
const inboxes = new Map();          // email → [{ id, from, subject, body_text, body_html, created_at }]
const words = ["quiet", "amber", "swift", "lunar", "maple", "cobalt", "ember", "willow"];

function body(req) {
  return new Promise(resolve => {
    let data = "";
    req.on("data", c => { data += c; });
    req.on("end", () => { try { resolve(JSON.parse(data || "{}")); } catch { resolve({}); } });
  });
}

function send(res, status, obj) {
  res.writeHead(status, { "content-type": "application/json" });
  res.end(obj === undefined ? "" : JSON.stringify(obj));
}

createServer(async (req, res) => {
  const url = new URL(req.url, `http://127.0.0.1:${PORT}`);
  if (url.pathname === "/_inject" && req.method === "POST") {
    const b = await body(req);
    const list = inboxes.get(b.email);
    if (!list) return send(res, 404, { error: { detail: "no such address" } });
    list.push({
      id: randomBytes(6).toString("hex"), from: b.from ?? '"Acme" <no-reply@acme.example>',
      subject: b.subject ?? "Your code", body_text: b.text ?? "", body_html: b.html ?? "",
      created_at: new Date().toISOString(),
    });
    return send(res, 200, { ok: true });
  }
  if (url.pathname === "/_state") return send(res, 200, Object.fromEntries(inboxes));
  if (!req.headers["x-api-key"]) return send(res, 401, { error: { detail: "no key" } });
  if (url.pathname === "/v1/emails" && req.method === "POST") {
    const b = await body(req);
    const name = b.email ?? `${words[Math.floor(Math.random() * words.length)]}.${randomBytes(3).toString("hex")}`;
    const email = name.includes("@") ? name : `${name}@glyf-temp.example`;
    inboxes.set(email, []);
    return send(res, 200, { email, ttl: 3600 });
  }
  const msgs = url.pathname.match(/^\/v1\/emails\/([^/]+)\/messages$/);
  if (msgs && req.method === "GET") {
    const list = inboxes.get(decodeURIComponent(msgs[1]));
    return list ? send(res, 200, { messages: list }) : send(res, 404, { error: { detail: "expired" } });
  }
  const one = url.pathname.match(/^\/v1\/emails\/([^/]+)$/);
  if (one && req.method === "DELETE") {
    inboxes.delete(decodeURIComponent(one[1]));
    res.writeHead(204); return res.end();
  }
  if (url.pathname === "/v1/domains") return send(res, 200, { domains: [{ name: "glyf-temp.example", type: "public" }] });
  if (url.pathname === "/v1/rate_limit") return send(res, 200, { limit: 10000, used: 0, remaining: 10000, reset: 0 });
  send(res, 404, { error: { detail: "not found" } });
}).listen(PORT, "0.0.0.0", () => console.log(`fake Temp-Mail.io on :${PORT}`));

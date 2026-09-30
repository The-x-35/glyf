// A stand-in for mail.tm's API (https://docs.mail.tm, shared/tempmail/RULES.md)
// for device scenarios: the keyboards call mail.tm directly, so tests point
// them here with the setting `tempMailBase` (iOS: http://127.0.0.1:8798,
// Android emulator: http://10.0.2.2:8798).
//
//   node qa/fake-mailtm.mjs          listens on 8798
//
// Scenarios drop a mail into an address with
//   curl -X POST 127.0.0.1:8798/_inject -d '{"email":"…","subject":"…","text":"…"}'
// and read what exists with GET /_state.

import { createServer } from "node:http";
import { randomBytes } from "node:crypto";

const PORT = Number(process.env.PORT ?? 8798);
const DOMAIN = "glyf-temp.example";
const accounts = new Map();   // id → { id, address, password, messages: [] }
const tokens = new Map();     // token → account id

const hex = n => randomBytes(n).toString("hex");

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

function who(req) {
  const auth = req.headers.authorization ?? "";
  const id = tokens.get(auth.replace(/^Bearer\s+/i, ""));
  return id ? accounts.get(id) : undefined;
}

const listItem = m => ({ id: m.id, from: m.from, subject: m.subject, intro: m.text.slice(0, 120), seen: false,
  createdAt: m.createdAt, hasAttachments: false });

createServer(async (req, res) => {
  const url = new URL(req.url, `http://127.0.0.1:${PORT}`);
  const path = url.pathname;
  if (path === "/_inject" && req.method === "POST") {
    const b = await body(req);
    const acct = [...accounts.values()].find(a => a.address === b.email);
    if (!acct) return send(res, 404, { detail: "no such address" });
    const [name, address] = [b.fromName ?? "Acme", b.fromAddress ?? "no-reply@acme.example"];
    acct.messages.unshift({ id: hex(12), from: { name, address }, subject: b.subject ?? "Your code",
      text: b.text ?? "", html: b.html ? [b.html] : [], createdAt: new Date().toISOString() });
    return send(res, 200, { ok: true });
  }
  if (path === "/_state") {
    return send(res, 200, [...accounts.values()].map(a => ({ address: a.address, messages: a.messages.length })));
  }
  if (path === "/domains" && req.method === "GET") {
    return send(res, 200, [{ id: "d1", domain: DOMAIN, isActive: true, isPrivate: false }]);
  }
  if (path === "/accounts" && req.method === "POST") {
    const b = await body(req);
    if (!b.address?.endsWith(`@${DOMAIN}`) || !b.password) return send(res, 422, { detail: "invalid" });
    if ([...accounts.values()].some(a => a.address === b.address)) return send(res, 422, { detail: "address already used" });
    const acct = { id: hex(12), address: b.address, password: b.password, messages: [] };
    accounts.set(acct.id, acct);
    return send(res, 201, { id: acct.id, address: acct.address, quota: 40000000, used: 0,
      createdAt: new Date().toISOString() });
  }
  if (path === "/token" && req.method === "POST") {
    const b = await body(req);
    const acct = [...accounts.values()].find(a => a.address === b.address && a.password === b.password);
    if (!acct) return send(res, 401, { code: 401, message: "Invalid credentials." });
    const token = hex(24);
    tokens.set(token, acct.id);
    return send(res, 200, { token, id: acct.id });
  }
  const acct = who(req);
  if (!acct) return send(res, 401, { code: 401, message: "JWT Token not found" });
  if (path === "/messages" && req.method === "GET") return send(res, 200, acct.messages.map(listItem));
  const one = path.match(/^\/messages\/([^/]+)$/);
  if (one && req.method === "GET") {
    const m = acct.messages.find(x => x.id === one[1]);
    return m ? send(res, 200, { ...listItem(m), text: m.text, html: m.html }) : send(res, 404, { detail: "Not Found" });
  }
  const del = path.match(/^\/accounts\/([^/]+)$/);
  if (del && req.method === "DELETE") {
    if (del[1] !== acct.id) return send(res, 403, { detail: "Access Denied." });
    accounts.delete(acct.id);
    res.writeHead(204); return res.end();
  }
  send(res, 404, { detail: "Not Found" });
}).listen(PORT, "0.0.0.0", () => console.log(`fake mail.tm on :${PORT}`));

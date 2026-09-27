// A stand-in for the Google APIs the keyboards call themselves: the token
// endpoint (a refresh on the iPhone), Meet's spaces.create and Calendar's
// events.insert. The keyboards reach it only in debug builds, after a
// scenario connects "Google" with --glyf-test-google <base> (iPhone) or the
// `googlefake` debug tool (Android). No real account is touched and nobody is
// emailed.
//
//   PORT=8797 node qa/fake-google.mjs
//
// GET /_log lists the Meet links made and the events added (with the query,
// so a test can see sendUpdates=all); GET /_reset clears it.
import { createServer } from "node:http";
import { randomBytes } from "node:crypto";

const PORT = Number(process.env.PORT ?? 8797);
const log = { spaces: [], events: [] };

function send(res, status, body) {
  res.writeHead(status, { "content-type": "application/json" });
  res.end(JSON.stringify(body));
}

/** "abc-defg-hij", the shape of a Meet code. */
function meetCode() {
  const letters = [...randomBytes(10)].map(b => "abcdefghijklmnopqrstuvwxyz"[b % 26]).join("");
  return `${letters.slice(0, 3)}-${letters.slice(3, 7)}-${letters.slice(7, 10)}`;
}

createServer((req, res) => {
  const url = new URL(req.url, `http://127.0.0.1:${PORT}`);
  let body = "";
  req.on("data", c => { body += c; });
  req.on("end", () => {
    console.log(`${req.method} ${url.pathname}${url.search}`);
    if (url.pathname === "/_log") return send(res, 200, log);
    if (url.pathname === "/_reset") {
      log.spaces.length = 0;
      log.events.length = 0;
      return send(res, 200, log);
    }
    if (url.pathname === "/token" && req.method === "POST") {
      const form = new URLSearchParams(body);
      if (form.get("grant_type") !== "refresh_token" || !form.get("refresh_token")) {
        return send(res, 400, { error: "invalid_grant" });
      }
      return send(res, 200, { access_token: `fake-access-${Date.now()}`, expires_in: 3600, token_type: "Bearer" });
    }
    const signed = /^Bearer \S+/.test(req.headers.authorization ?? "");
    if (url.pathname === "/v2/spaces" && req.method === "POST") {
      if (!signed) return send(res, 401, { error: { code: 401, message: "Request is missing credentials" } });
      const code = meetCode();
      const space = { name: `spaces/${randomBytes(6).toString("hex")}`, meetingUri: `https://meet.google.com/${code}`, meetingCode: code };
      log.spaces.push(space);
      return send(res, 200, space);
    }
    if (url.pathname === "/calendar/v3/calendars/primary/events" && req.method === "GET") {
      // events.list, the way the keyboards ask it: everything inserted here,
      // plus whatever /_seed put in (an "edited on the web" stand-in).
      if (!signed) return send(res, 401, { error: { code: 401, message: "Request is missing credentials" } });
      const items = log.events.map(e => ({ ...e.body, id: e.id, status: "confirmed" }));
      return send(res, 200, { kind: "calendar#events", items });
    }
    if (url.pathname === "/_seed" && req.method === "POST") {
      // A test drops an event in as if it were made on the web.
      const event = JSON.parse(body || "{}");
      const id = randomBytes(8).toString("hex");
      log.events.push({ query: {}, body: event, id });
      return send(res, 200, { id });
    }
    if (url.pathname === "/calendar/v3/calendars/primary/events" && req.method === "POST") {
      if (!signed) return send(res, 401, { error: { code: 401, message: "Request is missing credentials" } });
      const event = JSON.parse(body || "{}");
      if (!event.summary || !event.start || !event.end) return send(res, 400, { error: { code: 400, message: "Missing time" } });
      const id = randomBytes(8).toString("hex");
      const video = event.conferenceData?.createRequest && url.searchParams.get("conferenceDataVersion") === "1";
      const out = {
        ...event, id, status: "confirmed",
        htmlLink: `https://www.google.com/calendar/event?eid=${id}`,
        ...(video ? { hangoutLink: `https://meet.google.com/${meetCode()}` } : {}),
      };
      log.events.push({ query: Object.fromEntries(url.searchParams), body: event, id });
      return send(res, 200, out);
    }
    send(res, 404, { error: { code: 404, message: "Not found" } });
  });
}).listen(PORT, "127.0.0.1", () => console.log(`fake Google on http://127.0.0.1:${PORT}`));

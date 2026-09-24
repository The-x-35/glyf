// A stand-in for Cal.com's API (v2 slots, event types, bookings), so the
// keyboard's Book a time can be tried end to end without booking a real
// person's calendar. Start it, then start the Glyf server with
//
//   PORT=8796 node qa/fake-scheduling.mjs
//   CALCOM_API_BASE=http://127.0.0.1:8796/v2 npm run dev
//
// Every page has open times each day at 10:00, 11:30, 15:00 and 17:30 in the
// zone asked for. GET /_log lists what was booked. Never deploy this; it
// exists only so a phone can exercise the real code.
import { createServer } from "node:http";

const PORT = Number(process.env.PORT ?? 8796);
const log = { bookings: [] };

function send(res, status, body) {
  res.writeHead(status, { "content-type": "application/json" });
  res.end(JSON.stringify(body));
}

/** The offset of a zone at a moment, as "+05:30". */
function offset(tz, at) {
  const parts = new Intl.DateTimeFormat("en-US", { timeZone: tz, timeZoneName: "longOffset" }).formatToParts(at);
  const name = parts.find(p => p.type === "timeZoneName")?.value ?? "GMT";
  const m = name.match(/GMT([+-]\d{2}):?(\d{2})?/);
  return m ? `${m[1]}:${m[2] ?? "00"}` : "+00:00";
}

function slots(start, end, tz) {
  const out = {};
  const d = new Date(`${start}T00:00:00Z`);
  const last = new Date(`${end}T00:00:00Z`);
  while (d <= last) {
    const day = d.toISOString().slice(0, 10);
    const off = offset(tz, d);
    out[day] = ["10:00", "11:30", "15:00", "17:30"].map(t => ({ start: `${day}T${t}:00.000${off}` }));
    d.setUTCDate(d.getUTCDate() + 1);
  }
  return out;
}

createServer((req, res) => {
  const url = new URL(req.url, `http://127.0.0.1:${PORT}`);
  let body = "";
  req.on("data", c => { body += c; });
  req.on("end", () => {
    console.log(`${req.method} ${url.pathname}${url.search}`);
    if (url.pathname === "/_log") return send(res, 200, log);
    if (url.pathname === "/_reset") {
      log.bookings.length = 0;
      return send(res, 200, log);
    }
    if (url.pathname === "/v2/slots") {
      const q = url.searchParams;
      if (!q.get("eventTypeSlug") || !q.get("username")) return send(res, 400, { status: "error" });
      return send(res, 200, { status: "success", data: slots(q.get("start"), q.get("end"), q.get("timeZone") || "UTC") });
    }
    if (url.pathname === "/v2/event-types") {
      return send(res, 200, { status: "success", data: [{ id: 1, slug: "30min", title: "30 min meeting", lengthInMinutes: 30 }] });
    }
    if (url.pathname === "/v2/bookings" && req.method === "POST") {
      const b = JSON.parse(body || "{}");
      if (!b.attendee?.email || !b.start) return send(res, 400, { status: "error", error: { message: "attendee.email is required" } });
      if (log.bookings.some(x => x.start === b.start && x.username === b.username)) {
        return send(res, 400, { status: "error", error: { message: "User either already has booking at this time or is not available" } });
      }
      log.bookings.push(b);
      const end = new Date(new Date(b.start).getTime() + 30 * 60_000).toISOString();
      return send(res, 201, { status: "success", data: {
        uid: `bk_${log.bookings.length}`, start: b.start, end,
        title: `30 min meeting between ${b.username} and ${b.attendee.name}`,
        meetingUrl: `https://app.cal.com/video/bk_${log.bookings.length}`,
      } });
    }
    send(res, 404, { status: "error" });
  });
}).listen(PORT, "127.0.0.1", () => console.log(`fake Cal.com on http://127.0.0.1:${PORT}`));

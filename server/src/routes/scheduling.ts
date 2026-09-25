import type { FastifyInstance } from "fastify";
import { z } from "zod";

/**
 * Booking links for the keyboard's calendar.
 *
 * Call links are Google Meet only, made by the keyboard itself with the
 * person's own Google grant (nothing here).
 *
 * Booking links: `GET /scheduling/slots?link=` reads a Cal.com or Calendly
 * link. Cal.com's API answers a public event's open times with no key (v2
 * /slots, 120 requests a minute without one), so each time comes back with a
 * link that opens straight on that slot. Calendly gives times only to the
 * host's own sign-in, so only its link comes back, on the day chosen.
 *
 * Booking with someone: `POST /scheduling/book` books a time on a Cal.com
 * page with the attendee's name and email and any guests' emails, the way
 * Cal.com's own page does, and Cal.com emails everyone the invite. No key.
 *
 * Invites for the keyboard's own events don't come through here: with
 * Google connected the keyboard adds the event to the person's Google
 * Calendar itself and Google emails the guests; without it, the event goes
 * into the message. Google's tokens stay on the phone.
 * Researched 2026-09-24; see docs/BACKEND.md.
 */

export interface BookingLink {
  provider: "calcom" | "calendly";
  /** The link without query or extra path: https://cal.com/jane/30min */
  base: string;
  username: string;
  slug?: string;
  /** physics for physics.cal.com: Cal.com organisations have their own host. */
  org?: string;
}

/** A Cal.com or Calendly booking link, however it was typed ("cal.com/jane",
 *  "https://calendly.com/jane/30min?month=…"); null for anything else. */
export function parseBookingLink(raw: string): BookingLink | null {
  let s = raw.trim();
  if (!s) return null;
  if (!/^https?:\/\//i.test(s)) s = `https://${s}`;
  let u: URL;
  try { u = new URL(s); } catch { return null; }
  const host = u.hostname.toLowerCase().replace(/^www\./, "");
  const parts = u.pathname.split("/").filter(Boolean).map(p => decodeURIComponent(p));
  if (parts.length < 1 || parts.some(p => !/^[\w.-]+$/.test(p))) return null;
  const [username, slug] = parts;
  if (host === "calendly.com") {
    return { provider: "calendly", base: `https://calendly.com/${[username, slug].filter(Boolean).join("/")}`, username, slug };
  }
  if (host === "cal.com" || host === "app.cal.com" || host.endsWith(".cal.com")) {
    const org = host.endsWith(".cal.com") && host !== "app.cal.com" ? host.slice(0, -".cal.com".length) : undefined;
    const shown = host === "app.cal.com" ? "cal.com" : host;
    return { provider: "calcom", base: `https://${shown}/${[username, slug].filter(Boolean).join("/")}`, username, slug, org };
  }
  return null;
}

/** The booking page on a day ("…?month=2026-09&date=2026-09-25"), and on one
 *  time when there is one: Cal.com goes straight to the form with `slot`. */
export function bookingUrl(link: BookingLink, date?: string, slotUtc?: string): string {
  const u = new URL(link.base);
  if (date) {
    u.searchParams.set("month", date.slice(0, 7));
    u.searchParams.set("date", date);
  }
  if (slotUtc && link.provider === "calcom") u.searchParams.set("slot", slotUtc);
  return u.toString();
}

/** `CALCOM_API_BASE` points at a fake for device tests; never set in production. */
const calApi = () => (process.env.CALCOM_API_BASE?.trim() || "https://api.cal.com/v2").replace(/\/$/, "");
const cache = new Map<string, { at: number; value: unknown }>();
const TTL_MS = 60_000;

function cached<T>(key: string): T | undefined {
  const hit = cache.get(key);
  if (hit && Date.now() - hit.at < TTL_MS) return hit.value as T;
  if (hit) cache.delete(key);
  return undefined;
}

function remember(key: string, value: unknown): void {
  if (cache.size > 500) cache.delete(cache.keys().next().value as string);
  cache.set(key, { at: Date.now(), value });
}

function validZone(tz: string): boolean {
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: tz });
    return true;
  } catch {
    return false;
  }
}

function addDays(date: string, n: number): string {
  const d = new Date(`${date}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}

interface CalEventType { slug: string; title?: string; lengthInMinutes?: number; hidden?: boolean; bookingUrl?: string }

async function calJson(path: string, version: string): Promise<unknown> {
  const res = await fetch(`${calApi()}${path}`, {
    headers: { "cal-api-version": version, accept: "application/json" },
    signal: AbortSignal.timeout(8000),
  });
  if (!res.ok) throw Object.assign(new Error(`cal.com ${res.status}`), { status: res.status });
  return res.json();
}

/** The event to book on a link with no event in it ("cal.com/jane"): the
 *  shortest one that is shown. */
async function firstEventType(link: BookingLink): Promise<CalEventType | null> {
  const q = new URLSearchParams({ username: link.username });
  if (link.org) q.set("organizationSlug", link.org);
  const body = await calJson(`/event-types?${q}`, "2026-06-12") as { data?: CalEventType[] };
  const shown = (body.data ?? []).filter(t => t.slug && !t.hidden);
  shown.sort((a, b) => (a.lengthInMinutes ?? 999) - (b.lengthInMinutes ?? 999));
  return shown[0] ?? null;
}

export interface SlotDay { date: string; slots: { start: string; url: string }[] }

/** What Cal.com said, when it said something a person can act on. */
function calMessage(body: unknown): string {
  const b = body as { error?: { message?: unknown } | string; message?: unknown } | null;
  const m = typeof b?.error === "object" ? b.error?.message : b?.error ?? b?.message;
  return typeof m === "string" ? m : Array.isArray(m) ? m.join(", ") : "";
}

export function schedulingRoutes(app: FastifyInstance) {
  const slotsQuery = z.object({
    link: z.string().min(3).max(300),
    date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
    days: z.coerce.number().int().min(1).max(7).default(3),
    tz: z.string().max(64).default("UTC"),
  });

  app.get("/scheduling/slots", async (req, reply) => {
    const parsed = slotsQuery.safeParse(req.query);
    if (!parsed.success) return reply.code(400).send({ error: "Bad request" });
    const { days } = parsed.data;
    const tz = validZone(parsed.data.tz) ? parsed.data.tz : "UTC";
    const date = parsed.data.date ?? new Date().toLocaleDateString("en-CA", { timeZone: tz });
    const link = parseBookingLink(parsed.data.link);
    if (!link) return reply.code(400).send({ error: "That isn't a Cal.com or Calendly link" });

    if (link.provider === "calendly") {
      // Times need the host's Calendly sign-in; the day itself does not.
      return { provider: "calendly", link: link.base, bookingUrl: bookingUrl(link, date), days: [] };
    }

    const key = `${link.base}|${date}|${days}|${tz}`;
    const hit = cached<object>(key);
    if (hit) return hit;
    try {
      let slug = link.slug;
      let title: string | undefined;
      let length: number | undefined;
      let base = link.base;
      if (!slug) {
        const type = await firstEventType(link);
        if (!type) return reply.code(404).send({ error: "No bookable event on that Cal.com link" });
        slug = type.slug;
        title = type.title;
        length = type.lengthInMinutes;
        // Cal.com's own page for it: a bare username can be someone in an
        // organisation, whose page lives on the organisation's host.
        const own = type.bookingUrl ? parseBookingLink(type.bookingUrl) : null;
        base = own?.provider === "calcom" && own.slug ? own.base : `${link.base.replace(/\/$/, "")}/${slug}`;
      }
      const full: BookingLink = { ...link, slug, base };
      // A day earlier than asked, so a zone ahead of UTC keeps its morning.
      const q = new URLSearchParams({
        eventTypeSlug: slug, username: link.username,
        start: addDays(date, -1), end: addDays(date, days), timeZone: tz,
      });
      if (link.org) q.set("organizationSlug", link.org);
      const body = await calJson(`/slots?${q}`, "2024-09-04") as { data?: Record<string, { start: string }[]> };
      const last = addDays(date, days);
      const out: SlotDay[] = Object.entries(body.data ?? {})
        .filter(([d]) => d >= date && d < last)
        .sort(([a], [b]) => a.localeCompare(b))
        .map(([d, slots]) => ({
          date: d,
          slots: slots.slice(0, 24).map(s => ({
            start: s.start,
            url: bookingUrl(full, d, new Date(s.start).toISOString()),
          })),
        }));
      const value = { provider: "calcom", link: full.base, bookingUrl: bookingUrl(full, date), title, length, days: out };
      remember(key, value);
      return value;
    } catch (err) {
      const status = (err as { status?: number }).status;
      if (status === 404) return reply.code(404).send({ error: "Cal.com doesn't know that link" });
      app.log.warn({ err: String(err) }, "cal.com slots failed");
      return reply.code(502).send({ error: "Cal.com didn't answer. Try again" });
    }
  });

  const bookBody = z.object({
    link: z.string().min(3).max(300),
    start: z.string().datetime({ offset: true }),
    name: z.string().trim().min(1).max(120),
    email: z.string().trim().email().max(200),
    guests: z.array(z.string().trim().email().max(200)).max(10).default([]),
    tz: z.string().max(64).default("UTC"),
    notes: z.string().trim().max(500).optional(),
  });

  app.post("/scheduling/book", async (req, reply) => {
    const parsed = bookBody.safeParse(req.body ?? {});
    if (!parsed.success) {
      const email = parsed.error.issues.some(i => i.path[0] === "email" || i.path[0] === "guests");
      return reply.code(400).send({ error: email ? "Check the email addresses" : "Bad request" });
    }
    const b = parsed.data;
    const link = parseBookingLink(b.link);
    if (!link) return reply.code(400).send({ error: "That isn't a Cal.com or Calendly link" });
    if (link.provider !== "calcom") {
      return reply.code(400).send({ error: "Calendly books only on its own page. Send the link instead" });
    }
    const tz = validZone(b.tz) ? b.tz : "UTC";
    try {
      let slug = link.slug;
      if (!slug) {
        const type = await firstEventType(link);
        if (!type) return reply.code(404).send({ error: "No bookable event on that Cal.com link" });
        slug = type.slug;
      }
      const body: Record<string, unknown> = {
        start: new Date(b.start).toISOString(),
        eventTypeSlug: slug,
        username: link.username,
        attendee: { name: b.name, email: b.email, timeZone: tz },
      };
      if (link.org) body.organizationSlug = link.org;
      if (b.guests.length) body.guests = [...new Set(b.guests.map(g => g.toLowerCase()))].filter(g => g !== b.email.toLowerCase());
      if (b.notes) body.bookingFieldsResponses = { notes: b.notes };
      const res = await fetch(`${calApi()}/bookings`, {
        method: "POST",
        headers: { "cal-api-version": "2026-02-25", "content-type": "application/json", accept: "application/json" },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(12_000),
      });
      const out = await res.json().catch(() => null) as { data?: Record<string, unknown> } | null;
      if (!res.ok) {
        const said = calMessage(out);
        app.log.warn({ status: res.status, said }, "cal.com booking refused");
        if (/available|booked|already|slot/i.test(said)) {
          return reply.code(409).send({ error: "That time was just taken. Pick another" });
        }
        if (/authenticat|owner|admin/i.test(said)) {
          return reply.code(403).send({ error: "This page only takes bookings on Cal.com itself. Send the link instead" });
        }
        return reply.code(502).send({ error: said ? `Cal.com said: ${said}` : "Cal.com couldn't book it. Try again" });
      }
      const d = out?.data ?? {};
      return {
        ok: true,
        uid: d.uid, start: d.start ?? body.start, end: d.end,
        title: d.title, meetingUrl: d.meetingUrl ?? d.location,
        invited: [b.email, ...b.guests],
      };
    } catch (err) {
      app.log.warn({ err: String(err) }, "cal.com booking failed");
      return reply.code(502).send({ error: "Cal.com didn't answer. Try again" });
    }
  });
}

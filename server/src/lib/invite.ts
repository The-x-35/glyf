import { randomUUID } from "node:crypto";

/**
 * A calendar invitation (iCalendar, RFC 5545, METHOD:REQUEST): the file
 * Gmail, Outlook and Apple Mail read as an invite with Yes, Maybe and No.
 * The keyboard's New Event sends one to its invitees through
 * `POST /invites/send`; the phone's own calendar can't invite anyone (iOS
 * gives apps no way to add attendees), so the invite comes from here.
 */

export interface InviteEvent {
  title: string;
  start: Date;
  end: Date;
  allDay: boolean;
  /** Where, or the call link. */
  location?: string;
  description?: string;
  /** The zone the day of an all-day event is counted in. */
  timeZone: string;
  organizer: { name?: string; email: string };
  attendees: string[];
  uid?: string;
  now?: Date;
}

/** Commas, semicolons, backslashes and line breaks are escaped in text. */
export function escapeText(s: string): string {
  return s.replace(/\\/g, "\\\\").replace(/;/g, "\\;").replace(/,/g, "\\,").replace(/\r?\n/g, "\\n");
}

/** Lines are folded at 75 octets, the rest carried on lines that start with a space. */
export function fold(line: string): string {
  const bytes = Buffer.from(line, "utf8");
  if (bytes.length <= 75) return line;
  const parts: string[] = [];
  let start = 0;
  let limit = 75;
  while (start < bytes.length) {
    let end = Math.min(start + limit, bytes.length);
    // Never split a UTF-8 character: back up to the start of one.
    while (end < bytes.length && (bytes[end] & 0xc0) === 0x80) end--;
    parts.push(bytes.subarray(start, end).toString("utf8"));
    start = end;
    limit = 74; // the leading space counts
  }
  return parts.join("\r\n ");
}

function utcStamp(d: Date): string {
  return d.toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, "");
}

/** The calendar date of an instant in a zone: 20260925. */
function dateIn(d: Date, timeZone: string): string {
  return d.toLocaleDateString("en-CA", { timeZone }).replace(/-/g, "");
}

function quoteParam(s: string): string {
  // A parameter value with ; , or : must be quoted, and can't hold a quote.
  const clean = s.replace(/"/g, "'");
  return /[;,:]/.test(clean) ? `"${clean}"` : clean;
}

export function buildInvite(e: InviteEvent): string {
  const now = e.now ?? new Date();
  const lines = [
    "BEGIN:VCALENDAR",
    "PRODID:-//Glyf//Keyboard//EN",
    "VERSION:2.0",
    "CALSCALE:GREGORIAN",
    "METHOD:REQUEST",
    "BEGIN:VEVENT",
    `UID:${e.uid ?? `${randomUUID()}@tryglyf.com`}`,
    `DTSTAMP:${utcStamp(now)}`,
  ];
  if (e.allDay) {
    lines.push(`DTSTART;VALUE=DATE:${dateIn(e.start, e.timeZone)}`);
    // The end date is the day after the last one, as calendars count it.
    const lastDay = new Date(Math.max(e.end.getTime() - 1, e.start.getTime()));
    const after = new Date(`${dateIn(lastDay, e.timeZone).replace(/(\d{4})(\d{2})(\d{2})/, "$1-$2-$3")}T00:00:00Z`);
    after.setUTCDate(after.getUTCDate() + 1);
    lines.push(`DTEND;VALUE=DATE:${after.toISOString().slice(0, 10).replace(/-/g, "")}`);
  } else {
    lines.push(`DTSTART:${utcStamp(e.start)}`, `DTEND:${utcStamp(e.end)}`);
  }
  lines.push(`SUMMARY:${escapeText(e.title)}`);
  if (e.location) lines.push(`LOCATION:${escapeText(e.location)}`);
  if (e.description) lines.push(`DESCRIPTION:${escapeText(e.description)}`);
  const cn = e.organizer.name ? `;CN=${quoteParam(e.organizer.name)}` : "";
  lines.push(`ORGANIZER${cn}:mailto:${e.organizer.email}`);
  for (const a of e.attendees) {
    lines.push(`ATTENDEE;CN=${quoteParam(a)};ROLE=REQ-PARTICIPANT;PARTSTAT=NEEDS-ACTION;RSVP=TRUE:mailto:${a}`);
  }
  lines.push("STATUS:CONFIRMED", "SEQUENCE:0", "TRANSP:OPAQUE", "END:VEVENT", "END:VCALENDAR");
  return lines.map(fold).join("\r\n") + "\r\n";
}

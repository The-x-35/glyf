/** The keyboard's calendar, as the apps have it: the day's events, a plan
 *  read out of a line ("investor meet at 10pm"), the strip chip's words and
 *  what an event puts in the message. A port of the iOS keyboard's
 *  EventParse.swift and CalendarText.swift, in a US English locale (the
 *  demo's examples are American). Pure, like data.ts. */

export type CalEvent = {
  id: string;
  title: string;
  start: Date;
  end: Date;
  allDay?: boolean;
  /** The calendar's colour, for the bar down the row. */
  color?: string;
  location?: string;
};

export type Plan = { title: string; start: Date; end: Date; allDay: boolean; hasDay: boolean; hasTime: boolean };

const MIN = 60_000;

export const startOfDay = (d: Date) => new Date(d.getFullYear(), d.getMonth(), d.getDate());
export const addDays = (d: Date, n: number) => new Date(d.getFullYear(), d.getMonth(), d.getDate() + n, d.getHours(), d.getMinutes());
export const sameDay = (a: Date, b: Date) =>
  a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
const at = (day: Date, h: number, m = 0) => new Date(day.getFullYear(), day.getMonth(), day.getDate(), h, m);

/** iOS and new ICU put a narrow no-break space before AM/PM; the demo writes a plain one. */
const plain = (s: string) => s.replace(/[\u202f\u00a0]/g, " ");

/** "10:00 PM" (CalendarText.clock, short time). */
export const clock = (d: Date) => plain(new Intl.DateTimeFormat("en-US", { hour: "numeric", minute: "2-digit" }).format(d));

/** "Mon, Oct 5" (CalendarText.dayLabel: the "EEE d MMM" template in en-US). */
export const dayLabel = (d: Date) =>
  plain(new Intl.DateTimeFormat("en-US", { weekday: "short", month: "short", day: "numeric" }).format(d));

/** "October 5" (CalendarSurface.dateText, Insert date). */
export const dateText = (d: Date) => new Intl.DateTimeFormat("en-US", { month: "long", day: "numeric" }).format(d);

/** "October 2026", the month grid's title. */
export const monthLabel = (d: Date) => new Intl.DateTimeFormat("en-US", { month: "long", year: "numeric" }).format(d);

/** "10:00–11:00 PM": one AM/PM when both ends share it (CalendarText.range). */
export function range(a: Date, b: Date): string {
  const x = clock(a);
  const y = clock(b);
  const suffix = [" AM", " PM"].find((s) => x.endsWith(s) && y.endsWith(s));
  return suffix ? `${x.slice(0, -suffix.length)}–${y}` : `${x}–${y}`;
}

/** "📅 Investor meet · Mon, Oct 5, 10:00–11:00 PM" (CalendarText.insert). */
export function insertText(e: CalEvent): string {
  const day = dayLabel(e.start);
  const when = e.allDay ? day : `${day}, ${range(e.start, e.end)}`;
  return [`📅 ${e.title}`, when, e.location].filter(Boolean).join(" · ");
}

/** "Investor meet · Today 10:00 PM": the strip chip's words (EventParse.summary). */
export function summary(p: Plan, now = new Date()): string {
  const day = sameDay(p.start, now) ? "Today" : sameDay(p.start, addDays(now, 1)) ? "Tomorrow" : dayLabel(p.start);
  const when = p.allDay ? day : `${day} ${clock(p.start)}`;
  return p.title ? `${p.title} · ${when}` : when;
}

/* ── The day ─────────────────────────────────────────────── */

/** The tour's practice day, as the app has it (CalendarText.practiceDay):
 *  three plain events and an open evening, so 10 PM is free. */
export function sampleEvents(now = new Date()): CalEvent[] {
  const today = startOfDay(now);
  return [
    { id: "standup", title: "Standup", start: at(today, 10), end: at(today, 10, 15) },
    { id: "lunch", title: "Lunch with Sam", start: at(today, 13), end: at(today, 14) },
    { id: "gym", title: "Gym", start: at(today, 18, 30), end: at(today, 19, 30) },
  ];
}

/** Everything that touches the day, all-day events first (CalendarText.events(on:)). */
export function eventsOn(day: Date, all: CalEvent[]): CalEvent[] {
  const start = startOfDay(day);
  const end = addDays(start, 1);
  return all
    .filter((e) => e.start < end && (e.end > start || (+e.end === +e.start && e.start >= start)))
    .sort((a, b) => (a.allDay ? 0 : 1) - (b.allDay ? 0 : 1) || +a.start - +b.start);
}

/** When the day has room, between 9 AM and 9 PM, in a sentence (CalendarText.freeTime). */
export function freeTime(day: Date, all: CalEvent[], now = new Date()): string {
  const label = dayLabel(day);
  const dayStart = startOfDay(day);
  let open = at(dayStart, 9);
  const close = at(dayStart, 21);
  let startsNow = false;
  if (sameDay(now, day) && now > open) {
    startsNow = true;
    const half = Math.ceil((+now - +dayStart) / (30 * MIN)) * 30 * MIN;
    open = new Date(+dayStart + half);
    if (open >= close) return "I'm done for today";
  }
  const busy = eventsOn(day, all);
  if (busy.some((e) => e.allDay)) return `I'm busy all day ${label}`;
  const gaps: [Date, Date][] = [];
  let cursor = open;
  for (const e of [...busy].sort((a, b) => +a.start - +b.start)) {
    const s = e.start > open ? e.start : open;
    const f = e.end < close ? e.end : close;
    if (f <= s) continue;
    if (+s - +cursor >= 30 * MIN) gaps.push([cursor, s]);
    if (f > cursor) cursor = f;
  }
  if (+close - +cursor >= 30 * MIN) gaps.push([cursor, close]);
  if (!gaps.length) return `I'm booked ${label}`;
  if (!startsNow && gaps.length === 1 && +gaps[0][0] === +open && +gaps[0][1] === +close) return `I'm free all day ${label}`;
  const parts = gaps.map(([a, b]) => range(a, b));
  const list = parts.length > 1 ? `${parts.slice(0, -1).join(", ")} and ${parts[parts.length - 1]}` : parts[0];
  return `I'm free ${label}, ${list}`;
}

/** The month's cells, Sunday first: null before the 1st and after the last. */
export function monthCells(month: Date): (Date | null)[] {
  const first = new Date(month.getFullYear(), month.getMonth(), 1);
  const days = new Date(month.getFullYear(), month.getMonth() + 1, 0).getDate();
  const cells: (Date | null)[] = Array.from({ length: first.getDay() }, () => null);
  for (let i = 1; i <= days; i++) cells.push(new Date(month.getFullYear(), month.getMonth(), i));
  while (cells.length % 7) cells.push(null);
  return cells;
}

/* ── A plan in a line (EventParse.parse, the English half) ── */

class Work {
  text: string;
  constructor(s: string) {
    this.text = s;
  }
  /** The first match's groups, lowercased, and the match blanked out where it stood. */
  take(re: RegExp): string[] | null {
    const m = re.exec(this.text);
    if (!m) return null;
    this.text = this.text.slice(0, m.index) + " ".repeat(m[0].length) + this.text.slice(m.index + m[0].length);
    return m.map((g) => (g ?? "").toLowerCase());
  }
  title(): string {
    let t = this.text.replace(/\s+/g, " ");
    t = t.replace(/^\s*(?:hey|hi|so|ok|okay|yo|good morning|good evening|gm)[,!.]*\s+/i, "");
    t = t.replace(/^\s*(?:(?:let[’']?s|lets|let us|shall we|should we|can we|could we|we should|how about|what about|maybe|pls|please|remind me to|reminder to|reminder:?)\s+)+/i, "");
    for (let i = 0; i < 3; i++) {
      t = t.replace(/(?:\s+(?:at|on|for|from|by|around|in|this|next|the|and|,|-|–))+\s*$/i, "");
      t = t.replace(/^[\s,.;:!?\-–]+|[\s,.;:!?\-–]+$/g, "");
    }
    t = t.replace(/^(?:on|at|by)\s+/i, "").replace(/\s+([,.!?])/g, "$1");
    return t ? t[0].toUpperCase() + t.slice(1) : "";
  }
}

const WEEKDAY: Record<string, number> = { sun: 0, mon: 1, tue: 2, wed: 3, thu: 4, fri: 5, sat: 6 };

/** Minutes after midnight for "5", "5:30", with a meridiem when one was given. */
function minutesOf(h: string, m: string, mer: string | null, pm: boolean | null): number | null {
  let hour = Number(h);
  const minute = Number(m || 0);
  if (!Number.isFinite(hour) || hour > 23 || minute >= 60) return null;
  if (mer) {
    if (hour < 1 || hour > 12) return null;
    if (mer === "pm" && hour < 12) hour += 12;
    if (mer === "am" && hour === 12) hour = 0;
  } else if (hour <= 12) {
    const isPM = pm ?? (hour <= 7 || hour === 12);
    if (isPM && hour < 12) hour += 12;
  }
  return hour * 60 + minute;
}

export function parsePlan(text: string, now = new Date()): Plan {
  const w = new Work(text);
  let allDay = false;
  let dayOffset: number | null = null;
  let weekday: { wd: number; next: boolean; self: boolean } | null = null;
  let minutes: number | null = null;
  let endMinutes: number | null = null;
  let bare: [number, number] | null = null;
  let part: number | null = null;
  let pm: boolean | null = null;
  let duration: number | null = null;

  if (w.take(/\b(all[ -]?day|whole day|full day)\b/i)) allDay = true;
  const dur = w.take(/\bfor\s+(\d+(?:\.\d+)?|an?|half an?)\s*(minutes?|mins?|hours?|hrs?|h)\b/i);
  if (dur) {
    const n = dur[1] === "a" || dur[1] === "an" ? 1 : dur[1].startsWith("half") ? 0.5 : Number(dur[1]);
    duration = Math.round(dur[2].startsWith("h") ? n * 60 : n);
  }
  // Parts of the day: a time of their own, and whether 8 means 8 PM. "Good
  // morning" is a greeting and "last night" is gone: neither is a plan.
  // (No lookbehind: Safari before 16.4 can't parse one.)
  const p = w.take(/\b(?:(good|last)\s+)?(?:this\s+|in the\s+)?(morning|afternoon|evening|tonight|night)\b/i);
  if (p && !p[1]) {
    part = ({ morning: 9, afternoon: 15, evening: 18 } as Record<string, number>)[p[2]] ?? 20;
    part *= 60;
    pm = p[2] !== "morning";
    if (p[2] === "tonight") dayOffset = 0;
  }

  const hm = String.raw`(\d{1,2})(?:[:.](\d{2}))?`;
  const r =
    w.take(new RegExp(String.raw`\b(?:from\s+)?${hm}\s*(am|pm)?\s*(?:-|–|to|till|until)\s*${hm}\s*(am|pm)\b`, "i")) ??
    w.take(new RegExp(String.raw`\bfrom\s+${hm}\s*(am|pm)?\s*(?:-|–|to|till|until)\s*${hm}\s*(am|pm)?\b`, "i"));
  if (r) {
    const endMer = r[6] || null;
    const startMer = r[3] || endMer;
    const s = minutesOf(r[1], r[2], startMer, pm);
    const e = minutesOf(r[4], r[5], endMer, pm);
    if (s !== null && e !== null) {
      minutes = !r[3] && s > e && s >= 720 ? s - 720 : s;
      endMinutes = e;
    }
  }
  if (minutes === null) {
    const m = w.take(new RegExp(String.raw`\b(?:at\s+|@\s*|around\s+|by\s+)?${hm}\s*(am|pm|a\.m\.?|p\.m\.?)(?![a-z])`, "i"));
    if (m) minutes = minutesOf(m[1], m[2], m[3].startsWith("p") ? "pm" : "am", pm);
  }
  if (minutes === null) {
    const m = w.take(/\b(?:at\s+|@\s*|around\s+|by\s+)?(\d{1,2}):(\d{2})\b/i);
    if (m) {
      const h = Number(m[1]);
      const mm = Number(m[2]);
      if ((h >= 13 && h <= 23) || h === 0) minutes = h * 60 + mm;
      else if (h <= 12) bare = [h, mm];
    }
  }
  if (minutes === null && !bare) {
    const m = w.take(/\b(?:at|@|around)\s+(\d{1,2})(?:[:.](\d{2}))?\b(?!\s*(?:%|\/|st\b|nd\b|rd\b|th\b|people|mins?|minutes|hours?|hrs?))/i);
    if (m) bare = [Number(m[1]), Number(m[2] || 0)];
  }
  if (minutes === null && !bare) {
    const m = w.take(/\b(noon|midday|midnight)\b/i);
    if (m) {
      if (m[1] === "midnight") {
        minutes = 0;
        dayOffset = (dayOffset ?? 0) + 1;
      } else minutes = 720;
    }
  }
  if (pm === null && bare) {
    if (/\b(dinner|drinks|party|movie|club)\b/i.test(text)) pm = true;
    if (/\bbreakfast\b/i.test(text)) pm = false;
  }
  if (bare && bare[0] >= 1 && bare[0] <= 12 && bare[1] < 60) {
    let h = bare[0];
    const isPM = pm ?? (h <= 7 || h === 12);
    if (isPM && h < 12) h += 12;
    if (!isPM && h === 12) h = 0;
    minutes = h * 60 + bare[1];
  }

  if (w.take(/\bday after (?:tomorrow|tmrw)\b/i)) dayOffset = 2;
  if (w.take(/\b(tomorrow|tomorow|tmrw|tmr|tomo)\b/i)) dayOffset = 1;
  if (w.take(/\btoday\b/i)) dayOffset = 0;
  const full = w.take(/\b(?:(this|next|coming|on)\s+)?(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b/i);
  const short = full ? null : w.take(/\b(this|next|coming|on|by)\s+(mon|tue|tues|wed|thu|thur|thurs|fri|sat|sun)\b/i);
  const named = full ?? short;
  if (named) weekday = { wd: WEEKDAY[named[2].slice(0, 3)], next: named[1] === "next", self: named[1] === "this" };
  if (!weekday && dayOffset === null && w.take(/\bnext week\b/i)) dayOffset = 7;
  if (!weekday && dayOffset === null && w.take(/\b(?:this\s+)?weekend\b/i)) weekday = { wd: 6, next: false, self: true };

  const today = startOfDay(now);
  let day: Date | null = null;
  if (weekday) {
    let ahead = (weekday.wd - today.getDay() + 7) % 7;
    if (ahead === 0 && !weekday.self) ahead = 7;
    if (weekday.next && ahead < 7 - today.getDay()) ahead += 7;
    day = addDays(today, ahead);
  } else if (dayOffset !== null) day = addDays(today, dayOffset);
  const hasDay = day !== null;
  const hasTime = !allDay && (minutes !== null || (part !== null && hasDay));
  if (minutes === null && part !== null) minutes = part;

  const title = w.title();
  if (!hasTime && !allDay) {
    const meal = ([["breakfast", 540], ["brunch", 660], ["lunch", 780], ["dinner", 1200]] as const).find(([word]) =>
      new RegExp(`\\b${word}\\b`, "i").test(title),
    );
    if (meal) minutes = meal[1];
  }

  const startDay = day ?? today;
  let start: Date;
  if (allDay) start = startDay;
  else if (minutes !== null) {
    start = at(startDay, 0, minutes);
    // A time with no day is the next time it comes round.
    if (!hasDay && start <= now) start = addDays(start, 1);
  } else if (hasDay && !sameDay(startDay, today)) start = at(startDay, 9);
  // Nothing said when: the next whole hour, like Calendar's own New Event.
  else start = at(now, now.getHours() + 1);

  let end: Date;
  if (allDay) end = addDays(start, 1);
  else if (endMinutes !== null) {
    end = at(startOfDay(start), 0, endMinutes);
    if (end <= start) end = addDays(end, 1);
  } else end = new Date(+start + (duration ?? 60) * MIN);
  return { title, start, end, allDay, hasDay, hasTime };
}

const INTENT =
  /\b(let[’']?s|lets|shall we|should we|can we|could we|meet|meeting|call|catch up|see you|see u|dinner|lunch|breakfast|brunch|coffee|drinks|party|appointment|interview|standup|sync|review|demo|class|session|gym|workout|yoga|movie|movies|film|concert|flight|dentist|doctor|haircut|game|match|pickup)\b/i;

/** A plan worth offering to put in the calendar: a time, and a day or a
 *  word that makes it a plan (EventParse.looksLikePlan). */
export function looksLikePlan(text: string, now = new Date()): Plan | null {
  if (text.includes("📅") || /\bI[’']?m (free|busy|booked|done)\b/i.test(text)) return null;
  if (/\bin\s+(?:\d+|an?|a few|few|couple of)\s*(?:minutes?|mins?)\b/i.test(text)) return null;
  const p = parsePlan(text, now);
  if (!p.hasTime) return null;
  return p.hasDay || INTENT.test(text) ? p : null;
}

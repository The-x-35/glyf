import { afterEach, describe, expect, it, vi } from "vitest";
import { bookingUrl, jitsiLink, parseBookingLink } from "../src/routes/scheduling.js";
import { signedInApp } from "./helpers.js";

const savedDaily = process.env.DAILY_API_KEY;

afterEach(() => {
  vi.restoreAllMocks();
  if (savedDaily === undefined) delete process.env.DAILY_API_KEY; else process.env.DAILY_API_KEY = savedDaily;
});

/** A fetch that answers from a table of URL prefixes, and records what it was asked. */
function fakeFetch(table: Record<string, { status?: number; body: unknown }>) {
  const asked: { url: string; init?: RequestInit }[] = [];
  vi.spyOn(globalThis, "fetch").mockImplementation(async (input: string | URL | Request, init?: RequestInit) => {
    const url = String(input);
    asked.push({ url, init });
    const hit = Object.entries(table).find(([prefix]) => url.startsWith(prefix));
    if (!hit) return new Response("{}", { status: 404 });
    return new Response(JSON.stringify(hit[1].body), {
      status: hit[1].status ?? 200, headers: { "content-type": "application/json" },
    });
  });
  return asked;
}

describe("booking links", () => {
  it("reads Cal.com and Calendly links however they were typed", () => {
    expect(parseBookingLink("cal.com/jane/30min")).toEqual({
      provider: "calcom", base: "https://cal.com/jane/30min", username: "jane", slug: "30min", org: undefined,
    });
    expect(parseBookingLink("https://app.cal.com/jane")?.base).toBe("https://cal.com/jane");
    expect(parseBookingLink("physics.cal.com/rick/15min")).toMatchObject({ org: "physics", username: "rick", slug: "15min" });
    expect(parseBookingLink("https://calendly.com/jane/intro?month=2026-09")).toEqual({
      provider: "calendly", base: "https://calendly.com/jane/intro", username: "jane", slug: "intro",
    });
    expect(parseBookingLink("cal.com")).toBeNull();
    expect(parseBookingLink("example.com/jane")).toBeNull();
    expect(parseBookingLink("cal.com/jane/<script>")).toBeNull();
  });

  it("opens the page on a day, and Cal.com on the time itself", () => {
    const cal = parseBookingLink("cal.com/jane/30min")!;
    expect(bookingUrl(cal, "2026-10-06", "2026-10-06T08:40:00.000Z"))
      .toBe("https://cal.com/jane/30min?month=2026-10&date=2026-10-06&slot=2026-10-06T08%3A40%3A00.000Z");
    const calendly = parseBookingLink("calendly.com/jane/intro")!;
    expect(bookingUrl(calendly, "2026-09-25", "2026-09-25T10:00:00.000Z"))
      .toBe("https://calendly.com/jane/intro?month=2026-09&date=2026-09-25");
  });
});

describe("POST /meetings/new", () => {
  it("makes a Jitsi link when there is no Daily key", async () => {
    delete process.env.DAILY_API_KEY;
    const res = await signedInApp().inject({ method: "POST", url: "/meetings/new", payload: {} });
    expect(res.statusCode).toBe(200);
    expect(res.json().provider).toBe("jitsi");
    expect(res.json().url).toMatch(/^https:\/\/meet\.jit\.si\/Glyf-[A-Za-z0-9]{10}$/);
    expect(jitsiLink()).not.toBe(jitsiLink());
  });

  it("makes a Daily room with the key, and falls back to Jitsi when Daily says no", async () => {
    process.env.DAILY_API_KEY = "daily-test";
    const asked = fakeFetch({ "https://api.daily.co/v1/rooms": { body: { url: "https://glyf.daily.co/abc123" } } });
    const res = await signedInApp().inject({ method: "POST", url: "/meetings/new", payload: {} });
    expect(res.json()).toEqual({ url: "https://glyf.daily.co/abc123", provider: "daily" });
    expect((asked[0].init?.headers as Record<string, string>).authorization).toBe("Bearer daily-test");

    vi.restoreAllMocks();
    fakeFetch({ "https://api.daily.co/v1/rooms": { status: 401, body: { error: "authentication-error" } } });
    const fallback = await signedInApp().inject({ method: "POST", url: "/meetings/new", payload: {} });
    expect(fallback.json().provider).toBe("jitsi");
  });

  it("is behind the session gate", async () => {
    const { buildApp } = await import("../src/index.js");
    const res = await buildApp().inject({ method: "POST", url: "/meetings/new", payload: {} });
    expect(res.statusCode).toBe(401);
  });
});

describe("GET /scheduling/slots", () => {
  it("gives Calendly's link on the day, since its times need the host's sign-in", async () => {
    const asked = fakeFetch({});
    const res = await signedInApp().inject({
      method: "GET", url: "/scheduling/slots?link=calendly.com/jane/intro&date=2026-09-25&tz=Asia/Kolkata",
    });
    expect(res.json()).toEqual({
      provider: "calendly", link: "https://calendly.com/jane/intro",
      bookingUrl: "https://calendly.com/jane/intro?month=2026-09&date=2026-09-25", days: [],
    });
    expect(asked).toHaveLength(0);
  });

  it("gives Cal.com's open times, each opening straight on the slot", async () => {
    const asked = fakeFetch({
      "https://api.cal.com/v2/slots": { body: { status: "success", data: {
        "2026-09-27": [{ start: "2026-09-27T23:30:00.000+05:30" }],
        "2026-09-28": [{ start: "2026-09-28T19:00:00.000+05:30" }, { start: "2026-09-28T19:30:00.000+05:30" }],
        "2026-09-29": [{ start: "2026-09-29T10:00:00.000+05:30" }],
      } } },
    });
    const res = await signedInApp().inject({
      method: "GET", url: "/scheduling/slots?link=cal.com/slot-test/30min&date=2026-09-28&days=1&tz=Asia/Kolkata",
    });
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.provider).toBe("calcom");
    expect(body.days).toEqual([{
      date: "2026-09-28",
      slots: [
        { start: "2026-09-28T19:00:00.000+05:30",
          url: "https://cal.com/slot-test/30min?month=2026-09&date=2026-09-28&slot=2026-09-28T13%3A30%3A00.000Z" },
        { start: "2026-09-28T19:30:00.000+05:30",
          url: "https://cal.com/slot-test/30min?month=2026-09&date=2026-09-28&slot=2026-09-28T14%3A00%3A00.000Z" },
      ],
    }]);
    const url = new URL(asked[0].url);
    expect(url.searchParams.get("eventTypeSlug")).toBe("30min");
    expect(url.searchParams.get("username")).toBe("slot-test");
    expect(url.searchParams.get("start")).toBe("2026-09-27");
    expect(url.searchParams.get("timeZone")).toBe("Asia/Kolkata");
    expect((asked[0].init?.headers as Record<string, string>)["cal-api-version"]).toBe("2024-09-04");
  });

  it("picks the shortest shown event when the link names none", async () => {
    const asked = fakeFetch({
      "https://api.cal.com/v2/event-types": { body: { status: "success", data: [
        { slug: "60min", title: "Hour", lengthInMinutes: 60 },
        { slug: "secret", title: "Hidden", lengthInMinutes: 5, hidden: true },
        { slug: "15min", title: "Quick chat", lengthInMinutes: 15 },
      ] } },
      "https://api.cal.com/v2/slots": { body: { status: "success", data: {} } },
    });
    const res = await signedInApp().inject({
      method: "GET", url: "/scheduling/slots?link=cal.com/pick-test&date=2026-09-28&tz=UTC",
    });
    expect(res.json()).toMatchObject({ provider: "calcom", link: "https://cal.com/pick-test/15min", title: "Quick chat", length: 15, days: [] });
    expect(new URL(asked[1].url).searchParams.get("eventTypeSlug")).toBe("15min");
  });

  it("says what went wrong in words", async () => {
    const bad = await signedInApp().inject({ method: "GET", url: "/scheduling/slots?link=example.com/jane" });
    expect(bad.statusCode).toBe(400);
    expect(bad.json().error).toBe("That isn't a Cal.com or Calendly link");
    fakeFetch({ "https://api.cal.com/v2/slots": { status: 404, body: { status: "error" } } });
    const gone = await signedInApp().inject({ method: "GET", url: "/scheduling/slots?link=cal.com/nobody-here/30min&date=2026-09-28" });
    expect(gone.statusCode).toBe(404);
    expect(gone.json().error).toBe("Cal.com doesn't know that link");
  });
});

describe("POST /scheduling/book", () => {
  const base = {
    link: "cal.com/book-test/30min", start: "2026-09-28T13:30:00.000Z",
    name: "Sam Lee", email: "sam@example.com", tz: "Asia/Kolkata",
  };

  it("books on Cal.com with the attendee and guests, and Cal.com emails them", async () => {
    const asked = fakeFetch({ "https://api.cal.com/v2/bookings": { body: { status: "success", data: {
      uid: "bk_1", start: "2026-09-28T13:30:00.000Z", end: "2026-09-28T14:00:00.000Z",
      title: "30 min between Jane and Sam Lee", meetingUrl: "https://app.cal.com/video/bk_1",
    } } } });
    const res = await signedInApp().inject({ method: "POST", url: "/scheduling/book",
      payload: { ...base, guests: ["ria@example.com", "SAM@example.com"] } });
    expect(res.statusCode).toBe(200);
    expect(res.json()).toMatchObject({ ok: true, uid: "bk_1", meetingUrl: "https://app.cal.com/video/bk_1" });
    const sent = JSON.parse(String(asked[0].init?.body));
    expect(sent).toEqual({
      start: "2026-09-28T13:30:00.000Z", eventTypeSlug: "30min", username: "book-test",
      attendee: { name: "Sam Lee", email: "sam@example.com", timeZone: "Asia/Kolkata" },
      guests: ["ria@example.com"],
    });
    expect((asked[0].init?.headers as Record<string, string>)["cal-api-version"]).toBe("2026-02-25");
  });

  it("says a taken time plainly, and keeps Calendly to its own page", async () => {
    fakeFetch({ "https://api.cal.com/v2/bookings": { status: 400,
      body: { status: "error", error: { message: "User either already has booking at this time or is not available" } } } });
    const taken = await signedInApp().inject({ method: "POST", url: "/scheduling/book", payload: base });
    expect(taken.statusCode).toBe(409);
    expect(taken.json().error).toBe("That time was just taken. Pick another");
    const calendly = await signedInApp().inject({ method: "POST", url: "/scheduling/book",
      payload: { ...base, link: "calendly.com/jane/intro" } });
    expect(calendly.statusCode).toBe(400);
    const bad = await signedInApp().inject({ method: "POST", url: "/scheduling/book", payload: { ...base, email: "not-an-email" } });
    expect(bad.json().error).toBe("Check the email addresses");
  });
});

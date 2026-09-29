import { afterEach, beforeEach, describe, expect, it } from "vitest";
import {
  extractCode, extractLink, htmlToText, parseFrom, setTempMailFetch, signInbox, toMessage, verifyInbox,
} from "../src/lib/tempmail.js";
import { signedInApp, testToken } from "./helpers.js";

describe("reading a temp mail", () => {
  it("finds the one-time code people are waiting for", () => {
    const cases: [string, string, string | undefined][] = [
      ["Your verification code", "Your code is 482913. It expires in 10 minutes.", "482913"],
      ["482913 is your Instagram code", "", "482913"],
      ["Welcome to Google", "G-482913 is your Google verification code.", "G-482913"],
      ["Sign in to Acme", "Use 123 456 to sign in.", "123456"],
      ["Security code", "Your one-time passcode: 7391", "7391"],
      ["Confirm your email", "Enter this code to confirm your account:\n\n  90217\n\nThanks", "90217"],
      // Numbers that are not codes.
      ["Your order shipped", "Order #48291376 is on its way. Questions? Call 555-123-4567.", undefined],
      ["Autumn sale", "Our 2026 sale: 50% off everything, now $1299.", undefined],
      ["Meeting", "See you at 10:30 on 29/09/2026 in room 204.", undefined],
    ];
    for (const [subject, text, code] of cases) expect(extractCode(subject, text), `${subject} | ${text}`).toBe(code);
  });

  it("finds the link a mail asks to be opened, not its logo", () => {
    const html = `<a href="https://acme.com"><img src="logo.png"></a>
      <a href="https://acme.com/v?t=abc&amp;u=1">Verify email</a>`;
    expect(extractLink("", html)).toBe("https://acme.com/v?t=abc&u=1");
    expect(extractLink("Confirm here: https://x.io/confirm/123.", "")).toBe("https://x.io/confirm/123");
    expect(extractLink("Visit https://acme.com for more", "")).toBeUndefined();
  });

  it("turns HTML into text and a sender into a name", () => {
    expect(htmlToText("<style>p{}</style><p>Hi&nbsp;there</p><p>Code: <b>1234</b></p>")).toBe("Hi there\nCode: 1234");
    expect(parseFrom('"Acme" <no-reply@acme.com>')).toEqual({ name: "Acme", address: "no-reply@acme.com" });
    expect(parseFrom("no-reply@acme.com")).toEqual({ name: "", address: "no-reply@acme.com" });
    const m = toMessage({ id: "1", from: '"Acme" <a@acme.com>', subject: "Your code", body_html: "<p>Code 551234</p>",
      created_at: "2026-09-30T10:00:00Z" });
    expect(m).toMatchObject({ from: "Acme", fromAddress: "a@acme.com", text: "Code 551234", code: "551234" });
  });

  it("lets only the account that made an address read it, and only while it lives", () => {
    const exp = Date.now() + 3600_000;
    const token = signInbox("google:a", "x@temp.io", exp);
    expect(verifyInbox("google:a", "x@temp.io", token)).toBe(true);
    expect(verifyInbox("google:a", "X@Temp.io", token)).toBe(true);
    expect(verifyInbox("google:b", "x@temp.io", token)).toBe(false);
    expect(verifyInbox("google:a", "y@temp.io", token)).toBe(false);
    expect(verifyInbox("google:a", "x@temp.io", token, exp + 1000)).toBe(false);
    expect(verifyInbox("google:a", "x@temp.io", "garbage")).toBe(false);
  });
});

describe("POST /tempmail", () => {
  const key = process.env.TEMP_MAIL_API_KEY;
  let calls: { method: string; path: string; body?: string }[];
  let inbox: unknown[];

  beforeEach(() => {
    process.env.TEMP_MAIL_API_KEY = "test-key";
    calls = [];
    inbox = [];
    setTempMailFetch(async (input, init) => {
      const url = new URL(String(input));
      calls.push({ method: init?.method ?? "GET", path: url.pathname, body: init?.body as string | undefined });
      const headers = (init?.headers ?? {}) as Record<string, string>;
      if (headers["X-API-Key"] !== "test-key") return new Response("{}", { status: 401 });
      if (url.pathname === "/v1/emails" && init?.method === "POST") {
        return Response.json({ email: "quiet.fox@temp.example", ttl: 3600 });
      }
      if (/^\/v1\/emails\/[^/]+\/messages$/.test(url.pathname)) return Response.json({ messages: inbox });
      if (/^\/v1\/emails\/[^/]+$/.test(url.pathname) && init?.method === "DELETE") return new Response(null, { status: 204 });
      return new Response("{}", { status: 404 });
    });
  });

  afterEach(() => {
    setTempMailFetch(null);
    if (key === undefined) delete process.env.TEMP_MAIL_API_KEY;
    else process.env.TEMP_MAIL_API_KEY = key;
  });

  it("makes an address, shows its mail with the code, and lets it go", async () => {
    const app = signedInApp();
    const made = (await app.inject({ method: "POST", url: "/tempmail", payload: { deviceId: "temp-dev-0001" } })).json();
    expect(made).toMatchObject({ ok: true, address: "quiet.fox@temp.example" });
    expect(made.expiresAt).toBeGreaterThan(Date.now());
    expect(JSON.parse(calls[0].body ?? "{}")).toEqual({ domain_type: "premium" });

    const ask = { address: made.address, token: made.token, deviceId: "temp-dev-0001" };
    expect((await app.inject({ method: "POST", url: "/tempmail/messages", payload: ask })).json())
      .toEqual({ ok: true, messages: [] });
    inbox = [{ id: "m1", from: '"Acme" <no-reply@acme.com>', subject: "482913 is your Acme code",
      body_text: "Your code is 482913", created_at: "2026-09-30T10:00:00Z" }];
    // Within the cache's few seconds, the same answer and no request upstream.
    const before = calls.length;
    expect((await app.inject({ method: "POST", url: "/tempmail/messages", payload: ask })).json().messages).toEqual([]);
    expect(calls.length).toBe(before);

    const fresh = signedInApp();
    const listed = (await fresh.inject({ method: "POST", url: "/tempmail/messages", payload: ask })).json();
    // A new app has its own cache: the mail shows, with its code read out.
    expect(listed.messages[0]).toMatchObject({ id: "m1", from: "Acme", subject: "482913 is your Acme code", code: "482913" });

    expect((await fresh.inject({ method: "POST", url: "/tempmail/delete", payload: ask })).json()).toEqual({ ok: true });
    expect(calls.some(c => c.method === "DELETE")).toBe(true);
  });

  it("falls back to a public domain when the plan has no premium ones", async () => {
    setTempMailFetch(async (_input, init) => {
      const body = JSON.parse(String(init?.body ?? "{}"));
      if (body.domain_type === "premium") return Response.json({ error: { detail: "premium domains need a plan" } }, { status: 403 });
      return Response.json({ email: "plain@temp.example", ttl: 600 });
    });
    const app = signedInApp();
    const made = (await app.inject({ method: "POST", url: "/tempmail", payload: { deviceId: "temp-dev-0002" } })).json();
    expect(made).toMatchObject({ ok: true, address: "plain@temp.example" });
  });

  it("never reads an address with someone else's token", async () => {
    const app = signedInApp();
    const theirs = signInbox("google:someone-else", "quiet.fox@temp.example", Date.now() + 3600_000);
    const res = await app.inject({ method: "POST", url: "/tempmail/messages",
      payload: { address: "quiet.fox@temp.example", token: theirs, deviceId: "temp-dev-0003" } });
    expect(res.statusCode).toBe(403);
    expect(calls.length).toBe(0);
  });

  it("says plainly when there is no key yet", async () => {
    delete process.env.TEMP_MAIL_API_KEY;
    const app = signedInApp();
    const res = await app.inject({ method: "POST", url: "/tempmail", payload: { deviceId: "temp-dev-0004" } });
    expect(res.statusCode).toBe(503);
    expect(res.json().error).toBe("Temp mail isn't set up yet");
    expect(testToken()).toBeTruthy();
  });
});

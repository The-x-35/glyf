import { createHmac, timingSafeEqual } from "node:crypto";

/**
 * Temporary inboxes in the keyboard (Arpit, 2026-09-30: "we will have option
 * to enter temporary mail and we will monitor its mails for next some times
 * and show the mails gotten on it, so user can get temporary mails directly
 * inside their keyboards").
 *
 * On Temp-Mail.io's API (https://docs.temp-mail.io; the shape here is its
 * official client's, github.com/temp-mail-io/temp-mail-go): the key stays on
 * this server, the keyboards only ever talk to Glyf. Chosen 2026-09-30 over
 * mail.tm (free, but its terms bar wrapping it in a paid product and cap every
 * caller at 8 requests a second per IP, which one server for everyone would
 * hit), Mailsac (free addresses are public: anyone can read them), MailSlurp
 * (built for QA, 100 inboxes a month free) and DevInbox (a single domain,
 * easy for sign-up forms to turn away).
 *
 * An address is the person's for as long as it lives: every read carries a
 * token binding it to their account (HMAC with SESSION_SECRET), so nobody can
 * read someone else's inbox through Glyf by guessing an address. Nothing is
 * stored: messages pass through, cached a few seconds so several keyboards
 * watching one address cost one request upstream.
 */

export interface TempMessage {
  id: string;
  /** Who sent it, as a person reads it: the name, else the address. */
  from: string;
  fromAddress: string;
  subject: string;
  /** Plain text, HTML turned to text when that is all there is. */
  text: string;
  /** Epoch milliseconds. */
  receivedAt: number;
  /** A one-time code the mail carries ("482913", "G-123456"), if any. */
  code?: string;
  /** The link it asks to be opened (verify, confirm, sign in), if any. */
  link?: string;
}

export class TempMailError extends Error {
  constructor(public readonly status: number, message: string) {
    super(message);
  }
}

type Fetch = typeof fetch;
let fetcher: Fetch = (...args) => fetch(...args);

/** Tests hand in a fake Temp-Mail.io. */
export function setTempMailFetch(f: Fetch | null): void {
  fetcher = f ?? ((...args) => fetch(...args));
}

function base(): string {
  // Local testing only, against a stand-in; never set on Railway.
  return (process.env.TEMP_MAIL_BASE_URL || "https://api.temp-mail.io").replace(/\/+$/, "");
}

export function tempMailConfigured(): boolean {
  return Boolean(process.env.TEMP_MAIL_API_KEY?.trim());
}

async function call<T>(path: string, init: { method: string; body?: unknown } = { method: "GET" }): Promise<T> {
  const key = process.env.TEMP_MAIL_API_KEY?.trim();
  if (!key) throw new TempMailError(503, "Temp mail isn't set up yet");
  let res: Response;
  try {
    res = await fetcher(base() + path, {
      method: init.method,
      headers: { "X-API-Key": key, "Content-Type": "application/json", Accept: "application/json" },
      body: init.body === undefined ? undefined : JSON.stringify(init.body),
      signal: AbortSignal.timeout(8000),
    });
  } catch {
    throw new TempMailError(502, "Couldn't reach temp mail. Try again in a moment");
  }
  if (res.status === 429) throw new TempMailError(429, "Temp mail is busy. Try again in a minute");
  if (res.status === 401) throw new TempMailError(503, "Temp mail isn't set up yet");
  if (res.status === 404) throw new TempMailError(404, "That address has expired");
  if (!res.ok) {
    let detail = "";
    try {
      const body = await res.json() as { error?: { detail?: string } };
      detail = body.error?.detail ?? "";
    } catch { /* no body */ }
    throw new TempMailError(res.status, detail || "Temp mail didn't answer. Try again in a moment");
  }
  if (res.status === 204) return undefined as T;
  return await res.json() as T;
}

/** A new address. Premium domains first: fewer sign-up forms turn them
 *  away. A plan without them gets a public one. */
export async function createAddress(): Promise<{ address: string; expiresAt: number }> {
  let made: { email: string; ttl: number };
  try {
    made = await call("/v1/emails", { method: "POST", body: { domain_type: "premium" } });
  } catch (err) {
    if (!(err instanceof TempMailError) || ![400, 402, 403, 422].includes(err.status)) throw err;
    made = await call("/v1/emails", { method: "POST", body: {} });
  }
  const ttl = Number.isFinite(made.ttl) && made.ttl > 0 ? made.ttl : 3600;
  return { address: made.email, expiresAt: Date.now() + ttl * 1000 };
}

interface RawMessage {
  id: string;
  from?: string;
  subject?: string;
  body_text?: string;
  body_html?: string;
  created_at?: string;
}

/** What the address has received, newest first. */
export async function listMessages(address: string): Promise<TempMessage[]> {
  const got = await call<{ messages?: RawMessage[] }>(`/v1/emails/${encodeURIComponent(address)}/messages`);
  return (got.messages ?? []).map(toMessage).sort((a, b) => b.receivedAt - a.receivedAt);
}

export async function deleteAddress(address: string): Promise<void> {
  await call(`/v1/emails/${encodeURIComponent(address)}`, { method: "DELETE" });
}

export function toMessage(m: RawMessage): TempMessage {
  const { name, address } = parseFrom(m.from ?? "");
  const subject = (m.subject ?? "").trim();
  const text = (m.body_text?.trim() ? m.body_text : htmlToText(m.body_html ?? "")).trim().slice(0, 4000);
  const received = Date.parse(m.created_at ?? "");
  const code = extractCode(subject, text);
  const link = extractLink(m.body_text ?? "", m.body_html ?? "");
  return {
    id: m.id, from: name || address, fromAddress: address, subject, text,
    receivedAt: Number.isFinite(received) ? received : Date.now(),
    ...(code ? { code } : {}), ...(link ? { link } : {}),
  };
}

/** `"Service" <no-reply@service.com>` → name and address. */
export function parseFrom(from: string): { name: string; address: string } {
  const m = from.match(/^\s*"?([^"<]*?)"?\s*<([^>]+)>\s*$/);
  if (m) return { name: m[1].trim(), address: m[2].trim() };
  return { name: "", address: from.trim() };
}

const ENTITIES: Record<string, string> = { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " ", "#39": "'" };

export function htmlToText(html: string): string {
  return html
    .replace(/<(script|style|head)[\s\S]*?<\/\1>/gi, " ")
    .replace(/<br\s*\/?>|<\/(p|div|tr|li|h[1-6])>/gi, "\n")
    .replace(/<[^>]+>/g, " ")
    .replace(/&(#\d+|#x[0-9a-f]+|[a-z]+);/gi, (all, e: string) => {
      const k = e.toLowerCase();
      if (k in ENTITIES) return ENTITIES[k];
      if (k.startsWith("#x")) return String.fromCodePoint(parseInt(k.slice(2), 16));
      if (k.startsWith("#")) return String.fromCodePoint(parseInt(k.slice(1), 10));
      return all;
    })
    .replace(/[ \t\f\v ]+/g, " ")
    .replace(/\s*\n\s*/g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

/** Words a code sits next to, in the mails people get when signing up. */
const CODE_WORDS = /\b(codes?|otp|passcode|pass code|pin|verification|verify|security|confirmation|confirm|one[- ]time|log ?in|sign[- ]?in|2fa|two[- ]factor|token|password)\b/i;

/** A one-time code in a mail: "Your code is 482913", "G-482913 is your
 *  Google verification code", "123 456". A number counts when the subject
 *  holds it or it stands within a few words of a code word; years, prices,
 *  phone numbers and dates never do. */
export function extractCode(subject: string, text: string): string | undefined {
  const hay = `${subject}\n${text}`.slice(0, 6000);
  const re = /(?<![\w$€£₹.,/:-])((?:[A-Z]{1,3}-)?\d{3}[ -]?\d{3}|(?:[A-Z]{1,3}-)?\d{4,8})(?![\w%$€£₹/:]|[.,]\d)/g;
  let best: { code: string; score: number } | undefined;
  for (const m of hay.matchAll(re)) {
    const raw = m[1];
    const digits = raw.replace(/^[A-Z]{1,3}-/, "").replace(/[ -]/g, "");
    if (digits.length < 4 || digits.length > 8) continue;
    // A year on its own is a date, not a code.
    if (digits.length === 4 && /^(19|20)\d\d$/.test(digits) && !/^[A-Z]{1,3}-/.test(raw)) continue;
    const at = m.index ?? 0;
    const around = hay.slice(Math.max(0, at - 80), at + raw.length + 40);
    const inSubject = at < subject.length;
    let score = 0;
    if (inSubject) score += 3;
    if (CODE_WORDS.test(around)) score += 3;
    if (digits.length === 6) score += 2;
    else if (digits.length >= 4 && digits.length <= 8) score += 1;
    if (/^[A-Z]{1,3}-/.test(raw)) score += 1;
    // A phone number or an order number reads differently.
    if (/\b(phone|call|tel|order|invoice|ref|reference|account (?:number|no\.?|#)|zip|postal)\b/i.test(hay.slice(Math.max(0, at - 30), at))) score -= 4;
    if (score >= 4 && (!best || score > best.score)) {
      best = { code: /^[A-Z]{1,3}-/.test(raw) ? raw.replace(/ /g, "") : digits, score };
    }
  }
  return best?.code;
}

const LINK_WORDS = /(verif|confirm|activat|validat|magic|log-?in|sign-?in|signin|auth|reset|token|onboard|welcome|join|invite)/i;

/** The link a mail asks to be opened: a verify or sign-in link, from the
 *  HTML's hrefs first (their text says what they are), else the text. */
export function extractLink(text: string, html: string): string | undefined {
  for (const m of html.matchAll(/<a\b[^>]*href\s*=\s*["']([^"']+)["'][^>]*>([\s\S]*?)<\/a>/gi)) {
    const href = m[1].replace(/&amp;/g, "&");
    if (/^https:\/\//i.test(href) && (LINK_WORDS.test(href) || LINK_WORDS.test(htmlToText(m[2])))) return href;
  }
  for (const m of text.matchAll(/https:\/\/[^\s<>"')\]]+/gi)) {
    const href = m[0].replace(/[.,;]+$/, "");
    if (LINK_WORDS.test(href)) return href;
  }
  // A logo or an unsubscribe link is no action: nothing rather than a guess.
  return undefined;
}

// ── who may read an address ───────────────────────────────────────────────

function secret(): string {
  return (process.env.SESSION_SECRET ?? "").trim();
}

function mac(userId: string, address: string, exp: number): string {
  return createHmac("sha256", secret()).update(`tempmail|${userId}|${address.toLowerCase()}|${exp}`).digest("base64url");
}

/** A token that lets this account, and only it, read this address until it
 *  expires. */
export function signInbox(userId: string, address: string, expiresAt: number): string {
  const exp = Math.floor(expiresAt / 1000);
  return `${exp}.${mac(userId, address, exp)}`;
}

export function verifyInbox(userId: string, address: string, token: string, now = Date.now()): boolean {
  if (!secret()) return false;
  const [expText, sig] = token.split(".");
  const exp = Number(expText);
  if (!Number.isFinite(exp) || !sig || exp * 1000 < now) return false;
  const want = Buffer.from(mac(userId, address, exp));
  const got = Buffer.from(sig);
  return want.length === got.length && timingSafeEqual(want, got);
}

import { createHash, createHmac, createPublicKey, timingSafeEqual, verify, type JsonWebKey } from "node:crypto";

/**
 * Who someone is, straight from Apple or Google.
 *
 * The phone signs in natively (Sign in with Apple, Google's own sign-in) and
 * hands over the ID token it got. The token is checked here against the
 * provider's published keys: signed by them, issued for this app, fresh, and
 * carrying the nonce the phone made for this one sign-in. Then Glyf issues its
 * own session token, which is what every later call carries.
 *
 * Config (all public ids except the session secret):
 *   GOOGLE_CLIENT_ID      web client: the audience Android's sign-in asks for
 *   GOOGLE_IOS_CLIENT_ID  iOS client: the audience of tokens from iPhones
 *   APPLE_BUNDLE_ID       the app's bundle id, Apple's audience (com.arpit.glyf);
 *                         a comma-separated list is accepted, so builds from
 *                         an older bundle id can sign in while they last
 *   SESSION_SECRET        signs Glyf sessions; never leaves the server
 */

export type Provider = "google" | "apple";

export interface Identity {
  provider: Provider;
  /** The provider's stable id for the person. */
  sub: string;
  email?: string;
  name?: string;
}

const ISSUERS: Record<Provider, string[]> = {
  google: ["https://accounts.google.com", "accounts.google.com"],
  apple: ["https://appleid.apple.com"],
};

const KEYS_URL: Record<Provider, string> = {
  google: "https://www.googleapis.com/oauth2/v3/certs",
  apple: "https://appleid.apple.com/auth/keys",
};

type Jwk = JsonWebKey & { kid?: string };

const keyCache = new Map<Provider, { keys: Jwk[]; at: number }>();

export function resetKeyCacheForTests(): void {
  keyCache.clear();
}

async function providerKeys(provider: Provider, fetchImpl: typeof fetch, fresh = false): Promise<Jwk[]> {
  const cached = keyCache.get(provider);
  if (!fresh && cached && Date.now() - cached.at < 3600_000) return cached.keys;
  const res = await fetchImpl(KEYS_URL[provider], { signal: AbortSignal.timeout(5000) });
  if (!res.ok) throw new Error(`keys ${res.status}`);
  const body = await res.json() as { keys?: Jwk[] };
  const keys = body.keys ?? [];
  keyCache.set(provider, { keys, at: Date.now() });
  return keys;
}

/** The client ids a provider's tokens may be issued to. */
export function audiences(provider: Provider, env: NodeJS.ProcessEnv = process.env): string[] {
  const ids = provider === "google"
    ? [env.GOOGLE_CLIENT_ID, env.GOOGLE_IOS_CLIENT_ID]
    : (env.APPLE_BUNDLE_ID || "com.arpit.glyf").split(",");
  return ids.map(s => s?.trim() ?? "").filter(Boolean);
}

/** What the app needs to start a sign-in. Public ids only. */
export function signInConfig(env: NodeJS.ProcessEnv = process.env) {
  const web = env.GOOGLE_CLIENT_ID?.trim() || null;
  const ios = env.GOOGLE_IOS_CLIENT_ID?.trim() || null;
  const sessions = Boolean(env.SESSION_SECRET?.trim());
  return {
    google: sessions && (web || ios) ? { webClientId: web, iosClientId: ios } : null,
    apple: sessions,
  };
}

function json64(part: string): Record<string, unknown> | null {
  try {
    const value = JSON.parse(Buffer.from(part, "base64url").toString("utf8"));
    return value && typeof value === "object" ? value as Record<string, unknown> : null;
  } catch {
    return null;
  }
}

function verifiedEmail(claims: Record<string, unknown>): string | undefined {
  const email = typeof claims.email === "string" ? claims.email.trim() : "";
  const ok = claims.email_verified === true || claims.email_verified === "true";
  return email && ok ? email : undefined;
}

/**
 * Checks an ID token from Apple or Google. `nonce` is the raw value the phone
 * made for this sign-in: Google carries it as is, Apple as its SHA-256 hex.
 * Returns who it is, or null for anything that does not hold up.
 */
export async function verifyIdToken(
  provider: Provider,
  token: string,
  opts: { nonce: string; audiences?: string[]; fetchImpl?: typeof fetch; now?: number },
): Promise<Identity | null> {
  const allowed = opts.audiences ?? audiences(provider);
  if (!token || !opts.nonce || allowed.length === 0) return null;
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  const [h, p, s] = parts;
  const header = json64(h);
  const claims = json64(p);
  if (!header || !claims || header.alg !== "RS256") return null;

  const now = (opts.now ?? Date.now()) / 1000;
  if (typeof claims.iss !== "string" || !ISSUERS[provider].includes(claims.iss)) return null;
  const aud = claims.aud;
  const audOk = typeof aud === "string" ? allowed.includes(aud)
    : Array.isArray(aud) && aud.some(a => typeof a === "string" && allowed.includes(a));
  if (!audOk) return null;
  if (typeof claims.exp !== "number" || claims.exp < now - 60) return null;
  if (typeof claims.iat === "number" && claims.iat > now + 300) return null;
  if (typeof claims.sub !== "string" || !claims.sub) return null;
  const expectedNonce = provider === "apple"
    ? createHash("sha256").update(opts.nonce).digest("hex")
    : opts.nonce;
  if (claims.nonce !== expectedNonce) return null;

  const fetchImpl = opts.fetchImpl ?? fetch;
  const kid = typeof header.kid === "string" ? header.kid : undefined;
  let keys: Jwk[];
  try {
    keys = await providerKeys(provider, fetchImpl);
    // Providers rotate keys; an unknown kid earns one fresh fetch.
    if (kid && !keys.some(k => k.kid === kid)) keys = await providerKeys(provider, fetchImpl, true);
  } catch {
    return null;
  }
  const candidates = kid ? keys.filter(k => k.kid === kid) : keys;
  const data = Buffer.from(`${h}.${p}`);
  const signature = Buffer.from(s, "base64url");
  const signed = candidates.some(jwk => {
    try {
      return verify("RSA-SHA256", data, createPublicKey({ key: jwk, format: "jwk" }), signature);
    } catch {
      return false;
    }
  });
  if (!signed) return null;

  const name = typeof claims.name === "string" && claims.name.trim() ? claims.name.trim() : undefined;
  return { provider, sub: claims.sub, email: verifiedEmail(claims), name };
}

// ── Glyf sessions ───────────────────────────────────────────────────────────

const SESSION_DAYS = 180;

function sessionSecret(secret?: string): string {
  return (secret ?? process.env.SESSION_SECRET ?? "").trim();
}

/** A Glyf session for a user id: HS256, signed with SESSION_SECRET. */
export function issueSession(userId: string, opts: { secret?: string; now?: number; days?: number } = {}): string | null {
  const secret = sessionSecret(opts.secret);
  if (!secret) return null;
  const iat = Math.floor((opts.now ?? Date.now()) / 1000);
  const exp = iat + (opts.days ?? SESSION_DAYS) * 86400;
  const h = Buffer.from(JSON.stringify({ alg: "HS256", typ: "JWT" })).toString("base64url");
  const p = Buffer.from(JSON.stringify({ iss: "glyf", sub: userId, iat, exp })).toString("base64url");
  const sig = createHmac("sha256", secret).update(`${h}.${p}`).digest("base64url");
  return `${h}.${p}.${sig}`;
}

// ── Confirmations ───────────────────────────────────────────────────────────

/** How long a confirmation stays good: long enough to read a sheet and tap,
 *  too short to be kept around and replayed later. */
const CONFIRM_SECONDS = 300;

function confirmSig(secret: string, purpose: string, userId: string, exp: number): string {
  return createHmac("sha256", secret).update(`confirm|${purpose}|${userId}|${exp}`).digest("base64url");
}

/** A short-lived token that says this person just asked for [purpose] (for
 *  now only "delete-account"). A session lives for months, so an action
 *  that can't be undone asks for one of these as well, minted moments
 *  before. Null without a session secret. */
export function issueConfirmation(userId: string, purpose: string,
  opts: { secret?: string; now?: number; seconds?: number } = {}): string | null {
  const secret = sessionSecret(opts.secret);
  if (!secret || !userId) return null;
  const exp = Math.floor((opts.now ?? Date.now()) / 1000) + (opts.seconds ?? CONFIRM_SECONDS);
  return `${exp}.${confirmSig(secret, purpose, userId, exp)}`;
}

/** Whether [token] is a confirmation of [purpose] by this user that has not
 *  run out. */
export function checkConfirmation(token: string, userId: string, purpose: string,
  opts: { secret?: string; now?: number } = {}): boolean {
  const secret = sessionSecret(opts.secret);
  if (!secret || !userId || typeof token !== "string") return false;
  const dot = token.indexOf(".");
  if (dot <= 0) return false;
  const exp = Number(token.slice(0, dot));
  if (!Number.isInteger(exp) || exp < (opts.now ?? Date.now()) / 1000) return false;
  const given = Buffer.from(token.slice(dot + 1), "base64url");
  const expected = Buffer.from(confirmSig(secret, purpose, userId, exp), "base64url");
  return given.length === expected.length && timingSafeEqual(given, expected);
}

/** The user id a Glyf session belongs to, or null. */
export function verifySession(token: string, opts: { secret?: string; now?: number } = {}): string | null {
  const secret = sessionSecret(opts.secret);
  if (!secret || !token) return null;
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  const [h, p, s] = parts;
  const header = json64(h);
  const claims = json64(p);
  if (!header || !claims || header.alg !== "HS256") return null;
  const expected = createHmac("sha256", secret).update(`${h}.${p}`).digest();
  const given = Buffer.from(s, "base64url");
  if (given.length !== expected.length || !timingSafeEqual(given, expected)) return null;
  const now = (opts.now ?? Date.now()) / 1000;
  if (claims.iss !== "glyf" || typeof claims.exp !== "number" || claims.exp < now) return null;
  return typeof claims.sub === "string" && claims.sub ? claims.sub : null;
}

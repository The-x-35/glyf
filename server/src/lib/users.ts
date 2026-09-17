import { createPublicKey, verify, type JsonWebKey } from "node:crypto";

/**
 * People who signed in to the app, in Postgres (Neon).
 *
 * Only what a person would expect an app to know about its users is kept:
 * who they are (Privy id, email, name, how they signed in), the phone they
 * use it on, their keyboard settings, and what they do in the app. Nothing
 * from the vault ever arrives here, not even encrypted: the app sends the
 * KINDS of detail someone saved ("address", "upi"), never the details.
 */

export type SqlQuery = (text: string, params?: unknown[]) => Promise<Record<string, unknown>[]>;

const DDL = [
  `create table if not exists glyf_users (
     privy_id text primary key,
     email text,
     name text,
     login_method text,
     platform text,
     app_version text,
     locale text,
     region text,
     timezone text,
     created_at timestamptz not null default now(),
     last_seen_at timestamptz not null default now()
   )`,
  `create table if not exists glyf_user_prefs (
     privy_id text primary key references glyf_users(privy_id) on delete cascade,
     prefs jsonb not null default '{}'::jsonb,
     updated_at timestamptz not null default now()
   )`,
  `create table if not exists glyf_events (
     id bigserial primary key,
     privy_id text not null references glyf_users(privy_id) on delete cascade,
     name text not null,
     props jsonb not null default '{}'::jsonb,
     at timestamptz not null default now()
   )`,
  `create index if not exists glyf_events_user_at on glyf_events (privy_id, at desc)`,
];

// ── Privy sessions ──────────────────────────────────────────────────────────

type Jwks = { keys: (JsonWebKey & { kid?: string })[] };

let jwksCache: { appId: string; keys: Jwks["keys"]; at: number } | null = null;

async function privyKeys(appId: string, fetchImpl: typeof fetch): Promise<Jwks["keys"]> {
  if (jwksCache && jwksCache.appId === appId && Date.now() - jwksCache.at < 3600_000) {
    return jwksCache.keys;
  }
  const res = await fetchImpl(`https://auth.privy.io/api/v1/apps/${encodeURIComponent(appId)}/jwks.json`, {
    signal: AbortSignal.timeout(5000),
  });
  if (!res.ok) throw new Error(`jwks ${res.status}`);
  const body = await res.json() as Jwks;
  jwksCache = { appId, keys: body.keys ?? [], at: Date.now() };
  return jwksCache.keys;
}

export function resetKeyCacheForTests(): void {
  jwksCache = null;
}

function json64(part: string): Record<string, unknown> | null {
  try {
    return JSON.parse(Buffer.from(part, "base64url").toString("utf8")) as Record<string, unknown>;
  } catch {
    return null;
  }
}

/** Checks a Privy access token (ES256, signed for this app, not expired) and
 *  returns the Privy user id, or null for anything that does not hold up. */
export async function verifyPrivyToken(
  token: string,
  opts: { appId?: string; fetchImpl?: typeof fetch; now?: number } = {},
): Promise<string | null> {
  const appId = opts.appId ?? process.env.PRIVY_APP_ID ?? "";
  if (!appId || !token) return null;
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  const [h, p, s] = parts;
  const header = json64(h);
  const claims = json64(p);
  if (!header || !claims || header.alg !== "ES256") return null;
  const now = (opts.now ?? Date.now()) / 1000;
  const aud = claims.aud;
  const audOk = aud === appId || (Array.isArray(aud) && aud.includes(appId));
  if (claims.iss !== "privy.io" || !audOk) return null;
  if (typeof claims.exp !== "number" || claims.exp < now - 30) return null;
  if (typeof claims.sub !== "string" || !claims.sub) return null;
  let keys: Jwks["keys"];
  try {
    keys = await privyKeys(appId, opts.fetchImpl ?? fetch);
  } catch {
    return null;
  }
  const candidates = header.kid ? keys.filter(k => k.kid === header.kid) : keys;
  for (const jwk of candidates) {
    try {
      const key = createPublicKey({ key: jwk, format: "jwk" });
      const ok = verify("sha256", Buffer.from(`${h}.${p}`), { key, dsaEncoding: "ieee-p1363" },
        Buffer.from(s, "base64url"));
      if (ok) return claims.sub;
    } catch {
      // try the next key
    }
  }
  return null;
}

export interface PrivyProfile {
  email?: string;
  name?: string;
  method?: string;
}

/** Email, name and sign-in method from Privy itself, so the app cannot claim
 *  an address it does not own. Needs the app secret, which never leaves here. */
export async function privyProfile(userId: string, fetchImpl: typeof fetch = fetch): Promise<PrivyProfile> {
  const appId = process.env.PRIVY_APP_ID;
  const secret = process.env.PRIVY_APP_SECRET;
  if (!appId || !secret) return {};
  const res = await fetchImpl(`https://auth.privy.io/api/v1/users/${encodeURIComponent(userId)}`, {
    signal: AbortSignal.timeout(6000),
    headers: {
      authorization: `Basic ${Buffer.from(`${appId}:${secret}`).toString("base64")}`,
      "privy-app-id": appId,
    },
  });
  if (!res.ok) return {};
  const user = await res.json() as { linked_accounts?: Record<string, unknown>[] };
  const accounts = user.linked_accounts ?? [];
  const str = (v: unknown) => (typeof v === "string" && v.trim() ? v.trim() : undefined);
  const google = accounts.find(a => a.type === "google_oauth");
  const apple = accounts.find(a => a.type === "apple_oauth");
  const email = accounts.find(a => a.type === "email");
  const first = [...accounts].sort((a, b) =>
    Number(a.first_verified_at ?? a.verified_at ?? 0) - Number(b.first_verified_at ?? b.verified_at ?? 0))[0];
  const method = first?.type === "google_oauth" ? "google"
    : first?.type === "apple_oauth" ? "apple"
    : first?.type === "email" ? "email" : undefined;
  return {
    email: str(email?.address) ?? str(google?.email) ?? str(apple?.email),
    name: str(google?.name),
    method,
  };
}

// ── What is kept ────────────────────────────────────────────────────────────

/** Settings worth learning from. Anything not named here is dropped, so a new
 *  private setting can never slip in by default. */
const PREF_KEYS = new Set([
  "appearance", "keyTheme", "themeBg", "keyBorders", "themeBrightness", "haptics", "keyClicks",
  "numberRow", "autocorrect", "autocapitalize", "periodShortcut", "candidates",
  "clipboardHistory", "clipboardScreenshots", "aiUsesVault", "pasteStyle", "vocabPacks",
  "vocabLearning", "toolbarOrder", "toolbarHidden", "menuOrder", "translateOther", "plan",
  "bindings", "customTitles", "vaultKinds", "noteCount", "shorthandCount",
]);

const VAULT_KINDS = new Set(["name", "email", "phone", "address", "upi", "gst", "wallet", "link",
  "social", "bio", "reply", "custom", "handle", "company"]);

export function cleanPrefs(input: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(input)) {
    if (!PREF_KEYS.has(k)) continue;
    if (k === "vaultKinds") {
      if (Array.isArray(v)) out[k] = [...new Set(v.filter((x): x is string => typeof x === "string" && VAULT_KINDS.has(x)))];
      continue;
    }
    const size = JSON.stringify(v ?? null).length;
    if (size > 4000) continue;
    out[k] = v;
  }
  return out;
}

export interface Device {
  platform?: string;
  appVersion?: string;
  locale?: string;
  region?: string;
  timezone?: string;
}

export interface AppEvent {
  name: string;
  props?: Record<string, unknown>;
  at?: string;
}

export class Users {
  private schema: Promise<void> | null = null;
  private sqlPromise: Promise<SqlQuery> | null = null;

  constructor(private readonly source: string | SqlQuery | undefined = process.env.DATABASE_URL) {}

  get enabled(): boolean {
    return Boolean(this.source);
  }

  private sql(): Promise<SqlQuery> {
    if (!this.sqlPromise) {
      const source = this.source;
      if (!source) return Promise.reject(new Error("no database"));
      this.sqlPromise = typeof source === "function"
        ? Promise.resolve(source)
        : import("@neondatabase/serverless").then(({ neon }) => {
          const client = neon(source);
          return (async (text, params) =>
            await client.query(text, params as unknown[]) as Record<string, unknown>[]) as SqlQuery;
        });
    }
    return this.sqlPromise;
  }

  private ensureSchema(): Promise<void> {
    if (!this.schema) {
      this.schema = (async () => {
        const sql = await this.sql();
        for (const statement of DDL) {
          try {
            await sql(statement);
          } catch {
            // Two cold instances creating the same table: it exists either way.
          }
        }
      })();
    }
    return this.schema;
  }

  async upsert(id: string, profile: PrivyProfile, device: Device): Promise<void> {
    await this.ensureSchema();
    const sql = await this.sql();
    await sql(
      `insert into glyf_users (privy_id, email, name, login_method, platform, app_version, locale, region, timezone)
       values ($1, $2, $3, $4, $5, $6, $7, $8, $9)
       on conflict (privy_id) do update set
         email = coalesce(excluded.email, glyf_users.email),
         name = coalesce(excluded.name, glyf_users.name),
         login_method = coalesce(glyf_users.login_method, excluded.login_method),
         platform = coalesce(excluded.platform, glyf_users.platform),
         app_version = coalesce(excluded.app_version, glyf_users.app_version),
         locale = coalesce(excluded.locale, glyf_users.locale),
         region = coalesce(excluded.region, glyf_users.region),
         timezone = coalesce(excluded.timezone, glyf_users.timezone),
         last_seen_at = now()`,
      [id, profile.email ?? null, profile.name ?? null, profile.method ?? null, device.platform ?? null,
        device.appVersion ?? null, device.locale ?? null, device.region ?? null, device.timezone ?? null],
    );
  }

  async savePrefs(id: string, prefs: Record<string, unknown>): Promise<void> {
    await this.ensureSchema();
    const sql = await this.sql();
    await sql(
      `insert into glyf_user_prefs (privy_id, prefs) values ($1, $2::jsonb)
       on conflict (privy_id) do update set prefs = excluded.prefs, updated_at = now()`,
      [id, JSON.stringify(cleanPrefs(prefs))],
    );
  }

  async addEvents(id: string, events: AppEvent[]): Promise<number> {
    if (events.length === 0) return 0;
    await this.ensureSchema();
    const sql = await this.sql();
    let stored = 0;
    for (const e of events.slice(0, 100)) {
      // Events carry counts and ids, never text someone typed.
      const props: Record<string, unknown> = {};
      for (const [k, v] of Object.entries(e.props ?? {})) {
        if (typeof v === "string" && v.length > 80) continue;
        if (typeof v === "object" && v !== null) continue;
        props[k] = v;
      }
      const at = e.at && !Number.isNaN(Date.parse(e.at)) ? e.at : new Date().toISOString();
      await sql(`insert into glyf_events (privy_id, name, props, at) values ($1, $2, $3::jsonb, $4)`,
        [id, e.name.slice(0, 64), JSON.stringify(props), at]);
      stored++;
    }
    return stored;
  }

  async remove(id: string): Promise<void> {
    await this.ensureSchema();
    const sql = await this.sql();
    await sql(`delete from glyf_users where privy_id = $1`, [id]);
  }
}

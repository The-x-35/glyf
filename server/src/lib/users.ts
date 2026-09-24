/**
 * People who signed in to the app, in Postgres (Neon).
 *
 * Only what a person would expect an app to know about its users is kept:
 * who they are (their Apple or Google id, email, name), the phone they
 * use it on, their keyboard settings, and what they do in the app. Nothing
 * from the vault ever arrives here, not even encrypted: the app sends the
 * KINDS of detail someone saved ("address", "upi"), never the details.
 */

export type SqlQuery = (text: string, params?: unknown[]) => Promise<Record<string, unknown>[]>;

const DDL = [
  // Accounts were keyed by Privy id before sign-in moved to Apple and Google
  // directly; the column is now the user id ("google:<sub>", "apple:<sub>").
  `do $$ begin
     if exists (select 1 from information_schema.columns
                where table_name = 'glyf_users' and column_name = 'privy_id') then
       alter table glyf_users rename column privy_id to user_id;
     end if;
     if exists (select 1 from information_schema.columns
                where table_name = 'glyf_user_prefs' and column_name = 'privy_id') then
       alter table glyf_user_prefs rename column privy_id to user_id;
     end if;
     if exists (select 1 from information_schema.columns
                where table_name = 'glyf_events' and column_name = 'privy_id') then
       alter table glyf_events rename column privy_id to user_id;
     end if;
   end $$`,
  `create table if not exists glyf_users (
     user_id text primary key,
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
     user_id text primary key references glyf_users(user_id) on delete cascade,
     prefs jsonb not null default '{}'::jsonb,
     updated_at timestamptz not null default now()
   )`,
  `create table if not exists glyf_events (
     id bigserial primary key,
     user_id text not null references glyf_users(user_id) on delete cascade,
     name text not null,
     props jsonb not null default '{}'::jsonb,
     at timestamptz not null default now()
   )`,
  `create index if not exists glyf_events_user_at on glyf_events (user_id, at desc)`,
  // The plan is the server's word: a phone can claim what it likes, the cap
  // it gets is the one on this row. Nothing but a verified purchase moves it.
  `alter table glyf_users add column if not exists plan text not null default 'free'`,
];

export interface Profile {
  email?: string;
  name?: string;
  /** How they signed in: "google" or "apple". */
  method?: string;
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

  async upsert(id: string, profile: Profile, device: Device): Promise<void> {
    await this.ensureSchema();
    const sql = await this.sql();
    await sql(
      `insert into glyf_users (user_id, email, name, login_method, platform, app_version, locale, region, timezone)
       values ($1, $2, $3, $4, $5, $6, $7, $8, $9)
       on conflict (user_id) do update set
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
      `insert into glyf_user_prefs (user_id, prefs) values ($1, $2::jsonb)
       on conflict (user_id) do update set prefs = excluded.prefs, updated_at = now()`,
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
      await sql(`insert into glyf_events (user_id, name, props, at) values ($1, $2, $3::jsonb, $4)`,
        [id, e.name.slice(0, 64), JSON.stringify(props), at]);
      stored++;
    }
    return stored;
  }

  /** Puts a plan on their row (creating the row if sign-in never did). */
  async setPlan(id: string, plan: "free" | "plus" | "max"): Promise<void> {
    await this.ensureSchema();
    const sql = await this.sql();
    await sql(
      `insert into glyf_users (user_id, plan) values ($1, $2)
       on conflict (user_id) do update set plan = excluded.plan, last_seen_at = now()`,
      [id, plan],
    );
  }

  /** The plan on their row; free for anyone not on one. */
  async plan(id: string): Promise<"free" | "plus" | "max"> {
    await this.ensureSchema();
    const sql = await this.sql();
    const rows = await sql(`select plan from glyf_users where user_id = $1`, [id]);
    const plan = rows[0]?.plan;
    return plan === "plus" || plan === "max" ? plan : "free";
  }

  async remove(id: string): Promise<void> {
    await this.ensureSchema();
    const sql = await this.sql();
    await sql(`delete from glyf_users where user_id = $1`, [id]);
  }
}

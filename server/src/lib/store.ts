import { mkdirSync, readFileSync, writeFileSync, existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

/** Durable storage behind ONE interface. Local dev: JSON files under
 *  server/data/ (zero-setup, survives restarts). Deploys: Postgres (Neon),
 *  because a serverless file system is per-instance and read-only, so FileKV
 *  would lose every write between invocations (SPEC §2 pins Postgres in prod).
 *
 *  The four data methods stay synchronous, which is what every caller already
 *  expects. The two optional lifecycle methods are how an async store keeps
 *  that promise: `refresh()` pulls in what other instances wrote before a
 *  handler reads, `flush()` waits for what this instance wrote to land.
 *  Drivers that are already local define neither and pay nothing. */
export interface KV {
  get<T>(collection: string, id: string): T | undefined;
  put<T>(collection: string, id: string, value: T): void;
  del(collection: string, id: string): void;
  list<T>(collection: string): { id: string; value: T }[];
  /** Optional: pull changes written elsewhere. Called once per request. */
  refresh?(): Promise<void>;
  /** Optional: wait for queued writes to reach the store. Never rejects. */
  flush?(): Promise<void>;
  /** Optional: what GET /health reports about storage. */
  status?(): KVStatus;
}

export type KVStatus = {
  driver: "file" | "memory" | "postgres";
  /** false means the store has not been read successfully yet. */
  ready: boolean;
  collections: number;
};

export class FileKV implements KV {
  private cache = new Map<string, Map<string, unknown>>();
  constructor(private dir: string) {
    mkdirSync(dir, { recursive: true });
  }

  private file(collection: string): string {
    return join(this.dir, `${collection}.json`);
  }

  private load(collection: string): Map<string, unknown> {
    let m = this.cache.get(collection);
    if (m) return m;
    m = new Map();
    const f = this.file(collection);
    if (existsSync(f)) {
      try {
        const obj = JSON.parse(readFileSync(f, "utf8")) as Record<string, unknown>;
        for (const [k, v] of Object.entries(obj)) m.set(k, v);
      } catch { /* corrupt file starts fresh; originals stay on disk */ }
    }
    this.cache.set(collection, m);
    return m;
  }

  private flushFile(collection: string): void {
    const m = this.load(collection);
    writeFileSync(this.file(collection),
      JSON.stringify(Object.fromEntries(m), null, 1));
  }

  get<T>(c: string, id: string): T | undefined {
    return this.load(c).get(id) as T | undefined;
  }

  put<T>(c: string, id: string, value: T): void {
    this.load(c).set(id, value);
    this.flushFile(c);
  }

  del(c: string, id: string): void {
    this.load(c).delete(id);
    this.flushFile(c);
  }

  list<T>(c: string): { id: string; value: T }[] {
    return [...this.load(c).entries()].map(([id, value]) => ({ id, value: value as T }));
  }

  status(): KVStatus {
    return { driver: "file", ready: true, collections: this.cache.size };
  }
}

export class MemoryKV implements KV {
  private m = new Map<string, Map<string, unknown>>();
  private col(c: string): Map<string, unknown> {
    let x = this.m.get(c);
    if (!x) { x = new Map(); this.m.set(c, x); }
    return x;
  }
  get<T>(c: string, id: string): T | undefined { return this.col(c).get(id) as T | undefined; }
  put<T>(c: string, id: string, v: T): void { this.col(c).set(id, v); }
  del(c: string, id: string): void { this.col(c).delete(id); }
  list<T>(c: string): { id: string; value: T }[] {
    return [...this.col(c).entries()].map(([id, value]) => ({ id, value: value as T }));
  }
  status(): KVStatus {
    return { driver: "memory", ready: true, collections: this.m.size };
  }
}

// ── Postgres (Neon) ────────────────────────────────────────────────────────

/** The only shape PostgresKV needs from a driver: parameterised SQL in, rows
 *  out. Neon's HTTP `sql.query` matches it exactly, and a fake matches it in
 *  the tests, so no live database is needed to prove the semantics. */
export type SqlQuery = (text: string, params?: unknown[]) => Promise<Record<string, unknown>[]>;

export const KV_TABLE = "glyf_kv";

/** One table, keyed by collection + key, holding JSON. `deleted` is a
 *  tombstone rather than a DELETE so other instances can see a removal in the
 *  same "what changed since" query that carries every other change. */
const DDL = [
  `create table if not exists ${KV_TABLE} (
     collection text not null,
     key text not null,
     value jsonb,
     deleted boolean not null default false,
     updated_at timestamptz not null default now(),
     primary key (collection, key)
   )`,
  `create index if not exists ${KV_TABLE}_updated_at_idx on ${KV_TABLE} (updated_at)`,
];

const SELECT_SINCE =
  `select collection, key, value, deleted, updated_at from ${KV_TABLE}
   where updated_at >= $1::timestamptz order by updated_at asc`;

const UPSERT =
  `insert into ${KV_TABLE} (collection, key, value, deleted, updated_at)
   values ($1, $2, $3::jsonb, $4, now())
   on conflict (collection, key) do update
   set value = excluded.value, deleted = excluded.deleted, updated_at = now()`;

const EPOCH = "1970-01-01T00:00:00.000Z";

type PendingWrite = {
  collection: string; key: string; value: unknown; deleted: boolean; attempts: number;
};

/** One queue entry per row. JSON keeps the pair unambiguous whatever a key
 *  contains (device ids, base64url emails, "<device>:<provider>"). */
const pendingKey = (collection: string, key: string) => JSON.stringify([collection, key]);

export class PostgresKV implements KV {
  private mirror = new Map<string, Map<string, unknown>>();
  /** Highest updated_at applied so far. `>=` on purpose: re-reading the newest
   *  handful of rows is cheap, and missing a row written in the same tick is not. */
  private watermark = EPOCH;
  private pending = new Map<string, PendingWrite>();
  private refreshing: Promise<void> | null = null;
  private flushing: Promise<void> | null = null;
  private sqlPromise: Promise<SqlQuery> | null = null;
  private schemaReady: Promise<void> | null = null;
  private loaded = false;

  /** Either a connection string (Neon over HTTP, created on first use) or a
   *  query function, which is what the tests pass. */
  constructor(
    private source: string | SqlQuery,
    private log: (msg: string, err?: unknown) => void = defaultLog,
  ) {}

  // Reads and writes: synchronous against the mirror, exactly like FileKV.

  get<T>(c: string, id: string): T | undefined {
    return this.mirror.get(c)?.get(id) as T | undefined;
  }

  put<T>(c: string, id: string, value: T): void {
    this.col(c).set(id, value);
    this.enqueue({ collection: c, key: id, value, deleted: false, attempts: 0 });
  }

  del(c: string, id: string): void {
    this.col(c).delete(id);
    this.enqueue({ collection: c, key: id, value: null, deleted: true, attempts: 0 });
  }

  list<T>(c: string): { id: string; value: T }[] {
    const m = this.mirror.get(c);
    return m ? [...m.entries()].map(([id, value]) => ({ id, value: value as T })) : [];
  }

  status(): KVStatus {
    return { driver: "postgres", ready: this.loaded, collections: this.mirror.size };
  }

  /** Pull everything written since the last call (the whole table on the first
   *  one). Rejects on a store failure so the caller can log it; the mirror
   *  keeps serving what it already has. */
  async refresh(): Promise<void> {
    if (this.refreshing) return this.refreshing;
    this.refreshing = this.doRefresh().finally(() => { this.refreshing = null; });
    return this.refreshing;
  }

  /** Wait for queued writes to land. Never rejects: a caller is usually a
   *  response hook, and a storage failure must not turn into a 500 after the
   *  work itself succeeded. Failures are logged. */
  async flush(): Promise<void> {
    // A write queued while a drain was running, or one that failed its first
    // attempt, gets another pass. Each write is dropped after two, so a store
    // that is down cannot grow the queue without bound.
    while (this.pending.size > 0 || this.flushing) {
      if (!this.flushing) {
        this.flushing = this.drain().finally(() => { this.flushing = null; });
      }
      await this.flushing;
    }
  }

  private col(c: string): Map<string, unknown> {
    let m = this.mirror.get(c);
    if (!m) { m = new Map(); this.mirror.set(c, m); }
    return m;
  }

  private enqueue(w: PendingWrite): void {
    this.pending.set(pendingKey(w.collection, w.key), w);
    if (!this.flushing) {
      // Land it without waiting for a hook. Errors are logged inside drain().
      void this.flush();
    }
  }

  private async sql(): Promise<SqlQuery> {
    if (!this.sqlPromise) {
      const source = this.source;
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

  /** `create ... if not exists` twice from two cold instances at once can trip
   *  a unique-violation on the catalog. Both mean the table is there, so the
   *  error is swallowed and the first SELECT is what reports a real problem. */
  private async ensureSchema(): Promise<void> {
    if (!this.schemaReady) {
      this.schemaReady = (async () => {
        const sql = await this.sql();
        for (const statement of DDL) {
          try {
            await sql(statement);
          } catch (err) {
            this.log("kv schema statement failed (continuing)", err);
          }
        }
      })();
    }
    return this.schemaReady;
  }

  private async doRefresh(): Promise<void> {
    const sql = await this.sql();
    await this.ensureSchema();
    const rows = await sql(SELECT_SINCE, [this.watermark]);
    for (const raw of rows) {
      const row = raw as {
        collection: string; key: string; value: unknown;
        deleted: boolean; updated_at: string | Date;
      };
      const stamp = toIso(row.updated_at);
      if (stamp > this.watermark) this.watermark = stamp;
      // A local write still on its way out wins: it is newer than anything
      // this query can have seen, and it is already in the mirror.
      if (this.pending.has(pendingKey(row.collection, row.key))) continue;
      if (row.deleted) this.col(row.collection).delete(row.key);
      else this.col(row.collection).set(row.key, row.value);
    }
    this.loaded = true;
  }

  private async drain(): Promise<void> {
    let sql: SqlQuery;
    try {
      sql = await this.sql();
      await this.ensureSchema();
    } catch (err) {
      this.log("kv unavailable, dropping queued writes", err);
      this.pending.clear();
      return;
    }
    for (const [id, w] of [...this.pending]) {
      try {
        await sql(UPSERT, [w.collection, w.key, JSON.stringify(w.value ?? null), w.deleted]);
        this.pending.delete(id);
      } catch (err) {
        w.attempts += 1;
        this.log(`kv write failed for ${w.collection} (attempt ${w.attempts})`, err);
        if (w.attempts >= 2) this.pending.delete(id);
      }
    }
  }
}

function toIso(value: string | Date): string {
  return value instanceof Date ? value.toISOString() : new Date(value).toISOString();
}

function defaultLog(msg: string, err?: unknown): void {
  console.error(`[kv] ${msg}`, err instanceof Error ? err.message : err ?? "");
}

const DATA_DIR = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "data");

/** test → memory; DATABASE_URL → Postgres; a serverless host without a
 *  database → memory (its disk is per-instance and read-only, so FileKV would
 *  only pretend to work); anything else → files under server/data/.
 *
 *  `GLYF_STORE=file|memory|postgres` forces one, which is the escape hatch for
 *  a machine that has DATABASE_URL in its environment for something else and
 *  still wants local JSON files. Tests are always memory, whatever is set. */
export function defaultKV(): KV {
  if (process.env.NODE_ENV === "test") return new MemoryKV();
  const url = process.env.DATABASE_URL?.trim();
  const forced = process.env.GLYF_STORE?.trim().toLowerCase();
  if (forced === "memory") return new MemoryKV();
  if (forced === "file") return new FileKV(DATA_DIR);
  if (forced === "postgres") {
    if (!url) throw new Error("GLYF_STORE=postgres needs DATABASE_URL");
    return new PostgresKV(url);
  }
  if (url) {
    if (!process.env.VERCEL && !process.env.AWS_LAMBDA_FUNCTION_NAME
        && process.env.NODE_ENV !== "production") {
      // Loud on purpose: a laptop that has DATABASE_URL in server/.env now
      // reads and writes that database instead of server/data/*.json.
      console.warn("[kv] DATABASE_URL is set, so this run uses Postgres, not server/data/. Set GLYF_STORE=file to keep the local JSON files.");
    }
    return new PostgresKV(url);
  }
  if (process.env.VERCEL || process.env.AWS_LAMBDA_FUNCTION_NAME) {
    console.warn("[kv] no DATABASE_URL on a serverless host: state lives in memory and dies with the instance");
    return new MemoryKV();
  }
  return new FileKV(DATA_DIR);
}

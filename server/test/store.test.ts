import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterAll, describe, expect, it } from "vitest";
import { buildApp } from "../src/index.js";
import {
  FileKV, MemoryKV, PostgresKV, type KV, type SqlQuery,
} from "../src/lib/store.js";

/** A stand-in for Neon's `sql.query`: one table, the same five statements the
 *  driver sends, no network. Two PostgresKV instances sharing one of these is
 *  two serverless instances sharing one database. */
function fakePostgres() {
  type Row = {
    collection: string; key: string; value: unknown; deleted: boolean; updated_at: string;
  };
  const rows = new Map<string, Row>();
  const pgKey = (collection: string, key: string) => JSON.stringify([collection, key]);
  const statements: string[] = [];
  let tick = 0;
  let failWith: string | null = null;
  const stamp = () => new Date(Date.UTC(2026, 0, 1) + (tick += 1)).toISOString();

  const query: SqlQuery = async (text, params = []) => {
    statements.push(text.trim().split(/\s+/).slice(0, 3).join(" ").toLowerCase());
    if (failWith) throw new Error(failWith);
    if (/^create/i.test(text)) return [];
    if (/^insert/i.test(text)) {
      const [collection, key, value, deleted] = params as [string, string, string, boolean];
      rows.set(pgKey(collection, key), {
        collection, key, value: JSON.parse(value), deleted, updated_at: stamp(),
      });
      return [];
    }
    if (/^select/i.test(text)) {
      const since = String(params[0]);
      return [...rows.values()]
        .filter(r => r.updated_at >= since)
        .sort((a, b) => a.updated_at.localeCompare(b.updated_at)) as unknown as Record<string, unknown>[];
    }
    throw new Error(`unexpected sql: ${text}`);
  };

  return {
    query, rows, statements,
    /** Write straight into the table, as another instance would. */
    external(collection: string, key: string, value: unknown, deleted = false) {
      rows.set(pgKey(collection, key), { collection, key, value, deleted, updated_at: stamp() });
    },
    breakStore(message: string | null) { failWith = message; },
  };
}

const tmpDirs: string[] = [];
function tempFileKV(): FileKV {
  const dir = mkdtempSync(join(tmpdir(), "glyf-kv-"));
  tmpDirs.push(dir);
  return new FileKV(dir);
}

afterAll(() => {
  for (const dir of tmpDirs) rmSync(dir, { recursive: true, force: true });
});

/** Every driver has to behave like MemoryKV, because that is what the meter,
 *  connections, glyf library, hub, pages, telemetry, waitlist and search
 *  recents were written against and they call it synchronously. */
const drivers: [string, () => KV][] = [
  ["MemoryKV", () => new MemoryKV()],
  ["FileKV", () => tempFileKV()],
  ["PostgresKV", () => new PostgresKV(fakePostgres().query, () => {})],
];

describe.each(drivers)("KV contract: %s", (_name, make) => {
  it("reads back what it wrote", () => {
    const kv = make();
    kv.put("connections", "dev:google", { access_token: "t", expires_at: 1 });
    expect(kv.get("connections", "dev:google")).toEqual({ access_token: "t", expires_at: 1 });
  });

  it("returns undefined for a missing key or collection", () => {
    const kv = make();
    expect(kv.get("nope", "nothing")).toBeUndefined();
    kv.put("hub", "a", 1);
    expect(kv.get("hub", "b")).toBeUndefined();
  });

  it("overwrites in place and keeps collections apart", () => {
    const kv = make();
    kv.put("userglyfs", "x", { v: 1 });
    kv.put("userglyfs", "x", { v: 2 });
    kv.put("hub", "x", { v: 9 });
    expect(kv.get("userglyfs", "x")).toEqual({ v: 2 });
    expect(kv.get("hub", "x")).toEqual({ v: 9 });
  });

  it("deletes, and deleting an absent key is a no-op", () => {
    const kv = make();
    kv.put("installs", "d:g", { at: "now" });
    kv.del("installs", "d:g");
    kv.del("installs", "never-there");
    expect(kv.get("installs", "d:g")).toBeUndefined();
    expect(kv.list("installs")).toEqual([]);
  });

  it("lists a collection as id and value pairs, empty when unknown", () => {
    const kv = make();
    expect(kv.list("waitlist")).toEqual([]);
    kv.put("waitlist", "a", { email: "a@example.com" });
    kv.put("waitlist", "b", { email: "b@example.com" });
    const ids = kv.list<{ email: string }>("waitlist").map(e => e.id).sort();
    expect(ids).toEqual(["a", "b"]);
    expect(kv.list("waitlist")).toHaveLength(2);
  });

  it("round trips the value shapes the callers actually store", () => {
    const kv = make();
    kv.put("skills-installs", "count", 7);          // lib/skills.ts stores numbers
    kv.put("skills-installs-by", "dev:id", true);   // and booleans
    kv.put("devices", "dev", { days: ["2026-01-01"] });
    kv.put("pages", "p1", { title: "t", places: [], createdAt: 1 });
    expect(kv.get("skills-installs", "count")).toBe(7);
    expect(kv.get("skills-installs-by", "dev:id")).toBe(true);
    expect(kv.get<{ days: string[] }>("devices", "dev")?.days).toEqual(["2026-01-01"]);
    expect(kv.get("pages", "p1")).toEqual({ title: "t", places: [], createdAt: 1 });
  });
});

describe("PostgresKV", () => {
  it("creates its table and index if missing, before any write lands", async () => {
    const db = fakePostgres();
    const kv = new PostgresKV(db.query, () => {});
    kv.put("waitlist", "a", { email: "a@example.com" });
    await kv.flush();
    expect(db.statements[0]).toBe("create table if");
    expect(db.statements).toContain("create index if");
    expect(db.rows.size).toBe(1);
  });

  it("makes a write visible to another instance after flush and refresh", async () => {
    const db = fakePostgres();
    const writer = new PostgresKV(db.query, () => {});
    const reader = new PostgresKV(db.query, () => {});
    writer.put("connections", "dev:google", { access_token: "tok" });
    await writer.flush();

    expect(reader.get("connections", "dev:google")).toBeUndefined();
    await reader.refresh();
    expect(reader.get<{ access_token: string }>("connections", "dev:google")?.access_token).toBe("tok");
  });

  it("propagates a delete to another instance", async () => {
    const db = fakePostgres();
    const writer = new PostgresKV(db.query, () => {});
    const reader = new PostgresKV(db.query, () => {});
    writer.put("connections", "dev:slack", { access_token: "tok" });
    await writer.flush();
    await reader.refresh();
    expect(reader.get("connections", "dev:slack")).toBeDefined();

    writer.del("connections", "dev:slack");
    await writer.flush();
    await reader.refresh();
    expect(reader.get("connections", "dev:slack")).toBeUndefined();
    expect(reader.list("connections")).toEqual([]);
  });

  it("only asks for what changed after the first refresh", async () => {
    const db = fakePostgres();
    const kv = new PostgresKV(db.query, () => {});
    db.external("hub", "g1", { installs: 1 });
    await kv.refresh();
    expect(kv.get("hub", "g1")).toEqual({ installs: 1 });

    db.external("hub", "g2", { installs: 2 });
    await kv.refresh();
    expect(kv.get("hub", "g2")).toEqual({ installs: 2 });
    expect(kv.list("hub")).toHaveLength(2);
  });

  it("does not let a refresh clobber a write that has not landed yet", async () => {
    const db = fakePostgres();
    const kv = new PostgresKV(db.query, () => {});
    db.external("accounts", "dev", { displayName: "old" });
    await kv.refresh();

    kv.put("accounts", "dev", { displayName: "new" }); // queued, not yet in the table
    await kv.refresh();
    expect(kv.get("accounts", "dev")).toEqual({ displayName: "new" });

    await kv.flush();
    await kv.refresh();
    expect(kv.get("accounts", "dev")).toEqual({ displayName: "new" });
  });

  it("keeps serving reads when the store is down, and flush never rejects", async () => {
    const db = fakePostgres();
    const kv = new PostgresKV(db.query, () => {});
    kv.put("telemetry", "2026-01-01:glyf_fired", { count: 1 });
    await kv.flush();

    db.breakStore("connection refused");
    kv.put("telemetry", "2026-01-01:glyf_fired", { count: 2 });
    expect(kv.get("telemetry", "2026-01-01:glyf_fired")).toEqual({ count: 2 });
    await expect(kv.flush()).resolves.toBeUndefined();
    await expect(kv.refresh()).rejects.toThrow(/connection refused/);
    expect(kv.get("telemetry", "2026-01-01:glyf_fired")).toEqual({ count: 2 });
  });

  it("reports its driver and readiness for GET /health", async () => {
    const db = fakePostgres();
    const kv = new PostgresKV(db.query, () => {});
    expect(kv.status?.()).toEqual({ driver: "postgres", ready: false, collections: 0 });
    await kv.refresh();
    expect(kv.status?.().ready).toBe(true);
  });

  it("MemoryKV and FileKV expose no async lifecycle, so local runs pay nothing", () => {
    expect(new MemoryKV().refresh).toBeUndefined();
    expect(new MemoryKV().flush).toBeUndefined();
    expect(tempFileKV().refresh).toBeUndefined();
    expect(tempFileKV().flush).toBeUndefined();
  });
});

/** The hooks buildApp() adds for a store that lives somewhere else. They are
 *  what lets every existing caller keep calling the KV synchronously. */
describe("KV lifecycle hooks", () => {
  class HookKV extends MemoryKV {
    refreshes = 0;
    flushes = 0;
    async refresh(): Promise<void> { this.refreshes += 1; }
    async flush(): Promise<void> { this.flushes += 1; }
  }

  it("refreshes once per request and flushes before the response goes out", async () => {
    const kv = new HookKV();
    const app = buildApp(kv);
    await app.inject({ method: "GET", url: "/health" });
    expect(kv.refreshes).toBe(1);
    expect(kv.flushes).toBe(1);

    const res = await app.inject({
      method: "POST", url: "/waitlist", payload: { email: "someone@example.com" },
    });
    expect(res.statusCode).toBe(200);
    expect(kv.refreshes).toBe(2);
    expect(kv.flushes).toBe(2);
  });

  it("gives the handler what another instance wrote, not a stale mirror", async () => {
    class LateKV extends HookKV {
      async refresh(): Promise<void> {
        await super.refresh();
        this.put("waitlist", "from-another-instance", { email: "a@example.com" });
      }
    }
    const app = buildApp(new LateKV());
    const res = await app.inject({ method: "GET", url: "/waitlist/count" });
    expect(res.json().count).toBe(1);
  });

  it("serves the request anyway when the store cannot be reached", async () => {
    class BrokenKV extends MemoryKV {
      async refresh(): Promise<void> { throw new Error("db unreachable"); }
      async flush(): Promise<void> { /* never rejects, by contract */ }
    }
    const app = buildApp(new BrokenKV());
    const res = await app.inject({ method: "GET", url: "/health" });
    expect(res.statusCode).toBe(200);
    expect(res.json().ok).toBe(true);
  });

  it("exposes the store to the serverless entry point", () => {
    const kv = new HookKV();
    expect(buildApp(kv).glyfKV).toBe(kv);
  });

  /** OAuth start and callback are two requests, so on a serverless host they
   *  can be two instances. The authorization has to live in the store. */
  it("keeps an OAuth authorization in the shared store, not in one instance", async () => {
    process.env.GOOGLE_CLIENT_ID = "test-client";
    process.env.GOOGLE_CLIENT_SECRET = "test-secret";
    try {
      const shared = new MemoryKV();          // one database
      const one = buildApp(shared);           // two instances of the server
      const two = buildApp(shared);

      const start = await one.inject({
        method: "GET",
        url: "/oauth/google/start?deviceId=test-dev-00000001&scopes=calendar",
      });
      const state = new URL(start.json().url).searchParams.get("state") ?? "";
      expect(state).not.toBe("");

      const held = shared.list<{ deviceId: string; provider: string }>("oauth_pending");
      expect(held).toHaveLength(1);
      expect(held[0].id).toBe(state);
      expect(held[0].value).toMatchObject({ deviceId: "test-dev-00000001", provider: "google" });

      // The callback lands on the other instance and consumes it.
      const done = await two.inject({
        method: "GET", url: `/oauth/google/callback?state=${state}&error=access_denied`,
      });
      expect(done.headers.location).toContain("provider=google");
      expect(shared.list("oauth_pending")).toHaveLength(0);
    } finally {
      delete process.env.GOOGLE_CLIENT_ID;
      delete process.env.GOOGLE_CLIENT_SECRET;
    }
  });
});

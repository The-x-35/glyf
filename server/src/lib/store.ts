import { mkdirSync, readFileSync, writeFileSync, existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

/** Durable storage behind ONE interface. Today: JSON files under server/data/
 *  (zero-setup, survives restarts, fine for dev). The Postgres driver drops in
 *  behind the same interface for deploy — SPEC §2 pins Postgres in prod. */
export interface KV {
  get<T>(collection: string, id: string): T | undefined;
  put<T>(collection: string, id: string, value: T): void;
  del(collection: string, id: string): void;
  list<T>(collection: string): { id: string; value: T }[];
}

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

  private flush(collection: string): void {
    const m = this.load(collection);
    writeFileSync(this.file(collection),
      JSON.stringify(Object.fromEntries(m), null, 1));
  }

  get<T>(c: string, id: string): T | undefined {
    return this.load(c).get(id) as T | undefined;
  }

  put<T>(c: string, id: string, value: T): void {
    this.load(c).set(id, value);
    this.flush(c);
  }

  del(c: string, id: string): void {
    this.load(c).delete(id);
    this.flush(c);
  }

  list<T>(c: string): { id: string; value: T }[] {
    return [...this.load(c).entries()].map(([id, value]) => ({ id, value: value as T }));
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
}

const DATA_DIR = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "data");

export function defaultKV(): KV {
  return process.env.NODE_ENV === "test" ? new MemoryKV() : new FileKV(DATA_DIR);
}

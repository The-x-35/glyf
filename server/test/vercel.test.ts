import { createServer, type Server } from "node:http";
import type { AddressInfo } from "node:net";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import handler from "../api/index.js";
import { env } from "../src/env.js";

/** The Vercel entry point is a plain Node request handler, so it can be
 *  checked the way Vercel will run it: hand it a real req/res pair and see
 *  what comes back. The server here is ephemeral (port 0) and closes with the
 *  file. Nothing about `npm run dev` or `npm start` is involved. */

let server: Server;
let base = "";

beforeAll(async () => {
  env.mockAI = true; // no model quota burned, same as the other route tests
  server = createServer((req, res) => { void handler(req, res); });
  await new Promise<void>(resolve => server.listen(0, "127.0.0.1", resolve));
  base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
});

afterAll(async () => {
  await new Promise<void>(resolve => server.close(() => resolve()));
});

describe("vercel function entry", () => {
  it("serves the same routes as the standalone server", async () => {
    const res = await fetch(`${base}/health`);
    expect(res.status).toBe(200);
    const body = await res.json() as Record<string, unknown>;
    expect(body.ok).toBe(true);
    expect(body.storage).toMatchObject({ driver: "memory" });
    const catalog = await (await fetch(`${base}/glyf/catalog`)).json() as { glyfs: unknown[] };
    expect(catalog.glyfs.length).toBeGreaterThanOrEqual(9);
  });

  it("builds the app once and reuses it across requests", async () => {
    const first = await (await fetch(`${base}/health`)).json() as Record<string, unknown>;
    const second = await (await fetch(`${base}/health`)).json() as Record<string, unknown>;
    expect(first.ok).toBe(true);
    expect(second.ok).toBe(true);
  });

  it("passes SSE through unbuffered on POST /glyf/run", async () => {
    const res = await fetch(`${base}/glyf/run`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        glyfId: "rewrite.polite",
        input: "send me the file now",
        vars: {},
        deviceId: "vercel-device-0001",
      }),
    });

    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toContain("text/event-stream");
    // A streamed response has no length up front. A buffered one would.
    expect(res.headers.get("content-length")).toBeNull();
    expect(res.headers.get("transfer-encoding")).toBe("chunked");
    // The proxy-buffering opt-outs have to survive the entry point.
    expect(res.headers.get("x-accel-buffering")).toBe("no");
    expect(res.headers.get("cache-control")).toContain("no-transform");

    const chunks: string[] = [];
    const reader = res.body!.getReader();
    const decoder = new TextDecoder();
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      chunks.push(decoder.decode(value, { stream: true }));
    }
    const payload = chunks.join("");
    expect(chunks.length).toBeGreaterThan(0);
    expect(payload).toContain("event: token");
    expect(payload).toContain("event: done");
    expect(payload).toContain("MOCK polite");
  });

  it("answers a POST route with a normal JSON body", async () => {
    const res = await fetch(`${base}/act`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ text: "2+2", deviceId: "vercel-device-0001" }),
    });
    expect(res.status).toBe(200);
    const body = await res.json() as { ok: boolean; cards: unknown[] };
    expect(body.ok).toBe(true);
    expect(Array.isArray(body.cards)).toBe(true);
  });

  it("404s an unknown path instead of crashing the function", async () => {
    const res = await fetch(`${base}/not-a-route`);
    expect(res.status).toBe(404);
  });
});

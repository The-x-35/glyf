import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { KV } from "../lib/store.js";

/** §12 telemetry sink — EVENTS ONLY, never content. The client batches its
 *  local JSONL up; the funnel endpoint powers the D1/D7/D30 dashboard
 *  (retention math needs accounts + time; counts ship now). */
export function telemetryRoutes(app: FastifyInstance, kv: KV): void {

  const Batch = z.object({
    deviceId: z.string().min(8).max(64),
    events: z.array(z.object({
      event: z.string().min(1).max(64),
      ts: z.string(),
    }).passthrough()).max(500),
  });

  app.post("/telemetry", async (req, reply) => {
    const parsed = Batch.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: "Bad request" });
    const { deviceId, events } = parsed.data;
    const day = new Date().toISOString().slice(0, 10);
    // Content guard (§12): drop any field that looks like free text.
    for (const e of events) {
      for (const key of Object.keys(e)) {
        const v = (e as Record<string, unknown>)[key];
        if (typeof v === "string" && v.length > 80) delete (e as Record<string, unknown>)[key];
      }
      const id = `${day}:${e.event}`;
      const cur = kv.get<{ count: number }>("telemetry", id) ?? { count: 0 };
      kv.put("telemetry", id, { count: cur.count + 1 });
    }
    const seen = kv.get<{ days: string[] }>("devices", deviceId) ?? { days: [] };
    if (!seen.days.includes(day)) {
      kv.put("devices", deviceId, { days: [...seen.days, day].slice(-60) });
    }
    return { ok: true, accepted: events.length };
  });

  app.get("/telemetry/funnel", async () => {
    const counts: Record<string, Record<string, number>> = {};
    for (const { id, value } of kv.list<{ count: number }>("telemetry")) {
      const [day, event] = [id.slice(0, 10), id.slice(11)];
      counts[event] = counts[event] ?? {};
      counts[event][day] = value.count;
    }
    const devices = kv.list<{ days: string[] }>("devices");
    return {
      events: counts,
      activeDevices: devices.length,
      note: "D1/D7/D30 retention lands with accounts (M7-ship)",
    };
  });
}

import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { Reports } from "../lib/reports.js";

/**
 * POST /report — someone flags an AI result from the keyboard's AI panel
 * (Google Play's AI-Generated Content policy: report offensive output
 * without leaving the app). Behind the sign-in gate like everything else;
 * kept in Postgres (lib/reports.ts) to be looked at.
 */

const ReportSchema = z.object({
  deviceId: z.string().min(8).max(64),
  feature: z.string().min(1).max(64),
  result: z.string().min(1).max(4000),
  reason: z.string().max(500).optional(),
  platform: z.enum(["ios", "android"]).optional(),
});

const HOUR = 3600 * 1000;
/** Reports a phone may send an hour: plenty for honest use. */
const PER_HOUR = 10;

export interface ReportDeps {
  reports?: Reports;
  now?: () => number;
}

export function reportRoutes(app: FastifyInstance, deps: ReportDeps = {}): void {
  const reports = deps.reports ?? new Reports();
  const now = deps.now ?? Date.now;
  const sent = new Map<string, number[]>();

  app.post("/report", async (req, reply) => {
    const parsed = ReportSchema.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ ok: false, error: "Bad request" });
    const { deviceId, feature, result, reason, platform } = parsed.data;
    const t = now();
    // Counted per account when signed in: a new deviceId is free to make.
    const sender = req.glyfUser ? `user:${req.glyfUser}` : deviceId;
    const times = (sent.get(sender) ?? []).filter(at => t - at < HOUR);
    if (times.length >= PER_HOUR) {
      return reply.code(429).send({ ok: false, error: "That's a lot of reports. Try again later." });
    }
    sent.set(sender, [...times, t]);
    if (!reports.enabled) {
      // A local server without a database: say so in its log, not to the phone.
      req.log.warn({ feature, platform }, "report_not_stored_no_database");
      return { ok: true };
    }
    try {
      await reports.add({
        userId: req.glyfUser ?? null, deviceId, feature, result,
        reason: reason ?? "", platform: platform ?? "",
      });
    } catch (err) {
      req.log.error({ err: err instanceof Error ? err.message : String(err) }, "report_failed");
      return reply.code(503).send({ ok: false, error: "Couldn't send the report. Try again in a moment." });
    }
    req.log.info({ feature, platform }, "report");
    return { ok: true };
  });
}

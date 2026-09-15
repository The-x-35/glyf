import type { FastifyInstance } from "fastify";
import type { MeterStore } from "../lib/meter.js";

/** §6.16: the remaining-runs chip reads this. */
export function meterRoutes(app: FastifyInstance, meter: MeterStore): void {
  app.get<{ Params: { deviceId: string } }>("/meter/:deviceId", async req => ({
    remaining: meter.remaining(req.params.deviceId),
  }));
}

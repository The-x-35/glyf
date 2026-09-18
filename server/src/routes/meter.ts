import type { FastifyInstance } from "fastify";
import type { Guard } from "../lib/guard.js";

/** §6.16: the remaining-runs chip reads this. Signed in, it answers for the
 *  account; signed out, for the phone. */
export function meterRoutes(app: FastifyInstance, guard: Guard): void {
  app.get<{ Params: { deviceId: string } }>("/meter/:deviceId", async req => ({
    remaining: await guard.left(req, req.params.deviceId),
  }));
}

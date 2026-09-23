import type { FastifyInstance } from "fastify";
import type { Guard } from "../lib/guard.js";

/** §6.16: the remaining-runs chip and the app's plan card read this. Signed
 *  in, it answers for the account; signed out, for the phone. The plan comes
 *  with it, so the app never claims a plan the server is not enforcing. */
export function meterRoutes(app: FastifyInstance, guard: Guard): void {
  app.get<{ Params: { deviceId: string } }>("/meter/:deviceId", async req =>
    guard.status(req, req.params.deviceId));
}

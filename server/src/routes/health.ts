import type { FastifyInstance } from "fastify";
import { env } from "../env.js";

export function healthRoutes(app: FastifyInstance): void {
  app.get("/health", async () => ({
    ok: true,
    mockAI: env.mockAI,
    fastModels: env.fastModels,
    // Never echo secrets — presence booleans only (§1.6).
    hasOpenRouterKey: env.openrouterKey.length > 0,
  }));
}

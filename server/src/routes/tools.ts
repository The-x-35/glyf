import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { loadTools, runTool } from "../lib/tools.js";

/** Direct tool runs for the keyboard's search surface (Gboard-style
 *  Search / YouTube / Maps tabs). Keyless tools only — anything needing a
 *  user connection keeps going through the engine, where per-device tokens
 *  are resolved. No LLM cost, so runs don't touch the plan meter; each
 *  tool's own rateLimit still applies. */

const BodySchema = z.object({
  id: z.string().min(1).max(64),
  args: z.record(z.string(), z.string().max(300)).default({}),
  deviceId: z.string().min(1).max(80),
});

export function toolsRoutes(app: FastifyInstance): void {
  app.post("/tools/run", async (req, reply) => {
    const parsed = BodySchema.safeParse(req.body);
    if (!parsed.success) {
      return reply.code(400).send({ error: "bad request" });
    }
    const { id, args } = parsed.data;
    const meta = loadTools().get(id);
    if (!meta) return reply.code(404).send({ error: "That tool isn't available." });
    if (meta.auth !== "none") {
      return reply.code(403).send({ error: "connected tools run through your glyfs" });
    }
    try {
      const result = await runTool(id, args, {});
      return { ok: true, result };
    } catch (err) {
      // A tool's refusal is worded for the person ("No quote for 'xyz'"); a
      // service that broke is ours to read in the log, not theirs.
      const userFacing = (err as { userFacing?: boolean })?.userFacing === true;
      req.log.warn({ tool: id, err: err instanceof Error ? err.message : String(err) }, "tool failed");
      return reply.code(502).send({
        ok: false,
        error: userFacing ? (err as Error).message : "Couldn't get that right now. Try again.",
      });
    }
  });
}

import type { FastifyInstance } from "fastify";
import { z } from "zod";
import type { KV } from "../lib/store.js";

/** Marketing-site waitlist. Emails land in kv (deduped, capped); nothing
 *  else is collected. GET /waitlist/count feeds the site's social proof. */

const BodySchema = z.object({
  email: z.string().trim().toLowerCase().email().max(120),
});

const CAP = 50_000;

export function waitlistRoutes(app: FastifyInstance, kv: KV): void {
  app.post("/waitlist", async (req, reply) => {
    const parsed = BodySchema.safeParse(req.body);
    if (!parsed.success) {
      return reply.code(400).send({ ok: false, error: "That email doesn't look right" });
    }
    const email = parsed.data.email;
    const id = Buffer.from(email).toString("base64url");
    const existing = kv.get<{ email: string; at: string }>("waitlist", id);
    if (!existing) {
      if (kv.list("waitlist").length >= CAP) {
        return reply.code(503).send({ ok: false, error: "Waitlist is full" });
      }
      kv.put("waitlist", id, { email, at: new Date().toISOString() });
    }
    return { ok: true, count: kv.list("waitlist").length };
  });

  app.get("/waitlist/count", async () => {
    return { count: kv.list("waitlist").length };
  });
}

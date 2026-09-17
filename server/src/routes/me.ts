import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";
import { z } from "zod";
import { privyProfile, Users, verifyPrivyToken, type PrivyProfile } from "../lib/users.js";

/**
 * The signed-in person.
 *
 * POST   /me         who I am and the phone I'm on (after every sign-in)
 * POST   /me/prefs   my keyboard settings (the non-private ones)
 * POST   /me/events  what I did in the app (names and counts, never text)
 * DELETE /me         forget me
 *
 * Every call carries the Privy access token; the server checks its signature
 * and reads email and name from Privy itself.
 */

const DeviceSchema = z.object({
  platform: z.enum(["ios", "android"]).optional(),
  appVersion: z.string().max(32).optional(),
  locale: z.string().max(35).optional(),
  region: z.string().max(8).optional(),
  timezone: z.string().max(64).optional(),
});

const PrefsSchema = z.object({ prefs: z.record(z.string(), z.unknown()) });

const EventsSchema = z.object({
  events: z.array(z.object({
    name: z.string().min(1).max(64),
    props: z.record(z.string(), z.unknown()).optional(),
    at: z.string().max(40).optional(),
  })).max(100),
});

export interface MeDeps {
  users?: Users;
  verify?: (token: string) => Promise<string | null>;
  profile?: (userId: string) => Promise<PrivyProfile>;
}

export function meRoutes(app: FastifyInstance, deps: MeDeps = {}): void {
  const users = deps.users ?? new Users();
  const check = deps.verify ?? ((t: string) => verifyPrivyToken(t));
  const profileOf = deps.profile ?? ((id: string) => privyProfile(id).catch((): PrivyProfile => ({})));

  async function who(req: FastifyRequest, reply: FastifyReply): Promise<string | null> {
    const header = req.headers.authorization ?? "";
    const token = header.startsWith("Bearer ") ? header.slice(7).trim() : "";
    const id = token ? await check(token) : null;
    if (!id) {
      await reply.code(401).send({ ok: false, error: "Sign in again" });
      return null;
    }
    return id;
  }

  app.post("/me", async (req, reply) => {
    const id = await who(req, reply);
    if (!id) return reply;
    const parsed = DeviceSchema.safeParse(req.body ?? {});
    if (!parsed.success) return reply.code(400).send({ ok: false, error: "Bad request" });
    const profile = await profileOf(id);
    if (users.enabled) {
      try {
        await users.upsert(id, profile, parsed.data);
      } catch (err) {
        req.log.error({ err: err instanceof Error ? err.message : String(err) }, "me_upsert_failed");
        return reply.code(503).send({ ok: false, error: "Could not save your account right now" });
      }
    }
    return { ok: true, stored: users.enabled, user: { id, email: profile.email ?? null, name: profile.name ?? null } };
  });

  app.post("/me/prefs", async (req, reply) => {
    const id = await who(req, reply);
    if (!id) return reply;
    const parsed = PrefsSchema.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ ok: false, error: "Bad request" });
    if (!users.enabled) return { ok: true, stored: false };
    try {
      await users.savePrefs(id, parsed.data.prefs);
      return { ok: true, stored: true };
    } catch (err) {
      req.log.error({ err: err instanceof Error ? err.message : String(err) }, "me_prefs_failed");
      return reply.code(503).send({ ok: false, error: "Could not save settings right now" });
    }
  });

  app.post("/me/events", async (req, reply) => {
    const id = await who(req, reply);
    if (!id) return reply;
    const parsed = EventsSchema.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ ok: false, error: "Bad request" });
    if (!users.enabled) return { ok: true, stored: 0 };
    try {
      return { ok: true, stored: await users.addEvents(id, parsed.data.events) };
    } catch (err) {
      req.log.error({ err: err instanceof Error ? err.message : String(err) }, "me_events_failed");
      return reply.code(503).send({ ok: false, error: "Could not save events right now" });
    }
  });

  app.delete("/me", async (req, reply) => {
    const id = await who(req, reply);
    if (!id) return reply;
    if (users.enabled) {
      try {
        await users.remove(id);
      } catch (err) {
        req.log.error({ err: err instanceof Error ? err.message : String(err) }, "me_delete_failed");
        return reply.code(503).send({ ok: false, error: "Could not delete your account right now" });
      }
    }
    return { ok: true };
  });
}

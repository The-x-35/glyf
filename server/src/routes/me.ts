import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";
import { z } from "zod";
import { forgetDevices } from "../lib/forget.js";
import { checkConfirmation, issueConfirmation, verifySession } from "../lib/identity.js";
import type { KV } from "../lib/store.js";
import { Users } from "../lib/users.js";

/**
 * The signed-in person.
 *
 * POST   /me         who I am and the phone I'm on (after every sign-in)
 * POST   /me/prefs   my keyboard settings (the non-private ones)
 * POST   /me/events  what I did in the app (names and counts, never text)
 * POST   /me/delete  "I mean it": a confirmation good for five minutes
 * DELETE /me         forget me (with that confirmation)
 *
 * Every call carries the Glyf session from POST /auth/session (after Sign in
 * with Apple or Google); email and name were taken from the provider's
 * verified token then.
 */

const DeviceSchema = z.object({
  platform: z.enum(["ios", "android"]).optional(),
  appVersion: z.string().max(32).optional(),
  locale: z.string().max(35).optional(),
  region: z.string().max(8).optional(),
  timezone: z.string().max(64).optional(),
});

const PrefsSchema = z.object({ prefs: z.record(z.string(), z.unknown()) });

const PlanSchema = z.object({ plan: z.enum(["free", "plus", "max"]) });

const EventsSchema = z.object({
  events: z.array(z.object({
    name: z.string().min(1).max(64),
    props: z.record(z.string(), z.unknown()).optional(),
    at: z.string().max(40).optional(),
  })).max(100),
});

const DeleteSchema = z.object({
  confirm: z.string().min(1).max(200),
  /** The phone's device ids (shared settings `deviceId`): what is filed
   *  under the phone rather than the account goes too (lib/forget.ts). */
  deviceIds: z.array(z.string().min(8).max(80)).max(4).optional(),
});

const DELETE_PURPOSE = "delete-account";

export interface MeDeps {
  users?: Users;
  verify?: (token: string) => Promise<string | null>;
  /** Where device-keyed data lives (glyfs, installs, connections). */
  kv?: KV;
  /** Signs confirmations; SESSION_SECRET when not given. */
  confirmSecret?: string;
}

export function meRoutes(app: FastifyInstance, deps: MeDeps = {}): void {
  const users = deps.users ?? new Users();
  const check = deps.verify ?? (async (t: string) => verifySession(t));

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
    if (users.enabled) {
      try {
        // The phone it is on now; who they are was saved at sign-in.
        await users.upsert(id, {}, parsed.data);
      } catch (err) {
        req.log.error({ err: err instanceof Error ? err.message : String(err) }, "me_upsert_failed");
        return reply.code(503).send({ ok: false, error: "Could not save your account right now" });
      }
    }
    return { ok: true, stored: users.enabled, user: { id } };
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

  /** The plan, as the paywall picks it. Until App Store receipts land this
   *  is a self-serve switch, and it is OFF unless PLAN_SELF_SERVE=true (dev
   *  and TestFlight): a shipped server never hands out plans for a tap.
   *  Whatever it says, the app and the keyboard then read the same answer
   *  back from /meter, so the two never disagree about what a person has. */
  app.post("/me/plan", async (req, reply) => {
    const id = await who(req, reply);
    if (!id) return reply;
    const parsed = PlanSchema.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ ok: false, error: "Bad request" });
    if (process.env.PLAN_SELF_SERVE !== "true") {
      return reply.code(403).send({ ok: false, error: "Plans arrive with the App Store build" });
    }
    if (!users.enabled) return { ok: true, stored: false, plan: parsed.data.plan };
    try {
      await users.setPlan(id, parsed.data.plan);
      return { ok: true, stored: true, plan: parsed.data.plan };
    } catch (err) {
      req.log.error({ err: err instanceof Error ? err.message : String(err) }, "me_plan_failed");
      return reply.code(503).send({ ok: false, error: "Could not change your plan right now" });
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

  /** Step one of Delete account: the app asks once the person has confirmed
   *  on the phone, and sends what comes back with DELETE /me. A session
   *  lasts months; this lasts five minutes, so a token kept somewhere can't
   *  delete an account on its own. */
  app.post("/me/delete", async (req, reply) => {
    const id = await who(req, reply);
    if (!id) return reply;
    const confirm = issueConfirmation(id, DELETE_PURPOSE, { secret: deps.confirmSecret });
    if (!confirm) return reply.code(503).send({ ok: false, error: "Could not delete your account right now" });
    return { ok: true, confirm, expiresIn: 300 };
  });

  /** Deletes the account and everything kept for it (Users.remove) and for
   *  the phones it names (forgetDevices). Asking again is fine: there is
   *  nothing left and it says ok. */
  app.delete("/me", async (req, reply) => {
    const id = await who(req, reply);
    if (!id) return reply;
    const parsed = DeleteSchema.safeParse(req.body ?? {});
    if (!parsed.success || !checkConfirmation(parsed.data.confirm, id, DELETE_PURPOSE,
      { secret: deps.confirmSecret })) {
      return reply.code(428).send({ ok: false, error: "Confirm again to delete your account", confirm: "required" });
    }
    const deviceIds = [...new Set(parsed.data.deviceIds ?? [])];
    if (users.enabled) {
      try {
        await users.remove(id, deviceIds);
      } catch (err) {
        req.log.error({ err: err instanceof Error ? err.message : String(err) }, "me_delete_failed");
        return reply.code(503).send({ ok: false, error: "Could not delete your account right now" });
      }
    }
    const rows = deps.kv ? forgetDevices(deps.kv, deviceIds) : 0;
    // Counts only: the account is gone, its id doesn't go in the log either.
    req.log.info({ devices: deviceIds.length, kvRows: rows }, "account_deleted");
    return { ok: true, stored: users.enabled };
  });
}

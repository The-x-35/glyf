import type { FastifyInstance, FastifyRequest } from "fastify";
import { z } from "zod";
import { TTLCache } from "../lib/cache.js";
import type { Guard } from "../lib/guard.js";
import { verifySession } from "../lib/identity.js";
import {
  createAddress, deleteAddress, listMessages, signInbox, TempMailError, verifyInbox,
} from "../lib/tempmail.js";

/**
 * Temp mail for the keyboard (lib/tempmail.ts):
 *
 *   POST /tempmail           a new address, and the token that reads it
 *   POST /tempmail/messages  what it has received, newest first
 *   POST /tempmail/delete    done with it
 *
 * Addresses travel in bodies, never in URLs, so they stay out of access
 * logs. Every route needs a signed-in person (protectRoutes) and only reads
 * an address with the token issued to that same person. New addresses and
 * checks have their own daily allowances (Guard.tempInbox, Guard.tempCheck);
 * neither spends a run. The log carries events only: never an address, a
 * sender, a subject or a code.
 */

const Device = z.object({ deviceId: z.string().min(1).max(80) });
const Inbox = Device.extend({
  address: z.string().min(3).max(254).regex(/^[^\s@]+@[^\s@]+\.[^\s@]+$/),
  token: z.string().min(10).max(200),
});

function userOf(req: FastifyRequest): string | null {
  const header = req.headers.authorization ?? "";
  const token = header.startsWith("Bearer ") ? header.slice(7).trim() : "";
  return token ? verifySession(token) : null;
}

function refuse(reply: { code: (n: number) => { send: (b: unknown) => unknown } }, err: unknown) {
  if (err instanceof TempMailError) {
    const status = err.status === 404 ? 410 : err.status === 429 ? 429 : err.status === 503 ? 503 : 502;
    return reply.code(status).send({ ok: false, error: err.message });
  }
  return reply.code(502).send({ ok: false, error: "Temp mail didn't answer. Try again in a moment" });
}

export function tempMailRoutes(app: FastifyInstance, guard: Guard): void {
  // Several keyboards (or one asking every few seconds) watching an address
  // cost one request upstream in this window.
  const cache = new TTLCache(6_000, 1000);

  app.post("/tempmail", async (req, reply) => {
    const parsed = Device.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ ok: false, error: "Bad request" });
    const userId = userOf(req);
    if (!userId) return reply.code(401).send({ ok: false, error: "Sign in to use Glyf" });
    const gate = await guard.tempInbox(req, parsed.data.deviceId);
    if (!gate.ok) return reply.code(429).send({ ok: false, error: gate.message });
    try {
      const made = await createAddress();
      req.log.info({ event: "tempmail_created" }, "tempmail");
      return { ok: true, address: made.address, expiresAt: made.expiresAt,
        token: signInbox(userId, made.address, made.expiresAt) };
    } catch (err) {
      req.log.warn({ status: err instanceof TempMailError ? err.status : 0 }, "tempmail create failed");
      return refuse(reply, err);
    }
  });

  app.post("/tempmail/messages", async (req, reply) => {
    const parsed = Inbox.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ ok: false, error: "Bad request" });
    const userId = userOf(req);
    const { address, token, deviceId } = parsed.data;
    if (!userId || !verifyInbox(userId, address, token)) {
      return reply.code(403).send({ ok: false, error: "That address isn't yours, or it has expired" });
    }
    const key = TTLCache.key(["tempmail", address.toLowerCase()]);
    const hit = cache.get(key);
    // A cached look costs nothing upstream, so it costs nothing here.
    if (hit !== undefined) return { ok: true, messages: JSON.parse(hit) };
    const gate = await guard.tempCheck(req, deviceId);
    if (!gate.ok) return reply.code(429).send({ ok: false, error: gate.message });
    try {
      const messages = await listMessages(address);
      cache.set(key, JSON.stringify(messages));
      return { ok: true, messages };
    } catch (err) {
      return refuse(reply, err);
    }
  });

  app.post("/tempmail/delete", async (req, reply) => {
    const parsed = Inbox.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ ok: false, error: "Bad request" });
    const userId = userOf(req);
    const { address, token } = parsed.data;
    if (!userId || !verifyInbox(userId, address, token)) {
      return reply.code(403).send({ ok: false, error: "That address isn't yours, or it has expired" });
    }
    try {
      await deleteAddress(address);
    } catch (err) {
      // Already gone is what was asked for.
      if (!(err instanceof TempMailError && err.status === 404)) return refuse(reply, err);
    }
    cache.delete(TTLCache.key(["tempmail", address.toLowerCase()]));
    return { ok: true };
  });
}

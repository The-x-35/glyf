import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { issueSession, signInConfig, verifyIdToken, type Identity, type Provider } from "../lib/identity.js";
import { Users } from "../lib/users.js";

/**
 * Signing in.
 *
 * GET  /auth/config   which ways in are set up, with the public client ids
 * POST /auth/session  an Apple or Google ID token in, a Glyf session out
 *
 * The phone signs in natively and sends the provider's token with the nonce
 * it made; the token is checked against Apple's or Google's keys here, the
 * person is saved, and the session that comes back is what /me calls carry.
 */

const SessionSchema = z.object({
  provider: z.enum(["google", "apple"]),
  idToken: z.string().min(20).max(8000),
  nonce: z.string().min(16).max(200),
  /** Apple sends a name to the phone once, on the first sign-in only. */
  name: z.string().max(120).optional(),
  device: z.object({
    platform: z.enum(["ios", "android"]).optional(),
    appVersion: z.string().max(32).optional(),
    locale: z.string().max(35).optional(),
    region: z.string().max(8).optional(),
    timezone: z.string().max(64).optional(),
  }).optional(),
});

export interface AuthDeps {
  users?: Users;
  verify?: (provider: Provider, idToken: string, nonce: string) => Promise<Identity | null>;
  issue?: (userId: string) => string | null;
}

export function authRoutes(app: FastifyInstance, deps: AuthDeps = {}): void {
  const users = deps.users ?? new Users();
  const verifyToken = deps.verify ?? ((provider, idToken, nonce) => verifyIdToken(provider, idToken, { nonce }));
  const issue = deps.issue ?? ((userId: string) => issueSession(userId));

  app.get("/auth/config", async () => ({ ok: true, ...signInConfig() }));

  app.post("/auth/session", async (req, reply) => {
    const parsed = SessionSchema.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ ok: false, error: "Bad request" });
    const { provider, idToken, nonce, name, device } = parsed.data;

    const identity = await verifyToken(provider, idToken, nonce);
    if (!identity) {
      req.log.warn({ provider }, "auth_token_rejected");
      return reply.code(401).send({ ok: false, error: "Sign-in could not be verified. Try again." });
    }
    const userId = `${identity.provider}:${identity.sub}`;
    const token = issue(userId);
    if (!token) {
      req.log.error("auth_no_session_secret");
      return reply.code(503).send({ ok: false, error: "Sign-in is not set up yet." });
    }
    // Apple's token never carries a name; the phone passes the one Apple gave
    // it on the first sign-in, and only for Apple.
    const displayName = identity.name ?? (provider === "apple" ? name?.trim() || undefined : undefined);
    if (users.enabled) {
      try {
        await users.upsert(userId, { email: identity.email, name: displayName, method: provider }, device ?? {});
      } catch (err) {
        req.log.error({ err: err instanceof Error ? err.message : String(err) }, "auth_upsert_failed");
        return reply.code(503).send({ ok: false, error: "Could not save your account right now" });
      }
    }
    return {
      ok: true,
      token,
      user: { id: userId, provider, email: identity.email ?? null, name: displayName ?? null },
    };
  });
}

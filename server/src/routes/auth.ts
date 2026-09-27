import { createHash, timingSafeEqual } from "node:crypto";
import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { issueSession, signInConfig, verifyIdToken, type Identity, type Provider } from "../lib/identity.js";
import { Users } from "../lib/users.js";

/**
 * Signing in.
 *
 * GET  /auth/config   which ways in are set up, with the public client ids
 * POST /auth/session  an Apple or Google ID token in, a Glyf session out
 * POST /auth/review   App Review's way in: the passphrase from App Store
 *                     Connect, no Apple or Google account
 *
 * The phone signs in natively and sends the provider's token with the nonce
 * it made; the token is checked against Apple's or Google's keys here, the
 * person is saved, and the session that comes back is what /me calls carry.
 *
 * Review: Glyf has no email-and-password accounts, but App Store Connect
 * wants credentials a reviewer can type. REVIEW_PASSWORD (env) is that
 * password; it signs the reviewer into one shared account
 * (review:appstore) and puts a month of Max on it, so every feature is
 * there to review. The app shows this door only from the sign-in screen's
 * hidden triple-tap, as the review notes say.
 */

const ReviewSchema = z.object({
  password: z.string().min(1).max(200),
});
const HOUR = 3600 * 1000;
/** Wrong guesses an address gets an hour. */
const REVIEW_MISSES_PER_HOUR = 10;
export const REVIEW_USER_ID = "review:appstore";

/** Equal without leaking how far the guess got. */
function same(a: string, b: string): boolean {
  return timingSafeEqual(createHash("sha256").update(a).digest(), createHash("sha256").update(b).digest());
}

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
  reviewPassword?: () => string;
  reviewMode?: () => boolean;
  now?: () => number;
}

export function authRoutes(app: FastifyInstance, deps: AuthDeps = {}): void {
  const users = deps.users ?? new Users();
  const verifyToken = deps.verify ?? ((provider, idToken, nonce) => verifyIdToken(provider, idToken, { nonce }));
  const issue = deps.issue ?? ((userId: string) => issueSession(userId));
  const reviewPassword = deps.reviewPassword ?? (() => (process.env.REVIEW_PASSWORD ?? "").trim());
  // The on-off switch, so the password never has to be set twice: Railway's
  // REVIEW_MODE=true while a submission is in review, false the rest of the
  // time — the link and the door go together.
  const reviewMode = deps.reviewMode ?? (() => (process.env.REVIEW_MODE ?? "").trim().toLowerCase() === "true");
  const now = deps.now ?? Date.now;
  const reviewMisses = new Map<string, number[]>();

  // `review` switches the sign-in screen's App Review link on and off from
  // the server (REVIEW_MODE on Railway).
  app.get("/auth/config", async () =>
    ({ ok: true, ...signInConfig(), review: reviewMode() && Boolean(reviewPassword()) }));

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

  app.post("/auth/review", async (req, reply) => {
    const expected = reviewPassword();
    if (!reviewMode() || !expected) {
      return reply.code(503).send({ ok: false, error: "Reviewer sign-in is not set up." });
    }
    const address = req.ip || "?";
    const recent = (reviewMisses.get(address) ?? []).filter(t => now() - t < HOUR);
    if (recent.length >= REVIEW_MISSES_PER_HOUR) {
      return reply.code(429).send({ ok: false, error: "Too many tries. Try again in an hour." });
    }
    const parsed = ReviewSchema.safeParse(req.body);
    if (!parsed.success || !same(parsed.data.password, expected)) {
      reviewMisses.set(address, [...recent, now()]);
      req.log.warn("auth_review_rejected");
      return reply.code(401).send({ ok: false, error: "That isn't the reviewer password." });
    }
    const token = issue(REVIEW_USER_ID);
    if (!token) {
      req.log.error("auth_no_session_secret");
      return reply.code(503).send({ ok: false, error: "Sign-in is not set up yet." });
    }
    let plan = "max";
    if (users.enabled) {
      try {
        await users.upsert(REVIEW_USER_ID,
          { email: "review@tryglyf.com", name: "App Review", method: "review" }, {});
        // A month of Max, refreshed on each sign-in: reviewers see the paid
        // features without a purchase. One shared row, so it never stacks.
        await users.recordPurchase(REVIEW_USER_ID, {
          originalTransactionId: "review:appstore",
          productId: "review.max",
          plan: "max",
          expiresAt: new Date(now() + 30 * 24 * HOUR),
          environment: "review",
        });
        plan = (await users.refreshPlan(REVIEW_USER_ID)).plan;
      } catch (err) {
        req.log.error({ err: err instanceof Error ? err.message : String(err) }, "auth_review_upsert_failed");
      }
    }
    req.log.info({ plan }, "auth_review_signed_in");
    return {
      ok: true,
      token,
      // The phone keeps the plan the way a purchase would leave it.
      plan,
      user: { id: REVIEW_USER_ID, provider: "review", email: "review@tryglyf.com", name: "App Review" },
    };
  });
}

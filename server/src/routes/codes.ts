import type { FastifyInstance, FastifyRequest } from "fastify";
import { z } from "zod";
import { Codes, normalizeCode } from "../lib/codes.js";
import { verifySession } from "../lib/identity.js";
import { Users } from "../lib/users.js";

/**
 * POST /codes/redeem — a gift code (lib/codes.ts) puts its plan on the
 * signed-in account for its days: a month or a year of Max.
 *
 * The plan is kept as a purchase named "code:ABC123", so it runs out, stacks
 * and is outranked exactly the way an App Store subscription is
 * (Users.refreshPlan): Max over Plus, then whichever runs longest.
 */

const RedeemSchema = z.object({ code: z.string().min(1).max(40) });
const DAY = 24 * 3600 * 1000;
const HOUR = 3600 * 1000;
/** Wrong guesses an account gets an hour: with about 890 million possible
 *  codes, nobody walks their way to a real one. */
const MISSES_PER_HOUR = 10;

export interface CodeDeps {
  users?: Users;
  codes?: Codes;
  verifySessionToken?: (token: string) => Promise<string | null>;
  now?: () => number;
}

export function codeRoutes(app: FastifyInstance, deps: CodeDeps = {}): void {
  const users = deps.users ?? new Users();
  const codes = deps.codes ?? new Codes();
  const session = deps.verifySessionToken ?? (async (t: string) => verifySession(t));
  const now = deps.now ?? Date.now;
  const misses = new Map<string, number[]>();

  async function who(req: FastifyRequest): Promise<string | null> {
    const header = req.headers.authorization ?? "";
    const token = header.startsWith("Bearer ") ? header.slice(7).trim() : "";
    return token ? await session(token).catch(() => null) : null;
  }

  function recentMisses(id: string): number[] {
    const recent = (misses.get(id) ?? []).filter(t => now() - t < HOUR);
    if (recent.length > 0) misses.set(id, recent);
    else misses.delete(id);
    return recent;
  }

  function miss(id: string): void {
    misses.set(id, [...recentMisses(id), now()]);
  }

  app.post("/codes/redeem", async (req, reply) => {
    const id = await who(req);
    if (!id) return reply.code(401).send({ ok: false, error: "Sign in again" });
    if (recentMisses(id).length >= MISSES_PER_HOUR) {
      return reply.code(429).send({ ok: false, error: "Too many tries. Try again in an hour" });
    }
    const parsed = RedeemSchema.safeParse(req.body);
    const code = parsed.success ? normalizeCode(parsed.data.code) : null;
    if (!code) {
      miss(id);
      return reply.code(400).send({ ok: false, error: "A code is 6 letters and numbers" });
    }
    if (!users.enabled || !codes.enabled) {
      return reply.code(503).send({ ok: false, error: "Codes can't be used right now" });
    }

    try {
      const claim = await codes.claim(code, id);
      if (!claim.ok) {
        miss(id);
        return claim.reason === "used"
          ? reply.code(409).send({ ok: false, error: "That code has already been used" })
          : reply.code(404).send({ ok: false, error: "That code doesn't exist" });
      }
      // On top of the same plan, the code's days start where that plan ends.
      const current = await users.refreshPlan(id);
      const runsTo = current.plan === claim.plan ? current.expiresAt?.getTime() ?? 0 : 0;
      const expiresAt = new Date(Math.max(now(), runsTo) + claim.days * DAY);
      try {
        await users.recordPurchase(id, {
          originalTransactionId: `code:${code}`,
          productId: `code.${claim.plan}.${claim.days}d`,
          plan: claim.plan,
          expiresAt,
          environment: "code",
        });
      } catch (err) {
        await codes.release(code, id).catch(() => {});
        throw err;
      }
      const { plan, expiresAt: until } = await users.refreshPlan(id);
      req.log.info({ plan, days: claim.days }, "code_redeemed");
      return { ok: true, plan, codePlan: claim.plan, days: claim.days, expiresAt: until?.toISOString() ?? null };
    } catch (err) {
      req.log.error({ err: err instanceof Error ? err.message : String(err) }, "code_redeem_failed");
      return reply.code(503).send({ ok: false, error: "Couldn't use the code right now. Try again in a moment" });
    }
  });
}

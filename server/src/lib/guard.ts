/** Who is asking, and what they are allowed to spend.
 *
 *  Signed in, the account carries the cap: the key is the user id and the
 *  plan is the one on their row, so a second phone doesn't double anyone's
 *  day. Signed out, the phone carries it. Either way the client's own claim
 *  about its plan is ignored — it is the database's word, not the app's.
 */
import type { FastifyRequest } from "fastify";
import { verifySession } from "./identity.js";
import { allow, capsFor, refusal, suggestCapsFor, translateCapsFor, type Allowance, type Caps, type Limiter, type Plan } from "./limits.js";
import { Users } from "./users.js";

export interface GuardDeps {
  limits: Limiter;
  users?: Users;
  verify?: (token: string) => Promise<string | null>;
  freePerDay: number;
  /** The strip's suggestions a free plan gets a day (their own count). */
  freeSuggestionsPerDay?: number;
  /** The translate bar's translations a free plan gets a day (their own count). */
  freeTranslationsPerDay?: number;
}

export interface Verdict extends Allowance {
  plan: Plan;
  key: string;
  /** What to tell them when ok is false. */
  message: string;
}

export class Guard {
  private readonly users: Users;
  private readonly verify: (token: string) => Promise<string | null>;

  constructor(private readonly deps: GuardDeps) {
    this.users = deps.users ?? new Users();
    this.verify = deps.verify ?? (async (t: string) => verifySession(t));
  }

  private async who(req: FastifyRequest, deviceId: string): Promise<{ key: string; plan: Plan }> {
    const header = req.headers.authorization ?? "";
    const token = header.startsWith("Bearer ") ? header.slice(7).trim() : "";
    const userId = token ? await this.verify(token).catch(() => null) : null;
    if (!userId) return { key: `device:${deviceId || "unknown"}`, plan: "free" };
    let plan: Plan = "free";
    if (this.users.enabled) {
      try {
        plan = await this.users.plan(userId);
      } catch {
        // A database that isn't answering caps at free rather than opening up.
        plan = "free";
      }
    }
    return { key: `user:${userId}`, plan };
  }

  /** Spends one run if there is one to spend. */
  async spend(req: FastifyRequest, deviceId: string, now = new Date()): Promise<Verdict> {
    const { key, plan } = await this.who(req, deviceId);
    const caps = capsFor(plan, this.deps.freePerDay);
    const verdict = await allow(this.deps.limits, key, caps, now);
    return { ...verdict, plan, key, message: refusal(verdict.reason, plan) };
  }

  /** Spends one of the strip's suggestions, never a run: they are counted
   *  under their own key, so a day of chatting can't use up the runs someone
   *  holds space for. */
  suggest(req: FastifyRequest, deviceId: string, now = new Date()): Promise<Verdict> {
    return this.spendApart(req, deviceId, "suggest", plan =>
      suggestCapsFor(plan, this.deps.freeSuggestionsPerDay ?? 100),
      "No more suggestions today. They come back tomorrow", now);
  }

  /** Spends one of the translate bar's translations, never a run. */
  translate(req: FastifyRequest, deviceId: string, now = new Date()): Promise<Verdict> {
    return this.spendApart(req, deviceId, "translate", plan =>
      translateCapsFor(plan, this.deps.freeTranslationsPerDay ?? 100),
      "No more translations today. They come back tomorrow", now);
  }

  private async spendApart(req: FastifyRequest, deviceId: string, kind: string,
    capsOf: (plan: Plan) => Caps, usedUp: string, now: Date): Promise<Verdict> {
    const { key, plan } = await this.who(req, deviceId);
    const verdict = await allow(this.deps.limits, `${kind}:${key}`, capsOf(plan), now);
    const message = verdict.reason === "burst" ? refusal("burst", plan) : usedUp;
    return { ...verdict, plan, key, message };
  }

  /** What is left today, spending nothing. */
  async left(req: FastifyRequest, deviceId: string, now = new Date()): Promise<number> {
    return (await this.status(req, deviceId, now)).remaining;
  }

  /** What is left today and on which plan, so the app's plan card and the
   *  keyboard's runs chip read the same numbers. */
  async status(req: FastifyRequest, deviceId: string, now = new Date()):
    Promise<{ remaining: number; plan: Plan; perDay: number; period: "day" | "week" }> {
    const { key, plan } = await this.who(req, deviceId);
    const caps = capsFor(plan, this.deps.freePerDay);
    const period = caps.window ?? "day";
    const remaining = await this.deps.limits.left(key, period, caps.runsPerDay, now);
    // perDay is the period's cap (old apps read it as a day's).
    return { remaining, plan, perDay: caps.runsPerDay, period };
  }
}

/** Who may call this server at all.
 *
 *  Protected by default: every path needs a Glyf session — the one POST
 *  /auth/session hands back after Apple or Google have vouched for someone —
 *  unless it is on the short list below. Adding a route later gets the lock
 *  without anyone remembering to ask for it.
 *
 *  The open paths are the ones that cannot have a session yet, or that exist
 *  for people who are not users: signing in, the website's waitlist, the
 *  OAuth callbacks a provider redirects to, the shared /p/ pages, and a
 *  health check. Those are held down by IP instead.
 */
import type { FastifyInstance, FastifyRequest } from "fastify";
import { verifySession } from "./identity.js";
import type { Limiter } from "./limits.js";

/** Paths anyone may reach, as exact matches or prefixes. */
export const OPEN_PATHS: readonly (string | RegExp)[] = [
  "/health",
  "/auth/config",
  "/auth/session",
  /^\/p\//,            // a page someone shared; the link is the permission
  /^\/oauth\//,        // providers redirect here; they carry their own state
  /^\/connector\/[^/]+\/callback/,
  "/waitlist",
  // Only says whether Google sign-in is set up on this server; onboarding
  // asks before anyone can have a session.
  /^\/connectors\/status/,
  "/favicon.ico",
];

export function isOpen(path: string): boolean {
  const clean = path.split("?")[0];
  return OPEN_PATHS.some(p => typeof p === "string" ? clean === p : p.test(clean));
}

export interface ProtectDeps {
  limits: Limiter;
  verify?: (token: string) => Promise<string | null>;
  /** Requests a single IP may make per minute, signed in or not. */
  perIpPerMinute?: number;
  /** Requests an unauthenticated IP may make per minute on the open paths. */
  openPerIpPerMinute?: number;
}

declare module "fastify" {
  interface FastifyRequest {
    /** The signed-in user this request belongs to, once past the gate. */
    glyfUser?: string;
  }
}

function ip(req: FastifyRequest): string {
  const forwarded = req.headers["x-forwarded-for"];
  const first = Array.isArray(forwarded) ? forwarded[0] : (forwarded ?? "").split(",")[0];
  return (first || req.ip || "unknown").trim();
}

/** The gate, in front of everything. */
export function protectRoutes(app: FastifyInstance, deps: ProtectDeps): void {
  const verify = deps.verify ?? (async (t: string) => verifySession(t));
  const perIp = deps.perIpPerMinute ?? 60;
  const openPerIp = deps.openPerIpPerMinute ?? 12;

  app.addHook("onRequest", async (req, reply) => {
    // One address can only ask so often, whoever it says it is. This runs
    // before any work, so a flood costs a counter and nothing else.
    const address = `ip:${ip(req)}`;
    if (await deps.limits.spend(address, "minute", perIp) < 0) {
      return reply.code(429).send({ ok: false, error: "Too many requests — slow down" });
    }

    if (isOpen(req.url)) {
      // Nobody is signed in here, so the address is the only thing holding
      // the door: a tighter count on top of the one above.
      if (await deps.limits.spend(`${address}|open`, "minute", openPerIp) < 0) {
        return reply.code(429).send({ ok: false, error: "Too many requests — slow down" });
      }
      return;
    }

    const header = req.headers.authorization ?? "";
    const token = header.startsWith("Bearer ") ? header.slice(7).trim() : "";
    const user = token ? await verify(token).catch(() => null) : null;
    if (!user) {
      return reply.code(401).send({ ok: false, error: "Sign in to use Glyf" });
    }
    req.glyfUser = user;
  });
}

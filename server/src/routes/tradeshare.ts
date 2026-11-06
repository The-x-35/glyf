import type { FastifyInstance, FastifyRequest } from "fastify";
import { z } from "zod";
import { env } from "../env.js";
import { chainOf } from "../lib/evm.js";
import type { KV } from "../lib/store.js";
import { createShare, getShare, renderSharePage } from "../lib/tradeshare.js";

/**
 * POST /trade-shares is the app's (signed in): a trade that went through,
 * turned into a link and the line for the chat. GET /t/:id is the link's
 * page, open to anyone the link was sent to (lib/tradeshare.ts).
 */

/** The trades a friend can copy. Sends and requests name a person, so
 *  they are never shared. */
const KINDS = ["swap", "limit", "stop", "stop-loss", "take-profit", "bracket", "trailing-stop", "twap", "bridge"] as const;

/** Keys that name a person or are the page's own: never stored. */
const DROPPED = new Set(["to", "address", "copied", "memo"]);

const Query = z.record(z.string().regex(/^[A-Za-z]{1,16}$/), z.string().min(1).max(64).regex(/^[\w.$%:-]+$/))
  .refine(q => Object.keys(q).length <= 16, "too many keys")
  .refine(q => (KINDS as readonly string[]).includes(q.kind ?? "") && !!q.sell && !!q.buy, "not a trade");

const CreateSchema = z.object({
  query: Query,
  summary: z.string().trim().min(1).max(140),
  chainId: z.number().int().positive().optional(),
  txHash: z.string().regex(/^0x[0-9a-fA-F]{64}$/).optional(),
  orderId: z.string().regex(/^[\w-]{1,80}$/).optional(),
});

/** Where the link points: this server's public address (PUBLIC_BASE_URL, else the host it was asked on). */
function base(req: FastifyRequest): string {
  const fixed = process.env.PUBLIC_BASE_URL?.replace(/\/+$/, "");
  if (fixed) return fixed;
  if (process.env.NODE_ENV === "production") return `https://${req.headers.host}`;
  return `http://127.0.0.1:${env.port}`;
}

/** The line that goes in the chat. */
export function shareText(summary: string, url: string): string {
  return `${summary.replace(/[.!\s]+$/, "")} with Glyf. Copy my trade: ${url}`;
}

export function tradeShareRoutes(app: FastifyInstance, kv: KV): void {
  app.post("/trade-shares", async (req, reply) => {
    const parsed = CreateSchema.safeParse(req.body);
    if (!parsed.success || !req.glyfUser) {
      req.log.warn({ issues: parsed.success ? [] : parsed.error.issues.map(i => ({ path: i.path, code: i.code })) },
        "trade_share_bad_request");
      return reply.code(400).send({ ok: false, error: "Bad request" });
    }
    const s = parsed.data;
    const query = Object.fromEntries(Object.entries(s.query).filter(([k]) => !DROPPED.has(k)));
    const chainId = s.chainId ?? chainOf(query.chain ?? "")?.id ?? (query.chain === "polygon" ? 137 : undefined);
    const id = createShare(kv, {
      user: req.glyfUser,
      query,
      summary: s.summary,
      ...(chainId ? { chainId } : {}),
      ...(s.txHash ? { txHash: s.txHash } : {}),
      ...(s.orderId ? { orderId: s.orderId } : {}),
    });
    req.log.info({ kind: query.kind, chainId }, "trade_share_created");
    const url = `${base(req)}/t/${id}`;
    return { ok: true, id, url, text: shareText(s.summary, url) };
  });

  // The link's page: anyone the link reached, no session.
  app.get("/t/:id", async (req, reply) => {
    const share = getShare(kv, (req.params as { id: string }).id);
    reply.header("content-security-policy",
      "default-src 'none'; style-src 'unsafe-inline'; img-src data:; base-uri 'none'; form-action 'none'; frame-ancestors 'none'");
    reply.header("x-content-type-options", "nosniff");
    reply.header("referrer-policy", "no-referrer");
    if (!share) {
      reply.header("cache-control", "no-store");
      return reply.code(404).type("text/html").send(renderSharePage(null));
    }
    reply.header("cache-control", "public, max-age=300");
    return reply.type("text/html").send(renderSharePage(share));
  });
}

import type { FastifyInstance, FastifyRequest } from "fastify";
import { z } from "zod";
import {
  CRYPTO_PRICES, CryptoPayments, PERIOD_DAYS, USDC_MAINNET, findPayment, httpRpc, isSolanaAddress,
  newReference, solanaPayUrl, usdcUnits, type Rpc,
} from "../lib/cryptopay.js";
import { verifySession } from "../lib/identity.js";
import { Users } from "../lib/users.js";

/**
 * Plus and Max paid in USDC (docs/CRYPTO-PAYMENTS.md). Off unless
 * GLYF_TREASURY (the public address that receives) and SOLANA_RPC_URL are
 * set. Only builds where the store allows it ever show it: the Solana dApp
 * Store build (GLYF_CRYPTO_PAY), never the App Store or Google Play ones.
 *
 * GET  /billing/crypto          whether it is on, and the prices
 * POST /billing/crypto/request  {plan, period} → a Solana Pay request
 * POST /billing/crypto/verify   {reference} → the plan, once paid
 *
 * A paid request becomes a purchase named "sol:<signature>", so it runs
 * out, stacks and is outranked like an App Store subscription or a gift
 * code (Users.refreshPlan).
 */

const RequestSchema = z.object({
  plan: z.enum(["plus", "max"]),
  period: z.enum(["month", "year"]),
});
const VerifySchema = z.object({ reference: z.string().min(32).max(44) });
const DAY = 24 * 3600 * 1000;

export interface CryptoPayDeps {
  users?: Users;
  payments?: CryptoPayments;
  verifySessionToken?: (token: string) => Promise<string | null>;
  /** GLYF_TREASURY unless a test passes one. */
  treasury?: string;
  /** USDC on mainnet unless GLYF_USDC_MINT says otherwise (devnet tests). */
  mint?: string;
  /** SOLANA_RPC_URL's node unless a test passes one. */
  rpc?: Rpc | null;
  now?: () => number;
}

export function cryptoPayRoutes(app: FastifyInstance, deps: CryptoPayDeps = {}): void {
  const users = deps.users ?? new Users();
  const payments = deps.payments ?? new CryptoPayments();
  const session = deps.verifySessionToken ?? (async (t: string) => verifySession(t));
  const now = deps.now ?? Date.now;
  const treasury = () => (deps.treasury ?? process.env.GLYF_TREASURY ?? "").trim();
  const mint = () => (deps.mint ?? process.env.GLYF_USDC_MINT ?? "").trim() || USDC_MAINNET;
  const rpc = (): Rpc | null => {
    if (deps.rpc !== undefined) return deps.rpc;
    const url = process.env.SOLANA_RPC_URL;
    return url ? httpRpc(url) : null;
  };
  const enabled = () => isSolanaAddress(treasury()) && isSolanaAddress(mint()) && rpc() !== null
    && users.enabled && payments.enabled;
  // One verify per request at a time on this instance, so a phone polling
  // twice at once doesn't ask Solana twice.
  const inFlight = new Map<string, Promise<unknown>>();

  async function who(req: FastifyRequest): Promise<string | null> {
    const header = req.headers.authorization ?? "";
    const token = header.startsWith("Bearer ") ? header.slice(7).trim() : "";
    return token ? await session(token).catch(() => null) : null;
  }

  app.get("/billing/crypto", async (req, reply) => {
    const id = await who(req);
    if (!id) return reply.code(401).send({ ok: false, error: "Sign in again" });
    if (!enabled()) return { ok: true, enabled: false };
    return { ok: true, enabled: true, token: "USDC", mint: mint(), prices: CRYPTO_PRICES };
  });

  app.post("/billing/crypto/request", async (req, reply) => {
    const id = await who(req);
    if (!id) return reply.code(401).send({ ok: false, error: "Sign in again" });
    const parsed = RequestSchema.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ ok: false, error: "Bad request" });
    if (!enabled()) return reply.code(503).send({ ok: false, error: "Paying in USDC isn't on right now" });
    const { plan, period } = parsed.data;
    const dollars = CRYPTO_PRICES[plan][period];
    const reference = newReference();
    try {
      await payments.create({
        reference, userId: id, plan, period, amount: usdcUnits(dollars), mint: mint(), treasury: treasury(),
      });
    } catch (err) {
      req.log.error({ err: err instanceof Error ? err.message : String(err) }, "crypto_request_failed");
      return reply.code(503).send({ ok: false, error: "Couldn't start the payment. Try again in a moment" });
    }
    const name = plan === "max" ? "Max" : "Plus";
    req.log.info({ plan, period }, "crypto_request");
    return {
      ok: true,
      reference,
      recipient: treasury(),
      mint: mint(),
      amount: String(dollars),
      decimals: 6,
      label: "Glyf",
      message: `Glyf ${name}, 1 ${period}`,
      url: solanaPayUrl({
        recipient: treasury(), amount: dollars, mint: mint(), reference,
        label: "Glyf", message: `Glyf ${name}, 1 ${period}`,
      }),
    };
  });

  app.post("/billing/crypto/verify", async (req, reply) => {
    const id = await who(req);
    if (!id) return reply.code(401).send({ ok: false, error: "Sign in again" });
    const parsed = VerifySchema.safeParse(req.body);
    if (!parsed.success || !isSolanaAddress(parsed.data.reference)) {
      return reply.code(400).send({ ok: false, error: "Bad request" });
    }
    const reference = parsed.data.reference;
    const node = rpc();
    if (!users.enabled || !payments.enabled || !node) {
      return reply.code(503).send({ ok: false, error: "Paying in USDC isn't on right now" });
    }
    const running = inFlight.get(reference);
    if (running) await running.catch(() => {});

    const work = (async () => {
      const row = await payments.get(reference);
      // Someone else's request reads as no request at all.
      if (!row || row.userId !== id) return { code: 404, body: { ok: false, error: "That payment wasn't found" } };

      let signature = row.signature;
      let expiresAt = row.expiresAt;
      if (!signature) {
        const found = await findPayment(node, {
          reference, treasury: row.treasury, mint: row.mint, amount: row.amount,
        });
        if (found.status === "pending") return { code: 202, body: { ok: false, pending: true } };
        if (found.status === "short") {
          req.log.warn({ plan: row.plan, period: row.period }, "crypto_short");
          return { code: 402, body: { ok: false, error: "That payment was less than the price. Write to us and we'll sort it out" } };
        }
        // On top of the same plan, the new days start where that plan ends.
        const current = await users.refreshPlan(id);
        const runsTo = current.plan === row.plan ? current.expiresAt?.getTime() ?? 0 : 0;
        const ends = new Date(Math.max(now(), runsTo) + PERIOD_DAYS[row.period] * DAY);
        const marked = await payments.markPaid(reference, found.signature, ends);
        if (marked === "taken") {
          return { code: 409, body: { ok: false, error: "That payment was already used" } };
        }
        // "already": another call got there first; its end is the one kept.
        const fresh = marked === "won" ? null : await payments.get(reference);
        signature = fresh?.signature ?? found.signature;
        expiresAt = fresh?.expiresAt ?? ends;
      }
      // Recorded even when a first try stopped after marking it paid: the
      // same purchase id and end, so doing it twice changes nothing.
      const purchaseId = `sol:${signature}`;
      const owner = await users.purchaseOwner(purchaseId);
      if (owner && owner !== id) return { code: 409, body: { ok: false, error: "That payment was already used" } };
      if (!owner) {
        await users.recordPurchase(id, {
          originalTransactionId: purchaseId,
          productId: `sol.${row.plan}.${row.period}`,
          plan: row.plan,
          expiresAt: expiresAt ?? new Date(now() + PERIOD_DAYS[row.period] * DAY),
          environment: row.mint === USDC_MAINNET ? "solana" : "solana-test",
        });
      }
      const { plan, expiresAt: until } = await users.refreshPlan(id);
      req.log.info({ plan, paid: row.plan, period: row.period }, "crypto_paid");
      return {
        code: 200,
        body: { ok: true, plan, paidPlan: row.plan, period: row.period, signature,
          expiresAt: until?.toISOString() ?? null },
      };
    })();
    inFlight.set(reference, work);
    try {
      const { code, body } = await work;
      return reply.code(code).send(body);
    } catch (err) {
      req.log.error({ err: err instanceof Error ? err.message : String(err) }, "crypto_verify_failed");
      return reply.code(503).send({ ok: false, error: "Couldn't check the payment right now. Try again in a moment" });
    } finally {
      if (inFlight.get(reference) === work) inFlight.delete(reference);
    }
  });
}


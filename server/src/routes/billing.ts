import type { FastifyInstance, FastifyRequest } from "fastify";
import { z } from "zod";
import {
  APPLE_PRODUCTS, AppleSignatureError, planOf, verifyAppleJws,
  type AppleTransaction, type VerifyOptions,
} from "../lib/appstore.js";
import { verifySession } from "../lib/identity.js";
import { Users } from "../lib/users.js";

/**
 * Plus and Max through the App Store.
 *
 * POST /billing/apple — the app sends Apple's signed transactions (a
 * purchase, a restore, or what the phone holds at launch). Each is checked
 * against Apple's signature (lib/appstore.ts), kept on this account, and the
 * account's plan becomes the best one still running.
 *
 * POST /billing/apple/notifications — Apple's own server tells us about
 * renewals, lapses and refunds (App Store Server Notifications v2), so a
 * plan keeps running, or stops, without the app being opened.
 */

const PurchaseSchema = z.object({
  transactions: z.array(z.string().min(20).max(20_000)).min(1).max(20),
});
const NotificationSchema = z.object({ signedPayload: z.string().min(20).max(50_000) });

export interface BillingDeps {
  users?: Users;
  verifySessionToken?: (token: string) => Promise<string | null>;
  /** Swapped in tests; Apple's signature check everywhere else. */
  verifySigned?: (jws: string) => unknown;
  /** The app ids that sell the plans (APPLE_BUNDLE_ID, a comma list). */
  bundleIds?: string[];
}

export function billingRoutes(app: FastifyInstance, deps: BillingDeps = {}): void {
  const users = deps.users ?? new Users();
  const session = deps.verifySessionToken ?? (async (t: string) => verifySession(t));
  // StoreKit testing in Xcode signs locally; only a development server takes it.
  const opts: VerifyOptions = { allowXcode: process.env.NODE_ENV !== "production" };
  const verifySigned = deps.verifySigned ?? ((jws: string) => verifyAppleJws(jws, opts));
  const check = (jws: string) => verifySigned(jws) as AppleTransaction;
  // Every id in the list sells, not only the first: the order is whatever
  // Railway was given, and the old app id may come first.
  const bundleIds = deps.bundleIds
    ?? (process.env.APPLE_BUNDLE_ID || "com.arpit.glyf").split(",").map(s => s.trim()).filter(Boolean);
  const ours = (tx: AppleTransaction) => bundleIds.includes(tx.bundleId) && Boolean(APPLE_PRODUCTS[tx.productId]);

  async function who(req: FastifyRequest): Promise<string | null> {
    const header = req.headers.authorization ?? "";
    const token = header.startsWith("Bearer ") ? header.slice(7).trim() : "";
    return token ? await session(token).catch(() => null) : null;
  }

  app.post("/billing/apple", async (req, reply) => {
    const id = await who(req);
    if (!id) return reply.code(401).send({ ok: false, error: "Sign in again" });
    const parsed = PurchaseSchema.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ ok: false, error: "Bad request" });
    if (!users.enabled) return reply.code(503).send({ ok: false, error: "Plans can't be saved right now" });

    let theirs = 0;
    let checked = 0;
    try {
      for (const jws of parsed.data.transactions) {
        let tx: AppleTransaction;
        try {
          tx = check(jws);
        } catch (err) {
          req.log.warn({ err: err instanceof AppleSignatureError ? err.message : String(err) }, "billing_unverified");
          continue;
        }
        if (!ours(tx)) continue;
        checked++;
        const granted = planOf(tx, tx.bundleId);
        const kept = await users.recordPurchase(id, {
          originalTransactionId: tx.originalTransactionId, productId: tx.productId,
          plan: APPLE_PRODUCTS[tx.productId],
          // Refunded or lapsed: kept, but running out now.
          expiresAt: granted?.expiresAt ?? new Date(Math.min(Date.now(), tx.expiresDate ?? Date.now())),
          environment: tx.environment ?? "",
        });
        if (!kept) theirs++;
      }
      const { plan, expiresAt } = await users.refreshPlan(id);
      req.log.info({ plan, checked, theirs }, "billing_apple");
      if (checked === 0) {
        return reply.code(400).send({ ok: false, plan, error: "That purchase couldn't be checked with Apple" });
      }
      if (theirs > 0 && plan === "free") {
        return reply.code(409).send({ ok: false, plan,
          error: "That subscription is on another Glyf account. Sign in with that account to use it" });
      }
      return { ok: true, plan, expiresAt: expiresAt?.toISOString() ?? null };
    } catch (err) {
      req.log.error({ err: err instanceof Error ? err.message : String(err) }, "billing_apple_failed");
      return reply.code(503).send({ ok: false, error: "Couldn't save your plan right now. Try Restore in a moment" });
    }
  });

  app.post("/billing/apple/notifications", async (req, reply) => {
    const parsed = NotificationSchema.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ ok: false });
    let signedTransaction: string | undefined;
    try {
      const note = verifySigned(parsed.data.signedPayload) as
        { notificationType?: string; data?: { signedTransactionInfo?: string } };
      signedTransaction = note.data?.signedTransactionInfo;
      req.log.info({ type: note.notificationType }, "billing_apple_notification");
    } catch (err) {
      req.log.warn({ err: String(err) }, "billing_notification_unverified");
      return reply.code(400).send({ ok: false });
    }
    // Test notifications and summaries carry no transaction: nothing to do.
    if (!signedTransaction || !users.enabled) return { ok: true };
    try {
      const tx = check(signedTransaction);
      if (!ours(tx)) return { ok: true };
      const owner = await users.purchaseOwner(tx.originalTransactionId);
      // A subscription nobody has sent from the app yet waits for the app.
      if (!owner) return { ok: true };
      const granted = planOf(tx, tx.bundleId);
      await users.recordPurchase(owner, {
        originalTransactionId: tx.originalTransactionId, productId: tx.productId,
        plan: APPLE_PRODUCTS[tx.productId],
        expiresAt: granted?.expiresAt ?? new Date(Math.min(Date.now(), tx.expiresDate ?? Date.now())),
        environment: tx.environment ?? "",
      });
      await users.refreshPlan(owner);
      return { ok: true };
    } catch (err) {
      req.log.error({ err: err instanceof Error ? err.message : String(err) }, "billing_notification_failed");
      // Apple retries a failed delivery; say so.
      return reply.code(503).send({ ok: false });
    }
  });
}

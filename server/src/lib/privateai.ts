import { AsyncLocalStorage } from "node:async_hooks";
import type { FastifyInstance } from "fastify";
import type { KV } from "./store.js";

/**
 * Private AI: a phone that sends `X-Glyf-AI: 0g` has its model calls answered
 * by 0G's Private Computer (TEE-run models, OpenAI-compatible) instead of the
 * usual chain. A phone that doesn't send it (every build on TestFlight today)
 * is untouched. The flag rides the request in AsyncLocalStorage, so the
 * ModelRouter reads it without every route passing it down.
 *
 * Each 0G answer leaves a receipt for its account (GET /ai/receipts): 0G's
 * request id, the model, the provider that ran it and whether the router
 * checked its TEE signature, so the app can show where its AI ran.
 */

export interface ZeroGReceipt {
  requestId: string;
  model: string;
  /** The on-chain provider address 0G routed to. */
  provider?: string;
  /** 0G's own TEE check of the answer: true, false, or null when it couldn't. */
  teeVerified?: boolean | null;
  /** What the call cost, in millionths of a dollar. */
  costUsdMicro?: number;
  at: number;
}

export interface AIContext {
  zeroG: boolean;
  /** The phone sent X-Glyf-AI at all ("0g" or "off"): only the hackathon
   *  build does, so only there may a glyf's own privateAI switch 0G on. */
  asked: boolean;
  /** 0G's request ids for the completions this request made, for the log. */
  requests: string[];
  user?: string;
  kv?: KV;
}

const als = new AsyncLocalStorage<AIContext>();

export function aiContext(): AIContext | undefined {
  return als.getStore();
}

export function wantsZeroG(header: string | string[] | undefined): boolean {
  const v = Array.isArray(header) ? header[0] : header;
  return (v ?? "").trim().toLowerCase() === "0g";
}

/** Runs `fn` as a request that asked for 0G (tests, scripts). */
export function withZeroG<T>(fn: () => T, extra: Partial<AIContext> = {}): T {
  return als.run({ zeroG: true, asked: true, requests: [], ...extra }, fn);
}

const COLLECTION = "zgreceipts";
const KEEP = 20;

export function receiptsFor(kv: KV, user: string): ZeroGReceipt[] {
  return kv.get<ZeroGReceipt[]>(COLLECTION, user) ?? [];
}

/** Called by the ModelRouter when a 0G answer finishes. The streamed routes
 *  (/act, /glyf/run) never reach the onSend flush, so this flushes itself. */
export function noteZeroG(receipt: ZeroGReceipt): void {
  const ctx = als.getStore();
  if (!ctx) return;
  ctx.requests.push(receipt.requestId);
  if (!ctx.kv || !ctx.user) return;
  ctx.kv.put(COLLECTION, ctx.user, [receipt, ...receiptsFor(ctx.kv, ctx.user)].slice(0, KEEP));
  void ctx.kv.flush?.();
}

export function privateAIHooks(app: FastifyInstance, kv: KV): void {
  // Callback style, so the handler and everything it awaits run inside run().
  // protectRoutes' hook runs first, so the account is already known here.
  app.addHook("onRequest", (req, _reply, done) => {
    const header = req.headers["x-glyf-ai"];
    als.run({ zeroG: wantsZeroG(header), asked: header !== undefined, requests: [], user: req.glyfUser, kv }, done);
  });
  app.addHook("onResponse", async (req) => {
    const ctx = als.getStore();
    if (ctx?.zeroG && ctx.requests.length > 0) {
      req.log.info({ path: req.routeOptions?.url, zgRequests: ctx.requests }, "zerog_answered");
    }
  });
}

/** The last answers 0G gave this account, newest first. */
export function privateAIRoutes(app: FastifyInstance, kv: KV): void {
  app.get("/ai/receipts", async (req, reply) => {
    if (!req.glyfUser) return reply.code(401).send({ ok: false, error: "Sign in to use Glyf" });
    reply.header("cache-control", "no-store");
    return { ok: true, receipts: receiptsFor(kv, req.glyfUser) };
  });
}

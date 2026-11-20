import { AsyncLocalStorage } from "node:async_hooks";
import { createHash, randomBytes } from "node:crypto";
import type { FastifyInstance } from "fastify";
import { recoverMessageAddress } from "viem";
import type { FetchFn } from "./evm.js";
import type { KV } from "./store.js";

/**
 * Private AI (docs/NEAR-SPEC.md): a phone that sends `X-Glyf-AI: near` has
 * its model calls answered by NEAR AI Cloud's private models (open models
 * run in TEEs: Intel TDX with NVIDIA confidential GPUs, OpenAI-compatible)
 * and by nothing else. A phone that doesn't send it is untouched. The flag
 * rides the request in AsyncLocalStorage, so the ModelRouter reads it
 * without every route passing it down. With no NEARAI_API_KEY the header is
 * ignored.
 *
 * Each answer leaves a receipt for its account (GET /ai/receipts): the chat
 * id, the model, and SHA-256 of the exact request and response bytes. The
 * receipt is checked when the app asks for it (a serverless function can't
 * be trusted to finish work after it has answered):
 *
 * 1. NEAR AI Cloud's signature for the chat (GET /v1/signature/{id},
 *    ECDSA): its text is `<model>:<request_hash>:<response_hash>` from the
 *    model's TEE (or `<request_hash>:<response_hash>` from the gateway's).
 * 2. The signer is recovered from the text (EIP-191) and must be the
 *    signing_address it claims.
 * 3. Both hashes must be the ones this server computed: the signature is
 *    over this very request and answer.
 * 4. The signing address must be in the model's attestation report (GET
 *    /v1/attestation/report), the key its TEE published.
 *
 * Only then is a receipt "verified". The TDX quote and NVIDIA evidence in
 * that report are what NEAR's Verification Center (cloud.near.ai/verify)
 * and nearai-cloud-verifier check; the receipt keeps what they need.
 */

export const NEARAI_API = "https://cloud-api.near.ai/v1";
export const VERIFY_URL = "https://cloud.near.ai/verify";

export type ReceiptStatus = "pending" | "verified" | "failed" | "unavailable";

export interface NearAIReceipt {
  chatId: string;
  model: string;
  /** SHA-256 (hex) of the request body this server sent and of the
   *  response bytes it read: what NEAR's signature must cover. */
  requestHash: string;
  responseHash: string;
  at: number;
  status: ReceiptStatus;
  /** What the signature check found, once it ran. */
  signature?: {
    kind: string | null;
    algo: string;
    signingAddress: string;
    signature: string;
    text: string;
    signerOk: boolean;
    hashesMatch: boolean;
    attested: boolean;
  };
  /** Why it isn't verified, in a few words. */
  reason?: string;
  tries?: number;
  checkedAt?: number;
}

export interface AIContext {
  near: boolean;
  /** NEAR AI chat ids this request made, for the log. */
  requests: string[];
  user?: string;
  kv?: KV;
}

const als = new AsyncLocalStorage<AIContext>();

export function aiContext(): AIContext | undefined {
  return als.getStore();
}

export function wantsNearAI(header: string | string[] | undefined): boolean {
  const v = Array.isArray(header) ? header[0] : header;
  return (v ?? "").trim().toLowerCase() === "near";
}

/** Runs `fn` as a request that asked for NEAR AI (tests, scripts). */
export function withNearAI<T>(fn: () => T, extra: Partial<AIContext> = {}): T {
  return als.run({ near: true, requests: [], ...extra }, fn);
}

export const sha256 = (data: string | Uint8Array) => createHash("sha256").update(data).digest("hex");

const COLLECTION = "nearaireceipts";
const KEEP = 20;

export function receiptsFor(kv: KV, user: string): NearAIReceipt[] {
  return kv.get<NearAIReceipt[]>(COLLECTION, user) ?? [];
}

/** Called by the ModelRouter when a NEAR AI answer finishes. The streamed
 *  routes (/act, /glyf/run) never reach the onSend flush, so this flushes
 *  itself. */
export function noteNearAI(receipt: Omit<NearAIReceipt, "status">): void {
  const ctx = als.getStore();
  if (!ctx) return;
  ctx.requests.push(receipt.chatId);
  if (!ctx.kv || !ctx.user) return;
  const row: NearAIReceipt = { ...receipt, status: "pending" };
  ctx.kv.put(COLLECTION, ctx.user, [row, ...receiptsFor(ctx.kv, ctx.user)].slice(0, KEEP));
  void ctx.kv.flush?.();
}

export function privateAIHooks(app: FastifyInstance, kv: KV): void {
  // Callback style, so the handler and everything it awaits run inside run().
  // protectRoutes' hook runs first, so the account is already known here.
  app.addHook("onRequest", (req, _reply, done) => {
    als.run({ near: wantsNearAI(req.headers["x-glyf-ai"]), requests: [], user: req.glyfUser, kv }, done);
  });
  app.addHook("onResponse", async (req) => {
    const ctx = als.getStore();
    if (ctx?.near && ctx.requests.length > 0) {
      req.log.info({ path: req.routeOptions?.url, nearAIChats: ctx.requests }, "nearai_answered");
    }
  });
}

export interface VerifyDeps {
  fetchImpl?: FetchFn;
  /** NEARAI_API_KEY unless a test passes one. */
  key?: () => string;
  now?: () => number;
}

/** A signature that isn't there yet is asked for again this many times. */
const MAX_TRIES = 3;
const REPORT_KEEP_MS = 10 * 60 * 1000;

/** Signing addresses a model's TEEs (and the gateway) attest to. */
interface Attested { at: number; model: Set<string>; gateway: string | null }

export class ReceiptVerifier {
  private readonly fetchImpl: FetchFn;
  private readonly key: () => string;
  private readonly now: () => number;
  private readonly reports = new Map<string, Attested>();

  constructor(deps: VerifyDeps = {}) {
    this.fetchImpl = deps.fetchImpl ?? fetch;
    this.key = deps.key ?? (() => (process.env.NEARAI_API_KEY ?? "").trim());
    this.now = deps.now ?? Date.now;
  }

  /** The model's attestation report, kept ten minutes. */
  async attested(model: string): Promise<Attested> {
    const hit = this.reports.get(model);
    if (hit && this.now() - hit.at < REPORT_KEEP_MS) return hit;
    const q = new URLSearchParams({ model, signing_algo: "ecdsa", include_tls_fingerprint: "false",
      nonce: randomBytes(32).toString("hex") });
    const res = await this.fetchImpl(`${NEARAI_API}/attestation/report?${q}`, {
      headers: { accept: "application/json", "x-no-aliasing": "true", ...(this.key() ? { authorization: `Bearer ${this.key()}` } : {}) },
      signal: AbortSignal.timeout(8_000),
    });
    if (!res.ok) throw new Error(`attestation ${res.status}`);
    const json = await res.json() as { model_attestations?: { signing_address?: string }[]; gateway_attestation?: { signing_address?: string } };
    const report: Attested = {
      at: this.now(),
      model: new Set((json.model_attestations ?? []).map(a => String(a.signing_address ?? "").toLowerCase()).filter(Boolean)),
      gateway: json.gateway_attestation?.signing_address?.toLowerCase() ?? null,
    };
    this.reports.set(model, report);
    return report;
  }

  /** Checks one receipt; returns it updated (a new object). */
  async verify(r: NearAIReceipt): Promise<NearAIReceipt> {
    const checkedAt = this.now();
    const tries = (r.tries ?? 0) + 1;
    const q = new URLSearchParams({ model: r.model, signing_algo: "ecdsa" });
    let res: Response;
    try {
      res = await this.fetchImpl(`${NEARAI_API}/signature/${encodeURIComponent(r.chatId)}?${q}`, {
        headers: { accept: "application/json", authorization: `Bearer ${this.key()}` },
        signal: AbortSignal.timeout(8_000),
      });
    } catch {
      return { ...r, tries, checkedAt, ...(tries >= MAX_TRIES ? { status: "unavailable", reason: "NEAR AI didn't answer" } : {}) };
    }
    const json = await res.json().catch(() => ({})) as Record<string, unknown>;
    // 404, or a 2xx carrying error_code: not signed (yet).
    if (!res.ok || typeof json.text !== "string" || typeof json.signature !== "string") {
      return { ...r, tries, checkedAt, ...(tries >= MAX_TRIES ? { status: "unavailable", reason: "No signature for this answer" } : {}) };
    }
    const text = json.text;
    const signature = json.signature;
    const algo = String(json.signing_algo ?? "ecdsa");
    const signingAddress = String(json.signing_address ?? "");
    const kind = typeof json.signature_kind === "string" ? json.signature_kind : null;
    if (algo !== "ecdsa") {
      return { ...r, tries, checkedAt, status: "failed", reason: `Unexpected signing algorithm ${algo.slice(0, 16)}` };
    }
    let signerOk = false;
    try {
      const signer = await recoverMessageAddress({ message: text, signature: signature as `0x${string}` });
      signerOk = signer.toLowerCase() === signingAddress.toLowerCase();
    } catch {
      signerOk = false;
    }
    // The two hashes are always the text's last two parts; the model id in
    // front of them (provider_tee) may itself hold a colon.
    const parts = text.split(":");
    const [requestHash, responseHash] = parts.slice(-2);
    const hashesMatch = parts.length >= 2 && requestHash === r.requestHash && responseHash === r.responseHash;
    let attested = false;
    try {
      const report = await this.attested(r.model);
      const who = signingAddress.toLowerCase();
      attested = kind === "gateway" ? report.gateway === who : report.model.has(who) || (kind === null && report.gateway === who);
    } catch {
      attested = false;
    }
    const verified = signerOk && hashesMatch && attested;
    return {
      ...r, tries, checkedAt,
      status: verified ? "verified" : "failed",
      signature: { kind, algo, signingAddress, signature, text, signerOk, hashesMatch, attested },
      ...(verified ? { reason: undefined } : { reason: !signerOk ? "The signature isn't the signer's"
        : !hashesMatch ? "The signature is for a different request or answer" : "The signer isn't in the model's attestation" }),
    };
  }
}

/** The last answers NEAR AI gave this account, newest first, each checked
 *  once the app asks (a few at a time, so the list stays quick). */
export function privateAIRoutes(app: FastifyInstance, kv: KV, deps: VerifyDeps = {}): void {
  const verifier = new ReceiptVerifier(deps);
  const keyOf = deps.key ?? (() => (process.env.NEARAI_API_KEY ?? "").trim());
  app.get("/ai/receipts", async (req, reply) => {
    if (!req.glyfUser) return reply.code(401).send({ ok: false, error: "Sign in to use Glyf" });
    const user = req.glyfUser;
    let receipts = receiptsFor(kv, user);
    const open = receipts.filter(r => r.status === "pending").slice(0, 5);
    if (open.length && keyOf()) {
      const checked = new Map((await Promise.all(open.map(r => verifier.verify(r)))).map(r => [r.chatId, r]));
      // Re-read: another request may have added a receipt meanwhile.
      receipts = receiptsFor(kv, user).map(r => checked.get(r.chatId) ?? r);
      kv.put(COLLECTION, user, receipts);
    }
    reply.header("cache-control", "no-store");
    // `id` and `verified` are what the app reads first (true, false, or
    // null while the check hasn't run).
    return { ok: true, provider: "NEAR AI Cloud", verifyUrl: VERIFY_URL, receipts: receipts.map(r => ({ id: r.chatId,
      verified: r.status === "verified" ? true : r.status === "pending" ? null : false, ...r })) };
  });
}

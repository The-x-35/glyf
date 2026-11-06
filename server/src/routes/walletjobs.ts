import { randomBytes } from "node:crypto";
import type { FastifyInstance, FastifyRequest } from "fastify";
import { getAddress, isAddress } from "viem";
import { z } from "zod";
import { env } from "../env.js";
import { chainOf, evmRpc, RpcError, type FetchFn } from "../lib/evm.js";
import type { KV } from "../lib/store.js";
import { createJob, getJob, saveJob, type JobResult, type WalletJob } from "../lib/walletjobs.js";
import { renderSignPage } from "../lib/walletpage.js";

/**
 * POST /wallet-jobs and GET /wallet-jobs/:id are the app's (signed in).
 * Everything under /w/ is the wallet's browser, which has no Glyf session:
 * the page, the job it shows, where it sends the answers back, and the
 * receipt it waits on. The job's id is the only key (see lib/walletjobs.ts).
 */

const Hex = z.string().regex(/^0x[0-9a-fA-F]*$/).max(200_000);
const Address = z.string().refine(a => isAddress(a, { strict: false }), "address");

const StepSchema = z.discriminatedUnion("type", [
  z.object({
    type: z.literal("tx"),
    chainId: z.number().int().positive(),
    to: Address,
    data: Hex.optional(),
    value: z.string().regex(/^\d{1,40}$/).optional(),
    gas: z.string().regex(/^\d{1,12}$/).optional(),
    label: z.string().min(1).max(80),
  }),
  z.object({
    type: z.literal("typed"),
    chainId: z.number().int().positive(),
    data: z.record(z.string(), z.unknown()),
    label: z.string().min(1).max(80),
  }),
  // A plain personal_sign, like Flash's cancel message.
  z.object({
    type: z.literal("message"),
    message: z.string().min(1).max(1000),
    label: z.string().min(1).max(80),
  }),
]);

const CreateSchema = z.object({
  kind: z.enum(["connect", "run"]),
  wallet: z.enum(["metamask", "phantom"]),
  title: z.string().min(1).max(80),
  from: Address.optional(),
  steps: z.array(StepSchema).max(8).default([]),
}).refine(j => j.kind === "connect" || (j.steps.length > 0 && j.from), "a run needs steps and from");

const ResultSchema = z.object({
  status: z.enum(["open", "done", "failed", "cancelled"]),
  results: z.array(z.object({
    hash: z.string().regex(/^0x[0-9a-fA-F]{64}$/).optional(),
    signature: z.string().regex(/^0x[0-9a-fA-F]{130,1000}$/).optional(),
  })).max(8),
  address: Address.optional(),
  error: z.string().max(300).optional(),
});

/** Where the wallet opens the page: this server's public address. */
function base(req: FastifyRequest): string {
  const fixed = process.env.PUBLIC_BASE_URL?.replace(/\/+$/, "");
  if (fixed) return fixed;
  if (process.env.NODE_ENV === "production") return `https://${req.headers.host}`;
  return `http://127.0.0.1:${env.port}`;
}

const WALLET_NAMES: Record<string, string> = { metamask: "MetaMask", phantom: "Phantom" };

export interface WalletJobDeps {
  fetchImpl?: FetchFn;
}

export function walletJobRoutes(app: FastifyInstance, kv: KV, deps: WalletJobDeps = {}): void {
  const fetchImpl = deps.fetchImpl ?? fetch;

  app.post("/wallet-jobs", async (req, reply) => {
    const parsed = CreateSchema.safeParse(req.body);
    if (!parsed.success || !req.glyfUser) {
      req.log.warn({ issues: parsed.success ? [] : parsed.error.issues.map(i => ({ path: i.path, code: i.code })) },
        "wallet_job_bad_request");
      return reply.code(400).send({ ok: false, error: "Bad request" });
    }
    const j = parsed.data;
    if (j.steps.some(s => s.type !== "message" && !chainOf(s.chainId))) return reply.code(400).send({ ok: false, error: "Unknown chain" });
    const id = createJob(kv, {
      user: req.glyfUser,
      kind: j.kind,
      wallet: j.wallet,
      title: j.title,
      ...(j.from ? { from: getAddress(j.from) } : {}),
      steps: j.steps,
    });
    // The id is the job's only key, so it stays out of production logs.
    req.log.info({ kind: j.kind, wallet: j.wallet, steps: j.steps.length,
      ...(process.env.NODE_ENV === "production" ? {} : { id }) }, "wallet_job_created");
    return { ok: true, id, url: `${base(req)}/w/${id}` };
  });

  app.get("/wallet-jobs/:id", async (req, reply) => {
    const job = getJob(kv, (req.params as { id: string }).id);
    if (!job || job.user !== req.glyfUser) return reply.code(404).send({ ok: false, error: "Not found" });
    reply.header("cache-control", "no-store");
    return { ok: true, status: job.status, results: job.results,
      ...(job.address ? { address: job.address } : {}), ...(job.error ? { error: job.error } : {}) };
  });

  // The wallet's side.

  app.get("/w/:id", async (req, reply) => {
    const id = (req.params as { id: string }).id;
    const job = getJob(kv, id);
    const nonce = randomBytes(12).toString("base64");
    reply.header("cache-control", "no-store");
    reply.header("content-security-policy",
      `default-src 'none'; script-src 'nonce-${nonce}'; style-src 'unsafe-inline'; connect-src 'self'; img-src data:; base-uri 'none'; form-action 'none'; frame-ancestors 'none'`);
    reply.header("x-content-type-options", "nosniff");
    reply.header("referrer-policy", "no-referrer");
    if (!job) return reply.code(404).type("text/html").send(renderSignPage(null, nonce));
    return reply.type("text/html").send(renderSignPage({ wallet: WALLET_NAMES[job.wallet] ?? "your wallet" }, nonce));
  });

  app.get("/w/:id/job", async (req, reply) => {
    const job = getJob(kv, (req.params as { id: string }).id);
    if (!job) return reply.code(404).send({ ok: false, error: "This link has run out. Start again in Glyf" });
    reply.header("cache-control", "no-store");
    const chains: Record<string, { name: string; native: string; rpc: string; explorer?: string }> = {};
    for (const s of job.steps) {
      if (s.type === "message") continue;
      const c = chainOf(s.chainId);
      if (c) {
        chains[c.id] = { name: c.name, native: c.native, rpc: c.rpc,
          ...(c.id === 1874 ? { explorer: "https://explorer.testnet.whitechain.io" } : {}) };
      }
    }
    return { ok: true, kind: job.kind, wallet: job.wallet, walletName: WALLET_NAMES[job.wallet], title: job.title,
      from: job.from ?? null, steps: job.steps, chains, status: job.status, results: job.results };
  });

  app.post("/w/:id/result", async (req, reply) => {
    const id = (req.params as { id: string }).id;
    const job = getJob(kv, id);
    if (!job) return reply.code(404).send({ ok: false, error: "This link has run out. Start again in Glyf" });
    if (job.status !== "open") return reply.code(409).send({ ok: false, error: "Already finished" });
    const parsed = ResultSchema.safeParse(req.body);
    if (!parsed.success || parsed.data.results.length > job.steps.length) {
      return reply.code(400).send({ ok: false, error: "Bad request" });
    }
    const r = parsed.data;
    const next: WalletJob = {
      ...job,
      status: r.status,
      results: r.results.map(x => ({ ...(x.hash ? { hash: x.hash } : {}), ...(x.signature ? { signature: x.signature } : {}) }) as JobResult),
      ...(r.address ? { address: getAddress(r.address) } : {}),
      ...(r.error ? { error: r.error } : {}),
      updatedAt: Date.now(),
    };
    saveJob(kv, id, next);
    req.log.info({ kind: job.kind, status: r.status, results: r.results.length }, "wallet_job_result");
    return { ok: true };
  });

  /** ?chainId=8453&hash=0x… — what the page waits on between transactions.
   *  Only the job's own chains, and only this one read. */
  app.get("/w/:id/receipt", async (req, reply) => {
    const job = getJob(kv, (req.params as { id: string }).id);
    const q = req.query as { chainId?: string; hash?: string };
    const chain = chainOf(q.chainId ?? "");
    const ours = job?.steps.some(s => s.type !== "message" && s.chainId === chain?.id);
    if (!job || !chain || !ours || !/^0x[0-9a-fA-F]{64}$/.test(q.hash ?? "")) {
      return reply.code(400).send({ ok: false, error: "Bad request" });
    }
    try {
      const receipt = await evmRpc(fetchImpl, chain, "eth_getTransactionReceipt", [q.hash]) as { status?: string } | null;
      reply.header("cache-control", "no-store");
      return { ok: true, status: receipt ? (receipt.status === "0x1" ? "success" : "reverted") : "pending" };
    } catch (err) {
      return reply.code(err instanceof RpcError ? 400 : 502).send({ ok: false, error: `${chain.name} didn't answer` });
    }
  });
}

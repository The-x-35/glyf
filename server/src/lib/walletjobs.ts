import { randomBytes } from "node:crypto";
import type { KV } from "./store.js";

/**
 * Signing with a wallet Glyf doesn't hold (MetaMask, Phantom).
 *
 * The app writes down what needs signing as a job, opens the job's page in
 * the wallet's own browser, and the page asks the wallet (window.ethereum)
 * for each signature in turn. What the wallet answers comes back here under
 * the job's id, and the app reads it when the person returns.
 *
 * Nothing here is trusted: the id is the only key to a job, and the app
 * checks every answer itself (the signer recovered from each signature, the
 * sender of each transaction from its receipt) before it acts on it. A job
 * holds only unsigned transactions and the person's own address.
 */

export type JobStep =
  | { type: "tx"; chainId: number; to: string; data?: string; value?: string; gas?: string; label: string }
  | { type: "typed"; chainId: number; data: Record<string, unknown>; label: string }
  | { type: "message"; message: string; label: string };

export type JobResult = { hash?: string; signature?: string };

export interface WalletJob {
  user: string;
  kind: "connect" | "run";
  wallet: string;
  title: string;
  from?: string;
  steps: JobStep[];
  createdAt: number;
  status: "open" | "done" | "failed" | "cancelled";
  /** One per finished step, in order; a run that stops part way keeps what it did. */
  results: JobResult[];
  /** The connected address (connect jobs). */
  address?: string;
  error?: string;
  updatedAt?: number;
}

const COLLECTION = "walletjobs";

/** Long enough to open the wallet, read and confirm a few prompts. */
export const JOB_TTL_MS = 30 * 60 * 1000;

export function connectMessage(id: string): string {
  return `Glyf: use this wallet to sign\nCode: ${id}`;
}

export function createJob(kv: KV, job: Omit<WalletJob, "createdAt" | "status" | "results">, now = Date.now()): string {
  const id = randomBytes(16).toString("base64url"); // 22 chars, not enumerable
  const steps = job.kind === "connect"
    ? [{ type: "message" as const, message: connectMessage(id), label: "Prove it’s your wallet" }]
    : job.steps;
  kv.put<WalletJob>(COLLECTION, id, { ...job, steps, createdAt: now, status: "open", results: [] });
  sweep(kv, now);
  return id;
}

export function getJob(kv: KV, id: string, now = Date.now()): WalletJob | undefined {
  if (!/^[\w-]{20,24}$/.test(id)) return undefined;
  const job = kv.get<WalletJob>(COLLECTION, id);
  if (!job || now - job.createdAt > JOB_TTL_MS) return undefined;
  return job;
}

export function saveJob(kv: KV, id: string, job: WalletJob): void {
  kv.put<WalletJob>(COLLECTION, id, job);
}

/** Old jobs go when a new one is made, so the collection stays small. */
function sweep(kv: KV, now: number): void {
  for (const { id, value } of kv.list<WalletJob>(COLLECTION)) {
    if (now - value.createdAt > JOB_TTL_MS * 2) kv.del(COLLECTION, id);
  }
}

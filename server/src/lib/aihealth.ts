import { env } from "../env.js";
import { completeStreaming, ModelExhaustedError, readyModels, type Attempt } from "../providers/openrouter.js";

/**
 * Whether AI actually answers here, not just whether a key is set: one tiny
 * completion through the fast chain, the one holding space uses (GET
 * /health?deep=1). Production AI was down for days once while /health,
 * which only checks that keys are present, looked fine.
 *
 * The answer is kept for a minute, and callers in that minute share it (and
 * share a check still running), so hitting the URL in a loop costs at most
 * one call a minute per server instance.
 */

export interface AiHealth {
  ok: boolean;
  /** Mock mode: nothing was called. */
  mock: boolean;
  tier: "fast";
  /** The model that answered. */
  model?: string;
  /** From sending the probe to the whole answer. */
  latencyMs: number;
  /** Models tried before it, or all of them when none answered. */
  failures: Attempt[];
  /** Chain models skipped because a recent refusal or rate limit put them
   *  on a cool-down. */
  coolingDown: string[];
  chain: string[];
  checkedAt: string;
  /** True when this is the minute-old answer, not a fresh call. */
  cached: boolean;
}

export const AI_HEALTH_TTL_MS = 60_000;

let last: { at: number; value: AiHealth } | null = null;
let running: Promise<AiHealth> | null = null;

export function resetAiHealthForTests(): void {
  last = null;
  running = null;
}

async function probe(now: () => number): Promise<AiHealth> {
  const chain = [...env.fastModels];
  const ready = readyModels(chain);
  const coolingDown = chain.filter(m => !ready.includes(m));
  const started = now();
  const base = { mock: env.mockAI, tier: "fast" as const, chain, coolingDown, cached: false };
  try {
    const res = await completeStreaming("fast",
      [{ role: "user", content: "Reply with the single word OK." }],
      { onToken: () => {}, maxTokens: 5, temperature: 0 });
    return {
      ...base, ok: res.text.trim().length > 0, model: res.model, latencyMs: now() - started,
      failures: res.attempts, checkedAt: new Date(started).toISOString(),
    };
  } catch (err) {
    const failures = err instanceof ModelExhaustedError
      ? err.attempts
      : [{ model: "chain", status: err instanceof Error ? err.name : "error" }];
    return { ...base, ok: false, latencyMs: now() - started, failures, checkedAt: new Date(started).toISOString() };
  }
}

export async function aiHealth(now: () => number = Date.now): Promise<AiHealth> {
  if (last && now() - last.at < AI_HEALTH_TTL_MS) return { ...last.value, cached: true };
  if (!running) {
    running = probe(now).then(value => {
      last = { at: now(), value };
      return value;
    }).finally(() => { running = null; });
  }
  return running;
}

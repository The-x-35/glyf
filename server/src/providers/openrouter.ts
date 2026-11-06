import { env } from "../env.js";
import { aiContext, noteZeroG } from "../lib/privateai.js";
import { KEEP_PLACEHOLDERS, SecretVault } from "../lib/secrets.js";

/** §8: OpenRouter, backend only, OpenAI-compatible, streamed — plus any
 *  OpenAI-compatible provider named by a prefix in the model chain. */

export interface Endpoint {
  url: string;
  key: string;
  model: string;
  openrouter: boolean;
}

/** OpenAI-compatible providers a model chain can name by prefix. */
const PROVIDERS: Record<string, { url: string; key: () => string }> = {
  groq: { url: "https://api.groq.com/openai/v1/chat/completions", key: () => env.groqKey },
  gemini: { url: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions", key: () => env.geminiKey },
  mistral: { url: "https://api.mistral.ai/v1/chat/completions", key: () => env.mistralKey },
  inception: { url: "https://api.inceptionlabs.ai/v1/chat/completions", key: () => env.inceptionKey },
  cerebras: { url: "https://api.cerebras.ai/v1/chat/completions", key: () => env.cerebrasKey },
  // 0G Private Computer: models run in TEEs, and the router keeps billing
  // metadata only (lib/privateai.ts says who is sent here).
  zerog: { url: "https://router-api.0g.ai/v1/chat/completions", key: () => env.zeroGKey },
};

/** "groq:<model>", "gemini:<model>", … go to that provider; everything else
 *  is an OpenRouter id (which may itself contain ":free"). A provider without
 *  a key is skipped, so the chain falls through to the next model. */
export function endpointFor(spec: string): Endpoint | null {
  const colon = spec.indexOf(":");
  const prefix = colon > 0 ? spec.slice(0, colon) : "";
  const rest = colon > 0 ? spec.slice(colon + 1) : "";
  const provider = PROVIDERS[prefix];
  if (provider && rest) {
    const key = provider.key();
    return key ? { url: provider.url, key, model: rest, openrouter: false } : null;
  }
  const model = prefix === "openrouter" && rest ? rest : spec;
  return env.openrouterKey ? { url: "https://openrouter.ai/api/v1/chat/completions",
    key: env.openrouterKey, model, openrouter: true } : null;
}

const isZeroG = (ep: Endpoint) => ep.url.startsWith("https://router-api.0g.ai/");

/** "fast" answers someone holding space, "smart" builds and rewrites at
 *  length, and "suggest" reads a pause in typing for the strip's chip: a
 *  read nobody asked for, so it has its own small, cheap chain. */
export type Tier = "fast" | "smart" | "suggest" | "answer";

function chainFor(tier: Tier): string[] {
  // A phone that asked for private AI gets 0G and nothing else: falling
  // through to another provider would send its typing somewhere it said no
  // to. Without a 0G key the ask is ignored, so nothing breaks before one is set.
  if (aiContext()?.zeroG && env.zeroGKey) return tier === "smart" ? env.zeroGSmartModels : env.zeroGModels;
  return tier === "smart" ? env.smartModels : tier === "suggest" ? env.suggestModels
    : tier === "answer" ? env.answerModels : env.fastModels;
}

/** Per-model request settings. Reasoning models think before the first
 *  token unless told not to — seconds a keyboard can't spend — and some put
 *  that thinking into the answer text. */
export function requestOptions(ep: Endpoint, tier: Tier): Record<string, unknown> {
  const opts: Record<string, unknown> = { max_tokens: tier === "suggest" ? 200 : tier === "fast" ? 1500 : 4000 };
  const quick = tier !== "smart";
  const id = ep.model.toLowerCase();
  if (tier === "suggest") {
    // A few words of JSON, the same every time.
    opts.temperature = 0;
  }
  // Every tier, only to providers that neither keep nor train on what they
  // are sent: it is someone's typing (the privacy policy says so, and
  // Google's OAuth review asked, 2026-10-01).
  if (ep.openrouter) opts.provider = { data_collection: "deny" };
  if (isZeroG(ep)) {
    // The router checks the answer's TEE signature and says so in
    // x_0g_trace; its models think first unless told not to.
    opts.verify_tee = true;
    opts.chat_template_kwargs = { enable_thinking: false };
    return opts;
  }
  if (ep.openrouter) {
    // Hybrid models (Qwen 3.7 Flash, DeepSeek V4 Flash, Ling) think first
    // unless told not to: measured, a rewrite took 16 s and ten times the
    // tokens. Every tier turns thinking off, the Builder too (it makes valid
    // glyfs without it, in about 2 s). OpenRouter's own routers
    // (openrouter/free) can land on a model that must think, so there it is
    // only kept out of the answer.
    opts.reasoning = id.includes("gpt-oss")
      ? { effort: quick ? "low" : "medium", exclude: true }
      : !id.startsWith("openrouter/") ? { enabled: false } : { exclude: true };
    return opts;
  }
  if (id.includes("gpt-oss")) {
    opts.reasoning_effort = quick ? "low" : "medium";
  } else if (ep.url.includes("groq.com") && id.includes("qwen")) {
    // Groq returns Qwen's thinking as raw <think> text otherwise.
    opts.reasoning_effort = "none";
  } else if (ep.url.includes("googleapis.com") && /gemini-[\d.]+-(flash|pro)(?!-lite)/.test(id)) {
    // Gemini's full flash/pro models think first; the lite ones don't take the
    // option at all (400 Invalid argument), so never send it to them.
    opts.reasoning_effort = quick ? "none" : "low";
  }
  return opts;
}

/** A model that just hit its rate limit is skipped until it recovers, so an
 *  exhausted free quota doesn't cost every request a failed round trip. */
const coolingUntil = new Map<string, number>();

export function noteRateLimited(model: string, retryAfter: string | null, now = Date.now()): void {
  const seconds = Number(retryAfter);
  const wait = Number.isFinite(seconds) && seconds > 0 ? Math.min(seconds, 600) : 60;
  coolingUntil.set(model, now + wait * 1000);
}

/** Models ready now, in chain order; if every one is cooling, try them all. */
export function readyModels(models: string[], now = Date.now()): string[] {
  const ready = models.filter(m => (coolingUntil.get(m) ?? 0) <= now);
  return ready.length > 0 ? ready : models;
}

export function resetCooldowns(): void {
  coolingUntil.clear();
}

/** How long a model gets to start answering before the next one is tried.
 *  A suggestion that comes late comes after the message has gone. */
export const FIRST_BYTE_MS: Record<Tier, number> = { fast: 4000, smart: 20000, suggest: 2500, answer: 4000 };

/** 0G's models start slower than OpenRouter's (a TEE, fewer replicas). */
export const ZEROG_FIRST_BYTE_MS = 8000;

/** The last model in a chain gets this long to start (and between chunks). */
export const LAST_FIRST_BYTE_MS = 15000;

export interface StreamHandlers {
  onToken: (t: string) => void;
  signal?: AbortSignal;
  /** For callers that wait for the whole reply (nothing is streamed to a
   *  person): a model that goes quiet this long mid-answer is dropped for
   *  the next one instead of holding the reply hostage. */
  stallMs?: number;
  /** A model that had started answering was dropped for the next one: what
   *  it streamed so far is void, and the next model starts over. */
  onRestart?: () => void;
  /** A fact asked for is answered the same way every time: 0 kept "France
   *  won the 2022 World Cup" from coming back one run in several. */
  temperature?: number;
  /** Caps the reply below the tier's own max_tokens (the health check's
   *  one-word probe). */
  maxTokens?: number;
}

/** One model in the chain that did not answer, and why: an HTTP status, or
 *  "no-key", "slow", "empty", "classifier", an error name. */
export type Attempt = { model: string; status: number | string };

export class ModelExhaustedError extends Error {
  constructor(public attempts: Attempt[]) {
    super(`all models failed: ${attempts.map(a => `${a.model}(${a.status})`).join(", ")}`);
  }
}

/**
 * §8.3 ModelRouter: walk the fallback chain; a model that answers wins.
 * Returns the full text; tokens stream through `onToken` as they arrive.
 *
 * Every model call goes through here, so this is where card numbers, codes,
 * passwords and keys are swapped for placeholders (lib/secrets.ts) and put
 * back into the reply: no model ever reads one.
 */
export async function completeStreaming(
  tier: Tier,
  messages: { role: string; content: string }[],
  handlers: StreamHandlers,
): Promise<{ text: string; model: string; attempts: Attempt[] }> {
  const vault = new SecretVault();
  const safe = messages.map(m => ({ role: m.role, content: vault.mask(m.content) }));
  if (vault.count > 0) {
    const last = safe.length - 1;
    safe[last] = { ...safe[last], content: safe[last].content + KEEP_PLACEHOLDERS };
  }
  const stream = vault.restoringStream(handlers.onToken);
  const res = await completeMasked(tier, safe, { ...handlers, onToken: stream.push,
    onRestart: () => { stream.reset(); handlers.onRestart?.(); } });
  stream.flush();
  return { text: vault.restore(res.text), model: res.model, attempts: res.attempts ?? [] };
}

/** What a model is actually sent: messages with nothing private left in them. */
export let lastOutboundForTests: { role: string; content: string }[] = [];

async function completeMasked(
  tier: Tier,
  messages: { role: string; content: string }[],
  handlers: StreamHandlers,
): Promise<{ text: string; model: string; attempts?: Attempt[] }> {
  if (process.env.VITEST) lastOutboundForTests = messages;
  if (env.mockAI) {
    return mockStream(messages, handlers);
  }
  const models = readyModels(chainFor(tier));
  const attempts: Attempt[] = [];

  // Whether the model being tried has put anything in front of the person:
  // if it then fails, they are told to discard it before the next one starts.
  let spoke = false;
  const forward = (t: string) => {
    spoke = true;
    handlers.onToken(t);
  };
  const dropped = () => {
    if (spoke) handlers.onRestart?.();
    spoke = false;
  };
  for (const [index, model] of models.entries()) {
    // The last model has nobody to hand over to: it gets time to answer
    // rather than a quick give-up (Gemini straight from Google can take
    // 10 s or more to start when busy).
    const last = index === models.length - 1;
    const ep = endpointFor(model);
    if (!ep) {
      attempts.push({ model, status: "no-key" });
      continue;
    }
    // A model that has not started answering in a few seconds is stuck (a
    // queue, a silent rate limit): someone is holding the space bar, so move
    // on to the next one rather than wait it out.
    const attempt = new AbortController();
    let stallTimer: ReturnType<typeof setTimeout> | undefined;
    const firstByte = isZeroG(ep) ? Math.max(FIRST_BYTE_MS[tier], ZEROG_FIRST_BYTE_MS) : FIRST_BYTE_MS[tier];
    const stuck = setTimeout(() => attempt.abort(), last ? Math.max(firstByte, LAST_FIRST_BYTE_MS) : firstByte);
    const onAbort = () => attempt.abort();
    handlers.signal?.addEventListener("abort", onAbort);
    try {
      const res = await fetch(ep.url, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${ep.key}`,
          "Content-Type": "application/json",
          ...(ep.openrouter ? { "HTTP-Referer": "https://tryglyf.com", "X-Title": "Glyf" } : {}),
          // Only providers that run the model in a TEE.
          ...(isZeroG(ep) ? { "X-0G-Provider-Trust-Mode": "private" } : {}),
        },
        body: JSON.stringify({ model: ep.model, messages, stream: true, ...requestOptions(ep, tier),
          ...(handlers.temperature !== undefined ? { temperature: handlers.temperature } : {}),
          ...(handlers.maxTokens !== undefined ? { max_tokens: handlers.maxTokens } : {}) }),
        signal: attempt.signal,
      });
      clearTimeout(stuck);
      if (handlers.stallMs) {
        // Re-armed on every chunk below; fires only if the stream goes quiet.
        stallTimer = setTimeout(() => attempt.abort(), last ? Math.max(handlers.stallMs, LAST_FIRST_BYTE_MS) : handlers.stallMs);
      }
      if (!res.ok || !res.body) {
        if (res.status === 429) noteRateLimited(model, res.headers.get("retry-after"));
        // A key the provider refuses won't work on the next request either:
        // skip that model for ten minutes rather than pay a round trip each time.
        if (res.status === 401 || res.status === 402 || res.status === 403) noteRateLimited(model, "600");
        attempts.push({ model, status: res.status });
        continue;
      }
      const gate = new VerdictGate(forward);
      const trace: ZeroGTrace = {};
      const text = await drainSSE(res.body, { ...handlers, onToken: t => gate.push(t) }, () => {
        if (!handlers.stallMs) return;
        clearTimeout(stallTimer);
        stallTimer = setTimeout(() => attempt.abort(), last ? Math.max(handlers.stallMs, LAST_FIRST_BYTE_MS) : handlers.stallMs);
      }, isZeroG(ep) ? m => Object.assign(trace, m) : undefined);
      if (text.trim().length === 0) {
        attempts.push({ model, status: "empty" });
        dropped();
        continue;
      }
      if (gate.finish(text)) {
        // A router picked a moderation model: its verdict is not an answer,
        // and none of it reached the client — try the next model.
        attempts.push({ model, status: "classifier" });
        dropped();
        continue;
      }
      if (isZeroG(ep)) {
        noteZeroG({ requestId: trace.requestId ?? trace.id ?? res.headers.get("zg-res-key") ?? "unknown",
          model: ep.model, provider: trace.provider, teeVerified: trace.teeVerified ?? null, costUsdMicro: trace.costUsdMicro, at: Date.now() });
      }
      return { text, model, attempts };
    } catch (err) {
      if (handlers.signal?.aborted) throw err;
      attempts.push({ model, status: attempt.signal.aborted ? "slow" : (err as Error).name || "error" });
      dropped();
    } finally {
      clearTimeout(stuck);
      clearTimeout(stallTimer);
      handlers.signal?.removeEventListener("abort", onAbort);
    }
  }
  throw new ModelExhaustedError(attempts);
}

/** Free routers ("openrouter/free") can land on content-safety classifiers,
 *  which answer any prompt with a verdict like "User Safety: safe". */
export function isClassifierVerdict(text: string): boolean {
  return /^\s*(user|agent|response|prompt)\s+safety\s*:/i.test(text)
    || /^\s*(safe|unsafe)\s*$/i.test(text);
}

/** Holds back the first few tokens until it is clear the model is answering
 *  rather than classifying, so a verdict never streams to the keyboard. */
export class VerdictGate {
  private buffer = "";
  private decided = false;
  private verdict = false;
  private static readonly WINDOW = 24;

  constructor(private readonly forward: (t: string) => void) {}

  push(token: string): void {
    if (this.decided) {
      if (!this.verdict) this.forward(token);
      return;
    }
    this.buffer += token;
    if (this.buffer.trimStart().length >= VerdictGate.WINDOW) this.decide(this.buffer);
  }

  /** Call when the stream ends; returns true when the reply was a verdict. */
  finish(full: string): boolean {
    if (!this.decided) this.decide(full);
    return this.verdict;
  }

  private decide(text: string): void {
    this.decided = true;
    this.verdict = isClassifierVerdict(text);
    if (!this.verdict && this.buffer) this.forward(this.buffer);
    this.buffer = "";
  }
}

/** 0G's x_0g_trace, as far as a stream has told it. */
interface ZeroGTrace {
  id?: string;
  requestId?: string;
  provider?: string;
  teeVerified?: boolean | null;
  costUsdMicro?: number;
}

async function drainSSE(
  body: ReadableStream<Uint8Array>,
  handlers: StreamHandlers,
  onChunk: () => void = () => {},
  /** What 0G says about the call, as its chunks carry it. */
  onTrace?: (t: ZeroGTrace) => void,
): Promise<string> {
  const reader = body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  let text = "";
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    onChunk();
    buffer += decoder.decode(value, { stream: true });
    let idx: number;
    while ((idx = buffer.indexOf("\n")) >= 0) {
      const line = buffer.slice(0, idx).trim();
      buffer = buffer.slice(idx + 1);
      if (!line.startsWith("data:")) continue;
      const payload = line.slice(5).trim();
      if (payload === "[DONE]") return text;
      try {
        const obj = JSON.parse(payload);
        if (onTrace) {
          const t = obj.x_0g_trace;
          if (typeof obj.id === "string") onTrace({ id: obj.id });
          if (t && typeof t === "object") {
            onTrace({
              ...(typeof t.request_id === "string" ? { requestId: t.request_id } : {}),
              ...(typeof t.provider === "string" ? { provider: t.provider } : {}),
              ...("tee_verified" in t ? { teeVerified: t.tee_verified ?? null } : {}),
              ...(t.billing?.total_cost_usd_micro !== undefined ? { costUsdMicro: Number(t.billing.total_cost_usd_micro) } : {}),
            });
          }
        }
        const delta: string = obj.choices?.[0]?.delta?.content ?? "";
        if (delta) {
          text += delta;
          handlers.onToken(delta);
        }
      } catch {
        /* keep-alive comments etc. */
      }
    }
  }
  return text;
}

/** §8.4 MOCK_AI: deterministic, offline, burns zero quota. */
async function mockStream(
  messages: { role: string; content: string }[],
  handlers: StreamHandlers,
): Promise<{ text: string; model: string }> {
  const user = messages.filter(m => m.role === "user").map(m => m.content).join("\n");
  const tagMatch = user.match(/^\[\[(.+?)\]\]/m);
  const tag = tagMatch ? tagMatch[1] : "run";
  const input = user.split("\n").slice(-1)[0]?.slice(0, 140) ?? "";
  // A rewrite asks for JSON, one key per style; the mock keeps that shape
  // (a plain echo would be the model talking about the message, which the
  // real path rightly refuses to offer).
  const text = tag === "act.rewrite.options"
    ? JSON.stringify({ basic: input, work: `MOCK professional: ${input}`, shorter: `MOCK shorter: ${input}` })
    : `MOCK ${tag}: ${input}`;
  for (const word of text.split(/(?<= )/)) {
    if (handlers.signal?.aborted) break;
    handlers.onToken(word);
    await new Promise(r => setTimeout(r, 12));
  }
  return { text, model: "mock" };
}

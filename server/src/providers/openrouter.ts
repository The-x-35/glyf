import { env } from "../env.js";
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

/** Per-model request settings. Reasoning models think before the first
 *  token unless told not to — seconds a keyboard can't spend — and some put
 *  that thinking into the answer text. */
export function requestOptions(ep: Endpoint, tier: "fast" | "smart"): Record<string, unknown> {
  const opts: Record<string, unknown> = { max_tokens: tier === "fast" ? 1500 : 4000 };
  const id = ep.model.toLowerCase();
  if (ep.openrouter) {
    opts.reasoning = id.includes("gpt-oss")
      ? { effort: tier === "fast" ? "low" : "medium", exclude: true }
      : { exclude: true };
    return opts;
  }
  if (id.includes("gpt-oss")) {
    opts.reasoning_effort = tier === "fast" ? "low" : "medium";
  } else if (ep.url.includes("groq.com") && id.includes("qwen")) {
    // Groq returns Qwen's thinking as raw <think> text otherwise.
    opts.reasoning_effort = "none";
  } else if (ep.url.includes("googleapis.com") && /gemini-[\d.]+-(flash|pro)(?!-lite)/.test(id)) {
    // Gemini's full flash/pro models think first; the lite ones don't take the
    // option at all (400 Invalid argument), so never send it to them.
    opts.reasoning_effort = tier === "fast" ? "none" : "low";
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

/** How long a model gets to start answering before the next one is tried. */
export const FIRST_BYTE_MS = { fast: 4000, smart: 9000 };

export interface StreamHandlers {
  onToken: (t: string) => void;
  signal?: AbortSignal;
}

export class ModelExhaustedError extends Error {
  constructor(public attempts: { model: string; status: number | string }[]) {
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
  tier: "fast" | "smart",
  messages: { role: string; content: string }[],
  handlers: StreamHandlers,
): Promise<{ text: string; model: string }> {
  const vault = new SecretVault();
  const safe = messages.map(m => ({ role: m.role, content: vault.mask(m.content) }));
  if (vault.count > 0) {
    const last = safe.length - 1;
    safe[last] = { ...safe[last], content: safe[last].content + KEEP_PLACEHOLDERS };
  }
  const stream = vault.restoringStream(handlers.onToken);
  const res = await completeMasked(tier, safe, { ...handlers, onToken: stream.push });
  stream.flush();
  return { text: vault.restore(res.text), model: res.model };
}

/** What a model is actually sent: messages with nothing private left in them. */
export let lastOutboundForTests: { role: string; content: string }[] = [];

async function completeMasked(
  tier: "fast" | "smart",
  messages: { role: string; content: string }[],
  handlers: StreamHandlers,
): Promise<{ text: string; model: string }> {
  if (process.env.VITEST) lastOutboundForTests = messages;
  if (env.mockAI) {
    return mockStream(messages, handlers);
  }
  const models = readyModels(tier === "smart" ? env.smartModels : env.fastModels);
  const attempts: { model: string; status: number | string }[] = [];

  for (const model of models) {
    const ep = endpointFor(model);
    if (!ep) {
      attempts.push({ model, status: "no-key" });
      continue;
    }
    // A model that has not started answering in a few seconds is stuck (a
    // queue, a silent rate limit): someone is holding the space bar, so move
    // on to the next one rather than wait it out.
    const attempt = new AbortController();
    const stuck = setTimeout(() => attempt.abort(), tier === "fast" ? FIRST_BYTE_MS.fast : FIRST_BYTE_MS.smart);
    const onAbort = () => attempt.abort();
    handlers.signal?.addEventListener("abort", onAbort);
    try {
      const res = await fetch(ep.url, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${ep.key}`,
          "Content-Type": "application/json",
          ...(ep.openrouter ? { "HTTP-Referer": "https://tryglyf.com", "X-Title": "Glyf" } : {}),
        },
        body: JSON.stringify({ model: ep.model, messages, stream: true, ...requestOptions(ep, tier) }),
        signal: attempt.signal,
      });
      clearTimeout(stuck);
      if (!res.ok || !res.body) {
        if (res.status === 429) noteRateLimited(model, res.headers.get("retry-after"));
        attempts.push({ model, status: res.status });
        continue;
      }
      const gate = new VerdictGate(handlers.onToken);
      const text = await drainSSE(res.body, { ...handlers, onToken: t => gate.push(t) });
      if (text.trim().length === 0) {
        attempts.push({ model, status: "empty" });
        continue;
      }
      if (gate.finish(text)) {
        // A router picked a moderation model: its verdict is not an answer,
        // and none of it reached the client — try the next model.
        attempts.push({ model, status: "classifier" });
        continue;
      }
      return { text, model };
    } catch (err) {
      if (handlers.signal?.aborted) throw err;
      attempts.push({ model, status: attempt.signal.aborted ? "slow" : (err as Error).name || "error" });
    } finally {
      clearTimeout(stuck);
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

async function drainSSE(
  body: ReadableStream<Uint8Array>,
  handlers: StreamHandlers,
): Promise<string> {
  const reader = body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  let text = "";
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
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
  const text = `MOCK ${tag}: ${input}`;
  for (const word of text.split(/(?<= )/)) {
    if (handlers.signal?.aborted) break;
    handlers.onToken(word);
    await new Promise(r => setTimeout(r, 12));
  }
  return { text, model: "mock" };
}

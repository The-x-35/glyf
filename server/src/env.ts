import { config } from "dotenv";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

config({ path: join(dirname(fileURLToPath(import.meta.url)), "..", ".env") });

function num(name: string, fallback: number): number {
  const v = Number(process.env[name]);
  return Number.isFinite(v) && v > 0 ? v : fallback;
}

export const env = {
  port: num("PORT", 8787),
  openrouterKey: process.env.OPENROUTER_API_KEY ?? "",
  /** Optional OpenAI-compatible providers with free, fast tiers (no card).
   *  Route to them with "groq:<model>" / "gemini:<model>" in *_MODELS. */
  groqKey: process.env.GROQ_API_KEY ?? "",
  geminiKey: process.env.GEMINI_API_KEY ?? "",
  /** More OpenAI-compatible pools: "mistral:<model>" (free plan credits),
   *  "inception:<model>" (free tokens), "cerebras:<model>" (paid, fastest). */
  mistralKey: process.env.MISTRAL_API_KEY ?? "",
  inceptionKey: process.env.INCEPTION_API_KEY ?? "",
  cerebrasKey: process.env.CEREBRAS_API_KEY ?? "",
  mockAI: process.env.MOCK_AI === "true",
  /** The models and each plan's day are set here in code, never by the
   *  environment: a stale Railway variable once kept production on a slow
   *  chain with the old caps. Tests may still change them in-process. */
  /** A free plan's day. Plus and Max are in lib/limits.ts (PAID_PER_DAY). */
  freeRunsPerDay: 20,
  /** The strip's suggestions have their own allowance and never spend a run. */
  freeSuggestionsPerDay: 100,
  /** So do the translate bar's translations. */
  freeTranslationsPerDay: 100,
  /** §8.3 fallback chains, most-preferred first, measured 2026-09-26 for
   *  speed and price (docs/BACKEND.md 5.10). Never hard-code one :free id.
   *  Hold space and chip taps: Qwen 3.7 Flash writes all six rewrite
   *  versions for about $0.03 a thousand; Gemini 2.5 Flash-Lite stands
   *  behind it, then Gemini's own free tier. */
  fastModels: ["qwen/qwen3.7-flash", "google/gemini-2.5-flash-lite:nitro",
    "gemini:gemini-flash-lite-latest", "openrouter/free"],
  /** The Builder: Ling 3.0 Flash made a valid glyf six times out of six in
   *  about 2 s for $0.03 a thousand; Gemini 2.5 Flash-Lite (1.4 s) next. */
  smartModels: ["inclusionai/ling-3.0-flash", "google/gemini-2.5-flash-lite:nitro",
    "gemini:gemini-flash-lite-latest", "openrouter/free"],
  /** What reads a pause in typing for the strip's chip: small, paid, cheap
   *  (about $8 a million reads on Qwen 3.7 Flash) and never a free tier
   *  that keeps what it is sent. */
  suggestModels: ["qwen/qwen3.7-flash", "google/gemini-2.5-flash-lite", "inclusionai/ling-3.0-flash"],
  /** How long a glyf run's text is replayed (routes/glyf.ts): ten minutes
   *  at most, so nothing a person reads is ever much older than that. */
  cacheTtlMs: Math.min(num("CACHE_TTL_MS", 10 * 60 * 1000), 10 * 60 * 1000),
};

export function assertServerSecrets(): void {
  const anyKey = [env.openrouterKey, env.groqKey, env.geminiKey, env.mistralKey, env.inceptionKey, env.cerebrasKey]
    .some(Boolean);
  if (!env.mockAI && !anyKey) {
    throw new Error("No model key — set GEMINI_API_KEY, GROQ_API_KEY or OPENROUTER_API_KEY in server/.env, or run with MOCK_AI=true");
  }
}

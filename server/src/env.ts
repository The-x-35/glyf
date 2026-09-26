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
  /** A free plan's day. Plus and Max are fixed in lib/limits.ts. */
  freeRunsPerDay: num("FREE_RUNS_PER_DAY", 20),
  /** The strip's suggestions have their own allowance and never spend a run. */
  freeSuggestionsPerDay: num("FREE_SUGGESTIONS_PER_DAY", 100),
  /** So do the translate bar's translations. */
  freeTranslationsPerDay: num("FREE_TRANSLATIONS_PER_DAY", 100),
  /** §8.3 fallback chain, most-preferred first. Never hard-code one :free id.
   *  Qwen 3.7 Flash writes all six rewrite versions for about $0.03 a
   *  thousand, a third of Gemini 2.5 Flash-Lite, which stands behind it. */
  fastModels: (process.env.FAST_MODELS
    ?? "qwen/qwen3.7-flash,google/gemini-2.5-flash-lite:nitro,gemini:gemini-flash-lite-latest,openrouter/free")
    .split(",").map(s => s.trim()),
  smartModels: (process.env.SMART_MODELS ?? "openrouter/free").split(",").map(s => s.trim()),
  /** What reads a pause in typing for the strip's chip: small, paid, cheap
   *  (about $8 a million reads on Qwen 3.7 Flash) and never a free tier
   *  that keeps what it is sent. */
  suggestModels: (process.env.SUGGEST_MODELS
    ?? "qwen/qwen3.7-flash,google/gemini-2.5-flash-lite,inclusionai/ling-3.0-flash")
    .split(",").map(s => s.trim()),
  cacheTtlMs: num("CACHE_TTL_MS", 24 * 3600 * 1000),
  // Privy creds are parked here for M8's backend integration — NEVER sent to
  // clients, NEVER used before the crypto connector milestone (SPEC §6.14).
  privyAppId: process.env.PRIVY_APP_ID ?? "",
};

export function assertServerSecrets(): void {
  const anyKey = [env.openrouterKey, env.groqKey, env.geminiKey, env.mistralKey, env.inceptionKey, env.cerebrasKey]
    .some(Boolean);
  if (!env.mockAI && !anyKey) {
    throw new Error("No model key — set GEMINI_API_KEY, GROQ_API_KEY or OPENROUTER_API_KEY in server/.env, or run with MOCK_AI=true");
  }
}

import { config } from "dotenv";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

// server/.env on a laptop holds the production database. A test run must
// never reach it, so under vitest that one line of the file is skipped (a
// DATABASE_URL already in the real environment is left alone, as dotenv
// always does).
const fromFile: Record<string, string> = {};
config({ path: join(dirname(fileURLToPath(import.meta.url)), "..", ".env"), processEnv: fromFile });
for (const [key, value] of Object.entries(fromFile)) {
  if (key in process.env) continue;
  if (process.env.VITEST && key === "DATABASE_URL") continue;
  process.env[key] = value;
}

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
  /** NEAR AI Cloud (cloud-api.near.ai), only for phones that send
   *  X-Glyf-AI: near (lib/privateai.ts). */
  nearAIKey: process.env.NEARAI_API_KEY ?? "",
  mockAI: process.env.MOCK_AI === "true",
  /** The models and each plan's day are set here in code, never by the
   *  environment: a stale Railway variable once kept production on a slow
   *  chain with the old caps. Tests may still change them in-process. */
  /** A free plan's runs, counted over a week since 14 Oct 2026 (Arpit:
   *  "free to 50 runs per week"; lib/limits.ts capsFor). Plus and Max keep a
   *  day's (PAID_PER_DAY). The name stays for the tests that change it. */
  freeRunsPerDay: 50,
  /** The strip's suggestions have their own allowance and never spend a run. */
  freeSuggestionsPerDay: 100,
  /** So do the translate bar's translations. */
  freeTranslationsPerDay: 100,
  /** §8.3 fallback chains, most-preferred first, measured 2026-09-26 for
   *  speed and price (docs/BACKEND.md 5.10). Paid OpenRouter models only,
   *  every request denying data collection (requestOptions): no free tier,
   *  whose providers may keep or train on what they are sent (Google's OAuth
   *  review, 2026-10-01; the privacy policy promises it). Never hard-code
   *  one :free id. Hold space and chip taps: Qwen 3.7 Flash writes all six
   *  rewrite versions for about $0.03 a thousand; Gemini 2.5 Flash-Lite
   *  stands behind it. */
  fastModels: ["qwen/qwen3.7-flash", "google/gemini-2.5-flash-lite:nitro", "google/gemini-2.5-flash-lite", "gemini:gemini-3.5-flash-lite"],
  /** The Builder: Ling 3.0 Flash made a valid glyf six times out of six in
   *  about 2 s for $0.03 a thousand; Gemini 2.5 Flash-Lite (1.4 s) next. */
  smartModels: ["inclusionai/ling-3.0-flash", "google/gemini-2.5-flash-lite:nitro", "google/gemini-2.5-flash-lite", "gemini:gemini-3.5-flash-lite"],
  /** A question answered from what a model knows (hold space, the strip's
   *  "AI answer", the web tab), there being no search for now. Measured
   *  2026-09-29 on 18 facts twice at temperature 0: Gemini 3.1 Flash-Lite
   *  36/36 in about 1 s ($0.14 a thousand answers); Qwen 3.7 Flash 48/54,
   *  "France won the 2022 FIFA World Cup" every time and a made-up Super
   *  Bowl LX; Gemini 2.5 Flash-Lite thought the 2024 election was still to
   *  come. */
  answerModels: ["google/gemini-3.1-flash-lite", "qwen/qwen3.7-flash", "google/gemini-2.5-flash-lite:nitro", "gemini:gemini-3.5-flash-lite"],
  /** What reads a pause in typing for the strip's chip: small, paid, cheap
   *  (about $8 a million reads on Qwen 3.7 Flash) and never a free tier
   *  that keeps what it is sent. */
  /* Every chain ends in Gemini 3.5 Flash-Lite straight from Google
   * (GEMINI_API_KEY): OpenRouter's key answered 401 "User not found" in
   * Nov 2026 and every AI call failed (Arpit: "make the AI working, maybe use
   * a free plan"). A refused key is skipped for ten minutes, so the backup
   * answers at its own speed (about 1.6 s for a rewrite). */
  suggestModels: ["qwen/qwen3.7-flash", "google/gemini-2.5-flash-lite", "inclusionai/ling-3.0-flash", "gemini:gemini-3.5-flash-lite"],
  /** Private AI (lib/privateai.ts): NEAR AI Cloud's own private models,
   *  run in TEEs (verifiable, each with a model attestation report).
   *  Measured 2026-11-13 on a rewrite with thinking off: Qwen 3.6 35B-A3B
   *  answered in 1.1 s ($0.17 in / $1.10 out per million tokens), Qwen 3.8
   *  27B in 2.5 s ($0.04 / $1.35). GLM 5.3 Flash was dropped: it thought for
   *  800 characters anyway and took 6.6 s. Nothing outside NEAR AI answers
   *  these phones. */
  nearAIModels: ["nearai:Qwen/Qwen3.6-35B-A3B-FP8", "nearai:Qwen/Qwen3.8-27B"] as string[],
  nearAISmartModels: ["nearai:Qwen/Qwen3.6-35B-A3B-FP8", "nearai:Qwen/Qwen3.8-27B"] as string[],
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

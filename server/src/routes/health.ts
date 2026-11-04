import type { FastifyInstance } from "fastify";
import { env } from "../env.js";
import { aiHealth } from "../lib/aihealth.js";
import type { KV } from "../lib/store.js";
import { PROVIDERS } from "./connector.js";

/** GET /health is how a deploy gets checked, so it answers the question the
 *  checker actually has: which providers are configured here? GET
 *  /health?deep=1 adds whether a model actually answers.
 *
 *  Presence booleans and public origins only, never a key or any part of one
 *  (§1.6). Existing fields keep their names and meanings; new ones are added
 *  beside them so older clients and scripts keep parsing it. */
export function healthRoutes(app: FastifyInstance, kv?: KV): void {
  const has = (name: string) => Boolean(process.env[name]?.trim());

  app.get<{ Querystring: { deep?: string } }>("/health", async (req, reply) => {
    const report = summary();
    // ?deep=1 also asks a model for one word (lib/aihealth.ts: cached for a
    // minute) and answers 503 when none replies, for an uptime monitor.
    // Plain /health never calls out, so it stays instant.
    const deep = req.query?.deep;
    if (deep !== "1" && deep !== "true") return report;
    const ai = await aiHealth();
    return reply.code(ai.ok ? 200 : 503).send({ ...report, ok: ai.ok, ai });
  });

  function summary() {
    const models = {
      openrouter: env.openrouterKey.length > 0,
      gemini: env.geminiKey.length > 0,
      groq: env.groqKey.length > 0,
      mistral: env.mistralKey.length > 0,
      inception: env.inceptionKey.length > 0,
      cerebras: env.cerebrasKey.length > 0,
    };
    const connectors: Record<string, boolean> = {
      google: has("GOOGLE_CLIENT_ID") && has("GOOGLE_CLIENT_SECRET"),
    };
    for (const [id, p] of Object.entries(PROVIDERS)) {
      connectors[id] = has(`${p.envPrefix}_CLIENT_ID`) && has(`${p.envPrefix}_CLIENT_SECRET`);
    }
    return {
      ok: true,
      mockAI: env.mockAI,
      fastModels: env.fastModels,
      // Never echo secrets: presence booleans only (§1.6).
      hasOpenRouterKey: models.openrouter,
      smartModels: env.smartModels,
      suggestModels: env.suggestModels,
      /** True when this deploy can actually answer: a real model, not mock. */
      live: !env.mockAI && Object.values(models).some(Boolean),
      models,
      search: {
        brave: has("BRAVE_SEARCH_KEY"),
        serper: has("SERPER_API_KEY"),
        youtube: has("YOUTUBE_API_KEY"),
        googlePlaces: has("GOOGLE_PLACES_KEY"),
        googleWeather: has("GOOGLE_WEATHER_KEY") || has("GOOGLE_PLACES_KEY"),
        geoapify: has("GEOAPIFY_KEY"),
        klipy: has("KLIPY_APP_KEY"),
      },
      connectors,
      storage: kv?.status?.() ?? { driver: "unknown", ready: true, collections: 0 },
      env: {
        nodeEnv: process.env.NODE_ENV ?? "development",
        // Public origins, not secrets: they show up in every OAuth redirect
        // and in every shared page link, and getting them wrong is the most
        // common deploy mistake.
        oauthRedirectBase: process.env.OAUTH_REDIRECT_BASE ?? "",
        publicBaseUrl: process.env.PUBLIC_BASE_URL ?? "",
        hasDatabaseUrl: has("DATABASE_URL"),
      },
    };
  }
}

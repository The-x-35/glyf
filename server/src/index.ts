import Fastify from "fastify";
import { env, assertServerSecrets } from "./env.js";
import { Guard } from "./lib/guard.js";
import { protectRoutes } from "./lib/protect.js";
import { buildLimiter } from "./lib/limiter-factory.js";
import { defaultKV, type KV } from "./lib/store.js";
import { GlyfLibrary } from "./lib/userglyfs.js";
import { glyfRoutes } from "./routes/glyf.js";
import { meterRoutes } from "./routes/meter.js";
import { healthRoutes } from "./routes/health.js";
import { builderRoutes } from "./routes/builder.js";
import { hubRoutes } from "./routes/hub.js";
import { connectorRoutes } from "./routes/connector.js";
import { telemetryRoutes } from "./routes/telemetry.js";
import { gifRoutes } from "./routes/gif.js";
import { toolsRoutes } from "./routes/tools.js";
import { searchRoutes } from "./routes/search.js";
import { waitlistRoutes } from "./routes/waitlist.js";
import { actRoutes } from "./routes/act.js";
import { walletRoutes } from "./routes/wallet.js";
import { suggestRoutes } from "./routes/suggest.js";
import { translateRoutes } from "./routes/translate.js";
import { vocabRoutes } from "./routes/vocab.js";
import { authRoutes } from "./routes/auth.js";
import { meRoutes } from "./routes/me.js";

declare module "fastify" {
  interface FastifyInstance {
    /** The store this instance was built with, so a serverless entry point can
     *  flush queued writes once the response is done. */
    glyfKV: KV;
  }
}

/** `kv` is a parameter only so tests can watch the serverless lifecycle hooks;
 *  every caller leaves it alone and gets the store `defaultKV()` picks. */
export function buildApp(kv: KV = defaultKV()) {
  const app = Fastify({
    logger: { level: "info" },
    disableRequestLogging: true,
    // Nothing anyone types needs a megabyte; oversized bodies are refused
    // before a handler ever sees them.
    bodyLimit: 512 * 1024,
  });
  const limits = buildLimiter();
  const guard = new Guard({ limits, freePerDay: env.freeRunsPerDay });
  // The lock goes on before any route is registered, so nothing added later
  // is open by accident.
  protectRoutes(app, { limits });
  const library = new GlyfLibrary(kv);
  app.decorate("glyfKV", kv);

  // A store that lives somewhere else (Postgres on serverless) keeps the
  // synchronous KV calls honest with two hooks: read in what other instances
  // wrote before a handler looks, and get this handler's writes durable before
  // the client can act on the response (a /p/<id> link, an OAuth redirect).
  // FileKV and MemoryKV define neither, so local runs add nothing.
  if (kv.refresh) {
    app.addHook("onRequest", async () => {
      try {
        await kv.refresh!();
      } catch (err) {
        // Serve what the mirror already holds rather than failing the request.
        app.log.error({ err: err instanceof Error ? err.message : String(err) }, "kv_refresh_failed");
      }
    });
  }
  if (kv.flush) {
    app.addHook("onSend", async (_req, _reply, payload) => {
      await kv.flush!();
      return payload;
    });
  }

  healthRoutes(app, kv);
  glyfRoutes(app, guard, library, kv);
  meterRoutes(app, guard);
  builderRoutes(app, library, guard);
  hubRoutes(app, library, kv);
  connectorRoutes(app, kv);
  telemetryRoutes(app, kv);
  gifRoutes(app);
  toolsRoutes(app);
  searchRoutes(app, kv, guard);
  waitlistRoutes(app, kv);
  actRoutes(app, guard, kv);
  walletRoutes(app);
  suggestRoutes(app, guard);
  translateRoutes(app, guard);
  vocabRoutes(app, guard);
  authRoutes(app);
  meRoutes(app);
  return app;
}

const isMain = process.argv[1]?.endsWith("index.ts") || process.argv[1]?.endsWith("index.js");
if (isMain) {
  assertServerSecrets();
  const app = buildApp();
  app.listen({ port: env.port, host: "0.0.0.0" }).then(() => {
    app.log.info(`glyf server on :${env.port} mockAI=${env.mockAI}`);
  }).catch(err => {
    console.error(err);
    process.exit(1);
  });
}

import Fastify from "fastify";
import { env, assertServerSecrets } from "./env.js";
import { MemoryMeter } from "./lib/meter.js";
import { defaultKV } from "./lib/store.js";
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
import { vocabRoutes } from "./routes/vocab.js";

export function buildApp() {
  const app = Fastify({
    logger: { level: "info" },
    disableRequestLogging: true,
  });
  const kv = defaultKV();
  const meter = new MemoryMeter(env.freeRunsPerDay);
  const library = new GlyfLibrary(kv);

  healthRoutes(app);
  glyfRoutes(app, meter, library, kv);
  meterRoutes(app, meter);
  builderRoutes(app, library);
  hubRoutes(app, library, kv);
  connectorRoutes(app, kv);
  telemetryRoutes(app, kv);
  gifRoutes(app);
  toolsRoutes(app);
  searchRoutes(app, kv);
  waitlistRoutes(app, kv);
  actRoutes(app, meter, kv);
  vocabRoutes(app, meter);
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

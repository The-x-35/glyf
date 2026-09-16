import type { IncomingMessage, ServerResponse } from "node:http";
import type { FastifyInstance } from "fastify";
import { buildApp } from "../src/index.js";

/** Vercel entry point: one function that serves the whole Fastify app.
 *
 *  `vercel.json` rewrites every path here, so routing stays where it already
 *  is (`buildApp()` in src/index.ts registers the same routes as `npm start`).
 *  Nothing is duplicated and nothing about the local flows changes: `npm run
 *  dev` and `npm start` still run src/index.ts and listen on a port.
 *
 *  The app is built once per cold start and reused by every request the warm
 *  instance handles. Handing the raw req/res to Fastify's own server keeps the
 *  response a real Node stream, which is what /glyf/run needs: SSE frames go
 *  out as they are written instead of being collected into one body. */

let app: Promise<FastifyInstance> | undefined;

function instance(): Promise<FastifyInstance> {
  if (!app) {
    app = (async () => {
      const fastify = buildApp();
      await fastify.ready();
      return fastify;
    })();
  }
  return app;
}

export default async function handler(
  req: IncomingMessage, res: ServerResponse,
): Promise<void> {
  let fastify: FastifyInstance;
  try {
    fastify = await instance();
  } catch (err) {
    // A build failure would otherwise be an unexplained 500 on every path.
    app = undefined;
    console.error("[boot] buildApp failed", err);
    res.statusCode = 500;
    res.setHeader("content-type", "application/json");
    res.end(JSON.stringify({ ok: false, error: "Server failed to start" }));
    return;
  }

  fastify.server.emit("request", req, res);

  // Hold the invocation open until the response is finished. Without this the
  // function can be frozen mid-stream, and queued writes would never land.
  await new Promise<void>(resolve => {
    if (res.writableEnded) return resolve();
    res.once("close", resolve);
    res.once("finish", resolve);
  });

  // Backstop for the streaming routes, which end the raw response themselves
  // and so never reach the onSend hook that flushes for everyone else.
  try {
    await fastify.glyfKV.flush?.();
  } catch (err) {
    console.error("[kv] flush after response failed", err);
  }
}

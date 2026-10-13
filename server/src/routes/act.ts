import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { env } from "../env.js";
import { act, RunRefused, type ActResult, type ActStream } from "../lib/act.js";
import type { Guard, Verdict } from "../lib/guard.js";
import { createPage, getPage, renderPage } from "../lib/pages.js";
import type { KV } from "../lib/store.js";

/** POST /act — hold space: act on the typed intent (see lib/act.ts).
 *  Metered like a glyf run: it is the user asking the AI to do something. */

const ActSchema = z.object({
  text: z.string().min(1).max(2000),
  deviceId: z.string().min(1).max(80),
  plan: z.enum(["free", "plus", "max"]).default("free"),
  /** Coarse location, forwarded from the app's cached fix; never stored. */
  lat: z.number().min(-90).max(90).optional(),
  lon: z.number().min(-180).max(180).optional(),
  country: z.string().length(2).optional(),
  tz: z.string().max(64).optional(),
  /** Shareable vault details, when the writer allows it (see ActOptions). */
  profile: z.record(z.string().max(40), z.string().max(400)).optional(),
  /** Set when a suggestion chip was tapped: do what the chip said. */
  intent: z.enum(["place", "places", "answer", "video", "rewrite", "write"]).optional(),
  /** Answer as a stream of events: each version as soon as it is written,
   *  written text as it comes, then the whole result. Older keyboards leave
   *  it out and get one JSON reply, as before. */
  stream: z.boolean().optional(),
});

/** Where shared pages live. Unset in dev → this server, which is enough to
 *  open the link on the same machine; production sets PUBLIC_BASE_URL. */
function pageBase(): string | undefined {
  const base = process.env.PUBLIC_BASE_URL?.replace(/\/+$/, "");
  if (base) return base;
  return process.env.NODE_ENV === "production" ? undefined : `http://127.0.0.1:${env.port}`;
}

export function actRoutes(app: FastifyInstance, guard: Guard, kv: KV): void {
  app.get("/p/:id", async (req, reply) => {
    const page = getPage(kv, (req.params as { id: string }).id);
    if (!page) return reply.code(404).type("text/html").send("<h1>Not found</h1>");
    reply.header("cache-control", "public, max-age=300");
    // The page is static: no script may run on it, nothing may frame it.
    reply.header("content-security-policy",
      "default-src 'none'; style-src 'unsafe-inline'; img-src https: data:; base-uri 'none'; form-action 'none'; frame-ancestors 'none'");
    reply.header("x-content-type-options", "nosniff");
    reply.header("referrer-policy", "no-referrer");
    return reply.type("text/html").send(renderPage(page));
  });

  app.post("/act", async (req, reply) => {
    const parsed = ActSchema.safeParse(req.body);
    if (!parsed.success) {
      // Issues name the bad FIELD; the body is the user's text and stays out of logs.
      // Where the body was wrong, never what it said (it is what they typed).
      req.log.warn({ issues: parsed.error.issues.map(i => ({ path: i.path, code: i.code })) }, "act bad request");
      return reply.code(400).send({ ok: false, error: "Bad request" });
    }
    const { text, deviceId, plan, lat, lon, country, tz, profile, intent, stream } = parsed.data;

    // A run is spent the first time the model is asked, never up front: a
    // sum, a conversion, a price, the time or a place list costs nothing.
    let paid: Promise<Verdict> | undefined;
    const pay = async () => {
      const verdict = await (paid ??= guard.spend(req, deviceId));
      if (!verdict.ok) throw new RunRefused(verdict.message);
    };
    const remainingNow = async () => paid ? (await paid).remaining : guard.left(req, deviceId);

    const started = Date.now();
    const base = pageBase();
    const run = (live?: ActStream) => act(text, { lat, lon, country: country?.toUpperCase(), tz }, {
      profile,
      intent,
      publish: base ? (title, places) => `${base}/p/${createPage(kv, title, places)}` : undefined,
      stream: live,
      pay,
    });
    // The model was needed and no run was left: the refusal, even when
    // what was asked swallowed the error on its way out.
    const refusal = async (): Promise<string | undefined> => {
      if (!paid) return undefined;
      const verdict = await paid;
      return verdict.ok ? undefined : verdict.message;
    };
    // §12: events and timings only — never the typed text.
    const logDone = (result: ActResult) => req.log.info({ deviceId, intent: result.intent,
      provider: result.provider, cards: result.cards.length, inputChars: text.length,
      ms: Date.now() - started, streamed: !!stream }, "act");
    const failed = "Couldn't do that right now. Tap to retry.";

    if (!stream) {
      try {
        const result = await run();
        const refused = await refusal();
        if (refused) return reply.code(429).send({ ok: false, error: refused });
        logDone(result);
        return { ok: true, remaining: await remainingNow(), ...result };
      } catch (err) {
        const refused = await refusal();
        if (refused) return reply.code(429).send({ ok: false, error: refused });
        req.log.warn({ deviceId, err: err instanceof Error ? err.message : String(err) }, "act failed");
        return reply.code(502).send({ ok: false, error: failed });
      }
    }

    // The same headers as /glyf/run, so nothing in between holds the events
    // back until the end.
    reply.raw.writeHead(200, {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache, no-transform",
      Connection: "keep-alive",
      "X-Accel-Buffering": "no",
    });
    reply.raw.flushHeaders?.();
    const send = (event: string, data: unknown) => {
      if (!reply.raw.writableEnded) reply.raw.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
    };
    try {
      const result = await run({
        option: o => send("option", o),
        text: t => send("text", { t }),
        reset: () => send("reset", {}),
      });
      const refused = await refusal();
      if (refused) {
        send("error", { ok: false, error: refused });
      } else {
        logDone(result);
        send("done", { ok: true, remaining: await remainingNow(), ...result });
      }
    } catch (err) {
      const refused = await refusal();
      if (!refused) req.log.warn({ deviceId, err: err instanceof Error ? err.message : String(err) }, "act failed");
      send("error", { ok: false, error: refused ?? failed });
    }
    reply.raw.end();
  });
}

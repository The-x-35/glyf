import type { FastifyInstance } from "fastify";
import { env } from "../env.js";
import { profileBlock } from "../lib/act.js";
import { RunRequestSchema } from "../schemas/glyfdef.js";
import { loadRegistry, runGlyf } from "../lib/glyfengine.js";
import { completeStreaming } from "../providers/openrouter.js";
import { TTLCache } from "../lib/cache.js";
import type { Guard } from "../lib/guard.js";
import type { GlyfLibrary } from "../lib/userglyfs.js";
import type { KV } from "../lib/store.js";
import { connKey, PROVIDERS } from "./connector.js";

/** POST /glyf/run — SSE stream: token* → done | error (§6.4 fast path).
 *  Resolution order: shipped registry → the device's own glyfs → hub installs.
 *  The device sends a glyf id + input; prompts and provider keys live here. */
/** Makes the writer's details available to any prompt that asks for them:
 *  {{profile}} for the whole block, {{profile.email}} for one line. */
function withProfile(vars: Record<string, string>,
                     profile?: Record<string, string>): Record<string, string> {
  if (!profile || Object.keys(profile).length === 0) return { ...vars, profile: "" };
  const out: Record<string, string> = { ...vars };
  for (const [k, v] of Object.entries(profile)) out[`profile.${k}`] = v;
  out.profile = profileBlock(profile).trim();
  return out;
}

export function glyfRoutes(
  app: FastifyInstance, guard: Guard, library: GlyfLibrary, kv: KV,
): void {
  const registry = loadRegistry();
  const cache = new TTLCache(env.cacheTtlMs);

  /** provider → live access token for this device (expired ones dropped —
   *  the tool then asks the user to reconnect). Tokens stay server-side. */
  const connectionsFor = (deviceId: string): Record<string, string> => {
    const out: Record<string, string> = {};
    for (const provider of ["google", ...Object.keys(PROVIDERS)]) {
      const conn = kv.get<{ access_token: string; expires_at: number }>(
        "connections", connKey(deviceId, provider));
      if (conn && conn.expires_at > Date.now()) {
        out[provider] = conn.access_token;
      }
    }
    return out;
  };

  app.get("/glyf/catalog", async () => ({
    glyfs: [...registry.values()].map(d => ({
      id: d.id, name: d.name, icon: d.icon, input: d.input,
      discloses: d.discloses, version: d.version,
    })),
  }));

  app.post("/glyf/run", async (req, reply) => {
    const parsed = RunRequestSchema.safeParse(req.body);

    // `no-transform` and `X-Accel-Buffering: no` are what tell a CDN or proxy
    // in front of this server (Vercel's included) to pass bytes through
    // instead of collecting the whole body first, which would turn the stream
    // into one late blob. flushHeaders() opens the stream immediately so the
    // client sees a live connection before the first token.
    reply.raw.writeHead(200, {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache, no-transform",
      Connection: "keep-alive",
      "X-Accel-Buffering": "no",
    });
    reply.raw.flushHeaders?.();
    const send = (event: string, data: unknown) => {
      reply.raw.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
    };
    const fail = (message: string) => {
      send("error", { message });
      reply.raw.end();
    };

    if (!parsed.success) return fail("Bad request");
    const { glyfId, input, vars, deviceId, pro, plan, profile } = parsed.data;
    const def = registry.get(glyfId) ?? library.resolve(deviceId, glyfId);
    if (!def) return fail(`Unknown glyf '${glyfId}'`);

    // §12: events + timings only — never content.
    const started = Date.now();
    req.log.info({ glyfId, deviceId, plan, inputChars: input.length }, "glyf_fired");

    // §6.16 plans: the cap belongs to the account (or the phone, signed
    // out) and comes from the database — what the client says about its plan
    // is not evidence.
    const gate = await guard.spend(req, deviceId);
    if (!gate.ok) return fail(gate.message);
    const remaining = gate.remaining;

    const abort = new AbortController();
    // Response close = client went away mid-stream. (req.raw "close" fires as
    // soon as the request body is consumed — aborting there kills every run.)
    reply.raw.on("close", () => {
      if (!reply.raw.writableEnded) abort.abort();
    });

    // §8.4 cache: replay without burning quota upstream (still metered).
    const cacheKey = TTLCache.key([def.id, String(def.version), input, JSON.stringify(vars)]);
    const cached = cache.get(cacheKey);
    if (cached !== undefined) {
      send("token", { t: cached });
      send("done", { text: cached, remaining, model: "cache", ms: Date.now() - started });
      reply.raw.end();
      return;
    }

    try {
      const text = await runGlyf({
        def, input, vars: withProfile(vars, profile),
        connections: connectionsFor(deviceId),
        complete: async (tier, prompt, onToken) => {
          const res = await completeStreaming(
            tier,
            [{ role: "user", content: prompt }],
            { onToken, signal: abort.signal },
          );
          return res.text;
        },
        onToken: t => send("token", { t }),
      });

      cache.set(cacheKey, text);
      send("done", { text, remaining, ms: Date.now() - started });
      req.log.info({ glyfId, ms: Date.now() - started, ok: true }, "glyf_done");
    } catch (err) {
      if (!abort.signal.aborted) {
        const message = String((err as Error).message ?? err);
        req.log.warn({ glyfId, err: message }, "glyf_failed");
        // Tool/ask errors are user-meaningful; transport errors get the
        // standard quiet-retry line (§6.4).
        fail(message.startsWith("needs input") || message.includes("tool")
          ? message : "Couldn't reach Glyf. Tap to retry.");
        return;
      }
    }
    reply.raw.end();
  });
}

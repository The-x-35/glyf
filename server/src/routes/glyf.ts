import type { FastifyInstance } from "fastify";
import { env } from "../env.js";
import { profileBlock } from "../lib/act.js";
import { RunRequestSchema, type GlyfDef } from "../schemas/glyfdef.js";
import { loadRegistry, runGlyf, userFacingRunError } from "../lib/glyfengine.js";
import { completeStreaming } from "../providers/openrouter.js";
import { TTLCache } from "../lib/cache.js";
import type { Guard } from "../lib/guard.js";
import type { GlyfLibrary } from "../lib/userglyfs.js";
import type { KV } from "../lib/store.js";
import { connKey, PROVIDERS } from "./connector.js";
import { aiContext } from "../lib/privateai.js";
import { modelFree } from "../lib/buildertools.js";

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

/** Whether a run can be replayed to the same person: only when its words
 *  depend on nothing but what they typed. A tool answers live (the weather,
 *  a price), {{lat}}/{{lon}} is where the phone is now, and {{profile}} is
 *  one person's own details. */
export function replayable(def: GlyfDef): boolean {
  if (def.steps.some(s => s.type === "tool")) return false;
  return !/\{\{\s*(?:profile|lat|lon)\b/.test(JSON.stringify(def.steps));
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
    const { glyfId, input, vars, deviceId, pro, plan, profile, lat, lon } = parsed.data;
    // Where the phone is, for the tools that can use it (Weather with no
    // place named): a var like any other, "" when the app never got a fix.
    const located: Record<string, string> =
      lat != null && lon != null ? { lat: String(lat), lon: String(lon) } : {};
    const def = registry.get(glyfId) ?? library.resolve(deviceId, glyfId);
    if (!def) return fail(`Unknown glyf '${glyfId}'`);

    // §12: events + timings only — never content.
    const started = Date.now();
    req.log.info({ glyfId, deviceId, plan, inputChars: input.length }, "glyf_fired");

    // §6.16 plans: the cap belongs to the account (or the phone, signed
    // out) and comes from the database — what the client says about its plan
    // is not evidence.
    // A glyf that only hands over a Meet link or a place calls no model and
    // costs no run (only glyfs built with the Builder's Tools can be one).
    let remaining: number | undefined;
    if (!modelFree(def)) {
      const gate = await guard.spend(req, deviceId);
      if (!gate.ok) return fail(gate.message);
      remaining = gate.remaining;
    }

    // The glyf's own Private AI choice, when it made one, beats the phone's.
    const ai = aiContext();
    if (ai && def.privateAI !== undefined) ai.zeroG = def.privateAI;

    const abort = new AbortController();
    // Response close = client went away mid-stream. (req.raw "close" fires as
    // soon as the request body is consumed — aborting there kills every run.)
    reply.raw.on("close", () => {
      if (!reply.raw.writableEnded) abort.abort();
    });

    // §8.4 cache: replay without burning quota upstream (still metered) —
    // to the same person, for the same glyf as it is now, and never a run
    // whose words depend on more than the input.
    const cacheKey = replayable(def) ? TTLCache.key([def.id, String(def.version),
      TTLCache.key([JSON.stringify(def.steps)]), req.glyfUser ?? "", deviceId, input, JSON.stringify(vars)]) : null;
    const cached = cacheKey ? cache.get(cacheKey) : undefined;
    if (cached !== undefined) {
      send("token", { t: cached });
      send("done", { text: cached, remaining, model: "cache", ms: Date.now() - started });
      reply.raw.end();
      return;
    }

    try {
      const text = await runGlyf({
        def, input, vars: withProfile({ ...located, ...vars }, profile),
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

      if (cacheKey) cache.set(cacheKey, text);
      send("done", { text, remaining, ms: Date.now() - started });
      req.log.info({ glyfId, ms: Date.now() - started, ok: true }, "glyf_done");
    } catch (err) {
      if (!abort.signal.aborted) {
        const message = String((err as Error).message ?? err);
        req.log.warn({ glyfId, err: message }, "glyf_failed");
        // Tool/ask errors are user-meaningful; a model that did not answer
        // is ours to own, and the line says so without blaming the network
        // (the request did reach us) or naming what failed (§6.4).
        fail(userFacingRunError(err, "Glyf is busy right now. Tap to retry."));
        return;
      }
    }
    reply.raw.end();
  });
}

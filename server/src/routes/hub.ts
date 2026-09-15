import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { GlyfLibrary } from "../lib/userglyfs.js";
import { loadRegistry } from "../lib/glyfengine.js";
import { CATEGORIES, creators, recordOfficialInstall, skillsList } from "../lib/skills.js";
import type { KV } from "../lib/store.js";

/** §6.9 — the Hub: browse, publish (private by default, one tap to publish,
 *  moderation on publish), install (version-pinned), creator profiles. */
export function hubRoutes(app: FastifyInstance, library: GlyfLibrary, kv: KV): void {
  const registry = loadRegistry();

  /** The Skills browser: shipped + community skills, by category and search. */
  app.get("/skills", async req => {
    const { category, q } = req.query as { category?: string; q?: string };
    const needle = q?.trim().toLowerCase();
    const all = skillsList(registry, library, kv);
    const skills = all.filter(s =>
      (!category || category === "All" || s.category === category) &&
      (!needle || s.name.toLowerCase().includes(needle) || s.author.toLowerCase().includes(needle)));
    const present = new Set(all.map(s => s.category));
    return { categories: CATEGORIES.filter(c => present.has(c)), skills };
  });

  app.get("/skills/creators", async () => ({ creators: creators(library) }));

  // ownerId is the publisher's device id — a credential here — so it never
  // leaves the server.
  app.get("/hub/list", async () => ({
    glyfs: library.hubList().map(({ ownerId: _owner, ...entry }) => entry),
  }));

  const IdDevice = z.object({
    glyfId: z.string().min(1),
    deviceId: z.string().min(8).max(64),
  });

  app.post("/hub/publish", async (req, reply) => {
    const parsed = IdDevice.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: "Bad request" });
    const refusal = library.publish(parsed.data.deviceId, parsed.data.glyfId);
    if (refusal) return reply.code(422).send({ error: refusal });
    return { ok: true };
  });

  /** Adds a skill to someone's keyboard: a shipped glyf just counts the
   *  install (the app binds it by id); a community one pins its version. */
  app.post("/skills/get", async (req, reply) => {
    const parsed = IdDevice.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: "Bad request" });
    const { glyfId, deviceId } = parsed.data;
    if (registry.has(glyfId)) {
      return { ok: true, official: true, installs: recordOfficialInstall(kv, deviceId, glyfId) };
    }
    const result = library.install(deviceId, glyfId);
    if ("error" in result) return reply.code(404).send(result);
    return { ok: true, official: false, def: result.def };
  });

  app.post("/hub/install", async (req, reply) => {
    const parsed = IdDevice.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: "Bad request" });
    const result = library.install(parsed.data.deviceId, parsed.data.glyfId);
    if ("error" in result) return reply.code(404).send(result);
    req.log.info({ glyfId: parsed.data.glyfId }, "hub_install");
    return result;
  });

  app.post("/account/name", async (req, reply) => {
    const parsed = z.object({
      deviceId: z.string().min(8).max(64),
      displayName: z.string().min(1).max(40),
    }).safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: "Bad request" });
    library.setDisplayName(parsed.data.deviceId, parsed.data.displayName);
    return { ok: true };
  });

  app.get<{ Params: { deviceId: string } }>("/account/:deviceId/creator", async req =>
    library.creatorStats(req.params.deviceId));
}

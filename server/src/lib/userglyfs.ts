import { randomUUID } from "node:crypto";
import { z } from "zod";
import { GlyfDef, GlyfDefSchema } from "../schemas/glyfdef.js";
import { KV } from "./store.js";
import { toolExists, loadTools } from "./tools.js";

/** User-authored + hub glyfs (§6.8/§6.9). Storage collections:
 *  userglyfs: id → { def, ownerId, createdAt, updatedAt, published }
 *  hub:      id → { def, ownerId, installs, publishedAt, version }
 *  installs: `${deviceId}:${glyfId}` → { version, disclosesHash }
 *  accounts: deviceId → { displayName } */

export interface UserGlyf {
  def: GlyfDef;
  ownerId: string;
  createdAt: string;
  updatedAt: string;
  published: boolean;
}

export interface HubEntry {
  def: GlyfDef;
  ownerId: string;
  ownerName: string;
  installs: number;
  publishedAt: string;
}

/** §6.8: user glyfs may not use privileged step types or unknown tools, and
 *  §6.9 moderation: anything reading vault/wallet that sends content to a
 *  non-registry destination is auto-rejected. Returns a refusal or null. */
export function validateUserDef(def: GlyfDef): string | null {
  if (def.requires.wallet) {
    return "User glyfs can't touch the wallet";
  }
  for (const step of def.steps) {
    if (step.type === "tool" && !toolExists(step.tool)) {
      return `Unknown tool '${step.tool}' — only registry tools are allowed`;
    }
    // A link preview fetches whatever address it is given, so a glyf could
    // otherwise build one out of a calendar, a profile or earlier steps and
    // send it to a site its author runs. It may only open what was typed.
    if (step.type === "tool" && step.tool === "url.unfurl"
        && String((step.args as Record<string, unknown>)?.url ?? "").trim() !== "{{input}}") {
      return "Link previews can only open the link you type";
    }
    // OAuth-backed tools are allowed in defs; at RUN time the executor
    // asks the user to connect the provider when no token exists.
  }
  if (def.discloses.length === 0) return "Every glyf must say what it can see";
  if (def.steps.length > 12) return "Too many steps (max 12)";
  const totalPrompt = def.steps.reduce(
    (n, s) => n + (s.type === "llm" ? s.prompt.length : 0), 0);
  if (totalPrompt > 6000) return "Prompts too long (6000 chars total)";
  return null;
}

/** Live models sometimes emit prompts that DESCRIBE the input without
 *  interpolating it — the draft would never reach the model. If the def
 *  declares an input but no step references {{input}}, wire it into the
 *  first llm step. Mutates and returns the def. */
export function ensureInputWired(def: GlyfDef): GlyfDef {
  if (def.input === "none") return def;
  const touchesInput = def.steps.some(s => JSON.stringify(s).includes("{{input}}"));
  if (!touchesInput) {
    const llm = def.steps.find(s => s.type === "llm");
    if (llm && llm.type === "llm") {
      llm.prompt += "\n\nText:\n{{input}}";
    }
  }
  return def;
}

export const SaveGlyfSchema = z.object({
  deviceId: z.string().min(8).max(64),
  def: z.unknown(),
});

export class GlyfLibrary {
  constructor(private kv: KV) {}

  save(deviceId: string, rawDef: unknown): { id: string } | { error: string } {
    const parsed = GlyfDefSchema.safeParse(rawDef);
    if (!parsed.success) {
      return { error: `Invalid glyf: ${parsed.error.issues[0]?.message ?? "schema"}` };
    }
    const def = parsed.data;
    const refusal = validateUserDef(def);
    if (refusal) return { error: refusal };

    const existing = this.kv.get<UserGlyf>("userglyfs", def.id);
    if (existing && existing.ownerId !== deviceId) {
      return { error: "That glyf belongs to someone else" };
    }
    const now = new Date().toISOString();
    const id = existing ? def.id : `user.${randomUUID().slice(0, 8)}`;
    const stored: UserGlyf = {
      def: { ...def, id, version: existing ? existing.def.version + 1 : 1 },
      ownerId: deviceId,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      published: existing?.published ?? false,
    };
    this.kv.put("userglyfs", id, stored);
    return { id };
  }

  mine(deviceId: string): UserGlyf[] {
    return this.kv.list<UserGlyf>("userglyfs")
      .filter(e => e.value.ownerId === deviceId)
      .map(e => e.value);
  }

  remove(deviceId: string, id: string): boolean {
    const g = this.kv.get<UserGlyf>("userglyfs", id);
    if (!g || g.ownerId !== deviceId) return false;
    this.kv.del("userglyfs", id);
    this.kv.del("hub", id);
    return true;
  }

  publish(deviceId: string, id: string): string | null {
    const g = this.kv.get<UserGlyf>("userglyfs", id);
    if (!g || g.ownerId !== deviceId) return "Not your glyf";
    const refusal = validateUserDef(g.def); // re-run moderation at publish (§6.9)
    if (refusal) return refusal;
    const account = this.kv.get<{ displayName?: string }>("accounts", deviceId);
    const entry: HubEntry = {
      def: g.def,
      ownerId: deviceId,
      ownerName: account?.displayName ?? "anonymous",
      installs: this.kv.get<HubEntry>("hub", id)?.installs ?? 0,
      publishedAt: new Date().toISOString(),
    };
    this.kv.put("hub", id, entry);
    this.kv.put("userglyfs", id, { ...g, published: true });
    return null;
  }

  hubList(): (Omit<HubEntry, "def"> & {
    id: string; name: string; icon: string; discloses: string[]; version: number;
  })[] {
    return this.kv.list<HubEntry>("hub").map(e => ({
      id: e.id,
      name: e.value.def.name,
      icon: e.value.def.icon,
      discloses: e.value.def.discloses,
      version: e.value.def.version,
      ownerId: e.value.ownerId,
      ownerName: e.value.ownerName,
      installs: e.value.installs,
      publishedAt: e.value.publishedAt,
    }));
  }

  /** §6.9: installs pin a version; updates with changed `discloses` require
   *  re-consent — the caller compares hashes. */
  install(deviceId: string, glyfId: string): { def: GlyfDef } | { error: string } {
    const entry = this.kv.get<HubEntry>("hub", glyfId);
    if (!entry) return { error: "Not on the hub" };
    // One device counts once: reinstalling or re-consenting to an update
    // must not inflate the number other people see.
    if (!this.kv.get<unknown>("installs", `${deviceId}:${glyfId}`)) {
      this.kv.put("hub", glyfId, { ...entry, installs: entry.installs + 1 });
    }
    this.kv.put("installs", `${deviceId}:${glyfId}`, {
      version: entry.def.version,
      discloses: entry.def.discloses,
      at: new Date().toISOString(),
    });
    return { def: entry.def };
  }

  /** Resolve a runnable def for this device: own glyfs, then hub installs. */
  resolve(deviceId: string, glyfId: string): GlyfDef | undefined {
    const own = this.kv.get<UserGlyf>("userglyfs", glyfId);
    if (own && own.ownerId === deviceId) return own.def;
    const installed = this.kv.get<unknown>("installs", `${deviceId}:${glyfId}`);
    if (installed) return this.kv.get<HubEntry>("hub", glyfId)?.def;
    return undefined;
  }

  setDisplayName(deviceId: string, name: string): void {
    this.kv.put("accounts", deviceId, { displayName: name.slice(0, 40) });
  }

  creatorStats(deviceId: string): { glyfs: number; installs: number } {
    const mine = this.kv.list<HubEntry>("hub").filter(e => e.value.ownerId === deviceId);
    return {
      glyfs: mine.length,
      installs: mine.reduce((n, e) => n + e.value.installs, 0),
    };
  }
}

import type { GlyfDef } from "../schemas/glyfdef.js";
import type { KV } from "./store.js";
import type { GlyfLibrary } from "./userglyfs.js";

/**
 * The Skills browser (Acti's community hub, Glyf's way): one list that mixes
 * the glyfs Glyf ships with what people publish, browsable by category, plus
 * the creators behind them.
 *
 * Every number here is real — install counts come from actual installs, and
 * creators appear only once someone has published. Nothing is seeded.
 */

export const CATEGORIES = ["Writing", "Social", "Language", "Lookups", "Markets", "Community"] as const;
export type SkillCategory = (typeof CATEGORIES)[number];

/** Category from what a glyf is, not a stored field — so builder glyfs and
 *  hub installs sort themselves without asking their authors. */
export function categoryOf(id: string, name: string): SkillCategory {
  const i = id.toLowerCase();
  const n = name.toLowerCase();
  if (/^desi\.|^glyf\.translate/.test(i) || /translat|hindi|hinglish|tamil|spanish|language/.test(n)) return "Language";
  if (/^keyless\.(quote|stock)/.test(i) || /crypto|coin|token|stock|price|market|portfolio/.test(n)) return "Markets";
  if (/^social\./.test(i) || /reply|tweet|post|caption|hook|emotion|dm|rizz/.test(n)) return "Social";
  if (/^keyless\./.test(i) || /weather|define|wiki|lookup|convert|time in/.test(n)) return "Lookups";
  if (/^rewrite\.|^glyf\.(proofread|summarize)/.test(i) ||
      /rewrite|tone|proofread|polish|tighten|summar|formal|expand|grammar/.test(n)) return "Writing";
  return "Community";
}

export interface SkillRow {
  id: string;
  name: string;
  icon: string;
  category: SkillCategory;
  author: string;
  official: boolean;
  installs: number;
  discloses: string[];
  version: number;
}

const OFFICIAL_INSTALLS = "skill-installs";

/** Shipped glyfs that make sense as a key: not the free-form prompt, not
 *  dictation (that runs from the mic). */
function listable(def: GlyfDef): boolean {
  return def.id !== "custom.prompt" && !def.id.startsWith("dictation.");
}

export function skillsList(registry: Map<string, GlyfDef>, library: GlyfLibrary, kv: KV): SkillRow[] {
  const official: SkillRow[] = [...registry.values()].filter(listable).map(d => ({
    id: d.id, name: d.name, icon: d.icon, category: categoryOf(d.id, d.name),
    author: "Glyf", official: true,
    installs: kv.get<number>(OFFICIAL_INSTALLS, d.id) ?? 0,
    discloses: d.discloses, version: d.version,
  }));
  const community: SkillRow[] = library.hubList().map(h => ({
    id: h.id, name: h.name, icon: h.icon, category: categoryOf(h.id, h.name),
    author: h.ownerName, official: false, installs: h.installs,
    discloses: h.discloses, version: h.version,
  }));
  // Most-installed first; ties keep category order (writing is what most
  // people reach for), then the registry's own order.
  const rank = (c: SkillCategory) => CATEGORIES.indexOf(c);
  return [...official, ...community]
    .sort((a, b) => b.installs - a.installs || rank(a.category) - rank(b.category));
}

export interface Creator { name: string; skills: number; installs: number }

export function creators(library: GlyfLibrary): Creator[] {
  const byOwner = new Map<string, Creator>();
  for (const h of library.hubList()) {
    const c = byOwner.get(h.ownerId) ?? { name: h.ownerName, skills: 0, installs: 0 };
    c.skills += 1;
    c.installs += h.installs;
    byOwner.set(h.ownerId, c);
  }
  return [...byOwner.values()].sort((a, b) => b.installs - a.installs || b.skills - a.skills);
}

/** Counts a shipped glyf being added to someone's keyboard — once per
 *  device, so the number means people, not taps. */
export function recordOfficialInstall(kv: KV, deviceId: string, id: string): number {
  const n = kv.get<number>(OFFICIAL_INSTALLS, id) ?? 0;
  const key = `${deviceId}:${id}`;
  if (kv.get<boolean>(`${OFFICIAL_INSTALLS}-by`, key)) return n;
  kv.put(`${OFFICIAL_INSTALLS}-by`, key, true);
  kv.put(OFFICIAL_INSTALLS, id, n + 1);
  return n + 1;
}

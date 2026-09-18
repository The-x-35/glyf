import { describe, expect, it } from "vitest";
import { signedInApp } from "./helpers.js";
import { loadRegistry } from "../src/lib/glyfengine.js";
import { categoryOf, creators, recordOfficialInstall, skillsList } from "../src/lib/skills.js";
import { MemoryKV } from "../src/lib/store.js";
import { GlyfLibrary } from "../src/lib/userglyfs.js";

const userDef = (name: string) => ({
  id: "user.draft", version: 1, name, icon: "sparkles", input: "field",
  requires: { fullAccess: true, connectors: [], wallet: false },
  discloses: ["the text in your current field"],
  vars: {},
  steps: [{ id: "s1", type: "format", template: "{{input}}!!!", out: "final" }],
  output: { mode: "preview", from: "final" },
});

function publish(lib: GlyfLibrary, device: string, name: string): string {
  const saved = lib.save(device, userDef(name));
  if (!("id" in saved)) throw new Error(saved.error);
  expect(lib.publish(device, saved.id)).toBeNull();
  return saved.id;
}

describe("skills categories", () => {
  it("sorts shipped glyfs by what they do", () => {
    expect(categoryOf("rewrite.polite", "Polite")).toBe("Writing");
    expect(categoryOf("glyf.proofread", "Proofread")).toBe("Writing");
    expect(categoryOf("social.xreply", "X reply")).toBe("Social");
    expect(categoryOf("desi.hinglish", "Hinglish")).toBe("Language");
    expect(categoryOf("glyf.translate", "Translate")).toBe("Language");
    expect(categoryOf("keyless.stock", "Stock")).toBe("Markets");
    expect(categoryOf("keyless.weather", "Weather")).toBe("Lookups");
  });

  it("sorts community glyfs by name, and falls back to Community", () => {
    expect(categoryOf("user.1a2b3c4d", "Crypto price")).toBe("Markets");
    expect(categoryOf("user.1a2b3c4d", "Pirate voice")).toBe("Community");
  });
});

describe("skills list", () => {
  const registry = loadRegistry();

  it("mixes shipped and community skills with real, per-device install counts", () => {
    const kv = new MemoryKV();
    const lib = new GlyfLibrary(kv);
    const id = publish(lib, "device-aaaaaaaa", "Pirate voice");

    let rows = skillsList(registry, lib, kv);
    const official = rows.filter(r => r.official);
    expect(official.length).toBeGreaterThan(5);
    expect(official.every(r => r.author === "Glyf" && r.installs === 0)).toBe(true);
    // The free-form prompt and dictation aren't keys you add.
    expect(rows.some(r => r.id === "custom.prompt" || r.id.startsWith("dictation."))).toBe(false);
    expect(rows.find(r => r.id === id)).toMatchObject({ official: false, author: "anonymous", installs: 0 });

    expect(recordOfficialInstall(kv, "device-bbbbbbbb", "rewrite.polite")).toBe(1);
    expect(recordOfficialInstall(kv, "device-bbbbbbbb", "rewrite.polite")).toBe(1);
    expect(recordOfficialInstall(kv, "device-cccccccc", "rewrite.polite")).toBe(2);
    lib.install("device-bbbbbbbb", id);
    lib.install("device-bbbbbbbb", id);

    rows = skillsList(registry, lib, kv);
    expect(rows[0]).toMatchObject({ id: "rewrite.polite", installs: 2 });
    expect(rows.find(r => r.id === id)?.installs).toBe(1);
  });

  it("lists creators only once they've published, never their device id", () => {
    const kv = new MemoryKV();
    const lib = new GlyfLibrary(kv);
    expect(creators(lib)).toEqual([]);

    lib.setDisplayName("device-aaaaaaaa", "Maya");
    const a = publish(lib, "device-aaaaaaaa", "Pirate voice");
    publish(lib, "device-aaaaaaaa", "Haiku it");
    publish(lib, "device-dddddddd", "Rizz reply");
    lib.install("device-bbbbbbbb", a);

    const list = creators(lib);
    expect(list).toEqual([
      { name: "Maya", skills: 2, installs: 1 },
      { name: "anonymous", skills: 1, installs: 0 },
    ]);
    expect(JSON.stringify(list)).not.toContain("device-");
  });
});

describe("skills routes", () => {
  it("filters by category and search, gets shipped and community skills", async () => {
    const app = signedInApp();
    const all = await app.inject({ method: "GET", url: "/skills" });
    expect(all.statusCode).toBe(200);
    const body = all.json();
    expect(body.categories).toContain("Writing");
    expect(body.skills.length).toBeGreaterThan(5);

    const social = (await app.inject({ method: "GET", url: "/skills?category=Social" })).json();
    expect(social.skills.length).toBeGreaterThan(0);
    expect(social.skills.every((s: { category: string }) => s.category === "Social")).toBe(true);

    const found = (await app.inject({ method: "GET", url: "/skills?q=POLITE" })).json();
    expect(found.skills.map((s: { id: string }) => s.id)).toContain("rewrite.polite");

    const got = await app.inject({
      method: "POST", url: "/skills/get",
      payload: { glyfId: "rewrite.polite", deviceId: "skills-dev-000001" },
    });
    expect(got.statusCode).toBe(200);
    expect(got.json()).toMatchObject({ ok: true, official: true, installs: 1 });

    const missing = await app.inject({
      method: "POST", url: "/skills/get",
      payload: { glyfId: "user.nope0000", deviceId: "skills-dev-000001" },
    });
    expect(missing.statusCode).toBe(404);

    const creatorsRes = await app.inject({ method: "GET", url: "/skills/creators" });
    expect(creatorsRes.statusCode).toBe(200);
    expect(Array.isArray(creatorsRes.json().creators)).toBe(true);
  });

  it("keeps publisher device ids out of the public hub list", async () => {
    const app = signedInApp();
    const def = userDef("Shout");
    const save = await app.inject({ method: "POST", url: "/glyfs", payload: { deviceId: "owner-dev-0000001", def } });
    const id = save.json().id;
    await app.inject({ method: "POST", url: "/hub/publish", payload: { glyfId: id, deviceId: "owner-dev-0000001" } });

    const list = await app.inject({ method: "GET", url: "/hub/list" });
    expect(list.json().glyfs.some((g: { id: string }) => g.id === id)).toBe(true);
    expect(list.body).not.toContain("owner-dev-0000001");
  });
});

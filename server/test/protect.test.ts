import { describe, expect, it } from "vitest";
import { buildApp } from "../src/index.js";
import { isOpen } from "../src/lib/protect.js";
import { issueSession } from "../src/lib/identity.js";
import { signedInApp, testToken } from "./helpers.js";

describe("who may call this server", () => {
  it("keeps open only what cannot carry a session", () => {
    expect(isOpen("/health")).toBe(true);
    expect(isOpen("/auth/session")).toBe(true);
    expect(isOpen("/auth/config")).toBe(true);
    expect(isOpen("/p/abc123")).toBe(true);
    expect(isOpen("/waitlist")).toBe(true);
    expect(isOpen("/oauth/google/callback?code=x")).toBe(true);
    for (const path of ["/act", "/glyf/run", "/suggest", "/translate", "/vocab/generate",
      "/builder/generate", "/search/web", "/tools/run", "/me", "/meter/dev", "/glyfs",
      "/telemetry", "/hub/skills"]) {
      expect(isOpen(path), path).toBe(false);
    }
  });

  it("turns away a caller with no session", async () => {
    const app = buildApp();
    for (const url of ["/act", "/glyf/catalog", "/search/web?q=x", "/meter/dev-1"]) {
      const res = await app.inject({ method: "GET", url });
      expect([401, 404]).toContain(res.statusCode);
      if (res.statusCode === 401) expect(res.json().error).toContain("Sign in");
    }
  });

  it("turns away a made-up or tampered session", async () => {
    const app = buildApp();
    const real = testToken();
    const tampered = `${real.slice(0, -4)}aaaa`;
    for (const token of ["not-a-token", tampered, ""]) {
      const res = await app.inject({
        method: "POST", url: "/act",
        headers: token ? { authorization: `Bearer ${token}` } : {},
        payload: { text: "2+2", deviceId: "guard-dev-1" },
      });
      expect(res.statusCode).toBe(401);
    }
  });

  it("turns away a session signed with the wrong secret", async () => {
    const app = buildApp();
    const forged = issueSession("google:someone", { secret: "not-our-secret-not-our-secret" });
    const res = await app.inject({
      method: "POST", url: "/act",
      headers: { authorization: `Bearer ${forged}` },
      payload: { text: "2+2", deviceId: "guard-dev-2" },
    });
    expect(res.statusCode).toBe(401);
  });

  it("turns away an expired session", async () => {
    const app = buildApp();
    const old = issueSession("google:someone", { now: Date.now() - 400 * 86400_000, days: 1 });
    const res = await app.inject({
      method: "POST", url: "/act",
      headers: { authorization: `Bearer ${old}` },
      payload: { text: "2+2", deviceId: "guard-dev-3" },
    });
    expect(res.statusCode).toBe(401);
  });

  it("lets a signed-in phone through", async () => {
    const app = signedInApp();
    const res = await app.inject({ method: "GET", url: "/glyf/catalog" });
    expect(res.statusCode).toBe(200);
  });

  it("still answers health and the sign-in config to anyone", async () => {
    const app = buildApp();
    expect((await app.inject({ method: "GET", url: "/health" })).statusCode).toBe(200);
    expect((await app.inject({ method: "GET", url: "/auth/config" })).statusCode).toBe(200);
  });

  it("holds one address to a rate whoever it claims to be", async () => {
    const app = buildApp();
    let refused = 0;
    for (let i = 0; i < 80; i++) {
      const res = await app.inject({
        method: "GET", url: "/health",
        headers: { "x-forwarded-for": "203.0.113.9" },
      });
      if (res.statusCode === 429) refused++;
    }
    expect(refused).toBeGreaterThan(0);
  });
});

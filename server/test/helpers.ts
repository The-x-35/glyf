import { buildApp } from "../src/index.js";
import { issueSession } from "../src/lib/identity.js";
import type { KV } from "../src/lib/store.js";

/** The person the tests are signed in as. */
export const TEST_USER = "google:test-user-0001";

export function testToken(user = TEST_USER): string {
  const token = issueSession(user);
  if (!token) throw new Error("tests need SESSION_SECRET (server/.env)");
  return token;
}

/**
 * The app as a signed-in phone sees it. Every route needs a session now, so
 * a test that is about what a route DOES shouldn't have to say so each time;
 * the ones about the lock itself use buildApp directly.
 */
export function signedInApp(kv?: KV) {
  const app = kv ? buildApp(kv) : buildApp();
  const inject = app.inject.bind(app);
  const token = testToken();
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  (app as any).inject = (opts: any) => {
    if (typeof opts === "string") return inject(opts);
    return inject({
      ...opts,
      headers: { authorization: `Bearer ${token}`, ...(opts?.headers ?? {}) },
    });
  };
  return app;
}

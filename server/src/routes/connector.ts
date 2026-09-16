import type { FastifyInstance } from "fastify";
import { randomUUID, createHash } from "node:crypto";
import { env } from "../env.js";
import { KV } from "../lib/store.js";

/** §6.11 OAuth broker + §6.12 ConnectorSurface data.
 *
 *  ONE generic code-flow broker for every provider a keyboard plausibly
 *  wants (Notion, Slack, GitHub, Linear, Todoist, Calendly, Zoom, Spotify),
 *  plus a Google-specific start that lets the USER pick scopes (calendar /
 *  gmail / meet) — Google sign-in doubles as the account. Tokens live HERE
 *  only; devices get opaque summaries (§1.6/§11.5).
 *
 *  Each provider activates the moment <PREFIX>_CLIENT_ID and
 *  <PREFIX>_CLIENT_SECRET land in server/.env. Until then its start route
 *  answers a clean 503 naming the missing var. `mockcal` keeps the surface
 *  testable with zero credentials. */

type Connection = {
  provider: string;
  scopes: string[];
  email?: string;
  access_token: string;
  refresh_token?: string;
  expires_at: number;
  connectedAt: string;
};

type PendingAuth = {
  deviceId: string;
  provider: string;
  scopes: string[];
  verifier: string;
  createdAt: number;
};

/** User-facing Google scope choices → real scopes. */
const GOOGLE_SCOPES: Record<string, string[]> = {
  identity: ["openid", "email", "profile"],
  calendar: ["https://www.googleapis.com/auth/calendar.events"],
  gmail: ["https://www.googleapis.com/auth/gmail.compose"],
  meet: ["https://www.googleapis.com/auth/meetings.space.created"],
  // §6.12 — read-only, and the ONLY thing a Google login adds to the search
  // suite. It grants the user's subscriptions and liked videos; it does NOT
  // grant Search results, Search history or YouTube WATCH history (no such
  // scope exists, and watch history left the Data API years ago).
  youtube: ["https://www.googleapis.com/auth/youtube.readonly"],
};

type ProviderCfg = {
  label: string;
  envPrefix: string;
  authorizeUrl: string;
  tokenUrl: string;
  scope?: string;
  scopeParam?: string;          // slack wants user_scope
  authStyle: "basic" | "body";  // client creds in header vs body
  extraAuth?: Record<string, string>;
  tokenAccept?: string;         // github needs Accept: application/json
};

export const PROVIDERS: Record<string, ProviderCfg> = {
  notion: {
    label: "Notion", envPrefix: "NOTION",
    authorizeUrl: "https://api.notion.com/v1/oauth/authorize",
    tokenUrl: "https://api.notion.com/v1/oauth/token",
    authStyle: "basic",
    extraAuth: { owner: "user" },
  },
  slack: {
    label: "Slack", envPrefix: "SLACK",
    authorizeUrl: "https://slack.com/oauth/v2/authorize",
    tokenUrl: "https://slack.com/api/oauth.v2.access",
    scope: "channels:read,chat:write,search:read",
    scopeParam: "user_scope",
    authStyle: "body",
  },
  github: {
    label: "GitHub", envPrefix: "GITHUB",
    authorizeUrl: "https://github.com/login/oauth/authorize",
    tokenUrl: "https://github.com/login/oauth/access_token",
    scope: "repo read:user",
    authStyle: "body",
    tokenAccept: "application/json",
  },
  linear: {
    label: "Linear", envPrefix: "LINEAR",
    authorizeUrl: "https://linear.app/oauth/authorize",
    tokenUrl: "https://api.linear.app/oauth/token",
    scope: "read,write",
    authStyle: "body",
  },
  todoist: {
    label: "Todoist", envPrefix: "TODOIST",
    authorizeUrl: "https://todoist.com/oauth/authorize",
    tokenUrl: "https://todoist.com/oauth/access_token",
    scope: "data:read_write",
    authStyle: "body",
  },
  calendly: {
    label: "Calendly", envPrefix: "CALENDLY",
    authorizeUrl: "https://auth.calendly.com/oauth/authorize",
    tokenUrl: "https://auth.calendly.com/oauth/token",
    authStyle: "basic",
  },
  zoom: {
    label: "Zoom", envPrefix: "ZOOM",
    authorizeUrl: "https://zoom.us/oauth/authorize",
    tokenUrl: "https://zoom.us/oauth/token",
    authStyle: "basic",
  },
  spotify: {
    label: "Spotify", envPrefix: "SPOTIFY",
    authorizeUrl: "https://accounts.spotify.com/authorize",
    tokenUrl: "https://accounts.spotify.com/api/token",
    scope: "user-read-currently-playing",
    authStyle: "basic",
  },
};

/** An authorization in flight, held for ten minutes.
 *
 *  This lives in the KV rather than in a module Map because `start` and
 *  `callback` are two separate requests: on a serverless host they can land on
 *  two different instances, and a Map would lose the state between them, so
 *  every sign-in would come back as ok=false. The KV is shared, so it works on
 *  one process and on twenty. */
const PENDING = "oauth_pending";
const PENDING_TTL_MS = 600_000;

export function connKey(deviceId: string, provider: string): string {
  return `${deviceId}:${provider}`;
}

export function connectorRoutes(app: FastifyInstance, kv: KV): void {

  const pending = {
    set(state: string, auth: PendingAuth) {
      for (const { id, value } of kv.list<PendingAuth>(PENDING)) {
        if (Date.now() - value.createdAt > PENDING_TTL_MS) kv.del(PENDING, id);
      }
      kv.put(PENDING, state, auth);
    },
    get(state: string): PendingAuth | undefined {
      const auth = kv.get<PendingAuth>(PENDING, state);
      // Expiry is enforced on read too: pruning is best effort.
      return auth && Date.now() - auth.createdAt <= PENDING_TTL_MS ? auth : undefined;
    },
    delete(state: string) { kv.del(PENDING, state); },
  };

  const clientId = (p: ProviderCfg) => process.env[`${p.envPrefix}_CLIENT_ID`];
  const clientSecret = (p: ProviderCfg) => process.env[`${p.envPrefix}_CLIENT_SECRET`];
  const redirectFor = (provider: string) =>
    process.env[`${provider.toUpperCase()}_REDIRECT_URI`]
      ?? process.env.OAUTH_REDIRECT_BASE?.concat(`/oauth/${provider}/callback`)
      ?? `http://127.0.0.1:${env.port}/oauth/${provider}/callback`;

  app.get<{ Querystring: { deviceId?: string } }>(
    "/connectors/status", async req => {
      const deviceId = req.query.deviceId ?? "";
      const row = (id: string, label: string, envId: string) => {
        const conn = deviceId
          ? kv.get<Connection>("connections", connKey(deviceId, id))
          : undefined;
        return {
          id, label,
          configured: Boolean(process.env[envId]),
          connected: Boolean(conn),
          scopes: conn?.scopes ?? [],
          email: conn?.email,
        };
      };
      return {
        providers: [
          row("google", "Google", "GOOGLE_CLIENT_ID"),
          ...Object.entries(PROVIDERS).map(([id, p]) =>
            row(id, p.label, `${p.envPrefix}_CLIENT_ID`)),
        ],
        mock: { id: "mockcal", label: "Demo Calendar", configured: true, connected: true },
      };
    });

  // ── Google (scope-choosing start; PKCE; id_token email) ────────────────

  app.get<{ Querystring: { deviceId?: string; scopes?: string } }>(
    "/oauth/google/start", async (req, reply) => {
      const id = process.env.GOOGLE_CLIENT_ID;
      if (!id || !process.env.GOOGLE_CLIENT_SECRET) {
        return reply.code(503).send({
          error: "Google sign-in isn't configured yet — set GOOGLE_CLIENT_ID and GOOGLE_CLIENT_SECRET in server/.env",
        });
      }
      const deviceId = req.query.deviceId ?? "";
      if (deviceId.length < 8) return reply.code(400).send({ error: "deviceId required" });
      const chosen = (req.query.scopes ?? "identity")
        .split(",").map(s => s.trim()).filter(s => GOOGLE_SCOPES[s]);
      if (!chosen.includes("identity")) chosen.unshift("identity");

      const state = randomUUID();
      const verifier = randomUUID() + randomUUID();
      const challenge = createHash("sha256").update(verifier).digest("base64url");
      pending.set(state, {
        deviceId, provider: "google", scopes: chosen, verifier, createdAt: Date.now(),
      });

      const url = "https://accounts.google.com/o/oauth2/v2/auth?" + new URLSearchParams({
        client_id: id,
        redirect_uri: redirectFor("google"),
        response_type: "code",
        scope: chosen.flatMap(s => GOOGLE_SCOPES[s]).join(" "),
        access_type: "offline",
        prompt: "consent",
        state,
        code_challenge: challenge,
        code_challenge_method: "S256",
      }).toString();
      return { url };
    });

  app.get<{ Querystring: { code?: string; state?: string; error?: string } }>(
    "/oauth/google/callback", async (req, reply) => {
      const { code, state, error } = req.query;
      const auth = state ? pending.get(state) : undefined;
      if (state) pending.delete(state);
      if (error || !code || !auth) {
        return reply.redirect("glyf://connected?provider=google&ok=false");
      }
      const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
        method: "POST",
        headers: { "content-type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({
          client_id: process.env.GOOGLE_CLIENT_ID!,
          client_secret: process.env.GOOGLE_CLIENT_SECRET!,
          code,
          grant_type: "authorization_code",
          redirect_uri: redirectFor("google"),
          code_verifier: auth.verifier,
        }),
        signal: AbortSignal.timeout(8000),
      });
      if (!tokenRes.ok) {
        req.log.warn({ status: tokenRes.status }, "google_token_exchange_failed");
        return reply.redirect("glyf://connected?provider=google&ok=false");
      }
      const tokens = await tokenRes.json() as {
        access_token: string; refresh_token?: string; expires_in: number; id_token?: string;
      };
      let email: string | undefined;
      if (tokens.id_token) {
        try {
          email = JSON.parse(
            Buffer.from(tokens.id_token.split(".")[1], "base64url").toString()).email;
        } catch { /* display only */ }
      }
      kv.put("connections", connKey(auth.deviceId, "google"), {
        provider: "google",
        scopes: auth.scopes,
        email,
        access_token: tokens.access_token,
        refresh_token: tokens.refresh_token,
        expires_at: Date.now() + tokens.expires_in * 1000,
        connectedAt: new Date().toISOString(),
      } satisfies Connection);
      req.log.info({ scopes: auth.scopes }, "google_connected");
      return reply.redirect("glyf://connected?provider=google&ok=true");
    });

  // ── Every other provider: one generic code flow ────────────────────────

  app.get<{ Params: { provider: string }; Querystring: { deviceId?: string } }>(
    "/oauth/:provider/start", async (req, reply) => {
      const name = req.params.provider;
      const p = PROVIDERS[name];
      if (!p) return reply.code(404).send({ error: "unknown provider" });
      const id = clientId(p);
      if (!id || !clientSecret(p)) {
        return reply.code(503).send({
          error: `${p.label} isn't configured yet — set ${p.envPrefix}_CLIENT_ID and ${p.envPrefix}_CLIENT_SECRET in server/.env`,
        });
      }
      const deviceId = req.query.deviceId ?? "";
      if (deviceId.length < 8) return reply.code(400).send({ error: "deviceId required" });

      const state = randomUUID();
      pending.set(state, {
        deviceId, provider: name, scopes: p.scope ? p.scope.split(/[ ,]+/) : [],
        verifier: "", createdAt: Date.now(),
      });
      const params = new URLSearchParams({
        client_id: id,
        redirect_uri: redirectFor(name),
        response_type: "code",
        state,
        ...(p.scope ? { [p.scopeParam ?? "scope"]: p.scope } : {}),
        ...(p.extraAuth ?? {}),
      });
      return { url: `${p.authorizeUrl}?${params.toString()}` };
    });

  app.get<{ Params: { provider: string };
            Querystring: { code?: string; state?: string; error?: string } }>(
    "/oauth/:provider/callback", async (req, reply) => {
      const name = req.params.provider;
      const p = PROVIDERS[name];
      const { code, state, error } = req.query;
      const auth = state ? pending.get(state) : undefined;
      if (state) pending.delete(state);
      if (!p || error || !code || !auth || auth.provider !== name) {
        return reply.redirect(`glyf://connected?provider=${name}&ok=false`);
      }
      const body = new URLSearchParams({
        grant_type: "authorization_code",
        code,
        redirect_uri: redirectFor(name),
      });
      const headers: Record<string, string> = {
        "content-type": "application/x-www-form-urlencoded",
        ...(p.tokenAccept ? { accept: p.tokenAccept } : {}),
      };
      if (p.authStyle === "basic") {
        headers.authorization = "Basic " + Buffer
          .from(`${clientId(p)}:${clientSecret(p)}`).toString("base64");
      } else {
        body.set("client_id", clientId(p)!);
        body.set("client_secret", clientSecret(p)!);
      }
      const tokenRes = await fetch(p.tokenUrl, {
        method: "POST", headers, body, signal: AbortSignal.timeout(8000),
      });
      if (!tokenRes.ok) {
        req.log.warn({ provider: name, status: tokenRes.status }, "token_exchange_failed");
        return reply.redirect(`glyf://connected?provider=${name}&ok=false`);
      }
      const json = await tokenRes.json() as Record<string, unknown> & {
        access_token?: string; refresh_token?: string; expires_in?: number;
        authed_user?: { access_token?: string };
        workspace_name?: string; owner?: { user?: { person?: { email?: string } } };
      };
      // Slack user tokens ride in authed_user; everyone else is top-level.
      const accessToken = json.authed_user?.access_token ?? json.access_token;
      if (!accessToken) {
        return reply.redirect(`glyf://connected?provider=${name}&ok=false`);
      }
      kv.put("connections", connKey(auth.deviceId, name), {
        provider: name,
        scopes: auth.scopes,
        email: json.owner?.user?.person?.email
          ?? (typeof json.workspace_name === "string" ? json.workspace_name : undefined),
        access_token: accessToken,
        refresh_token: json.refresh_token,
        expires_at: Date.now() + (json.expires_in ?? 31536000) * 1000,
        connectedAt: new Date().toISOString(),
      } satisfies Connection);
      req.log.info({ provider: name }, "provider_connected");
      return reply.redirect(`glyf://connected?provider=${name}&ok=true`);
    });

  app.post<{ Body: { deviceId?: string; provider?: string } }>(
    "/connectors/disconnect", async (req, reply) => {
      const { deviceId, provider } = req.body ?? {};
      if (!deviceId || !provider) return reply.code(400).send({ error: "Bad request" });
      kv.del("connections", connKey(deviceId, provider));
      return { ok: true };
    });

  // ── §6.12 demo calendar (no credentials needed) ────────────────────────

  const MOCK_EVENTS = [
    { title: "Standup", start: "09:30", end: "09:45", link: "https://meet.tryglyf.com/standup" },
    { title: "Design review — keyboard", start: "11:00", end: "11:45", link: "https://meet.tryglyf.com/design" },
    { title: "Lunch w/ Priya", start: "13:00", end: "14:00", link: "https://maps.tryglyf.com/lunch" },
    { title: "Investor sync", start: "16:00", end: "16:30", link: "https://meet.tryglyf.com/investors" },
    { title: "Gym", start: "19:00", end: "20:00", link: "" },
  ];

  app.get<{ Querystring: { q?: string } }>("/connector/mockcal/events", async req => {
    const q = (req.query.q ?? "").toLowerCase();
    const events = q
      ? MOCK_EVENTS.filter(e => e.title.toLowerCase().includes(q)) : MOCK_EVENTS;
    return { day: env.mockAI ? "MOCK today" : new Date().toDateString(), events };
  });

  /** Month view for the ConnectorSurface calendar: which days carry events.
   *  Deterministic demo pattern (weekday mornings + a few one-offs). */
  app.get<{ Querystring: { year?: string; month?: string } }>(
    "/connector/mockcal/month", async req => {
      const now = new Date();
      const year = Number(req.query.year ?? now.getFullYear());
      const month = Number(req.query.month ?? now.getMonth() + 1); // 1-based
      const daysInMonth = new Date(year, month, 0).getDate();
      const days = [];
      for (let d = 1; d <= daysInMonth; d++) {
        const weekday = new Date(year, month - 1, d).getDay();
        let count = weekday === 0 || weekday === 6 ? 0 : 2;   // workdays
        if (d % 7 === 3) count += 2;                          // busy spikes
        if (weekday === 6 && d % 2 === 0) count = 1;          // some saturdays
        days.push({ day: d, events: count });
      }
      return {
        year, month, daysInMonth,
        firstWeekday: new Date(year, month - 1, 1).getDay(), // 0 = Sunday
        today: year === now.getFullYear() && month === now.getMonth() + 1
          ? now.getDate() : 0,
        days,
      };
    });
}

# Glyf Backend (`server/`)

The complete reference for the Glyf backend: what exists, how it works, every decision and why, what was tried and rejected, current status, and what is still pending.

- Last written: 2026-09-16. All dates and times are India Standard Time (IST).
- Written from: the code in `server/`, `shared/contracts/`, `ci/`, `SPEC.md`, `README.md`, the gate docs in `docs/`, the assistant's working notes, and the exported chat history in `docs/history/`.
- "Verified" in this doc means checked against the code while writing. Nothing was run while writing it (no server start, no tests). Where a fact comes only from chat history or notes, the text says so.
- `server/.env` was deliberately not opened. This doc never contains secret values, only variable names.

---

## Contents

1. [At a glance](#1-at-a-glance)
2. [Running it locally](#2-running-it-locally)
3. [Architecture](#3-architecture)
4. [Endpoint reference](#4-endpoint-reference)
5. [AI layer](#5-ai-layer)
6. [Search suite](#6-search-suite)
7. [Keyless tool registry](#7-keyless-tool-registry)
8. [Connectors and the OAuth broker](#8-connectors-and-the-oauth-broker)
9. [Wallet and crypto (M8)](#9-wallet-and-crypto-m8)
10. [Security rules and safeguards](#10-security-rules-and-safeguards)
11. [Environment variables](#11-environment-variables)
12. [Tests](#12-tests)
13. [Deployment](#13-deployment)
14. [Extending the backend](#14-extending-the-backend)
15. [Decision log](#15-decision-log)
16. [Known issues](#16-known-issues)
17. [Pending work and what Arpit needs to provide](#17-pending-work-and-what-arpit-needs-to-provide)
18. [Relationship to the website](#18-relationship-to-the-website)
19. [Sources](#19-sources)

---

## 1. At a glance

Glyf is an AI keyboard for iPhone and Android. The keyboards (native Swift on iOS, native Kotlin on Android) and the Flutter container app call this backend for everything that needs a network, a model, or a secret: AI runs, the hold-space "act" feature, the Google/YouTube/Maps search suite, keyless API tools, OAuth connectors, the Skills hub, telemetry and metering.

| Item | Value |
|---|---|
| Stack | Node 20+, Fastify 5, TypeScript 5 (ESM, `NodeNext`), zod 3, dotenv |
| Runner | `tsx` (runs TypeScript directly, no build step needed) |
| Tests | vitest 2, 8 files, 90 test cases (static count) |
| Entry point | `server/src/index.ts` (`buildApp()` registers all routes) |
| Port | `8787` by default (`PORT`), listens on `0.0.0.0` |
| Storage | JSON files in `server/data/` behind a `KV` interface. Postgres was planned but is not built |
| AI | Any OpenAI-compatible chat API: OpenRouter, Gemini, Groq, Mistral, Inception, Cerebras, chosen by an ordered fallback chain |
| Mock mode | `MOCK_AI=true` makes every model, search and tool call deterministic and offline |
| Public origin (planned) | `https://api.tryglyf.com` |
| Deployed? | **No.** As of the last notes (2026-09-16) the server only runs on Arpit's Mac. Release builds of the apps already point at `https://api.tryglyf.com`, so TestFlight users get no AI until it is deployed |
| Repo | Private monorepo `https://github.com/The-x-35/glyf` (first push 2026-09-16). `server/.env` and `server/data/` are not committed |
| Package version | `glyf-server` 0.2.0 (`server/package.json`) |

The website (`site/`, tryglyf.com on Vercel) does **not** use this server. Its waitlist writes to Neon Postgres directly. See [section 18](#18-relationship-to-the-website).

---

## 2. Running it locally

### Commands

All commands run from `server/`. Scripts come from `server/package.json`.

| Command | What it does |
|---|---|
| `npm install` | Install dependencies (first time only) |
| `npm run dev` | `tsx watch src/index.ts`. Starts the server and restarts on file changes |
| `npm start` | `tsx src/index.ts`. Starts the server once, no watch |
| `npm test` | `vitest run`. Runs all 8 test files once |
| `npm run typecheck` | `tsc --noEmit` |
| `npm run build` | `tsc -p tsconfig.json` into `server/dist/`. See [known issue 9](#16-known-issues): the build does not copy the registry JSON |

Environment setup:

1. Copy `server/.env.example` to `server/.env` (both paths are covered by the root `.gitignore` rule `.env`, `.env.*`, `!.env.example`).
2. For offline work keep `MOCK_AI=true`. No keys are needed.
3. For live AI set `MOCK_AI=false` and at least one model key (`GEMINI_API_KEY`, `GROQ_API_KEY` or `OPENROUTER_API_KEY`). Startup throws if live mode has no model key (`assertServerSecrets()` in `server/src/env.ts`).
4. Remove or comment out `OAUTH_REDIRECT_BASE` for local work. The example file sets it to the production URL, which would send OAuth callbacks to production (see [known issue 14](#16-known-issues)).

`.env` is loaded by `dotenv` from `server/.env` (path resolved relative to `src/`). dotenv does not override variables already set in the shell, so `MOCK_AI=true npm start` forces mock mode even when `.env` says `false`.

Health check: `curl http://127.0.0.1:8787/health` returns `{ ok, mockAI, fastModels, hasOpenRouterKey }`.

### How clients reach a local server

| Client | Debug build backend | Release build backend | Where it is set |
|---|---|---|---|
| iOS keyboard extension | `http://127.0.0.1:8787` | `https://api.tryglyf.com` | `GlyfSettings.defaultBackendURL` / `productionBackend` in `app/ios/GlyfKeyboard/Engine/SettingsStore.swift` |
| Flutter app | `http://127.0.0.1:8787` (fallback when shared settings have no URL) | `https://api.tryglyf.com` | `app/lib/core/glyf_api.dart` |
| Android app and IME | `http://10.0.2.2:8787` (the emulator's alias for the Mac) | `https://api.tryglyf.com` | `PRODUCTION_BACKEND` in `app/android/app/src/main/kotlin/com/demo/glyf/store/Stores.kt` |

The backend URL is persisted in shared settings (`backendURL`). Both native stores "productionize" it on load:

- A release build rewrites any stored dev URL (`127.0.0.1`, `localhost`, `10.0.2.2`, `0.0.0.0`) to production, so a shipped build can never point at a laptop.
- An iOS debug build rewrites a stored production URL back to the dev URL. This was added on 2026-09-14 after the simulator kept a persisted production URL and every search failed with a TLS error, because `api.tryglyf.com` does not exist yet. The same investigation found that Swift `#if DEBUG` was dead in the keyboard target (it needs `SWIFT_ACTIVE_COMPILATION_CONDITIONS`), so debug keyboards had been silently calling production.

A physical phone cannot reach `127.0.0.1` on the Mac. Until the server is deployed, device testing of AI features needs the stored `backendURL` changed to the Mac's LAN address or a tunnel. This was never set up in the notes.

### Working habits recorded in the history

- **Restart after adding routes.** A server process started before new routes were added answers `/health` fine but returns 404 for the new routes (SPIKES finding 23, 2026-09-12).
- **UI test suites need mock mode.** The iOS UI gate suites expect `MOCK_AI=true npm start` on `127.0.0.1:8787`. Restart in live mode afterwards. On 2026-09-14 the mock server was left running and Arpit saw fixture results in the keyboard ("you have hard coded results in ios"). Mock fixtures must never reach a user-facing run.
- **Resetting QA data.** Hub and skills testing writes real rows to `server/data/`. To reset, stop the server first (FileKV caches collections in memory and rewrites the whole file on the next write), then clear `accounts.json`, `installs.json`, `skill-installs.json` and `skill-installs-by.json`.
- A local preview launch configuration named `glyf-server` runs `npm run start` in `server/` on port 8787.

---

## 3. Architecture

### File map

```
server/
├── package.json, package-lock.json, tsconfig.json
├── .env.example            documented variable names (no values)
├── .gitignore              ignores data/
├── data/                   FileKV JSON collections (dev storage, not committed)
├── src/
│   ├── index.ts            buildApp(): creates KV, meter, library; registers every route module
│   ├── env.ts              loads server/.env; typed env object; assertServerSecrets()
│   ├── providers/
│   │   └── openrouter.ts   model router: provider prefixes, request options, SSE streaming,
│   │                       rate-limit cooldown, classifier-verdict gate, mock stream
│   ├── routes/
│   │   ├── health.ts       GET /health
│   │   ├── meter.ts        GET /meter/:deviceId
│   │   ├── glyf.ts         GET /glyf/catalog, POST /glyf/run (SSE)
│   │   ├── act.ts          POST /act, GET /p/:id
│   │   ├── vocab.ts        POST /vocab/generate
│   │   ├── builder.ts      POST /builder/generate, /builder/test; POST/GET/DELETE /glyfs
│   │   ├── hub.ts          /skills, /skills/creators, /skills/get, /hub/*, /account/*
│   │   ├── search.ts       POST /search; GET /search/suggest, /search/photo, /search/staticmap, /search/status
│   │   ├── tools.ts        POST /tools/run
│   │   ├── connector.ts    OAuth broker, /connectors/*, mock calendar
│   │   ├── gif.ts          GET /gif/search (GIPHY proxy)
│   │   ├── telemetry.ts    POST /telemetry, GET /telemetry/funnel
│   │   └── waitlist.ts     POST /waitlist, GET /waitlist/count (legacy)
│   ├── lib/
│   │   ├── glyfengine.ts   registry loader + step engine (llm, format, if, map, tool, ask)
│   │   ├── userglyfs.ts    GlyfLibrary: user glyfs, hub, installs, moderation
│   │   ├── skills.ts       Skills list, derived categories, creators, official install counts
│   │   ├── tools.ts        tool registry loader, per-tool rate limit, all tool executors, mock outputs
│   │   ├── act.ts          hold-space intent planner and executor
│   │   ├── pages.ts        live mini-app pages (create, get, render HTML)
│   │   ├── search.ts       search engine: web, YouTube, maps provider chains; nearby; provider status
│   │   ├── answers.ts      instant answers: math, sunset, time, weather, currency, Wikipedia
│   │   ├── sun.ts          sunrise, sunset, golden hour (NOAA equation), clock formatting
│   │   ├── suggest.ts      landing state: trending searches, popular or liked videos, nearby places
│   │   ├── searchcards.ts  card contract shared with Swift and Kotlin; composeInsert()
│   │   ├── vocab.ts        AI vocabulary pack generation and cleaning
│   │   ├── meter.ts        plans, planCap(), in-memory daily meter
│   │   ├── cache.ts        TTLCache (sha256 keys, TTL, max entries)
│   │   └── store.ts        KV interface, FileKV, MemoryKV, defaultKV()
│   ├── registry/
│   │   ├── glyfs/*.json    23 shipped glyf definitions
│   │   └── tools/*.json    30 tool definitions
│   └── schemas/
│       ├── glyfdef.ts      zod schema for glyf definitions and run requests
│       └── contracts.generated.ts  zod Intent/Result, generated from shared/contracts (not imported yet)
└── test/                   8 vitest files (see section 12)
```

### Request flow

```mermaid
flowchart LR
  KB["iOS keyboard / Android IME"] -->|"POST /glyf/run (SSE)"| RUN["glyf.ts"]
  KB -->|"POST /act"| ACT["act.ts"]
  KB -->|"POST /search, GET /search/suggest"| SR["search.ts"]
  APP["Flutter app"] -->|"builder, skills, hub, oauth, telemetry, vocab"| OTHER["route modules"]
  RUN --> ENG["glyfengine.ts"]
  ENG --> MR["providers/openrouter.ts"]
  ENG --> TOOLS["lib/tools.ts"]
  ACT --> MR
  ACT --> SEARCH["lib/search.ts"]
  SR --> SEARCH
  SEARCH --> ANS["lib/answers.ts + sun.ts"]
  MR --> LLM["Gemini / Groq / OpenRouter / ..."]
  TOOLS --> APIS["free public APIs, Google Calendar, Notion"]
  SEARCH --> PROV["Brave, Serper, YouTube, Places, Geoapify, OSM"]
  OTHER --> KV["KV: server/data/*.json"]
  RUN --> KV
```

### Identity: the device id

There are no user accounts yet. Every client generates a random lowercase UUID once (`deviceId` in shared settings) and sends it with requests. The server keys everything to it: meter counts, user glyfs, hub ownership, installs, OAuth connections, display names, telemetry days.

Consequences:

- The device id works as a bearer credential. Anyone who knows it can list that device's glyfs, publish or delete them, or disconnect its connectors. The hub list strips owner ids for this reason (fixed 2026-09-15).
- Data survives app updates because the settings file survives updates (verified experimentally on 2026-09-13). An uninstall or a bundle id change creates a new device id and orphans server-side data.
- Accounts are planned: Arpit decided on 2026-09-15 that the app will get a sign-up step backed by the same Neon database as the waitlist, with Google permissions requested only when a feature needs them. Nothing of this exists in the server yet.

### Storage (`server/src/lib/store.ts`)

`KV` is a four-method interface (`get`, `put`, `del`, `list`) over named collections.

- `FileKV` (default): each collection is one JSON file in `server/data/`. Loaded lazily into memory, the whole file is rewritten synchronously on every `put` or `del`. A corrupt file starts empty in memory and the original stays on disk until the next write overwrites it.
- `MemoryKV`: used when `NODE_ENV=test` (vitest sets this by default).
- The code comment says a Postgres driver will drop in behind the same interface for deploy (SPEC §2 pins Postgres in production). It has not been written.

Collections:

| Collection | Key | Value | Written by |
|---|---|---|---|
| `userglyfs` | glyf id (`user.<8 hex>`) | `{ def, ownerId, createdAt, updatedAt, published }` | `POST /glyfs`, publish |
| `hub` | glyf id | `{ def, ownerId, ownerName, installs, publishedAt }` | `POST /hub/publish`, installs |
| `installs` | `<deviceId>:<glyfId>` | `{ version, discloses, at }` | `/hub/install`, `/skills/get` (community) |
| `accounts` | deviceId | `{ displayName }` | `POST /account/name` |
| `skill-installs` | shipped glyf id | install count (number) | `/skills/get` (official) |
| `skill-installs-by` | `<deviceId>:<glyfId>` | `true` | `/skills/get` (official) |
| `connections` | `<deviceId>:<provider>` | `{ provider, scopes, email, access_token, refresh_token, expires_at, connectedAt }` | OAuth callbacks |
| `pages` | 12-char random id | `{ title, places, createdAt }` | `POST /act` (places intent) |
| `telemetry` | `<YYYY-MM-DD>:<event>` | `{ count }` | `POST /telemetry` |
| `devices` | deviceId | `{ days: string[] }` (last 60 active days) | `POST /telemetry` |
| `waitlist` | base64url of the email | `{ email, at }` | `POST /waitlist` (legacy) |

At the time of writing, `server/data/` holds dev files for most collections (entry counts only were checked: 29 user glyfs, 22 telemetry counters, 10 devices, 1 waitlist row, the rest empty). There is no `connections.json` or `pages.json`, which is consistent with no OAuth connection ever having been made. OAuth tokens and waitlist emails are personal data: never commit or share these files.

### In-memory state (lost on restart)

| State | Where | Effect of a restart |
|---|---|---|
| Daily run counts | `MemoryMeter` in `lib/meter.ts` | Everyone's free runs reset |
| Run output cache (24 h) | `TTLCache` in `routes/glyf.ts` | Cache cleared |
| Search cache (10 min) and suggest cache (30 min) | `lib/search.ts`, `lib/suggest.ts` | Cache cleared |
| Model cooldowns | `coolingUntil` in `providers/openrouter.ts` | Rate-limited models are retried |
| OAuth pending states (10 min) | `pending` map in `routes/connector.ts` | In-flight sign-ins fail |
| Per-tool request timestamps | `hits` map in `lib/tools.ts` | Tool rate limits reset |
| Nominatim request queue | `nominatimGate` in `lib/search.ts` | Queue reset |

None of this works across multiple server instances. A deployment must run one instance until the meter, pending states and caches move to shared storage.

### Logging and privacy in logs

- Fastify logger at `info`, with `disableRequestLogging: true`, so URLs and query strings (which can carry coordinates) are not logged per request.
- Routes log events and timings only (SPEC §12): glyf id, device id, plan, input length, duration, intent, provider, card count. Never the typed text, the query, the vocabulary description or the model output.
- Bad-request logs record which zod field failed (`issues`), never the body.
- SPEC §8.4 asked for per-call latency and token counts in dev logs. Token counts are not logged.

---

## 4. Endpoint reference

### 4.1 All routes

"Metered" means the request consumes one run from the device's daily cap. "Used by" comes from searching the client source for the path; "none found" means no current caller was found.

| # | Method | Path | Purpose | Metered | File | Used by |
|---|---|---|---|---|---|---|
| 1 | GET | `/health` | Liveness and config presence | No | `routes/health.ts` | Flutter app |
| 2 | GET | `/meter/:deviceId` | Remaining runs today | No | `routes/meter.ts` | iOS keyboard, Flutter app |
| 3 | GET | `/glyf/catalog` | Shipped glyf list | No | `routes/glyf.ts` | Flutter app |
| 4 | POST | `/glyf/run` | Run a glyf, streamed over SSE | Yes | `routes/glyf.ts` | iOS keyboard, Android IME, Flutter app |
| 5 | POST | `/act` | Hold space: act on typed text | Yes | `routes/act.ts` | iOS keyboard, Android IME |
| 6 | GET | `/p/:id` | Live mini-app page (HTML) | No | `routes/act.ts` | Message recipients in a browser |
| 7 | POST | `/vocab/generate` | AI vocabulary pack | Yes | `routes/vocab.ts` | Flutter app |
| 8 | POST | `/builder/generate` | Plain English to glyf definition | **No** | `routes/builder.ts` | Flutter app |
| 9 | POST | `/builder/test` | Test-run an unsaved definition | **No** | `routes/builder.ts` | Flutter app |
| 10 | POST | `/glyfs` | Save a user glyf | No | `routes/builder.ts` | Flutter app |
| 11 | GET | `/glyfs?deviceId=` | List the device's glyfs | No | `routes/builder.ts` | Flutter app |
| 12 | DELETE | `/glyfs/:id?deviceId=` | Delete a user glyf | No | `routes/builder.ts` | Flutter app |
| 13 | GET | `/skills?category=&q=` | Skills browser list | No | `routes/hub.ts` | Flutter app |
| 14 | GET | `/skills/creators` | Creators with real counts | No | `routes/hub.ts` | Flutter app |
| 15 | POST | `/skills/get` | Add a skill (official or community) | No | `routes/hub.ts` | Flutter app |
| 16 | GET | `/hub/list` | Published community glyfs | No | `routes/hub.ts` | None found (superseded by `/skills`) |
| 17 | POST | `/hub/publish` | Publish own glyf | No | `routes/hub.ts` | Flutter app |
| 18 | POST | `/hub/install` | Install a community glyf | No | `routes/hub.ts` | None found (superseded by `/skills/get`) |
| 19 | POST | `/account/name` | Set display name | No | `routes/hub.ts` | Flutter app |
| 20 | GET | `/account/:deviceId/creator` | Creator stats | No | `routes/hub.ts` | Flutter app |
| 21 | POST | `/search` | Typed search cards | No | `routes/search.ts` | iOS keyboard, Android IME |
| 22 | GET | `/search/suggest` | Landing state before typing | No | `routes/search.ts` | iOS keyboard, Android IME |
| 23 | GET | `/search/photo?ref=` | Google Places photo proxy | No | `routes/search.ts` | Card thumbnails (relative URLs; Android prefixes its backend URL, iOS handling not verified) |
| 24 | GET | `/search/staticmap?lat=&lon=` | Geoapify static map proxy | No | `routes/search.ts` | Android IME act map card |
| 25 | GET | `/search/status` | Which search providers are live | No | `routes/search.ts` | None found (diagnostic) |
| 26 | POST | `/tools/run` | Run one keyless tool | No | `routes/tools.ts` | Client methods exist in both keyboards, no current call sites found |
| 27 | GET | `/connectors/status?deviceId=` | Provider configured/connected state | No | `routes/connector.ts` | Flutter app |
| 28 | GET | `/oauth/google/start?deviceId=&scopes=` | Google consent URL | No | `routes/connector.ts` | Flutter app |
| 29 | GET | `/oauth/google/callback` | Google redirect target | No | `routes/connector.ts` | Google |
| 30 | GET | `/oauth/:provider/start?deviceId=` | Consent URL for other providers | No | `routes/connector.ts` | Flutter app |
| 31 | GET | `/oauth/:provider/callback` | Redirect target for other providers | No | `routes/connector.ts` | The provider |
| 32 | POST | `/connectors/disconnect` | Delete a stored connection | No | `routes/connector.ts` | Flutter app |
| 33 | GET | `/connector/mockcal/events?q=` | Demo calendar events | No | `routes/connector.ts` | iOS keyboard ConnectorSurface |
| 34 | GET | `/connector/mockcal/month?year=&month=` | Demo month grid | No | `routes/connector.ts` | iOS keyboard ConnectorSurface |
| 35 | GET | `/gif/search?q=&limit=` | GIPHY search proxy | No | `routes/gif.ts` | None found (no GIF tab yet) |
| 36 | POST | `/telemetry` | Event batch sink | No | `routes/telemetry.ts` | Flutter app |
| 37 | GET | `/telemetry/funnel` | Aggregated counts | No | `routes/telemetry.ts` | None found |
| 38 | POST | `/waitlist` | Legacy waitlist signup | No | `routes/waitlist.ts` | None (the site now uses Neon) |
| 39 | GET | `/waitlist/count` | Legacy waitlist count | No | `routes/waitlist.ts` | None |

No route has real authentication, CORS configuration or a global rate limiter. Fastify's default JSON body limit applies.

### 4.2 Health and meter

**`GET /health`**
- Response: `{ ok: true, mockAI: boolean, fastModels: string[], hasOpenRouterKey: boolean }`.
- Only presence booleans, never secrets (SPEC §1.6). A test asserts no OpenRouter-shaped key appears in the body.
- It reports only the OpenRouter key, not Gemini or Groq keys.

**`GET /meter/:deviceId`**
- Response: `{ remaining: number }`, computed against the free cap (it does not know the device's plan). Capped at 9999.
- Powers the remaining-runs chip.

### 4.3 AI runs

**`GET /glyf/catalog`**
- Response: `{ glyfs: [{ id, name, icon, input, discloses, version }] }` for the 23 shipped definitions. Steps and prompts are not exposed.

**`POST /glyf/run`** (Server-Sent Events)
- Request (`RunRequestSchema` in `schemas/glyfdef.ts`):

  | Field | Type | Rules |
  |---|---|---|
  | `glyfId` | string | required |
  | `input` | string | max 8000, default `""` |
  | `vars` | `Record<string,string>` | default `{}`; clients send `toneHint`, `target`, `tone`, `prompt` |
  | `deviceId` | string | 8 to 64 chars |
  | `plan` | `"free" \| "plus" \| "max"` | default `"free"`, client-asserted |
  | `pro` | boolean | legacy flag, treated as `plus` when `plan` is `free` |

- Response: HTTP 200 with `Content-Type: text/event-stream`, then frames:
  - `event: token` with `{ t: string }`, zero or more times.
  - `event: done` with `{ text, remaining, ms }` (plus `model: "cache"` on a cache hit).
  - `event: error` with `{ message }`.
- Errors always arrive as an `error` frame on an HTTP 200 stream: bad request, unknown glyf, cap reached ("Daily free runs used up" on free; on paid plans a "Daily runs used up" message), tool or `ask` errors (passed through verbatim), and transport failures ("Couldn't reach Glyf. Tap to retry.").
- Resolution order: shipped registry, then the device's own glyfs, then glyfs the device installed from the hub. A user glyf cannot shadow a shipped id.
- The meter is consumed before the cache check, so cache hits still count.
- If the client disconnects mid-stream, the upstream model request is aborted. The abort listens on `reply.raw` "close" while the response is unfinished. Listening on the request's "close" (the first implementation) fired as soon as the body was read and killed every run (fixed 2026-09-12).
- Connected accounts: before running, the route loads the device's unexpired OAuth access tokens so `tool` steps like `calendar.today` can use them. Tokens never leave the server.

**`POST /act`**
- Request: `{ text (1 to 2000), deviceId (1 to 80), plan, lat?, lon?, country? (2 letters), tz? }`. Location is optional, forwarded from the app's cached fix, and never stored.
- Response (200): `{ ok: true, remaining, intent, title, cards, text?, insert, page?, provider }`.
  - `intent`: `place`, `places`, `answer`, `video` or `rewrite`.
  - `cards`: search-suite cards (see [6.1](#61-shape-and-card-contract)).
  - `insert`: the exact text the keyboard drops into the field.
  - `page`: live mini-app URL for a places list, when publishing is possible.
- Errors: 400 bad request, 429 cap reached, 502 "Couldn't do that right now. Tap to retry."
- How it decides and what it returns: [5.6](#56-act-engine-hold-space).

**`GET /p/:id`**
- Serves a small self-contained HTML page listing the places from an `/act` list result. Light and dark via `prefers-color-scheme`, "Made with glyf" footer.
- Ids must match `^[\w-]{8,24}$`; unknown ids return a 404 HTML page. `Cache-Control: public, max-age=300`.
- Pages are stored forever. There is no expiry or deletion yet.

**`POST /vocab/generate`**
- Request: `{ description (3 to 500), deviceId (1 to 80), plan }`.
- Response: `{ ok: true, remaining, name, words: string[], phrases: string[] }`. Errors: 400, 429, 502 "Couldn't make words right now. Try again."
- The description is never logged. Details: [5.7](#57-vocabulary-packs).

### 4.4 Builder and user glyfs

**`POST /builder/generate`**
- Request: `{ description (4 to 600), deviceId (8 to 64) }`.
- Response: `{ def }`, a runnable definition with id `user.draft`. Errors: 400; 422 when two attempts both fail validation (a message asking to describe the action differently).
- Not metered (see [known issue 4](#16-known-issues)). Details: [5.5](#55-builder).

**`POST /builder/test`**
- Request: `{ def, input (max 4000, default ""), vars, deviceId }`.
- Response: `{ text, ms }`. Errors: 400; 422 for schema failures, moderation refusals, or run errors.
- Runs without connected accounts (no `connections` passed), so OAuth tool steps fail here with a "connect first" error. Not metered.

**`POST /glyfs`**
- Request: `{ deviceId (8 to 64), def }`.
- Response: `{ id }`. A new glyf gets `user.<first 8 hex chars of a UUID>`. Saving an existing id you own bumps `version`. Errors: 400; 422 for invalid schema, moderation refusal, or "That glyf belongs to someone else".

**`GET /glyfs?deviceId=`**
- Response: `{ glyfs: [{ id, name, icon, input, discloses, version, published, updatedAt, def }] }`.

**`DELETE /glyfs/:id?deviceId=`**
- Response: `{ ok: true }` or 404. Deleting also removes the hub entry, so installers can no longer run it.

### 4.5 Skills, hub and accounts

**`GET /skills?category=&q=`**
- Response: `{ categories: string[], skills: SkillRow[] }`. A `SkillRow` is `{ id, name, icon, category, author, official, installs, discloses, version }`.
- One list mixes shipped glyfs (author "Glyf", `official: true`) with published community glyfs. `custom.prompt` and the two `dictation.*` glyfs are not listed (they are not keys you add).
- `category` filters (`All` or missing means all). `q` matches name or author, case-insensitive.
- Categories are derived from the id and name, never stored: Writing, Social, Language, Lookups, Markets, Community. A category with no skills is omitted.
- Sorted by installs descending, ties by category order.
- Every number is real: install counts come from actual installs and each device counts once. Nothing is seeded.

**`GET /skills/creators`**
- Response: `{ creators: [{ name, skills, installs }] }`. A creator appears only after publishing. Device ids are never included.

**`POST /skills/get`**
- Request: `{ glyfId, deviceId (8 to 64) }`.
- Shipped glyf: `{ ok: true, official: true, installs }` (counts once per device; the app binds it by id).
- Community glyf: `{ ok: true, official: false, def }` and an install record. 404 if not on the hub.

**`GET /hub/list`**
- Response: `{ glyfs: [{ id, name, icon, discloses, version, ownerName, installs, publishedAt }] }`. The owner's device id is stripped (it leaked until 2026-09-15).

**`POST /hub/publish`**
- Request: `{ glyfId, deviceId }`. Response `{ ok: true }` or 422 with the refusal ("Not your glyf" or a moderation reason). Moderation re-runs at publish (SPEC §6.9). Private by default; publishing is one call.

**`POST /hub/install`**
- Request: `{ glyfId, deviceId }`. Response `{ def }` or 404. Records `{ version, discloses, at }` for re-consent checks, and counts the install once per device.

**`POST /account/name`**
- Request: `{ deviceId, displayName (1 to 40) }`. Response `{ ok: true }`. The name shows as the creator name on the hub (default "anonymous").

**`GET /account/:deviceId/creator`**
- Response: `{ glyfs, installs }` totals for that device's published glyfs.

### 4.6 Search suite

**`POST /search`**
- Request: `{ vertical: "web" | "yt" | "maps", query (1 to 200), deviceId (1 to 80), lat?, lon?, country? (2 letters, uppercased), tz? }`.
- Response: `{ ok: true, vertical, query, cards: SearchCard[], provider }`. `provider` names the rung that answered (`google`, `brave`, `none`, `youtube-data-api`, `google-places`, `geoapify`, `openstreetmap`, `mock`), so the app can tell a key outage from an empty result.
- Errors: 400 (only zod field names are logged, never the query), 502 with the error message.
- Not metered (no model cost), but it can spend paid provider quota. Details: [section 6](#6-search-suite).

**`GET /search/suggest?vertical=&country=&lat=&lon=&deviceId=`**
- Response: `{ ok: true, vertical, cards, provider }`. Landing rows for a tab before the user types: trending searches (web), the user's liked videos or the popular chart (yt), places around the caller (maps).
- `deviceId` is used only on the YouTube tab, to look up that device's Google token for liked videos.
- Errors: 400 for a bad vertical, 502 on failure.

**`GET /search/photo?ref=places/<id>/photos/<id>`**
- Streams a Google Places photo (max 256x256) so the Places key never reaches a client. Only a Places photo resource name matching `^places\/[\w-]+\/photos\/[\w-]+$` is accepted, never an arbitrary URL.
- 404 without `GOOGLE_PLACES_KEY` or with a bad ref, 502 on upstream failure. `Cache-Control: public, max-age=86400`.

**`GET /search/staticmap?lat=&lon=&w=&h=&dark=`**
- Streams a Geoapify static map centred on the coordinates with a red marker. Only two numbers cross the wire, never a caller URL.
- `w` is clamped to 120 to 800 (default 600), `h` to 80 to 500 (default 240). `dark=1` uses the `dark-matter` style, otherwise `positron`. Zoom 15.5, scale factor 2.
- 404 without `GEOAPIFY_KEY` or with invalid coordinates (the card then keeps its pin). iOS draws its own map with MapKit; Android uses this route.

**`GET /search/status`**
- Response: `{ ok: true, providers: { web, yt, maps } }` without revealing keys.
  - `web`: `brave` if `BRAVE_SEARCH_KEY`, else `google` if `SERPER_API_KEY`, else `answers-only`.
  - `yt`: `youtube-data-api` or `none`.
  - `maps`: `google-places`, `geoapify`, `openstreetmap-dev` (non-production only) or `none`.
- The assistant used this route to confirm keys were live without seeing their values.

### 4.7 Tools

**`POST /tools/run`**
- Request: `{ id (1 to 64), args: Record<string, string (max 300)>, deviceId (1 to 80) }`.
- Response: `{ ok: true, result: string }`. The result is a plain string; the three search tools return a JSON array of `{ title, snippet?, url }` rows encoded as a string.
- Errors: 400; 404 unknown tool; 403 for OAuth tools ("connected tools run through your glyfs", because tokens are only resolved inside `/glyf/run`); 502 with the tool's error (including its rate-limit message).
- Not metered. Each tool's own per-minute limit applies. The tool catalogue is in [section 7](#7-keyless-tool-registry).
- History: this was the first search surface (2026-09-13). Since 2026-09-14 the keyboards use the typed `/search` endpoint instead. The client methods still exist but no call sites were found.

### 4.8 Connectors and OAuth

**`GET /connectors/status?deviceId=`**
- Response: `{ providers: [{ id, label, configured, connected, scopes, email? }], mock: { id: "mockcal", label: "Demo Calendar", configured: true, connected: true } }`.
- Providers in order: google, notion, slack, github, linear, todoist, calendly, zoom, spotify.
- `configured` is true when `<PREFIX>_CLIENT_ID` is set (the secret is not checked). `connected` is true when a connection row exists, even if its token has expired ([known issue 11](#16-known-issues)).

**`GET /oauth/google/start?deviceId=&scopes=identity,calendar,gmail,meet,youtube`**
- Response: `{ url }`, the Google consent URL for the app to open.
- 503 with a message naming `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET` when either is missing; 400 when `deviceId` is shorter than 8 chars.
- Unknown scope names are ignored; `identity` is always added.

**`GET /oauth/google/callback?code=&state=`**
- Exchanges the code (with the PKCE verifier and client secret), stores the tokens, then redirects to `glyf://connected?provider=google&ok=true` (or `ok=false` on any failure).

**`GET /oauth/:provider/start?deviceId=`** and **`GET /oauth/:provider/callback`**
- Same pattern for notion, slack, github, linear, todoist, calendly, zoom and spotify. 404 for an unknown provider, 503 naming `<PREFIX>_CLIENT_ID` and `<PREFIX>_CLIENT_SECRET` when unconfigured. Redirects to `glyf://connected?provider=<name>&ok=true|false`.

**`POST /connectors/disconnect`**
- Request: `{ deviceId, provider }`. Response `{ ok: true }`. Deletes the stored row. It does not revoke the token at the provider.

**`GET /connector/mockcal/events?q=`**
- Response: `{ day, events: [{ title, start, end, link }] }`. Five fixed demo events (Standup, Design review, Lunch, Investor sync, Gym) filtered by `q`. `day` reads "MOCK today" in mock mode, otherwise today's date string.

**`GET /connector/mockcal/month?year=&month=`**
- Response: `{ year, month, daysInMonth, firstWeekday (0 = Sunday), today (0 if another month), days: [{ day, events }] }`. A deterministic pattern: two events on weekdays, spikes on some days, a few Saturdays.
- Both mock routes keep the in-keyboard calendar surface (hold C) testable with zero credentials.

Full broker design: [section 8](#8-connectors-and-the-oauth-broker).

### 4.9 GIF search

**`GET /gif/search?q=&limit=`**
- Response: `{ gifs: [{ id, title, preview, url }] }` from GIPHY search (or trending when `q` is empty). `limit` defaults to 24, max 50. Rating `pg-13`. Query truncated to 80 chars.
- 503 naming `GIPHY_API_KEY` when unset, 502 on provider error.
- Why it exists: keyboards cannot type images. Gboard's pattern is to copy the GIF to the pasteboard for the user to paste. Search goes through the server so the key stays server-side. No keyboard GIF tab has been built (2026-09-12 decision, still waiting on a GIPHY key).

### 4.10 Telemetry

**`POST /telemetry`**
- Request: `{ deviceId (8 to 64), events: [{ event (1 to 64), ts, ...extra }] (max 500) }`.
- Response: `{ ok: true, accepted }`.
- Content guard (SPEC §12): any string field longer than 80 chars is dropped. Only per-day event counts and per-device active days are stored; the extra fields are not persisted at all.
- The device JSONL log on the phone stays the source of truth; the app sends throttled batches.

**`GET /telemetry/funnel`**
- Response: `{ events: { <event>: { <day>: count } }, activeDevices, note }`. D1/D7/D30 retention is noted as waiting for accounts. Public, no auth.

### 4.11 Waitlist (legacy)

**`POST /waitlist`** with `{ email }` and **`GET /waitlist/count`**
- Stores lowercased, deduplicated emails in the `waitlist` collection, capped at 50,000. Returns `{ ok: true, count }`. No throttle.
- Built 2026-09-13 for the first website, which proxied its form here through a `GLYF_API` variable. On 2026-09-15 the site switched to a direct Neon Postgres insert. Nothing calls these routes now; they can be removed.

---

## 5. AI layer

All model access is server-side only (SPEC §1.6 and §8.1). Devices send a glyf id and input; prompts, model choice and provider keys live on the server.

### 5.1 Model router (`server/src/providers/openrouter.ts`)

The file keeps its original name, but since 2026-09-15 it routes to any OpenAI-compatible chat completions API.

**Tiers.** Every model call asks for a tier:

| Tier | Used by | Chain variable | `max_tokens` |
|---|---|---|---|
| `fast` | glyf `llm` steps with `model: "fast"`, act routing and rewrites, answer summaries, vocab packs | `FAST_MODELS` | 1500 |
| `smart` | Builder generation, glyf steps with `model: "smart"` or `"strict"` | `SMART_MODELS` | 4000 |

SPEC §8.3 also names a `strict` tier (JSON validated against a schema, one retry, fail closed). In code `strict` maps to the `smart` chain; the strict behaviour lives in the Builder route, which validates and retries.

**Chains.** `FAST_MODELS` and `SMART_MODELS` are comma-separated lists, most preferred first. Both default to `openrouter/free` (OpenRouter's Free Models Router). SPEC §8.2 forbids relying on one hard-coded `:free` id because free models rotate out without notice.

**Provider prefixes** (`endpointFor()`):

| Model spec | Endpoint | Key variable |
|---|---|---|
| `groq:<model>` | `https://api.groq.com/openai/v1/chat/completions` | `GROQ_API_KEY` |
| `gemini:<model>` | `https://generativelanguage.googleapis.com/v1beta/openai/chat/completions` | `GEMINI_API_KEY` |
| `mistral:<model>` | `https://api.mistral.ai/v1/chat/completions` | `MISTRAL_API_KEY` |
| `inception:<model>` | `https://api.inceptionlabs.ai/v1/chat/completions` | `INCEPTION_API_KEY` |
| `cerebras:<model>` | `https://api.cerebras.ai/v1/chat/completions` | `CEREBRAS_API_KEY` |
| `openrouter:<id>` or any other id (including ids containing `:free`) | `https://openrouter.ai/api/v1/chat/completions` | `OPENROUTER_API_KEY` |

A model whose provider has no key is skipped (recorded as `no-key`) and the chain moves on. OpenRouter requests also send `HTTP-Referer: https://tryglyf.com` and `X-Title: Glyf` (SPEC §8.1).

**Per-model request options** (`requestOptions()`), added 2026-09-15 because reasoning models spend seconds thinking before the first token, which a keyboard cannot afford, and some leak the thinking into the answer:

| Case | Option sent |
|---|---|
| OpenRouter, model id contains `gpt-oss` | `reasoning: { effort: low (fast) or medium (smart), exclude: true }` |
| OpenRouter, any other model | `reasoning: { exclude: true }` |
| Direct provider, `gpt-oss` model | `reasoning_effort: low (fast) or medium (smart)` |
| Groq, Qwen model | `reasoning_effort: "none"` (otherwise Groq returns raw `<think>` text) |
| Gemini, `gemini-2.5-flash` (not Flash-Lite) | `reasoning_effort: none (fast) or low (smart)` |
| Everything else (for example Gemini 2.5 Flash-Lite, Mistral) | only `max_tokens` |

**Walking the chain** (`completeStreaming()`):

1. In mock mode, return the mock stream ([5.2](#52-mock-mode)).
2. Filter the chain to models not cooling down. If every model is cooling down, try them all anyway.
3. For each model: POST with `stream: true`. On a non-OK response record the status (and on HTTP 429 start a cooldown). On success, drain the SSE stream, forwarding `choices[0].delta.content` tokens.
4. Empty text is a failure (`empty`). A classifier verdict is a failure (`classifier`).
5. The first model that returns a real answer wins: `{ text, model }`.
6. If all fail, throw `ModelExhaustedError` listing every attempt, for example `all models failed: a(429), b(no-key)`.
7. If the client aborted, the abort error is rethrown immediately.

**Rate-limit cooldown** (added 2026-09-15). When a model returns 429 it is skipped until it recovers, so an exhausted free quota does not cost every request a failed round trip. The wait is the `Retry-After` header in seconds, capped at 600 seconds, defaulting to 60 seconds.

**Classifier verdict gate** (added around 2026-09-14/15). `openrouter/free` sometimes routed prompts to content-safety classifier models, which answer anything with a verdict such as "User Safety: safe". A proofread once returned exactly that. `VerdictGate` holds back the first 24 non-space characters of the stream until it can tell whether the reply is a verdict (`^(user|agent|response|prompt) safety:` or a bare `safe`/`unsafe`). A verdict never reaches the client and the next model is tried. A real answer is forwarded in full and in order.

### 5.2 Mock mode

`MOCK_AI=true` (SPEC §8.4: UI work must burn zero quota). It changes:

| Area | Mock behaviour | Read from |
|---|---|---|
| Model calls | Streams `MOCK <tag>: <last prompt line, max 140 chars>` word by word, 12 ms apart. `<tag>` is the `[[tag]]` at the start of the prompt (for example `MOCK polite: ...`), else `run` | `env.mockAI` |
| Builder generate | Deterministic single-`llm` definition whose name is built from the description's first long words | `env.mockAI` |
| Act planner | Text ending in `?` becomes `answer`, anything else `rewrite` | `env.mockAI` |
| Act answer summary | A `MOCK` summary is ignored, so links are shown | `env.mockAI` |
| Vocab packs | Distinct words longer than 3 letters from the description | `env.mockAI` |
| Search | Fixed cards per vertical (a sunset answer and a link; two videos; two Bengaluru cafes) | `process.env.MOCK_AI` |
| Suggest | Fixed landing cards | `process.env.MOCK_AI` |
| Tools | Canned output per tool, each containing `MOCK` | `process.env.MOCK_AI` |
| Mock calendar | `day` is "MOCK today" | `env.mockAI` |
| Startup | `assertServerSecrets()` does not require a model key | `env.mockAI` |

`env.mockAI` is computed once at startup; `process.env.MOCK_AI` is read on each call. In a running server both come from the same variable. Tests set both explicitly.

**Rule from 2026-09-14:** mock output must never be visible to a real user. Mock mode is for the automated suites only.

### 5.3 Glyf definitions and the step engine

A glyf is one bindable action (SPEC §0, §6.8). Definitions are JSON validated by `GlyfDefSchema` (`server/src/schemas/glyfdef.ts`).

| Field | Type and rules |
|---|---|
| `id` | string |
| `version` | positive integer |
| `name` | string |
| `icon` | string, default `sparkles` (SF Symbol names) |
| `input` | `field`, `clipboard`, `selection` or `none` |
| `requires` | `{ fullAccess: boolean, connectors: string[], wallet: boolean }` |
| `discloses` | array of at least one non-empty string, rendered verbatim before install. A glyf without it cannot ship |
| `vars` | `Record<string,string>`, default `{}` |
| `steps` | at least one step |
| `output` | `{ mode: replace \| insert \| copy \| preview \| hud, from: string }` |

**Step types** (all implemented in `server/src/lib/glyfengine.ts`):

| Type | Fields | Behaviour |
|---|---|---|
| `llm` | `prompt`, `model` (`fast` default, `smart`, `strict`), `out` | Interpolates the prompt, calls the tier, stores trimmed text. Leading `[[directive]]` tags are stripped from the output (live models echoed `[[tighten]]` on empty input, fixed 2026-09-12) |
| `format` | `template`, `out` | Interpolation only |
| `tool` | `tool`, `args`, `out` | Resolves only against the server registry (SPEC §6.8, §11.5), so user glyfs can never make arbitrary HTTP calls. Unknown tools throw |
| `if` | `cond`, `then: stepIds`, `else: stepIds` | Runs the chosen branch's steps by id |
| `map` | `over`, `steps: stepIds`, `out` | Parses `over` as a JSON array, runs the steps per item with `{{item}}`, collects each iteration's last output into a JSON array |
| `ask` | `question`, `out` | A one-shot HTTP run cannot pause, so the answer must arrive as a var. Missing means the run fails with `needs input: <question>`. The interactive ask UI was planned for the chain editor (M9) |

Execution rules:

- Context starts as definition vars, overridden by caller vars, plus `input`.
- Steps run in order, except steps referenced by any `if` or `map`, which run only when their branch activates.
- Only the step whose `out` equals `output.from` streams tokens to the client, so intermediate results in a chain never leak.
- `output.from` must be produced, otherwise the run throws.
- `{{name}}` interpolation supports dotted paths into JSON values (`{{docs.0.title}}`) and `.length` on arrays. Missing values become empty strings.
- `evalCond` never uses `eval`. It supports `>`, `<`, `>=`, `<=` (numeric only), `==` and `!=` (numeric if both sides are numbers, else string), `contains` (case-insensitive), and bare truthiness (not empty, `0`, `false`, `[]`, `{}` or `null`). Quotes around operands are stripped.
- `loadRegistry()` validates every file in `server/src/registry/glyfs/` at startup and throws on an invalid definition or a duplicate id, so a bad shipped glyf stops the server from starting.

Chaining with conditionals is described in SPEC §0.1 as Glyf's main differentiator against Acti, which is why the schema supported it from day one (M2) and the engine executed it from M5 (2026-09-12).

### 5.4 Shipped glyf catalog (23)

All live in `server/src/registry/glyfs/`, version 1, output mode `preview` from `final`. Default glyfs are data, not Swift or Kotlin code (SPEC §6.13, §13).

| Id | Name | Input | Steps | Vars |
|---|---|---|---|---|
| `custom.prompt` | Custom prompt | field | llm `[[custom]]` (applies `{{prompt}}` to the draft) | `prompt` |
| `glyf.proofread` | Proofread | field | llm | |
| `glyf.summarize` | Summarize | clipboard | llm | |
| `glyf.translate` | Translate | field | llm `[[translate:{{target}}]]` | `target` (default English) |
| `rewrite.polite` | Make it polite | field | llm | |
| `rewrite.professional` | Professional | field | llm | |
| `rewrite.tighten` | Tighten | field | llm | |
| `rewrite.expand` | Expand | field | llm | `toneHint` |
| `rewrite.emoji` | Emoji-fy | field | llm | |
| `rewrite.tone` | Tone shift | field | llm `[[tone:{{tone}}]]` | `tone` (default casual), `toneHint` |
| `social.reply` | Reply draft | clipboard | llm | `toneHint` |
| `social.hook` | Hook rewrite | field | llm | |
| `social.emotion` | Emotion read | clipboard | llm | |
| `social.xreply` | Super X reply | clipboard | llm | `tone` (default witty) |
| `desi.hinglish` | Hinglish flip | field | llm | |
| `desi.formalhindi` | Formal Hindi | field | llm | |
| `dictation.clean` | Clean dictation | none (transcript as input) | llm | |
| `dictation.formal` | Formal dictation | none | llm | |
| `keyless.weather` | Weather | field | if input empty → "Bengaluru" → tool `weather.now` | `place` |
| `keyless.quote` | Quote lookup | field | tool `quote.crypto` | |
| `keyless.stock` | Stock check | field | if input empty → "AAPL" → tool `stocks.quote` | |
| `keyless.define` | Define | field | tool `dict.define` | |
| `keyless.wiki` | Wiki lookup | field | tool `wiki.summary` | |

Notes:

- All `llm` steps use the `fast` tier.
- `toneHint` is filled by the clients from the on-device tone profile (empty until at least 3 net accepted rewrites teach a preference). Tone data never leaves the device except as this short hint string (SPEC §6.15, §11.11).
- `dictation.clean` and `dictation.formal` post-process on-device speech transcripts (M3). They have `fullAccess: false`.
- Growth: 7 shipped definitions at M2 (2026-09-12 morning), 20 at the M5 gate (2026-09-12 afternoon), 23 after `keyless.define`, `keyless.wiki` and `keyless.stock` were added that night.

### 5.5 Builder

`POST /builder/generate` turns a plain-English description into a runnable definition (SPEC §6.8).

- Runs on the `smart` tier with a system prompt that demands one JSON object of an exact shape, lists the allowed step types, and lists exactly 27 tools (every registry tool except the three search-suite tools). It says "Never invent tools", requires the last output to be `final`, and asks for one `llm` step in most cases.
- Strict mode (SPEC §8.3): strip Markdown fences, `JSON.parse`, force `id: "user.draft"` and `version: 1`, validate with `GlyfDefSchema`, apply `ensureInputWired`, run moderation. Retry once, then fail closed with 422.
- `ensureInputWired()` (added 2026-09-12 after live testing): live models sometimes wrote prompts that described the input without interpolating it, so the user's draft never reached the model. When `input` is not `none` and no step mentions `{{input}}`, the server appends `Text: {{input}}` to the first `llm` step.
- Live timings on 2026-09-12 with the unfunded OpenRouter free tier: 16.4 s to generate a working "Hinglish Reply" glyf.

**Moderation** (`validateUserDef()` in `server/src/lib/userglyfs.ts`), applied on test, save and again at publish:

- `requires.wallet` must be false ("User glyfs can't touch the wallet").
- Every `tool` step must name a registry tool.
- `discloses` must be non-empty.
- At most 12 steps.
- At most 6000 characters of `llm` prompt text in total.
- OAuth-backed tools are allowed (since 2026-09-12 evening). At run time the executor asks the user to connect the provider if no token exists.

SPEC §6.9 describes a server-side moderation queue that auto-rejects glyfs reading vault or wallet data and sending it to non-registry destinations. What exists is this synchronous rule check; there is no queue or human review.

### 5.6 Act engine (hold space)

Built 2026-09-14 night to 2026-09-15 for parity with Acti's launch video: hold space on typed text and get a place, a list, an answer, a video or a cleaner message. `server/src/lib/act.ts`.

**Principle:** everything shown comes from a real provider lookup or a model rewrite of the user's own words. A model never invents live facts. When no provider can answer, the result is an honest "See ... on Google" handoff card.

**Planning** (`plan()`):

1. Rules first (`planByRules()`), no model cost:
   - Arithmetic-only text, `<amount> <cur> to|in <cur>`, or sunset/sunrise/golden hour/weather/temperature/"what time is it"/"time in": `answer`.
   - "near me", "nearby", "around me", "close by": `places`, except "nearest"/"closest" which is `place`.
   - A list word (best, top, good, cheap, popular, places, spots, options...) plus a place or cuisine word: `places`.
   - Video, trailer, song, lyrics, playlist, tutorial, livestream, highlights: `video`.
2. Otherwise one fast-tier call with a JSON-only router prompt returning `{"intent": ..., "query": ...}`. The first JSON object in the reply is parsed and validated; unknown intents or parse failures fall back to `rewrite`. Model errors also fall back to `rewrite`.

**Execution:**

| Intent | Provider call | Result and insert |
|---|---|---|
| `place` | `search("maps")` | Top place card; insert is URL, then "📍 title", then address |
| `places` | `search("maps")` | Top 4 cards. If a public page base exists, publishes all places (max 8) as `/p/:id` and inserts the typed text plus the page link; otherwise a numbered list with rating, address and a maps link per place |
| `video` | `search("yt")` | First video card; insert is URL then "🎥 title" |
| `answer` | `search("web")` | An answer card if one exists (insert is value plus sub line). Else, with links, one fast-tier call answers in at most three lines using only those results or replies `UNKNOWN`; the insert is the summary plus the first link. With no links, the Google handoff card |
| `rewrite` | one fast-tier call (`[[act.rewrite]]`) | Text only, keeping the writer's meaning, language and tone |

**Page base** (`pageBase()` in `routes/act.ts`): `PUBLIC_BASE_URL` if set; otherwise `http://127.0.0.1:<PORT>` outside production and no pages in production.

**Pages** (`server/src/lib/pages.ts`): 9 random bytes as a 12-char base64url id (not enumerable), title max 120 chars, max 8 places. Rendering escapes every string, and only `http(s)` URLs may become links (a `javascript:` card URL renders as `#`). The page holds only what the user chose to share, nothing about the sender.

Examples that were verified live on 2026-09-14/15: "Times Square Starbucks" returned a real place card on the Android emulator; `/act` place, video and rewrite probes returned real results. "World Cup today" style answers need `BRAVE_SEARCH_KEY`, and place categories need `GEOAPIFY_KEY` (or Places) in production.

### 5.7 Vocabulary packs

`POST /vocab/generate` (`server/src/lib/vocab.ts`), built 2026-09-15 for Arpit's request for a categorized vocabulary library the keyboard learns from.

- Someone describes how they write (for example "cardiologist in Pune, texts in Hinglish"). One fast-tier call returns `{ name, words, phrases }` in JSON. Only the description is sent, never typed text.
- Cleaning: words max 32 chars, must contain a letter, at most two spaces, no URL/email/markup characters, deduplicated case-insensitively, max 150. Phrases must contain a space, max 60 chars, max 20. A reply with no usable words is a 502.
- Live test on 2026-09-15 took 58 seconds on the free OpenRouter models and returned words like Figma, BGMI, Koramangala, yaar and jugaad.
- The 20 built-in packs (about 2,200 words) are an app asset (`app/assets/vocab/packs.json`), not a server feature. Learning and autocorrect run entirely on the device.

### 5.8 Run cache

`TTLCache` in `server/src/lib/cache.ts`: sha256 of the joined key parts, TTL, max entries with oldest-first eviction.

- `/glyf/run`: key is glyf id, version, input and `JSON.stringify(vars)`. TTL `CACHE_TTL_MS` (default 24 hours), 500 entries. SPEC §8.4 asked for this to save the free-tier rate limit during development. The key has no device id, and tool-backed outputs are cached too ([known issue 3](#16-known-issues)).
- The search and suggest caches are separate ([6.7](#67-caching-rules)).

### 5.9 Metering and plans

`server/src/lib/meter.ts`, SPEC §6.16.

| Plan | Price (decided 2026-09-12) | Daily cap (`planCap()`) | Intended extras |
|---|---|---|---|
| free | $0 | `FREE_RUNS_PER_DAY` (40) | fast tier, slower |
| plus | $4.99/month | 10 times the free cap (400) | priority |
| max | $19.99/month | unlimited (`Number.MAX_SAFE_INTEGER`) | smartest models, early features |

- Arpit asked on 2026-09-12: "we can give some slow free replies with ai in free and ask to update accordingly one 5 $ plan and one 20$". The assistant researched Wispr Flow ($12 to 15/month with a hard free cap) and Grammarly's keyboard (about $12/month) and proposed undercutting with Plus and out-featuring with Max.
- Metered routes: `/glyf/run`, `/act`, `/vocab/generate`. One request is one run.
- Counts are per device per UTC day (reset at 05:30 IST), in memory. Responses cap `remaining` at 9999.
- The plan is asserted by the client until StoreKit receipt validation exists (the "M7-ship TODO"). The in-app paywall currently unlocks locally. The legacy `pro: true` flag maps to `plus`.
- The "priority" and "smart models for Max" promises are not implemented: every plan uses the same chains.

### 5.10 Model choices over time, research and costs

**Timeline**

| Date | Chain | Why it changed |
|---|---|---|
| 2026-09-11 | Arpit supplies an OpenRouter key | SPEC §8 pinned OpenRouter |
| 2026-09-12 | Default `openrouter/free` | First live runs: about 23 s per rewrite on the unfunded free tier; 14.6 s tone rewrite; keyless tools 0.4 to 1.6 s. The assistant repeatedly recommended putting $10 on OpenRouter (unfunded accounts get 50 free requests per day, funded ones 1,000; 20 per minute either way, per SPEC §8.2) |
| About 2026-09-14/15 | Pinned OpenRouter free models: fast `google/gemma-4-26b-a4b-it:free`, `google/gemma-4-31b-it:free`, `nvidia/nemotron-3-super-120b-a12b:free`, `openrouter/free`; smart `nvidia/nemotron-3-super-120b-a12b:free`, `google/gemma-4-31b-it:free`, `openrouter/free` | `openrouter/free` landed on content-safety classifiers; free models returned 429, overload and 12 to 20 s latency; the daily free quota was exhausted during testing, causing 502s |
| 2026-09-15 | No-card chain in `.env.example`: fast `gemini:gemini-2.5-flash-lite`, `groq:qwen/qwen3.8-27b`, `groq:openai/gpt-oss-20b`, `openrouter/free`; smart `groq:openai/gpt-oss-120b`, `groq:qwen/qwen3.8-27b`, `gemini:gemini-2.5-flash` | Arpit: "find me good and v cheap ai model to use here, i heard groq is good but ig they stopped sharing dev apis" |

Per the 2026-09-15 context snapshot, `server/.env` was set to the Gemini/Groq chain with the pinned OpenRouter free models kept as the tail, and the `GEMINI_API_KEY` and `GROQ_API_KEY` lines were left empty for Arpit to fill. This was not re-checked while writing (the file was not opened). Until those keys exist, live AI depends on the OpenRouter free tier, which was out of quota at the time.

**Research findings (2026-09-15)**

- Groq did not stop developer access. The Free plan (no card) and Developer plan still exist after its December 2025 NVIDIA licensing deal. It removed `llama-3.1-8b-instant` and `llama-3.3-70b` from self-serve on 2026-08-16 (enterprise only now).
- Groq self-serve models: `openai/gpt-oss-20b` ($0.075 in / $0.30 out per 1M tokens), `openai/gpt-oss-120b` ($0.15 / $0.60), `qwen/qwen3.6-27b`, `qwen/qwen3.8-27b` (preview). Free limits per model: 30 requests/minute, 1,000 requests/day, 8,000 tokens/minute, 200,000 tokens/day.
- Gemini 2.5 Flash-Lite: first token in about 0.28 s, thinking off by default, $0.10 / $0.40 per 1M tokens when paid, about 500 requests/day free. Gemini 3.x Flash-Lite cannot disable thinking (5 to 8 s to first token), so avoid it.
- Groq `gpt-oss-120b` gives reliable strict JSON for the Builder.
- Free capacity across the no-card chain: roughly 40,000 calls/month. Fine for testing, not for launch.
- Paid estimate: about $12 to $13/month for 100,000 fast calls plus 2,000 smart calls on paid Gemini plus the Groq Developer plan. Gemini's paid tier needs a $5 prepay with auto-reload.
- Cerebras is the fastest option but has no free tier any more (about $25 per 100,000 calls); kept as an optional `cerebras:` prefix.
- GitHub Models was retired on 2026-07-30.
- Extra free pools if keys are added: `mistral:mistral-small-2603` (free plan credits) and `inception:mercury-2.5` (free tokens).
- Premium alternatives were about 10 times the price.
- There is no independent Hinglish benchmark for these models. The suggested check is to run about 50 real messages once keys exist.

**Caveats that still apply**

- Gemini's free tier trains on submitted data, and its terms prohibit sending personal information and apps likely to be used by under-18s. The assistant flagged this as a terms-of-service problem, largely removed by paying.
- OpenRouter free models may also train on inputs. The server sends no data-collection opt-out flags. On 2026-09-15 Arpit deferred this: "we will not work on ai privacy rn as we will have privacy policy".

---

## 6. Search suite

Gboard-style Search, YouTube and Maps tabs inside both keyboards (SPEC §6.12 area), built 2026-09-14 after Arpit asked for the website's search cards "fully working" in the keyboard, with results shown inline and pasted into the chat. Engine: `server/src/lib/search.ts`, `answers.ts`, `sun.ts`, `suggest.ts`, `searchcards.ts`.

**Core rule:** keys are optional everywhere and adding one upgrades a vertical in place with no client change. Without a key a vertical degrades honestly (computed answers, a handoff link). It never shows a fabricated result list.

### 6.1 Shape and card contract

- `POST /search` returns typed cards (thumbnails, ratings, durations). `/tools/run` stays separate because glyf chains consume flat strings. The two were deliberately not merged.
- The card contract lives in `server/src/lib/searchcards.ts` and is mirrored field for field in Swift (`app/ios/GlyfKeyboard/Engine/SearchCard.swift`) and Kotlin (`BackendClient.SearchCard`). Renaming a field means renaming it in all three places.

| Card `kind` | Fields beyond `id`, `title`, `url`, `emoji?`, `extra?` |
|---|---|
| `answer` | `value` (headline, for example "6:13 PM"), `sub?`, `art` (`sun`, `weather`, `calc`, `define`, `none`), `source?` |
| `link` | `domain`, `snippet?`, `thumb?` |
| `video` | `videoId`, `channel`, `duration?`, `live?`, `thumb?`, `source?` (`liked` for the user's own) |
| `place` | `address?`, `rating?`, `ratingCount?`, `openNow?`, `distance?` (only with a location), `thumb?`, `lat?`, `lon?` |
| `query` | `source?` (`trending` or `recent`); tapping runs a search instead of pasting |

**Paste format** (`composeInsert()`), verified against Gboard's own YouTube and Maps shares:

- Title and link (default): URL on line 1, `<emoji> <title>` on line 2, and for places the address on line 3. Videos use 🎥, places 📍, plain web links no emoji.
- Link only: just the URL.
- The setting (`pasteStyle`) was Arpit's request on 2026-09-14: "we can have option in setting to paste only link or title and link and by default it should be title and link".
- The function lives on the server so the keyboards and the site cannot drift. Each client ports it with the same tests.

### 6.2 Web vertical

Order inside `searchWeb()`:

1. **Instant answer** (`instantAnswer()`), always tried first. Cheap string checks gate every network call, so an ordinary query like "best running shoes" costs nothing.

   | Detector | Triggers on | Source | Needs |
   |---|---|---|---|
   | Math | Digits and `+ - * / % ^ ( )`, also `15% of 200` | Recursive-descent parser, never `eval`; rejects bare numbers, division by zero, identifiers | nothing |
   | Sun | sunset, sunrise, golden hour | Computed with the NOAA sunrise equation (`sun.ts`), accurate to well under a minute; handles midnight sun and polar night; golden hour = sun 6° above the horizon | caller `lat`/`lon`; skipped when the query names a place ("in Paris") |
   | Time | "time", "what's the time", "current time" | `Intl` in the caller's zone | caller `tz`; skipped for a named place |
   | Weather | weather, temperature, how hot/cold, raining | Google Weather API current conditions, metric | `GOOGLE_WEATHER_KEY` or `GOOGLE_PLACES_KEY`, plus location |
   | Currency | `<amount> <CUR> in/to/= <CUR>` | Frankfurter (`api.frankfurter.dev/v1`) | nothing |
   | Wikipedia | "what/who/where is/was/are/were ..." | Wikipedia REST summary; disambiguation pages ignored | nothing |

2. **Serper** (`SERPER_API_KEY`): real google.com results including the answer box and knowledge panel, `gl` set from `country`. Provider name `google`.
3. **Brave** (`BRAVE_SEARCH_KEY`): 6 results, `safesearch=moderate`, `country` passed. Provider name `brave`.
4. A tail row "See all results for ..." linking to Google search is always appended, so the tab is never a dead end.

The decided order is Brave first with Serper as an opt-in fallback. The code currently tries Serper first ([known issue 2](#16-known-issues)). With neither key the tab is answers-only (provider `none`).

### 6.3 YouTube vertical

- `YOUTUBE_API_KEY` (YouTube Data API v3): `search.list` for 6 videos (with `regionCode` from `country`), then one `videos.list` call for durations and live status. Durations are formatted from ISO 8601 (`PT1H2M14S` becomes `1:02:14`); live streams show no duration. HTML entities in titles are decoded.
- Without a key: no video cards, only a "Search YouTube for ..." tail link. There is no legitimate keyless YouTube search API.
- The tail row reads "More on YouTube for ..." when there are results.
- Quota facts from the research: the default project quota allows about 100 `search.list` calls per day. `videos.list` costs 1 unit for up to 50 ids, so duration enrichment and the popular chart are effectively free.
- Status: the key was provided on 2026-09-14 and the tab was verified live (real thumbnails, durations and channels in the keyboard).

### 6.4 Maps vertical

Order inside `searchMaps()`:

1. **Google Places API (New)** `places:searchText` (`GOOGLE_PLACES_KEY`): 6 results with a 15 km location bias when the caller sent coordinates. Field mask requests rating, rating count, open-now, location, first photo and the Google Maps URI. Photos are returned as `/search/photo?ref=...` so the key stays on the server. Provider `google-places`.
2. **Geoapify** (`GEOAPIFY_KEY`), the no-credit-card path. A "near me" query with a known category (cafe, restaurant, bar, ATM, bank, pharmacy, hospital, fuel, hotel, gym, park, supermarket, bakery) and a location goes to `/v2/places` within 3 km (distance returned free). Anything else goes to `/v1/geocode/search` with a proximity bias. Up to 6 to 8 results. Provider `geoapify`.
3. **Nominatim (OpenStreetMap public)**, development only (`NODE_ENV !== "production"`). Requests are serialized about 1.1 s apart to respect OSM's 1 request per second policy for the whole server. With a location: a tight bounded box for "near me" queries, a soft 0.6° box otherwise; results sorted by distance. "near me" words are stripped from the name search (Nominatim once returned a shop in Singapore literally named "Coffee Near Me").
4. **Overpass** (only inside the Nominatim path, only when `OVERPASS_API_BASE` is set): for "near me" category queries, named OSM features within 2 km, sorted by distance.
5. A "See ... on Maps" tail row is always appended.

Provider label defaults to `openstreetmap` even when nothing answered.

Place URLs use Google Maps' own share format (`/maps/search/?api=1&query=<name>&query_place_id=<id>`), or the Places `googleMapsUri` when available.

### 6.5 Landing state (`GET /search/suggest`)

Arpit, 2026-09-14: "u should show the recent google searches or top google searches and same witth yt show recent yt video views by user here, not put user in the search bar directly, same with maps, req location access and show nearby things".

| Tab | Server rows | Provider label | Needs |
|---|---|---|---|
| Web | Google Trends daily trending searches RSS for the caller's country (up to 8), else five starter queries | `google-trends` or `starter` | nothing |
| YouTube | The user's liked videos (`myRating=like`, 8) when their Google account is connected with the `youtube` scope, else the `chart=mostPopular` list for the country | `youtube-me`, `youtube-chart` or `none` | Google OAuth token, or `YOUTUBE_API_KEY` |
| Maps | Places Nearby Search within 2 km ranked by distance (restaurant, cafe, supermarket, pharmacy, park); without a Places key, Geoapify cafes and restaurants merged by distance | `nearby` or `none` | location plus `GOOGLE_PLACES_KEY` or `GEOAPIFY_KEY` |

- Country defaults to `US`.
- The clients merge their own on-device recents above these rows. Recents are never sent to the server.
- **What Google login cannot provide** (settled 2026-09-14): there is no API or OAuth scope for a person's Google Search history or YouTube watch history (watch history left the Data API years ago; Search history is Takeout-only). The `youtube.readonly` scope gives liked videos and subscriptions, which is what personalizes the YouTube tab. Web and Maps stay impersonal.
- A client-side bug found while building this: the landing list initially covered the key grid on both platforms, so the user could not type. Fixed with a separate landing layout that keeps the keys visible.

### 6.6 Location handling

- A keyboard extension cannot ask for location, so the app asks (an onboarding "Nearby search" step, and a Profile toggle added 2026-09-14 because the onboarding copy promised one).
- The app rounds the fix to about 1 km and caches `lastLat`, `lastLon` and `region` in shared settings. The keyboards forward `lat`, `lon`, `country` and `tz` with each `/search`, `/search/suggest` and `/act` request.
- The server uses location only for that request and never stores it.
- Uses: Places location bias (15 km) and nearby search (2 km), Geoapify category circle (3 km) and proximity bias, Nominatim bounding boxes, Overpass radius (2 km), distance labels (`350 m`, `1.2 km`), sunrise/sunset/golden hour, weather, local time, and `country` for Brave, Serper, YouTube `regionCode` and Google Trends.
- Verified end to end on 2026-09-14 on iOS: with location on, "Sunset" returned 6:23 PM for Bengaluru (nothing without a fix), and trending searches and the YouTube chart switched from US to Indian content.

### 6.7 Caching rules

| Cache | TTL | Size | Key | Exceptions |
|---|---|---|---|---|
| `/search` results | 10 min | 400 | vertical, lowercased query, lat and lon rounded to 2 decimals (about 1 km buckets), country | **Brave responses are never cached**: Brave's terms allow only transient storage needed for the operation. Mock responses bypass the cache |
| `/search/suggest` rows | 30 min | 60 | vertical, country, rounded lat and lon | Personalized YouTube rows (liked videos) are never cached |
| Places photo and static map proxies | Client-side `Cache-Control: public, max-age=86400` | none on the server | | |

Why a cache at all: search results are shared across users and go stale slowly, so a short cache speeds repeat queries and protects metered keys from the same query typed twice.

### 6.8 Keys per vertical

| Variable | Unlocks | Price and quota (as researched on the date) | Card needed | Status (per notes, not re-checked) |
|---|---|---|---|---|
| `BRAVE_SEARCH_KEY` | Real web links (primary by decision) | $5 per 1,000 queries; $5 free credit per month, which requires a "Powered by Brave" line in the app (2026-09-14) | Yes | Not provided |
| `SERPER_API_KEY` | Real google.com results with answer box (opt-in fallback only) | 2,500 free queries, then $1 per 1,000 (5 to 15 times cheaper than Brave) | Not recorded | Not provided |
| `YOUTUBE_API_KEY` | YouTube search, durations, popular chart | Free; about 100 searches per day for the whole project by default | No | Provided 2026-09-14, live. Regenerate and IP-restrict after deploy |
| `GEOAPIFY_KEY` | Maps without a card; static maps on Android | 3,000 requests/day free, 5 requests/second, commercial use allowed, attribution "Powered by Geoapify" with a link required | No (confirmed on their pricing page, 2026-09-14) | Not provided |
| `GOOGLE_PLACES_KEY` | Ratings, open-now, photos, nearby landing | Ratings/open-now/photos are the Enterprise SKU ($35 per 1,000, 1,000 free per month); names and addresses alone are Pro ($32 per 1,000, 5,000 free) | Yes (billing account) | Not provided. Arpit declined to add a card on 2026-09-14 |
| `GOOGLE_WEATHER_KEY` | Weather answer card (falls back to `GOOGLE_PLACES_KEY`) | $0.15 per 1,000, 10,000 free per month | Yes (same Cloud project) | Not provided |
| `OVERPASS_API_BASE` | Keyless "near me" categories on the dev path | Self-hosted Overpass instance | n/a | Not set |

What each tab looks like today without paid keys: YouTube works; Maps works only in development (Nominatim) and returns nothing but a tail link in production until `GEOAPIFY_KEY` or `GOOGLE_PLACES_KEY` exists; Search shows computed answers plus a Google handoff.

**Google Cloud setup steps given to Arpit on 2026-09-14** (for when he creates the keys):

1. YouTube key: Cloud Console, new project, enable "YouTube Data API v3", create an API key, restrict it to that API. When the wizard asks, choose "Public data" (Arpit asked "shud we just do public for now ?"; the answer was yes, because search and the popular chart are public-data calls, and personalization comes later through the separate OAuth client).
2. Places key: same project, link a billing account, enable "Places API (New)" (and "Weather API"), create a separate key restricted to those. Do not reuse the YouTube key, which was pasted in chat; an exposed key on a billed API is a money risk.
3. OAuth client: see [8.6](#86-setup-and-credentials-still-needed).
4. Put keys straight into `server/.env`, never in chat. The assistant verifies them through `/search/status` without seeing the values.

### 6.9 Tried and rejected

| Option | What happened | Outcome |
|---|---|---|
| DuckDuckGo Instant Answer API as the web tab (2026-09-13 v1, and Arpit's suggestion on 2026-09-14: "i think just use duck duck go here for search") | Measured on 2026-09-14: empty for "best pizza near me", "how to fix a flat tyre", "iphone 17 pro review", "flight status AI 806" and "nike running shoes". It is a Wikipedia-abstract service, not a web search API, and commercial use needs their written approval | Removed from `/search`. Still used by the `web.search` tool ([known issue 8](#16-known-issues)) |
| Google Custom Search JSON API | Closed to new customers; existing customers cut off on 2027-01-01. New Programmable Search engines are capped at 50 domains, so even the embeddable element cannot do full web | Impossible |
| Grounding with Google Search | Returns an LLM answer; its display terms forbid showing other content interspersed with the grounded results, which is exactly a card list | Rejected |
| Bing Search API | Retired 2025-08-11 | Impossible |
| Serper as the default web provider | Cheap and real Google results, but it resells scraped Google results, and Google is litigating that category (Google v. SerpApi, N.D. Cal.). The dependency can vanish on a court order | Demoted to opt-in fallback |
| Embedded browser loading google.com with the user's own Google login (Arpit's idea, 2026-09-14) | Google blocks OAuth in app-controlled webviews (HTTP 403 `disallowed_useragent`, enforced since 2021-09-30). Juno for YouTube was removed from the App Store in October 2024 under guideline 5.2.2 just for restyling youtube.com in a webview. Facebook v. Power Ventures (9th Cir. 2016): user-supplied credentials do not authorize access once the service objects. Meta v. Bright Data: the scraper won because it was logged out, so a logged-in user is bound by the terms. Google runs SearchGuard anti-scraping. Apple 4.4.1 forbids a keyboard launching any app but Settings. A keyboard extension also has only about 45 to 60 MB of memory | Dead. "Settled 2026-09-14, do not revisit" |
| Piped (YouTube scraping proxy) as a keyless YouTube rung | Same terms exposure as scraping YouTube; public instances collapsed | Removed |
| Public Nominatim as the production maps provider | A geocoder, not place search (0 results for a named hotel); forbids autocomplete-style use; caps the whole server at 1 request/second | Development only |
| Public Overpass for "near me" | Timed out at about 13 s, worse than no result inside a keyboard | Opt-in behind `OVERPASS_API_BASE` |
| Open-Meteo for answer cards | Its free tier is non-commercial only | Sunrise and sunset computed locally instead. Still used by three tools ([known issue 8](#16-known-issues)) |
| dictionaryapi.dev for definitions | Returning HTTP 522 on 2026-09-14; a dead upstream stalls the fallback | Wikipedia summaries in answers. Still used by the `dict.define` tool |
| Fetching a static map image for every place thumbnail | Research on 2026-09-14 said drawing the pin client-side is the right call for a list thumbnail | Pins drawn client-side. A Geoapify static map was added later (2026-09-15) only for the larger act place card on Android; iOS uses MapKit snapshots |
| HERE for maps without a card | The only free option with ratings and open-now, but reports conflicted on whether signup needs a card | Not built |

### 6.10 Provider obligations to honour before launch

- **Brave:** no result caching (implemented). The free monthly credit requires a "Powered by Brave" line.
- **Geoapify:** "Powered by Geoapify" attribution with a link somewhere in the app. Whether the apps show it was not verified.
- **YouTube:** every card showing YouTube content needs a YouTube mark (one blanket attribution is not enough), and thumbnails must not be cropped (aspect fit). Both implemented in the keyboards on 2026-09-14.
- **YouTube quota:** file the quota extension form early. It needs a public URL, a privacy policy and a demo account, and approval takes weeks to months. 100 searches/day is fine for TestFlight, not for launch.
- **`youtube.readonly`:** a sensitive scope. Google requires app verification before public launch; testing mode allows up to 100 test users.
- **OpenStreetMap:** Nominatim usage policy (1 request/second, no autocomplete). Enforced by keeping it out of production in `/search`.

---

## 7. Keyless tool registry

The registry (SPEC §6.11) is the only way a glyf can reach the outside world. Files: `server/src/registry/tools/*.json` (metadata) and `server/src/lib/tools.ts` (loader, rate limiter, executors, mock outputs).

### 7.1 Tool metadata schema (`ToolMetaSchema`)

```jsonc
{
  "id": "weather.now",
  "label": "Current weather",
  "auth": "none",                      // or "oauth:<provider>"
  "inputs": [{ "name": "place", "type": "string", "required": true }],
  "output": "string",
  "scopes": [],
  "discloses": "the place name you ask about (sent to Open-Meteo)",
  "rateLimit": { "perMin": 20 },
  "timeoutMs": 5000
}
```

- `discloses` is required and shown verbatim before install. A test fails if any tool lacks it, or lacks a positive rate limit and timeout.
- `runTool(id, args, connections)` returns a string: human-readable text for terminal results, JSON where chains continue (Notion results, unfurl, the search tools).
- OAuth tools look up the device's token in `connections`; with none they throw "Connect <Provider> in the Glyf app first".
- Rate limit: a sliding one-minute window per tool id. It is global across all devices, not per device ([known issue 6](#16-known-issues)).
- In mock mode every tool returns a canned string containing `MOCK`.
- SPEC target: "30 quality tools at launch beats 150 shallow ones". The registry has exactly 30 today.
- Growth: 7 tools at M5 (2026-09-12 afternoon), reported as 19 and then 28 later that day after Arpit asked to "research what more tools we can have, deeply research this" and "integrate as much free tools as possible", then the three search-suite tools on 2026-09-13. Categories that genuinely needed paid keys were left out and flagged for later: flight status, movie and TV data, general news wires.

### 7.2 All 30 tools

| Id | Label | Auth | Inputs | Upstream | Per min | Timeout |
|---|---|---|---|---|---|---|
| `advice.random` | Advice | none | none | Advice Slip API | 15 | 5 s |
| `air.quality` | Air quality | none | place | Open-Meteo geocoding + air quality | 20 | 6 s |
| `books.search` | Book search | none | query | Open Library | 15 | 7 s |
| `calendar.today` | Today's calendar | oauth:google | query (optional, unused) | Google Calendar v3, primary calendar, today's events | 20 | 4 s |
| `country.info` | Country facts | none | country | REST Countries | 15 | 6 s |
| `dict.define` | Dictionary | none | word | dictionaryapi.dev | 30 | 5 s |
| `fact.random` | Random fact | none | none | Useless Facts API | 15 | 5 s |
| `food.info` | Food facts | none | food | Open Food Facts | 10 | 8 s |
| `fx.convert` | Currency conversion | none | amount, from, to | Frankfurter | 20 | 5 s |
| `holidays.next` | Next holidays | none | country (default IN) | Nager.Date | 10 | 6 s |
| `joke.random` | Dad joke | none | none | icanhazdadjoke | 15 | 5 s |
| `maps.search` | Maps search | none | query | Nominatim (JSON rows with Google Maps links) | 30 | 7 s |
| `news.tech` | Tech headlines | none | none | Hacker News front page via Algolia | 10 | 6 s |
| `notion.search` | Search Notion | oauth:notion | query | Notion search API (`Notion-Version: 2022-06-28`), 5 results as JSON | 20 | 4 s |
| `places.search` | Place search | none | query | Nominatim, top 3 with OpenStreetMap links | 15 | 7 s |
| `quote.crypto` | Crypto price | none | symbol (btc, eth, sol, bonk, doge, usdc, usdt mapped) | CoinGecko simple price | 10 | 5 s |
| `quote.inspire` | Inspiring quote | none | none | ZenQuotes | 15 | 5 s |
| `recipes.search` | Recipe | none | dish | TheMealDB (public test key in the URL path) | 10 | 7 s |
| `repo.info` | GitHub repo | none | repo (`owner/repo`) | GitHub public REST API | 10 | 6 s |
| `route.eta` | Route ETA | none | from, to | Open-Meteo geocoding + public OSRM router (driving) | 10 | 8 s |
| `sports.next` | Next fixture | none | team | TheSportsDB (public test key `123`) | 10 | 7 s |
| `stocks.quote` | Stock quote | none | symbol (default AAPL, `.us` suffix added) | Stooq CSV | 20 | 6 s |
| `time.now` | Date and time | none | timezone (default Asia/Kolkata) | Computed locally with `Intl` | 60 | 1 s |
| `urban.define` | Slang lookup | none | term | Urban Dictionary API | 15 | 6 s |
| `url.unfurl` | Link preview | none | url | Fetches the page directly, reads Open Graph title and description (first 60 KB) | 15 | 6 s |
| `weather.now` | Current weather | none | place (default Bengaluru) | Open-Meteo geocoding + forecast | 20 | 5 s |
| `web.search` | Web search | none | query | DuckDuckGo Instant Answer API, plus a Google search link row | 30 | 6 s |
| `wiki.summary` | Wikipedia summary | none | topic | Wikipedia REST summary | 20 | 6 s |
| `word.synonyms` | Synonyms | none | word | Datamuse | 30 | 5 s |
| `yt.search` | YouTube search | none | query | YouTube Data API when `YOUTUBE_API_KEY` is set, else a search link | 30 | 6 s |

Notes:

- Only `yt.search` needs a server key. Every other keyless tool calls a free public API with no key.
- `calendar.today` metadata lists the scope `calendar.readonly`, while the Google broker requests `calendar.events` (which includes read access). Harmless, but inconsistent.
- The Builder's system prompt lists 27 tools. It omits `web.search`, `yt.search` and `maps.search`, although moderation would accept them in a hand-written definition.
- Several upstreams were chosen for being free, not for commercial-use terms. Open-Meteo (non-commercial free tier), DuckDuckGo (commercial use needs approval), public Nominatim (1 request/second policy) and dictionaryapi.dev (was failing) were explicitly rejected for the search suite on 2026-09-14 but are still used here. The terms of the other free APIs were not reviewed in the notes. See [known issue 8](#16-known-issues).
- Live checks on 2026-09-12: Mumbai weather in 1.6 s, SOL price in 0.4 s.

---

## 8. Connectors and the OAuth broker

File: `server/src/routes/connector.ts`. SPEC §6.11 calls connectors "the largest single module" and says "DO NOT SKIP".

### 8.1 Design

- **Tokens live on the server only.** Never on a device, never in the App Group, never in a response. Devices only ever see opaque summaries (`configured`, `connected`, scopes, email or workspace name).
- **One generic code-flow broker** for every provider, plus a Google-specific start that lets the user pick scopes. Google sign-in doubles as the account.
- **Each provider activates the moment its two variables exist** (`<PREFIX>_CLIENT_ID` and `<PREFIX>_CLIENT_SECRET`). Until then its start route fails closed with a 503 that names the missing variables. No fake "connected" states.
- **Hand-rolled** with `fetch` (8 s timeouts). SPEC §2 suggested `@fastify/oauth2` or Arctic; no library was used.
- **Callbacks return to the app** through the custom scheme `glyf://connected?provider=<name>&ok=true|false`, handled in `app/lib/main.dart`.
- Arpit's direction (2026-09-12): "we need a login when app is opened the first time and there only user can decide what all he wants to give access to mail, calendar, meet etc", asked "at the end of onboarding flow based on the answered questions". The onboarding "Connect your Google" step presets scope checkboxes from the persona answer (for example Working: Calendar, Gmail, Meet; Student: Calendar), and every toggle stays the user's choice. Profile, Connected tools has Connect and Disconnect.

### 8.2 Providers

| Id | Label | Env prefix | Scopes requested | Client auth at token exchange | Quirks handled |
|---|---|---|---|---|---|
| `google` | Google | `GOOGLE` | user-chosen (8.3) | client id and secret in the body, plus PKCE | email read from the `id_token` payload (display only, signature not verified) |
| `notion` | Notion | `NOTION` | none (`owner=user`) | HTTP Basic | email from `owner.user.person.email` |
| `slack` | Slack | `SLACK` | `channels:read,chat:write,search:read` as `user_scope` | body | user token read from `authed_user.access_token`; workspace name stored as the label |
| `github` | GitHub | `GITHUB` | `repo read:user` | body | token endpoint needs `Accept: application/json` |
| `linear` | Linear | `LINEAR` | `read,write` | body | |
| `todoist` | Todoist | `TODOIST` | `data:read_write` | body | |
| `calendly` | Calendly | `CALENDLY` | none | HTTP Basic | |
| `zoom` | Zoom | `ZOOM` | none | HTTP Basic | |
| `spotify` | Spotify | `SPOTIFY` | `user-read-currently-playing` | HTTP Basic | |

Research pick order for a keyboard, given on 2026-09-12: Google (Calendar, Gmail, Meet) first, then Notion, then Slack, then Todoist and Linear, then Calendly and Zoom, then Spotify and GitHub.

SPEC's launch set was Google (Gmail, Calendar, Drive, Meet, Contacts), Notion, Slack, Linear, Calendly and GitHub. Drive and Contacts scopes are not implemented on the server. Contacts search exists in the apps as a device-local feature (synced locally after an OS permission, never uploaded).

### 8.3 Google flow

`GET /oauth/google/start?deviceId=&scopes=...` then `GET /oauth/google/callback`.

| Scope choice | Real Google scopes |
|---|---|
| `identity` (always added) | `openid`, `email`, `profile` |
| `calendar` | `https://www.googleapis.com/auth/calendar.events` |
| `gmail` | `https://www.googleapis.com/auth/gmail.compose` |
| `meet` | `https://www.googleapis.com/auth/meetings.space.created` |
| `youtube` (added 2026-09-14) | `https://www.googleapis.com/auth/youtube.readonly` |

Steps:

1. Start: random `state` (UUID) and PKCE verifier (two UUIDs), S256 challenge. Pending state kept in memory for 10 minutes. Consent URL uses `access_type=offline` and `prompt=consent` (so a refresh token is issued).
2. Callback: look up and delete the pending state, exchange the code at `https://oauth2.googleapis.com/token` with client id, secret, redirect URI and verifier.
3. Store `{ provider, scopes, email, access_token, refresh_token, expires_at, connectedAt }` under `<deviceId>:google`.
4. Redirect to `glyf://connected?provider=google&ok=true`. Any error, missing code, unknown state or failed exchange redirects with `ok=false`.

### 8.4 Other providers

`GET /oauth/:provider/start` builds `authorizeUrl?client_id&redirect_uri&response_type=code&state` plus the provider's scope parameter and extra parameters. No PKCE. The callback checks that the state belongs to the same provider, exchanges the code with Basic or body client authentication, and stores the token. `expires_at` defaults to one year when the provider sends no `expires_in`.

**Redirect URI rule** (same for Google):

1. `<PROVIDER>_REDIRECT_URI` if set (for example `GOOGLE_REDIRECT_URI`), else
2. `OAUTH_REDIRECT_BASE` + `/oauth/<provider>/callback`, else
3. `http://127.0.0.1:<PORT>/oauth/<provider>/callback`.

The URI must match what is registered with the provider exactly. That is why the domain had to be decided before any credentials were created (discussed 2026-09-13), and why `OAUTH_REDIRECT_BASE=https://api.tryglyf.com` was added on 2026-09-14.

### 8.5 What connected accounts actually do today

| Connection | Consumers in the server | Working? |
|---|---|---|
| Google `calendar` | `calendar.today` tool inside glyf runs | Code path exists and is mock-tested. Never run against a real account |
| Google `youtube` | Liked videos on the YouTube landing tab (`/search/suggest`) | Code path exists. Never run against a real account |
| Google `gmail`, `meet` | None yet | Scopes requested but unused |
| Notion | `notion.search` tool inside glyf runs | Never run against a real account |
| Slack, GitHub, Linear, Todoist, Calendly, Zoom, Spotify | None yet | Connect and disconnect only |

- Tokens are resolved per request (`connectionsFor()` in `routes/glyf.ts`, `googleToken()` in `routes/search.ts`); expired tokens are skipped, and the tool then asks the user to reconnect.
- **No refresh flow exists.** Refresh tokens are stored but never used. Google access tokens last about an hour, so a real Google connection would need reconnecting after that ([known issue 11](#16-known-issues)).
- `/connectors/disconnect` deletes the row but does not revoke the token at the provider.
- The in-keyboard ConnectorSurface (hold C, with a Month view Arpit asked for on 2026-09-12) runs on the demo calendar routes (`/connector/mockcal/*`). It is not wired to the real `calendar.today` data.
- Tests cover: 503 naming the variable, the consent URL containing exactly the chosen scopes plus identity and S256 PKCE, and per-device status. No test exercises a callback.

**Summary:** the broker is complete code with zero real credentials. It has never completed a real sign-in with any provider.

### 8.6 Setup and credentials still needed

Nothing is needed per provider beyond the two variables and a registered redirect URI.

**Google** (steps given to Arpit on 2026-09-14):

1. Cloud Console, same project as the YouTube key. OAuth consent screen: External, app name, support email. Add the scopes you need (at least `youtube.readonly` if the YouTube tab should personalize; Calendar, Gmail and Meet APIs enabled for those scopes). Add your own Gmail as a test user.
2. Credentials, Create credentials, OAuth client ID, type **Web application**. Add both redirect URIs exactly:
   - `http://127.0.0.1:8787/oauth/google/callback`
   - `https://api.tryglyf.com/oauth/google/callback`
3. Put `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET` in `server/.env`.
4. Do not create the OAuth client through the API-key wizard; it does not set the redirect URIs cleanly.
5. `youtube.readonly` is a sensitive scope, so Google requires app verification before public launch. Testing mode works for up to 100 test users, which covers TestFlight. Start verification early. The verification requirements for the Gmail and Meet scopes were not researched in the notes.

**Notion:** create a public integration at notion.so/my-integrations, set `NOTION_CLIENT_ID` and `NOTION_CLIENT_SECRET`, register the callback URI.
**Slack:** create an app at api.slack.com/apps with the user scopes listed above, set `SLACK_CLIENT_ID` and `SLACK_CLIENT_SECRET`, register the callback URI.
**Others:** the same pattern for GitHub, Linear, Todoist, Calendly, Zoom and Spotify.

As of the last notes (2026-09-16) no OAuth credentials of any kind had been provided.

### 8.7 Gaps against SPEC §6.11 and §6.12

- SPEC says devices hold an opaque `connectionId`. In practice connections are keyed by device id plus provider name, and the device id is sent instead.
- SPEC says "refresh handling server-side; on revocation, glyfs fail with a clean Reconnect state". Refresh is missing; expiry produces the "Connect X in the Glyf app first" error.
- SPEC wants scope minimisation with escalation through a fresh consent screen. Scopes are chosen once at connect time; there is no escalation flow.
- SPEC's revocation UI shows a last-used timestamp per connector. The server does not record when a connection was last used.
- The M6 gate items (Gmail unread list, Notion recents, Drive recents, contacts, Meet link key, verifying via proxy that no token reaches the device) are not done because they need real credentials.

---

## 9. Wallet and crypto (M8)

Crypto is an optional connector shipped in a separate release after v1.0 (SPEC §6.14, §9). Nothing crypto-related is built in the server.

### 9.1 Privy

- On 2026-09-11 Arpit sent the Privy app id and app secret: "for privy , keep them safe in env". Both went into `server/.env` (gitignored, file mode 600, which was confirmed from the directory listing while writing). The assistant advised rotating them because they were pasted in chat.
- On 2026-09-12, after Arpit asked why his keys were not being tested, the app secret was authenticated against Privy's API: app "glyf", wallet auth enabled. Then it was parked.
- Code: `server/src/env.ts` reads `PRIVY_APP_ID` into `env.privyAppId`, which nothing uses. `PRIVY_APP_SECRET` is never read. The comment says: never sent to clients, never used before the crypto connector milestone.
- Rules: the Privy secret stays server-side. The Privy SDK must not be linked into any client binary before M8, because linking changes app size and App Store review scope permanently (SPEC §6.14, §13). The keyboard never holds keys and never signs (SPEC §1.5). The CI secrets guard includes a pattern for the Privy app secret shape.

### 9.2 What M0 Spike B decided for the backend (2026-09-11)

- `privy_flutter` 0.10.1 can sign and broadcast Solana transactions; SPEC §2.1 was stale.
- Plan for swaps: Jupiter `/order` returns a base64 transaction, the app signs with `signTransaction` (not `signAndSendTransaction`), and the backend broadcasts through a `POST /execute` route. This also avoids the iOS plugin silently dropping a custom `rpcUrl`.
- Caveats: omitting `cluster` on iOS silently means mainnet; the plugin needs iOS 17; versioned (v0) transaction signing, which Jupiter returns, is untested and should be tested first at M8.

### 9.3 Fee and contracts

- `GLYF_FEE_BPS=10` is in `.env.example`. SPEC §6.14.2: Jupiter integrator fees are 5 to 10 basis points, Glyf keeps 80%, the default is 10, and the fee must always be displayed in the preview. The variable is not read by any code yet.
- `shared/contracts/intent.schema.json` and `result.schema.json` define the keyboard-to-app handoff (kinds `swap`, `send`, `sign_message`, `dictation`; single use; 120 s TTL; nonce; risk flags). `tools/gen_contracts.mjs` generates Swift, Dart and the server's zod `contracts.generated.ts`. The server does not import the zod schemas yet; the handoff currently runs only between keyboard and app (used by dictation since M3).

### 9.4 Not built

- Server providers and routes listed in SPEC §3: `swap`, `risk`, `jupiter`, `solana`, `storekit`, and `POST /execute`.
- Risk scan (mint and freeze authority, LP lock, holder concentration, token age, honeypot heuristics) behind a `RiskProvider` interface.
- Token resolution, SNS (`.sol`) name resolution, the 3.1.5 legal memo.
- The website's demo chats show a MagicBlock private send and a "Routes by Jupiter" swap panel (2026-09-15). That is static front-end demo UI on the site with no server involvement.

What Arpit still needs to provide for M8: Privy dashboard configuration (Solana enabled), a decision on regions and licensing, and a Jupiter API key when swaps are built.

---

## 10. Security rules and safeguards

### 10.1 Rules and where they are enforced

| Rule | Source | Enforcement in the server |
|---|---|---|
| No API keys or OAuth tokens in any client | SPEC §1.6, §11.2 | All provider calls happen server-side. Places photos and static maps are proxied. `/health` and `/search/status` expose presence only |
| OAuth tokens server-side only | SPEC §6.11 | Stored in the `connections` collection; never returned |
| Privy secret server-side, untouched until M8 | Arpit, 2026-09-11; SPEC §6.14 | Not read by code |
| User glyfs cannot make arbitrary HTTP calls | SPEC §6.8, §11.5 | `tool` steps resolve only against the registry, checked at save, publish and run |
| Every glyf and tool declares what it can see | SPEC §6.8, §11.6 | Schema requires `discloses`; tests enforce it |
| User glyfs cannot touch the wallet | SPEC §6.9 | `validateUserDef` |
| Telemetry is events only, never content | SPEC §11.10, §12 | String fields over 80 chars dropped; only counts stored |
| No content in logs | SPEC §12 | Request logging disabled; routes log ids, lengths and timings |
| Location is not stored | Decision 2026-09-14 | Used per request only |
| No code execution from user input | SPEC §11.12 spirit | Math uses a parser, conditions use a parser, no `eval` anywhere |
| Rendered pages cannot run injected script | Act pages | HTML escaping, `http(s)`-only links, tested |
| Publisher device ids stay private | Fix 2026-09-15 | `/hub/list` and `/skills/creators` strip owner ids; tested |
| Strict JSON, fail closed | SPEC §8.3 | Builder retries once then returns 422 |

Rules owned by the clients and not the server: no AI in secure text fields (SPEC §11.9), vault and clipboard secret refusal (SPEC §11.3, §11.4), memory profiles on device (SPEC §11.11), intents single-use with TTL (SPEC §11.8).

### 10.2 Secrets handling

- Secrets live only in `server/.env`. The root `.gitignore` excludes `.env` and `.env.*` (except `.env.example`). `git ls-files` confirms `server/.env` and `server/data/` are not tracked.
- Standing practice since 2026-09-14: keys go straight into `server/.env`, never into chat. The assistant checks them through `/search/status` or `/health` without seeing values.
- Secrets that were pasted in chat and should be rotated: the OpenRouter key and the Privy app secret (2026-09-11), the YouTube API key (2026-09-14; restrict to YouTube Data API v3 now, IP-restrict to the server's egress address and regenerate after deploy), and the Neon database password (2026-09-15, pasted twice).
- According to the 2026-09-15 snapshot, a `DATABASE_URL` for Neon was also appended to `server/.env` (for future app sign-ups). The server code does not read it.

### 10.3 CI secrets guard (`ci/check_no_secrets.sh`)

- Greps `app/lib`, `app/ios`, `server/src` and `shared` for known key shapes: OpenRouter and OpenAI-style keys, other provider secret keys, Google API keys, Slack tokens, AWS access keys, PEM private key blocks and the Privy app secret shape. Exits 1 on a hit.
- **It currently checks nothing on this Mac.** The `--include='*.{swift,dart,ts,js,json,plist,xcconfig,yaml,yml,env}'` brace pattern is quoted, so grep receives it literally and does not expand the braces. A harmless filename-only test while writing this doc, using the system `/usr/bin/grep` under bash (the script's own shell), matched 0 files with that pattern and 29 files with `--include='*.ts'`. The script therefore always prints its OK line ([known issue 1](#16-known-issues)). GNU grep on a Linux CI runner was not tested.
- It also does not scan `app/android` or `site/`.

### 10.4 Throttles and limits

| Limit | Scope | Where |
|---|---|---|
| Daily run cap per plan | per device, per UTC day, in memory | `lib/meter.ts`; `/glyf/run`, `/act`, `/vocab/generate` |
| Tool requests per minute | per tool id, **global** across devices, in memory | `lib/tools.ts` |
| Model cooldown after HTTP 429 | per model spec, 60 s default, max 600 s | `providers/openrouter.ts` |
| Nominatim spacing about 1.1 s | whole server | `lib/search.ts` (search path only) |
| Upstream timeouts | per call, 4 to 8 s | throughout |
| Request size limits | per field (see section 4) | zod schemas |
| Waitlist cap 50,000 rows | legacy route | `routes/waitlist.ts` |
| OAuth pending state expiry | 10 minutes | `routes/connector.ts` |

Missing: authentication, a global per-IP rate limiter, metering on the Builder routes, and per-device limits on paid search providers. See [section 16](#16-known-issues).

---

## 11. Environment variables

Names only. Values live in `server/.env` (never committed). "Example" says whether the name appears in `server/.env.example` (commented lines count). "Read in" is where the code reads it.

### 11.1 Core and AI

| Variable | Purpose | Required | Default | Example | Read in |
|---|---|---|---|---|---|
| `PORT` | HTTP port | No | `8787` | Yes | `env.ts` |
| `NODE_ENV` | `test` selects in-memory storage; `production` disables Nominatim and disables mini-app pages unless `PUBLIC_BASE_URL` is set | No | unset | No | `lib/store.ts`, `lib/search.ts`, `routes/act.ts` |
| `MOCK_AI` | `true` turns on deterministic offline mode | No | off (the example file sets `true`) | Yes | `env.ts`, `lib/search.ts`, `lib/suggest.ts`, `lib/tools.ts` |
| `OPENROUTER_API_KEY` | OpenRouter models (any id without a known prefix) | One model key is required in live mode | empty | Yes | `env.ts` |
| `GEMINI_API_KEY` | `gemini:` models | See above | empty | Yes | `env.ts` |
| `GROQ_API_KEY` | `groq:` models | See above | empty | Yes | `env.ts` |
| `MISTRAL_API_KEY` | `mistral:` models | See above | empty | Yes (commented) | `env.ts` |
| `INCEPTION_API_KEY` | `inception:` models | See above | empty | Yes (commented) | `env.ts` |
| `CEREBRAS_API_KEY` | `cerebras:` models | See above | empty | Yes (commented) | `env.ts` |
| `FAST_MODELS` | Comma-separated fast-tier chain | No | `openrouter/free` | In comments only | `env.ts` |
| `SMART_MODELS` | Comma-separated smart-tier chain | No | `openrouter/free` | In comments only | `env.ts` |
| `CACHE_TTL_MS` | `/glyf/run` output cache TTL in ms | No | `86400000` (24 h) | No | `env.ts` |
| `FREE_RUNS_PER_DAY` | Free plan daily cap (Plus is 10 times this) | No | `40` | Yes | `env.ts` |

`PORT`, `FREE_RUNS_PER_DAY` and `CACHE_TTL_MS` fall back to their defaults when the value is not a positive number.

### 11.2 Connectors and pages

| Variable | Purpose | Required | Default | Example | Read in |
|---|---|---|---|---|---|
| `OAUTH_REDIRECT_BASE` | Public origin used to build OAuth callback URLs. Production value: `https://api.tryglyf.com` | For production OAuth | `http://127.0.0.1:<PORT>` | Yes (set to the production URL) | `routes/connector.ts` |
| `<PROVIDER>_REDIRECT_URI` | Per-provider callback override. Names: `GOOGLE_REDIRECT_URI`, `NOTION_REDIRECT_URI`, `SLACK_REDIRECT_URI`, `GITHUB_REDIRECT_URI`, `LINEAR_REDIRECT_URI`, `TODOIST_REDIRECT_URI`, `CALENDLY_REDIRECT_URI`, `ZOOM_REDIRECT_URI`, `SPOTIFY_REDIRECT_URI` | No | derived | Only `GOOGLE_REDIRECT_URI` (commented) | `routes/connector.ts` |
| `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET` | Google sign-in and scopes | To enable Google | unset | Yes (commented) | `routes/connector.ts` |
| `NOTION_CLIENT_ID`, `NOTION_CLIENT_SECRET` | Notion | To enable Notion | unset | Yes (commented) | `routes/connector.ts` |
| `SLACK_CLIENT_ID`, `SLACK_CLIENT_SECRET` | Slack | To enable Slack | unset | Yes (commented) | `routes/connector.ts` |
| `GITHUB_CLIENT_ID`, `GITHUB_CLIENT_SECRET` | GitHub | To enable GitHub | unset | No | `routes/connector.ts` |
| `LINEAR_CLIENT_ID`, `LINEAR_CLIENT_SECRET` | Linear | To enable Linear | unset | No | `routes/connector.ts` |
| `TODOIST_CLIENT_ID`, `TODOIST_CLIENT_SECRET` | Todoist | To enable Todoist | unset | No | `routes/connector.ts` |
| `CALENDLY_CLIENT_ID`, `CALENDLY_CLIENT_SECRET` | Calendly | To enable Calendly | unset | No | `routes/connector.ts` |
| `ZOOM_CLIENT_ID`, `ZOOM_CLIENT_SECRET` | Zoom | To enable Zoom | unset | No | `routes/connector.ts` |
| `SPOTIFY_CLIENT_ID`, `SPOTIFY_CLIENT_SECRET` | Spotify | To enable Spotify | unset | No | `routes/connector.ts` |
| `PUBLIC_BASE_URL` | Origin for live mini-app page links (`<base>/p/<id>`) | For pages in production | `http://127.0.0.1:<PORT>` outside production, none in production | No | `routes/act.ts` |
| `GIPHY_API_KEY` | GIF search proxy | To enable GIFs | unset | Yes (commented) | `routes/gif.ts` |

### 11.3 Search suite

| Variable | Purpose | Required | Default | Example | Read in |
|---|---|---|---|---|---|
| `BRAVE_SEARCH_KEY` | Brave web results (primary by decision) | No | unset | Yes (commented) | `lib/search.ts` |
| `SERPER_API_KEY` | Serper Google results (opt-in fallback) | No | unset | Yes (commented) | `lib/search.ts` |
| `YOUTUBE_API_KEY` | YouTube search, durations, popular chart, `yt.search` tool | No | unset | Yes (commented) | `lib/search.ts`, `lib/suggest.ts`, `lib/tools.ts` |
| `GEOAPIFY_KEY` | No-card maps provider and static maps | No | unset | Yes (commented) | `lib/search.ts`, `routes/search.ts` |
| `GOOGLE_PLACES_KEY` | Google Places search, nearby, photos; weather fallback | No | unset | Yes (commented) | `lib/search.ts`, `lib/answers.ts`, `routes/search.ts` |
| `GOOGLE_WEATHER_KEY` | Weather answer card | No | falls back to `GOOGLE_PLACES_KEY` | Yes (commented) | `lib/answers.ts` |
| `OVERPASS_API_BASE` | Self-hosted Overpass endpoint for keyless "near me" on the dev path | No | unset (off) | Yes (commented) | `lib/search.ts` |

### 11.4 Present in files but not read by the server

| Variable | Where it appears | Status |
|---|---|---|
| `PRIVY_APP_ID` | `.env.example`; `server/.env` per the 2026-09-12 snapshot | Read into `env.privyAppId`, never used. Parked for M8 |
| `PRIVY_APP_SECRET` | `.env.example`; `server/.env` per the 2026-09-12 snapshot | Never read. Parked for M8 |
| `GLYF_FEE_BPS` | `.env.example` (value 10); `server/.env` per the 2026-09-12 snapshot | Never read. Swap fee for M8 |
| `DATABASE_URL` | `server/.env` per the 2026-09-15 snapshot (not re-checked) | Never read. Intended for future app sign-ups in Neon |
| `GLYF_API` | Formerly the website's variable pointing at this server | Removed from the site on 2026-09-15 |

<!-- CONTINUE -->

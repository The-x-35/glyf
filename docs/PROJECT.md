# Glyf: project overview

Start here. This is the map of the whole project: what Glyf is, what exists, where everything lives, which accounts and keys it depends on, and where to find the details.

Last updated: Wed 16 Sep 2026 (IST).

---

## 1. What Glyf is

Glyf is an **AI keyboard for iPhone and Android** that replaces the system keyboard and turns any text field into a place to get things done. Website line: **"Type less. glyf more. The AI keyboard that does the rest."**

The unit of action is a **glyf**: one bindable action, such as rewrite this, translate it, find that Notion doc, drop a Meet link or paste my address. The original spec's line was "Every key is a glyf"; the website dropped it on 15 Sep.

Core surfaces, from `SPEC.md`:
1. **Glyf Bar:** hold space to run AI on what you typed. Today: hold still for 0.5s and it opens while your finger is down; glide to move the cursor.
2. **Glyf Keys:** hold a letter to fire the skill bound to it (a purple dot marks bound keys).
3. **Glyf Builder:** describe an action in plain English and get a runnable, bindable glyf with multi-step and conditional logic.
4. **Dictation:** speak anywhere you type (Raw, Clean, Formal).

Plus:
- the **vault** (your address, UPI, wallet, socials and notes, encrypted on the device) and `;shorthand`;
- **search inside the keyboard** (Google answers, YouTube, Maps, contacts);
- **connectors** (OAuth to Google, Notion, Slack and more, plus 28 free keyless tools);
- **act on typed text** (a place card with a map, lists, answers, videos);
- a **Skills hub** and **packs**;
- **autocorrect that learns your words**, including Hinglish and 20 vocabulary packs;
- **themes**;
- a planned **Solana wallet** with Privy and Jupiter swaps (M8, a separate release).

**Competitor:** Acti (openacti.com), which launched in June 2026. Much of the spec is parity with Acti. Glyf's stated edges:
- conditional, multi-step skills;
- memory and tone learning;
- a real wallet;
- its own design (never a 1:1 copy of Acti).

---

## 2. Who and how

- **Owner:** Arpit Singh (arpit@tryglyf.com on the site; GitHub `The-x-35`).
- **How it was built:** Arpit directs, and an AI coding assistant writes, tests and verifies the code in chat sessions, from 11 Sep 2026 on. Every request Arpit made is in [history/messages-from-arpit.md](history/messages-from-arpit.md).
- **Working style and rules:** [WORKING-AGREEMENTS.md](WORKING-AGREEMENTS.md).

---

## 3. Status at a glance

| Area | State |
|---|---|
| iOS app + keyboard | Built and tested on the simulator through M7 cores plus a large feature set beyond the spec. Arpit runs it on his iPhone. TestFlight build 2 uploaded; build 3 prepared (compliance key set) |
| Android app + keyboard | Built and verified on the emulator with iOS styling and the main features. The keyboard still trails iOS: no delete key repeat, multi-touch, accents or caps lock; holding the Translate, Vault or Calendar keys opens the app; the vault refuses 6 field types (see [APPS.md](APPS.md) section 6). Not published |
| Backend (`server/`) | Built and tested (about 90 tests). Runs locally only. Not deployed; `api.tryglyf.com` does not exist yet, so release app builds have no working AI |
| Website (`site/`) | v8, **live on https://www.tryglyf.com** (Vercel, deployed 16 Sep). Waitlist writes to Neon |
| Crypto wallet (M8) | Not started, on purpose. The site demos a private Solana payment UI only |
| Repo | Private GitHub `The-x-35/glyf`, history cleaned of AI attribution |
| Docs | This folder |

Latest test counts (15 Sep): server 90, iOS unit 61, Android unit 17. The iOS UI gate suite (`GlyfGateUITests`) and Flutter tests were passing at their last runs.

---

## 4. Repo map

```
glyf/
  SPEC.md, GLYF_BUILD_PROMPT.md   the build spec (same content; SPEC.md is the working copy)
  README.md                       milestones table, build/run basics, non-negotiables
  app/                            Flutter container app (package "glyf"), shared by iOS and Android
    lib/                          app UI: onboarding, home, build (builder, skills), profile, vault, notes, themes
    ios/GlyfKeyboard/             native Swift keyboard extension (no Flutter inside, ever)
    ios/Runner/                   iOS app host code (bridge, dictation, location)
    ios/RunnerTests/, GlyfM0UITests/   unit tests and UI gate tests (class GlyfGateUITests)
    android/                      Android app + Kotlin keyboard (IME) under app/src/main/kotlin/com/demo/glyf
    assets/                       Inter font, vocabulary packs (vocab/packs.json)
    dict/                         en.glyd dictionary (built from AOSP list + Glyf supplement)
  server/                         Fastify + TypeScript backend: AI, act, search, connectors, hub, telemetry
  site/                           Next.js website for tryglyf.com with the Neon waitlist
  shared/contracts/               JSON Schemas for keyboard↔app payloads (codegen to Swift/Dart/zod)
  shared/typing/                  dictionary format + golden/real autocorrect test cases
  ci/                             guards: no Flutter in the keyboard, no secrets in clients, memory budget
  tools/                          Xcode target wiring, dictionary builder, contracts codegen, share image generator
  docs/                           gate reports, spikes, evidence screenshots, and these docs
```

Not in git: `server/.env`, `site/.env.local`, build output, `docs/evidence/*.mp4` (too big for GitHub), and a stray Xcode template project in `/glyf` with its own git history (the real iOS app is `app/ios`).

---

## 5. Stack

| Part | Tech |
|---|---|
| Container app | Flutter (Dart), Cupertino styling on both platforms, Inter font |
| iOS keyboard | Swift, UIKit keyboard extension, App Group + Keychain, AES-GCM vault |
| Android keyboard | Kotlin `InputMethodService`, canvas-drawn keys on the GPU, AndroidKeyStore vault |
| Backend | Node, Fastify, TypeScript, zod, vitest, SSE streaming, file/memory key-value storage |
| AI | OpenRouter today; Gemini and Groq recommended (provider prefixes, cooldowns) |
| Website | Next.js 15, React 19, TypeScript, framer-motion 11, CSS, Neon serverless driver |
| Database | Neon Postgres (waitlist now; app sign-ups planned) |
| Hosting | Vercel for the site (planned); the server has no host yet |

---

## 6. Identifiers (do not change casually)

| What | Value |
|---|---|
| iOS app bundle ID | `com.demo.glyf` |
| iOS keyboard bundle ID | `com.demo.glyf.keyboard` |
| Android application ID | `com.demo.glyf` (IME `com.demo.glyf/.ime.GlyfIME`) |
| Apple signing team | `XFSL58LKTQ` |
| App Group | `group.so.glyf.shared` |
| Keychain group / vault service | `so.glyf.shared` / `so.glyf.vault` |
| Flutter MethodChannel | `so.glyf/bridge` |
| Logger subsystem | `so.glyf.keyboard` |
| URL scheme | `glyf://` |
| Marketing version / build | 1.0.0 / 3 |

The `so.glyf.*` names are older than the domain. They stay because changing the App Group or Keychain identifiers would point existing installs at an empty container and wipe the vault, notes and settings.

---

## 7. Domains and URLs

| URL | Purpose | State |
|---|---|---|
| `https://www.tryglyf.com` | Website | Live on Vercel (primary domain) |
| `https://tryglyf.com` | Redirects to www (308) | Live |
| `https://api.tryglyf.com` | Backend for release app builds and OAuth callbacks | Not deployed |
| `https://github.com/The-x-35/glyf` | Code (private) | Live |

---

## 8. Accounts, services and keys

| Service | Used for | State / what's needed |
|---|---|---|
| GitHub | Code | Private repo live; push works from the dev Mac over HTTPS with keychain credentials |
| Vercel | Website hosting | Live on www.tryglyf.com since 16 Sep (Root Directory `site`). Confirm `DATABASE_URL` with one real signup |
| Neon Postgres | Waitlist, later app users | Table created. **Rotate the password** (the connection string was pasted in chat twice) |
| Apple Developer / App Store Connect | Signing, TestFlight, later in-app purchases | Build 2 on TestFlight. Plus/Max products and receipt validation not created |
| Google Play Console | Android release | Not set up |
| OpenRouter | AI (free models are slow and rate-limited) | Key in `server/.env`. About $10 of credit was suggested for speed |
| Google AI Studio (Gemini), Groq | Recommended fast, cheap AI | `GEMINI_API_KEY` and `GROQ_API_KEY` not added yet |
| Privy | Wallet (M8) | App id and secret in `server/.env`; dashboard setup pending |
| Google Cloud | YouTube Data API (key provided), optional Places and Weather, OAuth client | Add key restrictions; file a quota extension before launch; regenerate the key after deploy; create the OAuth client |
| Geoapify | Maps and nearby places with no card | `GEOAPIFY_KEY` not created yet |
| Brave Search | Real web result links | Optional `BRAVE_SEARCH_KEY` |
| GIPHY | GIF panel | `GIPHY_API_KEY` not added |
| Notion, Slack, GitHub, Linear, Todoist, Calendly, Zoom, Spotify | OAuth connectors | Client ID and secret pairs not created |
| Mobbin | Design references (MCP connector) | Needs Arpit to authorize it |
| Paper | Design tool (MCP) | Installed; free plan weekly limit hit mid-port |
| MagicBlock, Jupiter, Solana, Circle | Named and shown on the website demo | Check brand guidelines before launch |

Environment variable names are listed in [BACKEND.md](BACKEND.md) (server) and [WEBSITE.md](WEBSITE.md) (site). Values never go in git or in docs.

---

## 9. How to run each part

```bash
cd server && npm install && npm run dev
```
Backend on port 8787. `MOCK_AI=true` gives deterministic outputs for tests only.

```bash
cd site && npm install && npm run dev
```
Website on port 3000. Needs `DATABASE_URL` in `site/.env.local` for the waitlist.

```bash
cd app && flutter build ios --simulator --debug
```
Then install on the iPhone 17 Pro simulator and enable the keyboard in Settings. [APPS.md](APPS.md) has the full recipes, including Android.

---

## 10. Where to read more

| Doc | What's in it |
|---|---|
| [README.md](README.md) | Index of all docs |
| [DECISIONS.md](DECISIONS.md) | Every decision, in order, with Arpit's words |
| [TIMELINE.md](TIMELINE.md) | What happened each day |
| [WEBSITE.md](WEBSITE.md) | The website in full, including all 8 chat scripts and the waitlist |
| [APPS.md](APPS.md) | The iOS and Android apps and keyboards |
| [BACKEND.md](BACKEND.md) | The server: routes, AI, search, connectors, env vars |
| [WORKING-AGREEMENTS.md](WORKING-AGREEMENTS.md) | How Arpit wants the work done; do and don't |
| [OPEN-ITEMS.md](OPEN-ITEMS.md) | Everything pending, blocked or owed |
| [history/](history/) | Every message, daily transcripts and context snapshots |
| `SPEC.md` | The original build spec |
| `docs/SPIKES.md`, `docs/M*-GATE.md` | Spike findings and milestone gate evidence |

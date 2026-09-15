# Glyf

Agentic AI keyboard for iOS. *Every key is a glyf.*

**Design (locked 2026-09-12): WHITE ONLY.** Near-white ground, white cards,
ink text, black pill CTAs, Apple-standard keyboard metrics (260pt: 44 toolbar
+ 216 keys). The accent `#7C5CFF` appears ONLY as the bound-key dot /
selection highlights — exactly like the logo (keycap-`g`, concept 01 in
`glyf-symbol-concepts.svg`, also the app icon). App shell: Acti-style bottom
bar — Home (Glyf Keys + status) · Build (catalog + bind-to-key) · Profile
(vault, prefs) · ＋.

Full specification: [SPEC.md](SPEC.md). Work happens milestone by milestone
(M0–M9, SPEC §9); each milestone has a hard acceptance gate.

## Status

| Milestone | State |
|---|---|
| **M0** — scaffold + spikes | ✅ done — [docs/SPIKES.md](docs/SPIKES.md), [docs/M0-GATE.md](docs/M0-GATE.md) |
| **M1** — daily-usable keyboard + onboarding | ✅ built & gate-tested on simulator — [docs/M1-M2-GATE.md](docs/M1-M2-GATE.md) (hardware re-verify pending) |
| **M2** — Glyf Bar + Glyf Keys + AI backend | ✅ built & gate-tested (mock + live OpenRouter) — same doc |
| **M3** — dictation (intent handoff + on-device speech + Raw/Clean/Formal) | ✅ built & gate-tested on simulator — [docs/M3-M4-GATE.md](docs/M3-M4-GATE.md) (real-mic device pass pending) |
| **M4** — vault & shorthand (encrypted, S-key picker, `;sig`) | ✅ built & gate-tested on simulator — same doc |
| **M5** — Builder + Hub + Packs + step engine + §6.13 map | ✅ built & gate-tested on simulator — [docs/M5-GATE.md](docs/M5-GATE.md) |
| **M6** — connectors | ✅ buildable core (keyless tools · ConnectorSurface on demo calendar · OAuth broker skeleton) — real providers blocked on OAuth client credentials, see same doc |
| **M7** — polish/perf/monetization | ✅ buildable core (paywall + pro flag · tone learning · telemetry sink · funnels) — StoreKit product + receipt validation at ship, see same doc |
| M8 — crypto (SEPARATE release; Privy stays server-side, unlinked until here) | not started, by design (§9) |
| M9 — Android | forbidden before iOS ships (§1) |

Run the backend before using AI features:

```bash
cd server && npm run dev
```

## Repo map (SPEC §3)

```
app/                  Flutter container app (Dart package name: glyf)
app/ios/GlyfKeyboard/ native Swift keyboard extension — NO FLUTTER HERE, ever (§1.1)
app/android/          Android app + native Kotlin keyboard (IME)
server/               Fastify backend (AI, search, OAuth)
site/                 tryglyf.com website — Next.js; Vercel root directory, needs DATABASE_URL
shared/contracts/     JSON Schemas, single source of truth for cross-process payloads
shared/typing/        typing-engine dictionary format + golden test cases
ci/                   guard scripts (Flutter-free keyboard §1.1, no client secrets §1.6)
tools/                repo automation (Xcode target wiring)
docs/                 spike findings + milestone gate evidence
```

## Build & run (simulator — iPhone 17 Pro, SPEC §10)

```bash
cd app
flutter build ios --simulator --debug
xcrun simctl boot "iPhone 17 Pro"
xcrun simctl install booted build/ios/iphonesimulator/Runner.app
xcrun simctl launch booted so.glyf.app
```

Enable the keyboard once per simulator reset:
`Settings → General → Keyboard → Keyboards → Add New Keyboard → Glyf`
(then `Glyf → Allow Full Access` for the gated features).

Logs:

```bash
xcrun simctl spawn booted log stream --level=debug --predicate 'subsystem == "so.glyf.keyboard"'
```

## CI guards

```bash
ci/check_keyboard_clean.sh   # fails if the keyboard extension links/embeds Flutter
ci/check_no_secrets.sh       # fails on key-shaped strings in client/server source
```

`check_keyboard_clean.sh` also runs automatically as the "Glyf CI Guard" build
phase on every Runner build.

## Xcode project wiring

The GlyfKeyboard target is added by a reproducible script, not by hand:

```bash
tools/xcodeproj-env.sh tools/add_keyboard_target.rb
```

## Non-negotiables (SPEC §1 — read before writing code)

1. The keyboard extension is native Swift. Flutter never links into it.
2. The keyboard never holds keys, never signs, never broadcasts.
3. No secrets in any client bundle.
4. Everything must keep working with Full Access off (typing, layouts, local data).
5. Never rebind Return/Shift/Delete/globe; long-press is additive.

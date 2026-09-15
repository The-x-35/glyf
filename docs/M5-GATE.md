# M5 Gate + M6/M7 Buildable Cores — PASSED on simulator (2026-09-12)

Verified on the mandated **iPhone 17 Pro** simulator (iOS 26.5), Xcode 26.6,
backend in MOCK_AI mode (deterministic, zero quota — §8.4).
Official run: **16/16 UI gate tests green in one pass** (00–09 regression +
7 new M5/M6/M7 tests), **30 Swift unit tests** (+6: v3 migration ×3, tone
profile ×3), **31 server tests**, Flutter analyze + widget test clean, both
CI guards green. Evidence: [evidence/m5-gate.mp4](evidence/m5-gate.mp4)
(the 7 new tests on camera — including test05 recovering a wedged keyboard
via the suite's new relaunch self-heal), stills `m5-home/build-tab/profile.png`.

```
test00_GrantFullAccess                     (prereq)
test01…test04, test06…test09               (M1–M4 regression, unchanged)
test05_GlyfKey_T_TranslationHUD            (M5 — T is now the HUD toggle)
test10_TonesPopup_R_RewritesCasual         (M5 §6.13 R)
test11_KeylessWeather_W                    (M6 keyless tool via step engine)
test12_ConnectorSurface_C_InsertsEvent     (M6 §6.12 on the demo calendar)
test13_BuilderMockEndToEnd                 (M5 §6.8 describe→test→save→bind→MINE)
test14_PackApplyWithKeyDiff                (M5 §6.14 → K binding live on Home)
test15_PaywallRenders                      (M7 §6.16 plan card → sheet → dismiss)
```

Getting 13–15 green surfaced one real product bug (fixed) and two automation
findings (SPIKES #24): the Build tab lives in an IndexedStack and never
re-fetched on return — MINE now refreshes via the shell's selected-tab
notifier; Tooltips swallow child text from the a11y tree; icon-button rows
merge into one semantic node.

## M5 — Builder + Hub + Packs + the step engine (§6.8–§6.10, §6.13–§6.14)

| Gate item | Status | Evidence |
|---|---|---|
| Builder: plain English → runnable glyf | ✅ | `POST /builder/generate` — smart tier in STRICT mode: parse → `GlyfDefSchema` → `validateUserDef` moderation; one retry then **422 fail-closed** (§8.3). MOCK mode returns a deterministic single-llm def. `BuilderScreen`: describe (+example chips) → generated steps rendered as cards with **editable prompts** → test drive → name → save → letter-grid bind. test13 runs the whole path |
| Step engine: if / map / tool / ask | ✅ | `server/src/lib/glyfengine.ts` — branch-referenced steps run via recursion, `map` collects JSON arrays, `tool` resolves ONLY against the server registry (§11.5), `ask` fails closed with the question when the var is missing. `evalCond` (no eval): `> < >= <= == != contains` + truthiness. Dotted interpolation `{{docs.0.title}}`, `.length`. 31 vitest incl. branch/tool/ask matrices |
| Catalog: 20 registry glyfs | ✅ | tone/expand/summarize, social reply/hook/emotion/xreply, desi hinglish/formalhindi, keyless weather/quote + M1–M4 set; all Builder-format JSON server-side (§13) |
| §6.13 default key map ships | ✅ | `SettingsStore` schemaVersion 3: t→Translation HUD ★, s→vault, r→tones ★, c→calendar picker, j→emoji ★, p→proofread, e→emotion ★, x→X-reply ★, w→weather, q→quote ★. Migration fills **unclaimed keys only**; a user's own rebinds survive (unit-tested ×3, idempotent) |
| Translation HUD (T ★) | ✅ | 44pt persistent strip above the toolbar (+44pt total height), debounced live translation of the draft on word commits, tap = explicit replace (never automatic), ✕ = off; state persists in shared settings; suppressed in secure fields (§11.9). test05 |
| Tones popup (R ★) | ✅ | Natural/Professional/Casual/Gen-Z grid over the keys → `rewrite.tone` with the `tone` var → normal bar preview (Replace/Insert/Copy). test10 |
| My glyfs: save / publish / delete | ✅ | `GlyfLibrary` — `user.<8hex>` ids, version bump on update, ownership checks; **publish re-runs moderation** (§6.9); Build-tab MINE section with bind/publish/delete |
| Hub: browse / install / creator | ✅ | `/hub/list`, install is **version-pinned** + shows `discloses` for consent before landing (§6.9); creator display name + stats endpoints. Install→bind flow in the Build tab |
| Packs (§6.14) | ✅ | Writer / Operator / Social / Desi — apply merges bindings behind a **key-diff sheet** ("replaces X" per conflicting key); onboarding's pack step now actually applies the chosen pack on finish. test14 |
| Custom names on keys | ✅ | `customTitles` in shared settings, written on bind; keyboard `GlyfCatalog.title(for:)` and the app's catalog both read it |
| Contracts single-source (§7/§3) | ✅ | `tools/gen_contracts.mjs` generates Swift + Dart + zod from `shared/contracts`; `IntentStore` refactored onto generated types. (Codegen bug found + fixed: bare `oneOf:[null,object]` needed handling before the `nested` branch — it was emitting an empty struct and dropping optionality) |

## M6 — Connectors: buildable core ✅ / real providers ⏳ blocked on credentials

| Item | Status | Evidence |
|---|---|---|
| Keyless tools (no login) | ✅ | `weather.now` (Open-Meteo geocode+forecast), `quote.crypto` (CoinGecko), `fx.convert` (Frankfurter), `url.unfurl` (OG tags), `time.now` — real free APIs, per-tool rate limits, registry JSON with `discloses`; MOCK canned outputs for tests. test11 drives W end to end through the if/format/tool pipeline |
| ConnectorSurface (§6.12) | ✅ | search (250ms debounce) · 44pt rows · action bar; opens with the default query ALREADY run; 5-min result cache; inline insert menu **Link / Time+title / Details** (a UIAlertController would clip inside the 260pt keyboard window). test12 inserts a calendar event into the field |
| Demo calendar connector | ✅ | `/connector/mockcal/events` (deterministic, `?q=` filter) exercises the entire surface until OAuth lands |
| OAuth broker skeleton (§6.11) | ✅ skeleton | `/connectors/status` reports per-provider `configured` from env; `/oauth/:provider/start` answers **503 with the exact missing env var** (e.g. `GOOGLE_CLIENT_ID`) — fail-closed, honest. Tokens will live server-side only; devices get opaque connectionIds |
| Google / Notion / Slack live flows | ⏳ **user-blocked** | needs OAuth client credentials in `server/.env` (`GOOGLE_CLIENT_ID/SECRET`, `NOTION_…`, `SLACK_…`). Profile → Connected tools shows the waiting state verbatim |

## M7 — Monetization + polish: buildable core ✅ / store plumbing ⏳ at ship

| Item | Status | Evidence |
|---|---|---|
| Meter + paywall moment (§6.16) | ✅ | server meter (40/day, `FREE_RUNS_PER_DAY`), cap-hit → SSE error "Daily free runs used up" → app catches `capHit` → paywall sheet. test15 renders + dismisses it |
| Pro flag end to end | ✅ | paywall unlock writes `proUnlocked` → shared settings → keyboard `BackendClient` and app runs send `pro: true` → server skips the meter (vitest-covered) |
| StoreKit + receipt validation | ⏳ **ship TODO** | current unlock is local and labeled as such in the sheet's small print; the App Store product + server receipt check replace the same toggle — no call-site changes |
| Tone learning (§6.15) | ✅ | `ToneProfile` — per-bucket accepted/discarded counters ON DEVICE (App Group), never transcripts (§11.11). Accept = bar Replace/Insert/Copy; discard = walking away from a result. Hint activates at **≥3 net accepts** → rides every run as the `{{toneHint}}` var. Profile card shows/reset it. Unit-tested ×3 |
| Telemetry sink (§12) | ✅ | device JSONL stays source of truth; throttled batches → `POST /telemetry` (strings >80 chars dropped server-side — events, never content); `GET /telemetry/funnel` aggregates per-day counts + active devices |
| Onboarding funnel instrumented | ✅ | every step logs view/complete; pack selection applies for real (M5) |

## Deliberately NOT here

- **M8 crypto**: no wallet, no Privy linkage in any client binary — separate
  release by design (§9). Privy credentials sit untouched in `server/.env`.
- **M9 Android**: forbidden before iOS ships (§1).

## Blocked on the user (documented, not faked)

1. **$10 OpenRouter** — free tier answers in ~20s; paid tier is the real UX.
2. **Apple dev team + physical iPhone** — 45MB jetsam gate, ripple Instruments
   profile, haptics, real-mic dictation, §1.3 device probe.
3. **OAuth client credentials** (Google/Notion/Slack) — flips M6 to live.
4. **App Store Connect product + shared secret** — flips M7 pro to real
   purchases with server receipt validation.
5. **Privy dashboard config** — M8, when we get there.

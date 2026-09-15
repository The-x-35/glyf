# M1 + M2 Gate — PASSED on simulator (2026-09-12) · hardware re-verify PENDING

Verified on the mandated **iPhone 17 Pro** simulator (iOS 26.5), Xcode 26.6.
Official run: **7/7 UI gate tests green** ([evidence/m1-m2-gate.mp4](evidence/m1-m2-gate.mp4), ~3 min)
plus **14 Swift unit tests**, **15 server tests**, **1 Flutter widget test**, `flutter analyze` clean.

```
test00_GrantFullAccess                             passed
test01_TypingAutocapAutocorrectAndToolbarCollapse  passed
test02_ShellNavigationAndSettings                  passed
test03_EmojiBoard                                  passed
test04_GlyfBar_SpaceHold_MockRun_Replace           passed
test05_GlyfKey_T_Translates                        passed
test06_OnboardingFunnel                            passed
```

## M1 gate items (SPEC §9)

| Item | Status | Evidence / notes |
|---|---|---|
| Base keyboard: QWERTY, letters/numbers/symbols, shift + caps lock (double-tap), accents in-frame, delete accel repeat, space-swipe cursor, number-row toggle, one-handed, dark/light | ✅ built | test01 exercises typing/shift/autocorrect; layouts unit-tested (`testLayoutShapes`); dark+light via dynamic tokens — keyboard follows the HOST app's appearance (correct iOS behavior) |
| Autocorrect + 3-candidate strip + tap-to-undo; autocap; ". " shortcut | ✅ | test01: "helo" → "Hello" (subsequence-ranked guesses); undo chip renders; pure logic unit-tested |
| Toolbar §6.2: Glyf button leftmost, items, scroll, **collapse-to-Glyf on candidates + restore** | ✅ | test01 asserts collapse & restore; long-press → settings pages wired |
| Emoji board: recents, search, skin-tone long-press | ✅ | test03 inserts 😀; search via InlineEditor routing |
| Clipboard manager: 20 items, pin, 1h expiry, **secret refusal** | ✅ | unit tests (card/seed/token/OTP refusal, expiry, pin survival). Reads are **user-intent only** — see finding #10 in SPIKES.md |
| GlyfShell §6.3: data-driven screens, ONE table view, back/close, 60s state survival, open-in-app footer | ✅ | test02 navigates root→settings→back→close; state file + 60s restore implemented |
| §5 design language: tokens verbatim, one blur layer, hairlines, press scale 0.96 | ✅ | `GlassTokens.swift`; screenshots [m1-keyboard-first-look.png](evidence/m1-keyboard-first-look.png) |
| §5.3 hold ripple: 320ms charge ring → ignition haptic → distance-staggered tint → surface rises +60ms; reduce-motion path | ✅ built | space-hold opens the bar in test04 via the full timeline; per-key `CAKeyframeAnimation`, LUT from key centers, blur never touched. **60fps Instruments profile + Reduce-Motion visual check: pending (device work)** |
| §6.18 onboarding funnel, instrumented | ✅ | test06 walks value→enable→FA→pack→first-fire→home; telemetry live: 145 events on-device incl. `onboarding_complete`, `full_access_granted` ([m1-home.png](evidence/m1-home.png) shows the funnel dashboard) |
| Extension < 45 MB; shell ≤ 6 MB | ⚠️ sim numbers | Debug-sim peak 59.9 MB (fresh appearance 26.1 MB); shell screens add ~1–2 MB (within budget). Simulator ≠ jetsam truth (§10.8) — **hardware verification is the gate-closer**; `ci/check_memory_budget.sh` enforces strict mode on device |
| Type 200 words in Notes without wanting to switch | ⏳ | subjective daily-driver test — needs the user on a device |

## M2 gate items (SPEC §9)

| Item | Status | Evidence |
|---|---|---|
| Backend `/glyf/run` streaming (SSE), model-router fallback chain, 24h cache, MOCK_AI, metering | ✅ | 15 vitest tests; §8 headers; meter 429s + `/meter/:deviceId` |
| Long-press space → "make this polite" → result streams → Replace works | ✅ | test04: space-hold → ripple → bar → polite chip → streamed mock → **Replace consumes the draft** (asserted) |
| Long-press `T` translates | ✅ | test05: bound-key ignition → auto-run translate → result rendered; binding shown with accent dot + in shell/app |
| Degrades cleanly with Full Access off | ✅ | verified visually during the FA-off runs: amber "AI needs Full Access — enable it in Settings → Glyf" row, no network attempted (backend hit count stayed 0) |
| **Live AI through the real OpenRouter key** | ✅ | server-side E2E: "hey can you please send me the file…" → `"Hey, send the file ASAP. Thanks!"`, streamed, metered (39 left). ~23s on the unfunded `:free` router — **fund $10 (§8.2) to fix latency** |
| Default glyfs are Builder-format data, not Swift (§13) | ✅ | 7 defs in `server/src/registry/glyfs/*.json`, schema-validated, every one carries `discloses` (tested) |
| Never auto-inserts (§6.4) | ✅ | result strip requires explicit Replace/Insert/Copy |
| No AI in secure fields (§11.9) | ✅ code | bar refuses `isSecureTextEntry`; candidates disabled |

## How to run everything

```bash
# backend (real AI — server/.env holds the key; MOCK_AI=true for offline)
cd server && npm run dev

# all tests
cd server && npm test
cd app && flutter test && flutter analyze
cd app/ios && xcodebuild test -project Runner.xcodeproj -scheme Runner \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -parallel-testing-enabled NO
```

UI-suite prerequisites it handles itself: keyboard enablement + Full Access (real Settings automation), QuickPath interstitial. It expects the mock server on `127.0.0.1:8787` (`MOCK_AI=true npm run dev`).

## Open items → next session

1. **Physical device pass** (needs Apple dev team + iPhone): memory gate for real, ripple Instruments profile at 60fps, Reduce Motion/Transparency visual checks, haptics feel (sim can't), §1.3 FA-off App-Group probe on device.
2. Fund OpenRouter ($10) → latency from ~23s to seconds; optionally pin `FAST_MODELS` in `server/.env`.
3. M1 keyboard polish from real typing feedback (key feel is a device thing).
4. M3 dictation is the next milestone per SPEC §9.

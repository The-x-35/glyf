# M3 + M4 Gate — PASSED on simulator (2026-09-12) · hardware re-verify PENDING

Verified on the mandated **iPhone 17 Pro** simulator (iOS 26.5), Xcode 26.6.
Official run: **10/10 UI gate tests green** in one recording
([evidence/m3-m4-gate.mp4](evidence/m3-m4-gate.mp4), ~4 min — includes the full
M1/M2 regression suite), plus **24 Swift unit tests**, **15 server tests**,
Flutter analyze/test clean.

```
test00_GrantFullAccess                             passed   (M1–M4 prereq)
test01…test06                                      passed   (M1/M2 regression)
test07_DictationEndToEnd                           passed   (M3)
test08_VaultPickerAndShorthand                     passed   (M4)
test09_VaultBlocksSecrets                          passed   (M4)
```

## M3 — Dictation (§6.6)

Path 1 shipped: **in-app capture + handoff**, built on the real §7 intent
machinery (single-use, 120s TTL, nonce — the same rails M8's swaps will ride).

| Gate item | Status | Evidence |
|---|---|---|
| Mic → record in app | ✅ | keyboard mic writes a `dictation` intent → HostAppOpener → recording sheet (pulsing orb-mic, live transcript, 60s cap) |
| Clean transcript at cursor | ✅ | `GLYF_DICT inserted chars=97` in [evidence/m3-m4-keyboard-logs.txt](evidence/m3-m4-keyboard-logs.txt); test07 asserts the cleaned text lands in the field exactly once |
| Raw / Clean / Formal works | ✅ | three-way toggle in the review step; Clean+Formal are Builder-format glyfs (`dictation.clean` / `dictation.formal`) run server-side; Raw needs no network |
| Under 4s for a 10s clip | ✅ architecture / ⏳ device | recognition streams DURING recording (`SFSpeechRecognizer` partials), so the raw transcript is ready ~instantly at stop; the sheet displays the measured "clean ready in Nms". Real-mic latency needs a physical device (and fast Clean needs the funded OpenRouter tier) |
| §7.3 contract rules | ✅ | 5 IntentStoreTests: TTL expiry refused, replay refused, results single-read, expired results never delivered |
| Privacy (§11) | ✅ | `requiresOnDeviceRecognition` when supported; audio never leaves the device; only chosen TEXT goes to cleanup; mic/speech usage strings say exactly that |

Simulator caveat: the speech stack is unreliable on sim, so the engine has a
fake mode (`--glyf-fake-dictation`, auto-fallback with a visible "simulated"
badge) streaming a canned filler-laden script. The REAL `AVAudioEngine` +
`SFSpeechRecognizer` path is compiled in and needs a device pass.

## M4 — Vault & Shorthand (§6.7)

| Gate item | Status | Evidence |
|---|---|---|
| Preset an address (app-side add/edit only) | ✅ | vault editor in the app (fields/combos/shorthand, bottom-sheet forms); native-side validation |
| Long-press `S` → picker → types | ✅ | test08: hold S → ripple → in-keyboard vault list → tap "Home" → address typed. `S → surface:vault` is the M4 default binding (schema v2 migration adds it to existing installs) |
| `;sig` expands inline | ✅ | test08: `;sig␣` → "— Arpit · tryglyf.com", trigger consumed, autocorrect-style undo armed |
| Blocked field types actually blocked | ✅ | 7-class refusal matrix unit-tested (passwords/cards/seeds/keys/OTP + Aadhaar/PAN/SSN); test09 proves the end-to-end error surface ("Card numbers can't be stored in the vault"); post-run decrypted dump confirmed nothing slipped through |
| Encrypted at rest, keyboard reads via shared Keychain | ✅ | AES-GCM blob in the App Group; 256-bit key in the shared Keychain group (`keychain-access-groups` on both targets); unit test proves ciphertext-on-disk + same-key cross-store decrypt + wrong-key reads-as-empty. **Cross-process decrypt verified live on sim by test08** |
| Combos ("Shipping block") | ✅ | model + editor + one-tap insert in the shell; comboText unit-tested |

## New automation findings (added to the recipe book)

- Flutter **modal bottom sheets** report frames in content coordinates once the
  keyboard lifts them — element taps land on the barrier/keys. Recipes: make
  form sheets non-dismissible (product win too), avoid typing in modals under
  test (prefill hooks), or tap by screen geometry.
- `Semantics(identifier:)` on Flutter `TextField`s DOES surface to XCUITest
  (`textFields["vault-value-field"]`) — use it over index games.
- A wedged sim test session (zero xcodebuild output, runner alive) is cured by
  `simctl shutdown` + boot — never by waiting.

## How to run

```bash
cd server && MOCK_AI=true npm run dev          # deterministic backend for the suite
cd app/ios && xcodebuild test -project Runner.xcodeproj -scheme Runner \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO
```

## Open items → next session

1. Device pass now covers: memory gate (sim-debug peak 61 MB incl. dictation flow), real-mic dictation latency, ripple profiling, haptics, Reduce Motion/Transparency.
2. **M5 next** (Builder + Hub + Packs + non-connector catalog) — the biggest milestone; the step-engine schema and per-glyf `discloses` plumbing it needs are already live.
3. Codegen debt (§7 "generate both sides"): Intent/Result structs are hand-mirrored in Swift; generator lands with M5's contract growth.

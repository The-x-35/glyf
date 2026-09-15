# M0 Gate — PASSED (2026-09-11)

SPEC §9 M0 gate: *"keyboard appears in simulator, types letters, writes a file the app reads. Both spikes answered in docs/SPIKES.md."*

Verified on the mandated **iPhone 17 Pro** simulator (iOS 26.5, UDID `04652CB6-3351-4F5E-934D-EF7A0B7F8585`), Xcode 26.6.

| Gate item | Status | Evidence |
|---|---|---|
| Flutter app + Swift extension in one Xcode project | ✅ | `app/ios/Runner.xcodeproj` — `GlyfKeyboard` appex target wired by [tools/add_keyboard_target.rb](../tools/add_keyboard_target.rb) |
| Keyboard appears and types letters | ✅ | `GlyfM0UITests.testA` types "glyf mo" on the Glyf keyboard — passing run in [evidence/m0-gate.mp4](evidence/m0-gate.mp4) |
| App Group bidirectional read/write | ✅ | same test: keyboard `keyboard-ping.json` → app card; app `app-pong.json` → rendered in the keyboard status strip |
| Memory logging on every keyboard appearance | ✅ | `GLYF_MEM appearance=… footprint_mb=…` lines in [evidence/m0-keyboard-logs.txt](evidence/m0-keyboard-logs.txt) (21.5 MB first appearance) |
| CI check: no Flutter in the keyboard target | ✅ | [ci/check_keyboard_clean.sh](../ci/check_keyboard_clean.sh) — runs standalone **and** as the "Glyf CI Guard" build phase on every Runner build |
| CI check: no client-side secrets | ✅ | [ci/check_no_secrets.sh](../ci/check_no_secrets.sh) |
| Spike A answered | ✅ | [SPIKES.md](SPIKES.md) — works on iOS 26 via modern-selector responder walk, end-to-end test green |
| Spike B answered | ✅ | [SPIKES.md](SPIKES.md) — `privy_flutter` 0.10.1 signs + broadcasts Solana; spec §2.1 stale |
| Screen recording of the gate flow | ✅ | [evidence/m0-gate.mp4](evidence/m0-gate.mp4) (clean full-suite pass, ~22 s of tests) |

Final suite result (3 consecutive green runs):

```
Test Case '-[GlyfM0UITests testA_TypingAndAppGroupBridge]' passed
Test Case '-[GlyfM0UITests testB_SpikeA_OpenHostAppFromSettings]' passed
Executed 2 tests, with 0 failures (0 unexpected) in 21.966
```

## Reproduce

```bash
cd app && flutter build ios --simulator --debug
xcrun simctl boot "iPhone 17 Pro" ; open -a Simulator
xcrun simctl install booted build/ios/iphonesimulator/Runner.app
cd ios && xcodebuild test -project Runner.xcodeproj -scheme Runner \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:GlyfM0UITests/GlyfM0UITests/testA_TypingAndAppGroupBridge \
  -only-testing:GlyfM0UITests/GlyfM0UITests/testB_SpikeA_OpenHostAppFromSettings
```

Prerequisites the tests handle themselves: enabling the keyboard + Full Access (driven through the real Settings UI), dismissing the QuickPath interstitial. Prerequisite they don't: software keyboard must not be suppressed by hardware-keyboard mode — `defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool false` once, with Simulator.app open.

The §1.3 probe (App Group with Full Access OFF — simulator says it works; device check pending in M1) runs separately:

```bash
xcodebuild test -project Runner.xcodeproj -scheme Runner \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:GlyfM0UITests/GlyfM0UITests/testZProbe_AppGroupWithFullAccessOff
```

## Iteration gotchas (cost real time — see SPIKES.md "Bonus findings")

- Stale extension process survives reinstall → `pkill -f GlyfKeyboard.appex`
- `xcodebuild test` may skip reinstalling the app when only the appex changed → `xcrun simctl install booted <DerivedData path>/Runner.app`
- Appex embed phase must precede Flutter's "Thin Binary" phase or Xcode reports "Cycle inside Runner" → `tools/fix_phase_order.rb`

## Not in M0 (deliberately)

Per SPEC §14: no real keyboard UI (M1), no backend code (M2), no Privy SDK linked (M8), no contract codegen (M2). The M0 keyboard/app screens are throwaway scaffolds labeled as such in-source.

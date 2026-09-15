# M0 Spike Findings

Date: 2026-09-11 · Environment: Xcode 26.6, iOS 26.5 simulator (iPhone 17 Pro), Flutter 3.44.8 / Dart 3.12.2, macOS 26 (Darwin 25.6)

Both spikes are **answered**. Spike A: yes, with a specific workaround verified end-to-end on iOS 26. Spike B: the spec was stale — the Flutter SDK can sign **and** broadcast Solana transactions; no native bridge needed.

---

## Spike A — Can the keyboard extension open the container app?

**Answer: YES on iOS 26.5 (simulator-verified, end to end), via one specific strategy — with the fallback UX still mandatory because the strategy is unsupported API behavior.**

### Method
Empirical, not speculative: `GlyfM0UITests.testB_SpikeA_OpenHostAppFromSettings` focuses a text field in the **Settings** app (so the container app is genuinely backgrounded), switches to the Glyf keyboard, taps the `APP↗` key, and asserts that (a) the app reaches `runningForeground` and (b) the `glyf://intent?id=…` deep link renders in the app. Verified green three consecutive runs.

### Strategies tried, in order ([HostAppOpener.swift](../app/ios/GlyfKeyboard/Bridge/HostAppOpener.swift))

| # | Strategy | Result on iOS 26.5 |
|---|---|---|
| 1 | `NSExtensionContext.open(_:completionHandler:)` — the documented API | `success=false` (refused for keyboards, as historically) |
| 2 | Responder-chain walk → live `UIApplication` instance → legacy `openURL:` via `perform(_:with:)` | UIApplication **is** still reachable in the chain, but the legacy `openURL:` selector **no longer exists** → dead |
| 3 | Same `UIApplication` instance → **`openURL:options:completionHandler:` invoked through a `@convention(c)` function pointer** (3 args — `perform` can't do it) | **WORKS. App foregrounds, deep link delivered.** |
| 4 | Any other responder answering `openURL:` | none exist in the chain |

Log evidence (`docs/evidence/m0-keyboard-logs.txt`):

```
GLYF_SPIKE_A extensionContext.open success=false
GLYF_SPIKE_A responderApplication legacy openURL: unavailable
GLYF_SPIKE_A responderApplicationModern invoked
GLYF_SPIKE_A_RESULT foregrounded=true
GLYF_SPIKE_A_RESULT deepLinkShown=true
```

### Implementation notes (hard-won)
- **Thread matters.** `extensionContext.open`'s completion arrives off-main; the responder walk must be dispatched to the main queue or delivery silently fails.
- The intent is written to the App Group **before** any open attempt, so if every strategy fails the app still finds the pending intent on manual launch. That is the designed degradation.

### Risk assessment
- This is unsupported behavior reached through the responder chain. Apple removed strategy 2 somewhere in iOS 18–26; strategy 3 can vanish in any release. **Treat as a per-iOS-beta regression test** (the UI test is exactly that) and keep the fallback UX shipping-quality: an "Open Glyf to continue" card in the keyboard, intent ID already in the App Group (clipboard copy requires Full Access, so the card copy is "open the app" — the app reads the pending intent itself).
- App Review: the call is dynamic (`sel_registerName` + IMP cast), not a linked private symbol, and major shipping keyboards do equivalents. Non-zero review risk; worth a note in the M7 submission memo. Swaps/sends/dictation must never *depend* on it working.

### Still needs
- Re-verification on physical hardware at M1 (same test target runs on device).
- Re-run on every new iOS point release; the test suite is the canary.

---

## Spike B — Privy Flutter: Solana `signTransaction`?

**Answer: SPEC §2.1 IS STALE — `privy_flutter` CAN sign *and* broadcast Solana transactions. No native platform-channel bridge needed.** Verified in the shipped package source (Dart + the iOS/Android native bridge code inside the plugin), not just docs.

Source of truth: `privy_flutter 0.10.1` (latest on pub.dev, published 2026-07-14, verified publisher privy.io), archive extracted and read file-by-file.

### API surface (verified in Dart source)
`lib/src/modules/embedded_solana_wallet_provider/embedded_solana_wallet_provider.dart`:

```dart
Future<Result<String>> signMessage(String message);
Future<Result<String>> signTransaction(Uint8List transaction);          // returns base64 signed tx
Future<Result<String>> signAndSendTransaction({
  required Uint8List transaction,
  SolanaCluster? cluster,      // mainnet | devnet | testnet
  String? rpcUrl,
  SendOptions? sendOptions,    // skipPreflight, preflightCommitment, maxRetries, minContextSlot
});                                                                     // returns tx signature
```

Solana wallet creation exists too: `PrivyUser.createSolanaWallet({bool allowAdditional})` + `embeddedSolanaWallets`. Solana transaction support landed in **0.5.0** per the package CHANGELOG. Input format: raw **`Uint8List`** of a serialized *unsigned* transaction — the bundled example builds `[0x00 sig-count byte] + compiled message bytes` using `package:solana` and gets a Solscan-viewable signature back.

### Verified caveats (in the plugin's own iOS bridge source)
1. **iOS drops `rpcUrl`.** `ios/.../WalletHandler.swift` parses the arg and never passes it to the native SDK (Android does pass it). Custom RPC broadcast on iOS ⇒ use `signTransaction` and broadcast through our backend instead — which is what Glyf's architecture wants anyway (§4: app signs, backend `POST /execute`).
2. **Omitting `cluster` on iOS silently means mainnet.** Always pass `cluster` explicitly.
3. **iOS minimum 17.0** for the plugin (project currently builds at iOS 15 — raise the floor when M8 links Privy).
4. Plugin pins native PrivySDK 2.12.0 (CocoaPods exact / SPM `from:`); native iOS SDK is at 2.16.2 (2026-09-11) which fixes an App Store submission issue (ITMS-91065, bundled SwiftyJSON). Under CocoaPods we may need a version override at M8.
5. GitHub repo for the Flutter SDK is private (404) — pub.dev archive is the only source access; no public issue tracker.

### Consequences for the plan
- M8 gets **simpler**: keep `privy_flutter` as the wallet layer, drop the native-bridge contingency, keep `SwapProvider` abstraction as planned.
- `SolanaCluster.devnet` exists ⇒ wallet-op testing on devnet is possible even though Jupiter swaps remain mainnet-only (§2.2 unchanged).
- Signing flow for swaps: Jupiter `/order` returns a base64 transaction → decode to bytes → `signTransaction` (NOT `signAndSendTransaction`) → backend `/execute` broadcasts. This also sidesteps the iOS `rpcUrl` gap.

### Still needs a live test (requires a Privy app ID — user action before M8)
1. Login → `createSolanaWallet()` → devnet `signAndSendTransaction` end-to-end (dashboard must have Solana enabled; TEE wallet migration path `migrateWalletsIfNeeded` untested).
2. Versioned (v0) transaction signing — the example uses legacy message format; Jupiter returns v0. **Test this first at M8; it's the one real unknown.**
3. Whether any Privy SDK init constraints matter inside the keyboard-extension *context* — irrelevant if we hold the line that only the app touches Privy (§1.5), which we must.

---

## Bonus findings (things M0 surfaced that the spec should absorb)

1. **§1.3 partially validated, device check pending.** With Full Access **OFF**, the keyboard still read/wrote the App Group container on the simulator (`GLYF_FA_PROBE pingUpdatedWithFullAccessOff=true`, via `testZProbe_AppGroupWithFullAccessOff`). Apple's docs historically gate the shared container behind open access, and the simulator does not enforce the extension sandbox faithfully (§10.8). **Re-run the probe on hardware in M1.** If a device blocks it, §1.3's "vault/clipboard/snippets work with Full Access off" needs a redesign (extension-local storage + one-way import when FA is granted).
2. **Enabled keyboards live in `.GlobalPreferences` on iOS 26**, not `com.apple.Preferences`. Working pre-enable for CI:
   `xcrun simctl spawn booted defaults write .GlobalPreferences AppleKeyboards -array "en_US@sw=QWERTY;hw=Automatic" "emoji@sw=Emoji" "so.glyf.app.keyboard"` then reboot the sim. The robust path (and the only one that grants Full Access) is the Settings-UI automation in `GlyfM0UITests.enableGlyfInSettings()` / `setFullAccess(_:)`.
3. **First keyboard presentation is blocked by the QuickPath education interstitial** ("slide to type" + Continue). Any automation must dismiss it (`dismissKeyboardInterstitials()`).
4. **Headless sims suppress the software keyboard** (hardware-keyboard mode). Required: `defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool false` (+ per-device `DevicePreferences` entry) and Simulator.app attached.
5. **Two stale-binary traps when iterating on the extension:** (a) iOS keeps the extension *process* alive across app reinstalls — `pkill -f GlyfKeyboard.appex` after installing; (b) `xcodebuild test` sometimes skips reinstalling an app whose main binary didn't change even when the appex did — `xcrun simctl install booted <DerivedData Runner.app>` forces it.
6. **Memory baseline (simulator, debug):** scaffold keyboard first appearance 21.5 MB → ~40 MB after several presentations in one process. Simulator numbers aren't budget-truth, but the growth pattern (VC re-instantiated per presentation) needs an Instruments look in M1. Also: `GLYF_MEM` logs at `.info` are stream-only — **move to `.log`/Default level in M1** so `log show` can retrieve them after the fact.
7. **Xcode "Cycle inside Runner"** when an appex embed phase is added to a Flutter project: the embed must run *before* Flutter's "Thin Binary" phase — automated in [tools/fix_phase_order.rb](../tools/fix_phase_order.rb).
8. Flutter 3.44's iOS template is **UIScene-based** with `FlutterImplicitEngineDelegate`; deep links arrive via `SceneDelegate` (`willConnectTo` / `openURLContexts`), not `AppDelegate.application(_:open:)`.
9. `glyf-ripple-prototype.html` is referenced by SPEC §5.3 but does not exist in the repo — the ripple was implemented from the §5.3 table directly in M1 (`Surfaces/RippleEngine` logic inside `KeyboardView.igniteRipple`).

## M1/M2 session findings (2026-09-12)

10. **Reading the pasteboard from a keyboard is a UX landmine.** `UIPasteboard.general.string` on every keyboard appearance fires Apple's paste-permission prompt OVER the keyboard, repeatedly. Redesign that shipped: `changeCount` probing (prompt-free) on appearance; actual reads only at user-intent moments — opening the clipboard screen, or the Glyf Bar falling back to clipboard input. SPEC §6.1's clipboard manager should note this constraint.
11. **iOS 26 Full Access automation recipe** (took four attempts): the switch's accessible frame spans the whole row, so `switch.tap()` hits the label and does nothing — tap the coordinate at the frame's right edge (`dx: 0.94`); the confirmation is a real alert whose confirm button is tapped by index (its label is "Allow"). In `GlyfGateUITests.ensureFullAccess()`.
12. **Flutter PageView vs XCUITest**: semantics frames are reported in scroll-content coordinates, so `isHittable`, element frames, and coordinate taps on matched elements are all unreliable across pages; label queries also match offscreen sibling pages, and Flutter merges card rows into single semantic nodes (exact-match queries fail). Working recipe: drive multi-page Flutter flows by normalized screen coordinates against stable layout slots and assert outcomes (plus the funnel's own telemetry). Single-page Flutter screens automate fine.
13. **Memory samples (sim, debug)**: fresh keyboard appearance 26.1 MB → 59.9 MB peak over a full suite (bar + emoji + shell cycling). Shell screens add ~1–2 MB each (6 MB budget honored); emoji board ~5 MB. Simulator numbers are NOT jetsam truth — device pass decides the 45 MB gate; watch the growth-across-presentations pattern (VCs are re-instantiated per presentation).
14. **Keyboard appearance follows the HOST app** (`keyboardAppearance` of the focused field), not the system: a dark host renders the dark palette even in system-light. Correct per-iOS behavior; both palettes are dynamic tokens.
15. **`log stream` (not `log show`) is still the only reliable GLYF_MEM capture** on this simulator even at Default level — the gate tooling captures via a background stream (`docs/evidence/m1-m2-keyboard-logs.txt`).

## Redesign session findings (2026-09-12, white/Acti overhaul)

16. **The keyboard-height saga** (Apple-acknowledged, no sanctioned fix): iOS hands extensions arbitrary/cached heights (444pt here) and ignores height constraints; `self.inputView` is NIL in viewDidLoad so `allowsSelfSizing` silently no-ops there (the VC's `view` IS the UIInputView — set it on that); `preferredContentSize` ignored. What shipped: transparent `PassThroughRoot` (hitTest nil above content) + the real keyboard BOTTOM-ANCHORED at exactly 260pt (toolbar 44 + keys 216, Apple metrics) + a 999 view-height request. After a clean rebuild iOS actually adopted 260 (`GLYF_KB height=260`), and the pass-through root guarantees the look even when it doesn't.
17. **Keyboard appearance is forced light** (`overrideUserInterfaceStyle = .light`) — white-only product decision; host-app appearance no longer leaks in.
18. **Phantom text sessions**: when the host app relaunches (or during teardown), the keyboard can be attached to a session whose document ACCEPTS inserts (verification against `documentContextBeforeInput` even passes!) while the visible field shows nothing — and "lost" inserts can be buffered and FLUSH later, doubling text. Delivery rule that survived: TAKE-ONCE, INSERT-ONCE — consume the §7 result before the single insert, never retry inserts. Delivery triggers: viewDidAppear (+0.5s) and textDidChange.
19. App icon pipeline: `NSImage.lockFocus` renders at the Mac's 2× backing scale — `sips -z 1024 1024` after; all appiconset sizes generated from the one 1024 render.

## M5–M7 session findings (2026-09-12, "finish everything" push)

20. **Codegen `oneOf` ordering bug**: in `tools/gen_contracts.mjs`, a bare `"error": {oneOf:[{type:"null"},{type:"object",…}]}` also satisfies the `nested` check, and the nested branch recursed into the *oneOf wrapper* (no `properties`) — emitting an EMPTY `Result_Error` struct and dropping optionality. Fix: handle `prop.oneOf` before `t.nested` in `collect()`. Symptom that caught it: `IntentStore` stopped compiling against the regenerated contracts.
21. **UIAlertController clips inside the keyboard window** — the extension's window is only as tall as the keyboard, so action sheets get cut off. ConnectorSurface's insert menu is an inline overlay (pill row over the table) instead.
22. **Flutter reads settings through `SettingsStore.load()`** (SettingsStore + ToneProfile compiled into the Runner target): the bridge's `readSharedSettings` returns the MIGRATED view, so §6.13 defaults appear in the app even before the keyboard's first run, and fresh installs see the full default map instead of `{}`.
23. **Old server process ≠ new routes**: the LIVE server running since M2 answered `/health` fine but 404'd every M5 route — always restart the backend after adding routes before blaming the client. (Mock suite runs `MOCK_AI=true npm start`; restore plain `npm start` after.)
24. **Two more Flutter⇄XCUITest traps** (found via the M5 suite): (a) a `Tooltip` with a non-empty message swallows its child's text into the tooltip's own semantics node — the letter-grid "Z" stopped matching `staticTexts` the moment Z became bound (bound keys had tooltips) — don't put Tooltips on things tests must find; (b) a card `Row` that mixes `Text`s with `IconButton`s gets MERGED into one semantic node, so the texts are not standalone `StaticText`s — query `descendants(matching: .any)` with a `label CONTAINS` predicate for such rows. Diagnose these with a mid-test `simctl` screenshot: if the text is visibly painted but `staticTexts` misses it, it's a merge, not a timing problem.

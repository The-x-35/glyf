# Glyf apps: the complete reference (iOS, Android, Flutter container app)

This file is the single place to learn everything about the Glyf **apps**: the Flutter container app, the native iOS keyboard extension, and the Android app with its native keyboard (IME). It covers what exists, how it works, where the code lives, every decision and why, what was tried and dropped, the current status, and what is still pending.

It does **not** document the backend (`server/`) or the website (`site/`) beyond how the apps use them. Those have their own docs.

Written on 2026-09-16 from the repo state at that time (latest commit `cc46b39`), the assistant's dated working notes, the gate docs in `docs/`, and the chat history exported to `docs/history/`. Where a claim could not be checked, it says so. Section 13 lists everything that could not be verified.

**Conventions**

- Times are India Standard Time (IST). The build ran from 2026-09-11 to 2026-09-16.
- "Arpit" is the project owner. "The assistant" is the AI coding assistant that wrote most of the code with him.
- Quotes from Arpit are verbatim (typos included) from `docs/history/messages-from-arpit.md`.
- Status words: **Active** (current behavior or rule), **Superseded** (replaced by a later decision), **Pending** (not done yet), **Blocked** (waiting on something only Arpit can provide).
- File paths are relative to the repo root.
- No secrets appear in this file. Environment variables are named, never valued. Real keys live only in `server/.env` and `site/.env.local`, which are gitignored.

## Contents

1. [Quick reference](#1-quick-reference)
2. [What Glyf is](#2-what-glyf-is)
3. [Architecture](#3-architecture)
4. [Non-negotiables and hard rules](#4-non-negotiables-and-hard-rules)
5. [Features, one by one](#5-features-one-by-one)
6. [iOS vs Android parity](#6-ios-vs-android-parity)
7. [Acti feature parity inventory](#7-acti-feature-parity-inventory)
8. [Design system and design history](#8-design-system-and-design-history)
9. [Milestones M0 to M9](#9-milestones-m0-to-m9)
10. [Build, run, test, release](#10-build-run-test-release)
11. [Pending work, known issues, what Arpit owes](#11-pending-work-known-issues-what-arpit-owes)
12. [Decision log (apps)](#12-decision-log-apps)
13. [Could not verify](#13-could-not-verify)

---

## 1. Quick reference

| Item | Value | Where it is set |
|---|---|---|
| iOS app bundle ID | `com.demo.glyf` | `app/ios/Runner.xcodeproj/project.pbxproj` (Runner, 3 configs) |
| iOS keyboard extension bundle ID | `com.demo.glyf.keyboard` | same file (GlyfKeyboard, 3 configs) |
| Android applicationId / namespace | `com.demo.glyf` | `app/android/app/build.gradle.kts` |
| Android IME component | `com.demo.glyf/.ime.GlyfIME` | `app/android/app/src/main/AndroidManifest.xml` |
| App Group (iOS) | `group.so.glyf.shared` | `app/ios/Runner/Runner.entitlements`, `app/ios/GlyfKeyboard/GlyfKeyboard.entitlements` |
| Keychain access group (iOS) | `$(AppIdentifierPrefix)so.glyf.shared` | both entitlements files |
| Vault key (iOS Keychain) | service `so.glyf.vault`, account `vault-key-v1` | `app/ios/GlyfKeyboard/Engine/VaultStore.swift` |
| Vault key (Android Keystore) | alias `so.glyf.vault` | `app/android/app/src/main/kotlin/com/demo/glyf/store/VaultStore.kt` |
| Flutter to native MethodChannel | `so.glyf/bridge` | `app/lib/core/bridge.dart`, `app/ios/Runner/GlyfBridge.swift`, `app/android/.../GlyfBridge.kt` |
| Deep link scheme | `glyf://` | `app/ios/Runner/Info.plist`, Android manifest intent filter |
| iOS log subsystem | `so.glyf.keyboard` | keyboard `Logger` instances |
| Dart package name | `glyf` | `app/pubspec.yaml` |
| Apple developer team | `XFSL58LKTQ` (Console Labs India Private Limited) | pbxproj, Runner + GlyfKeyboard, all configs |
| Version | 1.0.0, build 3 | `app/pubspec.yaml` (`1.0.0+3`); pbxproj `MARKETING_VERSION = 1.0.0`, `CURRENT_PROJECT_VERSION = 3` everywhere |
| iOS deployment target | 15.0 | pbxproj |
| Android minSdk | `maxOf(26, flutter.minSdkVersion)` (26+ for `java.time`) | `build.gradle.kts` |
| Backend in debug builds | iOS simulator `http://127.0.0.1:8787`, Android emulator `http://10.0.2.2:8787` | `SettingsStore.swift`, `Stores.kt`, `glyf_api.dart` |
| Backend in release builds | `https://api.tryglyf.com` (**not deployed yet**) | same files |
| Test-only bundle IDs | `so.glyf.app.m0uitests` (UI tests), `so.glyf.glyf.RunnerTests` (unit tests) | pbxproj (simulator only, never shipped) |
| Gate simulator | iPhone 17 Pro, UDID `04652CB6-3351-4F5E-934D-EF7A0B7F8585` (on Arpit's Mac) | `docs/M0-GATE.md` |
| Android emulator | AVD `Avici_API_36` (on Arpit's Mac) | assistant notes |
| Toolchain at build time | Xcode 26.6, iOS 26.5 simulator runtime, Flutter 3.44.8 / Dart 3.12.2, AGP 9.0.1, Kotlin 2.3.20, Gradle 9.1.0, Java 17 | `docs/SPIKES.md`, `app/android/settings.gradle.kts`, `gradle-wrapper.properties` |
| GitHub | private repo `The-x-35/glyf`, first push 2026-09-16 | assistant notes |

---

## 2. What Glyf is

Glyf is an AI keyboard for iPhone and Android. The website line is "Type less. Glyf more." The original spec line, still shown in the app's first onboarding screen, is "Every key is a Glyf."

A **Glyf** is one bindable action: rewrite this, translate it, proofread, paste my address, find a café. You fire Glyfs from inside the keyboard:

- **Hold the space bar** on what you typed: Glyf acts on it (place card with a map, list, answer, video, or a rewrite). On an empty field the hold opens the **Glyf Bar** (a prompt plus quick actions).
- **Hold a bound letter** (a key with a small purple dot): its Glyf runs and shows the result above the keys.
- **The g button** (top left of the keyboard) opens an in-keyboard menu: Search, Glyfs, Glyf Keys, Connectors, Vault, Shorthand, Clipboard, Packs, Settings.
- **Toolbar**: Search (Google/YouTube/Maps/Contacts), Clipboard, Vault, Dictation, Emoji, Translate, Settings.

Underneath it is a real keyboard: on-device autocorrect and next-word prediction that learn your words, vocabulary packs (including Hinglish), glide-to-move-cursor, shorthand like `;sig`, an encrypted vault, notes, clipboard history, emoji search, themes, and dark mode.

The product spec is `SPEC.md` (a working copy of the original `GLYF_BUILD_PROMPT.md`, with sections 1.4, 6.1, 6.4 and 6.9 updated during the build). The competitor it was built against is **Acti**; section 7 lists what was matched.

---

## 3. Architecture

### 3.1 The pieces

```
                 iPhone                                         Android phone
┌───────────────────────────────────────────┐   ┌─────────────────────────────────────────┐
│ Runner.app (Flutter container app)        │   │ com.demo.glyf (one package, one process │
│  lib/: onboarding, Home, Build, Profile,  │   │  when both are running)                 │
│  vault/notes editors, dictation sheet     │   │  MainActivity: the same Flutter app     │
│  ios/Runner: GlyfBridge, DictationEngine, │   │  GlyfBridge.kt: same channel methods    │
│  LocationOnce, AppDelegate, SceneDelegate │   │  ime/GlyfIME.kt: native Kotlin keyboard │
│                                           │   │  store/*.kt: settings, vault, notes     │
│  PlugIns/GlyfKeyboard.appex (Swift only,  │   │                                         │
│  separate process, ~40 to 70 MB cap)      │   │  shared state: filesDir/bridge/*.json   │
│                                           │   │  typing memory: noBackupFilesDir/typing │
│  shared state: App Group group.so.glyf.   │   └────────────────────┬────────────────────┘
│  shared, folder bridge/ + shared Keychain │                        │
└─────────────────────┬─────────────────────┘                        │
                      │ HTTPS (dev: HTTP to the Mac)                 │
                      └──────────────────────┬───────────────────────┘
                                             ▼
                          server/ (Fastify + TypeScript): AI, search,
                          tools, OAuth tokens, meter, Skills hub, telemetry
```

- **Flutter container app** (`app/lib`, Dart package `glyf`). Runs unchanged on iOS (Runner) and Android (MainActivity). It owns onboarding, the Home tab (live key map and binding editor), the Build tab (Builder, Packs, your Glyfs, Skills), the Profile tab (plan, settings, vault, notes, vocabulary, themes, contacts search, nearby search, connected tools, tone profile), the dictation recording sheet, and the paywall. The only Dart dependency beyond Flutter is `cupertino_icons`. All platform work goes through the app's own `so.glyf/bridge` channel, not third-party plugins.
- **iOS keyboard extension** (`app/ios/GlyfKeyboard`). Native Swift and UIKit, `UIInputViewController` subclass `GlyfKeyboardViewController`. It is a separate process with a tight memory cap, embedded in `Runner.app/PlugIns/GlyfKeyboard.appex`. **No Flutter, ever** (SPEC 1.1). A build phase ("Glyf CI Guard") fails the Runner build if Flutter links into it.
- **iOS native host code** (`app/ios/Runner`): `GlyfBridge.swift` (MethodChannel handler), `DictationEngine.swift` (on-device speech), `LocationOnce.swift` (one coarse location fix), `AppDelegate.swift` (test launch arguments, channel attach), `SceneDelegate.swift` (deep links arrive through the scene lifecycle in Flutter 3.44's template).
- **Swift files compiled into more than one target** (so the app and keyboard share one implementation): `Bridge/AppGroupStore.swift`, `Bridge/IntentStore.swift`, `Bridge/Contracts.generated.swift`, `Engine/SecretScanner.swift`, `Engine/VaultStore.swift`, `Engine/SettingsStore.swift`, `Engine/ToneProfile.swift`, `Engine/NotesStore.swift`. The list lives in `tools/sync_keyboard_files.rb` (`RUNNER_SHARED`).
- **Android** (`app/android`). A single package `com.demo.glyf` holds the Flutter `MainActivity` and the native Kotlin keyboard service `ime/GlyfIME.kt` (an `InputMethodService` with a canvas-drawn key view). Because app and keyboard are the same package, sharing is just the app's files directory. The Kotlin stores (`store/Stores.kt`, `store/VaultStore.kt`, `store/SecretScanner.kt`) mirror the Swift ones and use the same JSON file names and schemas.
- **Backend** (`server/`). Holds every provider key and OAuth token. The apps only call it over HTTP(S). It is not deployed yet, so today it runs on Arpit's Mac.

### 3.2 Repo map (app-related parts)

| Path | What it is |
|---|---|
| `app/lib/main.dart` | App entry: onboarding vs shell, deep-link routing (`glyf://intent`, `glyf://connected`), pending dictation check |
| `app/lib/shell/app_shell.dart` | 3-tab shell (Home, Build, Profile), crossfading tabs, tap-outside dismisses the keyboard |
| `app/lib/onboarding/` | `onboarding_flow.dart` (8 steps), `orb.dart` (the glass orb) |
| `app/lib/home/` | `home_tab.dart` (setup card, live key map, try field, bound key cards), `keyboard_visual.dart` |
| `app/lib/build/` | `build_tab.dart`, `builder_screen.dart`, `skills_screen.dart`, `key_picker.dart` |
| `app/lib/profile/` | `profile_tab.dart`, `keyboard_settings_sheet.dart`, `themes_screen.dart`, `paywall_sheet.dart` |
| `app/lib/vault/vault_screen.dart`, `app/lib/notes/notes_screen.dart`, `app/lib/vocab/vocabulary_screen.dart`, `app/lib/dictation/recording_sheet.dart` | Feature screens |
| `app/lib/core/` | `bridge.dart` (channel), `glyf_api.dart` (backend client), `catalog.dart`, `recommend.dart`, `packs.dart`, `telemetry.dart`, `theme.dart` (design system + brand marks), `contracts.g.dart` (generated) |
| `app/ios/GlyfKeyboard/GlyfKeyboardViewController.swift` | Keyboard composition root: surfaces, heights, typing, gestures, act, bar, delivery |
| `app/ios/GlyfKeyboard/Layout/` | `KeyboardLayout.swift` (key tables), `KeyboardView.swift` (touch handling, ripple), `KeyView.swift` (one key), `AccentPopup.swift` |
| `app/ios/GlyfKeyboard/Surfaces/` | `Toolbar.swift`, `GlyfBar.swift`, `ActSurface.swift`, `GlyfShell.swift`, `SearchSurface.swift`, `EmojiBoard.swift`, `ConnectorSurface.swift`, `TranslationHUD.swift`, `TonesPopup.swift`, `ClipContextStrip.swift`, `NoteEditSurface.swift`, `InlineEditor.swift`, `KeyboardToast.swift`, `ThumbLoader.swift` |
| `app/ios/GlyfKeyboard/Engine/` | `SettingsStore.swift`, `VaultStore.swift` (+ `Shorthand`), `NotesStore.swift`, `ClipboardStore.swift`, `SecretScanner.swift`, `ToneProfile.swift`, `SpaceGesture.swift` (+ `CursorMirror`), `SearchCard.swift`, `SearchRecents.swift`, `Autocorrect.swift` (`WordTracker`), `Typing/` (the typing engine) |
| `app/ios/GlyfKeyboard/Bridge/` | `AppGroupStore.swift`, `BackendClient.swift`, `IntentStore.swift`, `HostAppOpener.swift`, `GlyfCatalog.swift`, `Contracts.generated.swift` |
| `app/ios/GlyfKeyboard/Design/` | `GlassTokens.swift` (the `Glass` token enum), `EmojiData.swift` |
| `app/ios/GlyfKeyboard/MemoryLogger.swift` | `GLYF_MEM` footprint logging |
| `app/ios/RunnerTests/` | Swift unit tests (61 test functions) |
| `app/ios/GlyfM0UITests/GlyfM0UITests.swift` | UI gate tests; the class is `GlyfGateUITests` (23 tests) |
| `app/android/app/src/main/kotlin/com/demo/glyf/` | `MainActivity.kt`, `GlyfBridge.kt`, `store/`, `ime/` (`GlyfIME.kt`, `GlyfKeyboardView.kt`, `KeyboardLayout.kt`, `BackendClient.kt`, `SearchCards.kt`, `SpaceGesture.kt`, `typing/`) |
| `app/android/app/src/test/kotlin/...` | JVM unit tests (space gesture, typing engine, dictionary eval) |
| `app/assets/fonts/Inter-Variable.ttf` | Inter, used by the Flutter app on both platforms and by the Android keyboard |
| `app/assets/vocab/packs.json` | 20 vocabulary packs, shared by the app and both keyboards |
| `app/dict/` | `en.glyd` (compiled dictionary, 9.4 MB), `source/` (AOSP word lists), `supplement_en.combined`, `NOTICE.md` |
| `shared/contracts/` | JSON Schemas for keyboard to app intents and results |
| `shared/typing/` | `FORMAT.md` (engine spec), `golden-cases.json`, `real-cases.json`, `golden.combined`, `golden.glyd` |
| `tools/` | Xcode wiring Ruby scripts, `gen_contracts.mjs`, `build_dictionary.py`, `xcodeproj-env.sh` |
| `ci/` | `check_keyboard_clean.sh`, `check_no_secrets.sh`, `check_memory_budget.sh` |
| `docs/` | Spike findings, milestone gate reports, `evidence/` (screenshots, logs, gate videos) |
| `glyf/` (repo root) | A stray, empty Xcode template project with its own `.git`, created 2026-09-12 20:43. **Not the app.** Gitignored. |
| `spikes/` | Empty folder |

### 3.3 Identifiers and the do-not-change rule

The app's bundle IDs were renamed on 2026-09-12 from `so.glyf.app` / `so.glyf.app.keyboard` to `com.demo.glyf` / `com.demo.glyf.keyboard`, because Arpit had already registered the App ID: "i have the app id as com.demo.glyf not what u put, fix that". A build has since been uploaded to TestFlight under `com.demo.glyf`, so the bundle ID is now permanent for that App Store Connect record.

These `so.glyf.*` identifiers were **deliberately left unchanged** and must stay that way:

| Identifier | Why it must not change |
|---|---|
| App Group `group.so.glyf.shared` | Changing it points existing installs at a new, empty container: vault, notes, settings, learned words all vanish on update. |
| Keychain group `so.glyf.shared`, service `so.glyf.vault` | The vault's encryption key lives there. A new name means the existing vault can never be decrypted. |
| Android Keystore alias `so.glyf.vault` | Same, on Android. |
| MethodChannel `so.glyf/bridge` | Hard-coded on three sides (Dart, Swift, Kotlin). |
| Log subsystem `so.glyf.keyboard` | Log capture recipes and gate tooling filter on it. |
| URL scheme `glyf://` | The OAuth callback and dictation handoff use it. |

These are reverse-DNS names, not domains. When the domain became tryglyf.com (2026-09-14), only real URLs changed (backend URL, OAuth redirect base, JSON Schema `$id`s, demo text). The same reasoning keeps the bundle ID as `com.demo.glyf`.

The keyboard-enabled check in the app is **derived** from the running bundle ID (`Bundle.main.bundleIdentifier + ".keyboard"` in `GlyfBridge.swift`), so it works for any bundle ID. Never hard-code it again (the rename broke it once).

### 3.4 How the app and the keyboard share data

Platform channels cannot cross the app and keyboard processes (SPEC 1.1), so **files are the bus**.

- **iOS**: JSON files in the App Group container under `bridge/` (`AppGroupStore.bridgeDir`), written atomically. The vault is an AES-GCM blob; its 256-bit key sits in the shared Keychain group, never in the App Group. The app reads settings through `SettingsStore.load()`, so it always sees the migrated view.
- **Android**: the same file names and schemas in `filesDir/bridge/` (`Bridge.write` writes a `.tmp` file and renames it). The vault key is in the Android Keystore. Learned typing data is in `noBackupFilesDir/typing/`. Because the IME shares the app's package, `GlyfBridge.kt` can also call the live typing engine directly.

| File (in `bridge/`) | Written by | Read by | Purpose |
|---|---|---|---|
| `settings.json` | app and keyboard | both | All shared settings (section 3.5) |
| `onboarding.json` | app | app | `done`, `persona`, `displayName`, `completedAt` |
| `vault.enc` | app (add/edit) | keyboard (insert) | Encrypted vault: fields, combos, shorthand snippets |
| `notes.json` | app and keyboard note editor | both | Notes |
| `clipboard.json` | iOS keyboard | iOS keyboard | Clipboard history (20 items, 1 hour expiry unless pinned) |
| `clip-cc.json` | iOS keyboard | iOS keyboard | Last pasteboard `changeCount` seen (prompt-free probe) |
| `clip-context.json` | iOS keyboard | iOS keyboard | "Copied text" strip freshness and dismissal |
| `emoji-recents.json` | iOS keyboard | iOS keyboard | Emoji recents |
| `tone-profile.json` | keyboard (iOS records) | app and keyboard | Tone learning counters |
| `typing-memory.json` | keyboard | app ("My words") | Learned words and pairs. iOS writes it here only with Full Access, otherwise in the extension's own container. Android keeps it in `noBackupFilesDir/typing/` instead. |
| `typing-edits.json` | app | keyboard | "My words" edits (`add`, `forget`, `reset`) the keyboard applies next time it opens |
| `vocab-custom.json` | app | keyboards | Packs made from a description |
| `contacts.json` | app | keyboards | Minimal contacts index (name, phones, emails), created only when the user turns on Contacts search |
| `search-recents.json` | keyboard | keyboard | Recent searches per tab (6 each) |
| `shell-state.json` | iOS keyboard | iOS keyboard | In-keyboard menu stack, restored within 60 seconds |
| `runs-remaining.json` | iOS keyboard | iOS keyboard | Cached meter count |
| `keyboard-ping.json` | keyboard | app | Appearance count, memory footprint, `hasFullAccess`. The app uses this to show whether Full Access is on. Android always writes `hasFullAccess: true`. |
| `pending-intent.json`, `intents/<id>.json`, `results/<id>.json`, `consumed/<id>` | keyboard and app | both | The keyboard to app handoff (section 3.8) |
| `app-pong.json`, `spikea-attempt.json` | M0 scaffolding | M0 tests | Proof of bidirectional App Group access |
| `vault-debug.json` | app, only with `--glyf-dump-vault` | UI tests | **Decrypted** vault dump for test forensics. Debug launch argument only. |

**Update persistence** was verified on the simulator on 2026-09-13 after Arpit asked "can u verify that updating app wont require me to readd everything in vault and memory etc it should remember". The assistant snapshotted every store, reinstalled over the same bundle ID (what an App Store update does), and diffed: vault (and its Keychain key), settings, onboarding, tone profile, and notes were byte-identical. Caveats recorded then: **uninstalling wipes the App Group** (an iCloud backup or export could be added later, undecided), and **changing the bundle ID or team creates a new app**, so both must stay locked.

**Full Access caveat (unverified on a device).** SPEC 1.3 says vault, clipboard and snippets must work with Full Access off. On the simulator, the keyboard could read and write the App Group with Full Access off (`testZProbe_AppGroupWithFullAccessOff`), but the simulator does not enforce the extension sandbox faithfully. The device probe was never run. The typing engine already guards against a locked-down container by keeping learned words in the extension's own container when Full Access is off.

### 3.5 Shared settings schema

One schema, defined in `app/ios/GlyfKeyboard/Engine/SettingsStore.swift` (`GlyfSettings`) and mirrored in `app/android/.../store/Stores.kt` (`SettingsStore.defaults()`). The Flutter app edits the JSON directly through the bridge.

| Key | Default | Meaning |
|---|---|---|
| `schemaVersion` | 3 | Drives additive migrations |
| `haptics`, `keyClicks` | true, true | Key haptics and key sounds |
| `numberRow` | false | Extra number row (+42pt) |
| `autocorrect`, `autocapitalize`, `periodShortcut`, `candidates` | all true | Typing behaviors; `candidates` is the suggestion strip |
| `vocabPacks` | nil | Enabled vocabulary pack ids. Nil means "not chosen": phones set to India behave as `["local.hinglish"]` |
| `vocabLearning` | true | Learn words from typing |
| `oneHanded` | `"off"` | `off` / `left` / `right` (iOS only) |
| `toolbarOrder` | `search, clipboard, vault, dictation, emoji, translate, settings` | Toolbar order (iOS). Android's defaults omit `search`, but the Android toolbar is hard-coded anyway. |
| `toolbarHidden` | `[]` | Hidden toolbar items (iOS) |
| `bindings` | `t: surface:translate-hud`, `s: surface:vault`, `p: glyf.proofread` | Letter to action. Values are a Glyf id (`glyf.proofread`, custom `user.<8hex>`), `surface:<name>` (`translate-hud`, `vault`, `tones`, `notes`), or `connector:<id>` (`mockcal`) |
| `customTitles` | `{}` | Display names for custom and community Glyfs, written on bind |
| `translationHUD` | false | Translation HUD strip on or off |
| `proUnlocked` | false | Legacy plan flag, still sent to the server |
| `plan` | `"free"` | `free` / `plus` / `max` |
| `appearance` | `"auto"` | Keyboard appearance: `auto` follows the host, `light`, `dark` |
| `keyTheme` | `"glass"` | `glass` / `classic` / `glow` |
| `themeBg` | `""` | Painted keyboard background: `""`, `color:#RRGGBB`, or `grad:<id>` where id is `dusk`, `ocean`, `ember` or `forest` |
| `keyBorders` | false | Gboard-style borders around keys |
| `themeBrightness` | 0 | Background dim, 0 to 0.6 |
| `pasteStyle` | `"titleAndLink"` | Search result paste: `titleAndLink` or `linkOnly` |
| `lastLat`, `lastLon`, `region` | unset | Coarse location (rounded to ~1 km) and 2-letter region, cached by the app when the user allows location |
| `backendURL` | debug: local server, release: `https://api.tryglyf.com` | Backend base URL |
| `deviceId` | random lowercase UUID | The device's identity with the backend (there are no accounts yet) |
| `translateTarget` | `"English"` | Translation target language |

**Migrations** (`SettingsStore.migrated()`, pure and unit-tested; runs on every load):

1. `backendURL` is passed through `productionized()` (section 3.6).
2. Toolbar: if `search` is missing it is inserted first; any other new default item is appended.
3. v1 to v2: bind `s` to `surface:vault` if `s` is free (the vault shipped in M4).
4. v2 to v3: if `t` is still the old one-shot `glyf.translate`, upgrade it to `surface:translate-hud`; add default bindings only for keys the user has not claimed.
5. `customTitles` never nil; `plan` derived from `proUnlocked` when missing (`true` becomes `plus`).

Android has no versioned migrations: `SettingsStore.load()` fills any missing key from `defaults()` and productionizes the backend URL.

The default map was 10 keys in M5 (`t r s c j p e x w q`). On 2026-09-12 it was **trimmed to 3** after Arpit said "dont preset a lot". Installs that already had the 10-key map keep it. UI tests seed the full map with `--glyf-seed-bindings`.

### 3.6 How the apps talk to the backend

**Base URL.** Debug builds talk to the local server; release builds talk to `https://api.tryglyf.com`.

- iOS: `GlyfSettings.productionBackend` and `defaultBackendURL` behind `#if DEBUG`. `productionized()` rewrites a persisted local URL to production in release builds (so a shipped build never points at a laptop) and rewrites a persisted production URL back to local in debug builds (so a dev build never silently leaves the dev server).
- `#if DEBUG` only works because Debug configs set `SWIFT_ACTIVE_COMPILATION_CONDITIONS = $(inherited) DEBUG` on Runner, GlyfKeyboard and the UI test target. Before 2026-09-14 the keyboard target only had the C macro `DEBUG=1`, which Swift ignores. Every debug keyboard build then used the production URL, which did not resolve, and failed with an opaque `NSURLErrorDomain -1200` TLS error. Check this flag first whenever a debug build behaves like a release build.
- Android: `SettingsStore.PRODUCTION_BACKEND` and `BuildConfig.DEBUG` (which needs `buildFeatures { buildConfig = true }` in `build.gradle.kts`). Cleartext HTTP is allowed only for `10.0.2.2`, `127.0.0.1` and `localhost` (`res/xml/network_security_config.xml`).
- Flutter: `GlyfApi` uses the settings value, falling back to `kReleaseMode ? https://api.tryglyf.com : http://127.0.0.1:8787`.

**Identity.** Every call carries `deviceId`. The server treats it as the credential (on 2026-09-15 the public hub list was fixed so it no longer exposed publishers' device IDs). There is no sign-up or login yet.

**Plan.** Runs send `plan` (and the legacy `pro` flag). The server trusts this value today (section 11.4).

**Full Access (iOS).** The keyboard only makes network calls with Full Access. Without it the Glyf Bar shows "AI needs Full Access" and search shows "Search needs Full Access". Typing never needs the network.

**Streaming.** `POST /glyf/run` answers with server-sent events: `event: token` (`{"t": ...}`), `event: done` (`{"text": ..., "remaining": n}`), `event: error` (`{"message": ...}`). Clients show "Couldn't reach Glyf. Tap to retry." on transport failure and "Daily free runs used up" on HTTP 429. The app treats any error containing "free runs used up" as the paywall moment (`GlyfApiException.capHit`).

**Endpoints the apps call**

| Endpoint | Caller | Purpose |
|---|---|---|
| `POST /glyf/run` (SSE) | iOS keyboard (bar, skills, Translation HUD), Android IME (overlay, skills), Flutter app (dictation Clean/Formal) | Run a Glyf on text |
| `POST /act` | both keyboards | Hold space on typed text: server routes to place, list, answer, video, or rewrite; returns cards plus the text Insert should put in |
| `POST /search` | both keyboards | Search / YouTube / Maps tabs, typed result cards |
| `GET /search/suggest` | both keyboards | Landing rows before typing: trending searches, popular videos, nearby places |
| `GET /search/photo` | both keyboards (place thumbnails come back as a server-relative path) | Photo proxy so the Places key stays on the server |
| `GET /search/staticmap` | Android IME | Map image above a place card (Geoapify key needed). iOS draws its own map with MapKit. |
| `GET /meter/:deviceId` | iOS keyboard, Flutter app | Runs left today |
| `GET /connector/mockcal/events?q=`, `GET /connector/mockcal/month` | iOS keyboard (ConnectorSurface) | Demo calendar: today's events and the month grid |
| `POST /builder/generate`, `POST /builder/test` | Flutter Builder | Plain English to a Glyf definition; test run |
| `POST /glyfs`, `GET /glyfs?deviceId=`, `DELETE /glyfs/:id` | Flutter Build tab | Save, list, delete your Glyfs |
| `POST /hub/publish` | Flutter Build tab | Publish your Glyf |
| `GET /skills`, `GET /skills/creators`, `POST /skills/get` | Flutter Skills screen | Browse, creators, install (counted per device) |
| `POST /account/name`, `GET /account/:deviceId/creator` | Flutter Profile | Display name, creator stats |
| `GET /connectors/status?deviceId=` | Flutter Profile, Builder | Which providers are configured and connected |
| `GET /oauth/google/start?deviceId=&scopes=` | Flutter onboarding, Profile | Google consent URL with the scopes the user chose |
| `GET /oauth/google/callback` | browser, then redirects to `glyf://connected?provider=google&ok=true` (or `ok=false`) | Token exchange (tokens stay on the server) |
| `POST /connectors/disconnect` | Flutter Profile | Disconnect Google |
| `POST /vocab/generate` | Flutter Vocabulary | Word pack from a description |
| `POST /telemetry` | Flutter app | Event batches (never content) |
| `GET /health` | Flutter Profile | "Engine connected" dot |

`POST /tools/run` still has client helpers (`BackendClient.runTool` on iOS, `BackendClient.tool` on Android) but nothing calls them since the search suite moved to `/search` on 2026-09-14.

**Server environment variables that change what the apps can do** (names only; values live in `server/.env`, documented in `server/.env.example`): `OPENROUTER_API_KEY`, `GEMINI_API_KEY`, `GROQ_API_KEY`, `MISTRAL_API_KEY`, `INCEPTION_API_KEY`, `CEREBRAS_API_KEY`, `FAST_MODELS`, `SMART_MODELS`, `MOCK_AI`, `FREE_RUNS_PER_DAY`, `BRAVE_SEARCH_KEY`, `SERPER_API_KEY`, `YOUTUBE_API_KEY`, `GEOAPIFY_KEY`, `GOOGLE_PLACES_KEY`, `GOOGLE_WEATHER_KEY`, `OVERPASS_API_BASE`, `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `GOOGLE_REDIRECT_URI`, `OAUTH_REDIRECT_BASE`, `NOTION_CLIENT_ID` / `_SECRET` (and the same pair for `SLACK`, `GITHUB`, `LINEAR`, `TODOIST`, `CALENDLY`, `ZOOM`, `SPOTIFY`), `GIPHY_API_KEY`, `PUBLIC_BASE_URL`, `PRIVY_APP_ID`, `PRIVY_APP_SECRET` (M8 only, never used by the apps), `NODE_ENV`, `PORT`.

### 3.7 What runs on the device and what runs on the server

| On the device (works offline) | On the server (needs network; on iOS also Full Access) |
|---|---|
| Typing, layouts, shift, autocapitalization, accents (iOS) | Every AI call: Glyf runs, act routing, Builder generation, vocabulary pack generation, dictation Clean/Formal |
| Autocorrect, suggestions, next-word prediction, learning, vocabulary packs, the 165k-word dictionary | Search providers: web, YouTube, maps, instant answers, trending |
| Space-bar glide and hold detection | Keyless tools (weather, crypto, FX, and so on) |
| Vault encryption, vault and notes insert, `;shorthand` expansion | OAuth tokens and calls to Google, Notion, Slack and others |
| Clipboard history, secret scanning | Meter and plans |
| Emoji board and emoji search | Skills hub, your saved Glyfs, moderation, install counts |
| Contacts search (reads the local index) | Telemetry aggregation |
| Recent searches, coarse location cache | Live mini-app pages, map and photo proxies |
| Tone profile counters (compact numbers, never text) | |
| Speech recognition (iOS, on-device when supported; audio never leaves the phone) | |
| Themes, dark mode, memory logging | |

**What leaves the phone, and only when the user acts:** the field text a run or act reads (or the clipboard text when the bar falls back to it), search queries, the coarse location plus region and time zone sent with searches and act, the dictation transcript when Clean or Formal is picked, and the description typed into the Builder or "Make a pack". **Never sent:** keystrokes, typing logs, learned words, the vault, contacts, audio. Secure (password) fields disable all AI and search surfaces.

### 3.8 Keyboard to app handoff (intents) and opening the app

SPEC 4.1 says a keyboard cannot call `UIApplication.shared.open()`. Features that need the app (dictation now; swaps and sends at M8) use a file handoff plus a best-effort app opener.

- **Contracts**: `shared/contracts/intent.schema.json` and `result.schema.json` are the single source of truth. `node tools/gen_contracts.mjs` generates `app/ios/GlyfKeyboard/Bridge/Contracts.generated.swift`, `app/lib/core/contracts.g.dart` and `server/src/schemas/contracts.generated.ts`. Never hand-write both sides. (Bug fixed in the generator: a bare `oneOf: [null, object]` must be handled before the nested-object branch, or it emits an empty struct and drops optionality.)
- **`IntentStore.swift`** (compiled into the keyboard, the app and the tests): intents expire after **120 seconds**, carry a 32-byte random nonce, are **single-use** (a `consumed/<id>` marker; replay refused), and results are **single-read** (read and delete in one step). A `pending-intent.json` pointer tells the keyboard what it is waiting for. Five unit tests cover round trip, expiry, replay, single-read, and expired results.
- **`HostAppOpener.swift`** (Spike A, 2026-09-11). Tried in order on iOS 26.5:
  1. `NSExtensionContext.open`: refused for keyboards.
  2. Responder chain to the live `UIApplication`, legacy `openURL:`: the selector no longer exists.
  3. Same `UIApplication`, **`openURL:options:completionHandler:` called through a C function pointer**: **works**. The app comes to the foreground and receives `glyf://intent?id=...`.
  4. Any other responder answering `openURL:`: none.
  The intent is written **before** any open attempt, so if every strategy fails the app still finds it on the next manual launch. The keyboard then shows "Open the Glyf app to record". The completion of strategy 1 arrives off the main thread; the responder walk must run on main.
- **Risk.** This is unsupported behavior that Apple can remove in any iOS release; the UI test `testB_SpikeA_OpenHostAppFromSettings` (M0) is the canary. Research on 2026-09-14 also noted that App Store Guideline 4.4.1 forbids a keyboard from launching apps other than Settings. The dictation handoff, the shell's "Open in Glyf app" footer and the connector action bar all use the opener, so this needs a decision before App Store submission (section 11.2).
- **Take once, insert once.** When the user returns from the app, the keyboard delivers the dictation result (`deliverPendingResult`, triggered 0.5 s after `viewDidAppear` and on `textDidChange`). iOS can attach a keyboard to a "phantom" text session whose document accepts inserts that never show, and "lost" inserts can later flush and double the text. The rule that survived: consume the result first, insert exactly once, never retry an insert.

---

## 4. Non-negotiables and hard rules

### 4.1 From the spec (SPEC sections 1, 11 and 13)

1. **The iOS keyboard is native Swift. Flutter never links into it.** Keyboard extensions are capped at roughly 40 to 70 MB and Flutter alone would blow it. Enforced by `ci/check_keyboard_clean.sh`, which also runs as the "Glyf CI Guard" build phase on every Runner build. The same idea holds on Android: `GlyfIME` is plain Kotlin views and canvas drawing, no Flutter.
2. **The keyboard cannot read the conversation.** Inputs are only the text in the focused field, the clipboard (on user intent), or a selection. No screen reading, and on Android no accessibility-service tricks (SPEC 13).
3. **The keyboard must work without Full Access** (Apple 4.4.1). Typing, layouts, autocorrect, emoji, local shorthand, vault and clipboard work with it off. AI, connectors, dictation, search, crypto and sync need it.
4. **Never repurpose standard keys.** Long-press is additive (release early or with nothing bound and you get the letter). Return, Shift, Delete and Globe are never rebound, and Globe must always work.
5. **The keyboard never holds private keys and never signs.** Relevant from M8 (crypto): the keyboard would only write an unsigned intent; the app simulates, asks for Face ID, signs.
6. **No secrets in any client bundle.** Provider keys and all OAuth tokens live on the server; clients hold opaque IDs. `ci/check_no_secrets.sh` greps for key shapes.
7. **Security rules** (SPEC 11): the vault refuses passwords, card numbers, seed phrases and government IDs; the clipboard never stores secret-shaped text; user-made Glyfs cannot make arbitrary HTTP calls (server tool registry only); anything touching vault, wallet or a connector declares it (`discloses`) and the declaration is shown before install; **no AI in secure text fields**; telemetry is events and timings, never content; tone and memory profiles stay on the device; clipboard text is treated as hostile.
8. **What not to do** (SPEC 13): no swipe typing in v1; never auto-insert AI output (always Replace / Insert / Copy); never store OAuth tokens on the device; default Glyfs are Builder-format data on the server, never hard-coded Swift; the in-keyboard shell is data rendered by one table, never a stack of view controllers; microphone, signing, purchases, OAuth consent and secret entry open the app, never the keyboard; the toolbar collapses when suggestions show instead of stacking a second strip; don't link the Privy SDK before M8; no crypto UI (not even hidden) in the v1.0 binary.
9. **Milestone order with hard gates** (SPEC 9). In practice Arpit overrode the pace ("we dont have 16 -22 days, we building everything today only") and the order (Android started before iOS shipped). Crypto (M8) stayed out of every binary.

### 4.2 Rules Arpit set during the build

| Rule | Where it came from | Status |
|---|---|---|
| Keep the `so.glyf.*` identifiers; bundle ID is `com.demo.glyf` | 2026-09-12 21:05, 2026-09-14 12:53 | Active |
| Secrets stay server-side ("for privy , keep them safe in env") | 2026-09-11 23:14 | Active. Keys that were pasted in chat (OpenRouter, Privy secret, YouTube key, Neon password) should be rotated. |
| Acti is a reference, never a copy ("you do not need to copy it, just for references"; later "dont blindly copy") | 2026-09-11, 2026-09-12 17:59 | Active: Glyf's own look (black pills, purple only as the dot, own icons, no Acti-style labels) |
| Apple design language, Apple-size keyboard ("why not apple's default size for this") | 2026-09-12 11:39 and 16:40 | Active |
| No explainer lines ("i dont like explainer lines everywhere remove them") | 2026-09-12 16:40, repeated 2026-09-13 and 2026-09-15 | Active, not fully applied (section 11.4) |
| The purple dot is the brand ("i like the dot tho its glyf symbol of our app"); no accent borders on keyboard keys | 2026-09-13 01:57 | Active |
| Default keyboard is simple: glass keys plus purple dots ("by default we need simple v similar to apple with just purple dots and glassy keys liquid glass") | 2026-09-13 02:13 | Active |
| Same features and iOS style on both platforms ("i want exactly same features in all , and ios style in both") | 2026-09-13 16:30 | Active, parity incomplete (section 6) |
| Smooth like Apple and Gboard ("i need smooth as fuck experience") | 2026-09-12 17:59, 2026-09-13 19:59 | Active |
| Don't preset many keys ("dont preset a lot") | 2026-09-12 17:59 | Active |
| Space bar: glide at any time moves the cursor; holding still launches the AI while the finger is still down ("it should launch before only"; "if nothing glides for some time just open ai") | 2026-09-14 23:25 and 23:30 | Active |
| Autocorrect must learn the person's words and never be random ("not random ass auto corrects") | 2026-09-15 00:00 | Active |
| No fake, mock or hard-coded results in front of the user ("you have hard coded results in ios idiot the fuck make them work") | 2026-09-14 15:06 | Active. `MOCK_AI` is for automated tests only. |
| When asked to change one thing, change nothing else (the app icon background incident) | 2026-09-14 13:35 | Active |
| No credit card on API sign-ups for now ("i dont wanna add my card here rn") | 2026-09-14 15:59 | Active |
| Ask when a design call is ambiguous ("u can ask me wherever u are ambiguous instead of taking shit design decisions") | 2026-09-15 14:44 | Active |
| AI data privacy is handled by a privacy policy, not code, for now ("we will not work on ai privacy rn as we will have privacy policy") | 2026-09-15 01:57 | Active |
| Light and dark mode in the apps ("i need both light and dark modes both in site and later in apps too") | 2026-09-15 (design questions) | Pending for the apps. Supersedes the white-only app lock. |
| Sign-up first, then onboarding, then ask for Google and other permissions only when a feature needs them ("we will have a sign up page at first also, then onboarding then if users want more features from google etc they will be pinged to allow") | 2026-09-15 (design questions) | Pending |
| No em dashes ("they look fucking disgusting ai made") | 2026-09-16 02:13, said about the website | Active for the site; app strings still contain them (section 11.4) |
| Process: no broad filesystem scans ("the fuck are u requesting to access everything"); use the attached simulator/emulator and known tool paths; commit only when asked; no AI attribution in git history | 2026-09-14 15:04, 2026-09-16 | Active |

### 4.3 Engineering rules learned the hard way (keep following them)

- **Never read `UIPasteboard` when the keyboard appears.** It fires Apple's paste permission prompt over the keyboard, every time. Probe `changeCount` and `hasStrings` (prompt-free) and read only on a user action (opening the clipboard screen, tapping the copied-text strip, the bar falling back to the clipboard). See `ClipboardStore.captureNow()` and `ClipContext`.
- **One blur layer per surface, never per key.** Keys are translucent fills over one `UIVisualEffectView`. The hold ripple animates each key's own tint layer; the blur is never touched.
- **Take once, insert once** for anything delivered from the app (section 3.8).
- **Any in-keyboard search or text field must collapse its surface to a strip** so the letter keys show underneath (emoji search, connector search, search suite, note editor). Found from Arpit's device report: "i can’t search in emojis because keyboard not showing".
- **`UIAlertController` gets clipped inside the keyboard window.** Use inline overlays (the connector insert menu is a pill row).
- **New iOS surface? Add it to the alpha-restore list in `applySurfaceLayout`** or it renders invisible (it happened with the note editor).
- **New Swift file? Run `tools/xcodeproj-env.sh tools/sync_keyboard_files.rb`.** Otherwise the build silently uses a stale app. Pure-logic files the unit tests need go in `TEST_SHARED`; files the app also compiles go in `RUNNER_SHARED`.
- **Keep `SWIFT_ACTIVE_COMPILATION_CONDITIONS = $(inherited) DEBUG`** on Debug configs (section 3.6).
- **Replace swaps both sides of the cursor.** A glided cursor sits mid-sentence; deleting only the text before it duplicated the tail. Applies to the Glyf Bar, act Insert and skill Insert on both platforms.
- **Decide holds from touch timestamps, not only the timer.** A busy main thread can deliver touch-down and touch-up back to back, turning a real hold into a tap.
- **The keyboard extension version must match the app.** Every `CURRENT_PROJECT_VERSION` and `MARKETING_VERSION` in the pbxproj, including the extension's, moves in lockstep with `pubspec.yaml` (the extension does not inherit Flutter's build number).
- **Typing engine:** a constant changed in one engine must change in the other and in `shared/typing/FORMAT.md`, and both test suites must pass.
- **Search card paste format is written three times** (server `composeInsert`, Swift `SearchCard.insertText`, Kotlin `SearchCard.insertText`) and locked by identical tests.
- **Android:** never use `LAYER_TYPE_SOFTWARE` or `Paint.setShadowLayer` on keys (CPU redraw on every press); keep the navigation-bar inset padding on the IME root; read IME state through `InputMethodManager` (targetSdk 34+ blocks `Settings.Secure`); keep `mipmap-anydpi-v26/ic_launcher.xml` or launchers crop the icon.

---

## 5. Features, one by one

Each feature lists what it does, how it works on iOS, Android and in the Flutter app, what it needs from the server, and its status. Section 6 has the side-by-side parity table.

### 5.1 The base keyboard (layouts, keys, feel)

**Layouts** (`app/ios/GlyfKeyboard/Layout/KeyboardLayout.swift`, mirrored by `app/android/.../ime/KeyboardLayout.kt` with the same rows, unit widths and key ids):

- Letters: QWERTY, optional number row on top. Row 3 is Shift (1.4 units), `zxcvbnm`, Delete (1.4 units).
- Symbols 1 (`123`) and Symbols 2 (`#+=`). The `. , ? ! '` row stretches between the mode key and Delete like Apple's (1.44 units each). This came from Arpit's real-device WhatsApp screenshot on 2026-09-12 ("see the images secobd one is our it looks bad").
- Bottom row: mode key, Globe (iOS only, and only when iOS says a switch key is needed), emoji key, space (fills the rest, labeled with a faint "glyf" watermark), Return (2.2 units).
- **Field-aware rows** (added 2026-09-12 after "figure out how keyboard looks in number inputs screen and other screens where @ needs to entered like email field"): email fields get `@` and `.` beside space; URL fields (and web search fields on iOS) get `.` and `/`; number, decimal and phone fields get a 3 by 4 digit pad (corner key is `.` for decimal, `+` for phone). iOS reads `UIKeyboardType`; Android reads `EditorInfo.inputType`.

**Keys and feel (iOS, `KeyboardView.swift`, `KeyView.swift`)**

- Apple metrics measured against the system keyboard on 2026-09-13: 6pt key gaps, 10pt row gaps, 3pt side insets, corner radius 9.5, letters in the system font at 23pt regular. All keys look the same (Apple's current uniform look).
- **Press preview balloon** above every character key (1.55 times wider, 1.35 times taller, 34pt glyph), drawn over the toolbar. No scale animation on press: Arpit's smoothness complaint on 2026-09-13 led to removing the 90ms press scale, because animated transforms read as lag during fast typing.
- Shift: tap toggles, double tap within 0.3 s is caps lock, shift releases after one letter.
- **Auto-capitalization follows the field**, like Apple's: `none` never, `allCharacters` always, `words` after spaces, `sentences` after `. ! ?`. Controlled by the `autocapitalize` setting. Flutter text fields must set `textCapitalization` for this to work (the Home try field uses `sentences`).
- Delete fires on touch-down, repeats after 0.45 s at 90 ms, then 45 ms after 18 repeats.
- Double space within 0.45 s after a letter or digit types ". " (`periodShortcut`).
- Long-press a letter with accents (and no binding) for 320 ms: an accent popup drawn **inside** the keyboard frame (extensions cannot draw outside). Slide to pick. Includes `₹` on `$`.
- Globe: tap switches keyboard; long-press shows the input mode list.
- One-handed mode: 56pt inset on the left or right (`oneHanded`).
- Multi-touch typing is supported (per-touch state).
- Haptics: light impact on every key down, medium on ignition (setting `haptics`). Key clicks: `UIDevice.playInputClick` (setting `keyClicks`, and the system "Keyboard Clicks" setting also applies).

**Android (`GlyfKeyboardView.kt`)**: canvas-drawn keys with the same gaps (6dp, 10dp, 3dp), radius 9.5dp, key faces in **Inter** loaded from the Flutter bundle (`flutter_assets/assets/fonts/Inter-Variable.ttf`) so the keys match iOS instead of Roboto. Shift and Return glyphs are drawn as paths because Roboto renders `⏎` and `⇧` badly. Press balloon on characters. Fully GPU-rendered (shadows are offset rounded rectangles). On touch-down: `KEYBOARD_TAP` haptic and the standard key click at 0.6 volume (2026-09-13 smoothness pass: Android had no feedback at all before). Autocap uses `getCursorCapsMode`. Not on Android yet: caps lock, delete repeat, accent popups, one-handed mode, globe key, multi-touch, and the emoji key on the bottom row does nothing (section 6).

### 5.2 Keyboard height and frame (iOS)

Apple standard: **260pt in portrait** = 44pt toolbar + 216pt keys (`Glass.keyboardBaseHeight`). On 2026-09-12 Arpit asked "why is keyboard elongated as fuck, why not apple's default size for this". The cause was an Apple-acknowledged issue: iOS hands extensions a cached, oversized height (444pt here) and ignores height constraints and `allowsSelfSizing` (`self.inputView` is nil in `viewDidLoad`, so setting it there does nothing). The fix that shipped:

- `PassThroughRoot` (the view controller's root view) is transparent and passes touches above the content through to the host app.
- The real keyboard is **bottom-anchored** inside it with a required height constraint on the content view, plus a priority-999 request on the view itself. After a clean rebuild iOS adopted exactly 260 (`GLYF_KB height=260` in the logs), and the pass-through root keeps the look right even when it does not.

Heights grow per surface (`totalHeight` in `GlyfKeyboardViewController.swift`):

| State | Height |
|---|---|
| Keys | 260 (+42 with number row) |
| + Translation HUD strip, + copied-text strip | +44 each |
| Glyf Bar | +96 |
| Search suite | +96, plus up to 3 landing rows of 58 |
| In-keyboard menu (shell), ConnectorSurface, act result | +140 |
| Emoji search strip | +96 (strip above visible letter keys) |
| Note editor strip | +96 |

Every surface change runs one spring animation (0.30 s, damping 0.9). It was 0.46 s / 0.86 until Arpit's "google and apple are very much smoother compared to our" on 2026-09-13; don't slow it back down. Reduce Motion disables the animation; Reduce Transparency swaps the blur for a solid backdrop.

Android: the IME root is a vertical `LinearLayout` (toolbar 44dp + key view 216dp, +42dp with the number row). The root pads its bottom by the navigation bar inset, because keys drawn under the gesture-navigation zone were eaten as navigation gestures (tapping `123` or space collapsed the keyboard).

### 5.3 The toolbar and the suggestion strip

**iOS (`Surfaces/Toolbar.swift`)**, 44pt strip above the keys:

- **g button**, always leftmost: a black keycap (`Glass.brandInk`) with a bold white "g" and a glowing purple dot, on dark chrome with a faint white ring. It opens the in-keyboard menu (section 5.9). Before 2026-09-12 22:26 it was a washed-out white square; Arpit: "why is glyf button so dull and sad, saw how acti was soo good and bright".
- Items (SF Symbols, 20pt, order from `toolbarOrder`, hideable): Search, Clipboard, Vault, Dictation (mic), Emoji, Translate, Settings. Long-press an item to open its settings page in the menu.
- **Runs chip** at the right edge when 8 or fewer runs are left today.
- **Suggestions replace the tools** when there are candidates (never two strips, SPEC 6.2). Tapping g while suggestions show brings the tools back without opening the menu. Up to three slots: what you typed (in quotes, tap keeps it and teaches the engine), what space will insert (emphasized), the next best. After a correction, a single "↩ original" slot undoes it. After a space, the strip predicts the next word.

**Android (`GlyfIME.buildToolbar`)**: the same g keycap (tap opens the menu grid, long-press opens the app) and the same icons in the same order, drawn on canvas so they tint with the theme (emoji glyphs could not be tinted). Differences: Clipboard pastes the current clipboard (no history), Vault opens the vault panel, the mic shows a "Dictation lands in the Android update" toast, Translate runs `glyf.translate` on the field, the gear opens the app. The toolbar order and hidden items settings are not read. Suggestions work the same way (the three-slot strip replaces the icons; g restores them).

### 5.4 Typing engine: autocorrect, prediction, learning, vocabulary

**Why it was rebuilt.** On 2026-09-15 Arpit asked for "commonly used words by the person in vocabulary" and "not random ass auto corrects". A research pass showed the old iOS logic (`UITextChecker` plus re-ranking) produced teh→tech, Arpit→Armpit, glyf→glyph, Zomato→Tomato, acha→dacha and kal→kcal, and Android had no autocorrect at all.

**One engine, written twice, held to the same answers.**

- Swift: `app/ios/GlyfKeyboard/Engine/Typing/` (`TypingText`, `GlydTrie`, `Decoder`, `PersonalLexicon`, `TypingEngine`, `TypingStore`). Kotlin: `app/android/.../ime/typing/` (same names plus `WordContext`, `KeyboardTyping`).
- Spec: `shared/typing/FORMAT.md` (dictionary format, scoring, the exact rules for when a correction applies, learning rules). Change a number there, change it in both engines.
- Tests: `shared/typing/golden-cases.json` (64 cases against a small `golden.glyd`) and `shared/typing/real-cases.json` (106 cases against the real dictionary: typo fixes, names, slang and Hinglish that must be left alone, predictions). Both run in `RunnerTests/TypingEngineTests.swift` and the JVM `TypingEngineTest.kt`; `RealDictionaryEval.kt` prints decisions for tuning. A decision takes about 0.4 ms per word (reported 2026-09-15).

**How it decides.**

- Scoring is ported from AOSP LatinIME (Apache-2.0): where the finger landed on each key (touch offsets in key widths, fed by the key view) plus how common the word is.
- A correction applies only when confident: confidence at least 0.185, a clear lead over the runner-up, edit distance limits, and trust gates (never a far substitution in short words, so `yaar` is not `year`; a lowercase word becomes a proper noun only if common, so `priya` is not `Oriya`; never into an acronym, so `ngl` is not `NFL`; completions need 4 typed letters).
- **Never corrected**: words the person uses (in the dictionary, typed twice, kept once, in an enabled pack, added in the app, a contact name), capitalized words mid-sentence, tokens with digits or `@ # . / : _`, one-letter words, and any correction the user reverted before.
- AOSP's whitelist includes real-word swaps (`hum`→`him`, where "hum" is Hindi for "we"; `bot`→`not`; `os`→`is`; `id`→`I'd`). Glyf applies apostrophe fixes (`cant`→`can't`) only when the typed word is not a common real word, and different-word fixes (`alot`→`a lot`) only for non-words.
- **Field policy**: nothing (no suggestions, no correction, no learning) in secure, email, URL, username, one-time-code, card, phone and number fields; no autocorrect where the field or the user turned it off, or in name fields; no learning when paused (`vocabLearning`) or when the Android field sets `IME_FLAG_NO_PERSONALIZED_LEARNING`.

**Learning.** Only committed words. An unknown word counts as learned after 2 commits, or after 1 revert or one tap on the literal slot. Backspace right after a correction restores the typed word and blocks that pair forever. Counts halve every 90 days; words unused for 300 days are dropped; caps of 10,000 words and 30,000 pairs. Storage: iOS writes `typing-memory.json` to the App Group when Full Access is on (so the app can show "My words"), otherwise to the extension's own Application Support folder, and marks it excluded from iCloud backup. Android writes to `noBackupFilesDir/typing/`. Nothing typed is ever sent anywhere.

**iOS extras.** `requestSupplementaryLexicon` (Apple's API) supplies contact names (known words) and the user's iOS Text Replacements (expanded on space, undoable).

**Dictionary.** Approved by Arpit on 2026-09-15 ("yes install standrad dictionary and all"). `app/dict/en.glyd` (9.4 MB, memory-mapped so it costs the extension almost nothing) is compiled by `tools/build_dictionary.py` from AOSP's `en_wordlist.combined.gz` (165k words, US and UK spellings, Apache-2.0, see `app/dict/NOTICE.md`) plus `app/dict/supplement_en.combined` (texting words like lol/ok/u/idk/bruh; Indian names, apps and places like Swiggy, Zomato, Paytm, OTP, Aadhaar, crore, Chennai, Pune, Gurugram; about 50 next-word pairs such as happy→birthday). AOSP's emoji shortcut list (`en_emoji.combined.gz`) is downloaded but not wired in. Bundling: iOS via `tools/add_keyboard_resources.rb` (keyboard target resources); Android via `sourceSets.main.assets.srcDir("../../dict")`, copied once per app version into `noBackupFilesDir/typing/` so it can be memory-mapped.

**Vocabulary packs** (Arpit on 2026-09-15: "make a vocabulary lib ... like proffesoional vocab, local lang vocab, fun vocab categorise things"). `app/assets/vocab/packs.json`, 20 packs of about 2,200 words plus phrases:

| Group | Pack ids |
|---|---|
| Professional | `pro.work`, `pro.tech`, `pro.finance`, `pro.medical`, `pro.legal`, `pro.design`, `pro.study` |
| Local language | `local.hinglish` (326 words, includes SMS spellings like yar, nhi, kyu, bht, kr, rha, gya), `local.punjabi`, `local.tanglish`, `local.banglish` (shown as Bengali), `local.marathi`, `local.spanglish`, `local.places.in` |
| Fun | `fun.slang`, `fun.texting`, `fun.gaming`, `fun.food`, `fun.fitness`, `fun.crypto` |

Pack words become known words (and phrases teach word pairs). **Phones set to India start with Hinglish on** until the user chooses (`TypingStore.defaultPacks`, `KeyboardTyping.defaultPacks`, and the Dart Vocabulary screen), because without it chalo→chalk, arre→are and bas→has.

**Flutter: Profile → Vocabulary** (`app/lib/vocab/vocabulary_screen.dart`): switch packs on and off; "My words" (see what was learned, add, remove, pause learning, forget everything; edits go through `typing-edits.json` and apply the next time the keyboard opens); "Make a pack" describes how you write, calls `POST /vocab/generate`, lets you drop words, then saves to `vocab-custom.json`. A live test on free models took 58 s.

**Test hooks.** Launch argument `--glyf-reset-typing` writes a reset edit so UI tests start from a keyboard that learned nothing. UI tests `test01_TypingAutocapAutocorrectAndToolbarCollapse` and `test01b_AutocorrectUndoTeachesAndPredictsNextWord`. Verified on the Android emulator: "waht yaar definately thank " became "What yaar definitely thank " with "you" predicted.

### 5.5 Space bar gestures: glide to move the cursor, hold to launch the AI

Asked by Arpit on 2026-09-14 22:27: "i want hold and glide on keyboard to also move cursor thru text like apple keyboard and google keyboard does and i need hold to open ai thing also".

**The rule (Arpit's mandate, stated twice):**

- **Tap** space: types a space.
- **Glide at any point while holding**: the cursor follows the finger (Gboard's straight swipe, or Apple's press, pause, glide). Key faces go blank while gliding (Apple's trackpad look). It never types a space.
- **Hold still for 0.5 s**: the AI launches **right then, with the finger still down**. After launch, movement is ignored.
- Release sooner without moving: a space. Sliding off the bar vertically before anything is decided cancels the key.

**What was tried and rejected.** The first build armed at 320 ms and decided on release, so hold-then-glide and hold-for-AI could share the key. Arpit: "why does spacebar ai only launch after leaving key, it should launch before only, not like this" and "idiot acti also does this hold and glide and hold to open, if nothing glides for some time just open ai how idiot are u, set time v properly". The final design launches at 0.5 s (the platform long-press length) with the finger down.

**How it works.** One pure decision table, unit-tested on both platforms with identical thresholds: `app/ios/GlyfKeyboard/Engine/SpaceGesture.swift` and `app/android/.../ime/SpaceGesture.kt` (`HOLD_MS = 500`).

- Phases: pending, gliding, launched, finished. Effects: begin glide, move cursor by N grapheme clusters, end glide, open bar, type space.
- Hold threshold 0.5 s; glide starts after 10pt of sideways travel; 9pt per character at slow speed, with a gain ramping from 1 times at 250 pt/s to 2.6 times at 1050 pt/s for fast flicks.
- Decisions use the touches' own timestamps (`catchUp`), so a late timer on a busy main thread still launches a real hold. The lift position is applied as a final move, so fast flicks and sparse move events are not lost.
- The space key's charge ring is held back 100 ms (a normal tap never flashes it) and closes exactly at launch. Bound letter keys keep the spec's 320 ms.
- iOS moves the cursor with `adjustTextPosition`, which counts UTF-16 units; `CursorMirror` steps whole grapheme clusters from a snapshot taken when the glide starts (the proxy's context lags a move), so emoji and accented letters are never split.
- Android tracks the cursor locally (`onUpdateSelection` is asynchronous) and calls `setSelection`; it falls back to arrow key events only when the editor exposes no text, and never at an edge (an unconsumed arrow moves focus to another view).
- While an in-keyboard editor owns the keys (bar prompt, search, note), a glide does nothing and a hold is just a space. In secure fields a hold never opens the AI.

Tests: `testSpaceTapTypesASpace`, `testImmediateSwipeGlidesTheCursorGboardStyle`, `testPressPauseGlideIsApplesTrackpad`, `testHoldingStillLaunchesTheAIWhileTheFingerIsDown`, `testFastFlicksCoverMoreGroundThanSlowDrags`, `testLateTimerStillLaunchesByTheTouchClock` and others in `RunnerTests/GlyfEngineTests.swift`; `SpaceGestureTest.kt` on Android; UI test `test04b_SpaceBar_GlideMovesCursor_HoldOpensBar`.

### 5.6 Hold space on text: Act; on an empty field: the Glyf Bar

When the space hold launches (`kbSpaceHoldIgnited`, 60 ms after the ripple ignites, per SPEC 5.3):

- **There is typed text** (before or after the cursor), Full Access is on, and the field is not secure → **Act** on it.
- **Otherwise** → the **Glyf Bar** (it explains when Full Access is missing).

**Act** (built 2026-09-14 from Acti's launch video; section 7). The keyboard sends the text to `POST /act`. The server routes it with rules plus one fast JSON model call to a place search, a list, an answer, a video, or a rewrite, and returns a title, cards and the exact text Insert should put in. It never invents live facts; with no provider it returns a Google handoff card.

- iOS `Surfaces/ActSurface.swift` covers the keys: a **working** state (the black g keycap breathing inside quiet rings, the typed intent quoted, ✕ to cancel), a **result** state (the search suite's own cards, and for a single place a real map drawn with `MKMapSnapshotter`, no key needed; the rewritten text; buttons ↻ retry, Copy, and a black Insert pill), and a **failed** state (tap to retry).
- Android: the same three states in an act panel inside `GlyfIME.kt`; the map image comes from `GET /search/staticmap` (needs `GEOAPIFY_KEY`, otherwise no map is shown).
- **Insert replaces both sides of the cursor**: exactly the text the run read.
- For list results the server can publish a **live mini-app page** (`/p/:id`, needs `PUBLIC_BASE_URL`) and Insert then puts the page link after the typed text.
- Verified live on 2026-09-14: "Times Square Starbucks" returned a real place card and Insert pasted the maps link (Android emulator); UI tests `test04c_ActOnTypedText_InsertReplacesTheIntent` and `test04d_ActPlace_ShowsMap` (iOS).

**Glyf Bar** (M2, `Surfaces/GlyfBar.swift`; Android `showGlyfBar()` added 2026-09-14, before that Android had no bar):

- Rises inside the keyboard frame with the letter keys still visible, so you can type an instruction ("Tell Glyf what to do..."). Input source chip shows FIELD TEXT, CLIPBOARD, or no input.
- Input: the field text (both sides of the cursor); else the clipboard (read at this user-intent moment); else the prompt runs alone.
- Quick chips, same order on both platforms: Make it polite (`rewrite.polite`), Tighten (`rewrite.tighten`), Translate (`glyf.translate`, uses `translateTarget`), Emoji-fy (`rewrite.emoji`), Proofread (`glyf.proofread`). A typed instruction runs `custom.prompt` with the `prompt` variable.
- The result streams into a card over the keys with **Replace** (black pill), **Insert**, **Copy**. It **never auto-inserts** (SPEC 6.4). Errors appear inline ("Couldn't reach Glyf. Tap to retry."). The status line shows runs left.
- Design history: the purple Replace and purple washes were removed on 2026-09-12 22:26 (Arpit: "i dont like this screen much, improve it"); Replace became the black pill, siblings white with hairlines, the result a white card.
- The engine strips leaked internal directive tags like `[[tighten]]` that a live model once echoed on empty input.

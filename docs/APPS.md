# Glyf apps: the complete reference (iOS, Android, Flutter container app)

This file is the single place to learn everything about the Glyf **apps**: the Flutter container app, the native iOS keyboard extension, and the Android app with its native keyboard (IME). It covers what exists, how it works, where the code lives, every decision and why, what was tried and dropped, the current status, and what is still pending.

It does **not** document the backend (`server/`) or the website (`site/`) beyond how the apps use them. Those have their own docs: `docs/BACKEND.md` and `docs/WEBSITE.md`. The project-wide index is `docs/README.md` (with `PROJECT.md`, `DECISIONS.md`, `TIMELINE.md`, `OPEN-ITEMS.md`, `WORKING-AGREEMENTS.md`); this file goes deeper on the apps.

Written on 2026-09-16 from the repo state at that time (app code as of commit `cc46b39`; the later commits that day, `dbbd2c7` and `a1f0d0c`, only touched docs, the website, `README.md` and a share-image tool), the assistant's dated working notes, the gate docs in `docs/`, and the chat history exported to `docs/history/`. Where a claim could not be checked, it says so. Section 13 lists everything that could not be verified.

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
| iOS app bundle ID | `com.arpit.glyf` (since 2026-09-25; was `com.demo.glyf`) | `app/ios/Runner.xcodeproj/project.pbxproj` (Runner, 3 configs) |
| iOS keyboard extension bundle ID | `com.arpit.glyf.keyboard` | same file (GlyfKeyboard, 3 configs) |
| Android applicationId / namespace | `com.demo.glyf` (unchanged: the iOS move was for the App Store account) | `app/android/app/build.gradle.kts` |
| Android IME component | `com.demo.glyf/.ime.GlyfIME` | `app/android/app/src/main/AndroidManifest.xml` |
| App Group (iOS) | `group.com.arpit.glyf` (since 2026-09-25; was `group.so.glyf.shared`) | `app/ios/Runner/Runner.entitlements`, `app/ios/GlyfKeyboard/GlyfKeyboard.entitlements`, `AppGroupStore.groupID` |
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

Glyf is an AI keyboard for iPhone and Android. The website line is "Type less. Glyf more." (live on https://www.tryglyf.com since 2026-09-16, where the second "glyf" is drawn as the wordmark). The original spec line, still shown in the app's first onboarding screen, is "Every key is a Glyf."

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

- **Flutter container app** (`app/lib`, Dart package `glyf`). Runs unchanged on iOS (Runner) and Android (MainActivity). It owns onboarding, the Home tab (live key map and binding editor), the Build tab (Builder, Packs, your Glyfs, Skills), the Profile tab (plan, settings, vault, notes, vocabulary, themes, contacts search, nearby search, connected tools, tone profile, and Delete account at the foot: it confirms, calls `DELETE /me` and signs out; the vault and notes stay on the phone), the dictation recording sheet, and the paywall. The only Dart dependency beyond Flutter is `cupertino_icons`. All platform work goes through the app's own `so.glyf/bridge` channel, not third-party plugins.
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

These are reverse-DNS names, not domains. When the domain became tryglyf.com (2026-09-14), only real URLs changed (backend URL, OAuth redirect base, JSON Schema `$id`s, demo text). Reverse-DNS names are a convention, not proof of owning a domain, so the bundle ID also stays `com.demo.glyf`.

**2026-09-25: moved to Arpit's own developer account.** "we need to push at appstore today with our own acc, we were using a friends acc till now, so we can move from com.demo.glyf to com.arpit.glyf". The Console Labs India team (`XFSL58LKTQ`) was a friend's; its App IDs (`com.demo.glyf`, `com.demo.glyf.keyboard`) and App Group (`group.so.glyf.shared`) are registered there and can't be used from another team, so the iOS bundle IDs became `com.arpit.glyf` / `com.arpit.glyf.keyboard` and the App Group `group.com.arpit.glyf`. Arpit: "its okay if old users lose account". Sign in with Apple gives each team different user ids anyway, so nothing would have carried over. The rules in the table above protect people updating the same app; the App Store app is a new one. The keychain group name `so.glyf.shared` was kept: keychain groups carry the team prefix and are never registered. `DEVELOPMENT_TEAM` is empty until Arpit's own team is chosen in Xcode. The server accepts Apple tokens for every id in `APPLE_BUNDLE_ID` (comma-separated). Android stays `com.demo.glyf`.

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
| `vault-debug.json` | app, only with `--glyf-dump-vault` | UI tests | **Decrypted** vault dump for test forensics. Triggered only by a test launch argument, but the handler is not compiled out of release builds (section 11.4). |

**Update persistence** was verified on the simulator on 2026-09-13 after Arpit asked "can u verify that updating app wont require me to readd everything in vault and memory etc it should remember". The assistant snapshotted every store, reinstalled over the same bundle ID (what an App Store update does), and diffed: vault (and its Keychain key), settings, onboarding, tone profile, and notes were byte-identical. Caveats recorded then: **uninstalling wipes the App Group** (an iCloud backup or export could be added later, undecided), and **changing the bundle ID or team creates a new app**, so both must stay locked.

**Full Access caveat (unverified on a device).** SPEC 1.3 says vault, clipboard and snippets must work with Full Access off. On the simulator, the keyboard could read and write the App Group with Full Access off (M0 probe test `testZProbe_AppGroupWithFullAccessOff`, since removed from the test file), but the simulator does not enforce the extension sandbox faithfully. The device probe was never run. The typing engine already guards against a locked-down container by keeping learned words in the extension's own container when Full Access is off.

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
| `POST /act` | both keyboards | Hold space on typed text, or a tapped strip chip: server routes to place, list, answer, video, rewrite or write; returns cards plus the text Insert should put in. Streamed (`stream: true`): each version appears as it is written |
| `POST /suggest` | both keyboards | The strip's chip for a paused sentence; its own allowance, never a run |
| `POST /search` | both keyboards | Search / YouTube / Maps tabs, typed result cards |
| `GET /search/suggest` | both keyboards | Landing rows before typing: trending searches, popular videos, nearby places |
| `GET /search/photo` | both keyboards (place thumbnails come back as a server-relative path) | Photo proxy so the Places key stays on the server |
| `GET /search/staticmap` | Android IME | Map image above a place card (Geoapify key needed). iOS draws its own map with MapKit. |
| `GET /meter/:deviceId` | iOS keyboard, Flutter app | Runs left today |
| `GET /connector/mockcal/events?q=`, `GET /connector/mockcal/month` | iOS keyboard (ConnectorSurface) | Demo calendar: today's events and the month grid |
| `GET /scheduling/slots`, `POST /scheduling/book` | both keyboards (Book a time) | Open times on a Cal.com page; booking one for someone, guests included |
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

**What leaves the phone, and only when the user acts:** the field text a run or act reads (or the clipboard text when the bar falls back to it), search queries, the coarse location plus region and time zone sent with searches and act, the dictation transcript when Clean or Formal is picked, and the description typed into the Builder or "Make a pack". **Never sent:** keystrokes, typing logs, learned words, the vault, contacts, audio. Secure (password) fields disable every AI surface (section 5.26).

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
- **Risk.** This is unsupported behavior that Apple can remove in any iOS release. The M0 UI test `testB_SpikeA_OpenHostAppFromSettings` (keyboard used inside Settings, app must come forward) was meant as the per-release canary, but it is no longer in the test file; `test07_DictationEndToEnd` types in the Glyf app itself, so it does not prove the opener from a third-party app. Research on 2026-09-14 also noted that App Store Guideline 4.4.1 forbids a keyboard from launching apps other than Settings. The dictation handoff, the shell's "Open in Glyf app" footer and the connector action bar all use the opener, so this needs a decision before App Store submission (section 11.2).
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

- **A keyboard extension throws away touches that land on fully transparent pixels.** Not `alpha` on the view, which is the rule everywhere else: the rendered pixel. A `.clear` background makes a view invisible to touch before `hitTest` is ever consulted. This is the single cause behind three separate bug reports (dead gaps between keys, suggestions needing several taps, dead rows in panels), and it was found only by painting the grid red and watching the gaps start working. Every surface that must take a touch is painted with `Glass.touchableGrid`, which is the sheet's own colour at 1% alpha. Arpit, after two wrong diagnoses: "i think you are just spiraling arounf, research first , see why its not working, search web too and then fix".
- **There is no silent way to read the pasteboard.** `changeCount` and `hasStrings` are prompt-free but tell you nothing; `detectPatterns` names the pattern without the value; **`detectValues` is not silent** despite reading like it should be, because handing over a value is a read. The only quiet route to content is `UIPasteControl`, where the person's tap is the consent. Section 5.11 has the table.
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
- **The return key says what it does** when the field has told it (`returnKeyType`): search, go, send, done, next, join, route, continue, call; the plain ⏎ glyph otherwise.
- **WebKit number fields** (`type=number`, which iOS reports as `numbersAndPunctuation`) open on the 123 page, as Apple's keyboard does; every new field starts on the letters again.
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

- **The menu button, always leftmost: Glyf's own key** (since 2026-09-25, the same on Android): the app icon's mark on the site's pill (`globals.css` `.kb-g`), 41 by 30pt with 10pt corners. The mark is the icon's, measured off the 1024pt icon: its g (Inter SemiBold at text optical size) and its violet dot (#7C5CFF) above the letter's shoulder, the dot's centre 1.04 letter-heights right of the g's left edge and 0.49 above its top, a third of a letter-height across. Letter and dot together fill the key's height less 2.5pt top and bottom (a 15pt g, a 5pt dot), the g centred across. On a light sheet the pill is the icon's ink (#17181C) with a white g; on a dark sheet it is white with an ink g, the icon itself. The g is the font's outline, not text (`Design/GlyfMark.swift`, Android `GlyfMark.kt`), so the keyboard ships neither the font nor an image. At 30pt it is taller than the 26pt iOS 26 leaves above the strip's lifted middle (anything drawn over the strip's top edge is clipped), so it stands on that edge, its centre 2pt under the icons'. It opens the in-keyboard menu (section 5.9), and when a panel is open it becomes a plain ✕ that closes it. Section 8.4 has the whole design history of that slot, which took eight passes.
- Items (SF Symbols, **pointSize 21 regular**, order from `toolbarOrder`, hideable): Search, Clipboard, Vault, Dictation (mic), Emoji, Translate, Settings. Hold an item and it lifts: slide sideways to reorder, or drag it below the strip to hide it (it stays reachable in the g menu, and the menu's Settings → Toolbar items brings it back). A plain hold with no movement opens that Toolbar items screen.
- **The row is spaced by one gap, not by slots.** `layoutSubviews` solves for a single number that is both the air between any two icons and the air at each end, then hands the stack exactly the width that produces it (`distribution = .equalSpacing`). Measured result at 402pt: margins 19.0 and 19.3, gaps 46.7 to 47.3. Spacing by equal **slots** instead (each icon centred in a slot of one width) spaces the centres evenly but leaves the end margins to whatever the first and last icons happen to measure, which came out 14pt against 21.3 because the apps grid is 20pt wide and the translate symbol is 32.
- **Every icon gets 12pt of tap padding either side**, the same on both sides, so padding a target never moves an icon off the rhythm.
- **The apps grid carries 3pt of extra air (`gridSlack`)** because an SF Symbol does not fill the box it is drawn in and a drawn path does. Without it the grid sat 3pt nearer its neighbour, and 3pt nearer the screen edge, than anything else on the row.
- **The strip's contents sit `Glass.stripLift` = 5pt above centre.** Measured on iOS 26: the sheet's top edge at 531pt and the first key row at 588.33 leave the strip 57.3pt, so its middle is 559.67. At a lift of 3 the icons measured 561.83, two points low, which read as more air above the row than below.
- **Runs chip** at the right edge when 8 or fewer runs are left today.
- **Strip chips.** Sums, money, saved details, plans, booking links, payments and copies are spotted on the device. When none of those has anything to say, a 700 ms pause on a real sentence (12 characters, three words) asks `POST /suggest` what Glyf could do with it: "Tidy this up", "Show me places", "Find it on the map", "Find the video" or "Write it for me", with a sparkle where the verb goes, or a saved detail the sentence leads into ("sure, ship it to" offers the saved address). Tapping it runs hold space's act with that intent, streamed like hold space. It was removed on 2026-09-24 because every read spent one of the day's runs, and brought back on 2026-09-25 ("i need ai suggestions ... users will pay for that") on a small paid model chain with its own allowance: a suggestion never spends a run, tapping one does. Not in secure fields, not during the tour, and not with Suggestions off (`candidates`); kinds of saved detail are sent only while "Let AI use your details" is on, never the values.
- **Suggestions replace the tools** when there are candidates (never two strips, SPEC 6.2). Tapping g while suggestions show brings the tools back without opening the menu. Up to three slots: what you typed (in quotes, tap keeps it and teaches the engine), what space will insert (emphasized), the next best. After a correction, a single "↩ original" slot undoes it. After a space, the strip predicts the next word.

**Android (`GlyfIME.buildToolbar`)**: the same brand key (`GlyfKeyView`, drawn from the same outline and proportions; tap opens the menu grid, long-press opens the app) and the same icons in the same order, drawn on canvas so they tint with the theme (emoji glyphs could not be tinted). Differences: Clipboard pastes the current clipboard (no history), Vault opens the vault panel, the mic shows a "Dictation lands in the Android update" toast, Translate runs `glyf.translate` on the field, the gear opens the app. The toolbar order and hidden items settings are not read. Suggestions work the same way (the three-slot strip replaces the icons; g restores them).

### 5.4 Typing engine: autocorrect, prediction, learning, vocabulary

**Why it was rebuilt.** On 2026-09-15 Arpit asked for "commonly used words by the person in vocabulary" and "not random ass auto corrects". A research pass showed the old iOS logic (`UITextChecker` plus re-ranking) produced teh→tech, Arpit→Armpit, glyf→glyph, Zomato→Tomato, acha→dacha and kal→kcal, and Android had no autocorrect at all.

**One engine, written twice, held to the same answers.**

- Swift: `app/ios/GlyfKeyboard/Engine/Typing/` (`TypingText`, `GlydTrie`, `Decoder`, `PersonalLexicon`, `TypingEngine`, `TypingStore`). Kotlin: `app/android/.../ime/typing/` (same names plus `WordContext`, `KeyboardTyping`).
- Spec: `shared/typing/FORMAT.md` (dictionary format, scoring, the exact rules for when a correction applies, learning rules). Change a number there, change it in both engines.
- Tests: `shared/typing/golden-cases.json` (64 cases against a small `golden.glyd`) and `shared/typing/real-cases.json` (106 cases against the real dictionary: typo fixes, names, slang and Hinglish that must be left alone, predictions). Both run in `RunnerTests/TypingEngineTests.swift` and the JVM `TypingEngineTest.kt`; `RealDictionaryEval.kt` prints decisions for tuning. A decision takes about 0.4 ms per word (reported 2026-09-15).

**How it decides.**

- Scoring is ported from AOSP LatinIME (Apache-2.0): where the finger landed on each key (touch offsets in key widths, fed by the key view) plus how common the word is.
- A correction applies only when confident: confidence at least 0.185, a clear lead over the runner-up, edit distance limits, and trust gates (never a far substitution in short words, so `yaar` is not `year`; a lowercase word becomes a proper noun only if common, so `priya` is not `Oriya`; never into an acronym, so `ngl` is not `NFL`; completions need 4 typed letters).
- **Never corrected**: words the person uses (in the dictionary, typed twice, kept once, in an enabled pack, added in the app, a contact name), capitalized words mid-sentence, tokens with a digit, two or more capitals, or any of `@ # . / : _`, one-letter words, and any correction the user reverted before.
- AOSP's whitelist includes real-word swaps (`hum`→`him`, where "hum" is Hindi for "we"; `bot`→`not`; `os`→`is`; `id`→`I'd`). Glyf applies a same-letters apostrophe fix only when the typed spelling is not a real word within 40 frequency points of the fix (`cant` becomes `can't`, `id` stays), and a different-word fix (`alot`→`a lot`) only when the typed spelling is not a word at all.
- **Field policy**. iOS: nothing (no suggestions, correction or learning) in secure fields, URL, email, number, phone and decimal keyboards, or fields whose content type is URL, email, username, password, new password, one-time code, card number or phone; no autocorrect when the setting is off, the field disables it, the keyboard is the Twitter or web search type, or the content type is a name. Android: nothing in non-text, password, email, URI and filter fields or fields that ask for no suggestions; no autocorrect for person names and postal addresses. Both: no learning when paused (`vocabLearning`); Android also honors `IME_FLAG_NO_PERSONALIZED_LEARNING`.

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

**What was tried and rejected.** The first build armed at 320 ms and decided on release, so Apple's hold-then-glide and hold-for-AI could share the key. Arpit: "why does spacebar ai only launch after leaving key, it should launch before only, not like this". The next proposal (launch when the ring closes, then let a later glide push the bar aside) was also rejected: "idiot acti also does this hold and glide and hold to open, if nothing glides for some time just open ai how idiot are u, set time v properly". The final design launches at 0.5 s (the platform long-press length) with the finger down, and any glide before that moves the cursor.

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
- **It streams** (2026-09-25, Arpit: "5.4 s is too much ... maybe add streams so it looks better"). A rewrite's rows appear one by one as the model finishes each version (iOS `ActSurface.addOption`, fading in; Android `appendActOption`), and a row can be tapped before the rest arrive; "Write it for me" writes into its card as it comes. ↻ comes back when the last version is in. On the fast chain the first row shows about 1 s after the tap and all six by about 1.5 s (it was 5.4 s to anything).
- **Insert replaces both sides of the cursor**: exactly the text the run read.
- For list results the server can publish a **live mini-app page** (served at `/p/:id`; links in production need `PUBLIC_BASE_URL`, otherwise they point at the dev server) and Insert then puts the page link after the typed text.
- Verified live on 2026-09-14: "Times Square Starbucks" returned a real place card and Insert pasted the maps link (Android emulator); UI tests `test04c_ActOnTypedText_InsertReplacesTheIntent` and `test04d_ActPlace_ShowsMap` (iOS).

**Glyf Bar** (M2, `Surfaces/GlyfBar.swift`; Android `showGlyfBar()` added 2026-09-14, before that Android had no bar):

- Rises inside the keyboard frame with the letter keys still visible, so you can type an instruction ("Tell Glyf what to do..."). Input source chip shows FIELD TEXT, CLIPBOARD, or no input.
- Input: the field text (both sides of the cursor); else the clipboard (read at this user-intent moment); else the prompt runs alone.
- Quick chips, same order on both platforms: Make it polite (`rewrite.polite`), Tighten (`rewrite.tighten`), Translate (`glyf.translate`, uses `translateTarget`), Emoji-fy (`rewrite.emoji`), Proofread (`glyf.proofread`). A typed instruction runs `custom.prompt` with the `prompt` variable.
- The result streams into a card over the keys with **Replace** (black pill), **Insert**, **Copy**. It **never auto-inserts** (SPEC 6.4). Errors appear inline ("Couldn't reach Glyf. Tap to retry."). The status line shows runs left.
- Design history: the purple Replace and purple washes were removed on 2026-09-12 22:26 (Arpit: "i dont like this screen much, improve it"); Replace became the black pill, siblings white with hairlines, the result a white card.
- The server's engine strips leaked internal directive tags like `[[tighten]]` that a live model once echoed on empty input.

### 5.7 Glyf Keys: bound letters, the purple dot, the hold ripple, skill HUDs

**Binding.** Any letter can hold one action (`bindings` in settings). Bound keys show a **5pt purple dot at the top right** of the key. That dot is the brand mark (the logo is a keycap "g" with the same dot).

**Firing (iOS, `KeyboardView.swift`).** Press a bound letter: a 2pt purple **charge ring** contracts from 1.18 times onto the key edge over **320 ms**. Release earlier and you get the letter (long-press is additive, SPEC 1.4). At 320 ms, **ignition**: medium haptic, the key turns solid purple with a white glyph, and a **ripple** crosses the board: each other key's tint layer flashes (opacity 0 to 0.55 to 0) delayed by its distance from the origin times 22 ms per key pitch, 150 ms in and out. The surface starts rising 60 ms after ignition so it feels caused by the ripple (SPEC 5.3). Reduce Motion: no ring or ripple, just the haptic and a 120 ms flash. The HTML ripple prototype the spec mentions (`glyf-ripple-prototype.html`) was never in the repo, so timings come from the SPEC 5.3 table. The spec asked for a precomputed distance table; the code computes distances at ignition (about 30 keys, cheap). The 60 fps Instruments profile is still pending (device work).

**What a binding does** (`kbBoundKeyIgnited`):

| Binding value | Result on iOS | Result on Android |
|---|---|---|
| a Glyf id (for example `glyf.proofread`, `keyless.weather`, `user.<8hex>`) | **Skill HUD**: the act surface shows the skill's name over the letter's keycap while it works, the answer streams in, then ↻ / Copy / Insert. Input is the field text (Insert swaps it) or, if the field is empty, the clipboard (Insert only adds). Needs Full Access; without it the Glyf Bar opens and explains. Never in secure fields. | Same skill HUD in the act panel |
| `surface:translate-hud` | Toggles the Translation HUD strip (section 5.14) | Opens the app |
| `surface:tones` | Opens the tones popup (section 5.14) | Opens the app |
| `surface:vault` (or `surface:notes`, an alias) | Opens the in-keyboard Vault screen | Opens the app |
| `connector:mockcal` | Opens the ConnectorSurface calendar (section 5.15) | Opens the app |

Skill HUDs replaced the older behavior (the bar opening pre-run) on 2026-09-14/15 as part of Acti parity. UI tests: `test05_GlyfKey_T_TranslationHUD`, `test04e_BoundKeySkillHUD_ProofreadInserts`, `test10_TonesPopup_R_RewritesCasual`, `test11_KeylessWeather_W`, `test12_ConnectorSurface_C_InsertsEvent`.

**Bound-key look, and how it got here** (details in section 8.3): lavender wash plus accent outline rings (M1) → Arpit on 2026-09-13 01:57: "idiot lavendar lashes are not problem, see borders ... i think lavender dots are still fine, see acti has a blue light in M key" → rings removed for good, dot kept, soft purple under-glow added → 02:13 "still too much shadow and not glassy keys ... by default we need simple v similar to apple with just purple dots and glassy keys" → default became **glass keys with the dot alone**; the wash plus under-glow survives as the optional **Glow** key style. Never reintroduce accent borders on keyboard keys. (The Flutter Home key map still draws a light purple border on bound keys; see section 11.4.)

**Android** (`GlyfKeyboardView.kt`): 320 ms charge ring on bound letters (`BOUND_HOLD_MS`), dot on bound keys, Glow theme wash and halo. No ripple across the keys yet.

### 5.8 Default keys, recommendations, personas, packs

**Shipped defaults** (3 keys since 2026-09-12): `t` Translation HUD, `s` Vault, `p` Proofread.

**Per-key recommendations** (`app/lib/core/recommend.dart`). Tap a free key on the Home key map and a sheet shows "Recommended for 'X'" with three picks (the letter is the memory aid), excluding actions already bound elsewhere, then "Browse all". The per-letter table:

| Key | Picks | Key | Picks |
|---|---|---|---|
| c | Calendar picker, Tighten | n | Notes, Smart reply |
| d | Define, Hinglish | p | Proofread, Make it polite |
| e | Emotion check, Emoji-fy | q | Price check, Weather |
| f | Shuddh Hindi, Price check | r | Humanize (tones), Smart reply |
| g | Wiki lookup, Summarize | s | Vault picker, Summarize |
| h | Hook writer, Hinglish | t | Translation HUD, Tighten |
| j | Emoji-fy, Smart reply | u | Summarize, Expand |
| k | Tighten, Summarize | w | Weather, Hook writer |
| m | Stock check, Price check | x | Super X reply, Expand |

Fallbacks for every letter: Tone shift, Smart reply, Summarize.

**Personas** (onboarding "What fills your day?", keys bound on finish; the user can untick any):

| Persona | Keys |
|---|---|
| Studying (`student`) | u Summarize, x Expand, r Humanize |
| Working (`working`) | k Tighten, r Humanize, c Calendar picker |
| Creating content (`creator`) | h Hook writer, x Super X reply, j Emoji-fy |
| Mostly texting (`texting`) | j Emoji-fy, e Emotion check, r Humanize |

**Packs** (`app/lib/core/packs.dart`, Build tab). Applying a pack merges its bindings after a sheet that lists each key and marks conflicts ("replaces X"); nothing is overwritten silently.

| Pack | Keys |
|---|---|
| Writer | p Proofread, k Tighten, u Summarize, r Humanize |
| Operator | w Weather, q Price check, c Calendar picker, s Vault picker |
| Social | x Super X reply, e Emotion check, h Hook writer, j Emoji-fy |
| Desi | d Hinglish, f Shuddh Hindi, t Translation HUD, r Humanize |

The spec's Trader pack (crypto keys) belongs to M8 and does not exist. The in-keyboard Packs screen lists Writer, Operator and Social but its rows do nothing; packs are applied in the app. UI test `test14_PackApplyWithKeyDiff`.

**The catalog the app shows** (`app/lib/core/catalog.dart`): 22 Glyfs (Make it polite, Tighten, Professional, Translate, Emoji-fy, Proofread, Clean dictation, Formal dictation, Tone shift, Expand, Summarize, Smart reply, Hook writer, Emotion check, Super X reply, Hinglish, Shuddh Hindi, Weather, Price check, Define, Wiki lookup, Stock check) plus 5 bindable surfaces (Vault picker, Translation HUD, Humanize, Calendar picker, Notes). Dictation Glyfs are not bindable. The definitions themselves live on the server as Builder-format JSON (`server/src/registry/glyfs/`, 23 files including `custom.prompt`), never in Swift or Kotlin (SPEC 13). The keyboards only know ids and display titles (`GlyfCatalog.swift`; `skillTitle` in `GlyfIME.kt`), plus `customTitles` for custom and community Glyfs.

### 5.9 The in-keyboard menu (the g button, "GlyfShell")

SPEC 6.3: the user should rarely need to leave the keyboard; the container app is an escape hatch.

**iOS (`Surfaces/GlyfShell.swift`).** Memory rules from the spec are followed: screens are **data** (`Screen` structs with a `Row` enum) rendered by **one reused `UITableView`**; popping discards data, never a view controller tree; icons are small SF Symbols. The list is drawn the way Settings draws an inset-grouped table (2026-09-24): the rows of a group share one 12pt-radius card, a 0.5pt separator (`Glass.strokeSeparator`) runs between them from where the text starts, a `.header` row is a section title in 13pt small capitals above its group, an `.info` row is a footer, and an accent or danger `.action` sits in a card of its own. Rows are 44pt with 15pt regular text, switches are the system size (a tap anywhere on the row flips one with its own animation, and the list is not reloaded for it), segmented controls show capitalised titles, and a nav row's detail sits right-aligned beside the chevron. The Settings screen carries the same sections and words as the app's Keyboard screen (Typing, Feel, More); the Toolbar screen gives every item a ↑ beside its switch instead of a "move up" row. Each screen change logs `GLYF_MEM surface=shell:<id>` (budget: the shell adds at most 6 MB; simulator samples showed 1 to 2 MB per screen).

- Chrome: 36pt header (back chevron, title, close ✕); footer "Open in Glyf app ↗" on screens that have an app counterpart (opens `glyf://open?path=<screen>` through `HostAppOpener`).
- **Root is a launcher grid**, 4 columns of icon tiles with labels: Search, Glyfs, Glyf Keys, Connectors, Vault, Shorthand, Clipboard, Packs, Settings. Arpit on 2026-09-13 15:04: "list looks v bad here ... we need icons with text in bottom and rows and coloumns not everything in one columns, i think u need to show this list here how we show apps in dock".
- Deeper screens are **card rows** (rounded cards with an icon or keycap chip, a title, a data-only detail, and a trailing control). Rebuilt 2026-09-13 21:49 after "see this screen looks good but, other screen look bad i have attached": no explainer sublines, display names instead of raw ids (a `glyf.summarize` leak was fixed), unbinding moved to a small ✕ (tapping a row no longer unbinds by surprise).
- Screens: **Settings** (Appearance auto/light/dark, Key style glass/classic/glow, Haptics, Key sounds, Number row, Autocorrect, Auto-capitalize, "." shortcut, One-handed off/left/right, Paste title with link, Toolbar items), **Toolbar** (show/hide and move items up), **Vault** (combos, fields, notes with ✎ edit, "＋ New note"), **Shorthand** (triggers and expansions; tap inserts), **Clipboard** (history with pin; "Clear unpinned"), **Glyf Keys** (bound letters as keycap chips with the dot, display names, ✕ to unbind), **Glyfs** (catalog list, rows do nothing), **Connectors** (Calendar opens the demo calendar; a "Google · Notion · Slack soon" line), **Packs** (rows do nothing), **Account** ("Free · N runs left today"; not reachable from the grid and it does not read the plan).
- The nav stack is saved to `shell-state.json` and restored if the keyboard reopens within 60 seconds.
- UI test `test02_ShellNavigationAndSettings`.

**Android (`showMenuGrid` in `GlyfIME.kt`).** A 3-column grid: Search, Vault, Shorthand, Clipboard (pastes the current clipboard), Emoji, Settings (opens the app). Panels replace the keys with a back row and a title: Vault (fields and notes; tap inserts, long-press a note to edit, "＋ New note"), Shorthand, Emoji. There is no Glyfs, Glyf Keys, Connectors, Packs, Settings or Account screen inside the Android keyboard.

### 5.10 Vault, shorthand, and notes

**Vault** ("the feature users open the app for daily", SPEC 6.7). Saved personal info you drop into any field.

- **Model** (`Engine/VaultStore.swift`): fields (`kind`, `label`, `value`; kinds `name, email, phone, address, upi, gst, wallet, link, social, bio, reply, custom`), combos (several fields inserted together, joined by new lines, for example a shipping block), and snippets (`;trigger` → text).
- **Encryption**: the whole vault is one AES-GCM sealed blob, `vault.enc`, in the App Group; the 256-bit key is created on first use in the shared Keychain group (accessible after first unlock). Unit tests prove ciphertext on disk, cross-store decrypt with the same key, and "wrong key reads as empty". The cross-process decrypt (app writes, keyboard reads) was proven live by UI test `test08` on 2026-09-12.
- **Refusals** (`VaultRules`, SPEC 6.7 and 11.3), shown verbatim in the app: unsupported kind; a label containing password, passcode, pin, otp, cvv, seed, private key or recovery; card numbers (13 to 19 digits passing Luhn); seed phrases (12, 15, 18, 21 or 24 lowercase words of 3 to 8 letters); private keys and API tokens (known prefixes `sk-`, `sk_live_`, `sk_test_`, `rk_live_`, `rk_test_`, `whsec_`, `xoxb-`/`xoxp-`/`xoxa-`/`xoxr-`/`xoxs-`/`xapp-`, `ghp_`/`gho_`/`ghu_`/`ghs_`/`ghr_`/`github_pat_`, `glpat-`, `AKIA`/`ASIA`, `AIza`, `ya29.`, `npm_`, `hf_`, `shpat_`/`shpss_`, `SG.`, `sq0atp-`/`sq0csp-`, `privy_app_secret_`; JWTs; PEM private key blocks; 64 hex characters; 80 to 90 character base58 strings; any unbroken 40+ run of key characters; and 32+ letters and digits mixing both cases, with public wallet addresses (EVM `0x` + 40 hex, Bitcoin bech32, base58 25 to 44) exempt because the pay chip reads a copied one); 6-digit one-time codes; government IDs (12-digit Aadhaar, PAN pattern `AAAAA9999A`, US SSN `xxx-xx-xxxx`); empty values; values over 2000 characters. Snippet triggers must start with `;`, be 2 to 12 characters, and contain no spaces or extra semicolons.
- **Add and edit happen only in the app** (SPEC 6.3: no free-text secret entry inside the keyboard). `app/lib/vault/vault_screen.dart` uses non-dismissible form sheets with a header Save and an explicit ✕ (stray barrier taps were eating input during tests), and Semantics identifiers `vault-label-field`, `vault-value-field`, `vault-save`.
- **Insert from the keyboard**: hold `S` (default binding `surface:vault`) → ripple → Vault screen → tap a field or combo; or the toolbar Vault item; or the menu's Vault tile.
- **Android** (`store/VaultStore.kt`): AES-GCM with a key in the Android Keystore (IV plus ciphertext in `vault.enc`), same JSON shape. Its rules differ from iOS (section 11.4): a smaller kind list, no label or government-ID checks, a different trigger rule, and the keyboard's vault panel shows fields and notes but not combos.
- Tests: `RunnerTests/VaultTests.swift` (blocked types, allowed fields, encrypted round trip and combos, shorthand expansion, snippet validation); UI tests `test08_VaultPickerAndShorthand`, `test09_VaultBlocksSecrets`.

**Shorthand** (`Shorthand` in `VaultStore.swift`). Type a trigger such as `;sig` and then space: the trigger is replaced by its text before autocorrect looks at it, and backspace undoes it like an autocorrection. Exact prefix triggers only ("predictable beats clever"). Not applied in secure fields on iOS. Android does the same in `handleSpace`. The `;sig` test seed text starts with an em dash character followed by "Arpit · tryglyf.com" (changed from the invented glyf.so domain on 2026-09-14).

**Notes.** Added 2026-09-12 after "app needs to have in app notes too which user can access like we have in s key".

- Store: `Engine/NotesStore.swift` and Kotlin `NotesStore` (`notes.json`, plain JSON because notes are user content they can already read; at most 2000 characters; secrets refused by `SecretScanner`).
- App: `app/lib/notes/notes_screen.dart` (Profile → Notes).
- Keyboard: on 2026-09-13 Arpit said "notes shud be editable from here also , we can remove notes and vault can serve the feature and shorthand can be another thing". So notes now live **inside the Vault screen**, Shorthand got its own tile, and notes can be written without leaving the keyboard: `Surfaces/NoteEditSurface.swift` is a strip above the letter keys (✕, the note, a black Save; Return adds a new line). In the default look the Vault screen is the three-column card grid: notes are cards (tap inserts, **hold edits**) and the last card is **＋ New note**; the list-style screen of the other looks has the same ✎ and "＋ New note" row. Android has the same strip (`enterNoteEdit`). `surface:notes` bindings open the Vault screen.

### 5.11 Clipboard: history, categories, screenshots, and what iOS allows

Rewritten 21 to 22 Sep 2026. The panel is `Surfaces/ClipboardPanel.swift`, the store is `Engine/ClipboardStore.swift`.

**What the panel shows.** A two column masonry of cards under a row of filter pills.

- **Pills: All / Text / Link / Image.** Kinds, which is what a row of pills is for. Pinned is not a kind, so it stays a section: researched against Gboard and Acti before building.
- **PINNED then RECENT**, and pinned leads only within the kind being shown, so picking Link never scrolls you past pinned text to reach the links.
- **RECENT runs in time order**, copies and screenshots interleaved by when they happened. Screenshots used to sit in a block above every copy however old, so a shot from yesterday buried something copied a minute ago.
- **Hold a card** and the rest dim while a menu offers Paste, Save to vault, Pin / Unpin, Delete.
- Store rules: last 20 items, unpinned expire after **48h** (a copy from yesterday is exactly what you come looking for), pinned never expire or get evicted, 4000 characters max, duplicates collapse, and secret-shaped text (`SecretScanner`) is never stored.

**What counts as a Link.** `NSDataDetector`, the same detector iOS uses everywhere, so a bare domain counts without anyone typing `https://`: `tryglyf.com` belongs under Link. The match has to cover the **whole** clip (a sentence mentioning a link is still a sentence, and Text and Link must stay exclusive or the pills stop adding up to All), and a `mailto:` is left to Text because an address is something you paste into a To: field, not something you follow.

**The permission model, which is the whole difficulty.** iOS hands a keyboard nothing from the clipboard on its own.

| Call | Gives you | Silent? |
|---|---|---|
| `changeCount`, `hasStrings` | that something changed, not what | yes |
| `detectPatterns` | which patterns are present, no values | yes |
| `detectValues` | the actual link / number | **no** |
| `.string` | everything | **no** |
| `UIPasteControl` → `paste(itemProviders:)` | everything the person tapped for | yes, the tap **is** the consent |

`detectValues` being loud is the trap, and it cost a build to learn: handing over a value is a read, and iOS raises "Allow Paste?" for it exactly as it does for the whole string. Only `detectPatterns`, which answers with types and no values, stays quiet, and a type is not something a chip can show. So there is **no silent way to know what was copied**, and the two honest routes are the Paste button (no permission needed) and an opt-in that asks per copy.

**Defaults and the migration (22 Sep).** Both clipboard switches ship **on**, because a clipboard that misses what you copied reads as broken. Arpit: "i want it should auto get evrrything from new ss to new copied things".

- `clipboardCaptureAll` on: every copy is taken. iOS asks once per copy until the person sets **Settings → Glyf → Paste from Other Apps → Allow**, after which it never asks again. No app can write that setting.
- `clipboardScreenshots` on: this is the **wish**, not the permission. Only the container app can ask for the photo library, and the ask is the moment that switch is turned on. When the wish is on and the library is not granted, the panel says which of the two is missing rather than showing empty space.
- A settings file written before this decodes both as `nil`, not as the new default (Swift's synthesized decoder does not apply property defaults), so schema **v7 to v8** fills a blank with yes. A stored `false` is a real answer and is left alone. Tests: `testOlderInstallsGetTheClipboardFillingItself`, `testTurningTheClipboardOffSurvivesTheMigration`.

**The panel says what is in the way.** `blockers()` lists the yeses still missing, in the order they cost you, as tip cards at the end of the list. A clipboard quietly missing things looks broken; one that names the setting looks unfinished, which is what it is.

**Two defaults that disagreed (found 22 Sep).** `clipboardScreenshots` defaulted to `true` in Swift and `false` in the app's switch, and the keyboard's guard was `!= false`. So the app said screenshots were off, the keyboard believed they were on and went to a photo library it had never been given, and no screenshot ever appeared either way. Both are `true` now and the keyboard wants an explicit `== true`.

**The strip chip.** When something has been copied, the strip offers it as a Gboard-style pill: the clipboard mark, the words themselves where they are known, and a ✕ that dismisses that copy for good. It shows the **content** rather than "Paste what you copied" whenever the content is available, which is what capture being on buys. `Surfaces/ClipContextStrip.swift` is dead code from the older design and is not instantiated.

**Android never waits on the media index (24 Sep).** Right after a screenshot is taken, MediaStore is still indexing it and can take seconds to answer. The Android keyboard used to ask it on the main thread, twice: for the list of recent screenshots when the panel opened, and for the image's type when one was tapped. During the scenario run the emulator's storage service stalled for 15 seconds, and Android reported the keyboard as not responding (an ANR). Now `ClipboardPanelView` shows the copies at once and adds screenshots when a background query answers, `insertImage` looks up the type on a worker, and a GIF or sticker file is written on a worker too. Only the hand-over itself (`commitContent`, or the clipboard and its toast) runs on the main thread.

**A copied picture is not text (24 Sep).** Five places on Android read the clipboard with `coerceToText`: the strip's paste chip, Paste, the g bar's input, a skill run on the clipboard, and history capture. For a picture (a screenshot tapped in the panel, a GIF sent to a field that takes none), `coerceToText` opens the image and returns its bytes decoded as words, on the main thread. After a screenshot was copied, the paste chip's label held its PNG, about 200,000 characters. All five now go through `ClipboardStore.clipText`, which answers with the copied text, or a web link copied as a link, and nothing for anything else. S98 fails if any label on the keyboard grows past 1,000 characters.

### 5.12 Emoji

- **iOS** (`Surfaces/EmojiBoard.swift`, `Design/EmojiData.swift`): one collection view with text-only cells (no images, for memory), categories, recents (`emoji-recents.json`), long-press for 5 skin tones, and search over a compact built-in name map (the full Unicode name table costs too much memory). Opened by the bottom-row emoji key or the toolbar. Laid out and measured against Apple's own emoji keyboard on the iOS 26.5 simulator (2026-09-24): Apple's nine tabs in Apple's order (Frequently Used, Smileys & People, Animals & Nature, Food & Drink, Activity, Travel & Places, Objects, Symbols, Flags; the People list now sits inside Smileys and a Flags tab was added, flags built from ISO codes), light-weight SF Symbol glyphs close to Apple's (`teddybear`, `takeoutbag.and.cup.and.straw`, `soccerball`), a rounded-rectangle search field (radius 12, `#eff0f4`-like fill on the light sheet) instead of a pill, and Apple's lighter grey for the section name. The section name, the five rows and the bottom bar land within about 1pt of Apple's. The board always opens on Emoji. Beside the search field, four glyphs switch what it holds (section 5.24).
- **Emoji search shows the letter keys.** On 2026-09-13 19:36 Arpit reported from his iPhone: "Small bug - i can’t search in emojis because keyboard not showing". Now tapping "Search emoji" collapses the board to a 96pt strip (the field and one row of results, recents while empty) with the letter keys underneath; Return or ABC brings the grid back and clears the query (Apple's behavior). The same trap existed in the connector search and was fixed the same way. UI tests `test03_EmojiBoard`, `test03a_EmojiSearchShowsLetterKeys`.
- **Android** (`ime/EmojiBoardView.kt`, data generated from the Swift lists into `ime/EmojiData.kt`): the same board as iOS since 2026-09-24, Apple's nine tabs as canvas-drawn glyphs (`ToolIcon`), five rows paging sideways (a `RecyclerView` grid; every section padded to whole columns so a tab jump lands on the section's first emoji), recents, long-press skin tones, search in a strip over the letter keys (starts lowercase), and the Stickers, GIFs and Emoticons modes of section 5.24. Opened by the bottom-row emoji key and the toolbar's emoji tool.
- Not built: emoji suggestions from AOSP's emoji shortcut list.

### 5.13 Search suite: Google-style Search, YouTube, Maps, Contacts

**Why.** On 2026-09-13 Arpit sent Gboard screenshots: "need maps and youtube etc from google like gboard". The first version (DuckDuckGo instant answers, OpenStreetMap places, YouTube search links) shipped that day. On 2026-09-14 13:52, after seeing the website's search demo: "we need that in our keyboard with exact ui ux like that ... and when u click that its link is pasted on chat box ... we can have option in setting to paste only link or title and link and by default it should be title and link". Then at 14:32: "u should show the recent google searches or top google searches and same witth yt ... not put user in the search bar directly, same with maps, req location access and show nearby things".

**How it looks and works (iOS `Surfaces/SearchSurface.swift`, Android search panel in `GlyfIME.kt` plus `ime/SearchCards.kt`).**

- Opened from the toolbar magnifier (the first toolbar item since 2026-09-13) or the menu's Search tile.
- A row of chips: **Search** (drawn Google "G"), **YouTube** (drawn YouTube mark), **Maps** (drawn pin), **Contacts**, and on iOS **Translate** (which just opens the Glyf Bar on `glyf.translate`). Brand marks are drawn in code, not shipped as images, to keep the extension small.
- The query field is typed by the keyboard's own keys (`InlineEditor`); Return or the arrow runs the search.
- **Landing state** (never an empty box): your own recent searches for that tab (clock icon, stored on the device only, 6 per tab) and then trending searches, popular videos, or nearby places from `GET /search/suggest` (trend arrow). **The keys stay visible under the landing rows** so you can just start typing. This is a separate layout mode from results (`landingActive` vs `expandedForResults` on iOS; a panel capped at 3 rows inserted above the keys on Android). Both platforms first shipped it covering the keys; the UI test caught it.
- **Results replace the keys** (ABC returns to the landing rows). Cards match the tryglyf.com designs: an **answer card** (sunset and weather answers on a dusk gradient with a dotted sun arc; calculations and definitions on a plain card), **web link** rows, **YouTube** rows (16:9 thumbnail shown whole, not cropped, play badge, duration or LIVE chip, channel, a YouTube mark on every card), and **place** rows (photo or drawn map tile, name, distance, open now, rating when the provider has them). Thumbnails load through a small capped cache (`ThumbLoader`, 40 entries, 4 MB, cleared on memory warnings; Android `LruCache` sized in KB).
- **Tapping a card pastes it** into the field (and copies it). **Paste format** (checked against Gboard): the URL on the first line, then an emoji and the title (🎥 for videos, 📍 for places, nothing for web links), then for places a third line with the address. Setting "Paste title with link" (`pasteStyle`, default on) or link only. The format is implemented three times (server `composeInsert`, Swift `SearchCard.insertText`, Kotlin `SearchCard.insertText`) and locked by identical tests (`testPasteStyleTitleAndLinkMatchesGboard` and neighbors in `GlyfEngineTests.swift`). A contact row pastes the phone number or email itself.
- **Contacts tab** (Arpit: "i also need contact search feature like google board ask access if user enables it"): Profile → Contacts search shows an explanation, asks the OS, then syncs a minimal index (name, phones, emails, at most 2000 contacts) into `contacts.json`. The keyboard only reads that file; nothing is uploaded. Verified on the Android emulator on 2026-09-13 (searched "arjun", tapped, the number landed in the field).
- **Location for "near me"**: a keyboard cannot ask for location, so the app asks (onboarding step "Search what's near you", or Profile → Nearby search), takes **one coarse fix** (iOS `LocationOnce`, kilometer accuracy, 12 s timeout; Android the most recent last-known location), rounds it to about 1 km, and stores `lastLat`, `lastLon` and `region` in settings. The keyboard sends them (plus time zone) with searches and act. Nothing is stored on the server. Verified on the iOS simulator on 2026-09-14: "Sunset" returned nothing before location and "6:23 PM" for Bengaluru after; trending and YouTube charts switched from US to Indian content. Set a simulator location with `xcrun simctl location <udid> set <lat>,<lon>`.

**Providers and keys** (server-side; all optional; `GET /search/status` reports which are live):

| Tab | Provider chain | Status on 2026-09-16 |
|---|---|---|
| Search (web) | `BRAVE_SEARCH_KEY` first (independent index, about $5 per 1000; its terms forbid caching); `SERPER_API_KEY` opt-in fallback only (real Google results, cheap, but resells scraped results in a category Google is suing over) | **No key set**: the tab is instant answers only (math via a real parser, never `eval`; sunrise and sunset computed locally with the NOAA equation; time; currency; Wikipedia) plus a "See all results on Google" row. It never shows a fabricated list. |
| YouTube | `YOUTUBE_API_KEY` (there is no legitimate keyless YouTube search) | **Live** since 2026-09-14 (Arpit created a key with "Public data"). Default quota is 100 searches per day for the whole project; there is no record that the quota extension form was filed. |
| Maps | `GEOAPIFY_KEY` (no credit card, 3000 requests per day, commercial use allowed with "Powered by Geoapify" attribution; OpenStreetMap data: no ratings or open-now); or `GOOGLE_PLACES_KEY` (billing required; ratings and open-now are an expensive tier) | **Waiting on `GEOAPIFY_KEY`**. Nominatim works only in development (`NODE_ENV` not production) because OSM caps a whole server at 1 request per second. Overpass is opt-in via `OVERPASS_API_BASE` (it timed out at 13 s). |
| Weather answer | `GOOGLE_WEATHER_KEY` | Optional, not set |

**What was researched and rejected (2026-09-14, settled, do not revisit):**

- **DuckDuckGo as the web tab**: Arpit suggested it ("or i think just use duck duck go here for search"). Measured: its Instant Answer API returned nothing for every ordinary query tried ("best pizza near me", "how to fix a flat tyre", "iphone 17 pro review", "flight status AI 806", "nike running shoes"); it is a Wikipedia-abstract service and commercial use needs approval. Removed.
- **Google's own search API**: Custom Search JSON is closed to new customers (existing ones cut off 2027-01-01) and new Programmable Search engines are capped at 50 domains. "Grounding with Google Search" returns an AI answer whose terms forbid showing other results next to it. Bing's API retired in August 2025. No Google product returns google.com results as data for a new customer.
- **Embedding a browser and using the user's Google login** (Arpit: "just embed browser in it and visit google.com and fetch results and take login from user in on boarding"): dead at every layer. Google blocks OAuth inside app-controlled webviews (HTTP 403 `disallowed_useragent`, since 2021-09-30); Juno for YouTube was pulled from the App Store under 5.2.2 for merely restyling youtube.com in a webview; a logged-in user is bound by Google's terms (Facebook v. Power Ventures; Meta v. Bright Data won because it was logged out), so the user's accounts would get flagged; Apple 4.4.1 forbids a keyboard launching other apps (killing a deep-link fallback); and a keyboard extension cannot afford a full web page in memory.
- **A Piped (YouTube-scraping) fallback**: removed (same terms exposure, public instances collapsed).
- **"Recent YouTube views" from a Google login**: impossible. No scope grants Search history or YouTube watch history. The optional `youtube.readonly` scope (onboarding's YouTube row) only adds the user's liked videos and subscriptions to the YouTube landing row. It is a sensitive scope that needs Google app verification before public launch. Arpit on the key wizard: "i think we need user data here for his recent view etc or no? shud we just do public for now ?" → public data for now.
- **Mock results on screen**: the UI tests use `MOCK_AI=true` fixtures; once they were left on and Arpit saw them ("you have hard coded results in ios idiot the fuck make them work"). The server must run without `MOCK_AI` whenever a human looks at the app.

UI test: `test03b_SearchSuiteCardsAndPasteFormat` (needs the mock server).

### 5.14 Translation HUD (hold T) and the tones popup (hold R)

**Translation HUD** (`Surfaces/TranslationHUD.swift`, SPEC 6.13 T). Holding `T` (default binding `surface:translate-hud`) toggles a persistent 44pt strip above the toolbar. As you type, each committed word hands the text before the cursor to the HUD, which waits 0.35 s and translates it with `glyf.translate` into `translateTarget`. A language chip shows the target. Tapping the strip replaces your draft with the translation (always an explicit tap, never automatic); ✕ turns the HUD off. The state persists in settings (`translationHUD`). It never shows in secure fields or under another surface. The target language is picked in the app's Keyboard sheet: English, Hindi, Hinglish, Spanish, French, German, Portuguese, Japanese. Before M5, `T` was a one-shot translate; the v3 settings migration upgrades old installs. The toolbar Translate item is still a one-shot translate through the Glyf Bar. Android: holding a `surface:` key opens the app, and the toolbar Translate runs a one-shot translation overlay.

**Tones popup** (`Surfaces/TonesPopup.swift`, SPEC 6.13 R, "Humanize"). Holding a key bound to `surface:tones` shows "Rewrite your draft as..." over the keys with four pills: Natural, Professional, Casual, Gen-Z. A pick runs `rewrite.tone` with the `tone` variable and shows the result in the Glyf Bar with Replace / Insert / Copy. iOS only.

### 5.15 Connectors: the calendar picker, OAuth, keyless tools

**ConnectorSurface** (`Surfaces/ConnectorSurface.swift`, SPEC 6.12). A picker that rises inside the keyboard instead of a blind one-shot action. Built once to be reused for every connector; **today it only talks to the demo calendar** (`connector:mockcal`, server routes `/connector/mockcal/events` and `/connector/mockcal/month`, deterministic events).

- Title "Calendar · today", a search field (results refresh 250 ms after typing), 44pt rows, a bottom action.
- **Opens with the default query already run** (never empty) and paints a cached result set instantly if it is under 5 minutes old.
- Tap a row → an inline menu (a pill row, because `UIAlertController` gets clipped in the keyboard window): **Link**, **Time + title**, **Details**.
- **Month view** (Arpit, 2026-09-12 19:15: "in calendar option i also need a button to view months calendar along with my todays tasks"): a Month / Today toggle; the grid shows event dots and a pill on today; tapping a day inserts the date (for example "September 14"). At 22:26 Arpit asked "why does the month have soo much gap below it": the grid now stretches to fill the surface (rows computed from the days, cell height up to 62).
- Tapping search collapses the surface to a 184pt strip with the letter keys below (same rule as emoji search).
- The phone's own calendar (`Surfaces/CalendarSurface.swift`, Connected tools → Calendar): the day's events full width, **Insert date** ("September 24") beside **Share free time**, a Month grid to jump days, "Nothing planned" on an empty day, and before the calendar is allowed a line saying where to allow it (section 5.28). Adding events, booking pages, call links and invites: section 5.28.
- The action "New event from my text" currently only opens the app. Offline shows "Offline" plus a hint to start the server.
- UI test `test12_ConnectorSurface_C_InsertsEvent`.

**OAuth broker** (server-side, SPEC 6.11). Tokens are stored on the server keyed by device and provider and are **never sent to a phone**. The phone only learns connected or not, the scopes, and the account email.

- **Google**: Arpit on 2026-09-12 18:42: "we need a login when app is opened the first time and there only user can decide what all he wants to give access to mail, calendar, meet etc ... we can have this at the end of onboarding flow based on the answered questions". The consent URL is built with the scopes the user ticked (identity `openid email profile` always; Calendar `calendar.events`; Gmail `gmail.compose`; Meet `meetings.space.created`; YouTube `youtube.readonly`), with PKCE S256 and a 10-minute pending state. The browser comes back through `/oauth/google/callback`, which redirects to `glyf://connected?provider=google&ok=...`; the app shows "Google connected" or "Google connection didn’t finish".
- **Eight more providers** (added 2026-09-12 19:15 after "did u add notion, slack , and other thigs, research on what all we can have and add it"): Notion, Slack, GitHub, Linear, Todoist, Calendly, Zoom, Spotify. Each activates the moment `<NAME>_CLIENT_ID` and `<NAME>_CLIENT_SECRET` are in `server/.env`; until then its start route answers 503 naming the missing variables. Suggested priority for a keyboard: Google, then Notion, then Slack, then Todoist or Linear, then Calendly or Zoom, then Spotify or GitHub.
- Connected tools execute inside Glyf runs: `calendar.today` reads Google Calendar, `notion.search` searches Notion.
- **In the app**: Profile → Connected tools today holds Private payments, Calendar, Google Meet, Booking link and Contacts, then Gmail, Notion, Slack and Spotify as Coming soon (section 5.28 for Calendar and Google Meet); the server OAuth providers above have no Connect button in the app. The Builder's Apps tab lists 11 apps (Google Calendar, Gmail, Google Meet, Notion, Slack, GitHub, Linear, Todoist, Calendly, Zoom, Spotify) with their actions and Ready or Soon.
- **Status: Blocked.** No OAuth client credentials have been provided, so no real account has been connected yet. Google needs both redirect URIs registered: `http://127.0.0.1:8787/oauth/google/callback` and `https://api.tryglyf.com/oauth/google/callback`.
- Not built from SPEC 6.13: pickers for Gmail (G), Notion (N), Drive (D), Slack (K), Contacts (A); instant Meet link (M); LinkedIn summon (I).

**Keyless tools** (server registry `server/src/registry/tools/`, 30 definitions: 25 general no-key tools, 3 search tools for the search suite (web, YouTube, maps), and 2 OAuth tools, `calendar.today` and `notion.search`). The general set was grown in two research rounds on 2026-09-12 (19:15 and 22:26, after "integrate as much free tools as possible"): weather, air quality, crypto price, stocks, currency, dictionary, synonyms, Wikipedia, place search, route ETA, holidays, books, tech news, sports fixtures, recipes, link preview, time zones, jokes, quotes, advice, facts, slang, country facts, GitHub repos, food facts. Every tool must carry a `discloses` string. Things that genuinely need paid keys (flight status, movie data, news wires) were left out, not faked. In the apps they show up as: the Builder's Tools tab (25 chips), and bindable Glyfs Weather, Price check, Define, Wiki lookup, Stock check. UI test `test11_KeylessWeather_W`.

### 5.16 Builder, your Glyfs, and the Skills hub

**Builder** (`app/lib/build/builder_screen.dart`, SPEC 6.8). Plain English in, a runnable and bindable Glyf out. Nothing runs on the phone; the definition is the server's Builder format.

1. **"What do you want?"**: a description field with example chips, above an **Available tools** browser (Apps tab: 11 connectable apps with their actions and Ready or Soon; Tools tab: keyless tool chips). This layout came from Arpit's 2026-09-12 17:59 request "i really wanna revamp the builder screen i will tell how acti does it" and his Acti screen recording. Acti's "Agents" tab (coming-soon cards) was deliberately skipped.
2. **Generate** calls `POST /builder/generate` (the app waits up to 90 s, since free models are slow). The server asks its smart model for strict JSON, validates it against the schema and moderation, retries once, then fails closed with a clear error.
3. **Review**: the steps appear as cards; prompts and templates can be edited in place.
4. **Test** on sample text (`POST /builder/test`).
5. **Name and save** (`POST /glyfs`; the server assigns a `user.<8 hex>` id).
6. **Bind** to a key with the letter picker (`key_picker.dart`; taken keys are dimmed but can be rebound). Binding records the display name in `customTitles` so the keyboard can show it.

The format supports chaining and conditionals from day one (step types `llm`, `tool`, `format`, `if`, `map`, `ask`; `tool` steps resolve only against the server registry; every Glyf declares `discloses`). The server wires the input into generated prompts that forget it (`ensureInputWired`). A **visual chain editor** is not built (M9). If a test run hits the free cap, the paywall opens. UI test `test13_BuilderMockEndToEnd`.

**Build tab** (`build_tab.dart`): "Build your own" card, Packs (horizontal cards), **Mine** (your saved Glyfs: bind to a key, publish, delete; labeled Published or Private), and a **Skills** preview (top 5, "See all"). Publishing re-runs moderation on the server. The tab refreshes when you come back to it (tabs keep state, so it used to show stale data).

**Skills hub** (`skills_screen.dart`, built 2026-09-15).

- Decision history: on 2026-09-12 17:59 Arpit said "i think acti skill sharing platform etc is bad, we should make out own skills and ask users to select what they want ... also give users option to create their glyfs", so the curated library led and the community hub became a quiet section. On 2026-09-14 he sent Acti's launch video ("i need all features from it as well"), which features a Skills community, so a proper hub was built.
- One list mixing shipped skills (author "Glyf") and community skills, most-installed first (`GET /skills`). Search field. Category chips derived from what a skill does, never stored: Writing, Social, Language, Lookups, Markets, Community (empty categories hide). A creators strip (`GET /skills/creators`) that filters the list; creators appear only after they publish, never seeded.
- Install counts are real, count each device once, and show only once there is one ("Glyf · 12 installs", "by Maya").
- **Get** opens a sheet listing exactly what the skill can access (its `discloses`, verbatim), then Get → pick a key → bound. Community skills are version-pinned (`POST /skills/get`). Rows show the key a skill is already on.
- When the server is unreachable, the list falls back to the on-device catalog (no counts or categories).
- Verified on the Android emulator on 2026-09-15. A leak was fixed the same day: the public hub list exposed each publisher's device ID, which works as their credential.
- QA note: after testing install flows, stop the server and reset `server/data/accounts.json`, `installs.json`, `skill-installs.json` and `skill-installs-by.json` (the file store caches in memory).

### 5.17 Dictation (Raw / Clean / Formal)

SPEC 6.6: keyboard extensions cannot use the microphone, so the app records. "Post-processing is the product."

**iOS flow (path 1, in-app capture and handoff), built 2026-09-12:**

1. Toolbar mic → the keyboard writes a `dictation` intent (section 3.8) and opens `glyf://intent?id=...` through `HostAppOpener`. If opening fails: toast "Open the Glyf app to record".
2. The app opens `RecordingSheet` (`app/lib/dictation/recording_sheet.dart`), from the deep link or on launch or resume if an intent is pending. The sheet **consumes** the intent first (expired or replayed intents are refused).
3. `DictationEngine.swift`: `AVAudioEngine` plus `SFSpeechRecognizer` with live partial results and `requiresOnDeviceRecognition` when supported; a pulsing orb mic, a live transcript and a timer; 60-second cap. Audio never leaves the phone.
4. Stop (0.7 s grace for the last words) → "How should it read?": **Raw**, **Clean** (`dictation.clean`, fetched immediately, default), **Formal** (`dictation.formal`, fetched in parallel). The sheet shows "clean ready in N ms". Only the chosen text goes to the server, and only for Clean or Formal.
5. **Insert** writes the result; a snackbar says to switch back.
6. Back in the host app, the keyboard inserts the text exactly once ("Dictation inserted").

- The "under 4 seconds for a 10-second clip" gate is met by design (the raw transcript is ready at stop), but **real-microphone latency was never measured on a device**.
- Simulator: the speech stack is unreliable, so `--glyf-fake-dictation` (or automatic fallback when speech is unavailable) streams a canned filler-laden script with a visible "simulated" badge.
- Usage strings: `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription` in `app/ios/Runner/Info.plist`.
- Not built: SPEC path 2 (system dictation passthrough with cleanup).
- Depends on `HostAppOpener` and is therefore exposed to the Guideline 4.4.1 question (section 11.2).
- **Android: not built.** The bridge methods are no-ops ("Dictation lands in the Android update").
- Tests: `IntentStoreTests` (5), UI test `test07_DictationEndToEnd`; log marker `GLYF_DICT` in `docs/evidence/m3-m4-keyboard-logs.txt`.

### 5.18 Themes, key styles, and dark mode

**Key styles** (`keyTheme`, 2026-09-13 02:13, after "still too much shadow and not glassy keys, also give option to edit keyboard designs in app, like gboard gives"):

| Style | Look |
|---|---|
| **Glass** (default) | Translucent keys over the keyboard's single blur (white 58% in light, 14% in dark), whisper shadow (0.08 light, 0.22 dark), bindings marked by the dot alone |
| **Classic** | Solid Apple-white keys (0.42 gray in dark), crisp 1pt shadow (0.20 light, 0.40 dark) |
| **Glow** | Bound keys get a faint lavender wash plus a soft purple under-glow (the treatment Arpit liked on 2026-09-13 01:57, kept as an option) |

**Appearance** (`appearance`, 2026-09-13 00:54 after "fix dark mode too"): `auto` follows the host field's `keyboardAppearance` or the system style, like Apple's keyboard; `light` and `dark` force it. `resolveAppearance()` recomputes the tokens on every appearance and trait change and re-skins the chrome. The dark palette matches the system dark keyboard (0.42 gray keys, white glyphs, dark blur). Before this, the keyboard was forced light because of the white-only lock. Evidence: `docs/evidence/v4-light-keyboard.png`, `v4-dark-keyboard.png`.

**Painted themes** (Profile → Keyboard → Look, `app/lib/profile/keyboard_screen.dart`, 2026-09-13 15:04 after Gboard's theme screens): Glyf (the system sheet), Glass, the colour boards (Stone, Lilac, Sky, Mint, Sand, Blush, Ink, Indigo, Midnight, Pine, Plum, Cocoa) and the gradients (Dusk, Ocean, Ember, Forest, identical colour pairs in Flutter, Swift and Kotlin), plus borders around keys and a dim slider. A colour or gradient **paints the board** the tile shows: on iOS a `CAGradientLayer` under the keys (`applyBoardPaint()`), the keys as the app's `KeyPalette` draws them (white on a light board, the board lifted 18.5% towards white on a dark one; function keys 14% darker on a light board and 12% lighter on a dark one, the same numbers in Dart, Swift and Kotlin), and the strip, panels and cards taking their ink from the board's brightness (`Glass.chromeDark`). A look picked while a keyboard is up applies to that keyboard: `SettingsStore.reloadIfChanged()` posts `changedNote` whenever it finds the file changed, and the controller's `settingsChanged()` refreshes bindings and appearance on the next turn. Only the 16pt band iOS draws above every third-party keyboard keeps the system colour. Forcing **light** or **dark** in Appearance on a host whose sheet is the other way paints the matching Apple sheet colour under everything (`Glass.sheetPaint`), so keys and chrome agree; in **auto** nothing is painted and the host's sheet shows. The host's appearance is read from the trait collection above the keyboard's own view (`view.superview`), because the keyboard's `overrideUserInterfaceStyle` reaches its own trait collection and would otherwise make a forced dark read as a dark host and drop the painted sheet. Not built: photo backgrounds and per-part colour pickers.

**Key style cards** also sit at the top of Profile → Keyboard, each a live mini preview of three keys with a check on the active one (pattern from Snapchat's theme grid on Mobbin). The in-keyboard Settings screen has segmented controls for Appearance and Key style.

**Theme audit** (2026-09-13 18:58, after "icons are not properly visible in themes and some glyf symboil not visible in glass theme , i need you to check everytheme and then fix all ui issues"): all 8 combinations were screenshotted on both platforms. Fixed: Android toolbar icons were washed-out emoji (now canvas-drawn monochrome glyphs); the black g pill vanished on dark backdrops (now a faint white ring; iOS also had a latent white-on-white bug, fixed with the constant `Glass.brandInk`); the space-bar "glyf" watermark keyed off system dark instead of theme darkness (it was nearly invisible on light glass; now its own `Glass.watermark` token); Glow was missing on Android; borders were too faint. Recipe used: inject `settings.json` (Android: `run-as com.demo.glyf sh -c 'cat > files/bridge/settings.json'` then refocus a field; iOS: edit the App Group file and re-show the keyboard).

**The Flutter app itself is light only** today (`Glass.theme()` builds a light theme; there is no dark theme). Arpit asked on 2026-09-15 for light and dark "later in apps too". Pending.

### 5.19 Onboarding, permissions, and "login"

`app/lib/onboarding/onboarding_flow.dart`. One screen whose steps slide through an `AnimatedSwitcher` (not a `PageView`, which broke UI tests). A thin progress bar on top, a black pill for the main action, a quiet Skip or "Not now". Every step logs `onboarding_step_view` and `onboarding_step_complete`. The app polls every second for keyboard enabled and Full Access (read from `keyboard-ping.json`) so checks turn green on their own.

| Step | Screen | Notes |
|---|---|---|
| `hello` | Glass orb with "g", the wordmark, "Every key is a Glyf.", "Set up Glyf" | The orb came from Acti's "glassy ball" reference (Arpit, 2026-09-11) |
| `persona` | "What fills your day?" Studying / Working / Creating content / Mostly texting | Picks the suggested keys and Google scopes |
| `feel` | "Make it yours": Key sounds and Haptics switches | Asked up front per Arpit's 2026-09-12 request |
| `enable` | "Turn Glyf on" with the Settings path; Open Settings | Android copy: "Settings → On-screen keyboard → Glyf" |
| `access` | iOS: "Allow Full Access" ("AI runs need it. Typing works without it."). Android: "Switch to Glyf" with the system keyboard picker | |
| `nearby` | "Search what’s near you": one coarse location fix | Added 2026-09-14 after "u can req location access for this if needed in on boarding flow" |
| `keys` | "Your starting keys": the persona's keys, each can be unticked | Keys are bound on finish |
| `connect` | "Connect your Google": YouTube, Calendar, Gmail, Meet rows, preset from the persona (Working: Calendar, Gmail, Meet; others: Calendar); "Sign in with Google" or "Not now" | Until Google credentials exist, the server's error message is shown inline |

On finish the app writes key sounds, haptics and the chosen keys into settings and marks onboarding done (`onboarding.json`). Profile has "Replay onboarding".

**History.** M1 (2026-09-11/12) shipped a 5-step funnel: value screen with the glass orb, enable, Full Access, a drag-the-orb pack picker, and a first Glyf fire in a sandbox field. On 2026-09-12 17:59 Arpit asked for "a very smooth clean onboarding flow, ask user what all he wants ask if he is student or working then suggest things accordingly, ask questions and also ask abt if he wants key stroke sounds or not" and not to preset much; the flow was rebuilt around questions. The Google step was added at 18:42, nearby search on 2026-09-14. The drag-to-choose `DraggableOrb` widget in `orb.dart` is now unused; `GlassOrb` is still used by onboarding and the recording sheet.

**Permissions, all owned by the app** (a keyboard cannot ask): Full Access (iOS Settings), location (coarse, iOS when-in-use), contacts (on toggle in Profile), microphone and speech (when dictation starts), Google scopes (user-chosen). Android manifest: `INTERNET`, `READ_CONTACTS`, `ACCESS_COARSE_LOCATION`; the IME is declared with `BIND_INPUT_METHOD`.

**Login and accounts: not built.** Identity is the random `deviceId`. The only sign-in is the optional Google step. On 2026-09-15 Arpit set the target: a sign-up page first (users stored in the same Neon Postgres database as the website waitlist), then onboarding, then ask for Google and other permissions only when a feature needs them. Pending.

### 5.20 The app's three tabs

**Tab bar** (`app/lib/shell/app_shell.dart`): Home (a mini keycap "g", the brand itself), Build (grid icon), Profile (person icon), with a small purple dot under the selected tab. Tabs crossfade in 220 ms and keep their state. Tapping anywhere outside a text field dismisses the keyboard. Originally the bar copied Acti (keyboard, wand, person, ＋). Arpit on 2026-09-12 17:59: "why are you using same icons as acti for bottom bar etc ... if we have option to build in magic want section why to have Plus symbol too, instead have profile there, dont blindly copy". The ＋ tab was removed and the Builder moved into Build.

**Home** (`app/lib/home/home_tab.dart`):

- Wordmark, plus a small "setup" chip while setup is incomplete.
- A setup card with "Keyboard enabled" and "Full Access" (Android: "Switched to Glyf") and Open Settings buttons, **only while something is missing**. Arpit: "why does our app has those 3 green ticks, i guess once we got all permissions we need not show that".
- **Live key map** (`keyboard_visual.dart`): bound keys dark with the dot and a slight lift; tap a free key for recommendations, a bound key to change or unbind ("Hold X to fire"). Then "N keys bound".
- A **try field** right under the map (Arpit: "i dont like that test input is soo far below glyfs keys that i have to scroll soo much"), with sentence capitalization so the keyboard's autocap works.
- Bound keys as cards (keycap with dot, title, emoji). Arpit at 18:42: "the top kay board is good , but i liked the previous key list more", so both stayed.
- Keycap dot bug (2026-09-13 14:48, "why are the glyf symbols bad on main page here"): a `Container` with `alignment` handed its `Stack` loose constraints, so the dot followed the letter's width instead of the key corner. Fixed with a centered letter in a tight stack and a neutral hairline border.

**Build**: section 5.16.

**Profile** (`app/lib/profile/profile_tab.dart`, rebuilt 2026-09-12 after "our profile page looks bad and shit , see acti profile page for ref"):

- Identity: keycap "g" avatar, display name (Edit; saved in `onboarding.json` and sent to `POST /account/name`), a UID chip (first 8 hex characters of the device ID).
- Plan card: Free plan with runs left, Glyf Plus, or Glyf Max; "Go Pro" or "Upgrade" opens the paywall.
- Creator: "My Glyfs (N created)" and "Creator stats (N installs)". Both rows currently do nothing when tapped.
- Settings: Keyboard (sheet: key style cards, appearance chips, key sounds, haptics, number row, autocorrect, auto-capitalize, "." shortcut, suggestions, paste title with link, translate target), Vocabulary, Themes, Contacts search (toggle with a Cupertino dialog), Nearby search (toggle with a dialog), Your info & shorthand (the vault editor), Notes, Connected tools, Tone profile (shows the learned hint, Reset), Replay onboarding.
- Footer: "Engine connected" or "Engine offline" dot from `GET /health`.

### 5.21 Plans and the paywall

**Not on sale yet (26 Sep 2026).** Arpit: "greyout the pro features as coming soon for now in app". `plansOnSale = false` in `lib/profile/paywall_sheet.dart`: the sheet still shows Plus and Max, greyed and marked Coming soon, with a disabled Coming soon button, and cannot change a plan; Profile's plan card says "Pro coming soon" in grey. Purchases come in the next update through Apple and Google billing with RevenueCat (Razorpay and Dodo can't sell a plan inside the iPhone app; Dodo costs about as much as Apple on a $4.99 plan). Monthly and yearly ("we can yearly pay too and give discounts"), then cheaper ("i think 5$ and 20$ are too high for keboard and for beggining no? we should make 2$ and 5$ ig", 26 Sep): Plus $1.99 a month or $15.99 a year, Max $4.99 a month or $39.99 a year, both yearly plans a third off; the sheet shows the yearly price under each. Product IDs, group "Glyf Pro": `com.arpit.glyf.plus.monthly`, `com.arpit.glyf.plus.yearly`, `com.arpit.glyf.max.monthly`, `com.arpit.glyf.max.yearly` (Max on level 1, Plus on level 2). An optional introductory offer (a week free on the yearly plans) is Arpit's call. Flip `plansOnSale` when purchases are in.

**Plans** (decided 2026-09-12 19:15 after Arpit's "i think we can give some slow free replies with ai in free and ask to update accordingly one 5 $ plan and one 20$ iguess, research on this too"; priced against Wispr Flow at $12 to 15 a month and Grammarly's keyboard at about $12):

| Plan | Price | Runs | Also |
|---|---|---|---|
| Free | $0 | 40 a day (`FREE_RUNS_PER_DAY`), fast models | |
| Plus | $1.99 / month or $15.99 / year | 400 a day, priority | every tool and connector |
| Max | $4.99 / month or $39.99 / year | 1,000 a day (the card says unlimited) | the smartest models (not built: every plan gets the same models), unlimited custom Glyfs, early features |

- The server meter enforces caps per plan. The keyboard shows a runs chip at 8 or fewer and "Daily free runs used up" when capped. **No purchase UI ever appears inside the keyboard** (SPEC 6.3 and 6.16).
- The paywall (`app/lib/profile/paywall_sheet.dart`) is a two-card sheet (Plus, Max badged "Best"), titled "You’re out of runs today" when opened by a cap. It opens from the Profile plan card and when a Builder test run hits the cap.
- **The plan is the server's word.** Tapping Get Plus or Get Max calls `POST /me/plan`; the server changes the account's row only when `PLAN_SELF_SERVE=true` (dev and TestFlight), and answers 403 "Plans arrive with the App Store build" otherwise. The app writes the plan locally only after the server accepted it. The plan card and the keyboard's runs chip both read `GET /meter/:deviceId` (`remaining`, `plan`, `perDay`), so they can never disagree about what a person has. StoreKit and receipt validation replace the self-serve switch at ship (section 11.2).
- UI test `test15_PaywallRenders`.

### 5.22 Tone profile (on-device learning of writing style)

`Engine/ToneProfile.swift` (SPEC 6.15, M7 core). Compact counters only, never text. Accepting a result (Replace, Insert or Copy in the bar, Insert or Copy in a skill HUD) counts as accepted; closing a result without using it counts as discarded. Glyfs map to four buckets: concise (Tighten, Summarize), warm (Polite, Smart reply), formal (Professional, Shuddh Hindi), playful (Emoji-fy, Hook writer, Super X reply). Once a bucket has at least **3 more accepts than discards**, every run carries a hint such as "The user tends to prefer writing that is brief and to the point." in the `toneHint` variable, which server prompts can use. Profile → Tone profile shows the hint and can reset it. The spec's gate ("a rewrite visibly changes after 10 accepts") was not formally demonstrated. **Android reads and resets the profile from the app but its keyboard neither records outcomes nor sends the hint.** Unit tests: `testToneHintNeedsThreeNetAccepts`, `testToneHintPicksStrongestBucket`, `testToneBucketsMapKnownGlyfs`.

### 5.23 Telemetry

`app/lib/core/telemetry.dart` (SPEC 12: events and timings, never content). Events are appended to `telemetry.jsonl` in the app's documents folder (the source of truth) and flushed best-effort to `POST /telemetry` at most every 15 seconds in batches of up to 500. The server drops string fields longer than 80 characters and serves daily counts at `GET /telemetry/funnel`.

Events the app logs today: `app_open`, `onboarding_step_view`, `onboarding_step_complete`, `onboarding_complete`, `onboarding_location`, `onboarding_google_start`, `connector_connected`, `binding_changed`, `rec_bound`, `key_bound`, `pack_applied`, `builder_generate`, `builder_generated_ok`, `builder_tested`, `builder_saved`, `hub_publish`, `skill_get`, `vocab_pack`, `kb_setting_changed`, `paywall_shown`, `plan_selected`, `tone_reset`, `dictation_opened`, `dictation_cancelled`, `dictation_used`, `vault_field_saved`, `profile_myglyfs`.

**Neither keyboard sends telemetry.** The SPEC's keyboard events (`keyboard_activated`, `glyf_fired` with latency, `glyf_result_action`, `full_access_granted`) are not implemented; the keyboards only write `os_log` markers (`GLYF_KB`, `GLYF_MEM`, `GLYF_RUN`, `GLYF_DICT`, `GLYF_SPIKE_A`) on iOS and `GlyfKB` logcat lines on Android. The SPEC's core metric (D1, D7, D30 retention of default-keyboard users) has no dashboard yet.

### 5.24 GIFs, stickers and emoticons

Arpit on 2026-09-12: "we can aslo add gif and stickers support like gboard has it", and again on 2026-09-24 with Gboard's Emoji, Bitmoji, Stickers, GIFs and Emoticons tabs as the reference: "ui very close to apple keyboard ... research a lot on what we can integrate freely". Built on iOS on 2026-09-24.

**What can be used for free (researched 2026-09-24, sources in the commit):**
- **Tenor's API is closed.** Google stopped new keys on 2026-01-13 and ended the API on 2026-06-30.
- **GIPHY** is free only up to 100 calls an hour per key; production keys are paid and quoted case by case, and its terms forbid proxying calls or files through a server. Not used; the old `/gif/search` GIPHY proxy was removed.
- **KLIPY** (klipy.com, by Tenor's founders; Google's AI Futures Fund invested in June 2026) is the free replacement: GIFs, stickers, clips and memes, a copy of Tenor's API. Test keys allow 100 calls an hour; production access is requested in its Partner Panel once the attribution is live. Its terms require "Search KLIPY" in the search field and visible KLIPY branding, and want every API call and file load to come from the device, not a proxy (a server proxy needs written approval from developers@klipy.com). It must not be cached or stored server-side, its results must not be reordered or mixed with other sources in one grid, and ads are optional (off here).
- **Noto Animated Emoji** (Google, CC BY 4.0, about 880 emoji as 512px GIF, WebP and Lottie on `fonts.gstatic.com`, plus 32/128/512px PNG stills) work with no key at all. Credit is required.
- **Skipped:** Emoji Kitchen (no licence or API for third parties), Bitmoji (Snap removed Bitmoji Kit in 2022; the Bitmoji app closed on 2026-06-30), Stipop (paid), Apple's own stickers (not reachable from a keyboard).
- **iOS cannot type a picture.** A keyboard can only insert text (`UITextDocumentProxy`); adaptive image glyphs come only from the system's own input. Gboard for iPhone copies the GIF and the person pastes it, and so does Glyf. Full Access is needed for both the network and the pasteboard.

**How it works (iOS):**
- **Modes.** Four glyphs at the end of the search field row, Apple's grey circle behind the chosen one: Emoji (the smiley), Stickers (a peeled-corner sticker drawn in code, `BoardGlyphs.sticker`), GIFs (a boxed "GIF") and Emoticons (":-)"). Every mode keeps Apple's shape: the same field, a small-capitals section name, ABC at the bottom left, delete at the bottom right, the grey circle or capsule behind the chosen chip. The chips scroll sideways and fade at their ends.
- **GIFs** (`Bridge/MediaClient.swift`, `Surfaces/MediaGrid.swift`): the keyboard asks our server for `GET /media/config` (the KLIPY app key, only for a signed-in phone) and then calls KLIPY itself: `{base}{key}/gifs/trending|search|recent/{customer_id}` with `per_page=24`, `locale` (the phone's language), `content_filter=high`, `format_filter=gif`, and a random per-install `customer_id` (not the Glyf account). Ads (items of type `ad`) are skipped. A two-column masonry grid that scrolls down like Messages' #images, each tile KLIPY's `sm` GIF animated by ImageIO one frame at a time (`CGAnimateImageDataWithBlock`), stills when Reduce Motion is on. Chips: Recently used (KLIPY's own list for this install), Trending, and feelings (Haha, Love, Sad, Yes, No, Wow, OMG, Thanks, Hi, Bye, Miss you, Hug, Party, Dance, Congrats, Birthday, Good night, Facepalm, Sleepy, Hungry, Awkward), each a search. "Search KLIPY" in the field, "Powered by KLIPY" beside the section name. Tapping the field collapses the board to a strip over the letter keys (as emoji search does) with KLIPY's autocomplete as chips; Return or a chip runs the search and brings the grid back.
- **Sending.** A tap downloads KLIPY's `md` GIF, puts it on the pasteboard as `com.compuserve.gif` and nothing else (so no app pastes a link instead), tells KLIPY it was shared (`POST .../share/{slug}`, which feeds its trending and this install's recents), and says "GIF copied. Hold the text box and tap Paste". The board stays up for the next one. Checked end to end on the simulator: the GIF pastes into a Messages draft as an image.
- **Stickers.** With a KLIPY key: KLIPY's stickers (transparent GIFs, or PNG stills when a sticker has no GIF) in a four-column grid, feelings as emoji glyph chips (😂 ❤️ 👍 😢 😡 🎉 🙏 👋 😴 😮 🐶 🐱 🍕 🎂), and Noto's animated emoji as a page of their own at the end (never mixed into KLIPY's grids). Without a key: Noto alone, "Popular" plus the same feeling chips, served by `GET /media/emoji-stickers?q=&page=` from a catalogue bundled with the server (611 base emoji, most popular first, a synonym table so "sad" finds crying, pensive and pleading faces). The grid shows Noto's 128px PNG still (6 KB) and the 512px animated GIF is what gets pasted. "Noto Emoji by Google · CC BY 4.0" beside the section name.
- **Emoticons** (`Design/EmoticonData.swift`): about 170 text emoticons in Classic, Smiling, Love, Hugs, Sad, Angry, Surprised, Cool, Shrug and Animals, plus recents. They type straight into the field (no Full Access needed), with a space in front when they follow a word.
- **Memory.** Previews are cached by bytes (12 MB cap, dropped on a memory warning); a preview wider than 320px is shown as a downscaled still instead of being animated; the full file is downloaded only when tapped and never cached.
- **Dark mode.** The board re-takes its colours when light and dark flip while it is open (`EmojiBoard.applyPalette()`).
- **Testing without a key:** `qa/fake-klipy.mjs` answers KLIPY's paths in KLIPY's response shape from a folder of small GIFs; start the server with `KLIPY_APP_KEY=demo KLIPY_BASE_URL=http://127.0.0.1:8798/api/v1/`. UI tests S102 (emoticons), S103 (a GIF is copied), S104 (a sticker is copied) and S105 (GIF search); Android S106 to S108.
- **Android** (`ime/EmojiBoardView.kt`, `ime/MediaClient.kt`): the same modes, chips, sources and attribution. Android can put a picture straight into a field that says it takes one: the keyboard writes the file under its cache, serves it through a `FileProvider` (`${applicationId}.media`, read-only grants) and calls `InputConnection.commitContent` when the field's `contentMimeTypes` include the GIF's or PNG's type; elsewhere it copies the image (`ClipData.newUri`) and says "GIF copied. Paste it in the message". Checked on the emulator: Google Messages accepted a GIF through `commitContent` (and then refused it only because the emulator has no MMS), the Glyf app's own field fell back to the copy. Animated previews use `AnimatedImageDrawable`; anything wider than 320px is decoded down to the tile.

### 5.25 Memory budget and logging (iOS)

- `MemoryLogger.swift` logs `GLYF_MEM appearance=N footprint_mb=X` on every keyboard appearance and `GLYF_MEM surface=<name>` when the shell, emoji board, search, connector or note editor opens. It logs at Default level because `.info` lines are stream-only (M0 finding).
- Budgets from the spec: whole extension under 45 MB, shell under 6 MB, ConnectorSurface under 4 MB. `ci/check_memory_budget.sh <log>` checks the peak and only fails with `GLYF_MEM_STRICT=1` (meant for device runs).
- Simulator numbers (debug builds): 21.5 MB at the first M0 appearance; 26.1 MB fresh and 59.9 MB peak across the M1/M2 suite; about 61 MB including the dictation flow (M3/M4). Simulator memory is **not** jetsam truth. **The device measurement that closes the gate has never been done.**
- Choices made for memory: one blur layer, one reused table for the shell, text-only emoji cells, drawn brand marks instead of image assets, a capped thumbnail cache cleared on memory warnings, a memory-mapped dictionary.
- Android writes `footprintMB: 0.0` (no measurement).

### 5.26 Secure fields and other privacy behaviors

- In secure (password) fields the keyboards disable the Glyf Bar, act, skills, the Translation HUD, the tones popup and dictation handoff (iOS), shorthand expansion (iOS), suggestions, autocorrect and learning (SPEC 11.9). The toolbar search suite, emoji, clipboard and vault inserts are not blocked there: they only insert text the user picks, and search queries are typed into the keyboard's own field, not the secure one.
- `SecretScanner` (Swift and Kotlin) refuses secret-shaped text in the vault, notes and both clipboard histories, with the same key rules on both since 2026-09-24 (`SecretScanner.keyPrefixes`, JWTs, long key-character runs, 32+ mixed-case random strings, wallet addresses exempt). That day a 38-character `whsec_` webhook secret on the Mac's clipboard reached the Android emulator keyboard's history under the old rules (too short for the 40-character rule, an unknown prefix); unit tests on both platforms pin the new rules (`GlyfEngineTests.testKeysAndTokensRefused`, `SecretScannerTest`).
- Contacts and location are collected by the app, reduced (minimal index, ~1 km rounding), kept on the device, and deletable (turning the feature off deletes `contacts.json` or clears the coordinates).
- Info.plist usage strings: contacts ("nothing leaves your device"), location ("kept on your device and never stored on our servers"), microphone ("transcribed on-device and never uploaded"), speech recognition.
- `ITSAppUsesNonExemptEncryption = NO` in both the app and extension Info.plists (only HTTPS and Apple's CryptoKit and Keychain are used).
- Open item: server-side AI calls go to model providers whose free tiers may train on inputs (Gemini's free tier terms also exclude personal information and apps likely used by under-18s). Arpit decided on 2026-09-15 to cover this with a privacy policy rather than code for now.

### 5.27 Crypto (M8): deliberately absent

The spec's crypto connector (Privy Solana wallet, Jupiter swaps, paste guard) is a separate, later release. **No wallet code, no Privy SDK, and no crypto UI exist in either app**, by design (SPEC 9 and 13). Findings kept for later: Spike B showed `privy_flutter` 0.10.1 can sign and broadcast Solana transactions, so no native bridge is needed; on iOS its bridge ignores `rpcUrl` and defaults to mainnet if `cluster` is omitted; the plugin needs iOS 17 (the app targets 15); versioned (v0) transaction signing is the one untested unknown. Privy credentials were authenticated server-side on 2026-09-12 and sit only in `server/.env`. The website's chat demo shows a private MagicBlock payment and a Jupiter swap screen, but that is website-only mock UI. The keyboard's `SecretScanner` already refuses long base58 strings (Solana secret keys).

### 5.28 The keyboard's calendar: new events, Book a time, Meet links, invites

Built 2026-09-24 on both keyboards, after Arpit asked: "i need calendar to support adding events and maybe meetings too or maybe try if we can integrate cal.com or calnedly as well", then "also need email and like add quest email like we book with someone on cal.com etc". Reworked the same day after "i dont wanna setup resend, use cal,com to make it maybe idk or google calendar ... else lets just have it like we paste the details on the text box" and "we can have google meet links creation permission while google sign in and just also have option to set key to maybe also sned a new meet link": invites now come from the person's own Google Calendar or go into the chat, and call links are their own Google Meet. Later that day Arpit asked why Jitsi was in there at all ("i need google meet"): nobody had asked for it, so the Jitsi and Daily fallbacks were removed and **call links are Google Meet only**. And "calendar permissions and this google login will happen on onboarding only": both are asked in onboarding. That evening, "i cant see option to connect google meet etc in connections" put them back in Connected tools too, for whoever skipped them. The server side is BACKEND.md section 4.12.

**What changed in the calendar** (hold C, or the calendar tool): the header gains a camera button and Calendar's own **+**, and the buttons at the foot gain **Book a time** once the person has a booking page.

- **+ opens New Event**, laid out like Calendar's own sheet: Cancel, New Event and Add along the top, then Title, Invitees (only with Google Calendar connected), Starts, Ends, Video call (only when Google can make the Meet call), Share in chat and All-day. The title takes a whole plan in one line ("Lunch with Sam tomorrow 1pm") and fills in the times as it is typed; the line under the strip says what it read ("Fri 25 Sep, 1:00–2:00 PM"). Title and Invitees are typed with the keyboard's own keys under a strip, the way emoji search works (iOS `EventComposer.swift`, Android `EventComposerView.kt`); Return goes back to the rows. The date and time pills open wheels (day, hour, minute, AM/PM) in place of the rows, and moving the start keeps the length.
- **Add, with Google Calendar connected**, puts the event in the person's own Google Calendar (primary) with `sendUpdates=all`, so **Google emails each invitee** the invite, from the person's own address, and Video call gets the event's own Meet call (`conferenceData`). Toasts: "Added to Google Calendar" or "Added. Google emailed the invite to sam@x.com". Google's calendar reaches the phone's on its next sync. If Google refuses (a revoked grant, or a testing app's weekly expiry), the event is saved on the phone instead and the toast says so ("Added to Calendar. Sign in with Google again in Glyf").
- **Add, without Google**, saves to the phone's calendar and shows the day with the new event lit, scrolled into view, and read out as "Just added" (VoiceOver value, TalkBack state). On iOS it is written from the keyboard itself with EventKit, which works with Full Access on and the app's calendar permission (checked on the iOS 26.5 simulator; a real iPhone is still to be checked). On Android it goes through the calendar provider (the app asks for read and write), into the primary writable calendar or, on a phone with no account, a local "Glyf" calendar made once. Invitees aren't offered: nothing on a phone can email them.
- **Share in chat** (on when New Event is opened with +, off when it comes from a plan chip, whose plan is in the message already): once added, the event goes into the message, "📅 Review · Fri 25 Sep, 3:00–4:00 PM · https://meet.google.com/abc-defg-hij", for the person the chat is with, and the calendar closes. Most people adding an event from a chat keyboard are planning it with that person.
- **Video call** is a Google Meet call: the event's own for a Google event, a Meet link of the person's (Meet REST API, `spaces.create`) for one saved on the phone when only Meet was granted. Without Google the row isn't there.
- **The camera** puts "Join me on a call: https://meet.google.com/abc-defg-hij" in the message without making an event: the person's own **Google Meet** link, and nothing else. Without Google, or when Google says no, nothing goes in and a toast says where to connect it ("Connect Google Meet in Glyf › Connected tools"). No other kind of call link exists.
- **A key for Meet links**: Meet link is a bindable target (`connector:meet`, in the app's Glyf Keys list). Holding its letter puts a fresh Meet link in the message, the same way as the camera.
- **Book a time** (the person's own page, set in the app under Profile → Connected tools → Booking link, stored as `bookingLink` in the shared settings): the chosen day's open times on their Cal.com page as pills, four to a row, with ‹ › for other days. Tapping a time asks who it is for in one line: a name, an email, then any guests' emails ("Sam Lee sam@x.com ria@y.com"); the strip opens by itself when no email is known yet. **Book it** books it on Cal.com for that person, and Cal.com emails the host, the person and every guest the invite. The message gets "Booked for Thu 24 Sep, 5:30 PM. The invite is on its way to sam@x.com and ria@y.com. Call: <link>". **Send the link** puts the page (or that time on it) in the message instead: "How about Thu 24 Sep at 5:30 PM? Book it here: <link>", or "Pick a time that works for you: <page>" before a time is picked. A Calendly page shows no times (Calendly shares them only with the host's own sign-in), so it says so and sends the page on that day.
- **Someone else's page** in the message or just copied ("cal.com/sam/30min", "calendly.com/ria") brings a strip chip, "A time on cal.com/sam/30min" with **Book**. It opens the same Book a time on their page, starting from the person's own name and email in the vault ("You"). The person's own link never brings the chip.
- **A plan in the message** ("dinner friday 8pm", "kal 5 baje milte hain") brings a chip, "Dinner · Tomorrow 8:00 PM" (or "Fri 25 Sep 8:00 PM" further out) with **Add**, which opens New Event filled in; nothing is typed. The rules are `EventParse` (Swift and Kotlin twins with the same test cases): weekdays, "tomorrow", "tonight", dates both ways round by region, ranges ("10:30-11:30am", "from 5 to 7"), durations, "in 30 mins", "all day", noon and midnight, Hinglish ("kal", "parso", "baje", "shaam"). "I'm free…", "busy", "booked" and whatever the calendar itself typed (the 📅 lines) never bring the chip.
- Everything the calendar puts in the message is a sentence of its own: a space goes in first when the text before the cursor doesn't end in one.

**Google Calendar and Meet** (`GoogleAccess`, `GoogleClient` and `GoogleEvent`, twins on both platforms): scopes `calendar.events.owned` (events on calendars the person owns, the narrowest write scope, which also makes an event's Meet call) and `meetings.space.created` (Meet links on their own). **Signing in with Google asks for them** (`SignIn.askCalendarAtSignIn`): on the iPhone they are on the same Google page (the PKCE code flow with the iOS client id now also returns a refresh token, kept in the keychain group the app and keyboard share); on Android, Play services' consent comes right after the sign-in sheet (`AuthorizationClient`), and the keyboard asks Play services for a fresh token each time. Google lets the person untick either one; the keyboard offers only what was granted. **Onboarding's calendar step** ("Plan it where you chat", after Nearby) asks for the phone's calendar permission and, when sign-in didn't bring Google Calendar and Meet (an Apple sign-in, or unticked boxes), offers **Connect Google Meet**, with Google Meet's own mark (`GoogleMeetMark`). **Profile → Connected tools** has the same two for anyone who said "Not now" there, or finished onboarding before the step existed (taken out on 25 Sep morning with "calendar permissions and this google login will happen on onboarding only", back that evening after "i cant see option to connect google meet etc in connections"): **Calendar** reads Turn on until the phone allows it, then On (taking it back is the phone's Settings'); **Google Meet** is a switch whose on runs the same Google page as onboarding and shows the account, and whose off takes the grant back from Google too. Profile's "N active" counts Calendar, Google Meet, Contacts and a booking link. Signing out revokes the Google grant; the next sign-in's onboarding asks again. The iPhone keyboard says "Turn on Calendar in Glyf › Connected tools" while the app has never asked (Settings shows no Calendars switch for an app until it has asked once) and "Allow Calendars in Settings › Apps › Glyf" after a refusal; on Android "Allow Calendar in Settings" opens Glyf's own page in Settings, which lists the permission either way. On Android, allowed means on. The keyboard calls Google directly (`oauth2.googleapis.com/token` on iOS, `meet.googleapis.com/v2/spaces`, `calendar/v3/calendars/primary/events`), so Glyf's server never sees anyone's calendar and needs no Google secret.

**In the app**: Profile → Connected tools has a **Booking link** card (Cal.com and Calendly marks) with a sheet to paste the link, save or remove it.

**Test ids**: `calendar:new`, `calendar:call`, `calendar:book`, `event:title`, `event:title:field`, `event:invitees`, `event:invitees:field`, `event:hint`, `event:starts:time`, `event:video`, `event:share`, `event:allday`, `event:add`, `booking:slot:N`, `booking:who:field`, `booking:who:hint`, `booking:book`, `booking:link`, `booking:next`, `booking:status`, `booking:back`, `tools:google`. Debug hooks (debug builds only): on iOS `--glyf-booking-link <link>`, `--glyf-test-google <base>` (Google as if connected, pointed at `qa/fake-google.mjs`; "" disconnects) and `--glyf-bind m=connector:meet` ("m=" frees it); the Android debug tools `calendaron`, `bookinglink --es text <link>`, `googlefake --es text http://10.0.2.2:8797` and `bind --es text m=connector:meet`.

**Scenarios** (all passing on 2026-09-24, against `qa/fake-scheduling.mjs` and `qa/fake-google.mjs` where they book or reach Google): iOS S109 (New Event into the day's list), S110 (a plan offers Add), S113 (a call link, then Send the link), S114 (a Meet-only grant: the event on the phone with the person's Meet link), S115 (book for someone with a guest), S121 (a Meet link from the camera), S122 (a guest's event goes to Google Calendar with `sendUpdates=all` and a Meet call), S123 (without Google: no call link, no Video call row, and the event goes into the message), S124 (a key held for a Meet link). Android S111, S112, S117, S118, S120 and the twins S125 to S128. The earlier email invites through the server (S116, S119) were retired with Resend.

---

### 5.29 Games: Snake and Chomp

Asked for on 2026-09-25 ("make a simple snake game and pacman too inside here"). g menu → **Games** opens a picker with two cards (a little drawing of each game, its name and the best score on this phone), then the game over the whole key area with a bar above it: ‹ back to the games, the name, lives (Chomp) and the score with the best. **Swipe** anywhere on the board to steer (one turn per 14pt of travel, so one drag can take a corner and then another), **tap** to start, pause and go on; a finished game says "Game over. Tap to play again". The clock stops whenever the panel closes or the keyboard goes away. No sound, no network, no runs spent.

- **Snake**: a 22 by 11 board with no walls (off one edge, back on the other, kinder on a board this small). Starts three long heading right at 150ms a step, a little quicker every four apples (never under 70ms); two swipes can queue so a quick up-then-left lands both; never straight back into itself. One continuous violet body lightening towards the tail, eyes on the head, a red apple with a leaf.
- **Chomp** (the arcade maze game; Pac-Man is Bandai Namco's name, so ours is Chomp): a 21 by 11 maze drawn for the keyboard's wide, short panel, 107 pellets and 4 power pellets, a tunnel through the middle row, a pen with a door. Three ghosts leave the pen a couple of seconds apart and hunt Chomp (one straight at it, one a few cells ahead of it, one at it from afar and to its corner up close, with a little randomness); a power pellet turns them blue and slow for about six seconds (200, 400, 800 points, then home to the pen). Three lives, 10 a pellet, 50 a power pellet; clearing the maze starts the next one a little faster, with shorter frights. Chomp and the ghosts slide between cells over each 140ms step.
- Rules are pure code, written twice and held to the same tests: `Engine/Games.swift` and Android `Games.kt` (seeded, so both put the same apple on the same cell for a seed). Views: `Surfaces/GamesSurface.swift` (CADisplayLink) and `GamesPanelView.kt` (Choreographer). Best scores: `games.best.snake` and `games.best.chomp` in the keyboard's own defaults.
- Tests: 8 unit tests a platform (turning, wrapping, growing, crashing; the maze is whole; eating; turning at the first opening; ghosts leave through the door; power pellets; losing a life; clearing the maze). Scenarios S131 and S132 (iPhone), S133 and S134 (Android): open from the g menu, swipe Snake up, pause it; start Chomp and watch it score.

## 6. iOS vs Android parity

Arpit on 2026-09-13 16:30: "why the fuck does android and ios apps look so diff, i want exactly same features in all , and ios style in both". What was done that day: the Flutter app uses **Inter** everywhere (SF-like metrics) on both platforms, Cupertino switches, sliders, dialogs and iOS-style page transitions on both; the Android keyboard got the same toolbar, the same icon set, the g menu grid, vault and notes panels, emoji panel, and one-tap translate. Parity is still incomplete. This table reflects the code on 2026-09-16.

| Feature | iOS keyboard | Android keyboard |
|---|---|---|
| Layouts, field-aware rows, digit pads | Yes | Yes |
| Accent popups | Yes | No |
| Globe key | Yes (when iOS requires it) | No (system switching only) |
| Caps lock (double tap shift) | Yes | No |
| Delete repeat | Yes (accelerating) | No (one delete per tap) |
| Multi-touch typing | Yes | No (single pointer) |
| One-handed mode | Yes | No |
| Number row | Yes | Yes |
| Press balloon, key sounds, haptics | Yes | Yes |
| Auto-capitalization from the field | Yes | Yes |
| Typing engine (autocorrect, prediction, learning, packs, dictionary) | Yes | Yes, same test cases |
| iOS Text Replacements and contact names as words | Yes (supplementary lexicon) | Contact names from the app's `contacts.json` |
| Space glide cursor, hold-still AI | Yes | Yes |
| Hold ripple across keys | Yes | No (charge ring and haptic only) |
| Act on typed text, map card | Yes (MapKit map) | Yes (Geoapify map, needs key) |
| Glyf Bar | Yes | Yes (since 2026-09-14) |
| Bound Glyf skill HUDs | Yes | Yes |
| Bound `surface:` and `connector:` keys (Translation HUD, tones, vault, calendar) | Yes | No, they open the app |
| Translation HUD strip | Yes | No |
| Tones popup | Yes | No |
| ConnectorSurface (calendar, month view) | Yes (demo calendar) | No |
| Phone calendar: day list, month, free time, New Event, Share in chat, Google Calendar invitees, Meet links and the Meet link key, Book a time, plan and booking chips (section 5.28) | Yes | Yes (no Insert date button) |
| Games from the g menu: Snake and Chomp, best scores on the phone (section 5.29) | Yes | Yes |
| Toolbar | Yes, reorderable and hideable | Same items, fixed order |
| Toolbar Clipboard | History screen with pins | Pastes the current clip |
| Clipboard history store | Yes | No |
| Copied-text strip | Yes | Yes |
| Toolbar Dictation | Handoff to the app | "Dictation lands in the Android update" toast |
| Toolbar Settings | In-keyboard Settings screen | Opens the app |
| g menu | 9-tile grid, full screens | 6-tile grid: Search, Vault, Shorthand, Clipboard, Emoji, Settings (app) |
| Glyfs, Glyf Keys, Connectors, Packs, Account screens in the keyboard | Yes (some rows inert) | No |
| Vault insert | Fields, combos, notes | Fields, notes (no combos) |
| Note editing in the keyboard | Yes | Yes (long-press a note) |
| Shorthand expansion | Yes | Yes |
| Emoji, stickers, GIFs, emoticons | One board: Apple's layout, four modes, search strip | The same board; GIFs and stickers go straight into fields that take images |
| Search suite (web, YouTube, maps, contacts, landing rows, paste format) | Yes, plus a Translate chip | Yes |
| Themes (glass, classic, glow, colors, gradients, borders, dim) | Yes | Yes |
| Dark mode following the system or field | Yes | Yes (follows system `uiMode` or the setting) |
| Tone learning (records outcomes, sends hint) | Yes | No |
| Secure field protections | Yes | Yes (password input types) |
| Memory logging | Yes | No |

| App (Flutter) behavior | iOS | Android |
|---|---|---|
| Same Dart code, Inter font, Cupertino controls | Yes | Yes |
| Onboarding step 2 | Allow Full Access | Switch to Glyf (keyboard picker) |
| Dictation sheet | Works | Errors out ("Dictation lands in the Android update") |
| Vault field kinds | All 12 kinds save | Only address, upi, email, phone, handle, link, custom save; the app offers name, gst, wallet, social, bio, reply too, which Android refuses (section 11.4) |
| Contacts search, nearby search | Yes | Yes (last-known location only) |
| Deep links `glyf://` | Scene delegate | `MainActivity` intent filter and `onNewIntent` |
| Release signing | Apple team `XFSL58LKTQ` | Debug keys (TODO in `build.gradle.kts`) |

---

## 7. Acti feature parity inventory

SPEC 0.1 frames most of Glyf as parity with Acti (Singapore; launched June 2026). Arpit sent three Acti references: a screen recording on 2026-09-11 ("you do not need to copy it, just for references of features i need"), two recordings plus screenshots on 2026-09-12 (keyboard, profile, builder, animations), and Acti's 113-second launch video on 2026-09-14 ("i hope u have seen video now i need all features from it as well"). Frames were pulled with an AVFoundation script (no ffmpeg on the Mac); the videos stay in Arpit's Downloads folder, not in the repo.

Glyf's stated edges over Acti (SPEC 0.1): chaining with conditionals in Glyfs, per-contact memory and tone learning, the crypto execution layer (post-v1), and paste-guard security. **Rule: build the features, never copy Acti's look** (black pills, purple only as the dot, neutral rings, no "ACTI"-style labels, no iridescent bar).

| Acti feature | Glyf equivalent | Status |
|---|---|---|
| Acti Bar: "press to type, hold to act" on the space bar, agent runs on typed text while the finger is down (frosted keys, rings, cancel) | Space hold at 0.5 s → Act (section 5.6) | Built, both platforms |
| Result cards replacing the keys: place with map snapshot, sports schedule, restaurant list | Act result cards; place map | Built. Live sports and news answers need `BRAVE_SEARCH_KEY`; place categories need `GEOAPIFY_KEY` |
| "Drop a live mini-app" (hosted page link) | `/p/:id` pages, inserted for list results | Built server-side; needs `PUBLIC_BASE_URL` in production; the inserted page link was not verified in either keyboard's UI |
| Skill keys: hold a letter to run an action | Glyf Keys and skill HUDs (section 5.7) | Built |
| Hold N → "Notion Summon" (doc row with last edited) | Notion OAuth + `notion.search` tool | Not built as a keyboard skill (needs Notion credentials) |
| Hold L → "LinkedIn HUD" (profile card above the keys) | none | Not built (would need a web search provider) |
| Key balloon shows the app icon while holding | Charge ring and ripple | Not built |
| Copied text shown as a quoted context card | Copied-text strip (section 5.11) | Built, both platforms |
| Skill Builder, "no code" | Builder (section 5.16) | Built; visual chain editor pending |
| Skills community: Featured, Crypto, Emoji fun tabs, creators with counts, share | Skills hub with derived categories, creators strip, real counts | Built (no share links, different tabs) |
| Persona packs | Packs and onboarding personas | Built |
| AI Dictation | Raw / Clean / Formal (section 5.17) | Built on iOS; Android missing; device latency unmeasured |
| "Liquid Glass" design | Glass key style (default) | Built |
| OAuth connectors (Gmail, Slack, Notion, Calendar) | OAuth broker for 9 providers | Built, blocked on credentials |
| 150+ keyless APIs | 28 curated keyless tools, 25 general plus 3 search (SPEC 6.11: "30 quality tools at launch beats 150 shallow ones") | Built |
| Multi-language | AI works in any language; Hinglish and other local vocabulary packs | Partial: no Hindi (Devanagari) or other layouts |
| Free tier with planned subscription | Free, Plus, Max | UI built; purchases pending |
| Keyboard follows host dark mode (seen in the 2026-09-12 recording) | Appearance auto/light/dark | Built |
| Onboarding "glassy ball" bubble | `GlassOrb` hero | Built (drag-to-choose version later dropped) |
| Release notes seen in research (not in the video): space-drag cursor, swipe typing, backspace swipe-delete, swipe-up numbers, haptic strength | Space glide cursor built; swipe typing is out of scope for v1 (SPEC 6.1); backspace swipe, swipe-up numbers, haptic strength levels | Only the cursor glide is built |

---

## 8. Design system and design history

### 8.1 The design system today

**Principles that hold across app and keyboard**

- Apple's language: calm, simple, type and product first, no decoration for its own sake. Arpit: "i need simplistic designs like that" (2026-09-12), "i like apple and acti soo much for design" (2026-09-13).
- **One accent, `#7C5CFF`, used as the dot** (bound keys, the logo, the selected tab marker) and for selection highlights. Primary actions are **black pills**. No purple washes except the optional Glow key style and painted themes.
- No explainer lines: headlines and functional labels only.
- Glyf's own look, not Acti's.
- Smooth: one quick spring for keyboard surfaces, instant key presses, crossfading tabs.

**Flutter app** (`app/lib/core/theme.dart`, class `Glass`): background `#F4F5F8`, white cards (`GlassCard`: radius 22, hairline border, whisper shadow), ink `#17181C`, soft ink `#8A8F98`, hairline 6% black, black pill `#141418` (`PillButton`, 52 high, radius 26), success `#1FA968`, warning `#B77909`, danger `#E0382C`, sheet radius 28. Material 3 seeded from the accent, **light only**, font family **Inter** (bundled variable font, so iOS and Android match), iOS-style page transitions on both platforms, Cupertino switches, sliders and dialogs. The file's header comment still says "WHITE ONLY"; that lock is superseded (section 8.3).

**iOS keyboard** (`app/ios/GlyfKeyboard/Design/GlassTokens.swift`, enum `Glass`): all tokens are computed from `isDark`, `keyTheme`, `themeBg` and `keyBorders`, which the view controller resolves on every appearance. Key fills per style (section 5.18), pressed fills (white 92% or 40% for glass), `surfaceCard` for cards inside surfaces, hairline strokes (black 8% or white 10%), key border stroke for the "borders" option, text primary (near-black or white), the constant `brandInk` for the g keycap, the `watermark` color for the space label, accent plus status colors (`#32D583`, `#B77909`, `#F04438`), radii (key 9.5, card 18, sheet 28), 4pt spacing unit, key shadow offset 1 with no blur, motion 0.18 s, ripple constants (hold 0.32 s, ring start scale 1.18, per-key tint 0.15 s, 22 ms per key of distance, surface rise delay 0.06 s, reduced-motion flash 0.12 s), heights (toolbar 44, keys 216, base 260, number row +42, bar +96, shell +140). The iOS keyboard uses the **system font** (SPEC 5.4: custom fonts cost extension memory). Reduce Transparency and Reduce Motion are honored.

**Android keyboard**: the same palette re-expressed in `GlyfKeyboardView.kt` (`keyFill`, `ink`, `hairline`, `backdrop`, `themedBackdrop`) and `GlyfIME.kt` (`ink()`, `card()`), with Inter for key faces.

### 8.2 Brand mark, wordmark, and app icon (canonical)

- **Source**: `glyf-symbol-concepts.svg` at the repo root. Concept 01, the bound keycap "g" with the purple dot, is the logo. Arpit on 2026-09-12: "why not using the logos i sent too, sending again for app logo and in app designs".
- **Keycap mark** (`KeycapGMark` in `theme.dart`): white rounded square (corner radius 0.30 of the size), ink "g" at 0.52 of the size (weight 600), dot diameter 0.13 of the size, inset 0.16 from the right and 0.14 from the top.
- **Wordmark** (`GlyfWordmark`), standardized 2026-09-14 after Arpit saw three different versions across Android, iOS and the site ("why is the logo fucking diff on android ios and website, why not fucking standard ... i need the dot on top right after f as we have on our keyboard"). "glyf" in weight 700 with tracking of -0.045 em; the dot is **0.18 em** wide, sits **0.16 em** after the f, and its **bottom rests at the top of the f** (raised 0.74 em), so the whole dot rides above the letter at the top right. In Flutter: `right: -size * (0.16 + 0.18)`, `top: size * (0.80 - 0.74 - 0.18)` with `Clip.none`. The first attempt aligned the dot's top with the f's top; Arpit rejected it twice ("it looks like its in from of f and not top right, make dot more up and look perfect"). The site uses the same fractions. The brand dot is always this raised mark, never a purple period on the baseline.
- **App icon** (`app/ios/Runner/Assets.xcassets/AppIcon.appiconset/`, every size regenerated 2026-09-14 13:36; verified in the 1024 px file): the keycap mark's geometry on a **plain white canvas**, "g" in Inter SemiBold at 0.52 of the canvas centered on the font box (so the descender hangs below center), dot 0.13 of the canvas, inset 0.16 from the right and 0.14 from the top. **Android**: adaptive icon with the same mark at 66% on a transparent foreground, background `#FFFFFF`, monochrome layer = foreground, plus legacy mipmaps. `mipmap-anydpi-v26/ic_launcher.xml` is required; without it launchers cropped the "g" into something that looked like an "f".
- **Icon saga** (the lesson that became a rule): the first icon (2026-09-12, rendered with `NSImage`, which draws at the Mac's 2x scale, then `sips -z 1024 1024`) was a white keycap on a grey square, which looked like a card inside a card under the OS icon mask. On 2026-09-14 13:19 Arpit asked "also why is bg on logo in app / see how other apps logo looks good". The assistant redrew the "g" and moved the dot. Arpit at 13:35: "it was good i liked the dot placement and everything in that, it was just in fuckin bg on the screen idiot / i just fucking asked u to remove bg and u asshole change dot possition and everything". The original geometry was restored with only the background removed. **When asked to remove a background, change nothing else.** Regenerate icons with the Python PIL snippet recorded in `docs/history/context-snapshots.md` (Snapshot 3) rather than editing PNGs by hand.
- Note: a transcript line on 2026-09-12 20:47 says the icon was "still the Flutter default" at that time, which conflicts with the 11:41 statement that the keycap icon had been generated. Which icon build 1 or 2 carried could not be verified.

### 8.3 Design history, in order

| When | What Arpit said | What changed |
|---|---|---|
| 2026-09-11 23:14 | "the glassy ball desgin to do public and private i need that type of design to do on boarding" (Acti reference) | Glass orb onboarding hero; M1 keyboard built to SPEC 5's purple glassmorphic tokens, dark and light |
| 2026-09-12 11:39 | "why is keyboard elongated as fuck, why not apple's default size for this, secondly the fuck is this purple ui soo shittyy, have white mode only ... a bottom bar ... why not using the logos i sent too" | 260pt Apple-size keyboard; **white only** (keyboard forced light, app near-white); Acti-style tab bar; keycap "g" as icon, toolbar button, hero; accent only as the dot |
| 2026-09-12 16:40 | "study apple's design language i need simplistic designs like that ... i dont like explainer lines everywhere remove them" | Explainer lines, ALL-CAPS section labels and captions removed; one-word statuses |
| 2026-09-12 17:59 | Green ticks, "our profile page looks bad", builder revamp, "test input is soo far below", "dont preset a lot", "why are you using same icons as acti", "why is glyf opeing so rough" | v2: setup card only while needed; live key map with the try field under it; Profile on Acti's structure; Builder "What do you want?"; 3 tabs with own icons, no ＋; persona onboarding; spring animations on every surface; tab crossfades. Evidence `v2-*.png` |
| 2026-09-12 18:42 | "the top kay board is good , but i liked the previous key list more" | Key map on top and the card list below |
| 2026-09-12 22:26 | "why does the month have soo much gap below it ... why is glyf button so dull and sad ... i dont like this screen much, improve it" | Month grid fills the surface; black g keycap with glowing dot; Glyf Bar de-purpled (black Replace pill, white card); symbols row stretch. Evidence `v3-*.png` |
| 2026-09-13 00:54 | "switch to apples keyboard with globe icon and see diff, i need apple like styles with our ui and apple ux, ley sizes spacing etc ... fix dark mode too" | Side-by-side with the system keyboard: uniform white keys, radius 9.5, 44pt keys, 23pt letters, press balloons, field-aware autocap. **White-only lock amended: the keyboard follows the host's dark mode** (auto/light/dark); the app stays white. Evidence `v4-light-keyboard.png`, `v4-dark-keyboard.png` |
| 2026-09-13 01:55 | "see the diff between apple and us, apple looks soo classy and cool , we dont" | The assistant started stripping the bound-key wash and rings |
| 2026-09-13 01:57 | "idiot lavendar lashes are not problem, see borders, and design, i think lavender dots are still fine, see acti has a blue light in M key ... i like the dot tho its glyf symbol of our app" | Accent outline rings removed for good; dot and faint wash kept; soft purple under-glow added; space label became a faint "glyf" watermark; lighter shadows. Evidence `v5-keyboard.png` |
| 2026-09-13 02:13 | "still too much shadow and not glassy keys, also give option to edit keyboard designs in app, like gboard gives ... by default we need simple v similar to apple with just purple dots and glassy keys liquid glass" | **Glass** default (translucent keys, dot only); Classic and Glow as options; key style picker in the app and in the keyboard. Evidence `v6-glass.png`, `v6-design-picker.png` |
| 2026-09-13 14:48 | "why are the glyf symbols bad on main page here" | Home keycap dot pinned to the key corner; hairline border instead of lavender on the list keycaps |
| 2026-09-13 15:04 | Gboard screenshots and a recording: "list looks v bad here / we need icons with text in bottom and rows and coloumns ... how we show apps in dock ... also sendding refs for how google does themes for keyboard and edit interface" | Launcher grid for the keyboard menu; Themes screen (colors, gradients, borders, dim); search suite; contacts search |
| 2026-09-13 16:19 | "icons are not properly visible in themes and some glyf symboil not visible in glass theme , i need you to check everytheme" | Theme audit fixes (section 5.18) |
| 2026-09-13 16:30 | "why the fuck does android and ios apps look so diff, i want exactly same features in all , and ios style in both" | Inter font and Cupertino controls on both; Android keyboard given the iOS toolbar, menu grid and panels |
| 2026-09-13 19:59 | "i feel google and apple are very much smoother compared to our ... i need smooth as fuck experience" | iOS key press scale removed; surface spring 0.46 s to 0.30 s; Android keyboard moved from CPU to GPU rendering and got touch-down haptics and clicks |
| 2026-09-13 21:49 | "see this screen looks good but, other screen look bad ... checkl fucking all screens and see and fix them to look good ui ux and clean" | Every keyboard menu screen rebuilt as cards; no explainer sublines; display names; ✕ to unbind; notes inside Vault; Shorthand tile |
| 2026-09-14 12:53 to 13:35 | "no need to change the glyf logo or anything thats all perfect"; then the wordmark and icon complaints | Wordmark standardized; icon background removed (section 8.2) |
| 2026-09-14 13:52 | "i really love the ui u made for this on website, no we need that exact fully working" | Keyboard search cards rebuilt to match the website's card designs |
| 2026-09-14 22:27 onward | Apple and Gboard cursor glide, Acti's hold-to-act | Trackpad look during glides (key faces blank); act surface in Glyf's language (neutral rings, black g keycap, black Insert pill) |
| 2026-09-15 14:44 | "i like ui ux on website dont copy mobile for that, its shit in mobile rn" | App work paused for the website launch; **an app UI redesign is implied but not started** |
| 2026-09-15 (design questions) | "i need both light and dark modes both in site and later in apps too" | **Supersedes the white-only lock for the apps.** Pending |
| 2026-09-16 02:13 | "remove the em dashes from everywhere in website, they look fucking disgusting ai made" | Done on the site; app strings not yet cleaned |
| 2026-09-19 to 09-21 | "i feel our keyboard is a little above from bottom than apple / fucking get pixels correctly", "and the space between also set like apple does" | Key geometry re-measured against iOS 26 on four widths and pinned in `KeyMetrics` with tests. The row gap is one constant (11pt) on every phone; the key stands 43pt on a standard phone and 45 on the wide class |
| 2026-09-20 to 09-21 | "touc landing in between is not working the fuck cant u do a simple thing", "still empty space feels no touch, every area should b sensitive like apple fucking research and do it" | Two wrong diagnoses (blaming the automation, then the hit test) before the real cause: a keyboard extension discards touches on fully transparent pixels. Found by painting the grid red. Arpit confirmed it himself: "ok now gaps work in the red keyboar du made". Then "so i feel instead of clear, you can set th ecolour based on the phone dark or light mode etc" gave `Glass.touchableGrid` |
| 2026-09-21 | "i dont need paste here in vault, image additiong and other options etc will be thru app only in vault" | Paste removed from the vault; images are added in the app |
| 2026-09-21 | "i think in app one thing can be pointed by many keys like in app both s and v can open vault" | A rule that dropped `s` when `v` held the vault was reverted. Nothing unbinds a key behind the person; pinned by `testTwoKeysMayOpenTheSameThing` |
| 2026-09-21 to 09-22 | "i think u need to work on the g logo in top bar, its cutting the bottom part i feel" | Five passes on one slot, see 8.5 |

### 8.4 The toolbar's first slot: eight passes on one icon (21 to 25 Sep 2026)

Worth recording because each step was a real measurement and the end point is not where it started.

1. **The tail looked cut off**, and was: a `UIButton` centres its title's **line box**, and a lowercase "g" has no ascender ink and a deep descender, so it sank to the floor of the pill. Measured 10.33pt of black above the letter against 2.00pt below. Fixed by centring the glyph's own outline (`CTFontGetBoundingRectsForGlyphs`), which landed it at 6.33 and 6.00.
2. **"this still looks shit and nothing like our logo ... instead of rectangle why arent we have squarish logo here".** The system "g" was replaced with the real mark from `assets/brand/glyf-symbol.png`, reversed out of a 28pt square. An extension cannot read the host app's artwork, so the mark shipped with the appex.
3. **"the g looks very small here".** It was 10.9pt, because the app icon gives its letter only 40% of its height. That is right at 60pt on a home screen, where the padding separates the icon from wallpaper, and far too small at 28pt where the tile already separates it. Pulled in to a 2pt margin: 14.3pt.
4. **"i think not have the black bg and make g bigger".** Off its tile the letter reached 19.3pt, because a tile has to hold the mark **and** its margins. The accent dot moved to the letter's shoulder: at the logo's own offset it clipped the top of a 36pt strip, and read as a stray mark rather than composition once the tile was gone.
5. **"use some icon like this only, dont use glyf logo"**, with a reference image. The logo left the slot entirely for a drawn apps grid. The brand artwork added in step 2 was deleted again. The turned tile is not decoration: it is what separates this icon from the Skills hub's own `square.grid.2x2`, which someone may well put on the same strip.

Then "looks bad, spacing isnt perfect" and "cross looks bad" gave the row's spacing rules (section 5.3) and took the fill off the close button, which was a 50 by 32 pill because the fill was the whole tap target.

6. **"i need the g button back on ios also, figure out how to add it and make it look good, we need branding properly"** (25 Sep). Android had kept its black g pill all along. The slot became the brand key on both keyboards, built to answer each earlier note: squarish, not a pill (step 2); the letter large, 16.5pt on a 26pt key (steps 3 and 4); and the logo's own letter rather than the system font. The icon's g was matched by overlaying Inter's outline on the 1024pt icon: SemiBold at text size covers 99.3% of it with the same proportions (the default display cut only 94.7%). The key is a little wider than tall so the violet dot has its own corner, 4pt clear of the letter; a square key put the dot against the g's stem. The act panel's working key wears the same g. Scenarios S129 (iPhone) and S130 (Android) sample the key's face and dot on light and dark sheets.
7. **"g logo here looks okay i think just a bit more height, the one u have in app rn looks shit"**, with a screenshot of tryglyf.com's keyboard (same day). The site's key is a wider pill (1.51 to 1) with Inter Bold's g centred and the dot at the letter's shoulder, 18% down and 20% in. The strip now draws exactly that at 41 by 30 instead of the site's 41 by 27, in the site's colours.
8. **"are u usng the same logo in top bar in keyboard as app icon, it should be same, i like the pill thing rn, but feel the purple dot is not in place like the app icon, also why is it black in dark mode also"** (same day). It wasn't the same: pass 7 copied the site's key, whose g is Bold and whose dot is pinned to the pill's corner. The pill stayed. Inside it is now the icon's own mark, measured off the 1024pt icon: the SemiBold g and the dot where the icon has it, higher and further right of the letter than the corner put it, drawn as one unit centred in the key. On a dark sheet the key is white with an ink g, the icon itself, instead of black on black. The act panel's working key carries the same mark. S129 and S130 check an ink face in light, a white face in dark, and violet at the icon's dot position.


### 8.5 Design artifacts and references outside the code

- **Mobbin** was used on 2026-09-12 and 2026-09-13 (Wispr Flow's keyboard setup flow as the onboarding benchmark, Raycast iOS, Dot's settings, Brave Leo, Opera's Light/System/Dark control, Sora and Philips Hue dark keyboards, Snapchat's theme grid). Later the Mobbin connector needed re-authorization and could not be used; authorize it before relying on it.
- **Paper** (design tool, 2026-09-14 19:24): Arpit asked to "port all app and website design to paper now with all screens and flows". Built in the Paper file named "Humble hill" in the "glyf" team: a design system page (wordmark, icon, palette, type scale, buttons, keycaps, chips, cards, 51 tokens), an onboarding page (8 screens) and an app screens page (Home, Profile, Build, Keyboard settings and Paywall sheets, Themes, Vault & shorthand, Notes). The keyboard page is empty and the website page was never started: Paper's weekly limit blocked further work (it resets weekly or with Paper Pro). Paper cannot create prototype links. Page links are in `docs/history/transcript-2026-09-14.md`.
- **Gboard** was studied on the Android emulator and from Arpit's screenshots and recording (toolbar, feature drawer, theme editor anatomy, search chips and result cards).
- **Screenshots in `docs/evidence/`**: `m0-app-first-launch.png`, `m0-final-state.png` (2026-09-11); `m4-vault-picker.png`, `redesign-home.png`, `redesign-keyboard2.png` (white redesign, 2026-09-12 midday); `m5-home.png`, `m5-build-tab.png`, `m5-profile.png`, `m5-home-clean.png`, `m5-home-simplified.png`, `m5-live-run.png` (2026-09-12 afternoon); `v2-home.png`, `v2-home-list.png`, `v2-onboarding.png`, `v2-profile.png`, `v2-connect.png`, `v2-month.png` (2026-09-12 evening); `v3-bar.png`, `v3-bar-result.png`, `v3-month.png` (2026-09-12 night); `v4-light-keyboard.png`, `v4-dark-keyboard.png`, `v5-keyboard.png`, `v6-glass.png`, `v6-design-picker.png` (2026-09-13 early morning). Nothing after 2026-09-13 02:24 was saved to `docs/evidence/` (search suite, Android, space gestures, act, typing engine screenshots were only sent in chat).

---

## 9. Milestones M0 to M9

SPEC 9 defines the milestones and says every gate is verified on the iPhone 17 Pro simulator with a screen recording, the `GLYF_MEM` peak, and automated checks, and that memory-sensitive gates must be re-verified on a physical device. Gate videos (`docs/evidence/*.mp4`) are gitignored (some are over 100 MB), so they exist only on Arpit's Mac.

| Milestone | Scope | Status | Date | Evidence |
|---|---|---|---|---|
| **M0** | Flutter app plus Swift extension in one Xcode project, App Group both ways, CI guard, memory logging, Spike A (open the app from the keyboard), Spike B (Privy Solana signing) | **Passed** on the simulator | 2026-09-11 19:39 | `docs/M0-GATE.md`, `docs/SPIKES.md`, `m0-gate.mp4`, `m0-keyboard-logs.txt`, `m0-app-first-launch.png`, `m0-final-state.png` |
| **M1** | Daily-usable keyboard, toolbar, shell chrome, design tokens, hold ripple, onboarding funnel | **Passed on the simulator**, 7/7 UI tests. **Device re-verification pending** (45 MB memory, ripple at 60 fps in Instruments, Reduce Motion and Transparency visuals, haptics, "type 200 words in Notes", Full-Access-off App Group probe) | 2026-09-12 00:35 | `docs/M1-M2-GATE.md`, `m1-m2-gate.mp4`, `m1-m2-keyboard-logs.txt` (two screenshots the doc links, `m1-home.png` and `m1-keyboard-first-look.png`, are missing) |
| **M2** | Glyf Bar, Glyf Keys, backend streaming, model fallback, metering | **Passed** (mock and live OpenRouter). Live example: "hey can you please send me the file as soon as you can thanks so much" became "Hey, send the file ASAP. Thanks!" in about 23 s on the unfunded free tier | 2026-09-12 00:35 | same doc |
| **M3** | Dictation with Raw / Clean / Formal | **Passed on the simulator** (simulated speech). Real-microphone device pass pending | 2026-09-12 ~11:14 | `docs/M3-M4-GATE.md`, `m3-m4-gate.mp4`, `m3-m4-keyboard-logs.txt` |
| **M4** | Encrypted vault, S-key picker, `;sig` shorthand, blocked types | **Passed on the simulator**, 10/10 UI tests including M1 to M3 regression | 2026-09-12 ~11:14 | same doc, `m4-vault-picker.png` |
| (redesign) | White-only, Apple-size keyboard, tab bar, logo | 10/10 UI tests | 2026-09-12 ~12:25 | `redesign-gate.mp4`, `redesign-home.png`, `redesign-keyboard2.png` |
| **M5** | Builder, Hub, Packs, step engine, non-connector catalog, Translation HUD, tones | **Passed on the simulator**, 16/16 UI tests, 30 Swift unit tests, 31 server tests | 2026-09-12 15:47 | `docs/M5-GATE.md`, `m5-gate.mp4`, `m5-*.png` |
| **M6** | OAuth broker, keyless registry, ConnectorSurface, connector Glyfs | **Buildable core done** (keyless tools live, ConnectorSurface on the demo calendar, real OAuth broker for 9 providers). **Real providers blocked on credentials.** The M6 gate (link Google, Notion and Slack; C, G, N, D, A pickers; Meet link; revoke state; no token on device by proxy check; 4 MB budget) is not met | 2026-09-12 | `docs/M5-GATE.md` (M6 section) |
| **M7** | Tone learning, monetization, polish, v1.0 App Store submission | **Partial**: tone profile, telemetry sink, plan UI with local unlock. TestFlight builds uploaded. Not done: StoreKit and receipt validation, privacy nutrition labels, App Store assets, device TestFlight pass with the 45 MB budget, submission | 2026-09-12/13 | `docs/M5-GATE.md` (M7 section) |
| **M8** | Crypto connector (separate release) | **Not started, by design** | | Spike B in `docs/SPIKES.md` |
| **M9** | Visual chain editor, more layouts and languages, then Android | Android **started early** (2026-09-13, Arpit's call after pushing TestFlight build 2: "i pushed now u work on android"). Languages: vocabulary packs only, no new layouts. Chain editor not started | | none formal |

**Work after M5 that had no formal gate** (dates in section 12): v2 redesign and Google OAuth (2026-09-12 evening), Apple parity, dark mode and key styles (2026-09-13 early), TestFlight builds 2 and 3, Android port (from 2026-09-13), Gboard-style search, themes and contacts (2026-09-13), shell redesign (2026-09-13 night), tryglyf.com wiring and brand standardization (2026-09-14), search suite with real providers and location (2026-09-14), space gestures and Acti parity (2026-09-14/15), typing engine, vocabulary and dictionary (2026-09-15). App work paused on 2026-09-15 14:44 for the website.

**Test status at the end of the build (as last reported):**

- iOS unit tests: **61** (`RunnerTests`: 38 in `GlyfEngineTests`, 12 in `TypingEngineTests`, 5 in `IntentStoreTests`, 5 in `VaultTests`, 1 template test). All passed on 2026-09-15.
- iOS UI tests: **23** in `GlyfGateUITests`. The last full-suite run reported was 16/16 on 2026-09-13 around 02:13. Tests added after that (`test01b`, `test03a`, `test03b`, `test04b`, `test04c`, `test04d`, `test04e`) passed in subsets (with `test00` first); no full run of all 23 was reported.
- Android JVM tests: 6 in `SpaceGestureTest`, 11 in `TypingEngineTest`, plus the `RealDictionaryEval` report (17 passing reported on 2026-09-15).
- Flutter: `flutter analyze` clean and 1 widget test passing (reported 2026-09-15).
- Server: 90 tests (reported 2026-09-15; server docs).
- Caution: on 2026-09-13 21:51 the assistant found that some subset runs that evening had silently executed **zero** tests because of a wrong class name (see 10.5). The re-run found two real bugs (the emoji ABC button not restoring the grid, and the note editor rendering invisible).

---

## 10. Build, run, test, release

### 10.1 Machine and toolchain (Arpit's Mac)

- macOS 26 (Darwin 25.6), Xcode 26.6, iOS 26.5 simulator runtime. Three "iPhone 17 Pro" simulators exist; the set-up one is UDID `04652CB6-3351-4F5E-934D-EF7A0B7F8585` (keyboard enabled, hardware keyboard off).
- Flutter at `/opt/homebrew/share/flutter` (3.44.8 with Dart 3.12.2 on 2026-09-11). In Flutter 3.44, `CupertinoPageTransitionsBuilder` comes from `cupertino.dart`, not `material.dart`.
- Homebrew CocoaPods (its bundled gem environment supplies the `xcodeproj` gem) and Homebrew Ruby, used by `tools/xcodeproj-env.sh`.
- Android command-line tools at `/opt/homebrew/share/android-commandlinetools` (`adb` in `platform-tools/`), AVD `Avici_API_36`, Java 17.
- Node (server and `tools/gen_contracts.mjs`), Python 3 (`tools/build_dictionary.py`).
- Not installed: `ffmpeg` (video frames were pulled with an AVFoundation Swift script), `idb`.
- **Do not search the whole disk for tools** (`find /`). Use `flutter doctor -v`, `flutter devices`, `xcrun simctl`, the paths above, or ask Arpit.

### 10.2 iOS: build and run on the simulator

```bash
# once per machine, or the software keyboard never appears (and keep Simulator.app open)
defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool false

# terminal 1, from the repo root: backend for the apps (live AI); MOCK_AI=true only for UI tests
cd server && npm run dev

# terminal 2, from the repo root: build and install
cd app && flutter build ios --simulator --debug
xcrun simctl boot 04652CB6-3351-4F5E-934D-EF7A0B7F8585
open -a Simulator
xcrun simctl install booted build/ios/iphonesimulator/Runner.app
pkill -f GlyfKeyboard.appex        # the old extension process survives reinstalls
xcrun simctl launch booted com.arpit.glyf
```

SPEC 10.2 still says `so.glyf.app` for the launch command; the bundle ID is now `com.demo.glyf`.

Useful commands:

```bash
# keyboard logs (GLYF_KB, GLYF_RUN, GLYF_DICT ...)
xcrun simctl spawn booted log stream --level=debug --predicate 'subsystem == "so.glyf.keyboard"'
# memory samples: run in the background into a file; `log show` misses them
xcrun simctl spawn booted log stream --predicate 'eventMessage CONTAINS "GLYF_MEM"' > /tmp/glyf-mem.log
ci/check_memory_budget.sh /tmp/glyf-mem.log

xcrun simctl openurl booted "glyf://intent?id=<uuid>"          # deep link
xcrun simctl location 04652CB6-3351-4F5E-934D-EF7A0B7F8585 set 12.97,77.59   # "near me"
xcrun simctl io booted screenshot ~/Desktop/glyf.png
xcrun simctl io booted recordVideo ~/Desktop/glyf.mp4
xcrun simctl erase <udid>                                      # factory reset (re-enable the keyboard after)
```

On a physical iPhone, open `app/ios/Runner.xcworkspace`, pick the device, run. Arpit has run Glyf on his own iPhone since 2026-09-12 (his WhatsApp and emoji-search screenshots came from it).

### 10.3 iOS: enable the keyboard

Manually: **Settings → General → Keyboard → Keyboards → Add New Keyboard → Glyf**, then **Glyf → Allow Full Access → Allow**. The app's onboarding opens Settings and turns green when both are done.

Automation facts:

- On iOS 26, enabled keyboards live in `.GlobalPreferences` under `AppleKeyboards` (entry `com.arpit.glyf.keyboard` since 2026-09-25), and the keyboard a field opens with is `KeyboardLastUsed` / `KeyboardLastUsedForLanguage` in `com.apple.keyboard.preferences`. The UI tests rely on Glyf being the last used one: they can't find the globe on iOS 26's bottom row. After a bundle rename, rewrite both and reboot the simulator (the old entry `com.demo.glyf.keyboard`), not in `com.apple.Preferences`. Pre-enable for CI with `xcrun simctl spawn booted defaults write .GlobalPreferences AppleKeyboards -array "en_US@sw=QWERTY;hw=Automatic" "emoji@sw=Emoji" "com.demo.glyf.keyboard"` and reboot the simulator (`docs/SPIKES.md` shows the old ID).
- Full Access has no known defaults key. `test00_GrantFullAccess` drives the real Settings app. The switch's accessible frame spans the whole row, so a center tap hits the label: tap at 94% of the frame width, then tap the alert's last button ("Allow").
- The first keyboard presentation shows the QuickPath "slide to type" interstitial with a Continue button; tests dismiss it.
- A new keyboard bundle identity resets Full Access, and a keyboard process started before the grant must be killed (`pkill -f GlyfKeyboard.appex`).
- Two installed Glyf apps (the old `so.glyf.app` and `com.demo.glyf`) produced duplicate "Glyf" rows in Settings and silently broke the Full Access automation. Uninstall the old one.

### 10.4 iOS: Xcode project wiring scripts

Never hand-edit the project for these; run the scripts through `tools/xcodeproj-env.sh <script.rb>`.

| Script | What it does |
|---|---|
| `tools/add_keyboard_target.rb` | Creates the GlyfKeyboard extension target (idempotent): Info.plist and entitlements, `APPLICATION_EXTENSION_API_ONLY`, bundle IDs (constants `com.demo.glyf` / `com.demo.glyf.keyboard`), embeds the appex, adds the "Glyf CI Guard" build phase. It sets the extension's build number to 1, so bump it if the target is ever recreated. |
| `tools/fix_phase_order.rb` | Moves "Embed Foundation Extensions" before Flutter's "Thin Binary" phase. Fixes the "Cycle inside Runner" build error. |
| `tools/add_uitest_target.rb` | Adds the `GlyfM0UITests` UI test target to the Runner scheme. |
| `tools/sync_keyboard_files.rb` | Adds every Swift file under `GlyfKeyboard/` to the keyboard target, the shared ones to RunnerTests (`TEST_SHARED`) and Runner (`RUNNER_SHARED`), and new files under `Runner/` and `RunnerTests/`. **Run after adding any Swift file**, or the build silently uses a stale app. |
| `tools/add_keyboard_resources.rb` | Bundles `app/dict/en.glyd` and `app/assets/vocab/packs.json` into the keyboard and removes the stale `en_US.glyd` reference. |

Other project settings changed by one-off scripts that are not in the repo: the development team on both targets (2026-09-12) and `SWIFT_ACTIVE_COMPILATION_CONDITIONS = $(inherited) DEBUG` on the Debug configs of Runner, GlyfKeyboard and GlyfM0UITests (2026-09-14). Keep both if the project is ever regenerated.

### 10.5 iOS and Flutter: tests

**Unit tests** (`app/ios/RunnerTests`, 61): secret scanner, clipboard expiry and refusal, word tracking, layouts and accents, settings migrations, paste format, debug/release backend URL, tone hints, space gestures, cursor mirror, intents (TTL, replay, single read), vault rules and encryption, and the shared typing cases. The typing tests load the real dictionary cases from `shared/typing/`.

**UI gate tests** (`app/ios/GlyfM0UITests/GlyfM0UITests.swift`, class `GlyfGateUITests`, 23): they drive the real keyboard in the simulator against the backend in `MOCK_AI` mode.

| Test | Covers |
|---|---|
| `test00_GrantFullAccess` | Enables the keyboard's Full Access through Settings. Run it first in every subset. |
| `test01_TypingAutocapAutocorrectAndToolbarCollapse`, `test01b_AutocorrectUndoTeachesAndPredictsNextWord` | Typing, autocap, autocorrect, undo teaching, prediction, toolbar collapse and restore |
| `test02_ShellNavigationAndSettings` | g menu navigation and settings |
| `test03_EmojiBoard`, `test03a_EmojiSearchShowsLetterKeys` | Emoji insert; emoji search shows the letter keys |
| `test03b_SearchSuiteCardsAndPasteFormat` | Search landing, cards, paste format |
| `test04_GlyfBar_SpaceHold_MockRun_Replace` | Space hold on an empty field, bar, mock run, Replace |
| `test04b_SpaceBar_GlideMovesCursor_HoldOpensBar` | Exact cursor glide results, hold on text opens act, empty field opens bar chips |
| `test04c_ActOnTypedText_InsertReplacesTheIntent`, `test04d_ActPlace_ShowsMap` | Act Insert; place map (writes a `GLYF_SHOT` marker for screenshots) |
| `test04e_BoundKeySkillHUD_ProofreadInserts` | Bound P skill HUD |
| `test05_GlyfKey_T_TranslationHUD` | Hold T toggles the HUD strip |
| `test06_OnboardingFunnel` | Onboarding end to end |
| `test07_DictationEndToEnd` | Dictation handoff, insert exactly once |
| `test08_VaultPickerAndShorthand`, `test09_VaultBlocksSecrets` | Hold S picker, `;sig`, card refusal |
| `test10_TonesPopup_R_RewritesCasual`, `test11_KeylessWeather_W`, `test12_ConnectorSurface_C_InsertsEvent` | Tones, keyless weather, calendar picker |
| `test13_BuilderMockEndToEnd`, `test14_PackApplyWithKeyDiff`, `test15_PaywallRenders` | Builder, packs, paywall |

The M0 tests quoted in `docs/M0-GATE.md` (`testA_TypingAndAppGroupBridge`, `testB_SpikeA_OpenHostAppFromSettings`, `testZProbe_AppGroupWithFullAccessOff`) and its `-only-testing:GlyfM0UITests/GlyfM0UITests/...` commands are **no longer in the file**; the class was renamed and the tests replaced.

**Running the UI suite without stale-binary traps:**

```bash
# terminal 1, repo root: deterministic backend, zero AI quota
cd server && MOCK_AI=true npm start

# terminal 2, repo root
cd app/ios
xcodebuild build-for-testing -project Runner.xcodeproj -scheme Runner \
  -destination 'platform=iOS Simulator,id=04652CB6-3351-4F5E-934D-EF7A0B7F8585'
xcrun simctl install 04652CB6-3351-4F5E-934D-EF7A0B7F8585 \
  ~/Library/Developer/Xcode/DerivedData/Runner-*/Build/Products/Debug-iphonesimulator/Runner.app
pkill -f GlyfKeyboard.appex
xcodebuild test-without-building -project Runner.xcodeproj -scheme Runner \
  -destination 'platform=iOS Simulator,id=04652CB6-3351-4F5E-934D-EF7A0B7F8585' \
  -parallel-testing-enabled NO \
  -only-testing:GlyfM0UITests/GlyfGateUITests/test00_GrantFullAccess \
  -only-testing:GlyfM0UITests/GlyfGateUITests/test08_VaultPickerAndShorthand
# then restart the server WITHOUT MOCK_AI before anyone looks at the app
```

- The `-only-testing` path must be `GlyfM0UITests/GlyfGateUITests/<test>`. A wrong class name matches nothing and xcodebuild still prints "Test Suite passed" with `Executed 0 tests`. Always check that N is greater than zero.
- Keep parallel testing off (simulator clones do not have the keyboard enabled).
- A wedged session (xcodebuild prints nothing, the runner stays alive): `xcrun simctl shutdown` then boot. Killing `testmanagerd` makes it worse.
- Failure forensics: Xcode 26 result bundles contain a video per test (`xcrun xcresulttool export attachments`).

**Launch arguments for tests** (handled in `app/ios/Runner/AppDelegate.swift`, `DictationEngine.swift` and `vault_screen.dart`):

| Argument | Effect |
|---|---|
| `--glyf-skip-onboarding` / `--glyf-reset-onboarding` | Write or delete `onboarding.json` |
| `--glyf-seed-bindings` | Fill the full 10-key test map (only keys not already bound) |
| `--glyf-seed-vault` | Seed a Home address and a UPI placeholder when the vault is empty, and always refresh the `;sig` snippet |
| `--glyf-dump-vault` | Write the **decrypted** vault to `vault-debug.json` (forensics only) |
| `--glyf-reset-typing` | Write a reset edit so the typing engine starts empty |
| `--glyf-fake-dictation` | Stream a canned transcript instead of the microphone |
| `--glyf-test-prefill-card` | Open the vault form prefilled with a test card number to exercise the refusal |

**Flutter:** `cd app && flutter analyze && flutter test`. The only widget test checks that a fresh install lands on the onboarding hello step ("Set up Glyf" and "Every key is a Glyf."), so update it if that copy changes.

### 10.6 Android: build, install, enable the keyboard

```bash
ADB=/opt/homebrew/share/android-commandlinetools/platform-tools/adb
# start the emulator (AVD Avici_API_36) from the SDK's emulator tool, or with `flutter emulators`
# terminal 1, repo root (the emulator reaches the Mac at 10.0.2.2:8787)
cd server && npm run dev
# terminal 2, repo root
cd app && flutter build apk --debug
$ADB install -r build/app/outputs/flutter-apk/app-debug.apk
$ADB shell am start -n com.demo.glyf/.MainActivity
# ALWAYS after a reinstall: reinstalling over the active keyboard wedges it
$ADB shell ime reset
$ADB shell ime enable com.demo.glyf/.ime.GlyfIME
$ADB shell ime set com.demo.glyf/.ime.GlyfIME
```

- Run `ime set` **after** launching the app (after an install and force-stop the system falls back to Gboard), then tap a text field. After the keyboard hides, a focused Flutter field needs a second tap to bring it back.
- The wedge looks like the keyboard is selected but never shows, or like an AI run "stuck at Running...". It is not a code bug; the reset, enable, set triple fixes it.
- On a phone: Settings → On-screen keyboard (or Keyboard list) → enable Glyf, then choose it with the keyboard picker. The onboarding's "Switch to Glyf" button opens the picker.
- Unit tests: the JVM tests in `app/android/app/src/test/` (the exact Gradle command used was not recorded; the standard one would be `./gradlew :app:testDebugUnitTest` from `app/android`).

**Emulator recipes** (from the space-gesture and typing work):

- `adb shell input text` bypasses the IME (and needs `%s` for spaces). To exercise Glyf keys, tap coordinates taken from a fresh screenshot. Arpit sometimes uses the emulator at the same time, so take the screenshot right before tapping.
- Space glide: `adb shell "input motionevent DOWN x y; input motionevent MOVE x2 y; input motionevent UP x2 y"` (each `input` call takes 0.1 to 0.3 s, which gives Apple's press, pause, glide).
- Space hold: `adb shell "input motionevent DOWN x y; sleep 0.9; log -t GlyfTest before-UP; input motionevent UP x y"`, then check that logcat shows `space hold → AI` (tag `GlyfKB`) **before** the marker.
- After `input text`, wait about 2.5 s before a glide (it races Flutter's debug editing state).
- Flutter field text is not visible to `uiautomator`; read it from screenshots. For native fields `uiautomator dump` lists `text=` before `class=`.
- Theme testing: write settings directly with `adb shell run-as com.demo.glyf sh -c 'cat > files/bridge/settings.json'`, then refocus a field.

### 10.7 Regenerating shared artifacts

```bash
# dictionary for both keyboards, then rebuild both apps
python3 tools/build_dictionary.py app/dict/source/en_wordlist.combined.gz app/dict/supplement_en.combined app/dict/en.glyd
# small test dictionary used by the golden cases
python3 tools/build_dictionary.py shared/typing/golden.combined shared/typing/golden.glyd
# intent/result contracts (Swift, Dart, zod)
node tools/gen_contracts.mjs
```

### 10.8 CI guard scripts

| Script | Checks | Notes |
|---|---|---|
| `ci/check_keyboard_clean.sh [Runner.app]` | The extension exists and neither links nor embeds Flutter (`otool -L`) | Also runs as the "Glyf CI Guard" build phase on every Runner build |
| `ci/check_no_secrets.sh` | Key-shaped strings (OpenRouter, OpenAI-style, Google, Slack, AWS, PEM, Privy secret prefixes) | Scans `app/lib`, `app/ios`, `server/src`, `shared`. It does **not** scan `app/android`. |
| `ci/check_memory_budget.sh <log>` | Peak `GLYF_MEM` under 45 MB | Warns on simulator numbers; fails only with `GLYF_MEM_STRICT=1` |

There is no hosted CI pipeline; the scripts are run by hand.

### 10.9 Signing, App Store Connect, TestFlight

**Team and IDs.** Since 2026-09-25 Glyf ships under **Arpit's own individual developer account**: App ID `com.arpit.glyf`, extension `com.arpit.glyf.keyboard` (an extension's ID must start with the app's ID), App Group `group.com.arpit.glyf`. Automatic signing on Runner and GlyfKeyboard, all configurations; `DEVELOPMENT_TEAM` is empty in the project until his team is picked in Xcode (Signing & Capabilities, both targets), and the first archive from the Xcode GUI registers both App IDs, the App Group and Sign in with Apple. Until then the TestFlight builds lived under a friend's team, **Console Labs India Private Limited (`XFSL58LKTQ`)**, as `com.demo.glyf`; that App Store Connect record may still hold the name "Glyf".

**Capabilities** (Arpit asked "what are the capabilities i need to add to apple app store" on 2026-09-12 20:29; answer updated to the current IDs):

- **Needed now, on both App IDs**: **App Groups**, with the group `group.com.arpit.glyf` registered and assigned. **Keychain Sharing** on both targets with group `so.glyf.shared` (added in Xcode; there is no portal checkbox). **Sign in with Apple** on the app. The entitlements files already declare them.
- **Later**: **In-App Purchase** on the app (StoreKit 2 subscriptions; enabled by default on App IDs, add the capability in Xcode and create the products in App Store Connect). **Sign in with Apple** only if M8's login offers third-party social sign-in (Guideline 4.8).
- **Not needed**: Associated Domains (only if deep links move from `glyf://` to universal links), Push Notifications.
- **Not capabilities but reviewed**: microphone and speech recognition usage strings plus App Privacy answers; `RequestsOpenAccess` (Full Access) in the keyboard's Info.plist, which App Review asks you to justify.

**Archive errors hit on 2026-09-12 and how each was fixed:**

| Error | Cause | Fix |
|---|---|---|
| ITMS 90242 `LSApplicationCategoryType` and 90236 ICNS icon (reported from a screenshot) | Xcode archived the **Mac ("Designed for iPad")** variant: with no iPhone plugged in, the destination picker defaults to "My Mac" | Archive with destination **Any iOS Device (arm64)**, or use `flutter build ipa`. (The assistant suggested unchecking the Mac destination in Supported Destinations; whether that was done is not recorded.) |
| `Signing for "GlyfKeyboard" requires a development team` | The extension target had no team at all | Team set on all three GlyfKeyboard configurations |
| `No Account for Team "246K6T9TPL"`, plus three provisioning errors: the profile `iOS Team Provisioning Profile: *` doesn't include the App Groups capability, doesn't support the `group.so.glyf.shared` App Group, and doesn't include the `com.apple.security.application-groups` entitlement | `246K6T9TPL` in the project belonged to no account Xcode knew; Xcode fell back to a wildcard profile, which can never carry App Groups | Switched all six Runner and GlyfKeyboard configurations to `XFSL58LKTQ`. The **first archive must be done in the Xcode GUI** so automatic signing registers both App IDs and the App Group and creates the Apple Distribution certificate (an interactive prompt the CLI cannot handle). After that `flutter build ipa` works. |
| Bundle ID did not match the registered App ID | The project used `so.glyf.app` | Renamed to `com.demo.glyf` (section 3.3) |

**Releasing a TestFlight build:**

1. Bump the build number **everywhere**: `app/pubspec.yaml` `version: 1.0.0+N` and every `CURRENT_PROJECT_VERSION = N` in `app/ios/Runner.xcodeproj/project.pbxproj` (12 occurrences today, including the keyboard's). Keep `MARKETING_VERSION = 1.0.0` identical everywhere. The runner app reads `FLUTTER_BUILD_NUMBER`, but the extension reads its own project settings and does not inherit Flutter's number; App Store validation rejects mismatched app and extension versions.
2. `cd app && flutter build ipa --release`, or archive in Xcode with Any iOS Device.
3. Check the built bundles report the same version and build for app and appex (the assistant used `plutil` on the built Info.plists).
4. Upload `build/ios/ipa/*.ipa` with Xcode Organizer or Transporter.

**Build history:**

| Build | When | Notes |
|---|---|---|
| 1 | 2026-09-12 night (inferred) | Not recorded in the transcripts; build 2 implies an earlier upload |
| 2 | Bumped 2026-09-13 02:31; Arpit: "i pushed now u work on android" (02:38) | The bump also fixed a lurking rejection: the extension had `MARKETING_VERSION` 1.0 instead of 1.0.0 and a hard-coded build 1 in some configurations |
| 3 | Bumped 2026-09-13 20:07 with the export compliance key | The assistant reported it "Ready to push". **Whether it was uploaded is not recorded.** At the bump it included the emoji and connector search fixes, theme fixes, the smoothness pass, Inter, contacts search, themes and the first search suite. At 21:51 the assistant said the keyboard menu redesign would also "ride your next TestFlight push", so what an uploaded build 3 contains depends on when it was archived |
| next | | Everything from 2026-09-14 onward (tryglyf.com backend switch, real search providers, location, space gestures, act, Skills hub, typing engine, dictionary) needs build 4 or later |

**"Missing Compliance"** (Arpit, 2026-09-13 20:07: "why is appstore connect showing Missing Compliance fix this too"). Every upload that talks HTTPS gets the export compliance question. Glyf only uses exempt encryption (HTTPS/TLS, CryptoKit AES-GCM, Keychain), so `ITSAppUsesNonExemptEncryption = NO` was added to both `app/ios/Runner/Info.plist` and `app/ios/GlyfKeyboard/Info.plist` from build 3 on. For a build already uploaded without the key, click **Manage** next to Missing Compliance in App Store Connect and answer: uses encryption, only exempt (standard HTTPS and OS-provided crypto), not subject to the French declaration.

**What testers get today.** The backend runs only on Arpit's Mac and `https://api.tryglyf.com` does not exist yet. Builds 2 and 3 predate the release-URL switch (2026-09-14) and point at `127.0.0.1`. So on testers' phones typing works, but AI, search, act, Skills and connectors cannot reach a server (inferred from dates, not verified on a tester device). A deployed server is required before TestFlight is a real product test. The assistant offered Fly.io or Railway; no host was chosen.

**Android release.** `buildTypes.release` still signs with the debug key (TODO in `build.gradle.kts`). No Play Console account, no release keystore, no Play Billing yet.

### 10.10 Traps and quirks (each one cost real time)

**iOS keyboard and simulator**

- The software keyboard never appears in a headless simulator or with the hardware keyboard connected: set `ConnectHardwareKeyboard` to false and keep Simulator.app open.
- Stale binaries: the extension **process survives an app reinstall** (`pkill -f GlyfKeyboard.appex`), and `xcodebuild test` may skip reinstalling an app whose main binary did not change even when the appex did (install from DerivedData yourself).
- New Swift file not in the target: the build silently uses a stale app. Run `tools/sync_keyboard_files.rb`. Engine files the tests need must be in `TEST_SHARED` too.
- "Cycle inside Runner": run `tools/fix_phase_order.rb`.
- `#if DEBUG` dead in the keyboard: check `SWIFT_ACTIVE_COMPILATION_CONDITIONS` first (section 3.6).
- Keyboard heights are cached and oversized by iOS (section 5.2).
- Reading the pasteboard on appearance shows Apple's paste prompt (section 4.3).
- The keyboard's colors follow the **host app's** `keyboardAppearance`, not the system setting; a dark host renders dark even in system light mode.
- Phantom text sessions during host relaunch accept inserts that never appear and may flush later (take once, insert once).
- `UIAlertController` is clipped in the keyboard window; use inline menus.
- A new surface missing from `applySurfaceLayout`'s alpha-restore list renders invisible.
- The first presentation shows the QuickPath "Continue" interstitial.
- `flutter build ios` can serve a stale Dart build; `App.framework`'s modification time is the truth, and `rm -rf app/.dart_tool/flutter_build app/build/ios` forces a clean one. (The night this was suspected, the real cause was Apple's keyboard left active after cycling the globe key and a 1 AM clock misread, so check the obvious first.)
- `GLYF_MEM` lines can only be captured with `log stream`, not `log show`.
- The assistant's own iOS Simulator panel tool never worked on this Mac (it claimed Xcode was not selected even though `xcode-select -p` was correct; `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` or a restart may fix it). Its tap tool also could not hit the emoji search field. Drive such flows with XCUITest.
- SourceKit "No such module UIKit/Flutter/XCTest" warnings in editors are noise; the real build decides.
- Swift gotchas met: `textDocumentProxy.isSecureTextEntry` is optional (`?? false`); `Locale.current.region` needs iOS 16, so the code uses `regionCode`; stored properties cannot live in extensions.

**Flutter under XCUITest**

- `PageView` pages report frames in scroll-content coordinates: taps, hit-testing and queries are unreliable and offscreen pages match. Onboarding uses an `AnimatedSwitcher` for this reason; otherwise drive by screen coordinates and assert outcomes.
- Modal bottom sheets report warped frames once the keyboard lifts them: taps land on the barrier and dismiss the sheet. Make form sheets non-dismissible, avoid typing in modals under test (use prefill launch arguments), tap Save-type buttons by geometry.
- `Semantics(identifier:)` does surface on Flutter text fields (for example `textFields["vault-value-field"]`).
- A `Tooltip` swallows its child's text in the accessibility tree (the letter "Z" vanished once Z was bound). Don't put tooltips on things tests must find.
- A row mixing texts and icon buttons merges into one accessibility node; query `descendants(matching: .any)` with `label CONTAINS`.
- `UITableViewCell` identifiers are invisible to XCUITest unless the cell is an accessibility element, and even then they are neither keys nor buttons (the `kb()` helper falls back to any descendant).
- XCUITest's first "phantom" text session reports autocapitalization `none`, so the harness's first letter can be lowercase. Tests assert case-insensitively; **never "fix" the product for this**.
- The Home try field sits under the key map: check whether it is visible before swiping, and swipe toward it (swiping first scrolled it away and failed every keyboard test once).
- A tab kept alive in a `Stack` or `IndexedStack` never refetches on return; listen to the selected-tab notifier.

**Android**

- Reinstalling over the active IME wedges it system-wide: `ime reset`, `ime enable`, `ime set` after every install.
- targetSdk 34+ throws `SecurityException` for `Settings.Secure.ENABLED_INPUT_METHODS`; use `InputMethodManager.enabledInputMethodList` and, on API 33+, `currentInputMethodInfo`.
- Keys under the gesture-navigation zone become navigation gestures: keep the navigation-bar inset padding.
- `LAYER_TYPE_SOFTWARE` and `setShadowLayer` made every key press redraw the whole keyboard on the CPU.
- Roboto draws `⏎` and `⇧` badly: they are canvas paths.
- AGP 8 and later do not generate `BuildConfig` unless `buildFeatures { buildConfig = true }`.
- Kotlin: a parameter named `text` shadows `TextView.text` inside `apply {}` ("'val' cannot be reassigned").
- Launcher icons need `mipmap-anydpi-v26/ic_launcher.xml`.
- `minSdk` is at least 26 for `java.time`; cleartext HTTP only to the three dev hosts.
- After install plus force-stop, the system switches back to Gboard; set the IME after launching the app.

**Process**

- UI tests need `MOCK_AI=true`; anyone looking at the app needs the live server. Leaving mock mode on showed fixtures to Arpit.
- An old server process can answer `/health` but 404 every new route: restart the backend after adding routes.
- Hub QA writes install counts to `server/data/`; reset those files with the server stopped.
- Don't run broad filesystem scans; don't run page JavaScript or headless-browser scripts when researching (both triggered permission prompts that angered Arpit).

---

## 11. Pending work, known issues, what Arpit owes

### 11.1 What Arpit still owes (as of 2026-09-16)

| # | Item | Unlocks |
|---|---|---|
| 1 | `GEMINI_API_KEY` and/or `GROQ_API_KEY` in `server/.env` (free, no card; the model chain is already configured and skips providers without keys), or $10 of OpenRouter credit | Fast AI. Free OpenRouter models took 12 to 20 s or more, and the daily free quota ran out during testing |
| 2 | `GEOAPIFY_KEY` (no card) | Maps tab, nearby landing rows, Android act maps |
| 3 | Optional `BRAVE_SEARCH_KEY`, `GOOGLE_PLACES_KEY` (billing), `GOOGLE_WEATHER_KEY` | Real web links and live answers ("World Cup today"), ratings and open-now, weather card |
| 4 | YouTube key hygiene: restrict it to YouTube Data API v3 now; after deploy restrict it to the server's IP and regenerate it (it was pasted in chat); file the quota extension (needs a public URL, privacy policy and demo account; approval takes weeks) | A YouTube tab that survives launch traffic |
| 5 | OAuth client credentials: Google (`GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, consent screen, test users, both redirect URIs), Notion, Slack, and any of GitHub, Linear, Todoist, Calendly, Zoom, Spotify. Start Google's verification early for the sensitive scopes | Real connectors, Google sign-in, liked videos |
| 6 | `KLIPY_APP_KEY` from partner.klipy.com (free; ask for production access once "Search KLIPY" is live) | GIFs and KLIPY stickers in the emoji board (stickers already work without it, from Noto) |
| 7 | A server host and DNS for `api.tryglyf.com` (then `OAUTH_REDIRECT_BASE` and `PUBLIC_BASE_URL`) | AI and search on TestFlight builds; OAuth callbacks; mini-app pages |
| 8 | App Store Connect subscription products for Plus and Max, and what receipt validation needs | Real purchases |
| 9 | A physical-device test session | The 45 MB memory gate, ripple profile, haptics feel, real-mic dictation latency, Full-Access-off App Group probe, "type 200 words in Notes" |
| 10 | Google Play Console account and a release keystore | Android testers and release |
| 11 | ~~A privacy policy~~ **Written 25 Sep:** https://www.tryglyf.com/privacy (`site/app/privacy/page.tsx`), live once pushed. Update it when a feature starts sending something new | App Store, YouTube quota form, AI provider terms |
| 12 | Rotate secrets that were pasted in chat: OpenRouter key, Privy app secret, YouTube key, Neon database password | Security |
| 13 | Privy dashboard configuration | M8 only |
| 14 | Authorize the Mobbin connector; Paper Pro or wait for the weekly limit | Design research, finishing the Paper port |
| 15 | Decisions: back up vault and settings across uninstall (iCloud or export) or not; how to handle Guideline 4.4.1 and the app opener; the app's onboarding tagline ("Every key is a Glyf." vs the site's "Type less. Glyf more.") | Section 11.2 |

### 11.2 Must happen before an App Store submission

- **Real purchases**: StoreKit 2 in the app, server-side receipt validation, remove the local "Get Plus / Get Max" unlock, and stop the server trusting the plan a device sends.
- **Deployed backend** and a release build pointing at it, verified on TestFlight.
- **Device gate pass** (memory, performance, haptics, microphone, Full Access off).
- **Review risks**: `HostAppOpener` reaches `UIApplication` through the responder chain (unsupported); Guideline 4.4.1 forbids keyboards launching apps other than Settings, and the dictation handoff, the shell's "Open in Glyf app" footer and the connector action all do that. Prepare the Full Access justification. Confirm the keyboard stays useful without Full Access on a device.
- **Privacy**: App Privacy answers and nutrition labels, matching what the privacy policy says; the policy URL `https://www.tryglyf.com/privacy` in App Store Connect; Google OAuth verification if Gmail, Calendar or YouTube scopes stay in onboarding; fix onboarding's "Read-only" wording (section 11.4).
- **Store assets**: screenshots, description. (The icon is final.)
- **Finish or hide inert UI** (section 11.4 items 6 to 10).
- **Copy pass**: remaining explainer lines and em dashes.
- **Attribution**: YouTube marks on every card are in place; if Geoapify is used, add "Powered by Geoapify" (not present in app code).
- Build number 4 or later, compliance key present, no crypto code (already true).

### 11.3 Product work that is pending

- **App UI redesign with light and dark mode.** Arpit on 2026-09-15: "its shit in mobile rn" and "i need both light and dark modes both in site and later in apps too". The website (tryglyf.com, see the site docs) is the latest design he liked, but his instruction was only that the site must not copy the current app ("dont copy mobile for that"). Whether the app should adopt the site's look is not decided; ask him.
- **Sign-up and accounts**: a sign-up page first, users stored in the same Neon Postgres database as the website waitlist, then onboarding, then Google and other permissions requested only when a feature needs them. This will move the Google step out of onboarding.
- **Android parity** (section 6): delete repeat, multi-touch, caps lock, accents, globe, one-handed mode, emoji search and recents and the emoji key, clipboard history, in-keyboard settings and screens, Translation HUD, tones, vault picker and calendar surfaces, tone learning, dictation, the vault kind and rule mismatch.
- **Real connectors in the keyboard**: Google Calendar in the ConnectorSurface, the Gmail, Notion, Drive, Slack and Contacts pickers, an instant Meet link, action bar verbs that act in place; Connect buttons for non-Google providers in the app.
- **GIF and sticker tabs on Android** (iOS built 2026-09-24).
- **Keyboard telemetry** and the D1/D7/D30 retention dashboard the spec calls the only metric that matters.
- **M9**: visual chain editor for conditionals; Hindi (Devanagari plus transliteration) and other layouts (SPEC 6.17).
- **Acti extras not built**: Notion summon and LinkedIn HUD skills, app icon in the key balloon while holding, backspace swipe-delete, swipe-up numbers, haptic strength levels.
- Emoji suggestions from AOSP's emoji list.
- Tone learning gate demonstration (a rewrite visibly changes after 10 accepts).
- Finish the Paper design port if still wanted.
- **M8 crypto** as a separate release, per the spec.

### 11.4 Known issues found in the code while writing this doc

These were found by reading the code on 2026-09-16. None were reproduced at runtime.

1. **Plans have no receipts yet.** The paywall asks the server (`POST /me/plan`), which only says yes when `PLAN_SELF_SERVE=true`; production must keep that off until StoreKit lands (section 5.21).
2. **Android refuses vault kinds the app offers.** `vault_screen.dart` offers `name, email, phone, address, upi, gst, wallet, link, social, bio, reply, custom`; Android `VaultStore.kt` only allows `address, upi, email, phone, handle, link, custom`, so saving a name, GST number, wallet, social link, bio or saved reply fails on Android with "That kind of info can't be stored".
3. **Android vault rules are weaker than iOS**: no label check (password, pin, cvv and so on), no government-ID check, no 2000-character cap, a different trigger rule (lowercase letters and digits only), combos not validated against existing fields, and the keyboard's vault panel does not list combos. `SecretScanner.kt` patterns also differ from Swift.
4. **Android keyboard gaps**: no delete repeat, single-pointer touch only, no caps lock, no accent popups, no one-handed mode, no globe key, the bottom-row emoji key does nothing, `surface:` and `connector:` bindings open the app, no tone outcome recording or tone hint, and the toolbar order and hidden settings are ignored.
5. **Android emoji data has a corrupted token** (a Unicode replacement character followed by the word "against") in the sports group of `GlyfIME.kt`, masked by a filter. Harmless, but clean it up.
6. ~~`glyf://open?path=...` deep links are not routed~~ Fixed 2026-09-24: `main.dart` routes `build`, `keys`, `vault`, `connectors`/`connected`, `settings` and `wallet` to their screens.
7. **Profile → My Glyfs and Creator stats** do nothing when tapped.
8. ~~**Profile → Connected tools** has Connect and Disconnect only for Google.~~ 25 Sep: Connected tools has Calendar and Google Meet (section 5.28), Booking link and Contacts; the other providers are Coming soon.
9. **iOS in-keyboard menu**: the Glyfs and Packs rows do nothing; Connectors is demo-only with a "soon" line; the Account screen always says "Free" (it ignores `plan`) and cannot be reached from the grid; the list-based `root` screen definition (with Notes and Account rows) is dead code behind the grid.
10. **ConnectorSurface action "New event from my text"** only opens the app.
11. **Onboarding "Connect your Google" says "Read-only"**, but the Calendar scope is `calendar.events` (read and write) and Gmail is `gmail.compose` (creates drafts).
12. **Copy conflicts with Arpit's preferences**: app strings still contain em dashes (Glyf Bar input chip and Full Access message, Translation HUD placeholder and its "Replaced" message, the connector offline message and its "Details" insert text, vault and notes refusal messages, Android's OTP refusal, an onboarding location note, `NSContactsUsageDescription`) and some explainer lines (the HUD placeholder, the bar's "Pick a quick Glyf or describe what you want", the Notes empty state, onboarding footnotes).
13. **Home key map** (`keyboard_visual.dart`) still draws a 50% purple border on bound keys, while borders were removed from the keyboard and the Home list keycaps.
14. **Onboarding still says "Every key is a Glyf."**, a line Arpit said on 2026-09-15 he did not like much for the site. The widget test asserts it.
15. **Key sounds toggle on iOS** may not silence every click: `KeyboardView.tapAction` calls `playInputClick()` without checking `keyClicks` (the system Keyboard Clicks setting still applies).
16. **Test launch arguments are handled in release builds too** (`AppDelegate.swift` is not wrapped in `#if DEBUG`), including `--glyf-dump-vault`, which writes the decrypted vault to the App Group. Launch arguments cannot normally be passed to App Store builds, but wrapping these in `#if DEBUG` is safer.
17. **`ci/check_no_secrets.sh` does not scan `app/android`.**
18. **Keyboards send no telemetry.**
19. **Android settings defaults** omit `search` from `toolbarOrder` and have no `vocabPacks` / `vocabLearning` keys (the code falls back correctly, but the files differ from iOS).
20. **Unused code**: `DraggableOrb` in `orb.dart`; the `POST /tools/run` client helpers on both keyboards.
21. **Onboarding's location error messages** expect a `nofix` code that only Android returns; iOS reports "unavailable" for the same situation.

### 11.4b Found by using every feature (audit, 25 Sep 2026 evening)

A fresh install on the iPhone 17 Pro simulator (iOS 26.5), taken through sign-in, all eight onboarding steps, the eight tour chats, every tab and Profile screen and every keyboard panel, then the Android keyboard on the emulator. Fixed the same evening:

- **Backspace put a corrected word back in the wrong place.** Holding delete over "I'm free Fri, Sep 25, 7:30–8:00 PM" left "I'm from": the backspace-undo of an autocorrection only checked that the text ended with the corrected word, so a later "free" in other text matched and was swapped for "from". The undo is now tied to the exact text the correction left (both keyboards).
- **The iPhone keyboard froze while iOS asked "Allow Paste?".** With "Capture everything you copy" on (the default since onboarding), the keyboard read the clipboard on its main thread as it appeared; that read waits for the person's answer, so no key, strip or panel worked until then, and the UI tests hung on it. The read runs on a background queue now, a refused copy is not asked about twice (the detected-value read used to follow straight after), and a second read never starts while one is waiting.
- **Android's keyboard messages were invisible.** All eleven used system toasts, and Android draws a keyboard's window above toasts and above its own popup windows, so "Copied", "Screenshot copied" and "Connect Google Meet in Glyf › Connected tools" sat under the keys. They are drawn on the keyboard's own overlay now (`GlyfIME.notice`); scenario S137.
- **Translate bar** re-translated its own output after Replace and sat on "…" (both keyboards).
- **Clipboard paste** glued onto the word before it ("10.8QvS…"); pastes are spaced like every other insert (both keyboards).
- **"Tidy this up"** was offered on the text a rewrite had just written (both keyboards).
- **A ;trigger** got dictionary suggestions ("it's", "its") while typed (both keyboards).
- **Sunset and weather** used a saved location from another time zone: the simulator's San Francisco location with the Mac's Bangkok zone gave "Sunset 9:03 AM". On a phone that is a location saved before a flight. The phone's zone now wins (`locationFitsZone`, server).
- **Vocabulary "Make words"** failed ("no usable words") whenever the model's word list ran past its length limit; the cut-off list is recovered (server).
- **Meet link** could not be bound: it was in the catalog but not in Home's key sheet. It is now, with Google Meet's mark.
- **No privacy policy link in the app** (App Store 5.1.1): on the sign-in screen and at the bottom of Profile.
- **Keys list** in the keyboard said "Connector:calendar" (iOS).
- **Stray slot lines** beside panel titles (Calendar, Glyf) and between the g menu's icons (iOS).
- **Emoji board labels** ("Frequently used", "Trending", KLIPY's required "Powered by KLIPY") were near-invisible on painted looks (iOS).
- **Keyboard stayed up** on Vocabulary, Wallet, Builder and Vault when tapping outside a field, and came back over a new pack; **the shorthand trigger field** was autocorrected ("omw" became "On my way!").
- **Contacts permission text** had an em dash.

Still open from the audit: "Get Plus" and "Get Max" grant a plan without payment (item 1; App Review will reject a paywall that grants for free), and the symbols page does not switch back to letters after ";" or an apostrophe the way Apple's does.

### 11.5 Stale or inconsistent docs

- `README.md` (refreshed on 2026-09-16): its M9 row says the Android keyboard is "at feature parity", which section 6 shows is not true yet; its M6 row still calls the OAuth broker a "skeleton" (it is a working broker for 9 providers, waiting on credentials); its Website row says "not deployed yet" (the site went live on www.tryglyf.com at 03:12 that day).
- `SPEC.md` 10.2: `xcrun simctl launch booted so.glyf.app` (now `com.demo.glyf`).
- `docs/M0-GATE.md`: reproduce commands reference `GlyfM0UITests/GlyfM0UITests/testA...`; the class is now `GlyfGateUITests` and those M0 tests no longer exist.
- `docs/M1-M2-GATE.md`: links `evidence/m1-home.png` and `evidence/m1-keyboard-first-look.png`, which are not in the repo. It also describes the M1 "space-swipe cursor" and the forced-light keyboard, both since replaced.
- `docs/SPIKES.md` finding 2 uses the old keyboard ID `so.glyf.app.keyboard`; finding 17 (keyboard forced light) is superseded.
- `app/lib/core/theme.dart` header comment: "WHITE ONLY".
- `shared/contracts/README.md` says codegen is not built; it is (`tools/gen_contracts.mjs`).

---

## 12. Decision log (apps)

Times are IST. In the "Why" column, text in quotation marks is Arpit's own words; unquoted text is the reason recorded by the assistant or the spec.

| When | Decision | Why | Status |
|---|---|---|---|
| 2026-09-11 18:56 | Build from `GLYF_BUILD_PROMPT.md` (copied to `SPEC.md`), milestone by milestone, M0 first | SPEC 14 | Active (pace overridden, see 2026-09-12 11:39) |
| 2026-09-11 | iOS keyboard is native Swift in a separate extension; Flutter only in the container app; CI build phase enforces it | SPEC 1.1: extension memory cap | Active |
| 2026-09-11 | Keyboard and app share data through App Group JSON files and a shared Keychain key | Platform channels can't cross processes | Active |
| 2026-09-11 | Open the app from the keyboard via the responder-chain `UIApplication` and `openURL:options:completionHandler:`; write the intent first; keep a fallback | Spike A: the only strategy that works on iOS 26 | Active, review risk (11.2) |
| 2026-09-11 | M8 wallet will use `privy_flutter` directly (sign in app, broadcast via backend); no native bridge | Spike B: the Flutter SDK can sign Solana transactions | Active for M8 (not started) |
| 2026-09-11 23:14 | Provider secrets live only in `server/.env` | "for privy , keep them safe in env" | Active |
| 2026-09-11 23:14 | Acti recordings are feature references, not a design to copy; glass orb onboarding | "you do not need to copy it, just for references of features i need" | Active |
| 2026-09-12 | Delivery from the app to the keyboard is take once, insert once; never retry inserts | Phantom text sessions lose or double inserts | Active |
| 2026-09-12 | Never read the pasteboard on keyboard appearance; probe `changeCount` | Apple's paste prompt fires over the keyboard | Active |
| 2026-09-12 11:39 | Build everything now, not over weeks | "we dont have 16 -22 days, we building everything today only" | Active (as a working mode) |
| 2026-09-12 11:39 | Apple-size keyboard (260pt) via pass-through root and bottom anchoring | "why is keyboard elongated as fuck, why not apple's default size for this" | Active |
| 2026-09-12 11:39 | White-only UI; keyboard forced light; accent only as dots; black pill CTAs | "the fuck is this purple ui soo shittyy, have white mode only" | Superseded for the keyboard on 2026-09-13 00:54 and for the apps on 2026-09-15 (pending); accent and pill rules active |
| 2026-09-12 11:39 | Keycap "g" (concept 01) is the app icon, toolbar button and onboarding mark; tab-bar app | "why not using the logos i sent too"; "a bottom bar and having all this" | Active (tab icons changed 17:59) |
| 2026-09-12 13:01 | Finish M5 plus buildable cores of M6 and M7; crypto stays out | "yes finish everything end to end and cleanly" | Done |
| 2026-09-12 | Default Glyfs are server-side Builder-format JSON; clients know ids and titles only | SPEC 13 | Active |
| 2026-09-12 | Keyboard shell screens are data in one reused table | SPEC 6.3 memory budget | Active |
| 2026-09-12 | Inline menus instead of `UIAlertController` in the keyboard | Alerts clip inside the keyboard window | Active |
| 2026-09-12 16:40 | Remove explainer lines; follow Apple's design language | "i dont like explainer lines everywhere remove them"; "see apple's design language and simplify things" | Active (not fully applied) |
| 2026-09-12 17:59 | Hide setup ticks once everything is granted | "why does our app has those 3 green ticks, i guess once we got all permissions we need not show that" | Active |
| 2026-09-12 17:59 | Curated skills plus the Builder first; community hub demoted | "i think acti skill sharing platform etc is bad, we should make out own skills and ask users to select what they want" | Superseded 2026-09-14 23:25 (full Skills hub built 2026-09-15) |
| 2026-09-12 17:59 | Ship only 3 default bindings; recommendations per key; personas in onboarding; key sounds and haptics asked up front | "we can also recommend what to do for each key, and dont preset a lot, also ask all setting in user onboarding flow" | Active |
| 2026-09-12 17:59 | Home shows a live key map with the try field right under it | "i dont like that test input is soo far below glyfs keys that i have to scroll soo much" | Active |
| 2026-09-12 17:59 | Profile rebuilt on Acti's structure; Builder starts with "What do you want?" plus a tools browser | "our profile page looks bad and shit"; "i really wanna revamp the builder screen" | Active |
| 2026-09-12 17:59 | In-app Notes reachable from the keyboard | "app needs to have in app notes too which user can access like we have in s key" | Active (merged into Vault in the keyboard 2026-09-13) |
| 2026-09-12 17:59 | Field-aware layouts (email, URL, number, phone) | "figure out how keyboard looks in number inputs screen and other screens where @ needs to entered" | Active |
| 2026-09-12 17:59 | Own tab icons, no ＋ tab, Builder inside Build | "why are you using same icons as acti for bottom bar etc ... dont blindly copy" | Active |
| 2026-09-12 17:59 | Springs on every keyboard surface, crossfading tabs | "why is glyf opeing so rough" | Active (tuned 2026-09-13 19:59) |
| 2026-09-12 17:59 | GIFs via copy-to-pasteboard, server GIPHY proxy | "add gif and stickers support like gboard has it, research on that" | Replaced 2026-09-24: KLIPY called from the phone, Noto stickers, no GIPHY |
| 2026-09-24 | Emoji, Stickers, GIFs and Emoticons in one board, Apple's look | "do stickers and gifs directly here too like google board does it ... ui as close to apple keyboard as possible" | Active on iOS |
| 2026-09-12 18:42 | Google sign-in at the end of onboarding with user-chosen scopes, preset by persona | "we can have this at the end of onboarding flow based on the answered questions we will aks perms in google login" | Active in code, blocked on credentials; to be reworked by the 2026-09-15 sign-up decision |
| 2026-09-12 18:42 | Keep the key card list below the key map; tap outside dismisses the keyboard | "i liked the previous key list more"; "i should be able to close keyboard by clicking outside" | Active |
| 2026-09-12 19:15 | Generic OAuth broker for 9 providers; keyless tools expanded; month view in the calendar picker | "did u add notion, slack , and other thigs"; "i also need a button to view months calendar" | Active |
| 2026-09-12 19:15 | Plans: Free 40/day, Plus $4.99, Max $19.99; local unlock until StoreKit | "one 5 $ plan and one 20$ iguess, research on this too" | Superseded 26 Sep: new prices below |
| 2026-09-26 | Plans cheaper for launch: Plus $1.99 a month or $15.99 a year, Max $4.99 a month or $39.99 a year; greyed as Coming soon until App Store and Play purchases are built | "i think 5$ and 20$ are too high for keboard and for beggining no? we should make 2$ and 5$ ig"; "we can yearly pay too and give discounts" | Active |
| 2026-09-12 20:47 | Archive with "Any iOS Device (arm64)" | The Mac destination produced a Mac archive (90242, 90236) | Active |
| 2026-09-12 20:59 | Team `XFSL58LKTQ` (Console Labs India Private Limited) on both targets | The team in the project (`246K6T9TPL`) belonged to no account | Active |
| 2026-09-12 21:05 | Bundle IDs `com.demo.glyf` and `com.demo.glyf.keyboard`; keep `so.glyf.*` group, keychain, channel, scheme | "i have the app id as com.demo.glyf not what u put, fix that"; renaming the group would orphan data | Active, permanent |
| 2026-09-12 22:26 | Keyboard-enabled check derived from the bundle ID | The rename broke the hard-coded check | Active |
| 2026-09-12 22:26 | Bright black g keycap; de-purpled Glyf Bar (black Replace pill); Apple symbols row; month grid fills its surface | "why is glyf button so dull and sad"; "i dont like this screen much"; "why does the month have soo much gap below it" | Active |
| 2026-09-13 00:54 | Match Apple's keyboard metrics; press balloons; honor field autocapitalization; keyboard follows host dark mode with auto/light/dark; the app stays white | "i need apple like styles with our ui and apple ux, ley sizes spacing etc / and fix dark mode too" | Active (app white superseded 2026-09-15) |
| 2026-09-13 01:57 | Keep the lavender dot (and wash); remove accent borders forever; add purple under-glow | "idiot lavendar lashes are not problem, see borders ... i like the dot tho its glyf symbol of our app" | Dot and no-borders active; wash and glow moved to the optional Glow style at 02:13 |
| 2026-09-13 02:13 | Default key style Glass (dots only); Classic and Glow optional; Gboard-style picker in app and keyboard | "by default we need simple v similar to apple with just purple dots and glassy keys liquid glass" | Active |
| 2026-09-13 02:29 | Update persistence proven; lock bundle ID and team before real users; uninstall backup undecided | "can u verify that updating app wont require me to readd everything in vault and memory etc it should remember" | Active; backup pending |
| 2026-09-13 02:31 | Build 2; keep the extension's version and build in lockstep with the app | "increase build no, i am pushing update to testflight" | Active |
| 2026-09-13 02:38 | Start the Android port now (native Kotlin IME, unchanged Flutter app, same file schemas) | "i pushed now u work on android" (overrides SPEC's M9 order) | Active |
| 2026-09-13 15:04 | Gboard as the UX reference: launcher grid menu, themes screen, contacts search with permission, Google/YouTube/Maps inside the keyboard, on both platforms | "i need you to install gboard in android use it and learn from it"; "i need all features properly for both ios and android" | Active |
| 2026-09-13 16:30 | Same features and iOS style on both platforms: Inter everywhere, Cupertino controls, same toolbar | "i want exactly same features in all , and ios style in both" | Active, incomplete |
| 2026-09-13 19:36 | In-keyboard search fields collapse their surface so letter keys show | "i can’t search in emojis because keyboard not showing" | Active |
| 2026-09-13 19:59 | No key press scale; 0.30 s surface spring; Android GPU rendering with touch-down haptics and clicks | "i need smooth as fuck experience" | Active |
| 2026-09-13 20:07 | Build 3; `ITSAppUsesNonExemptEncryption = NO` in both plists | "why is appstore connect showing Missing Compliance fix this too" | Active |
| 2026-09-13 21:49 | Keyboard screens as cards without sublines; Notes inside Vault; Shorthand separate; notes editable in the keyboard | "notes shud be editable from here also , we can remove notes and vault can serve the feature and shorthand can be another thing" | Active |
| 2026-09-14 12:53 | Domain tryglyf.com in URLs; release builds use `https://api.tryglyf.com`, debug uses the Mac; persisted URLs rewritten per build; identifiers unchanged | "bought tryglyf.com now, wire it up in app and everywhere, no need to change the glyf logo" | Active |
| 2026-09-14 12:57 | One wordmark spec on every surface: raised dot at the top right after the f | "i need the dot on top right after f as we have on our keyboard / dont fuck up and fucking standardise things like this" | Active |
| 2026-09-14 13:35 | App icon: original keycap geometry on white, background removed and nothing else changed | "i just fucking asked u to remove bg and u asshole change dot possition and everything" | Active (and a working rule) |
| 2026-09-14 13:52 | Keyboard search uses the website's card designs; tap pastes; paste title and link by default with a link-only setting | "we need that in our keyboard with exact ui ux like that ... by default it should be title and link" | Active |
| 2026-09-14 14:03 | Location permission asked by the app in onboarding (and Profile), coarse and cached | "u can req location access for this if needed in on boarding flow" | Active |
| 2026-09-14 14:32 | Search opens on recents and trending, popular or nearby rows, with the keys still visible | "not put user in the search bar directly" | Active |
| 2026-09-14 15:06 | No mock results in front of users; `MOCK_AI` for tests only | "you have hard coded results in ios idiot the fuck make them work" | Active |
| 2026-09-14 15:28 | Web tab: no DuckDuckGo (measured empty), no embedded browser or login scraping; answers plus a Google handoff; Brave when real links are wanted | Research: no Google SERP product for new customers; webview OAuth blocked; legal and App Store precedents | Active |
| 2026-09-14 15:52 | YouTube via the Data API with a public-data key; Google login adds liked videos only | "shud we just do public for now ?" | Active |
| 2026-09-14 15:59 | Maps via Geoapify (no card); Nominatim dev-only | "find free alternative for maps key, i dont wanna add my card here rn" | Active, key pending |
| 2026-09-14 23:25 | Build every feature from Acti's launch video in Glyf's own look | "i hope u have seen video now i need all features from it as well" | Mostly built (section 7) |
| 2026-09-14 23:30 | Space bar: glide anytime moves the cursor; still for 0.5 s launches the AI with the finger down | "it should launch before only"; "if nothing glides for some time just open ai" | Active (release-based design superseded) |
| 2026-09-15 00:00 | New on-device typing engine (AOSP scoring, trust gates, learning) on both keyboards, held to shared test cases | "not random ass auto corrects" | Active |
| 2026-09-15 00:11 | Categorized vocabulary packs; India defaults to Hinglish; AI-made packs reviewed before saving | "like proffesoional vocab, local lang vocab, fun vocab categorise things" | Active |
| 2026-09-15 01:57 | Install the AOSP English dictionary plus a Glyf supplement; disable AOSP's real-word swaps | "yes install standrad dictionary and all" | Active |
| 2026-09-15 01:57 | Don't change AI data handling in code now; a privacy policy will cover it | "we will not work on ai privacy rn as we will have privacy policy" | Active |
| 2026-09-15 (early morning) | AI models: Gemini 2.5 Flash-Lite, then Groq Qwen and gpt-oss, OpenRouter free as tail; about $12 to 13 a month when paid | "find me good and v cheap ai model to use here, i heard groq is good but ig they stopped sharing dev apis" (Groq did not stop; it removed Llama from self-serve) | Active, keys pending |
| 2026-09-15 14:44 | Pause app work to launch the website with a waitlist | "we will come back to app by evening, i need to work on website and releae it by tonight" | App work not resumed as of 2026-09-16 |
| 2026-09-15 (questions) | Light and dark mode in the apps | "i need both light and dark modes both in site and later in apps too" | Pending |
| 2026-09-15 (questions) | Sign-up page first, users in the Neon database, then onboarding, then permissions on demand | "we will have a sign up page at first also, then onboarding then if users want more features from google etc they will be pinged to allow" | Pending |
| 2026-09-16 00:10 | Whole monorepo in the private GitHub repo `The-x-35/glyf`; gate videos and the stray `glyf/` project excluded | "push everything together on github" | Active |
| 2026-09-16 02:13 | No em dashes | "they look fucking disgusting ai made" (website) | Active on the site; apps pending |
| 2026-09-16 02:20 | No AI attribution in the git history or repo docs | Arpit asked to remove it from commit history | Active |

---

## 13. Could not verify

- Whether TestFlight **build 1** existed and when it was uploaded, and whether **build 3** was ever uploaded (only the bump is recorded).
- Which icon the early TestFlight builds carried (a 2026-09-12 20:47 transcript line contradicts the 11:41 line).
- That builds 2 and 3 point at `127.0.0.1` and therefore have no working AI for testers (inferred from dates).
- Anything on a physical device: the 45 MB memory gate, ripple frame rate, haptics feel, real-microphone dictation latency, App Group access with Full Access off, Glyf Bar and act behavior on real networks.
- Runtime confirmation of the issues in section 11.4 (all found by reading code).
- Whether the Mac ("Designed for iPad") destination was unchecked in Xcode.
- Whether the YouTube key was restricted, and whether the quota extension was filed.
- Whether `glyf/` (the stray Xcode project) has any value; it looks like an empty template.
- The exact Gradle command used for the Android unit tests, and the emulator binary path.
- The full contents of the Paper file (the tool's limit blocked reading it after the port).
- Website status is outside this doc; Arpit reported on 2026-09-16 03:12 that it is deployed on www.tryglyf.com (see `docs/WEBSITE.md`).
- The server-side details referenced here (provider behavior, meter, moderation), which belong to the server docs and were only checked at the level of route names and environment variable names.

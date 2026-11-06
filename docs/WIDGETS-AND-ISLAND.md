# Widgets, the Dynamic Island and Shortcuts (6 Nov 2026)

What was built from `docs/RESEARCH-ISLAND-SHORTCUTS-WIDGETS.md`. Everything runs on the phone: no server changes, no APNs.

## The widget extension

- `app/ios/GlyfVoiceWidget` is attached to Runner again (`tools/xcodeproj-env.sh tools/add_voice_widget_target.rb`, idempotent; it also wires every file below).
- **Device builds:** the extension (`com.arpit.glyf.voicewidget`) needs its own provisioning profile, which Xcode can only make after Arpit accepts Apple's new Program License Agreement. Until then, build for the phone without it:
  1. `tools/xcodeproj-env.sh tools/detach_voice_widget.rb`
  2. Build and install as usual.
  3. `tools/xcodeproj-env.sh tools/add_voice_widget_target.rb` puts it back.
  Detached, the app still builds: Live Activity requests just show nothing, and Shortcuts still work (they live in Runner).

## Trade in flight (Live Activity)

- **Data:** `GlyfTradeAttributes` (`GlyfVoiceWidget/Shared/GlyfTradeAttributes.swift`, compiled into the app and the widget).
  - Fixed per trade: pair, kind, amount, trigger, chain, cancellable.
  - Changes as it goes: phase, the screen's words, wallet, link, order id.
- **Phases:**
  - Placing.
  - Waiting for Phantom or MetaMask.
  - Placed (a Flash order) or Confirmed (a swap or send).
  - Sent, still confirming.
  - Failed.
  The mapping from each `TradeOutcome` is pure (`GlyfTradeActivity`) and unit tested.
- **How it starts:** `TradeScreen._show` calls `TradeActivity.show` (`app/lib/evm/trade_activity.dart`) on every step. That goes over `so.glyf/bridge` as `liveActivity.update` to `Runner/TradeActivityHost.swift`, which starts the activity or updates it. While the trade is in flight the app holds `beginBackgroundTask`, so the step after the wallet hand-off still lands.
- **How it ends:**
  - Confirmed: stays 15 min.
  - Failed: 5 min.
  - Sent: 30 min.
  - A placed Flash order stays until cancelled or until iOS's 8 h run out.
- **Views:** `GlyfVoiceWidget/GlyfTradeLiveActivity.swift`.
  - Compact: the g mark, and the status with a spinner while in flight.
  - Minimal.
  - Expanded: pair and kind, fact chips, a headline, then Cancel (EVM Flash only), Open, and the explorer.
  - Lock Screen: on black.
- **Cancel:** `CancelFlashOrderIntent` is a LiveActivityIntent, so it runs in the app. It opens `glyf://open?path=flash-cancel&id=…`. `main.dart` then shows the trade screen running `FlashCancel.steps`: the same cancel the order list uses (`lib/evm/flash_orders.dart`), signed by the wallet. The activity then says "Order cancelled". Flash on Solana has no cancel in Glyf yet, so its activity shows no Cancel.
- **Simulator:** `--glyf-demo-trade` (debug builds only) walks a Base stop-loss through every phase.

## Next meeting (Live Activity, experimental)

- **Data:** `GlyfMeetingAttributes`, plus `Runner/MeetingActivityHost.swift`.
- **Scheduling:** every time Glyf comes forward, the next event that has a call (Meet, Zoom, Teams, Webex or FaceTime; `CalendarSync` now stores the link as `meet`) is scheduled with iOS 26's `Activity.request(…, start:)`, 10 minutes before the event.
- **What it shows:** a countdown, then the time left, and Join.
- **Cleanup:** a moved or removed meeting's activity is ended.
- **Simulator:** `--glyf-demo-meeting` shows one at once.

## Widgets

Code is in `GlyfVoiceWidget/GlyfHomeWidgets.swift` and `GlyfWidgetStyle.swift`. The data is in `Shared/GlyfWidgetData.swift`, whose pure parts are unit tested.

| Widget | Sizes | What's in it |
|---|---|---|
| Watchlist | small, medium, Lock Screen rectangular and inline | BTC, ETH, SOL, AAPL (or settings `watchlist`) with price and 24 h change |
| Quick glyfs | small, medium | Meet link and Voice run in place; Wallet and Vault open Glyf |
| Next event | medium, Lock Screen rectangular | Next event, Join (opens the call) and New Meet link (made in place) |
| Glyf (all in one) | medium, large | Prices, the four buttons and the next event; large adds saved glyfs and runs left |

- **Prices:** fetched by the widget itself from Jupiter's keyless API, through the keyboard's `TokenLookup` (stocks via xStocks). They're kept in the App Group as `widget-prices.json` and refreshed every 15 min, and at an event's start and end.
- **Other data the widgets read:**
  - Calendar: `calendar.json`, `google-calendar.json` and `google-added.json`.
  - Settings: `settings.json`.
  - Runs left: `runs-remaining.json`.
- **What's never shown:** no vault data, keys or addresses.
- **Buttons:** New Meet link and Voice are LiveActivityIntents, so they run in the app's process, where the Google grant and the microphone live. A new Meet link is copied and shown on the widget for 30 min (`widget-meet.json`).
- **Look:** Glyf's ink and white with the violet dot, SF with tabular numbers, system backgrounds (light, dark, tinted, clear) and `widgetAccentable` on the marks and changes. Empty states are one line, placeholders are redacted samples, and every widget has `#Preview`s.
- **Refreshes:** the app reloads all widget timelines whenever it comes forward.

## Shortcuts (App Intents, in Runner)

`Runner/GlyfShortcuts.swift` is the app's one `AppShortcutsProvider`. The voice phrases moved here from `VoiceIntents.swift`. Every phrase names Glyf.

- **Rewrite Text** (text, style: Basic, Professional, Polite, Shorter or Emoji): POST `/act` with intent `rewrite` and the session from the shared keychain. Returns the chosen version. Runs without opening Glyf.
- **New Meet Link:** made on the phone with the Google grant (`GlyfMeetLink`, the same calls as the keyboard's `GoogleClient`). Copied and returned. Without Meet connected, it says to connect it.
- **Run Glyf** (`GlyfEntity`: saved glyfs from settings' `customTitles`, then built-ins): POST `/glyf/run`. Returns the text.
- **Open in Glyf** (Wallet, Ethereum wallet, Vault, Build your own, My glyfs): opens the app there.
- **Start Glyf Voice:** the existing `StartGlyfVoiceIntent`.

## Simulator notes

- **Shortcuts on the simulator:** Xcode signs simulator builds "Sign to Run Locally", with no team. linkd then refuses to run the app's intents ("Unable to run App Shortcut", "Unable to get teamId"). Re-signing the built app with the team's development certificate fixes it: `codesign --force --sign <Apple Development: … (YNABR226PF)>` on the frameworks, the appexes and then the app. Phones are unaffected, because device builds are always team-signed.
- **Reinstalls end Live Activities:** reinstalling the app (as every `xcodebuild test` run does) ends all of its Live Activities.

## Tests

- **iOS:** `app/ios/RunnerTests/GlyfWidgetDataTests.swift` covers:
  - trade attributes and phases;
  - the 4 KB limit;
  - prices and changes;
  - the next event and its call link;
  - quick and saved glyfs;
  - the rewrite and run parsers;
  - the meeting start.
- **Snapshots:** `app/ios/RunnerTests/GlyfWidgetSnapshots.swift` draws every widget in every size, light and dark. With `TEST_RUNNER_GLYF_SNAPSHOT_DIR=<dir>` set, it writes the PNGs to that folder.
- **Flutter:** `app/test/trade_activity_test.dart` covers the payload and that `show` never throws.

## Left

- **Not built:**
  - A watcher for fills, so a placed order turns into Filled. That needs APNs and a worker.
  - Portfolio balances on the watchlist.
  - Open Flash orders on the large widget.
  - A Control Center New Meet link control.
  - A "Shortcut" glyf type on the keyboard.
- **Waiting on Arpit:** the widget's device profile, which needs the PLA accepted.

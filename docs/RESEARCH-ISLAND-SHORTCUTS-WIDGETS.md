# Dynamic Island, Shortcuts and widgets for Glyf (research, 6 Nov 2026)

These are plans only; nothing here is built yet. The targets are iOS 26 and the existing widget target `app/ios/GlyfVoiceWidget`, which is detached for now and can be re-attached with `tools/add_voice_widget_target.rb`.

## Hard limits that shape everything

- **The keyboard can't start a Live Activity or run an App Intent.** Only three things can:
  - the app, in the foreground;
  - a `LiveActivityIntent` running in the app's process (a Control Center control, Siri, the Action button);
  - our server, with APNs push-to-start.
- **A Live Activity has no network access when it draws.** It holds at most 4 KB of data, and runs for up to 8 h, plus 4 h more on the Lock Screen. Buttons run App Intents.
- **Updates while the app is closed need APNs.** That means an APNs auth key (`.p8`, created under Keys on developer.apple.com), the Push Notifications capability on the App ID, and `aps-environment` in `Runner.entitlements`. The App Store Connect API key in `tools/appstore` can't send pushes.
- **Anything that watches prices, fills or payments needs a long-running worker.** Vercel Hobby only runs cron jobs daily, so this needs Pro or a separate worker. Arpit decides the host.
- **A keyboard can't turn on the torch, change Focus or Wi-Fi, or use the camera.** Neither can any app, through public APIs. A keyboard key can still run one of the user's own Shortcuts, through `shortcuts://x-callback-url/run-shortcut?name=…`, at the cost of a visible jump to Shortcuts and back.
- **App Review (guideline 4.5.3):** Live Activities must be real tasks: no promotion, no streaks, nothing sensitive on the Lock Screen.

## Dynamic Island: ideas, ranked

| # | What | Starts from | Server push? |
|---|---|---|---|
| 1 | Trade in flight: "Placing stop-loss…" → Placed → Confirmed, with Cancel and the tx link | App, at signing | No (later fills: yes) |
| 2 | Signing hand-off: "Waiting for Phantom…", tap to return | App | No |
| 3 | TWAP/DCA progress ring "4/10", average price, Pause/Cancel | App | Yes (a watcher) |
| 4 | Next meeting countdown + Join Meet | iOS 26 scheduled activity | No |
| 5 | Voice dictation listening | Already built (`GlyfVoiceWidget`) | No |
| 6 | Keyboard setup guide while you're in Settings ("Step 2/3: Allow Full Access") | App | No |
| 7 | Timer from what you type ("call mom in 20 min", "leave at 6"), +5 min / Done | Keyboard chip → push-to-start | Push-to-start only |
| 8 | AI glyf finishing while you switch apps: result, Copy | Keyboard → push-to-start | Yes |
| 9 | Pay request waiting → Paid | App | Yes (a chain watcher) |
| 10 | Price alert ("ETH below X") | Push-to-start | Yes (a watcher) |
| 11 | Ticker for money-chip assets | App, broadcast channel | Yes |
| 12 | Leave-by countdown from a shared Maps place | App | No |
| 13 | Copied password: "clears in 0:58 · Clear now" (no content shown) | Keyboard → push-to-start | Yes |
| 14 | Cal.com booking made: "Alex booked Thu 3 PM" | App | Yes (webhook) |
| 15 | "3 people copied your trade" | App | Yes |
| 16 | Translate session | Like #5 | No |

Not possible, or not worth it:
- A Meet call in progress: Glyf can't see Meet's call state.
- Game scores, streaks, quota nags: these read as promotion under guideline 4.5.3.
- Temp-mail codes: the code would have to pass through our server, and the keyboard already shows it.

## iPhone Shortcuts

- **Glyfs as Shortcuts actions** (App Intents + `AppShortcutsProvider`), in Siri, Spotlight, the Action button and Control Center:
  - Rewrite text, which chains Clipboard → Rewrite → Copy.
  - New Meet link.
  - Portfolio value.
  - Open orders.
  - Place stop-loss (always confirmed and authenticated).
  - Temp-mail code.
  - Start voice (exists).
- **Glyfs people build themselves:** a `GlyfEntity` read from the App Group, plus `RunGlyfIntent(glyf:)`, gives "Run ⟨glyf⟩ in Glyf". The same entity drives a configurable widget and control.
- **A "Shortcut" glyf type on the keyboard:** you name one of your own shortcuts (Torch, Focus…). The key runs it through x-callback-url and comes back to the app you were in, for the 29 host apps Glyf already knows.

## Widgets: ideas, ranked

1. **Watchlist and portfolio** (small, medium, Lock Screen).
2. **Open Flash orders**, showing status and distance to the trigger.
3. **Quick glyfs:** four buttons that run in the background and copy the result.
4. **Next event**, with Join Meet and New Meet link.
5. **Control Center control:** New Meet link.
6. **Control Center control:** Run ⟨picked glyf⟩.
7. **Rewrite clipboard:** one tap.
8. **Temp-mail code**, with a Copy button.
9. **Voice start** (exists).
10. **Last trade**, with a Share button.
11. **0G Private AI status and receipts.**
12. **Vault quick copy:** shows names only, needs authentication, and is never on the Lock Screen.
13. **Runs left this week.**
14. **Snake best score.**

**The all-in-one Glyf widget:**
- **Medium:** portfolio and 24 h change on the left, four glyf buttons on the right, and the next event with Join along the bottom.
- **Large:** adds two Flash order rows, New Meet link, the temp-mail code with Copy, and a footer with voice, the 0G receipt count and runs left.
- **What works in place:** refresh, glyf runs, Meet link, Copy code, voice.
- **What opens the app:** trades, cancels, the vault and games.

## Suggested order and effort

| When | What | Effort |
|---|---|---|
| Now | Trade in flight (Island #1 + #2), app-driven, no server | 3–5 h |
| Next | Voice re-attached, the setup guide, meeting countdowns | ~1 day |
| Next | Watchlist widget, New Meet link control, Rewrite intent + App Shortcuts | 1–1.5 days |
| Then | GlyfEntity / Run glyf intent / Quick glyfs widget | ~2 days |
| Then | All-in-one widget | ~2 days |
| Then | Shortcut glyf type on the keyboard | ~1 day |
| Then | APNs foundation + push-to-start (timers, AI runs, password clear) | 1.5–2 days |
| Last | Watchers for fills, DCA, price alerts, pay requests | 1–2 days + a hosting decision |

## Sources

- **Live Activities:**
  - [Displaying live data](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)
  - [ActivityKit push](https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications)
  - [Scheduled start](https://developer.apple.com/documentation/activitykit/activity/request(attributes:content:pushtype:style:alertconfiguration:start:))
  - [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/live-activities)
  - [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- **App Intents:**
  - [supportedModes](https://developer.apple.com/documentation/appintents/appintent/supportedmodes)
  - [WWDC25 App Intents](https://developer.apple.com/videos/play/wwdc2025/275/)
  - [AppShortcutsProvider](https://developer.apple.com/documentation/appintents/appshortcutsprovider)
  - [Dynamic phrases (forums)](https://developer.apple.com/forums/thread/773827)
- **Widgets:**
  - [WWDC25 What's new in widgets](https://developer.apple.com/videos/play/wwdc2025/278)
  - [Keeping a widget up to date](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date)
- **Shortcuts:** [x-callback-url](https://support.apple.com/guide/shortcuts/apdcd7f20a6f/ios)
- **Hosting:** [Vercel cron limits](https://vercel.com/docs/cron-jobs/usage-and-pricing)

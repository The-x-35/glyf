# What to improve in the app: an audit of 29 Oct 2026

An audit of the whole product, read-only. It covers:

- both keyboards (`app/ios/GlyfKeyboard`, `app/android/.../ime`);
- the Flutter app (`app/lib`);
- the server (`server/`, live on Vercel at api.tryglyf.com);
- the site (`site/`);
- the docs in `docs/`.

No code, config or data was changed. The market-side companion is [RESEARCH-IMPROVEMENTS-MARKET.md](RESEARCH-IMPROVEMENTS-MARKET.md).

**What was read in production**, all reads:

- `GET /health`, `/auth/config`, `/telemetry/funnel` and `/wallet/fees` with a locally minted session;
- one `getLatestBlockhash` through `/wallet/rpc`;
- aggregate counts from Neon inside `READ ONLY` transactions: accounts, per-account events, usage rows, the KV table and the waitlist. No row contents or emails were read.
- Each request still ticks the server's own per-minute rate-limit counter (`glyf_usage`, kind `minute`); no request can avoid that.
- The OpenRouter key was checked against OpenRouter itself (`/api/v1/credits`, and a 5-token completion that was refused).

---

## What the production numbers say

**Who is in the database:**

- 28 accounts (18 iOS, 8 Android, 2 unknown), created 17 Sep to 20 Oct. One is the App Review account.
- 9 accounts are on Max, mostly from gift codes: `code_redeemed` by 7 accounts, and one sandbox `purchase_done`.
- 37 install IDs have ever sent telemetry.
- 22 waitlist emails, the last on 13 Oct.
- This is the founder, the QA harness and a few testers. App opens peaked at 100 to 228 a day during QA runs (24 Sep to 4 Oct) and have been 0 to 3 a day since 8 Oct. **No real-user funnel exists yet.**

**Onboarding funnel, per account** (distinct accounts in `glyf_events`; events only reach this table once someone is signed in):

| Step | Accounts | From the step before |
|---|---|---|
| Opened the app (`app_open`) | 24 | |
| Signed in (`onboarding_signed_in`) | 17 | 71% |
| Saw "meet" / "details" / "feel" | 19 / 19 / 19 | (includes replays) |
| Saw "setup" (Turn on Glyf) | 17 | 89% |
| Saw "tools" (Maps, Calendar, Meet) | 11 | **65%: the biggest drop** |
| Finished onboarding (`onboarding_complete`) | 12 | |
| Agreed to "What Glyf sends" (`ai_consent`) | 10 | 83% |
| Keyboard added (`funnel_keyboard_added`) | 1 | — |
| Keyboard opened (`funnel_keyboard_opened`) | 1 | — |
| Full Access on (`funnel_full_access`) | 1 | — |
| First strip answer (`funnel_first_answer`) | 0 | — |
| First AI run (`funnel_first_ai`) | 0 | — |

**Reading:**

- From app open to onboarding done, half the accounts finish (24 → 12).
- One step in three is lost at "Turn on Glyf" (17 → 11), the screen that sends people to Settings.
- The keyboard half of the funnel has no data. The counters were added on 14 Oct and no tester build since has them; the one device that reported is the founder's, on 28 Oct.

**AI use:**

- `glyf_usage` holds no `week` rows. Free runs count by the week and are kept 8 days, so **no free account ran AI in the last 8 days**.
- Three paid accounts (Max) used 208 runs on 27 Oct and 272 on 28 Oct (UTC days), most likely QA.

**The anonymous `/telemetry/funnel` counts by day** (all time):

- `onboarding_signed_in` 38;
- `onboarding_complete` 15;
- `paywall_shown` 22;
- `purchase_started` 5;
- `app_open` about 1,400.

These are counts by day and event name only. The server drops each event's properties, so this view can't say which onboarding step anyone was on (item 6).

---

## The top 20, ranked

Effort is S (a day or less), M (2 to 5 days) or L (more than a week). Impact is what it moves: activation, retention, revenue or trust.

### 1. Production AI may be down: the deployed OpenRouter key is rejected

- **Problem:**
  - OpenRouter refuses the key in `server/.env` with `401 "User not found."`, both on `/api/v1/credits` and on a chat completion.
  - `server/.env.vercel` holds the same key, and that file is where Vercel's variables came from (the deploy note of 21 Oct).
  - `/health` only says `hasOpenRouterKey: true`: the key is present, not that it works.
  - Every model chain is OpenRouter-only: `fastModels`, `smartModels` and `suggestModels` are all `qwen/…`, `google/gemini-2.5-flash-lite…` and `inclusionai/…` through OpenRouter.
  - The direct Gemini key does work (`200`), but no chain names a `gemini:` model, so nothing falls back to it.
  - If Vercel holds this key, then hold space, Rewrite, the Ask bar, suggestions and glyfs all fail. People see "Couldn't do that right now. Tap to retry." (`app/ios/GlyfKeyboard/Bridge/BackendClient.swift:542`).
- **Fix:**
  - Check the key on the OpenRouter dashboard, top up (OPEN-ITEMS B9), and put a working key in Vercel.
  - Make `/health` (or a private `/health/deep`) make a 1-token call per provider every few minutes and report `ok`/`failing`.
  - Add a last-resort `gemini:gemini-2.5-flash-lite` entry at the end of each chain, using the key that already works (paid Gemini, so its data terms match the privacy policy).
- **Effort:** S. **Impact:** retention, trust.

### 2. Testers don't have the app being built: ship a build

- **Problem:**
  - The newest tester builds are 1.0.0 (20) on TestFlight (8 Oct) and (21) for Play (12 Oct). `app/pubspec.yaml` is `1.0.0+21`.
  - Everything since is only on the founder's phone and the simulators:
    - the setup funnel counters;
    - the 14 Oct security fixes in the apps (release builds pin production, sensitive clipboard handling, password-field guards);
    - 29 themes, phrases, weather, sunrise;
    - Android flavors and Mobile Wallet Adapter.
  - App opens fell to 0 to 3 a day after 8 Oct.
- **Fix:** with Arpit's go-ahead and the build number he expects (no unasked uploads), archive build 22 for TestFlight's public link and the Play internal track. Then see items 6 and 17.
- **Effort:** S. **Impact:** activation (measurement), trust.

### 3. No account deletion inside the app: App Store and Play blocker

- **Problem:**
  - `app/lib/profile/profile_tab.dart:573` says there is no Delete account in the app (removed 29 Sep: "we dont want users to go idiot").
  - App Store Guideline 5.1.1(v) requires in-app deletion for any app that creates accounts, and Glyf creates one at the first screen.
  - Play requires an in-app path too (docs/PLAY-STORE.md, decision 2). The web page `/delete-account` alone isn't enough.
  - `Auth.deleteAccount()` (`app/lib/core/auth.dart:253`) and `DELETE /me` still exist.
  - The server deletion also leaves device-keyed data and `glyf_purchases` behind (SECURITY-AUDIT S8).
- **Fix:**
  - Add a quiet "Delete account" row at the bottom of Profile, with a confirm sheet, calling `Auth.deleteAccount()`.
  - On the server, delete device-keyed rows (connections, glyfs, installs, telemetry devices) with the account.
- **Effort:** S. **Impact:** trust (launch blocker).

### 4. The App Review build must be able to sell, and the paywall must appear at the right moments

- **Problem:**
  - `Billing.onSale = false` (`app/lib/core/billing.dart:38`): the paywall greys out Plus and Max and says "Plans open soon".
  - The four subscriptions are Ready to Submit and must go with version 1.0. A reviewer who can't buy them rejects under 2.1 (incomplete in-app purchase).
  - The only ways into the paywall are a Profile card (`profile_tab.dart:235`) and the Builder's cap (`build/builder_screen.dart:120`).
  - There is none at the end of onboarding, which GO-TO-MARKET 4.2 recommends, and none when the free runs run out in the keyboard.
- **Fix:**
  - Turn `onSale` on in the review build only (a `--dart-define`, so TestFlight sandbox builds stay greyed out). Arpit's OK is needed.
  - Show the paywall once after setup is done.
  - Give the keyboard's out-of-runs message a "Get more in Glyf" action (item 8).
- **Effort:** S. **Impact:** revenue.

### 5. When the API is down, new people can't get in at all

- **Problem:**
  - Sign-in is step 1 and the only way past it. `main.dart` sets `_onboarded = state['done'] == true && signedIn`.
  - Sign-in posts to `/auth/session`. When the server is down, people see "Sign-in could not be verified. Try again." (`auth.dart:185`). That reads like a problem with their Apple or Google account.
  - When Railway lapsed (before the 21 Oct move to Vercel):
    - every new install dead-ended on the first screen;
    - AI showed "Couldn't reach Glyf. Tap to retry." with no hint that the on-phone answers still work;
    - no alert reached anyone, because nothing watches the API.
  - Guideline 5.1.1(v) also says an app without significant account-based features should work without a login. A keyboard's typing, strip and vault don't need an account.
- **Fix:**
  - Let onboarding continue without an account: keyboard setup, typing, the strip and the vault.
  - Ask for sign-in at the first AI use, or from a "Sign in for AI" row.
  - Tell a 5xx or non-JSON reply apart from a refused token: "Glyf is having trouble. Try again in a few minutes."
  - Show a keyboard state, "AI is offline; answers on your phone still work", after two failures in a row.
  - Add a free uptime monitor on `/health` that emails Arpit.
- **Effort:** M. **Impact:** activation, trust.

### 6. The funnel can't answer the questions it was built for

- **Problem:**
  - **Properties are dropped.** `server/src/routes/telemetry.ts` counts `day:event` and throws away every property. "Which onboarding step did they leave on" is lost anonymously; it survives only in `glyf_events` for signed-in accounts.
  - **No unique devices.** Counts are per day, not per device, so no conversion rate can be computed from `/telemetry/funnel`.
  - **Keyboard milestones wait for the app.** `first_answer`, `first_ai` and `full_access` only travel when the app is opened again (`Funnel.report()` runs only in `main.dart:101,123`). Someone who sets up the keyboard and never reopens the app is never counted.
  - **Events can be lost.** Telemetry is throttled to one flush every 15 s and the queue is in memory (`core/telemetry.dart`). The moment people leave for Settings (the setup step) is when events are most likely to be lost.
  - **Android is missing a milestone.** It never marks `first_ai`; there are only `first_answer` marks in `GlyfIME.kt:2965,3068`.
  - **Wrong days and lost counts.** Counts land on the day the server receives them, not the event's `ts`. Two Vercel instances can each read, add one and write back, losing an increment (BACKEND.md 20.10 #3).
  - **Anyone can read it.** Any signed-in account can read the company's funnel.
- **Fix:**
  - Build `/telemetry/funnel` from `glyf_events`: distinct accounts per step, in order, by signup week, with D1, D7 and D30 from `app_open`.
  - Keep a step property on the anonymous counts: count `event:step`.
  - Flush telemetry when the app goes to the background.
  - Have the keyboard send its milestones itself when Full Access is on (counts only, `POST /telemetry`).
  - Add `first_ai` on Android.
  - Limit the endpoint to an admin account.
- **Effort:** M. **Impact:** activation (you can't fix what you can't see).

### 7. Onboarding asks for a lot before the keyboard does anything

- **Problem:** the flow is `_steps = ['signin', 'meet', 'details', 'feel', 'setup', 'tools']` (`app/lib/onboarding/onboarding_flow.dart:60`). Step by step:

  | Step | What it asks | Friction |
  |---|---|---|
  | 1 signin | Apple or Google, no skip | Google on iOS asks for the Calendar and Meet scopes right here (`SignIn.swift:57`, `askCalendarAtSignIn = true`). Google then shows its "unverified app" warning and stops after 100 people (item 10). A server outage blocks this step (item 5) |
  | 2 meet | "Let me remember you", one button | An extra tap before anything useful |
  | 3 details | Name, email, phone, home address (more under More) | Personal data before any value. It has Skip, but asking for an address on screen 3 costs trust |
  | 4 feel | Key sounds, keep what you copy, recent screenshots | The screenshots switch asks for the photo library. These are settings, not onboarding |
  | 5 setup | Add the keyboard in Settings; on iPhone Full Access; on Android the picker | People leave the app here. 17 → 11 accounts reach the next step. The relaunch after Full Access is handled ("Welcome back") |
  | 6 tools | Nearby (location), Calendar (EventKit), Google Meet (OAuth) | Up to three more system prompts and the unverified Google screen |
  | then | "What Glyf sends" sheet on first open, Home with a floating "Take a tour" | Another modal before typing anything real |

  Only step 5 has a practice box. The first real win (a strip answer) comes after six screens.

- **Fix:**
  - Order: sign-in (or skip, item 5) → setup with the practice box → a forced first win in that box ("split $84 four ways", "10 inches in cm", which needs no network) → done.
  - Move details, feel and tools to Home cards ("Save your address for one-tap forms", "Connect Calendar").
  - Ask each permission at first use: location on the first "near me", Calendar on the first plan chip.
  - Fold the consent sheet into the AI moment.
- **Effort:** M. **Impact:** activation.

### 8. Out-of-runs messages are wrong for Free and lead nowhere

- **Problem:**
  - Free is 50 runs a week (`server/src/lib/limits.ts:29`). Elsewhere the copy still talks about days:
    - the iOS keyboard's 429 fallback says "Daily free runs used up" (`BackendClient.swift:681`);
    - the paywall's cap header says "You're out of runs today… They come back tomorrow." (`paywall_sheet.dart:202,208`);
    - the paywall doesn't say what Free includes.
  - The server's own message is right ("This week's free runs are used up. They come back Monday"), but no keyboard offers an upgrade from it.
  - Android has no runs chip at all. Searching for `runsRemaining` finds 0 files on Android and 4 on iOS.
- **Fix:**
  - Make the copy follow `runsPeriod` (`GlyfCatalog.runsRemainingText` already knows it).
  - Add a "More runs in Glyf" button to the refusal on both keyboards, opening the paywall with `reason: 'cap'`.
  - Port the runs chip to Android.
- **Effort:** S. **Impact:** revenue.

### 9. Android can't take payment: Play Billing is a dependency with no code

- **Problem:**
  - `app/android/app/build.gradle.kts:124` adds `billing-ktx:9.1.0` to the play flavor, but no Kotlin uses `BillingClient`.
  - `Billing.available` is `onSale && Platform.isIOS`.
  - The server has `/billing/apple` only.
  - 8 of 28 accounts are Android.
- **Fix:**
  - A `BillingClient` bridge in the play flavor: products, purchase, acknowledge, restore.
  - `POST /billing/google` verifying with the Play Developer API (a service-account variable).
  - Real-time developer notifications (RTDN) through Pub/Sub for renewals.
  - The same product IDs as iOS.
- **Effort:** L. **Impact:** revenue.

### 10. Google sign-in asks for sensitive scopes on the first screen

- **Problem:**
  - On iOS, Google sign-in asks for `calendar.events.owned` and `meetings.space.created` at once (`SignIn.swift:57-61`).
  - Until Google verifies them (OPEN-ITEMS B12; the brand review is still owed a video and a reply), everyone sees "Google hasn't verified this app", and sign-in stops after 100 new users.
  - Of the 3 accounts with `onboarding_google_meet`, all are founder or QA.
- **Fix:**
  - Set `askCalendarAtSignIn = false`. The code's own comment says false asks only in Connected tools, so sign-in becomes `openid email profile`, which Google doesn't review.
  - Ask for Calendar and Meet when they are first used, while verification goes through.
  - Check that Android asks only for the ID token at sign-in.
- **Effort:** S. **Impact:** activation, trust.

### 11. Crashes and keyboard kills are invisible

- **Problem:**
  - None of the app, the keyboards or the server has crash reporting. Searching for Sentry, Crashlytics, MetricKit and `MXMetricManager` finds nothing.
  - On iOS, a keyboard killed for memory or a watchdog just vanishes for the user and is never seen by Glyf.
  - `MemoryLogger` (`app/ios/GlyfKeyboard/MemoryLogger.swift`) writes to the device log only.
- **Fix:**
  - MetricKit in the app and the extension: `MXCrashDiagnostic`, `MXAppExitMetric` (memory-limit and watchdog exits) and launch-time histograms, sent as counts and signatures, no text.
  - `ApplicationExitInfo` on Android.
  - Both are free and first-party: no new provider.
- **Effort:** S to M. **Impact:** retention, trust.

### 12. Typos typed in some fields teach autocorrect to leave them alone

- **Problem:**
  - In `GlyfKeyboardViewController.swift:1645`, a field with `autocorrectionType == .no`, a `.webSearch` or `.twitter` keyboard, or Glyf's own autocorrect switched off, loses autocorrect but keeps learning.
  - `PersonalLexicon.isKnown` says a word typed twice is "never autocorrected away again" (`Engine/Typing/PersonalLexicon.swift:92-95`).
  - So "teh" typed twice into Safari's search bar is never fixed in Messages again.
  - The simulators' `typing-memory.json` files hold learned misspellings like "thier" (typed 3 times) and "recieve".
  - Android has the same gap only when Glyf's autocorrect setting is off (`GlyfIME.kt` `typingPolicy`).
- **Fix:**
  - Words committed with autocorrect off count only as `seen`, not `total`, for `isKnown`.
  - Or require one deliberate keep (an undo of a correction, or tapping the typed word).
  - Prune known words that are one edit from a much more common word and were never kept.
- **Effort:** S. **Impact:** retention.

### 13. Server time per request and cold starts on Vercel

- **Problem:**
  - Warm `GET /health` takes 210 to 330 ms from India (edge `bom1`, function `sin1`).
  - Before any handler, each signed-in request makes at least 3 Neon HTTP round trips one after another:
    - `kv.refresh()`;
    - the per-IP limiter;
    - the per-user limiter (`server/src/lib/protect.ts:81-108`, `src/index.ts:75`).
  - AI routes add the plan lookup, the burst count and the window count (`lib/guard.ts`, `lib/limits.ts`).
  - A cold instance also runs every `create table if not exists` and loads the whole `glyf_kv` table: 388 rows and 264 kB today; BACKEND.md 20.9 says this is the first thing to revisit.
  - `/suggest` runs on a pause in typing, so this overhead shows up as strip lag.
  - A cold start was never caught: the instance stayed warm across this audit.
- **Fix:**
  - Add a `Server-Timing` header (db, model, total) and log it.
  - Run the two limiter upserts in parallel, or in one statement.
  - Cache the plan for 60 s per instance.
  - Move the DDL to a one-time migration.
  - Skip `kv.refresh()` on routes that never read the KV: `/suggest`, `/act`, `/translate`, `/rates`.
  - Load the KV per collection.
- **Effort:** M. **Impact:** retention.

### 14. Vercel Hobby's limits are close to what Glyf needs

- **Problem:**
  - Hobby allows 1M invocations and 4 h of active CPU a month.
  - At about 100 suggestion requests per active user a day (the free cap is 100 model reads, and requests are more), 330 daily users reach 1M a month.
  - Hobby's terms are also non-commercial. That doesn't matter until plans are on sale, and matters on the day they are.
- **Fix:** decide the host before `onSale` goes true: Vercel Pro ($20), or Railway, Koyeb or Fly (BACKEND.md lists them). The Vercel adapter and the Node start both already work.
- **Effort:** S (decision) to M (move). **Impact:** revenue, trust.

### 15. Security items open since 14 Oct

These are from SECURITY-AUDIT.md, still open in the code.

- **F1, pay deep links.** Any web page can open `glyf://open?path=pay?kind=send&to=…&amount=…`. With the wallet on, Glyf builds the transaction and opens Phantom with no review step in Glyf (`app/lib/main.dart:145-158`, `wallet/pay_launch_screen.dart`). The wallet is off by default, which limits who is exposed.
- **S5, S6, S8, accounts:**
  - `deviceId` still works as the password for glyfs, installs and OAuth connections;
  - sessions last 180 days and can't be revoked;
  - deleting an account leaves device data behind.
- **S7:** OAuth tokens are stored unencrypted.
- **Fix, in order:**
  1. a "Review and pay" step plus a one-time nonce;
  2. a per-user token version, checked in `verifySession`;
  3. key device data by `req.glyfUser`;
  4. encrypt `connections` with a key in a new variable.
- **Effort:** M. **Impact:** trust.

### 16. Keyboard memory hasn't been measured on a device since September

- **Problem:**
  - The only device-class number is M0's 21.5 MB on first appearance (docs/M0-GATE.md).
  - The simulators' `keyboard-ping.json` files show 20.7, 26.6 and 27.5 MB (16 to 20 Oct, appearances 1 to 2), under the 45 MB guard and Apple's roughly 60 MB limit.
  - Since then the keyboard has gained:
    - 29 themes with up to 1.3 MB of fonts and 600 kB of PNG tiles (fonts are registered one theme at a time, `Design/KeyboardTheme.swift:207`);
    - pattern colours cached per theme (`Design/KeyFaces.swift:36`);
    - the glide index;
    - emoji, GIF and sticker grids;
    - the Pay panel.
  - Good: the dictionary is memory-mapped (`TypingStore.swift:48`, `GlydTrie.mapped`).
  - SPIKES.md saw growth to about 40 MB over repeated presentations.
- **Fix:**
  - On a real iPhone, a scripted pass that takes `GLYF_MEM` for each surface: emoji to GIFs, theme switch × 10, Pay, Search, after 20 presentations.
  - Record the numbers in APPS.md.
  - Clear the pattern and thumbnail caches on hide.
  - Item 11's `MXAppExitMetric` then catches real memory kills.
- **Effort:** S. **Impact:** retention.

### 17. The waitlist and the public TestFlight link were never joined up

- **Problem:**
  - 22 people joined the waitlist (15 Sep to 13 Oct).
  - TestFlight's external group has a public link (the store-launch notes of 2 Oct).
  - The site still shows "Coming soon on" badges only (`site/app/page.tsx:26-37`), and nobody on the list was invited.
- **Fix:**
  - Once build 22 is out (item 2), email the 22 people the TestFlight link and Play's testing link.
  - Swap the iPhone badge for "Join the beta".
  - Those testers also count toward Play's 12-tester closed test (founder decision 9).
- **Effort:** S. **Impact:** activation.

### 18. Built but unreachable, dead code, and stale docs

- **The Skills hub has no screen.**
  - The server has `/hub/list`, `/hub/publish`, `/hub/install`, `/skills`, `/skills/creators` and `/account/:deviceId/creator` (`server/src/routes/hub.ts`).
  - The Dart client has `hubPublish`, `skills`, `skillCreators`, `skillGet` and `creatorStats` (`app/lib/core/glyf_api.dart:222-260`), with 0 callers.
  - The screen went in "A simpler app" (17 Sep).
  - These routes are also part of S5's `deviceId` exposure.
- **Dead iOS code.** `Surfaces/ClipContextStrip.swift` is never instantiated (OPEN-ITEMS N7).
- **Stale docs.**
  - The APPS.md 6 parity table still lists Android with no delete repeat, accents or multi-touch, but `GlyfKeyboardView.kt` has all three (`DELETE_REPEAT_DELAY_MS`, the accent popup, `ACTION_POINTER_DOWN`).
  - OPEN-ITEMS says "Last updated 27 Sep". Its section 7 Android catch-up list is done in code (`cityTime`, `untilTime`, `listMaker`, `pollMaker`, `asksToBook`, `asksToCall`, `cityState` and `seedOwnNames` all exist in the Kotlin).
  - B1, B16 and C11 describe Railway; `SOLANA_RPC_URL` now works on Vercel (`/wallet/rpc` answered).
- **Fix:**
  - Either bring skills back as share links (a growth loop; GO-TO-MARKET 3.4) or delete the hub routes and client methods.
  - Delete `ClipContextStrip.swift`.
  - Refresh the parity table and OPEN-ITEMS against the code.
- **Effort:** S (clean-up) or M (share links). **Impact:** trust (docs); activation if share links come back.

### 19. Android parity still owed

- **Problem:**
  - Android has no runs chip (item 8) and no `first_ai` mark (item 6).
  - Its vault has no images (`store/VaultStore.kt`; iOS keeps pictures).
  - Its keyboard ping always reports `hasFullAccess: true`.
  - Recent screenshots on Android need `READ_MEDIA_IMAGES`, which Play allows only with a declaration (PLAY-STORE.md decision 3).
- **Fix:**
  - Port the chip and the mark.
  - Decide on screenshots before the first production Play release. Dropping the permission is the safe choice.
  - Leave vault images for later.
- **Effort:** S to M. **Impact:** retention.

### 20. Test hooks and logs in release builds

- **Problem:**
  - Release builds still honour iOS launch arguments outside `#if DEBUG`: `--glyf-skip-onboarding`, `--glyf-seed-vault`, `--glyf-reset-typing`, `--glyf-seed-calendar` and others (`app/ios/Runner/AppDelegate.swift:12-145`; SECURITY-AUDIT I6).
  - Android release builds keep `Log` calls.
  - `GET /search/suggest` puts `deviceId`, latitude and longitude in the query string, on both platforms (`BackendClient.swift` `runSuggest`; Android A8).
- **Fix:**
  - Wrap the hooks in `#if DEBUG` (the QA harness runs Debug).
  - Strip `Log.d/i/v` with R8 rules.
  - Move location and the device ID into headers or a POST body.
- **Effort:** S. **Impact:** trust.

---

## Founder decisions still owed

Grouped; each one names where it comes from.

**Launch and App Review**

1. **Submit v1.0 with the four subscriptions.** When, and which build. Also: `onSale` on for the review build (item 4), with `REVIEW_MODE=true` and `REVIEW_PASSWORD` set on Vercel during review (OPEN-ITEMS B17; `/auth/config` shows `review: false` today).
2. **Bring Delete account back in the app.** Apple and Play require it (item 3). The 29 Sep removal was Arpit's call.
3. **Let people use the keyboard before signing in** (item 5, Guideline 5.1.1(v)).
4. **Which Apple account publishes 1.0, and is it an organization?** If it's individual, the wallet can't ship on iOS (3.1.5(i)) and must be hidden in the iOS 1.0 build (GO-TO-MARKET 7.2, decision 4).
5. **Keyboard opening the Glyf app** (Pay, dictation): accept the 4.4.1 risk with review notes, or ship "Open Glyf to finish" with a copied link (GO-TO-MARKET 7.1).
6. **Google OAuth:** publish the app and finish verifying the Calendar and Meet scopes (video and reply owed, B12), or ask for them only in Connected tools (item 10).

**Money**

7. **Hosting before charging:** Vercel Pro or another host (item 14).
8. **OpenRouter:** working key and credit (item 1, B9).
9. **Google Play:**
   - developer account type: personal (a closed test with 12 testers for 14 days) or organization (a D-U-N-S number);
   - the go-ahead to build Play Billing (item 9);
   - wallet and tokenized stocks on Play;
   - `READ_MEDIA_IMAGES` (PLAY-STORE.md decisions 3 to 5).
10. **Prices:**
    - the founding price now and a $4/$40 and $8/$80 test in month 2 (GO-TO-MARKET decision 1);
    - yearly at 10x monthly sits below Apple's equalized price in 78 storefronts. Keep it, or never go below Apple (the store-launch notes of 2 Oct, unanswered).
11. **Fees and wallets:**
    - the Jupiter referral account address, since the swap fee constants are empty (SWAP-FEE.md);
    - `GLYF_FEE_WALLET`: private-payment fees go to Arpit's personal wallet until it is set (commit ad49ce0);
    - `GLYF_TREASURY` for USDC plans.
12. **Growth:**
    - referral rewards through Apple offer codes;
    - student codes;
    - the Product Hunt date and the 20 people;
    - a Teams pilot in month 3 (GO-TO-MARKET decisions 6 to 8).

**Security** (SECURITY-AUDIT.md "Needs Arpit")

13. **F1:** pay-link review step plus nonce.
14. **S5, S6, S8:** tie data to accounts, revocable sessions, delete device data with the account.
15. **S7:** encrypt OAuth tokens (a new variable).
16. **S16:** caps on the telemetry, device and install collections.
17. **S18:** vitest 2 to 5.
18. **Release test hooks (I6).**
19. **Backup choices:** the wallet secrets' keychain group (I8), the vault key's backup class (I9), backup exclusion for the App Group files (I10), Android backup scope and the temp-mail login (A3, A7), log stripping and location out of URLs (A8).
20. **S15** is likely moot on Vercel (Vercel sets `X-Forwarded-For` itself), but check once.
21. **Rotate the keys pasted in chat:** Neon (W1), OpenRouter, YouTube, and Privy (BACKEND.md §1168).

**Accounts and providers**

22. `KLIPY_APP_KEY` production access from KLIPY (B8).
23. **Solana dApp Store:** publisher wallet and KYC, the Superteam grant (SOLANA-DAPP-STORE.md).
24. **Phone moves** still awaiting a go-ahead: weather and sunrise as answers, keyless tools, skipping Neon on public read-only routes (SERVER-INVENTORY / OPEN-ITEMS 9, items 6 to 8).
25. **Real-device checks only Arpit can run:** keyboard memory (A4, item 16), Phantom signing v0 swaps (A10), EventKit from the keyboard (A13), Google on a real phone (A15), and screenshots of the long-Android-phone band.
26. **Builds:** each TestFlight or Play upload and build-number bump needs his say in the moment (item 2).

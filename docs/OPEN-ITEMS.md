# Open items

Everything pending, blocked or owed, in one place. **Owner** is who has to act: Arpit (accounts, keys, money, logins, design calls) or Build (code work). Area docs have more detail: [WEBSITE.md](WEBSITE.md), [APPS.md](APPS.md), [BACKEND.md](BACKEND.md).

Last updated: Sun 27 Sep 2026 (IST).

---

## 1. Launch the website

| # | Item | Owner |
|---|---|---|
| W1 | Rotate the Neon database password (it was pasted in chat twice). Update it in Vercel and `site/.env.local` | Arpit |
| W2 | ~~Deploy on Vercel with domains~~ **Done 16 Sep:** live on www.tryglyf.com, apex redirects to www | Arpit |
| W3 | ~~Point canonical and share URLs at www~~ **Done 16 Sep 03:18:** pushed to `main`, Vercel redeployed automatically (the project is connected to the GitHub repo), and the live page now uses `https://www.tryglyf.com` everywhere | Build |
| W4 | Sign up once on the live site and check the row lands in Neon. The live API answers (email checks verified), but the database connection wasn't tested, to avoid putting a test row into the real list | Arpit |
| W5 | Share the link somewhere (iMessage, WhatsApp, X, LinkedIn) to see the preview card. Tags and images are live and correct | Arpit |
| W6 | Brand use: MagicBlock, Solana, USDC (Circle), App Store and Google Play marks appear on the page. Check their guidelines or ask MagicBlock | Arpit |
| W7 | Replace the vault placeholders if wanted: UPI `arpit@okbank`, phone `+91 98765 43210` | Arpit |
| W8 | Decide whether Semi's 🙏 reaction on the payment card stays (only the emoji after "thank you" was removed) | Arpit |
| W9 | Arpit's message "and i think we can re…" (15 Sep, 23:34) was cut off and never clarified | Arpit |
| W10 | Visually re-check on a phone: dark mode, the Messages list screen, the header blur, and the hero after the nav and wordmark changes (checked by measurement while the preview pane was hidden) | Build |
| W11 | The waitlist rate limit is per server instance; add a shared limit if spam shows up | Build |

## 2. Backend deployment and keys

| # | Item | Owner |
|---|---|---|
| B1 | Deploy `server/` to a host and point `api.tryglyf.com` at it. Until then, release app builds and TestFlight testers have no AI | Arpit (host choice) + Build |
| B2 | Add `GEMINI_API_KEY` (aistudio.google.com/apikey) and `GROQ_API_KEY` (console.groq.com/keys) to `server/.env`. Free OpenRouter models are slow and often out of quota | Arpit |
| B3 | Add `GEOAPIFY_KEY` (free, no card) for Maps and nearby places | Arpit |
| B4 | Optional: `BRAVE_SEARCH_KEY` for real web result links (needs a "Powered by Brave" line) | Arpit |
| B5 | YouTube Data API key: add restrictions, file the quota extension early (default 100 searches a day), regenerate after deploy | Arpit |
| B6 | Google OAuth client (`GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET`) with redirect URIs for local and `https://api.tryglyf.com/oauth/google/callback` | Arpit |
| B7 | OAuth client pairs for Notion, Slack, GitHub, Linear, Todoist, Calendly, Zoom, Spotify (each lights up when its pair is in `server/.env`) | Arpit |
| B8 | `KLIPY_APP_KEY` on Railway. The key arrived on 2026-09-24 and is in the local `server/.env`; real KLIPY GIFs and stickers were checked end to end on both keyboards (iOS S102 to S105, Android S106 to S108). Still to do: set it on Railway, and request production access from KLIPY once "Search KLIPY" is live | Arpit |
| B9 | About $10 of OpenRouter credit. The strip's AI suggestions and hold space run on paid models through OpenRouter: since 2026-09-26 Qwen 3.7 Flash first, about $8 a million suggestions and $0.03 per 1,000 hold-space rewrites (was $20 to $30 and $0.15 on Gemini first); $10 lasts a long time. The key answered on 2026-09-25 with $0 credit, which won't last; without credit the chip shows only what the phone's rules catch and hold space falls back to Gemini's free tier (about 4 s) | Arpit |
| B15 | On Railway, add `KLIPY_APP_KEY` (GIFs). Nothing else to change there: since 2026-09-26 the model chains and daily caps are in code and the old `FAST_MODELS`, `SMART_MODELS` and `FREE_RUNS_PER_DAY` values are ignored (delete them whenever, for tidiness) | Arpit |
| B10 | Benchmark Hinglish quality on the chosen models with about 50 real messages once keys are in | Build |
| B11 | Gemini free tier terms: it trains on what's sent and excludes apps likely used by under-18s. Paying removes most of this | Arpit (decision) |
| B12 | Google Cloud, in the project that holds the sign-in clients (console.cloud.google.com, Google Auth Platform): **(1)** APIs & Services → Library: enable the **Google Calendar API** and the **Google Meet REST API**. **(2)** Data Access → Add or remove scopes: add `https://www.googleapis.com/auth/calendar.events.owned` and `https://www.googleapis.com/auth/meetings.space.created`. **(3)** Audience → Test users: add yourself and every tester while the app is in Testing (only they can sign in; up to 100; their grants expire after 7 days). **(4)** Clients → the iOS client: Bundle ID `com.arpit.glyf` (it was made for `com.demo.glyf`). **(5)** Branding: app name Glyf, support email, home page `https://www.tryglyf.com`, privacy policy `https://www.tryglyf.com/privacy` (live once pushed), authorized domain `tryglyf.com`. **(6)** Before the App Store build goes to real people: Audience → Publish app (In production), or anyone outside Test users is refused at Google sign-in; then Verification Center → verify the two sensitive scopes (tryglyf.com proven in Search Console, an unlisted YouTube video of Google sign-in, Connect Google Meet and a Meet link from the keyboard, a line on why each scope; Google says 3 to 5 business days). Until Google verifies them, Google sign-in shows its "unverified app" warning, because sign-in asks for Calendar and Meet, and stops after 100 new people. No server key or secret is needed: the phone talks to Google | Arpit |
| B14 | Calendly: open times and booking inside the keyboard need Calendly's OAuth app (the `CALENDLY_*` pair in B7) and the host's own sign-in; today a Calendly link is offered as its page on the chosen day | Arpit (if wanted) + Build |
| B16 | The wallet on Railway: add `SOLANA_RPC_URL` (the Helius URL in the local `server/.env`), then push so `/wallet/rpc` and `/rates/token` go live. Until then the phone's Send, balances and the recipient check fail, and every copied address shows Send (the token lookup isn't there) | Arpit |
| B17 | App Review credentials: on Railway add `REVIEW_PASSWORD` (the value is in the local `server/.env`, set once) and `REVIEW_MODE=true`, push, and upload a build with the reviewer door (27 Sep or later). ASC Sign-In Information: user name `review@tryglyf.com`, that password; notes: tap "App Review sign-in" under the Google button, enter the password; Glyf is a keyboard, enable it under Settings → General → Keyboard → Keyboards → Add New Keyboard → Glyf and allow Full Access. After approval flip `REVIEW_MODE` to `false` — the link disappears and the door shuts; the password stays for next time | Arpit |

## 3. Apps

| # | Item | Owner |
|---|---|---|
| A1 | Upload TestFlight build 3 (version 1.0.0, build 3, export compliance set). Build 2 is the last confirmed upload | Arpit |
| A2 | Purchases are built (26 Sep): StoreKit 2 in the app, Apple's signature checked on the server, no RevenueCat. **2 Oct:** the Paid Apps Agreement, bank and tax are Active and the Small Business Program application is in; prices are whole dollars; the "Glyf Pro" group and its four subscriptions (`com.arpit.glyf.plus.monthly` $2, `.plus.yearly` $20, `.max.monthly` $5, `.max.yearly` $50, whole prices in all 175 storefronts) were created through the App Store Connect API and are Ready to Submit, with App Store Server Notifications set (APPS.md 5.21). Left: submit them with app version 1.0 and a build from 2 Oct or later, then buy on TestFlight (sandbox). Steps: the Glyf Store Setup page (https://claude.ai/artifact/Ev2659pwAEPeKWa5rhQhQG) | Arpit |
| A3 | Google Play Console setup and a signed Android release build | Arpit + Build |
| A4 | Real-device checks the simulator can't do: the 45 MB keyboard memory budget, haptics, the real microphone for dictation, the ripple performance profile | Arpit (device) + Build |
| A5 | ~~Lock the final bundle IDs~~ **25 Sep:** the iPhone app moved to Arpit's own developer account as `com.arpit.glyf` / `com.arpit.glyf.keyboard`, App Group `group.com.arpit.glyf` (Android keeps `com.demo.glyf`). The signing team is still to pick: A16 | Arpit |
| A6 | App sign-up page backed by the Neon database, then onboarding, then incremental Google permission requests (Arpit's plan from 15 Sep) | Build |
| A7 | Light and dark mode in the apps (the site has it; the keyboard already follows the host) | Build |
| A8 | Android round 2: in-keyboard AI prompt bar and clipboard history parity, automated tests | Build |
| A9 | Emoji suggestions from AOSP's emoji list (downloaded, not wired) | Build |
| A10 | ~~M8 crypto (Privy wallet, Jupiter swaps, platform fee)~~ **27 Sep:** built as a Phantom wallet instead (Profile → Wallet; Send, Send privately, Buy; Send and Buy chips on both keyboards). Left: try it on a real iPhone with Phantom and a few dollars (after B16), and confirm Phantom signs Jupiter's versioned (v0) swaps over its deeplinks, which its docs don't promise. Rotate the old Privy secret at Privy | Arpit (device) + Build |
| A11 | Paper design port: the keyboard page and website page were unfinished when the Paper free plan's weekly MCP limit hit. Resume after the reset or on Paper Pro | Arpit (plan) + Build |
| A12 | Mobbin connector: authorize it if design references from Mobbin are wanted | Arpit |
| A13 | Check on a real iPhone that the keyboard can add an event (EventKit from the keyboard with Full Access on). It works on the iOS 26.5 simulator; if a device refuses, New Event falls back to asking the app | Arpit (device) + Build |
| A14 | Add your own Cal.com or Calendly link under Profile → Connected tools → Booking link to see Book a time on your page. The device tests used a stand-in for Cal.com, never a real person's calendar | Arpit |
| A15 | Once B12 is done, sign in with Google on a real iPhone and an Android phone (onboarding asks for Calendar and Meet), then try the camera, a New Event with an invitee, and a key bound to Meet link. The device tests used a stand-in for Google's APIs, never a real account | Arpit (device) + Build |
| A16 | App Store from your own account: in Xcode pick your team for Runner and GlyfKeyboard (`DEVELOPMENT_TEAM` is empty), which registers `com.arpit.glyf`, `com.arpit.glyf.keyboard` and `group.com.arpit.glyf`; create the App Store Connect record; push `main` so https://www.tryglyf.com/privacy is live and put it in the record's Privacy Policy URL; answer App Privacy to match that page. On Railway, `APPLE_BUNDLE_ID` must include `com.arpit.glyf` if it is set at all (unset means `com.arpit.glyf`) | Arpit |

## 4. Code problems found while writing the docs (not fixed yet)

Found by reading the code on 16 Sep. Nothing was changed, because that task was documentation only. Full lists: [BACKEND.md](BACKEND.md) section 16 (28 items) and [APPS.md](APPS.md) section 11 (21 items). The most important:

| # | Problem | Where | Owner |
|---|---|---|---|
| C1 | The CI secrets check scans zero files (a quoted file-type pattern matches nothing), so it always passes | `ci/check_no_secrets.sh` | Build |
| C2 | The AI run cache isn't per user and includes tool results, so a shared skill could show one person's calendar or Notion results to another within 24h | `server/src/routes/glyf.ts` | Build |
| C3 | `url.unfurl` fetches any address, including internal ones, once the server is public | `server/src/lib/tools.ts` | Build |
| C4 | No real accounts: the device ID works as a login for editing skills and connectors | server routes | Build (with the planned sign-up) |
| C5 | The paywall grants Plus or Max without payment, and the server trusts whatever plan the phone sends | app paywall + server meter | Build (with A2) |
| C6 | Test launch arguments, including one that writes the decrypted vault to disk, are not removed from release builds | iOS app | Build |
| C7 | Onboarding calls the Google permissions "Read-only", but the Calendar and Gmail scopes can write | Flutter onboarding | Build |
| C8 | The Android vault refuses 6 field types the app offers (name, GST, wallet, social, bio, reply) | Android vault store | Build |
| C9 | Android keyboard gaps versus iOS: no delete repeat, multi-touch, accents or caps lock; holding Translate, Vault or Calendar keys only opens the app | Android IME | Build |
| C10 | Web search tries Serper before Brave (the opposite of the 14 Sep decision), and "Connect your account first" errors reach users as "Tap to retry" | server search and run routes | Build |
| C11 | TestFlight builds 2 and 3 were likely built before the release server address existed, and the server isn't deployed, so testers probably have no AI | apps + B1 | Build + Arpit |

## 5. Repo and housekeeping

| # | Item | Owner |
|---|---|---|
| R1 | The gate recordings `docs/evidence/*.mp4` exist only on the dev Mac (too big for GitHub). Back them up somewhere (Git LFS, Drive) if they matter | Arpit |
| R2 | The stray Xcode template project in `/glyf` (its own git repo, unrelated to the app) can be deleted if not needed | Arpit |
| R3 | Re-run `python3 tools/make_og_image.py` whenever the hero copy or styles change | Build |

## 6. Open as of 22 Sep 2026

| # | Item | Owner |
|---|---|---|
| N1 | **Set Paste from Other Apps to Allow** (Settings → Glyf) on the test phone. Until then iOS asks once per copy, which is the only thing between the clipboard and filling itself. No app can write this setting | Arpit |
| N2 | **Turn on Recent screenshots** once (Glyf app → Keyboard). That tap is the only moment Glyf can ask for the photo library | Arpit |
| N3 | Confirm on a real device whether tapping "Allow Paste" on iOS's own banner also flips the per-app setting, or only allows that one read. The simulator cannot settle it | Arpit |
| N4 | Bump the build past 7 before the next TestFlight upload. Everything since build 7 (the whole toolbar and clipboard run) is unreleased | Build |
| N5 | About fifteen local commits are unpushed. Arpit pushes | Arpit |
| N6 | Android parity for this week's iOS work: the vault's images, the clipboard's categories and screenshots, and the toolbar's apps grid are iOS-only. Android has not been run since | Build |
| N7 | `Surfaces/ClipContextStrip.swift` is dead code (never instantiated) and its comment claims `UIPasteControl` is inert, which is wrong. Delete it | Build |
| N8 | The site has a pre-existing hydration mismatch in `BackdropKeys` (NaN transforms on first paint). It renders correctly after hydration but logs two console errors | Build |
| N9 | App strings still contain em dashes; only the site was cleaned (D88 era) | Build |

## 7. Android catch-up from the iOS pass of 7 Oct 2026

Arpit asked for the iPhone first ("focus on ios for now, we will do android later, keep noting down what u improved for android to catch up later"). Each of these is live on iOS and still to be mirrored in the Kotlin twins (Smart.kt, TypingEngine.kt, GlyfIME.kt), with the shared JSON cases extended only once both pass:

- Strip suggestions: the word being typed is never shown as a chip (no quoted literal); the fix in bold plus two more words, or three completions. A known word offers only its completions and its own apostrophe forms, never neighbours (`TypingEngine.suggestions`, the `known` filter).
- Emoji in the last slot while a chat word is typed and after it (`EmojiWords.swift` table → `EmojiWords.kt`; Suggestion kind `.emoji`; tap adds " 🎂 " after the word).
- Smart answers: both currencies named ("100 usd to inr", "$20 in euros"); an amount of a coin ("1 sol", "0.5 btc", with Buy; `Smart.coinAmount` and the keyboard asking RatesStore for that coin); sums in words ("half of 350", "double 25", "sqrt 81"); the time somewhere else ("what time is it in tokyo", "tokyo time" → `cityTime`); the wait till a clock time ("how long until 5pm" → `untilTime`); the list maker ("need: milk, eggs, bread" → • / 1. lines in place, `listMaker`).
- Also from the research pass: a poll from three or more options in a question (`pollMaker`), the person's own booking page when asked for a time (`asksToBook`, `ownBooking` on `Smart.chip`), "Add a Meet link" when a call is talked about (`asksToCall` + `.action(intent: "meet")`, only with Meet connected), city/state form boxes from the saved address (`cityState`, field kinds city/state/cityState), and the vault's own names kept as words in the engine (`seedOwnNames`).
- Dictionary: month abbreviations Jan…Dec as proper nouns in `supplement_en.combined` (en.glyd rebuilt; Android ships the same file, so only the Kotlin engine filter above is owed there).
- Glide typing: see section 8 when it lands.
- The 8 Oct batches (second probe, research pass, calories) are on Android too: the same answers in the same order in `Smart.quickAnswer`, the sign-off chip, the score-over-sum rule, the code-first paste piece and the not-a-plan question, with `SmartProbeTest` mirroring the iOS assertions.

## 8. Android catch-up: glide typing

Live on the iPhone keyboard since 7 Oct 2026 (Arpit: "implement glide typing, like glide over keyboard to type; its guesses needs to be perfect too, see how perfect glide typing is on iOS"). To port to the Kotlin keyboard:

- **Decoder** (`Engine/Typing/GlideDecoder.swift` → `GlideDecoder.kt`, pure logic). Shape writing (SHARK2) over the same `en.glyd`: an index of every word spelled with the 26 letters (letters, trie node, probability, bucketed by first and last letter; built once by walking the trie, ~50 ms, warmed in the background). Decode: resample the finger's path to 32 equidistant points in key widths; candidates are the buckets of letters within 1.4 key widths of the first and last point whose ideal path (the letters' centres, doubled letters collapsed) is within 2× of the gesture's length and which the finger passed within 1.9 key widths of in order (a 32-bit mask of near samples per key makes that a few bit ops a letter); rough score for all, then the best 120 are time-aligned (DTW, band 6) against the gesture. Cost = 2.4·aligned location (distance beyond 0.15 slack, mean) + 3·shape (both paths centred and scaled to a unit box, mean point distance) + 0.8·(start + end miss) + 0.25 per sharp gesture turn (>60°) near no letter of the word + |ln(length ratio)| + 3·(255 − f)/255, with a dwell ≥0.14 s inside one key worth −0.45 on a doubled letter there (+0.3 when the word has none, +0.08 for a doubled letter with no dwell). f is the dictionary probability lifted by the person's words, the previous word's bigrams and the triple with the word before (TypingEngine's followers/trigrams, `unseenPairMost` 25), an acronym ("DJ", "PST") counts 40 points rarer, and `keptAfter` keeps "feel ill" as ill. The shown form is the node's likeliest ("don't", "I'm", "I", "Monday"), capitalised when the board's shift is on (caps lock → all capitals). Tuned in `RunnerTests/GlideDecoderTests.swift` against the 500 likeliest words with a synthetic finger (σ 0.25 key-width jitter, one corner in five cut by a third, 3% noise, half the doubles held): 96.8% / 96.6% top-1 and 100% / 99.8% top-3 at 402 and 440 pt, decode median 0.3 ms optimised (p95 1.5 ms) and 25 ms in a debug build (the simulator keyboard, the tests), so the hot loops use raw buffers and bit masks on purpose. Port the generator too and hold the Kotlin decoder to the same numbers.
- **Keyboard** (`Layout/KeyboardView.swift`, `Layout/GlideTrail.swift` → `GlyfKeyboardView.kt`): a touch that lands on a letter of the letter layer and travels ≥0.7 key widths before the 320 ms hold fires becomes a glide (hold/accents/bound keys cancelled for that touch; the slide-off cancel does not apply to letters while glide typing is on). While gliding: a tapering ribbon in the accent colour (last 0.45 s of the path, 7 pt at the finger) and the key under the finger lit (fill only, no balloon); the top guess floats in a pill 62 pt above the finger, re-decoded every 90 ms. Space keeps its own gestures (cursor glide, hold for AI); no glide on symbol layers, digit pads, in-keyboard editors or secure fields; off with the setting.
- **On lift** (`GlyfKeyboardViewController.swift` glide block, `Engine/Typing/GlideTyping.swift`): a word being typed is committed first (autocorrect + learning, as the space bar would) and a space added; then the best guess + " " goes in, is learned (`commit`), shift releases, and the other guesses show in the strip as plain word chips while the caret stays right after the word (`GlideState.anchor` = text before the caret). Tapping one swaps the word. One backspace right after a glide deletes the word and its space and offers the word and its alternatives back; the next backspace is ordinary. No punctuation swallow of the glide's space (the typed flow has none either).
- **Setting**: `glideTyping` (Bool, default true) in the shared settings JSON; "Glide typing" switch under Typing in the keyboard's Settings panel and the app's Keyboard screen, title only.
- **Android: done (8 Oct 2026).** `ime/typing/GlideDecoder.kt` + `GlideTyping.kt` (constant-for-constant ports), `GlyfKeyboardView.kt` glide touch mode + trail + floating word, a `// Glide typing` block in `GlyfIME.kt` (lift, strip alternatives, swap, one-backspace undo), "Glide typing" switch under Number row in the keyboard's Settings, `glideTyping` default in `SettingsStore`. `GlideDecoderTest` (same synthetic finger, 500 likeliest words): top-1 96.4% / 97.0% / 96.8% / 97.2% and top-3 99.8% / 100% / 100% / 100% at 393 / 411 / 427 / 360 dp; JVM decode median 0.8 ms, p95 3–4 ms. One change beyond Swift: a glide shorter than 0.9 key widths with no one-letter word near it ("we" cut short) now falls through to the full search instead of returning nothing; the Swift decoder still returns nothing there. One other difference: a glide right after "," "." etc. adds the space first ("hello, world"). Checked on the Avici_API_36 emulator: hello, thanks and tomorrow glide in, the trail, lit key and floating word draw, alternatives swap the word, and one backspace takes it back and re-offers it.

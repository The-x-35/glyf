# Timeline

What happened each day, in order. Times are IST. For the reasons behind each change see [DECISIONS.md](DECISIONS.md); for Arpit's exact words see [history/messages-from-arpit.md](history/messages-from-arpit.md).

The work ran in three chat sessions:
- **Session A:** Fri 11 Sep 18:56 to Tue 15 Sep about 15:30. It built the apps, the backend and the website up to v7.
- **Session B:** the continuation of A, Tue 15 Sep to now. It covers the website launch work, the GitHub repo and these docs.
- **Session C:** a short side chat on Sat 12 Sep, 20:29 to 21:05, about App Store capabilities and archive signing.

---

## Fri 11 Sep 2026

- **18:56** Arpit hands over `GLYF_BUILD_PROMPT.md` (the full build spec, kept as `SPEC.md`). Work starts on **M0**: repo scaffold (Flutter app, native Swift keyboard extension, Fastify server, shared contracts, CI guards) plus two spikes. Spike A opens the host app from the keyboard; Spike B does Privy Solana signing. Findings are in `docs/SPIKES.md` and `docs/M0-GATE.md`.
- **23:14** Arpit sends the OpenRouter key and Privy app id and secret ("keep them safe in env") and an Acti screen recording for feature reference. He also wants the "glassy ball" public/private design for onboarding. The keys go into `server/.env`.
- Overnight, **M1** (a daily-usable keyboard and onboarding) and **M2** (Glyf Bar, Glyf Keys, the AI backend) are built and gate-tested with mock and live OpenRouter (`docs/M1-M2-GATE.md`).

## Sat 12 Sep 2026

- **10:04** "continue building" starts **M3** (dictation: hand-off to the app, on-device speech, Raw/Clean/Formal) and **M4** (encrypted vault, S-key picker, `;sig` shorthand). Both are gate-tested (`docs/M3-M4-GATE.md`).
- **11:39** First angry redesign: "we building everything today only", Apple-size keyboard (not elongated), white only (no purple UI), an Acti-style bottom bar, and use the sent logos. The keyboard height saga ends at 260pt; the whole UI goes white with purple dots only.
- **12:54 to 13:01** Status check, then "finish everything end to end and cleanly".
  - **M5:** the full server step engine, 20 registry glyfs, Builder, Hub and Packs.
  - **M6 core:** keyless tools, connector surface and an OAuth skeleton.
  - **M7 core:** paywall, tone learning and telemetry.
  - Gate: `docs/M5-GATE.md`.
- **15:01** Arpit hit his usage limit; work resumed.
- **16:40** Study Apple's design language and Mobbin, test the real OpenRouter and Privy keys, and remove explainer lines.
- **17:59** Acti screenshots and recordings drive the app **v2 redesign**:
  - Home keyboard visual and recommended skills per key.
  - Acti-structured Profile.
  - Builder "What do you want?" with a tool browser.
  - Onboarding rebuilt (persona, sounds, enable, full access, keys).
  - In-app Notes; keyboard layouts for email, URL and number fields.
  - Spring micro-interactions; our own 3-tab bar with no + tab.
  - 16 of 16 UI tests pass.
- **18:42** A Google login at the end of onboarding with user-chosen scopes becomes a real Google OAuth broker. Arpit also asks to keep the old key list and to close the keyboard by tapping outside.
- **19:15** More providers (a 9-provider OAuth broker), more free tools (19 then 28), a month calendar view, and paid plans (Free 40 a day, Plus $4.99, Max $19.99).
- **20:29 to 21:05 (Session C)**
  - Arpit asks which capabilities to add in the App Store.
  - He pastes archive signing errors: a bogus team ID and a missing App Group capability.
  - He says his app ID is `com.demo.glyf`.
  - Bundle IDs become `com.demo.glyf` and `com.demo.glyf.keyboard`, with signing team XFSL58LKTQ.
- **22:26** Polish from real-device screenshots: the month-view gap, a brighter g button, more free tools, and fixing the symbols keyboard layout.

## Sun 13 Sep 2026

- **00:54 to 02:13**
  - Side-by-side with Apple's keyboard gives **Apple parity**: uniform white keys, key balloons, spacing, autocapitalisation.
  - The **keyboard follows host dark mode**.
  - Bound keys keep the dot and wash but lose the borders (Arpit: "lavendar lashes are not problem, see borders").
  - The default key style becomes **liquid glass**, with a Gboard-style theme picker (glass, classic, glow).
- **02:27 to 02:38** Update persistence verified (vault and settings survive reinstall). The build number goes up; Arpit uploads **TestFlight build 2** ("i pushed now") and says to work on Android.
- Early morning: **Android port** starts. It's a canvas-drawn Kotlin IME with the same Flutter app and the same settings format, running on emulator AVD `Avici_API_36`.
- **14:35 to 15:04**
  - Pending list; glyf symbols broken on Home; boot the Android device.
  - Gboard is the new reference: a dock-like grid menu, contact search, themes and an edit screen, Maps and YouTube search in the keyboard, on both platforms.
- **16:19 to 16:30** Theme audit (icons invisible in some themes). "exactly same features in all, and ios style in both" brings Inter and Cupertino everywhere, with the same toolbar icons and order.
- **16:41** "i want a website in next js ..." starts **site v1**: an interactive keyboard, features, store buttons and a waitlist through the backend.
- **19:36** Real-device bug: emoji search had no keys to type with. Any in-keyboard search now collapses to a strip above the keys.
- **19:59** Smoothness pass: Android GPU rendering, instant iOS key presses, faster springs.
- **20:07** Build number bump to 3; "Missing Compliance" fixed with the export compliance key.
- **20:33 to 21:49**
  - **Site v2** (framer-motion, search suite demo, no explainer copy).
  - **Site v3** (full product positioning, custom cursor).
  - "i cant see css on localhost" (caused by building while the dev server ran).
  - Working demos of the vault, clipboard and Glyf bar on the site.
  - App keyboard shell screens redesigned as cards, with notes moved into the vault.
- **22:37** "the website still looks really bad" brings **site v4**, studying heyclicky.com and openacti.com.
- **23:03 to 23:11** "see apple's design lang and make" brings **site v5**, Apple bands. The header is restored and "Made for thumbs." is kept.
- **23:25 to 23:31** Domain options (tryglyf.com, glyfboard.com, openglyf.com); `.so` can't be bought.

## Mon 14 Sep 2026

- **12:53** Arpit bought **tryglyf.com**. It's wired into the apps, server config and site. Release builds point at `https://api.tryglyf.com` (not deployed yet), and the `so.glyf.*` identifiers are untouched.
- **12:57 to 13:35** Logo standardisation across iOS, Android and site (dot at the top right after the f, raised). The app icon is restored to the original art with only the background removed, after Arpit was angry that the dot and letter had been changed.
- **13:52** "the google yt and maps search u implemented on website, it looks perfect, we need that in our keyboard". This starts the **keyboard search suite** on both platforms: real results, paste as title plus link, and a link-only setting.
- **14:03 to 14:32** Location permission in onboarding; landing lists of recent and top searches, popular videos and nearby places; verify end to end.
- **15:04** Arpit is angry about access prompts from a broad filesystem search. The new rule: no broad scans.
- **15:06** "you have hard coded results in ios idiot": mock results are removed from what users see.
- **15:18 to 15:59**
  - "ask me what apis u need". The research finds no Google web search API for new customers, a blocked embedded Google login, and empty DuckDuckGo answers. So: computed answers plus a Google hand-off, Brave recommended.
  - Arpit provides a **YouTube Data API key** and asks for restrictions.
  - Location-aware results; Geoapify chosen as the free no-card maps provider.
- **18:56 to 20:01** A research agent failed ("Try again"). The **Paper MCP** was installed at Arpit's request, and the app and site designs were partly ported to Paper until the Paper free plan's weekly MCP limit blocked it ("i cant see it on paper where did u add").
- **20:09** "design from first principles" brings **site v6** (split hero with a phone frame, zig-zag sections, bento grid).
- **22:27 to 23:30**
  - **Space-bar gestures** on both keyboards: glide to move the cursor, hold still 0.5s for AI while the finger is down.
  - "i need all features from [the Acti video]" starts **Acti parity**: act on typed text, a map result card, skill HUDs, a copied-text card, mini-app pages and a Skills hub.

## Tue 15 Sep 2026

- **00:00 to 00:48**
  - Requests for a personal vocabulary ("not random ass auto corrects") and a categorised vocabulary library.
  - The **Skills hub** is finished (real install counts; a device-ID leak fixed).
  - **20 vocabulary packs**.
  - **Autocorrect rebuilt** from scratch on both keyboards with AOSP scoring, learning and undo.
- **01:57** "install standrad dictionary", AI privacy deferred, and "find me good and v cheap ai model".
  - The AOSP dictionary is installed (165k words) with a Glyf supplement; bad AOSP fixes are switched off; Hinglish is on by default in India.
  - The model research recommends Gemini 2.5 Flash-Lite plus Groq; provider routing and cooldowns are implemented.
  - Tests: iOS unit 61, Android unit 17, server 84 to 90.
- **14:44** App work pauses: "releae it by tonight to we can have a waitlist ready". Requests: a heading with the keyboard below (no phone), the same full keyboard everywhere, look at apple.com and xome.bot, and a cooler cursor. Two research agents start.
- **15:00** "why are u asking for perms so much ... tf u executing js". The agents are stopped; research from here on is plain browsing only.
- **Questions answered:** tagline "Type less. Glyf more.", "It's all in the keys.", cursor "Caret → keycap", "Apple highlights + sections", light and dark, the Neon waitlist (and later app sign-ups), Vercel + tryglyf.com. The Neon table is created.
- **15:43 to 15:58** "finish fast" brings **site v7**: hero plus live keyboard, a shared keyboard with per-section autoplay, highlights tabs, stat sections, FAQ, and a working Neon waitlist. The old site is archived.
- **17:20 to 17:57** "i dont need explainer lines ... make it premium" plus "guide users to perform actions ... imessages like interface ... kinda like a game guide" brings **site v8**, the guided iMessage chat game with 8 chats and the send morph.
- **18:14 to 18:16** Script changes (Sakshi, Semi with Solana, Mumma, autotyping, Kabir + Maya).
- **18:46 to 19:08** Vault details (email, X, LinkedIn); the sunset answer widget; a WhatsApp layout detour rejected, so iMessage on desktop and mobile with a Messages list on phones; **Rohan** Hinglish autocorrect chat.
- **19:09 to 19:19** Hero backdrop keyboard (hero only, mirrors real keys), scroll autopilot with a ghost pointer, "Made for your thumbs." with a hold-space Rick Roll, vault links, scroll cue removed.
- **19:19 to 19:20** Greyed "Coming soon on" store badges; the Neon waitlist is hardened (setup SQL, email checks in form, API and database, honeypot, throttle) and tested live.
- **23:02 to 23:22** Semi becomes a **private Solana payment** with MagicBlock, a wallet balance and a Jupiter swap UI; real SOL, USDC and MagicBlock marks.
- **23:34** The 🙏 is removed from Semi's reply. The Rohan chat was opening AI because of a leftover hold from Neha's chat; that's fixed.
- **23:40 to 23:42** Order: Sakshi (coffee) first, Mumma (address, "beta") second.
- **23:44** "verify the whole experience ... on mobile". A full desktop and phone pass follows.

## Wed 16 Sep 2026

- **00:09** Verification report: all 8 chats work on phone and desktop. 8 layout issues were found and fixed (Semi preview, form sync, badge wrapping, banner over the back button, wallet header, AI label, header blur, tapback).
- **00:10 to 00:20** Mobile form-to-keyboard gap complaint, plus "push it to a private github repo", "which folder" and "which secret variable". The first push goes to `The-x-35/glyf` (videos over 100 MB, the stray Xcode template and secrets excluded). The folder map and Vercel steps are shared (Root Directory `site`, `DATABASE_URL`).
- **00:21** "this looks more bad now ... i wanted keyboard to go up a bit and be bigger on mobile". The hero text returns and the keyboard gets bigger and higher on phones.
- **00:24** Rick Roll link added to the keyboard clipboard (opens in a new tab); hold-space egg removed. Pushed.
- **02:10 to 02:19** "move type less glyf more a little above make it little bigger, fucking design it properly for mobile" brings a full mobile hero layout, tuned for short and narrow phones. "remove the em dashes from everywhere in website" is done across copy, messages and metadata. Pushed.
- **02:19** "note down everything in docs ... each and every fucking context" starts this documentation set (`docs/`).
- **02:20** Arpit asks to remove the AI assistant from the commit history. History rewritten and force-pushed: no AI co-author lines, no assistant config folder, no tool name in the spec titles.
- **After 02:20** "use the hero section as the og image" gives a generated 1200×630 share image. "make navbar a little bigger ... logo in navbar to be bigger ... glyf ... should be our wordmark logo" gives a 64px nav, a 28px wordmark, and the wordmark inside the headline.
- **03:09** Arpit commits everything so far ("fixes") and pushes. **The website goes live on Vercel at https://www.tryglyf.com**, with `tryglyf.com` redirecting to www. Checked: the share image and tags are live, and the waitlist API answers. The canonical and share URLs pointed at the redirecting apex, so the default moved to www.
- **03:17 to 03:18** The www fix is pushed; Vercel auto-deploys from `main` and the live page uses www for canonical and share URLs within a minute.

## Thu 17 Sep 2026

- **15:02 to 15:45** The website's eight chats become a **tour on the real keyboard**. Sign-in lands (Google, Apple or email at first) with the account in Postgres. Calendar arrives in the keyboard and Connected tools is rebuilt. Saved details start coming up from everyday words. Explainer lines go from the wallet and onboarding. A screenshot copied on iOS says how to paste it.
- **18:05 to 19:21** Android test flags apply to one launch only. The onboarding orb holds the real Glyf symbol and the official Google G. "Hi, I'm glyf" uses the wordmark. Keyboard setup is rebuilt twice: it shows an AI keyboard and names the exact switches to flip, then becomes one Settings card.
- **19:43 to 20:21** The **Ask Glyf bar**: one prompt in the strip, answers in the act panel. Sign-in narrows to **Apple or Google only**, then drops Privy entirely and verifies the ID tokens directly. The Google connector counts as set up only when its secret is present.
- **22:08 to 23:52** The **Lens Focus** launch animation. Onboarding gets a back button, safer details and a tour offer; Profile shows the account email and Sign out, no UID. A crash after closing the name sheet is fixed. Setup steps tick off, nearby shows the map before it asks, and the whole thing collapses to one screen where tapping a row turns it on.

## Fri 18 Sep 2026

- **00:12 to 00:50** The calendar panel shows the day's events with Month as a button. Screenshots ask for photos when switched on. The setup rows say where to walk in Settings.
- **12:59 to 14:00** The setup step can no longer dead-end on Full Access, and the photo switch says why it is asking. No false ticks; the rows go in order and there is a way to prove the step is done. The app gets a page of its own in Settings, and the documented way in is kept with a note on why (deep links into Settings do not work: see SPIKES).
- **14:17 to 16:12** Hard limits on the API, counted where they cannot be lost. **Every route goes behind a session** and the phones send it. The web tab answers with the model when no search key is set. **The API is live on Railway** (`api.tryglyf.com`, Singapore); a push to `main` deploys it.

## Sat 19 Sep 2026

- **11:41 to 11:57** Onboarding survives the relaunch that granting Full Access causes, and nearby search stays on when it resumes there.
- **12:56 to 13:39** `/rates` for the strip: a dollar table and a token's price. The site's tour moves the vault to **V**. Keys are redrawn like the system keyboard's, money goes in the strip, V and C are the two default binds. Lowercase settles at 24.5pt with boxes and ink within a pixel of Apple's; capitals take their 1pt nudge on every shift.
- **14:56 to 17:52** Build 4, then typing keeps up with fast fingers and money converts to a currency the person picks. Build 5.
- **18:26 to 22:22** The sheet band is drawn by Glyf on iOS below 26. The Taptic Engine is kept warm between keystrokes. The keystroke is measured instead of guessed at. The clipboard stops probing on every keystroke. **A touch in a gap types the nearest key**, keys match Apple's height, and copies keep for two days. The clipboard stops asking permission and the vault can hold pictures.

## Sun 20 to Mon 21 Sep 2026

- **Sun 00:20 to 01:32** A snapped key is no longer thrown away on the first tremor, and vaults open again (the `images` field had emptied them: see D100). The edges beside A and L type again. Every layer is sensitive edge to edge and the gap rule is provable.
- **Mon 09:56 to 10:48** The site's vault moves to V. A way to actually drive a gap on a simulator, and proof the gaps type. **The real cause of the dead gaps: the grid was transparent** (D99). The vault answers to V alone and the keyboard stops trying to edit it.
- **Mon 11:41 to 11:51** Several keys may open the same thing; nothing unbinds a key behind you. Build 6.
- **Mon 12:48 to 12:51** Joining the waitlist says so underneath, the form stays where it was, and joining empties the box for the next address.
- **Mon 13:17 to 15:23** A copy lands in the clipboard by itself and the autocorrect underline goes. The clipboard chip becomes a dismissable pill like Gboard's. A suggestion takes one tap, and so does everything on a clear surface. The chip shows **what** you copied and RECENT runs in time order. All / Text / Link / Image pills arrive and the panel stops asking to paste. A bare domain is a link. Build 7.
- **Mon 16:13 to 22:03** The "g" is centred on its own outline, then the pill becomes the real app mark in a square tile.

## Tue 22 Sep 2026

- **06:56 to 11:22** The mark fills its tile, then loses the tile altogether, then leaves the slot: the first slot becomes a drawn **apps grid** ("use some icon like this only, dont use glyf logo"). Its steps are made even and its geometry derived rather than eyeballed, after the turned tile was found overlapping its neighbours by 0.4pt.
- **13:05** **The site's stage becomes a timeline**: one scroll, one action, and a chat changes because it is done (D106).
- **14:26 to 14:32** Equal air everywhere on the strip and the row on its middle: margins 19.0 and 19.3, gaps 46.7 to 47.3, and the contents lifted to the strip's true centre. The close button loses its fill, which was a 50 by 32 pill because the fill was the whole tap target.
- **14:49 to 15:26** "i took a ss but it doesnt come in clipboard automatically and also its missing many things i copied". Two faults: the screenshot default disagreed between the app and the keyboard, and the app's note claimed links and numbers were kept when that had stopped being true. Then **the clipboard fills itself** (D107): both switches on, older installs migrated, and the panel names whichever permission is still missing.

## Wed 7 Oct 2026

Arpit: "use app on ios simulator across all diff scenarios and help improve app … i dont like the typed word as fist suggestion in "" feels like we are wasting a suggestion … also implement glide typing". The strip stopped showing the typed word as a quoted chip; a word typed in full offers only its completions; chat words bring an emoji to the last slot. A probe of 170 everyday messages (`RunnerTests/StripProbeTests.swift`) found gaps that became new answers: both currencies named, coin amounts, sums in words, city time, "until 5pm", lists, polls, the booking page, "Add a Meet link", city/state boxes. Glide typing on the iPhone (GlideDecoder: 96.8% of the 500 likeliest words right first time on synthetic fingers). Commit 653e158.

## Thu 8 Oct 2026

Arpit: "do glide and other things u made for android as well and research and implement more scenarios". Glide typing and the 7 Oct strip ported to Android. A second probe of 150 messages and a research pass (Raycast, Alfred, Espanso, Gboard, Omni calculators) added about forty answers on both keyboards and four fixes (STRIP-BACKLOG.md "Done on 8 Oct"); "3pm pst" stopped becoming "post". Caps lock on Android ("double tapping the shift key turns on caps lock like ios … but on our android its not doing like this"); hold Return for a new line on both ("hold return i need in ios too"). Build 1.0.0 (20) to TestFlight and the Android bundle, on request. Commits 1cb904d, 125a7a3, 924ac76, f839d01.

## Sat 10 Oct 2026

Arpit: "i need to know what all is happening from railway server, and out of it what all of it can we shift to local device". SERVER-INVENTORY.md maps every route, what already runs on the phone, what could move (currency rates, token prices, stickers, Cal.com booking, weather and sunrise, keyless tools) and what must stay (AI, keyed search providers, sign-in, plans, limits, the hub). It found an SSRF risk in the server's url.unfurl tool. Waiting on Arpit's go-ahead to start the moves.


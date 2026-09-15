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

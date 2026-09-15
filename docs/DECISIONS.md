# Decision log

Every product, design, technical and process decision made on Glyf from the first day (Fri 11 Sep 2026) to now, in order. Times are IST. Quotes are Arpit's own words from the chat (spelling kept). Status is **Active** unless a later decision replaced it.

Details live in the area docs: [WEBSITE.md](WEBSITE.md), [APPS.md](APPS.md), [BACKEND.md](BACKEND.md). The raw conversation is in [history/](history/).

---

## Fri 11 Sep 2026: kickoff

**D1. Build Glyf from the build prompt, milestone by milestone.** The spec is `GLYF_BUILD_PROMPT.md`, copied to `SPEC.md`. Milestones M0 to M9 each have a hard acceptance gate. The first session covered M0 only: scaffold plus two spikes (opening the host app from the keyboard, and Privy Solana signing).

**D2. Architecture from the spec.**
- A Flutter container app, with the iOS keyboard as a native Swift extension. Flutter never links into the extension, and CI enforces it.
- A Fastify + TypeScript backend.
- Shared JSON Schema contracts with generated Swift, Dart and zod types.
- An App Group (`group.so.glyf.shared`) and a Keychain group for cross-process data.
- Intents are single-use with a 120s TTL.

**D3. Secrets live only on the server.** The OpenRouter key and the Privy app id and secret go in `server/.env`, never in any client bundle. Arpit: "for privy , keep them safe in env". A CI guard (`ci/check_no_secrets.sh`) greps clients for key shapes.

**D4. Acti is a reference, not a template.** Arpit sent Acti's screen recording "to give references, you do not need to copy it, just for references of features i need". He also wants "the glassy ball desgin to do public and private ... on boarding".

---

## Sat 12 Sep 2026: first redesign, integrations, plans, signing

**D5. Build everything now.** "we dont have 16 -22 days, we building everything today only".

**D6. The keyboard uses Apple's default size.** "why is keyboard elongated as fuck, why not apple's default size": 260pt, which is a 44pt toolbar plus 216pt of keys.

**D7. White-only app design.**
- "the fuck is this purple ui soo shittyy, have white mode only".
- Accent `#7C5CFF` is used only as dots and highlights; CTAs are black pills.
- Status: the keyboard part was replaced by D22 (it follows the host's dark mode). The whole rule was replaced by D63 (light and dark on the site and later the apps).

**D8. Use Arpit's logo concepts.** From `glyf-symbol-concepts.svg`: concept 01, a keycap "g" with an accent dot, is the app icon; the "glyf" wordmark carries the dot. "why not using the logos i sent too".

**D9. An Acti-style app shell with a bottom bar.** "a bottom bar and having all this".

**D10. Finish the whole spec cleanly.** "yes finish everything end to end and cleanly".
- M5 was built in full, plus buildable cores of M6 and M7.
- M8 (crypto) stays out of every binary until its own release.
- M9 (Android) was planned for after iOS ships; D25 replaced that.

**D11. Apple's design language, no explainer lines.** "study apple's design language i need simplistic designs like that ... i dont like explainer lines everywhere remove them". This became a permanent rule for the apps and the site.

**D12. Test the real keys.** "i sent u openrouter api key why arent u testing that too, also sent u privy keys". Live OpenRouter and Privy calls were verified.

**D13. Home and onboarding changes (from Acti screenshots and recordings).**
- Hide the setup ticks once permissions are granted.
- Show a keyboard visual on Home that doesn't look copied.
- Revamp the profile page following Acti's structure.
- Builder starts with "What do you want?" plus a tool browser.
- The test field sits right under the keys, so no scrolling.
- Make the keyboard work for number and email fields.
- Onboarding asks the persona (student, working, and so on), key sounds and the emoji panel, recommends a skill per key, and "dont preset a lot".
- Research GIF and sticker support like Gboard.
- Use our own bottom bar icons: no + tab, Profile instead ("dont blindly copy").
- Very smooth micro-interactions.

**D14. Own skills, not a sharing platform (at first).** "i think acti skill sharing platform etc is bad, we should make out own skills and ask users to select what they want ... give users option to create their glyfs". Status: partly replaced by D52, since Acti parity later added a Skills hub with community skills.

**D15. Integrations must really work.** "i need these integrations to work end to end like google calendar, meet slack, notion ... ask me whatever keys you need".
- In-app Notes, like the S key.
- A Google login at the end of onboarding, where the user picks what to share (mail, calendar, meet) based on their answers: "we need a login when app is opened the first time and there only user can decide what all he wants to give access to".
- Keep the previous key list under the keyboard visual ("i liked the previous key list more").
- Tapping outside closes the test keyboard.

**D16. More providers and tools; month calendar; paid plans.** "did u add notion, slack , and other thigs ... research what more tools we can have ... in calendar option i also need a button to view months calendar ... one 5 $ plan and one 20$".
- An OAuth broker for 9 providers: Google, Notion, Slack, GitHub, Linear, Todoist, Calendly, Zoom and Spotify.
- 28 keyless tools.
- A month view in the calendar surface.
- Plans: Free (40 runs a day), Plus $4.99 (400 a day) and Max $19.99 (unlimited), researched against Wispr Flow and Grammarly.

**D17. App Store identity.**
- Arpit registered the app ID himself: "i have the app id as com.demo.glyf not what u put, fix that". Bundle IDs are `com.demo.glyf` (app) and `com.demo.glyf.keyboard` (keyboard).
- The `so.glyf.*` identifiers (App Group, Keychain group, vault service, MethodChannel, logger subsystem) stay unchanged on purpose, because renaming would orphan stored data.
- Signing team: XFSL58LKTQ (Console Labs India Private Limited). The team ID first in the project was bogus.
- Archives must target Any iOS Device (arm64).

**D18. UI polish round.**
- Fix the gap under the month view.
- Take references from Mobbin.
- A brighter g button: "why is glyf button so dull and sad, saw how acti was soo good and bright".
- Integrate as many free tools as possible.

---

## Sun 13 Sep 2026: Apple parity, Android, first website

**D19. The keyboard matches Apple's.** "switch to apples keyboard with globe icon and see diff, i need apple like styles with our ui and apple ux, ley sizes spacing etc". Uniform white keys, key radius 9.5, 44pt keys, press preview balloons, and the keyboard respects each field's autocapitalization.

**D20. Bound-key styling.** "idiot lavendar lashes are not problem, see borders ... i think lavender dots are still fine, see acti has a blue light in M key ... i like the dot tho its glyf symbol of our app". The dot and faint lavender wash stay, accent borders are removed for good, and there's a soft accent under-glow.

**D21. The default key style is liquid glass, plus a design picker.**
- "still too much shadow and not glassy keys, also give option to edit keyboard designs in app, like gboard ... by default we need simple v similar to apple with just purple dots and glassy keys liquid glass".
- Three themes: glass (default), classic and glow.
- Later came Gboard-style colour and gradient backgrounds, a borders toggle and brightness.

**D22. The keyboard follows the host's light or dark mode.** "fix dark mode too". This amends D7 for the keyboard only; the app stayed white at the time.

**D23. App updates must keep user data.** "can u verify that updating app wont require me to readd everything in vault and memory etc it should remember". Verified: the App Group and Keychain survive a reinstall with the same bundle ID. Lock the final bundle ID and team before real users.

**D24. TestFlight builds.**
- "increase build no, i am pushing update to testflight". Arpit uploaded build 2 himself ("i pushed now").
- Later: "ok update build no and we will push to testflight now, and why is appstore connect showing Missing Compliance". Build number 3; `ITSAppUsesNonExemptEncryption = false` added to both the app and keyboard Info.plists. Whether build 3 was uploaded isn't recorded.

**D25. Build Android too, now.** "lets also make everything for android as well, install android simulator and see everything and make for it too". This overrode the spec's "Android after iOS ships" gate (D10).
- A Kotlin IME drawn on a canvas.
- The same Flutter app.
- The same shared settings format as iOS.

**D26. Gboard is the reference for keyboard UX.**
- "install gboard in android use it and learn from it".
- A menu grid with icons and labels "how we show apps in dock", not one long column.
- Contact search with permission.
- Gboard-style themes and edit screen.
- "need maps and youtube etc from google like gboard", with real results.

**D27. Same features and iOS style on both platforms.** "why the fuck does android and ios apps look so diff, i want exactly same features in all , and ios style in both". The Inter font is bundled, Cupertino controls and transitions are used on Android, and the toolbar icons and order are identical.

**D28. Smooth like Apple and Google.** "i need smooth as fuck experience". Android keys render fully on the GPU (no software layers or shadow layers), there's no press scale animation on iOS, and surface springs are faster.

**D29. Notes live inside the vault.** "we can remove notes and vault can serve the feature and shorthand can be another thing". Notes are edited from the keyboard too.

**D30. Build a website.** "i want a website in next js typescript and react to showcase this glyf product, it will have a cool keyboard on site and should respond to keypresses ... we can show button to downloand apple and google play store ansd also a join waitlist area". See [WEBSITE.md](WEBSITE.md) for v1 to v5.

**D31. The website follows Apple's design language.**
- "still looks soo fucking shittt, are u idiot, see apple's design lang and make".
- White, #f5f5f7 and black bands; weight-600 type; one line per section; no decoration.
- "why is header so small, why u remove made for thumbs i love that line": the nav came back bigger and "Made for thumbs." stayed.

**D32. Domain.** Options were tryglyf.com, glyfboard.com and openglyf.com ("i cant find .so anywhere to buy"). See D33.

---

## Mon 14 Sep 2026: domain, logo, search suite, gestures, Acti parity

**D33. tryglyf.com everywhere.** "bought tryglyf.com now, wire it up in app and everywhere, no need to change the glyf logo or anything thats all perfect, just replace ur .so which u assumed".
- Every `glyf.so` domain reference became tryglyf.com.
- Release builds point at `https://api.tryglyf.com`, and debug builds point at local servers.
- `so.glyf.*` reverse-DNS identifiers stay (D17).

**D34. One standard wordmark on every surface.**
- "why is the logo fucking diff on android ios and website, why not fucking standard, i need the dot on top right after f as we have on our keyboard".
- Then: "it looks like its in from of f and not top right, make dot more up".
- Canonical geometry: dot 0.18em, gap 0.16em, and the dot's bottom sits at the f's top (rise 0.74em).

**D35. App icon: only remove the background.** "u fucked the app icon , it was good i liked the dot placement and everything in that, it was just in fuckin bg on the screen ... i just fucking asked u to remove bg". The original keycap-g art is kept on a plain white canvas. Lesson: when asked to remove a background, change nothing else.

**D36. The website's search UI becomes the keyboard's search suite.**
- "now the google yt and maps search u implemented on website, it looks perfect, we need that in our keyboard with exact ui ux like that".
- Tapping a result pastes it.
- Paste format is title plus link by default, with a link-only setting ("see how google also pastes title with link").

**D37. Location and landing content.**
- "u can req location access for this if needed in on boarding flow".
- "u should show the recent google searches or top google searches and same witth yt ... same with maps, req location access and show nearby things".
- Location is coarse, rounded to about 1km, cached on the device and never stored on the server.

**D38. No fake results.** "you have hard coded results in ios idiot the fuck make them work". Mock mode is only for automated tests; users never see canned results.

**D39. Ask for the keys that are needed.** "so fucking ask me what apis u need from google and how to get it and i will give".

**D40. Search provider choices (researched).**
- Google has no web search API for new customers, and Google login inside an embedded web view is blocked.
- DuckDuckGo instant answers returned nothing useful. So the web tab shows computed answers plus a hand-off to Google, and Brave Search is recommended for real links. Serper is only an opt-in fallback because of legal risk.
- YouTube uses the YouTube Data API key Arpit provided; add key restrictions. Public data for now: "shud we just do public for now ?"
- Maps uses Geoapify: free, no card. "find free alternative for maps key, i dont wanna add my card here rn". Google Places is optional later. Nominatim is for development only.
- Google login in onboarding is only for YouTube liked videos (read-only scope).
- Keys go straight into `server/.env`, not the chat. Don't reuse the exposed YouTube key for billed Places, and regenerate it after deploy.

**D41. No broad filesystem scans.** "the fuck are u requesting to access everything the fuck u need why not use simulator attached to clude only idiot". Use known tool paths or ask.

**D42. Port the designs to Paper.** "i need you to port all app and website design to paper now with all screens and flows". The Paper MCP was installed. The port was partly done, then blocked by Paper's weekly MCP limit on the free plan.

**D43. Website v6 from first principles.** "it still feels not good, content and things are good but not layout or anything ... design from first principles". A split hero with a phone frame, zig-zag sections and a bento grid. Replaced by D57.

**D44. Space-bar gestures like Apple, Gboard and Acti.**
- "i want hold and glide on keyboard to also move cursor thru text like apple keyboard and google keyboard does and i need hold to open ai thing also".
- "why does spacebar ai only launch after leaving key, it should launch before only".
- "if nothing glides for some time just open ai ... set time v properly".
- Final rule on both keyboards: glide at any time while holding to move the cursor; hold still for 0.5s and the AI opens while the finger is still down, never on lift; release sooner to type a space. Replace consumes text on both sides of the cursor.

**D45. Every feature from Acti's launch video.** "i hope u have seen video now i need all features from it as well". Built:
- act on typed text (hold space);
- result cards, including a map;
- skill-key HUDs;
- a copied-text card;
- live mini-app pages;
- a Skills hub.

---

## Tue 15 Sep 2026 (night): autocorrect, vocabulary, AI models

**D46. Autocorrect you can trust, which learns the person's words.** "we need to add commonly used words by the person in vocabulary and then suggest aut correct and changes arccording to it, not random ass auto corrects". One engine on both keyboards, using AOSP's scoring model. It only corrects when confident, undo teaches it, it predicts the next word, and learned words stay on the device.

**D47. A categorised vocabulary library.** "make a vocabulary lib ... like proffesoional vocab, local lang vocab, fun vocab categorise things". 20 packs (about 2,200 words) plus "make a pack with AI".

**D48. Install the standard dictionary.** "yes install standrad dictionary and all".
- The AOSP English list: 165k words, Apache-2.0.
- A Glyf supplement for texting words and Indian names and apps.
- AOSP's harmful fixes are switched off (for example hum→him).
- Phones set to India start with the Hinglish pack on.

**D49. AI privacy is out of scope for now.** "we will not work on ai privacy rn as we will have privacy policy".

**D50. AI model choice.** "find me good and v cheap ai model to use here, i heard groq is good but ig they stopped sharing dev apis". Findings:
- Groq still gives free developer keys, but dropped self-serve Llama.
- The recommended no-card chain is Gemini 2.5 Flash-Lite, then Groq Qwen and gpt-oss.
- On a paid plan it's about $12 to $13 a month at 100k rewrites.
- Provider prefixes and rate-limit cooldowns are implemented.
- Arpit still needs to add `GEMINI_API_KEY` and `GROQ_API_KEY`.

**D51. The Skills hub only shows real data.** Install counts are real (one per device) and there are no made-up creators. The public hub list no longer exposes publisher device IDs, which work as logins.

**D52. The Skills hub exists (Acti parity).** This partly replaces D14: official and community skills in one list, with categories, search and creators.

---

## Tue 15 Sep 2026 (day): website launch

**D53. Pause the apps and ship the website tonight.** "we will come back to app by evening, i need to work on website and releae it by tonight to we can have a waitlist ready".

**D54. The hero is a heading with the keyboard below it, no phone.** "see apple has heading and below it it had the device, so we need heading and below it the keyboard and dont show mobile on hero just the keyboard with the actions it can do". "Every key is a Glyf" is out ("i dont like every key is a glyf line that much").

**D55. Tagline and secondary line.** The first options were rejected ("these are all too cliche and bad ... something with glyf"). Chosen: **"Type less. Glyf more."** and **"It's all in the keys."** The second line was used in v7 only.

**D56. Every demo keyboard is the full keyboard.** "the demo keyboards on page shud share the same thing, it should have vaults and rewrites and google yt search etc on everykeybaord properly", and "all parts of site will still show diff features only but i said that others shud also work there".

**D57. Don't copy the mobile app's UI on the site.** "i like ui ux on website dont copy mobile for that, its shit in mobile rn".

**D58. Cursor: caret to keycap.** "the dot and circle design for pointer i dont like, make it fucking cool cursor". Chosen option: "Caret → keycap".

**D59. Features as Apple highlights plus sections (v7).** A liked reference was xome.bot ("it state features nicely"). Replaced by D64.

**D60. Ask when ambiguous.** "u can ask me wherever u are ambiguous instead of taking shit design decisions".

**D61. Research by plain browsing only.** "why are u asking for perms so much access site on browser and see idiot tf u executing js". No page JavaScript on other sites, no headless Chrome scripts, no background browsing agents.

**D62. Waitlist in Neon, and the same database for app sign-ups later.** "in a neon db ... use this db in app also for storing users who sign up, we will have a sign up page at first also, then onboarding then if users want more features from google etc they will be pinged to allow".

**D63. Light and dark mode.** "i need both light and dark modes both in site and later in apps too". This replaces D7.

**D64. The site becomes a guided iMessage game (v8).**
- "i dont need explainer lines anywhere, i need you to highlight vaults, search yt maps, and ai rewrite etc, and also doing calculations in keyboard, space key should say glyf ... show animations and micro interactions ... make user go thru each section on scroll and can jump in sections on clicking ... make it premium ... you keyboard now knows stuff about u".
- "instead of forcing animations etc, u shud guide users to perform actions and feel the features himself ... simulate a chat interface ... i need a imessages like interface ... kinda like a game guide".
- "see how i messages send msg animation works ... it forms a bubble and goes right".
- Result: a pinned scroll stage with friend chats, coach rings and pills, the send morph, and no autoplay.

**D65. Never make the visitor type.** "for zoya, the user should not be typing 3480/4, u shud type it as animations and user should just tap it", "u cant ask user to type soo much just make hiim do actions", "with transalte chat dont ask user to type, u type it". The keyboard types; the visitor holds, taps and sends.

**D66. Chat cast and script changes.**
- Riya → Sakshi.
- Vault Home → "123, A-block, Delhi 110001".
- Dev → Semi, with a Solana address (not EVM).
- Arjun → Mumma, who replies after the location.
- "3480/4 = 870" instead of just "870".
- Maya is merged into Kabir.
- The current scripts are in [WEBSITE.md](WEBSITE.md) section 3.6.

**D67. Arpit's details in the vault.**
- Email arpit@tryglyf.com.
- Socials as full links with the capital A: x.com/Arpitx35, linkedin.com/in/Arpitx35, instagram.com/Arpitx35. "dont use @arpitx35, use links bro".
- UPI and phone are still placeholders.

**D68. iMessage layout on desktop and mobile, not WhatsApp.** "no man i didnt want a whatsapp exact layout if u wanna copy exactly do imessages for mobile and desktop", "even the previous one was better ig with heading and list below".

**D69. Autocorrect in local languages on the site.** "show auto correct etc in local languages too ... like yaar". This added the Rohan chat: "Fixes the typos. Keeps the yaar."

**D70. Subtle keyboard behind the hero, which mirrors real keys.**
- "the type less gly more screen should show the keyboard behind very subtly".
- "it should also press keys if i press key on real keyboard".
- "i think subtle keyboard to only stay in hero section, elsewhere it looks shit". An interim "everywhere in bg" idea was dropped.

**D71. Scroll autopilot.** "if the user is nto doing actions and just scrolling, u shud do the action on further scrolling and maybe use a fake mouse pointer".

**D72. Finale line and a Rick Roll easter egg.** "change hold space for launch to made for yout thumbs and keep the rick roll easter egg": the finale reads "Made for your thumbs." and holding space there opened the Rick Roll. Status: the egg was replaced by D84.

**D73. No scroll cue in the hero.** "remove the scroller icon from hero".

**D74. Greyed store badges above the waitlist.** "after the ai keyboard that does the rest have apple and google store logos but greyed out, write coming soon on and then waitilist section".

**D75. A waitlist table and basic email checks.** "make a table or something for waitlist users and storying their mail and also but basic mail id check in there". Checks run in the form, the API and the database (CHECK constraint), with a unique lowercase email.

**D76. Semi's chat becomes a private Solana payment.**
- "he asks send me $200 for server costs ... he sends mei his wallet address i copy that and paste into chatbox and then we use magic blocks to send money privately on solana".
- "also have a ui for swaps powered by jupiter, we dont need to demo jup swaps ... use our site ui ux only".
- "remove asking insta from semi"; "show my balance in keyboard".

**D77. Real token and partner marks.** "use real sol and usdc symbol and also get , magic block logo and use that". Open point: check brand guidelines before launch.

**D78. Semi's reply has no 🙏.** "🙏 remove this after thank u in semi". The 🙏 tapback on the card is still there (asked, no answer).

**D79. Rohan's chat never opens the AI.** "in rohon why does it goes to ai while its a hinglish suggestion case". The chat is guided through suggestion chips, and holds are cancelled when the chat changes.

**D80. Chat order: Sakshi then Mumma.** "move mumma on top, replace script of mumma and sakshi ... saskshiw will be on top with coffee script", then "mummi wont say ghar ka khana, just say beta and the script". Order: Sakshi, Mumma, Semi, Neha, Rohan, Zoya, Kabir, Sofía.

**D81. Verify everything on mobile.** "can u verify the whole experience and everything on mobile mode too once of website". The fixes it produced are listed in [WEBSITE.md](WEBSITE.md) section 10.

---

## Wed 16 Sep 2026: repo, hosting, mobile hero, docs

**D82. One private GitHub repo holds everything.** "i need u to push it to a private github repo ... push everything together on github ... https://github.com/The-x-35/glyf do push it here".
- The whole monorepo is pushed.
- Excluded: real `.env` files; build output; the gate recordings `docs/evidence/*.mp4` (some are over GitHub's 100 MB limit; they stay on the Mac); the stray `/glyf` Xcode template project, which had its own git history.

**D83. Hosting on Vercel.** Root Directory `site`, with the env var `DATABASE_URL` (and optional `SITE_URL`). Arpit deploys it himself: "u tell me which folder to chose from project and which secret variable to add and i will do". Rotate the Neon password first.

**D84. The mobile hero keyboard is bigger and higher; the content isn't pushed down.**
- "i dont like the space after join waitlist and keyboard it can be reduced i feel in mobile".
- A first attempt moved the text down and was rejected: "this looks more bad now ... i wanted keyboard to go up a bit and be bigger on mobile".

**D85. The Rick Roll moves into the clipboard.** "i need clipboard to also have this link https://youtu.be/dQw4w9WgXcQ?si=ms6HzsvNvsPeLhH_ and when its clicked it opens this in a new tab ... did u implement rick roll on space long press on last screen remove it then we dont need that". This replaces the egg in D72.

**D86. Mobile hero: a bigger headline, higher up.** "move type less glyf more a little above make it little bigger, fucking design it properly for mobile". A full-height layout with the headline near the top and the badges and form just above the keyboard, tuned for short and narrow phones.

**D87. No em dashes on the website.** "remove the em dashes from everywhere in website, they look fucking disgusting ai made". The docs follow the same rule.

**D88. Write everything down.** "note down everything in docs, like everything, every decisions we made and our whole chat history for this project ... each and every fucking context". That is this `docs/` set.

**D89. No AI assistant traces in the git history.** Arpit asked to remove the AI assistant from the commit history and everywhere else in the repo.
- The history was rewritten and force-pushed.
- Co-author trailers were removed, the local assistant config folder was dropped from every commit, and the tool name was removed from the spec titles.
- Future commits carry no AI attribution.

**D90. The hero is the share image.** "i think u shud use the hero section as the og image also , set it properly and do it". A 1200×630 Open Graph and Twitter image is generated from the hero layout by `tools/make_og_image.py`.

**D91. A bigger navbar, and the wordmark inside the headline.** "make navbar a little bigger in site and logo in navbar to be bigger too and glyf more text in hero gly should be our workmark logo in there". The nav is 64px with a 28px wordmark, and "glyf" in "Type less. glyf more." is the wordmark with its raised dot.

---

## Standing rules (apply to all future work)

These came out of the decisions above and Arpit's feedback. [WORKING-AGREEMENTS.md](WORKING-AGREEMENTS.md) has the full list with context.

- No explainer lines, anywhere (apps and site).
- No em dashes on the site.
- The accent purple is only a dot or highlight: never washes, and never borders on keys.
- Glyf's own look: black pills, Inter, Apple-like. Never copy Acti 1:1.
- Never make a demo visitor type.
- No fake or hardcoded results shown to users.
- Secrets only in server env files. Never print the Neon connection string; rotate it before launch.
- Don't change the `so.glyf.*` identifiers.
- No broad filesystem scans. Browse other sites without running scripts.
- Ask Arpit when a design call is ambiguous.
- Commit and push only when Arpit asks, with no AI attribution.
- When asked to remove or change one thing (a background, a gap), change only that thing, and in the direction asked.

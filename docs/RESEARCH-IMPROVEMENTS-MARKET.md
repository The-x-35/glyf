# What to improve so people love Glyf and pay for it

Written 29 Oct 2026 from a web research pass (competitors, store and forum complaints, retention and subscription benchmarks). It complements [GO-TO-MARKET.md](GO-TO-MARKET.md) (14 Oct), which covers channels, store page, price tests and the setup funnel. This page is about the **product**: what to build or fix. Where the two overlap, this page points there instead of repeating it.

Sources are numbered [R1], [R2] … and listed at the end. Figures from a vendor, a single blog or an aggregator are marked (unverified). Nothing in the code was changed. Every decision here is Arpit's.

---

## The top 15, ranked

Ranked by expected effect on activation (A), retention (R) and revenue ($), weighed against effort. The first three protect everything else: an AI keyboard that mistypes, gets kicked out or scares people at Full Access loses them before any AI feature matters.

| # | Improvement | Main effect | Effort |
|---|---|---|---|
| 1 | Typing that never fights you: no dropped taps, an Undo for every autocorrect, names left alone | R (very high) | M |
| 2 | Never get kicked out: memory and launch reliability on real old iPhones | R (very high) | M |
| 3 | Full Access earned late, primed, and backed by a receipt on every AI run | A (very high) | S–M |
| 4 | First win inside 60 seconds, before sign-in and the paywall | A (high) | M |
| 5 | Voice that cleans up and acts, Android first | R, $ (high) | L |
| 6 | Charge for answers and actions, not for rewriting | $ (high) | S (packaging) |
| 7 | A free on-device tier (Apple Foundation Models, Gemini Nano): spike first | $ margin, A | M (spike S) |
| 8 | Caps people accept: meter only AI, show it, never block typing | $, reviews | S |
| 9 | Yearly-first plans and Google Play payment recovery | $ (medium–high) | S |
| 10 | "Reply to what you copied": conversation context the legal way | R, $ | M |
| 11 | Skills people make and share | R, acquisition | M–L |
| 12 | Multilingual typing and mid-sentence language switching | A (new markets), R | L |
| 13 | A weekly recap: "Glyf did 34 things for you this week" | R (D30), $ | S |
| 14 | Teach one hidden gesture at a time, in the moment | R (D7) | S |
| 15 | "Why did my keyboard change?": detect being switched off and help back | R | S |

### 1. Typing that never fights you

**Evidence.**
- In 1–3 star reviews of Gboard, SwiftKey, Grammarly, Fleksy and Typewise, autocorrect is the most common complaint (26%), then lag and dropped keystrokes (21%), privacy (18%), paywalled basics and upsells (16%) and updates that remove features (12%) [R1] (unverified: sample size not given). A typical line: autocorrect "changes my name and my contacts names every single time" [R1].
- Grammarly's iPhone keyboard is criticised for being "laggy" and missing keystrokes the stock keyboard catches [R38].
- Apple's own keyboard got worse in iOS 26: missed letters during fast typing, a Reddit thread of 600+ comments, fixed only in iOS 26.4 (March 2026) [R2][R3]. iOS 27 is expected to answer with smarter, meaning-aware autocorrect [R45]. The window when iPhone owners are open to switching is now, and the bar is "as good as Apple's, never worse".

**What the best do.** Gboard lets you long-press a suggestion to forget a learned word and syncs learned words [R34]. SwiftKey's selling point is prediction that learns your style [R1].

**For Glyf.**
- Ship the "Changed 'ket' to 'key' · Undo" chip (STRIP-BACKLOG #15, still open) and make backspace right after an autocorrect restore the original word and learn from it.
- Never autocorrect a capitalised word that is in Contacts, the vault, or typed twice.
- Make the typing harness (StripEval/TypingParity) a release gate with fixed numbers: no dropped taps at 10 taps a second, key-down to letter on screen under one frame at p95 on the oldest supported iPhone. Today's engine measures 75% fixes and 30% next word (10-05); publish the internal target and track it per build.

**Expected impact.** Retention at days 7 and 30. This is the reason people delete keyboards, and no AI feature makes up for it.

### 2. Never get kicked out

**Evidence.**
- Since iOS 17, keyboard extensions are silently killed and replaced by the system keyboard. The suspected cause is memory, the limits are undocumented, and the kill leaves no crash log in Xcode or App Store Connect [R4].
- Wispr Flow's own help pages list the keyboard crashing on iOS 26.4 with the system keyboard appearing in its place, and getting stuck on the mic button [R5].
- Microsoft says SwiftKey "won't run quickly" without enough memory, and that reloading after a switch is slow [R42].

**For Glyf.** OPEN-ITEMS A4 is still open: the 45 MB budget, haptics and real-microphone checks have only been run on the simulator.
- Profile on two real old phones (for example an iPhone SE 2nd gen and an iPhone 11) with every heavy surface open: emoji board with GIFs, themes with textures, Snake, the map card.
- Measure cold start (first key drawn) after the extension was killed.
- Count terminations from the gaps in `keyboard-ping.json`, so it shows in the funnel and isn't silent.

**Expected impact.** Retention. A keyboard that disappears twice a day is uninstalled within a week, and people blame the app, not iOS.

### 3. Full Access earned late, primed, and with a receipt

**Evidence.**
- Apple's switch text tells people the developer may "access, collect and transmit the data you type", and it is the same text for every keyboard [R23]. Testers of an open-source dictation keyboard declined setup because of it; the fix was an explainer screen before the step [R24].
- Privacy is 18% of 1–3 star keyboard reviews [R1]. Breaches like ai.type's open database (2017) are still cited [R37].
- Grammarly's help page explains Full Access plainly: typing works without it, and it checks only text typed with it [R15].

**For Glyf.** GO-TO-MARKET 3.1 covers the order and the "What leaves your phone" page. Two product additions:
- **An AI receipt.** After each run, one quiet line in the result: "Sent: 1 sentence · not kept". It turns the scary switch into something people can see.
- **A one-tap "Private" state on the strip** that stops all network calls until tapped again (on-phone answers keep working). Gboard has Incognito; people trust what they can switch off.

**Expected impact.** Activation (the Full Access rate is the biggest single gate on iPhone) and trust at the paywall.

### 4. First win inside 60 seconds, before sign-in and the paywall

**Evidence.**
- Users who complete a meaningful action in their first session are 2–3× more likely to be active on day 30 (UXCam data via Userpilot) [R29].
- 55% of 3-day trial cancellations happen on day 0 [R26]: if day 0 holds no win, the decision is already made.

**For Glyf.** Onboarding (10-06) starts with sign-in, and the app tour is optional on Home.
- Move the first strip answer ("split $84 four ways") into onboarding, right after the keyboard is added, on a practice field.
- Consider asking for sign-in only when the first AI run needs an account. Typing, the strip, the vault and the clipboard need no account.
- Record time-to-first-strip-answer as an activation metric.

**Expected impact.** Activation, and day-1 retention through it.

### 5. Voice that cleans up and acts, Android first

**Evidence.**
- Voice is the category people pay most for. Wispr Flow charges $15 a month (or $143.99 a year) with a free 1,000 words a week on iPhone [R21], raised a $280M Series B in Sep 2026 [R22], and its founder said 19% of free users paid (GO-TO-MARKET [S18], unverified).
- Google shipped Rambler in Gboard in May 2026: Gemini dictation that drops "um"s, understands mid-sentence corrections and switches language mid-sentence. It is Android only, first on Pixel and Galaxy, with "other Android devices to follow" [R7][R40]. Dictation startups had left Android underserved [R7].
- On iPhone, keyboards still can't use the microphone even with Full Access [R25]. Wispr's keyboard jumps to its app to record, and since iOS 26.4 people must swipe back by hand [R5][R6]. iOS 27 adds Apple's own dictation inside the keyboard [R6].

**For Glyf.**
- **Android:** a mic key in the keyboard (an IME may record) with Raw / Clean / Formal, filler removal and "no wait, 3pm" corrections, on every Android phone, not only Pixel and Galaxy.
- Then the part nobody does: **voice that acts.** "Send her my address and a time tomorrow" → the address from the vault plus the booking chip.
- **iPhone:** don't fight the platform. Make "hold space → Clean" work well on text that Apple's dictation just wrote, and keep the in-app dictation sheet as is.

**Expected impact.** Revenue (voice is a proven reason to pay $8–15 a month) and daily use.

### 6. Charge for answers and actions, not for rewriting

**Evidence.**
- Rewriting is now free and built in. Gboard's on-device writing tools proofread and rewrite [R11]. Apple Writing Tools are free. Microsoft even removed Copilot and Compose from SwiftKey, leaving only a proofreader [R10].
- Built-in rewriting barely lands: in a TidBITS reader poll of 760, about 84% saw no impact from Writing Tools (self-selected sample) [R12].
- The money in this category goes to what the built-ins can't do: Acti's agentic Skills [R8] and Wispr's voice [R21].

**For Glyf.**
- Keep basic Rewrite and Fix generous in the free tier (ideally on-device, see 7).
- Put the paid value in what only Glyf does: answers with live data (places, stocks, weather), actions (Meet links, booking, calendar), Skills, long text, better models and voice Clean and Formal.
- The paywall copy names those, not "AI rewriting".

**Expected impact.** Trial-to-paid conversion. A paywall that sells what iOS gives away converts badly and draws "scam" reviews.

### 7. A free on-device tier: spike first

**Evidence.**
- Gboard's writing tools run on device with Gemini Nano, a privacy point Google leads with [R11]. On-device processing is the main claim of newer keyboards such as Yaps [R39] (vendor).
- An Apple DTS engineer says the system model behind Foundation Models (iOS 26) is not loaded into an extension's memory, so it doesn't count against the limit. But some extensions are not allowed the XPC it needs, and keyboards were not named either way [R35] (unverified for keyboards).

**For Glyf.**
- Do a one-day spike: can the GlyfKeyboard extension call `SystemLanguageModel`, and does it work without Full Access?
- If yes: free, unlimited, offline Fix and Rewrite on Apple Intelligence phones, and possibly the first AI that works without Full Access. The same on Android with Gemini Nano where present.
- The server keeps answers, actions and the bigger models.

**Expected impact.** Lower AI cost per free user, a privacy story nobody else on iPhone has, and activation if it works without Full Access.

### 8. Caps people accept

**Evidence.**
- What others give free: Grammarly 100 AI prompts a month (Pro 2,000) [R13]; Wispr 1,000 words a week on iPhone [R21]; Acti free with credits that "are not fully quantified" [R9] (directory).
- What draws anger: "aggressive paywall tactics" and weekly plans. Wave AI Keyboard reviews call it a scam [R28], and weekly plans of $2.99 to $6.99 are common in AI keyboards [R20][R28] (aggregators). Paywalled basics are 16% of bad keyboard reviews [R1].
- The other side: Adapty reports weekly plans earn 62% of subscription revenue overall [R27] (secondary). For a keyboard that asks for trust, the review cost outweighs it.

**For Glyf.** 50 free runs a week (≈200 a month) is already twice Grammarly's free tier.
- Show the meter in the strip at 80% and say when it resets ("8 left · resets Monday").
- When runs are out, never block typing, the strip, the vault or the clipboard. Offer the plan once, then stay quiet until the reset.
- No weekly plans.

**Expected impact.** Revenue (people pay when they see the limit coming, not when they hit a wall) and the store rating.

### 9. Yearly-first plans and Play payment recovery

**Evidence (RevenueCat 2026 [R26]).**
- AI apps earn 41% more in year 1 than other apps ($30.16 against $21.37), but their monthly plans churn about 36% faster.
- 35% of yearly cancellations happen in month 1.
- Involuntary billing failures cause 31% of Google Play cancellations, against 14% on the App Store.
- Hard paywalls convert 5× better by day 35 (10.7% against 2.1%) with the same 1-year retention (27% against 28%).
- Trials of 17–32 days convert 42.5%, under 4 days 25.5%.

**For Glyf.** Arpit decided no trial (14 Oct); the numbers above say that if a trial is ever tried, a long one beats a short one.
- Make yearly the highlighted plan.
- Turn on Play's grace period and account hold, and show an in-app "Payment didn't go through · Fix" banner.
- For yearly buyers, a day-3 check-in that shows what they used.

**Expected impact.** Revenue: recovers lost Android renewals and lifts average revenue per payer.

### 10. "Reply to what you copied"

**Evidence.**
- Context-aware replies are a common ask (a Samsung community feature request; a crowd of "AI reply" keyboards) [R33]. iOS doesn't let a third-party keyboard read the chat: Apple's Smart Reply only works when the messaging app hands over a conversation context [R32]. Reply keyboards make people paste the message [R33].
- Acti's reviewers note some Skills need the text copied first [R9].

**For Glyf.** The clipboard history is already on the strip.
- When the newest clip looks like a received message and the text field is empty, offer "Reply: Yes / No / Later · ✨" chips from it.
- One tap writes a reply in the person's tone profile.
- Don't use Android's Accessibility API to read screens: Play restricts it and it would undo the trust work in 3.

**Expected impact.** Retention (messaging is the most frequent typing) and AI runs, which drive upgrades.

### 11. Skills people make and share

**Evidence.**
- Acti's early testers built over 1,000 Skills in under two weeks, from plain-language descriptions, with a public marketplace [R8].
- Prompt-template keyboards sell a lifetime unlock for saved prompts with variables [R44].

**For Glyf.** The Skills hub and Builder exist.
- Add a share link: tryglyf.com/s/… shows what the Skill does and opens it in Glyf.
- Show installs on each Skill, plus a "Made by you" shelf.
- GO-TO-MARKET item 4 covers the growth side. The retention side matters too: every Skill a person makes is a reason not to switch keyboards.

**Expected impact.** Retention at day 30 and beyond (personal investment), plus acquisition through shares.

### 12. Multilingual typing and language switching

**Evidence.**
- Typing two languages without switching layouts is a long-running request on open keyboards [R34].
- Gboard corrects and predicts from any enabled language without the globe key, FUTO does the same [R34], and Rambler switches language mid-sentence [R7].

**For Glyf.** The typing engine is English only (`en.glyd`). Glyf is a global product, but anyone who mixes languages will leave on day 1.
- Use the funnel's install countries to pick the first two or three languages.
- Then add auto-detection per word, so there is no globe tap between languages.

**Expected impact.** Activation outside English-only users. Large effort, so it ranks below the cheaper wins.

### 13. A weekly recap

**Evidence.**
- Grammarly's Monday "Insights" email reaches 50M+ users, keeps a weekly streak, and is run as a retention tool [R31].
- People look at their keyboard about 180 times a day (Fleksy, 2015) [R30] (old, vendor). The use is there; it just isn't visible.

**For Glyf.** A Monday notification and a Home card, counted on the phone only: "This week: 34 answers, your address filled 6 times, 3 Meet links, ~12 minutes saved." Free users also see "you used 41 of 50 runs".

**Expected impact.** Retention at day 30, and proof of value right before people decide whether to keep paying.

### 14. Teach one hidden gesture at a time

**Evidence.**
- A steep learning curve is Typewise's main complaint [R1].
- Glyf's best features (hold space, glide on space, the g menu, Skills) are invisible gestures, as Acti's are [R9].

**For Glyf.** No explainer lines under settings (Arpit's rule). Teach in the strip, once, at the moment it helps:
- after a long message: "Hold space to clean this up";
- after a typo fixed by hand twice: "Slide on space to move the cursor".

Each tip appears once, is dismissable, and comes from the keyboard. Track the features each person has used.

**Expected impact.** Retention at day 7: people who find hold-space are the ones who pay.

### 15. "Why did my keyboard change?"

**Evidence.**
- iOS forces Apple's keyboard in password and other secure fields, some apps block third-party keyboards, and the keyboard may not load on a locked phone [R36].
- People read this as the app being broken. Wispr's help pages spend sections on it [R5].

**For Glyf.**
- When the ping shows Glyf hasn't appeared for two days after daily use, send one notification: "Glyf got switched off — tap to see how to get it back". It opens a 3-step screen: the globe, hold to pick, or remove other keyboards.
- A help row: "Why Apple's keyboard shows in passwords".

**Expected impact.** Retention. It wins back people who never decided to leave.

---

## 1. Competitors in 2026

| Keyboard | Best-loved | Price | What users praise / complain |
|---|---|---|---|
| **Gboard** | Glide typing, voice typing, built-in search, clipboard (text and images), Emoji Kitchen [R46]; on-device proofread and rewrite (Gemini Nano) [R11]; Rambler AI dictation, May 2026, Android only [R7] | Free | Praise: the most polished all-rounder, multilingual. Complaints: Google and privacy, occasional lag, stubborn autocorrect [R1] |
| **SwiftKey** | Prediction that learns your style, themes [R1] | Free | Copilot and Compose removed; only Editor (proofreading) remains [R10]. Complaints: autocorrect overriding correct words, lag, development slowed [R1] |
| **Apple keyboard + Writing Tools** | Free system rewrite, proofread, summarise; iOS 27 adds system dictation built on a Gemini-derived model [R6]; smarter autocorrect expected [R45] | Free | iOS 26 missed-letter backlash, fixed in 26.4 [R2][R3]; weak perceived impact of Writing Tools in one poll [R12] |
| **Grammarly Keyboard** | Grammar and tone fixes in any app, now with speech-to-text [R13] | Free: 100 AI prompts a month. Pro about $12/mo yearly or $30/mo; US in-app $29.99/mo, $139.99/yr (Mar 2026) [R13][R14] | 4.7★ from about 210K ratings [R14]. Complaints: best suggestions behind Premium, constant upsells, lag and dropped keystrokes [R1][R38] |
| **Fleksy** | Speed, privacy stance, extensions [R1] | Free | The company now sells a keyboard SDK to businesses (B2B) [R18]; the consumer app is a sideline. Complaints: weaker prediction [R1] |
| **Typewise** | Hexagon layout, offline/private, undo-friendly; a separate fully offline app [R16] | Pro $1.99/mo or $9.49/yr US; lifetime about $25 [R16] | Learning curve [R1]. The company moved to B2B customer-service AI in 2022 [R17] |
| **Acti** | Agentic keyboard (Jun 2026): Skills made in plain language, a public Skills marketplace, Gemini models, local-first [R8] | Free with credits; subscriptions planned [R8][R9] | $5.3M seed (BITKRAFT). Reviewers like quick lookups (map links, Wikipedia); some Skills need text copied first [R9] (directory) |
| **Wispr Flow** (voice keyboard) | Clean dictation: fillers removed, formatted for the app [R41] | Free 1,000 words/week on iPhone; Pro $15/mo or $143.99/yr [R21] | $280M Series B, Sep 2026 [R22]. iPhone needs an app bounce, worse since 26.4; crash reports [R5] |
| **CleverType** | Grammar, rephrase, translate, 30+ AI tools [R19] | Freemium; about $5.99/mo or one-time $6–60, sources disagree [R19] | Some reviewers call the subscription too expensive [R19] |
| **KeysAI** and the "AI Keyboard" clones | Grammar fix, chat in keyboard | $2.99/week, $29.99/yr, $59.99 lifetime [R20] | Small review bases; legitimacy concerns in about 29% of reviews [R20] (aggregator) |
| **Clavier AI**, ViVi, Wave and similar | ChatGPT in keyboard, captions, fonts | Weekly plans $4.99–6.99 [R28] | "Scam" perception from aggressive paywalls [R28] |

"Rewind-style" keyboards: nothing found that records everything typed as memory. Given the privacy evidence above, that is a gap to leave alone.

**Reading the field:**
- The two old independents (Fleksy, Typewise) moved to selling to businesses, and Microsoft pulled AI out of SwiftKey. Consumer keyboards are hard to monetise on rewriting alone.
- The 2026 money is in voice (Wispr) and agents in the keyboard (Acti).
- Google and Apple are now shipping both, free, so Glyf's edge has to be answers and actions they don't do, on both platforms, with trust.

## 2. Recurring complaints and what the best do

| Pain point | Evidence | What the best do | Glyf's answer (item) |
|---|---|---|---|
| Autocorrect quality | #1 complaint, 26% of bad reviews; names mangled [R1]; iOS 26 backlash [R2] | Gboard: long-press to forget a word, synced dictionary; SwiftKey: learns your style [R34][R1] | Undo chip, names safe, release gate (1) |
| Lag and dropped keys | 21% [R1]; Grammarly "laggy" [R38] | Microsoft: memory headroom, reload after a switch [R42] | Device profiling (1, 2) |
| Full Access / privacy | 18% [R1]; Apple's warning text [R23]; setups abandoned [R24] | Grammarly explains it plainly [R15]; Typewise ships a fully offline app [R16]; Gboard on-device [R11] | Late ask, primer, AI receipt, Private (3); on-device tier (7) |
| Keyboard disappears / globe | Silent kills [R4]; secure fields force Apple's keyboard [R36]; Wispr crashes on 26.4 [R5] | Help pages; keeping Apple's keyboard installed as a fallback [R36] | Termination count (2), switched-off nudge (15) |
| No dictation on iPhone | No mic in keyboard extensions even with Full Access [R25]; the app bounce got worse in 26.4 [R5][R6] | Wispr: app bounce with a "Flow Session" [R41]; Gboard on Android: in-keyboard Rambler [R7] | Android in-keyboard voice; iPhone cleanup of Apple's dictation (5) |
| Battery | No reliable 2026 measurement found; Microsoft asks for reports above 1% drain [R42] | — | Keep the extension idle-light; covered by 2 |
| Learning curve | Typewise's top complaint [R1] | Gboard: tips in settings | One tip at a time (14) |
| Subscriptions | Paywalled basics 16% [R1]; weekly-plan "scam" reviews [R28] | Grammarly: generous free core, AI metered [R13]; Typewise: lifetime option [R16] | Meter only AI, no weekly plans (8), yearly-first (9) |

## 3. Retention patterns

No keyboard company publishes cohort retention. Fleksy claims 55% 30-day retention for its SDK clients, with no method given [R43] (vendor). General day-30 medians are 3–7% for all apps (GO-TO-MARKET §6). What follows is the assistant's synthesis of the evidence above.

- **Day 1: does it type as well as the stock keyboard?** Mistakes and lag are the top reasons for bad reviews [R1]. A first win in the first session predicts day-30 use 2–3× [R29]. Items 1, 2 and 4.
- **Day 7: is there a habit?** The keyboard is seen many times a day [R30]. People stay when something useful shows up without being asked (strip answers, autofill from the vault, the clipboard) and when they find the hidden power (hold space). Items 13 and 14.
- **Day 30: is there investment and proof?** Learned words, vault entries, Skills and a tone profile are switching costs. A weekly recap shows the value [R31]. Paid users who see what they used stay; 35% of yearly cancellations happen in month 1 [R26]. Items 9, 11 and 13.

**Onboarding practices for keyboard apps:**
1. Add the keyboard first. Show the real Settings path as screenshots (iOS deep links into Settings are dead on iOS 26).
2. Give a win before asking for Full Access.
3. Prime Full Access with a plain explainer [R24], and show what is sent [R15].
4. Practise on a field inside the app.
5. Put the paywall after the first win.
6. Ask for sign-in only when an account is needed.

**Activation metrics** (in addition to GO-TO-MARKET §6):
- time to first strip answer;
- keyboard appearances a day per active user (from the ping);
- days Glyf was switched off after being active (ping gaps);
- share of people still on Glyf as the default keyboard at day 7;
- AI runs per active week;
- free users reaching 80% of the weekly cap.

## 4. Monetisation that works

- **Free core, metered AI, generous enough to form a habit.** The pattern across Grammarly (100 prompts a month free) [R13], Wispr (1,000 words a week) [R21] and Acti (credits) [R9]. Glyf's 50 runs a week sits at the generous end, which is right for a keyboard.
- **Users accept limits on AI, not on typing.** Complaints concentrate on paywalled basics and weekly plans [R1][R28].
- **Pay for what is unique.** Voice ($12–15 a month) [R21] and actions [R8] hold value; rewriting doesn't, since it is free in the OS [R10][R11].
- **Yearly beats monthly for AI apps,** which churn faster on monthly [R26]. A lifetime option is common among keyboards [R16][R20][R44]. For Glyf, a lifetime price is safe only for parts with no AI cost (themes, games), not AI runs.
- **Recover Android renewals.** Play billing failures cause 31% of cancellations [R26].
- **Teams** (invoiced outside the App Store) are where Typewise and Fleksy found revenue [R17][R18]; GO-TO-MARKET covers a pilot.

## 5. Gaps nobody does well

1. **Voice that acts, on every Android phone.** Rambler cleans speech on Pixel and Galaxy first [R7]; nobody turns speech into keyboard actions (vault fill, booking, payments).
2. **AI on iPhone without Full Access.** Every AI keyboard needs the network. An on-device model in the keyboard, if Apple allows it [R35], would be a first.
3. **Replies with context, without reading people's chats.** Today it is paste-only [R33] or app-supplied [R32]; the clipboard-first approach (item 10) is open.
4. **Undoable, explainable autocorrect.** It is still the #1 complaint after a decade [R1].
5. **Typing in two languages without the globe** on iPhone keyboards outside Gboard [R34].
6. **Visible privacy.** Everyone writes a policy; nobody shows a per-request receipt (item 3).
7. **A keyboard that says when the OS switched it off** and helps people back (item 15).

---

## Sources

- [R1] Unstar, 1–3 star review analysis of Gboard, SwiftKey, Grammarly, Fleksy, Typewise (2026): https://unstar.app/blog/gboard-swiftkey-grammarly-fleksy-typewise-keyboard-apps-ranked-2026
- [R2] TechRadar, iOS 26 autocorrect broken: https://www.techradar.com/phones/ios/youre-not-bad-at-typing-ios-26s-autocorrect-is-broken-and-theres-still-no-fix-in-ios-26-2
- [R3] MacRumors, iOS 26.4 keyboard fix (18 Mar 2026): https://www.macrumors.com/2026/03/18/ios-26-4-iphone-keyboard-bug-fix/
- [R4] Apple Developer Forums, keyboard extensions silently killed on iOS 17+: https://developer.apple.com/forums/thread/743534
- [R5] Wispr Flow help, setting up the iPhone keyboard (26.4 behaviour, known problems): https://docs.wisprflow.ai/articles/7453988911-set-up-the-flow-keyboard-on-iphone
- [R6] TechCrunch, Apple introduces systemwide dictation in iOS 27 (8 Jun 2026): https://techcrunch.com/2026/06/08/apple-introduces-systemwide-dictation
- [R7] TechCrunch, Gemini-powered dictation (Rambler) in Gboard (12 May 2026): https://techcrunch.com/2026/05/12/google-adds-gemini-powered-dictation-to-gboard-which-could-be-bad-news-for-dictation-startups/
- [R8] TechCrunch, Acti puts AI agents into your keyboard (30 Jun 2026): https://techcrunch.com/2026/06/30/acti-puts-ai-agents-directly-into-your-smartphone-keyboard/
- [R9] ToolDirectory, Acti review (free, credits; reviewed 8 Jul 2026): https://tooldirectory.ai/tools/acti
- [R10] Microsoft Support, FAQs for Copilot changes in SwiftKey: https://support.microsoft.com/topic/faqs-for-copilot-changes-in-swiftkey-c02289e6-c5b3-401c-af8d-f6c88409a2d2
- [R11] Android Authority, Gboard writing tools upgrade: https://www.androidauthority.com/gboard-writing-tools-upgrade-3668502/ and https://www.androidauthority.com/gboard-writing-tools-other-android-phones-3593589
- [R12] TidBITS, Apple Intelligence sees weak adoption (reader poll, Jun 2025): https://tidbits.com/2025/06/20/do-you-use-it-apple-intelligence-sees-weak-adoption/
- [R13] Grammarly plans: https://www.grammarly.com/plans
- [R14] App Pricing Lab, Grammarly iOS in-app purchases: https://apppricinglab.com/iap/apple/1158877342 ; App Store listing: https://apps.apple.com/us/app/1158877342
- [R15] Grammarly Support, why the keyboard needs Full Access on iOS: https://support.grammarly.com/hc/en-us/articles/115000730091-Why-Grammarly-Needs-Full-Access-on-iOS
- [R16] Typewise support and App Store listing: https://typewise.app/support/ ; https://apps.apple.com/us/app/id1470215025
- [R17] Wikipedia, Typewise (pivot to B2B, 2022): https://en.wikipedia.org/wiki/Typewise
- [R18] Fleksy, sunsetting FleksyArt to focus on B2B: https://fleksy.com/blog/fleksy-sunsets-its-fleksyart-marketplace-to-double-down-on-b2b
- [R19] CleverType App Store listing and AlternativeTo: https://apps.apple.com/us/app/-/id6560110828 ; https://www.alternativeto.net/software/clevertype/about/
- [R20] JustUseApp, KeysAI reviews and prices: https://justuseapp.com/en/app/6477995307/keysai-ai-typo-fix-keyboard/reviews
- [R21] App Pricing Lab, Wispr Flow prices: https://apppricinglab.com/iap/apple/6497229487 ; Spokenly, Wispr Flow pricing (iPhone word cap): https://spokenly.app/blog/wispr-flow-pricing
- [R22] The Bridge, Wispr Series B $280M (Sep 2026): https://thebridge.jp/2026/09/wispr-flow-series-b-280m-funding
- [R23] Apple Developer, configuring open access for a custom keyboard: https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard
- [R24] Dictus (open-source iOS keyboard), issue #704 "explain Full Access before the keyboard step": https://github.com/getdictus/dictus-ios/issues/704
- [R25] Apple Developer Forums, keyboard mic access request (2026): https://origin-devforums.apple.com/forums/thread/843118
- [R26] RevenueCat, subscription app trends and benchmarks 2026: https://www.revenuecat.com/blog/growth/subscription-app-trends-benchmarks-2026
- [R27] Adapty, State of paywalls 2026: https://adapty.io/state-of-paywalls/report/
- [R28] Marlvel, Wave AI Keyboard review analysis: https://marlvel.ai/apps/wave-ai-keyboard-fonts-skins ; Adapty paywall library, ViVi Keyboard: https://adapty.io/paywall-library/vivi-keyboard/
- [R29] Userpilot, app retention strategies (UXCam first-session data): https://userpilot.com/blog/app-retention-strategies/
- [R30] TechCrunch, Fleksy deep linking (180 keyboard looks a day, 2015): https://techcrunch.com/2015/08/13/fleksy-adds-deep-linking-to-its-keyboard-app-opening-new-revenue-opportunities
- [R31] Grammarly Support, weekly Insights reports: https://support.grammarly.com/hc/en-us/articles/360003816132-How-do-you-create-the-weekly-Grammarly-Insights-reports-I-get-in-my-email ; Failory, recap emails: https://newsletter.failory.com/p/surprising-effectiveness-recap-emails
- [R32] Apple Developer, adopting Smart Reply in a messaging app: https://developer.apple.com/documentation/uikit/adopting-smart-reply-in-your-messaging-or-email-app
- [R33] ReplyAI Keyboard listing (paste-only context): https://apps.apple.com/us/app/-/id6755236899 ; Samsung community, contextual smart reply request: https://eu.community.samsung.com/t5/suggestion/keyboard-feature-suggestion-contextual-smart-reply/m-p/12233203/highlight/true
- [R34] GrapheneOS forum, autocorrect languages independent of layout: https://discuss.grapheneos.org/d/4985-feature-request-auto-correction-languages-independent-from-keyboard-layout ; FUTO Keyboard, languages and models: https://docs.keyboard.futo.org/settings/languagesmodels
- [R35] Apple Developer Forums, using FoundationModels in extensions: https://developer.apple.com/forums/thread/833575
- [R36] iMore, keyboard switching back to Apple's: https://www.imore.com/does-your-keyboard-keep-switching-back-apples-heres-fix ; MacRumors forum, locked-phone keyboard: https://forums.macrumors.com/threads/1783069
- [R37] Stack Junkie, keyboard apps and keystrokes (ai.type breach): https://www.stack-junkie.com/blog/keyboard-apps-sending-keystrokes-to-servers
- [R38] JustUseApp, Grammarly keyboard reviews: https://justuseapp.com/en/app/1158877342/grammarly-grammar-keyboard/reviews
- [R39] Yaps, best AI keyboards for iOS (vendor, Aug 2026): https://www.yaps.ai/blog/best-ai-keyboards-ios
- [R40] Android Authority, Gboard Rambler: https://androidauthority.com/gboard-rambler-gemini-intelligence-3665653
- [R41] 9to5Mac, Wispr Flow on the iPhone keyboard: https://9to5mac.com/2025/06/30/wispr-flow-is-an-ai-that-transcribes-what-you-say-right-from-the-iphone-keyboard/
- [R42] Microsoft Support, SwiftKey performance troubleshooting: https://support.microsoft.com/en-us/topic/cc372cce-07c2-480c-a452-76bbf5bbce55
- [R43] Fleksy developers page (55% 30-day retention claim): https://www.fleksy.com/developers
- [R44] hunted.space, AIKbd (prompt templates, lifetime unlock): https://hunted.space/product/aikbd
- [R45] 9to5Mac, iOS 27 autocorrect feature (31 Mar 2026): https://9to5mac.com/2026/03/31/ios-27-might-give-iphones-keyboard-a-new-autocorrect-feature/
- [R46] Android Central, top Gboard tips: https://androidcentral.com/apps-software/top-gboard-tips-and-tricks

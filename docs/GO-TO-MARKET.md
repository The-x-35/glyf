# Go to market: how Glyf gets users and makes money

Written 14 Oct 2026 after Arpit asked: "research on how we should distribute it and all too, we need to make it a successful revenue making startup". It draws on web research done that day: competitors, keyboard distribution channels, subscription benchmarks, crypto distribution and App Review rules. It also draws on what the repo says exists: PROJECT.md, APPS.md, WEBSITE.md, STRIP-BACKLOG.md, SERVER-INVENTORY.md, BACKEND.md 5.9 and OPEN-ITEMS.md. Sources are numbered [S1], [S2] … and listed at the end. Figures from vendors or single sources are marked (unverified).

Nothing in the code was changed. This page is a plan and a set of recommendations, and every decision in it is Arpit's.

---

## Do this first

These are the five moves with the most effect for the least money, in order.

**1. Fix and measure the setup funnel before anything else.** A keyboard app loses people in three places:
- adding the keyboard in Settings;
- turning on Full Access;
- the first real use.

No company publishes these drop-off rates [S41], and Glyf doesn't measure them yet either: the app logs onboarding steps, but nobody records whether the keyboard was added, whether Full Access is on, or the first strip answer and first AI run.

What to do:
- Add those four events, counts only.
- Lead with what works without Full Access (typing, the strip's on-phone answers, the vault, the clipboard).
- Ask for Full Access only at the moment AI is needed.
- Publish a plain "What leaves your phone" page, as Grammarly and SwiftKey do [S5][S11].

Every other channel feeds this funnel, so a leak here wastes all of them.

**2. Lead with what Apple and Google don't do.** Rewrite, proofread, smart replies and translation are now free and built in:
- Apple Writing Tools, and "Write with Siri" in iOS 27 [S12][S13];
- Gboard with Gemini Nano [S7][S8];
- Samsung Writing Assist [S15].

Glyf should not lead with them. Its edge is answers and actions while you type, without opening another app. None of the built-in keyboards does these [S13][S15]:
- "split $84 four ways" → $21;
- "$aapl" → the price;
- "where should we eat" → a place card;
- "when are you free" → your booking link;
- "hop on a call?" → a Meet link;
- your address from the vault.

The line for the store and videos: **"The keyboard that answers while you type."**

**3. Start a daily short-video habit now, and do the store page properly.** A keyboard demonstrates itself in a 10-second screen recording. Typing apps have gone viral this way:
- Paste Keyboard reached #4 in the US App Store from TikTok alone [S87];
- a fonts keyboard grew on its own TikTok account [S88];
- rizz-reply apps drew hundreds of millions of views with text-conversation videos (unverified) [S89].

The plan:
- Post one or two screen recordings a day on TikTok, Reels and Shorts, from now through launch.
- Build the store page around long-tail searches ("rewrite text", "text expander", "currency converter keyboard"), not "keyboard". Gboard, SwiftKey and the theme apps own "keyboard" [S82].
- Add Custom Product Pages for each kind of searcher; since 2025 these can be tied to keywords [S83].

**4. Get the paywall and price right before the first real buyer.**
- **Where the paywall goes.** Most subscription decisions happen on install day. In Productivity, 78% of trial starts are on day 0 [S42]. So the paywall belongs at the end of onboarding: one clear offer, a 7-day free trial on the yearly plan, and no trial on/off switch (Apple rejects those since Jan 2026 [S48]). A second paywall appears when the day's free runs run out.
- **The price.** At $2 and $5, Glyf is a fifth of the typical North American monthly price ($9.99 [S42]). Apps priced higher convert better, not worse: 2.8% against 1.4% [S42]. AI apps earn about 41% more per payer [S43].
- **What to do.** Launch at today's prices as a founding price. Then test Plus $4/$40 and Max $8/$80 on new users in month 2. Apple can keep existing subscribers on their old price.

**5. Open the Solana side door. It is nearly free, because Mobile Wallet Adapter is already built.**
- Put the Android build on the Solana dApp Store: no store fee, 1,500+ apps, 150k+ Seeker phones [S63][S65][S66].
- Apply for the Superteam / Solana Foundation India grant (up to $10k, consumer and AI listed as focus areas) [S70].
- Enter the next Colosseum hackathon. The winners' path leads to a $250k accelerator place [S72][S73].

This brings money and a first core of daily users who type tickers and addresses all day, which is exactly what the money chip and Pay panel do. Keep crypto low-key on iOS for now (see Risks).

**Before launch day (not growth, but launch fails without these):**
- Clear the App Review questions in the Risks section: 4.4.1 for keyboards, 3.1.5 for the wallet.
- Finish Google's OAuth verification. Until Google verifies the sensitive scopes, Google sign-in shows an "unverified app" warning and stops after 100 new people (OPEN-ITEMS B12).
- Remove the debug launch argument that can write the decrypted vault to disk from release builds (OPEN-ITEMS C6).
- Fix the url.unfurl server-side request forgery risk (SERVER-INVENTORY problem 1).

---

## 1. Where Glyf stands today

**What it already has that helps distribution:**
- iPhone and Android keyboards are built. TestFlight build 20 is out, Google Play testing is running, and the website has a live waitlist.
- About 50 instant strip answers run on the phone, cost nothing to serve and need no network (STRIP-BACKLOG.md). These make a free tier cheap, and they are the best demo material.
- The website's 8 iMessage chat scripts (WEBSITE.md 3.6) are ready-made video scripts.
- Shareable surfaces exist: the public places page (`/p/:id`), booking links, the Skills hub with publishing, and gift codes (6-character, single use).
- The four subscriptions are created in App Store Connect and Ready to Submit (Plus $2/$20, Max $5/$50, 175 storefronts). The Small Business Program means Apple takes 15%.
- The AI cost per user is known and capped in code: worst case $0.10 a month on Free, $0.48 on Plus and $1.20 on Max; a typical active user costs about $0.03 a month (BACKEND.md 5.9).

**What's missing for growth:**
- Keyboard-side activation events (keyboard added, Full Access, first strip answer, first AI run).
- Share links for glyfs and skills (APPS.md section 7 lists "no share links").
- A referral offer.
- A store page: screenshots, preview video, keywords.
- Plans are off sale (`Billing.onSale = false`) until the App Store release.

---

## 2. Competitors and what they teach

| Product | Price | How it got users | Numbers | What went wrong / lesson |
|---|---|---|---|---|
| **Grammarly** (bought Superhuman in July 2025 [S3]; parent renamed Superhuman, Oct 2025) | Free: 100 AI prompts a month. Pro about $12/mo billed yearly, $30 monthly (unverified) [S1] | Browser extension everywhere you type, freemium, heavy SEO, then selling to companies bottom-up [S4] | 40M+ daily users, $700M+ yearly revenue; $1B revenue-based financing, May 2025 [S2] | Its keyboard rides on a brand built on desktop. Its free tier is much smaller than Glyf's (100 a month against 20 a day) |
| **Gboard** | Free, bundled | Preinstalled on Android | 10B+ installs [S6] | Gemini writing tools only on flagship chips [S7]; custom instructions in beta [S8] |
| **SwiftKey** | Free | Bought by Microsoft for about $250M in 2016 [S9] | 300M+ installs at the time | Copilot and Compose were **removed** from the keyboard; users are sent to the Copilot app [S10]. A chatbot in the keyboard did not stick; actions inside the keyboard are a different bet |
| **Apple Writing Tools** | Free | Built into iOS | iPhone 15 Pro and later; 16 languages; not on devices bought in mainland China [S12] | Polishes selected text; does not act while you type. iOS 27 adds "Write with Siri" from the keyboard and grammar fixes [S13]; a Grammarly-style keyboard is rumoured, not decided [S14] |
| **Wispr Flow** (closest growth model) | Free: 2,000 words a week on desktop, 1,000 on iPhone. Pro $15/mo or $12/mo billed yearly. 14-day trial; students 50% off [S16][S23] | Founder posts on X and LinkedIn; unpaid endorsements from famous tech names; Product Hunt #1 of the day and week [S93]; creator video program; two-way referral (a free month each) and a 25% affiliate program [S21]; a team plan with a minimum of 3 seats; India pricing about $3.40 [S19] (unverified) | $280M Series B at a $2B valuation, Aug 2026; revenue up 150%+ a quarter [S17]. Founder said 19% of free users paid (June 2025) [S18] | Privacy row: a feature sent window screenshots to its servers and the user who found it was banned; the policy was rewritten [S24] (unverified). For a keyboard, trust is the product |
| **Typewise** | Consumer Pro $1.99/mo or $9.49/yr [S26] | Privacy keyboard | 65k users at soft launch | Switched to selling to companies (customer service AI) in 2022 [S25]. A consumer keyboard on its own was hard to make money from |
| **Fleksy** | — | — | — | Pinterest hired the team in 2016 [S28]; now a keyboard SDK licensed to others [S27]. Same lesson as Typewise |
| **Rewind / Limitless** | — | AI memory, pendant | Bought by Meta Dec 2025; recording switched off, subscriptions ended [S29][S30] | Users lost their data overnight. Glyf's on-phone vault plus an export is a selling point |
| **Raycast** | Free has no AI. Pro $10, Pro+ $20, Max $50 a month; teams $15–65 a seat (pricing changed 10 Sep 2026) [S31][S32] | Extension store (community building), Product Hunt, open source; 130 → 11k daily users in a year [S33][S34] | $30M Series B, 2024 | The store is the growth engine. Its iOS app now has its own keyboard with AI commands and snippets [S35], so it is a future competitor |
| **Acti** (direct rival) | Not public; "subscriptions planned" [S36]; lifetime codes on Product Hunt [S37] | Product Hunt; a Skill Hub seeded by 1,000+ tester skills before launch [S36] | $5.3M seed (BITKRAFT). CEO grew the Facemoji keyboard to 300M+ daily users [S36] | Same idea (hold space for AI, shared skills) with a funded team that has scaled a keyboard before. Glyf has to win on instant answers without AI, the wallet, both platforms at once, and price |
| **Willow Voice, Aqua Voice, Superwhisper** | Aqua $8/mo; Superwhisper about $8.49/mo or a lifetime licence (unverified) | Voice keyboards | Willow claims about 50% monthly growth (unverified) [S38] | Voice is the hot category, and Glyf already has dictation |
| **Weekly-priced AI keyboards** (Key AI, RizzKey and others) | $4.99–$9.99 **a week** [S39][S40] | Paid ads and TikTok | — | Weekly plans keep 3.4% of subscribers after a year, against 44.1% for yearly [S45]. Don't copy this |

**What follows for Glyf:**
1. Rewriting is now free everywhere, so lead with answers and actions.
2. Trust decides who wins a keyboard. Say exactly what is sent, before anyone asks.
3. A community store (Raycast, Acti's Skill Hub) drives growth, if each item can be shared as a link.
4. A consumer keyboard alone rarely makes money (Typewise, Fleksy). Revenue comes from subscriptions to power users, then teams.

---

## 3. Channels, ranked by impact and effort

| # | Channel | Impact | Effort | Cost | When |
|---|---|---|---|---|---|
| 1 | Setup funnel + Full Access trust | Very high (multiplies everything) | Medium | $0 | Week 1 |
| 2 | Short video (TikTok, Reels, Shorts) | Very high, uneven | Medium, daily | $0, later about $100–300 | Week 1 onward |
| 3 | App Store and Play listing (ASO) | High, compounds | Low–medium | $0 | Weeks 1–2 |
| 4 | Share loops inside the product (skills, places pages, booking links, referral) | High over time | Medium–high (build work) | $0 | Months 2–3 |
| 5 | Solana: dApp Store, grants, hackathon | Medium users, high cash for the effort | Low | $0 | Weeks 2–4 |
| 6 | Launch week: Product Hunt, Reddit, X | Medium (one spike) | Low–medium | $0 | Week 4 |
| 7 | Founder posting on X and LinkedIn | Medium | Low, daily | $0 | Ongoing |
| 8 | Paid-per-view clip campaigns | Medium | Low | Capped budget | Month 2 |
| 9 | Students | Medium | Low–medium | $0 | Month 2 |
| 10 | Affiliates (25–30% recurring) | Low–medium early | Medium | Revenue share only | Month 3 |
| 11 | Teams / B2B | Medium later | High | $0 | Month 3 pilot |
| 12 | OEM and carrier preloads | High at scale, out of reach now | Very high | — | Not now |

### 3.1 The setup funnel and the Full Access trust problem

**Why this comes first.**
- iOS warns at Full Access that the developer could send out everything you type.
- Apple requires a keyboard to work without Full Access (guideline 4.4.1 [S76]).
- No public number exists for how many people turn it on [S41]. Glyf has to measure its own.

**What the leaders do:**
- Grammarly's help page explains Full Access plainly: it checks only what you type while using it, and skips password and card fields [S5].
- SwiftKey says nothing typed is sent without an account [S11].

Glyf already has the right behaviour (APPS.md 4: typing, the vault and the clipboard work without Full Access, and no secure fields are touched). It just doesn't say so in the places people decide.

**Do:**
1. **Measure.** Add these counts-only events:
   - `kb_added` (the app sees the keyboard's ping);
   - `full_access_on` (`hasFullAccess` in the ping);
   - `first_strip_answer` (the keyboard writes a flag the app reads);
   - `first_ai_run` (the server already meters runs per account).

   Then build one funnel view: installs → onboarding done → keyboard added → Full Access → first strip answer → first AI run → day-7 use. Today `/telemetry/funnel` is public and unused (BACKEND.md 16 #13); make it private and use it.
2. **Earn it in order.** Put the keyboard in before asking for Full Access. Let the first win come from the strip, which needs no network for sums and units. Only then ask: "Turn on Full Access for AI. Here is exactly what is sent."
3. **"What leaves your phone"** as a short page on tryglyf.com and a sheet in the app, in a table:

   | What | Leaves the phone? | When |
   |---|---|---|
   | Typing, autocorrect, learned words | Never | — |
   | Strip sums, units, dates | Never | — |
   | Vault | Never; encrypted on the device | — |
   | AI requests | The text you chose to act on | Only when you ask |
   | Secure fields | Never touched | — |

   Add: "AI providers are told not to keep or train on it" (true since 2 Oct, BACKEND.md 5.10).
4. **App Store privacy label and screenshots.** One screenshot says it: "Works without Full Access. AI only when you ask."

### 3.2 Short video

**Evidence:**
- Paste Keyboard: 854k downloads in 6 days, #4 in the US App Store, no ads, all from TikTok [S87].
- A fonts keyboard grew on its own account by repeating one tutorial-plus-payoff format [S88].
- Rizz-reply apps used faceless accounts with text-conversation videos (about 550M views claimed, unverified) [S89].
- Cluely's "cheat on everything" controversy got attention but brought backlash and retractions [S90]. Avoid it.

**Formats that fit Glyf.** Each is a 7–15 second screen recording in an iMessage-style chat, with the payoff in the first 1–2 seconds and captions on (store previews autoplay muted, and people watch about 5 seconds [S85]):
- "POV: your keyboard does the math": "split $84 four ways" → $21 chip → sent.
- "Things my keyboard does that yours can't": $aapl price, a Meet link, an address from the vault, a café card. One feature per cut.
- "Texting Mom where to meet": hold space → a place card with a map. These are the website's chats; WEBSITE.md 3.6 has the scripts.
- "Rate my keyboard setup": glide typing, then the strip answering.
- "Crypto Twitter" version: "send 5 USDC to …" inside the chat. Post this on X and in Solana spaces only.

Keep it global with US examples ($, US places, "Mom"), as the product rules already say.

**Rhythm:**
- Run one account per platform: TikTok, Instagram, YouTube Shorts, X.
- Post 1–2 videos a day, the same video everywhere.
- After 30 posts, keep the 3 formats with the best 3-second hold and drop the rest.

**Paid, later.** Pay-per-view clipping (Whop Content Rewards) costs about $1 per 1,000 views, with a budget cap you set [S92]. That is cheaper than paying a creator $100–300 a video [S91]. Start at $100 in month 2, and only once one format has proved itself organically.

### 3.3 App Store and Google Play listing (ASO)

**How ranking works:**
- **iPhone:** Apple ranks on the title, subtitle, keyword field and category, plus downloads and ratings. The description is not indexed [S82].
- **Google Play:** indexes the title, the 80-character short description and the full description.
- **Tags:** Apple's AI-generated tags (from WWDC25) also put apps into searches and collections [S84].
- **Custom Product Pages:** up to 35 alternative store pages. Since 2025 each can be tied to keywords, so the right searchers see the right page [S83].

**A first pass to try:**
- **Name:** "Glyf: AI Keyboard" (already set in App Store Connect).
- **Subtitle (30 characters):** "Answers, rewrites and actions" (29).
- **Keyword field (100 characters, no words already in the name):** `rewrite,reply,grammar,translate,snippets,expander,clipboard,calculator,currency,swipe,mail` (90). Add `solana` only if the wallet stays visible on iOS.
- **Google Play short description:** "The AI keyboard that answers while you type: sums, places, rewrites, links." (75)
- **Screenshots:** the first three are what search results show. Use real content, not empty states, with a 3–5 word headline each:
  1. "Your keyboard does the math"
  2. "Find places mid-chat"
  3. "AI when you hold space"
  4. "Your details, one tap"
  5. "Works without Full Access"
- **Preview video, 15–20 seconds:** the strip answer in the first second, then hold space → place card, then a Meet link.
- **Custom Product Pages, one per kind of searcher:**
  - AI replies and rewrites;
  - calculator and currency;
  - privacy and vault;
  - productivity (snippets, clipboard, booking links);
  - crypto (Android and Play only at first).
- **In-App Events** (cards that can appear in search; up to 31 days each, a few live at once [S86]). Run one for every feature drop: "New: glide typing", "New: 50 instant answers". They give the listing something new to surface.
- **Ratings:**
  - Ask after a success, using Apple's own prompt (for example, the third strip answer used).
  - Never gate features behind a review, and never pay for ratings (guideline 3.2.2 [S76]).
- **Head-term competition:** Gboard has 10B+ installs [S6]; on Google Play SwiftKey shows 1B+ and Facemoji 100M+. Don't spend effort on the word "keyboard" alone.

### 3.4 Share loops inside the product

These are ordered by how naturally each one spreads.

1. **Skills hub on the web.**
   - Give every published skill a page: `tryglyf.com/s/<id>`, with a short GIF, the author, the install count and "Get it in Glyf".
   - The link opens the app and installs the skill (`glyf://` already exists).
   - This is Raycast's store and Notion's template gallery, which drove both [S34].
   - Seed it with 50 good skills before launch, as Acti did with 1,000+ tester skills [S36].
   - Let authors share their link.
2. **Places pages.** `/p/:id` already makes a public page when someone shares places from hold space. Put a quiet "Found with Glyf · Get the keyboard" line at the bottom. People open it because a friend sent it, so it reaches exactly the right audience.
3. **Booking links and Meet links** already go into chats. The booking slot page is Cal.com's, so leave it alone.
4. **Two-way referral: "Give a month, get a month".**
   - Dropbox's two-sided bonus took it from 100k to 4M users in 15 months [S96].
   - Wispr gives both sides a free month, but only after the friend dictates 2,000 words [S20].
   - Pay out only after the friend has used AI on 3 days.
   - How to pay it: Apple offer codes (one-time codes made in App Store Connect) are the safe route. Glyf's own gift codes unlocking a plan is the 3.1.1 grey area already noted in the gift-code work, so use them only on Android or for testers.
5. **"Sent with Glyf" signatures: don't.**
   - Hotmail's footer famously worked [S97].
   - But a line added to people's private chats reads as spam. Even "Sent from my iPhone" is widely deleted, and Ubuntu had to switch off "Sent from Ubuntu" after a backlash [S98].
   - If it ever appears, it is off by default, opt-in, and only on shared places pages and skill pages.

### 3.5 Solana: the side door

- **Solana dApp Store:**
  - No fee on purchases or subscriptions today [S63].
  - Submitting takes a signed APK, the listing, a Solana wallet and publisher identity checks [S64].
  - 1,561 apps by June 2026 [S65]; Solana Mobile says 175k+ Seeker phones sold [S66] (unverified).
  - Its policy follows Google Play's, and nothing found bans keyboards. Glyf's Android build already speaks Mobile Wallet Adapter, so it fits.
- **Seeker Seasons and SKR:**
  - Season 1 gave about 141M SKR to 188 developers who shipped a "quality app" [S68].
  - Season 2 (from Jan 2026) focuses on payments and trading [S67].
  - Ask Solana Mobile to feature Glyf as "the keyboard that pays".
- **Grants:**
  - Solana Foundation India / Superteam India: up to $10k (paid in USDG), about 30 days to an answer, for India-based builders; consumer and AI are listed [S70].
  - Superteam Moonshots: $20k for full-time founders building consumer apps [S71].
  - Solana Mobile Builder Grants: rolling, amounts not published [S69].
- **Colosseum:**
  - Hackathon prizes: $30k grand champion, $10k to each of the next 20 [S72].
  - The accelerator puts $250k into each accepted startup [S73] (reported at about 7% equity, unverified).
  - A consumer AI keyboard with a wallet is a strong entry.
- **Phantom:**
  - No formal partner programme was found.
  - Phantom Portal domain verification is needed to appear in its Explore tab, which lists web apps [S74].
  - Phantom has about 15M monthly users (Jan 2025) [S75].
  - Worth doing once the website has a wallet page.
- **On iOS, no tokens or points for tasks.** Guideline 3.1.5(v) forbids crypto apps paying currency for completing tasks [S76]. Keep any Seeker-only perks in the Android / dApp Store build.

### 3.6 Launch week: Product Hunt, Reddit, X

- **Product Hunt:**
  - Wispr Flow was #1 of the day and week with about 1,100 votes [S93].
  - In one founder survey, about half of launches brought 100–1,000 users, about 10% brought 2,000–5,000, and 16% saw no spike in sign-ups [S94].
  - Treat it as a backlink, press and early-adopter day, not mass reach.
  - Launch Tuesday to Thursday, with a 30-second video and the tagline "The keyboard that answers while you type".
  - Ask the waitlist to come and comment, but don't ask for upvotes; Product Hunt penalises vote rings.
- **Reddit:**
  - Use only the slots that allow it: r/iosapps' weekly promotion thread, r/SideProject, r/droidappshowcase, and r/iOSProgramming's "App Saturday" (one post per app a year) [S95].
  - r/androidapps bans app promotion outright [S95].
  - In big subreddits, answer "best keyboard" threads honestly and say you made it.
  - Never use alternative accounts.
- **X and LinkedIn:**
  - Post as the founder: build-in-public milestones and the videos.
  - Wispr's CEO did exactly this, alongside unpaid endorsements from people he onboarded himself [S19].
  - Pick 20 well-known iPhone, productivity and Solana people, give each a Max code and set them up personally.
- **Election day:** don't launch on Tue 3 Nov 2026. It is US election day and the news will drown it out.

### 3.7 Students

- **What others do:**
  - Perplexity gave students up to 2 years of Pro, plus a student-referral leaderboard [S99].
  - Wispr gives 3 free months with a student email, then 50% off [S22].
  - Nobody has published the results.
- **Cheap version for Glyf:**
  - Students text the most and live on TikTok.
  - Hand out Apple offer codes for 3 months of Plus through student clubs and college Discords.
  - Add .edu checking only if it takes off; SheerID-style verification costs money.
- **Skip campus ambassadors for now.** They take management time.

### 3.8 Teams and B2B (month 3 pilot, not before)

- **Prices to compare:**
  - Text Blaze Business: $6.99 a seat a month [S52].
  - TextExpander business: about $8–11 a seat (unverified).
  - Grammarly Business: about $12–15 a seat (unverified).
  - Raycast Teams: $15–65 a seat [S31].
  - These products spread bottom-up: individuals first, then the company buys.
- **The Glyf version: "Glyf for Teams", $6 a seat a month, at least 3 seats.** It includes:
  - shared glyfs;
  - shared snippets (pricing lines, booking links, support replies);
  - one bill.
- **Who to pilot with:** 3–5 small sales or support teams, invoiced by hand.
- **Billing:** a plan sold only to organisations for their staff may use payment outside Apple's in-app purchase (guideline 3.1.3(c) [S76]). So team billing can go through a web invoice (Stripe, Razorpay) without Apple's cut.
- **Don't build admin consoles, SSO or compliance until a pilot asks for it.**

### 3.9 Not now

- **OEM and carrier preloads.** Bobble's Mint keyboard is preloaded on Xiaomi phones and shares revenue with Xiaomi [S100]. Deals like that need scale, a sales team and low-end-Android markets, which is not a US-first launch.
- **Paid app-install ads.** Revenue per install is $0.38 on the App Store and $0.14 on Google Play (day 60) [S45]. Paid installs won't pay back at $2 to $5 prices.
- **Lifetime deals** (see 4.5).

---

## 4. Making money

### 4.1 Is $2 / $5 the right price?

Benchmarks:

| Benchmark | Figure | Source |
|---|---|---|
| Median monthly price, North America | $9.99 | [S42] |
| Median yearly price, North America | $39.99 | [S42] |
| Median monthly price, India and Southeast Asia | $3.75 | [S42] |
| Median yearly price, India and Southeast Asia | $18.32 | [S42] |
| Download → paid by day 35, high-priced apps | 2.8% | [S42] |
| Download → paid by day 35, low-priced apps | 1.4% | [S42] |
| First-year revenue per payer, AI apps | $30.16 | [S43] |
| First-year revenue per payer, non-AI apps | $21.37 | [S43] |
| Price tests that raised lifetime value | 45.5% of tests (even though only 28.3% raised conversion) | [S46] |
| Monthly plans still active after a year, low-priced | 22.5% | [S45] |
| Monthly plans still active after a year, high-priced | 12.2% | [S45] |

Closest products: Grammarly about $12, Wispr $12–15, Raycast Pro $10, Aqua $8, Typewise $1.99 (no AI cost) [S1][S16][S31][S26].

**Reading.** $2 is priced like Typewise, not like an AI tool. Cheap plans keep subscribers longer, but they don't convert better. And at $2 the business needs huge volume:

| Goal: $10k a month after Apple | Payers needed | Installs needed at 2% download → paid |
|---|---|---|
| Today's prices (blended about $2.50 net per payer: 70% Plus, 30% Max) | about 4,000 | about 200,000 |
| Plus $4 / Max $8 (blended about $4.40 net) | about 2,300 | about 115,000 |

**Recommendation:**
- Launch at $2/$20 and $5/$50 as the **founding price**: "Founding members keep this price." It is honest because App Store Connect lets a price rise leave existing subscribers on their old price.
- In month 2, with at least 1,000 installs a week, offer new users Plus $4/$40 and Max $8/$80. These follow Arpit's whole-number and "yearly = 10x" rules.
- Compare revenue per install at day 14, not conversion rate.
- In India and other cheaper storefronts, let Apple's regional price tiers do the work. Glyf already sets ₹199/₹499 by hand. Price parity for India is about 0.6 of the US [S46].

### 4.2 Trials, plans and the paywall

- **Trial:**
  - Offer a 7-day free trial on the **yearly** plans only.
  - Trials of 5–9 days convert 37.4% to paid, against 25.5% for 4 days or less [S42].
  - North American trials convert 34.2%, India and Southeast Asia 15.2% [S42].
  - A trial user costs at most about $0.30 of AI on Max (a quarter of the $1.20 monthly worst case).
- **Lead with yearly:**
  - AI apps lose subscribers faster: 21.1% of yearly AI plans are still active after a year, against 30.7% for other apps [S43][S44]. A yearly plan locks in the year.
  - Yearly plans keep 44.1% of subscribers after a year, monthly 17%, weekly 3.4% [S45].
  - Apps led by yearly plans earn $0.46 per install by day 60, monthly-led $0.24 [S42].
  - Never offer weekly.
- **Onboarding paywall:**
  - Put it at the end of onboarding, after the setup step, once the keyboard is on.
  - Use one screen and one clear offer, with the billed amount the most prominent price (3.1.2(c)) and no trial toggle [S48].
  - Multi-page onboarding paywalls converted 37% better than single-page ones in Superwall's data (12.41% against 9.07%) [S47]. A "here's what Max adds" second page is worth testing.
  - Closing it must be easy; Glyf's sheet already allows swipe-to-close.
- **Limit-hit paywall:**
  - When the day's runs are spent, the keyboard says "Out of AI runs today · Get Plus in Glyf". The runs chip already exists on the iPhone keyboard.
  - Freemium buyers come late: 23% convert after week 6 [S42]. This second moment matters.
- **What a hard paywall would mean:**
  - Hard paywalls convert 10.7% against 2.1% for freemium [S42], but a keyboard that must be paid for before it types won't spread.
  - Keep freemium. The on-phone strip answers stay free forever, because they cost nothing to serve.

### 4.3 Free-tier limits

- **What others give free:**
  - Grammarly: 100 AI prompts a month [S1].
  - Wispr: 1,000 words a week on iPhone, with a one-time bonus when first hit [S23].
  - Raycast: no AI at all [S31].
  - Glyf: 20 runs a day (about 600 a month), the most generous of the four.
- **Limits convert only if people reach them.**
- **The cost risk is the free crowd behind each payer.** At 2% conversion, each payer carries about 49 free users:
  - at the typical $0.03 a month each, that is about $1.47, almost all of a Plus payer's $1.70 net;
  - many installs go quiet, so the real figure is lower, but it is the number to watch.
- **Recommendation:**
  - Keep the strip answers and 100 AI suggestions a day free. They are what makes Glyf feel smart, and suggestions cost about $8 a million.
  - Test **50 AI runs a week** in place of 20 a day. It allows heavy days and makes the limit felt by the people most likely to pay.
  - Aim for 10–20% of weekly active free users hitting the limit at least once a week.
  - The limit is a code constant (`server/src/lib/limits.ts`), so it is easy to change.

### 4.4 The AI cost ceiling

- **Benchmarks:** AI companies run at about 52% gross margin, against 80–90% for classic SaaS; inference is about 23% of revenue at scaling AI companies [S54].
- **Ceilings for Glyf:**

  | Measure | Ceiling |
  |---|---|
  | All AI plus servers (Railway, Neon) | 25% of net revenue |
  | One payer, worst case | 30% of that payer's net |
  | Average free monthly active user | $0.03 a month |

- **Where Glyf is:** the payer worst case is already met and enforced by `test/limits.test.ts` (58–72% of the plan left, BACKEND.md 5.9).
- **What to add:** a weekly check of total AI spend (OpenRouter usage) ÷ net revenue, and of AI spend ÷ free monthly active users. If free users pass $0.03, lower the free limit before touching paid plans.

### 4.5 Lifetime deals: no

- AI apps have running costs, so lifetime pricing is a bet on future model prices.
- RevenueCat warns against it for apps with high per-user costs [S49]. MacroFactor refuses it for that reason [S50].
- AppSumo's revenue fell by half in two years, and AI token costs limit the deals it can run (secondary report) [S51].
- If a launch promotion is wanted, use a yearly plan at the founding price instead.

### 4.6 Crypto revenue: Jupiter's referral fee

- **How it works:**
  - Glyf calls Jupiter's Swap V2 `/order` (`app/lib/wallet/wallet_api.dart`).
  - Swap V2 replaced Ultra in March 2026 [S61]. Jupiter lets the app add `referralAccount` and `referralFee`, 50 to 255 basis points (0.5% to 2.55%). Jupiter keeps 20% of that fee [S60].
  - Setup is one referral account plus a token account for each coin the fee comes in (start with SOL and USDC).
  - If that token account is missing, the swap still goes through but pays no fee [S60].
  - All routers stay eligible with a referral; test that the routing is still good [S60].
- **What the market charges:** Phantom about 0.85% [S62]. A 0.5% Glyf fee is below Phantom's and nets Glyf 0.4%.
- **How much it could bring:** $100k a month of swaps through the keyboard brings about $400 a month; $1M brings about $4,000.
- **Recommendation:**
  - Turn it on first in the Android / dApp Store build.
  - On iOS, wait until the app is approved and the 3.1.5 position is clear (see Risks). A fee makes the app look more like an exchange to a reviewer.
  - Before any fee goes live, check on a real phone that Phantom signs Jupiter's v0 transactions over deeplinks (OPEN-ITEMS A10).
  - Say the fee on the Buy card ("Glyf fee 0.5%").

### 4.7 Affiliate revenue from search cards: later, and small

- **Amazon Associates:** allows apps only with approval, in free apps, and without showing Amazon pages in a web view [S55]. Links shown only to paying users likely break the rules.
- **Expedia:** pays up to 4% on hotels [S56].
- **Google Places:** the terms limit what can be done with its results, so read the current Maps terms before putting money links on place cards.
- **Track record:** no keyboard has shown meaningful affiliate income. SwiftKey's Bing search never reported revenue, and Fleksy's deep-link revenue gave way to SDK licensing [S27].
- **Treat it as upside after 50k monthly users, not a pillar.**

### 4.8 Selling outside the App Store

- **US link-outs:**
  - Apple's commission on US link-outs is in court. Apple proposed 15%, and 5% for small developers, in Aug 2026 [S57].
  - Google Play allows external offers in the US with its own fees from Oct 2026 [S59] (dates disputed).
- **Test result:** in RevenueCat's test, in-app purchase alone beat adding a web option, at Apple's 15% rate: $2.53 against $2.17 per user [S58].
- **Recommendation:** Glyf pays 15%, so stay in-app for individuals. Use web invoices only for team plans (3.1.3(c)).

---

## 5. The 90-day plan

For one founder with almost no budget. Today is Wed 14 Oct 2026. Total cash needed: about $300–500, mostly pay-per-view clips. Offer codes are free, and the Apple and Google accounts are already paid for.

### Week 1 (14–20 Oct): fix the base

- Add the activation events (3.1) and a private funnel view. **Build**
- Decide the App Review questions (section 7: Pay hand-off, wallet visibility on iOS, organization account). **Arpit**
- Pre-launch fixes: the release-build vault debug argument (C6), the url.unfurl fix, the Neon password rotation (W1). **Build + Arpit**
- Write the "What leaves your phone" page and in-app sheet. **Build**
- Store listing draft: subtitle, keywords, 5 screenshots, a 20-second preview video, Play short description. **Build drafts, Arpit approves**
- Start the 4 video accounts and post the first 7 videos from the website's chat scripts. **Arpit**
- Email the waitlist: "Launching soon. Want early access?" with the TestFlight public link and the Play testing link. **Arpit**

### Week 2 (21–27 Oct): submit and seed

- Turn the paywall on for release (`Billing.onSale`), set the yearly 7-day trial as an introductory offer, then submit v1.0 with the four plans to App Review. Only with Arpit's OK on the build number. **Arpit**
- Google Play: production release; finish Google OAuth verification (B12). **Arpit**
- Seed the Skills hub with 50 strong skills; build the public skill pages (`tryglyf.com/s/<id>`). **Build**
- Submit the Android build to the Solana dApp Store; apply for the Superteam India grant. **Arpit**
- Video: 1–2 a day. Note which 3 formats hold viewers longest. **Arpit**
- Line up 20 people to receive Max codes on launch day. **Arpit**

### Week 3 (28 Oct – 3 Nov): soft launch

- The App Store and Play releases go live quietly. Email the waitlist the store links. **Arpit**
- Watch the funnel every day; fix the worst step first (usually Full Access or "keyboard added"). **Build**
- Ask for ratings after a success, with the system prompt. **Build**
- Post nothing big on Tue 3 Nov (US election day).

### Week 4 (4–10 Nov): public launch

- Product Hunt (Wed 4 or Thu 5 Nov): 30-second video, founder comment, waitlist told to come and comment. **Arpit**
- The same day: r/SideProject, the r/iosapps promotion thread, r/droidappshowcase, a founder thread on X, LinkedIn. **Arpit**
- An App Store In-App Event: "Glyf launch: 50 instant answers". **Arpit**
- The 20 hand-picked people get their Max codes and a personal setup. **Arpit**
- End of week: first numbers review against the targets in section 6.

### Month 2 (11 Nov – 10 Dec): find the engine

- The price test for new users (Plus $4/$40, Max $8/$80) once there are 1,000+ installs a week; compare revenue per install at day 14. **Arpit decides, Build wires the paywall to choose by cohort**
- The free-limit test (20 a day against 50 a week). **Build**
- Places pages get the quiet "Found with Glyf" line; skill pages get install counts and author links. **Build**
- One In-App Event per feature drop (every 2–3 weeks).
- Video: keep the best 3 formats; start a $100 pay-per-view clip campaign on the best one.
- Student offer: Apple offer codes for 3 months of Plus through 5–10 college clubs and Discords.
- Turn on the Jupiter referral fee in the Android build after the real-phone check. **Build + Arpit**
- Enter the next Colosseum hackathon if one is open.
- Black Friday / Cyber Monday (27–30 Nov): a yearly-plan offer through an App Store In-App Event.

### Month 3 (11 Dec – 12 Jan): add loops, then teams

- Two-way referral ("give a month, get a month" via Apple offer codes, paid after 3 days of AI use). **Build**
- An affiliate program at 25–30% of revenue for 12 months (the norm [S101]), only if a creator asks or a format clearly works. Linkrunner's free tier covers install tracking [S102]. **Arpit**
- Glyf for Teams pilot with 3–5 small teams, invoiced by hand. **Arpit**
- New Year's resolution content ("type less in 2027") and an In-App Event.
- End-of-quarter review: keep the channels whose cost per payer is below a payer's first 3 months of net revenue (about $5 at today's prices, about $13 at $4/$8); drop the rest.

---

## 6. Metrics and targets

**Activation**

Activation means four things in order: the keyboard is added, Full Access is on, a strip answer is used, and AI is used within 24 hours. No public benchmark exists for these steps, so the targets are Glyf's own goals.

| Metric | Glyf target by day 30 |
|---|---|
| Install → onboarding done | 75% |
| Install → keyboard added | 60% |
| Keyboard added → Full Access (iPhone) | 70% |
| Install → first strip answer | 50% |
| Install → first AI run within 24 hours | 35% |

**Retention**

Share of installs still using the keyboard. A keyboard used every day should beat ordinary apps; below 8% at day 30 means the value isn't landing.

| Metric | Benchmark | Glyf target |
|---|---|---|
| Day 1 | — | 45% |
| Day 7 | — | 25% |
| Day 30 | 2.6% Utilities, 3.2% Productivity, about 7% median for all apps [S41] | 15% |

**Money**

| Metric | Benchmark | Glyf target |
|---|---|---|
| Trial starts per install | 8.5% for AI apps [S43] | 8–10% |
| Trial → paid | 34.2% North America, 15.2% India and Southeast Asia [S42] | 30% in the US |
| Download → paid by day 35 | 2.0% median; 2.1% freemium; 2.4% AI apps [S42][S43] | 2.5% |
| Yearly share of new subscriptions | about 40% in North America [S42] | 50%+ |
| Revenue per install by day 60 | $0.24 monthly-led, $0.46 yearly-led [S42] | $0.40 |
| Refund rate | 4.2% median for AI apps [S43] | under 4% |
| AI + server cost ÷ net revenue | about 23% inference share at AI companies [S54] | under 25% |
| Free users hitting the limit weekly | — | 10–20% |

**Measure weekly:**
- installs by source;
- the funnel above;
- videos posted and best video views;
- trial starts and paid;
- AI spend;
- skills published and installed;
- shared places pages opened.

---

## 7. Risks

### 7.1 Guideline 4.4.1 (keyboards)

The rule [S76] says a keyboard must:
- offer a way to switch to the next keyboard;
- work without network access and without Full Access;
- collect activity only to improve the keyboard;
- not launch other apps besides Settings;
- not repurpose keys (Apple's example is holding Return to open the camera).

| Rule | Glyf today | Risk and what to do |
|---|---|---|
| Works without Full Access | Yes (APPS.md 4) | Low. Say so in the review notes, and show the reviewer typing, the strip and the vault with it off. Apps that didn't work without it were rejected (FlickType [S78]) |
| Launches no apps other than Settings | The keyboard opens **the Glyf app** for Pay (which then opens Phantom), for Connect and for dictation (`HostAppOpener`) | **Medium.** Opening its own app is common for voice keyboards, but it is not what the text allows. **What to do:** the keyboard must never open Phantom directly (it doesn't today). Explain in the review notes that the app opens only on a tap, to finish a payment or recording. Have a fallback ready: "Open Glyf to finish" with a copied link |
| No repurposed keys | Hold space opens AI; hold Return adds a new line | Low to medium. A new line is still typing, and Acti ships hold-space AI. Make the feature obvious in onboarding and in the review notes |
| Collects activity only for the keyboard | Telemetry is counts only | Low. Keep it that way; the new activation events must stay counts only |

### 7.2 Guidelines 3.1.5 and 3.1.1 (crypto and payments)

- **Wallets (3.1.5(i)).** Apps that facilitate holding crypto must come from developers enrolled as an **organization** [S76]. A non-custodial wallet was still asked for licence evidence [S77].
  - The memory notes say the signing team became Arpit's own team YNABR226PF (25–27 Sep); APPS.md still lists Console Labs India Private Limited.
  - **Check which kind of enrollment YNABR226PF is.** If it is an individual account, either hide the wallet in the iOS 1.0 build or publish under the company.
- **Exchanges (3.1.5(iii)).** Apps that facilitate trades must be licensed where they are offered [S76]. A swap fee makes Glyf look more like an exchange. Keep the fee off iOS until the app has passed review once.
- **No crypto rewards for tasks (3.1.5(v))**, and no unlocking features with crypto (3.1.1). Plus and Max stay on Apple's in-app purchase.
- **Google Play.** Non-custodial wallets are outside the crypto-exchange licensing rules [S79]. Declare the wallet honestly in Play's financial-features declaration.

### 7.3 Full Access privacy

- One bad story ends a keyboard. Wispr's screenshot row is the recent example [S24].
- Apple's keyboard guide says keystrokes may be stored only for services that are obvious to the person [S81]. Google Play asks for a prominent disclosure and a clear yes before sending personal data [S80]; Glyf's "What Glyf sends" sheet already does this.
- **Keep:**
  - nothing typed in telemetry;
  - AI providers told not to keep data;
  - secure fields never touched;
  - an export for the vault.
- **Fix before launch:** the debug argument that can write the decrypted vault to disk (C6).

### 7.4 AI costs

- **What already guards this:** worst-case costs are capped in code and tested; models are cheap (Qwen 3.7 Flash).
- **What remains:**
  - **Free users at scale.** Watch $0.03 per free monthly user.
  - **Single-provider dependence.** Qwen 3.7 Flash has one provider; the chain falls back to Gemini, at about 3x the cost.
  - **Price changes on OpenRouter.**
- **Rule:** if AI plus servers passes 25% of net revenue for two weeks, lower the free limit first.

### 7.5 Apple and Google building it

- **What they cover now:** rewrite, proofread, smart replies and translation are already free and built in (iOS 26/27, Gboard, Samsung) [S13][S8][S15]. Apple may add a Grammarly-style keyboard in an iOS 27 update [S14].
- **Where Glyf stays ahead:**
  - on-phone answers for money, units and dates;
  - places, videos and booking from the keyboard;
  - the vault and shorthand;
  - shared skills;
  - the wallet;
  - the same keyboard on iPhone and Android;
  - older iPhones without Apple Intelligence.
- **Keep shipping what platforms won't:** actions that touch other services, and community skills.

### 7.6 Acti

- Acti is funded ($5.3M) and led by someone who scaled a keyboard to 300M daily users [S36].
- It will out-spend Glyf on reach. Glyf should out-ship it on specifics: the 50+ instant answers, the wallet, Android parity, price, and a faster community store with public skill pages.

### 7.7 Founder risks

- One person, and a lot of review, key and account work is still owed (OPEN-ITEMS).
- Protect the daily video slot and the weekly metrics review. Everything else can slip a week.

---

## 8. Decisions for Arpit

1. Launch at $2/$5 as a founding price, then test $4/$40 and $8/$80 in month 2?
2. Yearly 7-day free trial at onboarding: yes or no?
3. Free tier: keep 20 runs a day, or test 50 a week?
4. Which Apple account publishes 1.0, and is it enrolled as an organization? Does the wallet show in the iOS 1.0 build?
5. Jupiter referral fee: 0.5%, Android first?
6. Referral rewards through Apple offer codes, and student codes: yes or no?
7. Which day is the Product Hunt launch, and who are the 20 people?
8. A Glyf for Teams pilot in month 3?

---

## Sources

- [S1] Grammarly plans: https://www.grammarly.com/plans
- [S2] Grammarly growth financing (May 2025): https://www.grammarly.com/blog/company/grammarly-announces-growth-financing/
- [S3] Grammarly buys Superhuman: https://siliconangle.com/2025/07/01/grammarly-acquires-email-client-developer-superhuman/
- [S4] Grammarly's early growth: https://startupgtm.substack.com/p/bootstrap-to-100m-first-round-in
- [S5] Why Grammarly needs Full Access on iOS: https://support.grammarly.com/hc/en-us/articles/115000730091-Why-Grammarly-Needs-Full-Access-on-iOS
- [S6] Gboard passes 10 billion downloads: https://9to5google.com/2025/02/26/gboard-10-billion-downloads/
- [S7] Gboard Writing Tools on more Android phones: https://www.androidauthority.com/gboard-writing-tools-other-android-phones-3593589
- [S8] Gboard Writing Tools upgrade (beta): https://www.androidauthority.com/gboard-writing-tools-upgrade-3668502/
- [S9] Microsoft buys SwiftKey for about $250M: https://venturebeat.com/ai/microsoft-has-reportedly-acquired-mobile-keyboard-company-swiftkey-for-around-250m
- [S10] Copilot changes in SwiftKey (FAQ): https://support.microsoft.com/topic/faqs-for-copilot-changes-in-swiftkey-c02289e6-c5b3-401c-af8d-f6c88409a2d2
- [S11] Why SwiftKey needs Full Access on iOS: https://support.microsoft.com/en-us/swiftkey-keyboard/why-does-my-microsoft-swiftkey-keyboard-need-full-access-in-ios
- [S12] Apple Intelligence languages and regions: https://support.apple.com/en-gb/121115
- [S13] iOS 27 features: https://www.macrumors.com/guide/ios-27-public-beta-features/
- [S14] iOS 27 keyboard rumour: https://www.macrumors.com/2026/04/01/ios-27-upgraded-keyboard-rumor/
- [S15] Samsung Writing Assist: https://www.samsung.com/us/support/answer/ANS10000943/
- [S16] Wispr Flow pricing: https://wisprflow.ai/pricing
- [S17] Wispr raises $280M at $2B: https://pulse2.com/wispr-raises-280-million-at-2-billion-valuation-as-revenue-grows-150-quarterly-and-voice-ai-push-accelerates
- [S18] Wispr Flow iOS launch (TechCrunch): https://techcrunch.com/2025/06/03/wispr-flow-releases-ios-app-in-a-bid-to-make-dictation-feel-effortless
- [S19] How Wispr Flow grows (third-party breakdown): https://www.postbeam.ai/blog/how-wisprflow-grows
- [S20] Wispr Flow referral: https://docs.wisprflow.ai/articles/6496688316-how-to-find-your-referral-link
- [S21] Wispr Flow affiliate program: https://partners.dub.co/flow
- [S22] Wispr Flow for students: https://docs.wisprflow.ai/flow-pro/education
- [S23] Wispr Flow free limits: https://docs.wisprflow.ai/articles/4760791189
- [S24] Wispr Flow criticism (competitor blog): https://laxis.com/blog/wispr-flow/
- [S25] Typewise pivots to B2B: https://www.aol.com/news/typewise-got-yc-pivoting-b2b-154433639.html
- [S26] Typewise on the App Store: https://apps.apple.com/us/app/id1470215025
- [S27] Fleksy SDK: https://techcrunch.com/2020/06/10/fleksy-rolls-out-an-sdk-for-its-ai-keyboard/amp/
- [S28] Pinterest hires the Fleksy team: https://techcrunch.com/2016/06/15/pinterest-acquires-the-team-behind-fleksy-a-custom-iOS-and-android-keyboard/
- [S29] Meta acquires Limitless: https://techcrunch.com/2025/12/05/meta-acquires-ai-device-startup-limitless
- [S30] Rewind shutdown details: https://9to5mac.com/2025/12/05/rewind-limitless-meta-acquisition/
- [S31] Raycast pricing: https://www.raycast.com/pricing
- [S32] Raycast AI pricing change: https://www.raycast.com/blog/changing-how-raycast-ai-is-priced
- [S33] Atomico on Raycast: https://atomico.com/insights/our-investment-in-raycast-the-shortcut-to-everything
- [S34] Raycast store growth: https://tech.eu/brief/blazingly-fast-raycast-raises-15-million-in-accel-and-coatue-led-round/
- [S35] Raycast for iOS: https://www.raycast.com/ios
- [S36] Acti launch (TechCrunch): https://techcrunch.com/2026/06/30/acti-puts-ai-agents-directly-into-your-smartphone-keyboard
- [S37] Acti on Product Hunt: https://www.producthunt.com/p/acti-2/acti-3
- [S38] Willow Voice keyboard: https://tech.yahoo.com/ai/meta-ai/articles/willow-voice-keyboard-lets-type-072100796.html
- [S39] Key AI on the App Store: https://apps.apple.com/us/app/key-ai-ai-keyboard-assistant/id6742742345
- [S40] RizzKey on the App Store: https://apps.apple.com/us/app/id6475035053
- [S41] Mobile app retention benchmarks: https://uxcam.com/blog/mobile-app-retention-benchmarks
- [S42] RevenueCat State of Subscription Apps 2026: https://www.revenuecat.com/state-of-subscription-apps
- [S43] RevenueCat on AI apps (summary): https://ppc.land/ai-apps-earn-41-more-per-user-but-churn-30-faster-revenuecat-finds/
- [S44] AI apps and long-term retention (TechCrunch): https://techcrunch.com/2026/03/10/ai-powered-apps-struggle-with-long-term-retention-new-report-shows
- [S45] RevenueCat State of Subscription Apps 2025: https://www.revenuecat.com/state-of-subscription-apps-2025/
- [S46] Adapty State of In-App Subscriptions 2026: https://adapty.io/state-of-in-app-subscriptions-report/
- [S47] Superwall, multi-page onboarding paywalls: https://superwall.com/blog/new-postmulti-page-onboarding-paywalls-convert-37-better-than-single-page-heres-why.md
- [S48] RevenueCat, the end of the trial toggle: https://www.revenuecat.com/blog/growth/rip-toggle-paywall
- [S49] RevenueCat on lifetime subscriptions: https://www.revenuecat.com/blog/growth/lifetime-subscriptions
- [S50] MacroFactor on lifetime plans: https://help.macrofactorapp.com/en/articles/115-why-doesn-t-macrofactor-have-a-lifetime-subscription-tier-with-a-one-time-payment
- [S51] AppSumo revenue drop: https://ppc.land/appsumos-revenue-crashes-50-as-lifetime-deal-model-faces-existential-crisis/
- [S52] Text Blaze plans: https://blaze.today/plans
- [S54] ICONIQ State of AI (via SaaStr): https://www.saastr.com/iconiqs-latest-state-of-ai-report-the-10-most-important-data-points-for-saas-founders
- [S55] Amazon Associates mobile app rules: https://affiliate-program.amazon.com/help/node/topic/GHBY6W8UPTEFD3ZX
- [S56] Expedia affiliate program: https://partner.expediagroup.com/en-gb/solutions/explore-our-affiliate-program
- [S57] Apple proposes a fee on link-out purchases: https://techcrunch.com/2026/08/14/apple-proposes-to-take-a-15-cut-of-purchases-made-outside-the-app-store/
- [S58] RevenueCat in-app against web purchase test: https://revenuecat.com/blog/growth/iap-vs-web-purchases-conversion-test
- [S59] Google Play US external offers: https://support.google.com/googleplay/android-developer/answer/16470497?hl=en
- [S60] Jupiter Swap API fees: https://developers.jup.ag/docs/swap/fees
- [S61] Jupiter changelog, March 2026 (Swap V2): https://developers.jup.ag/changelog/2026-03
- [S62] Phantom on ethereum.org (swap fee): https://ethereum.org/wallets/find-wallet/phantom/
- [S63] Solana Mobile FAQ (fees): https://docs.solanamobile.com/get-started/faq
- [S64] Submitting to the Solana dApp Store: https://docs.solanamobile.com/dapp-store/submit-new-app
- [S65] dApp Store passes 1,561 apps: https://solanacompass.com/news/solana-mobile-dapp-store-surpasses-1561-apps-as-catalog-more-than-doubles-in-three-months
- [S66] Solana Mobile at MWC (Seeker sales): https://www.mwcbarcelona.com/exhibitors/34827-solana-mobile
- [S67] SKR launch and Seeker Season 2: https://blog.solanamobile.com/post/skr-launches-january-21-seeker-season-2-starts-now
- [S68] SKR airdrop to users and developers: https://cointelegraph.com/news/solana-mobile-airdrop-nearly-2b-seeker-users-and-devs
- [S69] Solana Mobile Builder Grants: https://solanamobile.com/blog/solana-mobile-builder-grants-bring-your-best-seeker-and-skr-ideas
- [S70] Solana Foundation India grants (Superteam): https://superteam.fun/earn/grants/solana-foundation-india-grants/
- [S71] Superteam Moonshots: https://in.superteam.fun/instagrants/moonshots
- [S72] Colosseum Frontier hackathon: https://blog.colosseum.com/announcing-the-solana-frontier-hackathon/
- [S73] Colosseum accelerator: https://www.colosseum.com/accelerator
- [S74] Phantom Portal: https://docs.phantom.com/phantom-portal/getting-started
- [S75] Phantom raises $150M (users): https://finder.techleap.nl/news/feed/phantom-raises-150m-at-3b-valuation
- [S76] App Store Review Guidelines (4.4.1, 3.1.1, 3.1.2, 3.1.3, 3.1.5, 3.2.2): https://developer.apple.com/app-store/review/guidelines/
- [S77] Apple forums, a non-custodial wallet asked for licences: https://developer.apple.com/forums/thread/729821
- [S78] FlickType and App Store hurdles: https://9to5mac.com/2021/08/16/flicktype-discontinuing-iphone-keyboard-app-due-to-app-store-hurdles/
- [S79] Google Play crypto exchanges and wallets policy: https://support.google.com/googleplay/android-developer/answer/16329703
- [S80] Google Play user data policy: https://support.google.com/googleplay/android-developer/answer/11150561
- [S81] Apple custom keyboard guide: https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html
- [S82] How App Store search works: https://developer.apple.com/app-store/search
- [S83] Custom Product Pages: https://developer.apple.com/app-store/custom-product-pages
- [S84] App Store tags (WWDC25): https://techcrunch.com/2025/06/11/at-wwdc-apple-says-it-will-use-ai-to-tag-apps-to-improve-discoverability-on-the-app-store
- [S85] App previews: https://developer.apple.com/support/app-previews/
- [S86] In-App Events guide: https://www.mobileaction.co/guide/in-app-events-promotional-content-guide
- [S87] Paste Keyboard goes viral: https://appfigures.com/resources/this-week-in-apps/20210604
- [S88] Fonts keyboard growth on TikTok: https://playkit.substack.com/p/custom-fonts-emojis-app
- [S89] Rizz apps on TikTok (vendor blog): https://www.shortimize.com/blog/rizz-apps-b-roll-strategy-that-got-them-half-a-billion-views-on-tiktok
- [S90] Cluely: https://en.wikipedia.org/wiki/Cluely
- [S91] UGC creator prices: https://influee.co/blog/ugc-price
- [S92] Whop Content Rewards: https://docs.whop.com/memberships-and-access/third-party-apps/content-rewards
- [S93] Wispr Flow word of mouth and Product Hunt: https://www.marketingmonk.so/p/wispr-flow-word-of-mouth-marketing-strategy
- [S94] Product Hunt launch survey: https://mysignature.io/blog/product-hunt-launch/
- [S95] Subreddit rules (read through mirrors, Oct 2026): https://www.reddit.com/r/iosapps/ and https://www.reddit.com/r/AndroidApps/
- [S96] Dropbox referral program: https://viral-loops.com/blog/dropbox-grew-3900-simple-referral-program/
- [S97] Hotmail's signature growth: https://themarketingmillennials.com/articles/2023-01-25/the-unknown-story-of-how-hotmail-grew-to-12-million-users-in-1-5-years-2/
- [S98] "Sent from Ubuntu" switched off: https://www.omgubuntu.co.uk/2010/09/sent-from-ubuntu-evolution-signature-turned-off
- [S99] Perplexity Pro free for students: https://geekflare.com/news/perplexity-just-made-its-pro-tools-free-for-students-globally
- [S100] Bobble and Xiaomi preload: https://www.outlookbusiness.com/big-idea/babble-out-bobble-in-5530
- [S101] Mobile app affiliate norms: https://winwinkit.com/blog/creator-partnerships-mobile-app-affiliate-program-2026/
- [S102] Linkrunner pricing: https://linkrunner.io/compare/apptrove

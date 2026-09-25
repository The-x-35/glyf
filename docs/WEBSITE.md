# Website: tryglyf.com

The marketing site and waitlist for Glyf. This file records what the site is today, how every part works, every design decision behind it (with Arpit's words where they drove the change), how it evolved from v1 to today, and what is still open.

Last updated: Wed 16 Sep 2026 (IST).

---

## 1. At a glance

| | |
|---|---|
| Purpose | Show what the Glyf keyboard does and collect waitlist signups before launch |
| Domain | **https://www.tryglyf.com** is the live, primary domain; `tryglyf.com` redirects to it (308). Domain bought by Arpit on 14 Sep 2026 |
| Code | `site/` in the monorepo (private GitHub repo `The-x-35/glyf`) |
| Stack | Next.js 15 (app router), React 19, TypeScript, framer-motion 11, plain CSS in `app/globals.css`, Inter variable font (local file) |
| Data | Neon Postgres, table `waitlist`, reached directly from a Next.js API route through `@neondatabase/serverless` |
| Hosting | Vercel (Arpit deploys it; no Vercel login exists on the dev Mac) |
| Env vars | `DATABASE_URL` (required), `SITE_URL` (optional, defaults to `https://www.tryglyf.com`; if set, it must be the domain that serves the page, not one that redirects) |
| Backend server | Not used. The site does not call `server/` at all |
| Status | **Live on Vercel since Wed 16 Sep 2026, about 03:10 IST**, deployed by Arpit from the repo. Share image confirmed live |

Run locally:

```bash
cd site && npm install && npm run dev
```

Opens on http://localhost:3000. The waitlist needs `DATABASE_URL` in `site/.env.local` (gitignored).

---

## 2. What the page is today (top to bottom)

`app/page.tsx` renders, in order:

1. **Cursor** (`components/Cursor.tsx`): the "caret to keycap" cursor (details in section 9).
2. **Backdrop keyboard** (`components/BackdropKeys.tsx`): a faint Glyf keyboard lying back in perspective behind the hero only.
3. **Fixed nav** (64px tall): the `glyf` wordmark at 28px with the raised purple dot, a 38px theme toggle (sun/moon), and a black "Join waitlist" pill (14px) linking to `#join`. Made bigger on 16 Sep: "make navbar a little bigger in site and logo in navbar to be bigger too".
4. **Hero** (`section.hero#top`):
   - Headline: **"Type less. glyf more."** where "glyf" is the wordmark itself (lowercase, weight 700, tight tracking, raised purple dot), per Arpit on 16 Sep: "glyf more text in hero, glyf should be our wordmark logo in there". One line on desktop, two lines on phones ("Type less." / "glyf• more.").
   - Subline: **"The AI keyboard that does the rest."**
   - Greyed store badges: "Coming soon on App Store" and "Coming soon on Google Play" (the small line is the same on both, so the pair reads as a pair; Apple's own badge says "Download on the", Google's says "GET IT ON") (not clickable, `aria-disabled`, 32% opacity, grayscale).
   - Waitlist form (`source="hero"`).
5. **The chat experience** (`div#try > components/chat/Experience.tsx`): a pinned, scroll-driven iMessage stage with 8 chats. Each chat is a small level where a friend asks for something and the visitor does it on the Glyf keyboard.
6. **Finale** (`section.finale#join`): **"Made for your thumbs."** plus a second waitlist form (`source="footer"`).
7. **Footer**: wordmark and "© 2026 Glyf · iPhone and Android · Privacy".

One more page: **`/privacy`** (`app/privacy/page.tsx`, since 25 Sep 2026), the privacy policy the App Store asks for, written from what the apps and server actually do: what stays on the phone, what the keyboard sends and when (AI features, strip suggestions, saved details, search, location), secret masking, the account data kept, every outside service (OpenRouter and its providers, the Gemini API with its unpaid-tier training note, search providers, KLIPY, Cal.com, Google Calendar and Meet from the phone, Privy or the wallet app, Railway, Neon, Vercel), the waitlist, Delete account, children under 13, and a contact address (arpit@tryglyf.com). The same nav and footer, one 680px column, styles under `.legal` in `globals.css`. Change it whenever a feature starts sending something new, and drop the Gemini line once production no longer uses Gemini's free tier.

There are no explainer lines anywhere, no pricing, no FAQ and no feature grid. Those existed in earlier versions and were removed on purpose (section 13).

---

## 3. The chat experience (`components/chat/Experience.tsx`)

### 3.1 Idea

Arpit's brief (15 Sep, 17:32): "instead of forcing animations etc, u shud guide users to perform actions and feel the features himself ... simulate a chat interface not a mobile device ... a msg comes pls send ur address, and i just open my vault and send it ... kinda like a game guide so user feels the need of it". Plus: "i need a imessages like interface ... exactly like imessages" and "see how i messages send msg animation works ... it forms a bubble and goes right".

So every feature is taught by a friend needing something, and the visitor does it with the real demo keyboard. A purple pulsing ring plus a small pill ("Hold S", "Tap Home", "Send") marks the exact key or card to use next. No sentences explain anything.

### 3.2 Layout

**Desktop (wider than 900px):** grid with the animated chat headline and the chat list on the left, and a rounded iMessage window on the right. Arpit rejected a WhatsApp Desktop layout ("no man i didnt want a whatsapp exact layout if u wanna copy exactly do imessages for mobile and desktop") and preferred "the previous one ... with heading and list below".

- Chat list rows: unread dot, emoji avatar, name, a small tag (for example "Maps", "Vault"), last message preview, and a green check when the chat is done. Clicking a row jumps the page scroll to that chat.
- The iMessage window: iOS 26 style glass header (avatar, name pill, video button), "Today <time>" stamp, bubbles with tails on the last bubble of a group, typing dots bubble, "Delivered" then "Read" receipts, tapback reactions, rich cards, and the Glyf keyboard docked at the bottom with the iOS 26 input bar (+ button, capsule field, blue send arrow).

**Phones (900px and below):** a full-screen iMessage conversation. The glass back button shows the unread count and slides in a "Messages" list screen (large title, rows with time and chevron, blue unread dots, bottom search pill). A short headline for the current chat sits above the conversation.

### 3.3 Scroll story: one scroll, one action (22 Sep 2026)

The stage is a **timeline of steps**, not a list of chats. One step of scroll performs one action: tap whatever the coach is pointing at, or, when a chat is finished, open the next one. **A chat changes because it is done, never because the page moved.**

- The section is `TICKS` steps tall (76). Desktop height `calc(var(--ticks) * 9svh + 100svh)`, phones `calc(var(--ticks) * 8.5svh + 100svh)`. The inner `.xp-pin` is sticky, so the stage stays pinned for the whole timeline and the page moving changes nothing on screen.
- `spent` is how many steps the demo has actually taken; `want` is how many the scroll has paid for. When `want` runs ahead the pointer performs the next one. When the visitor runs ahead by doing it themselves, the page is wound forward to meet them (`syncScroll`, forward only), so they never have to scroll back through a stretch their own taps already paid for.
- Both are counted by the same thing: the identity of the step on screen (`stepKey` = active chat, beat, and the coach's target, or "done"). Landing on a new one is a step, whoever caused it. The visitor and the pointer can therefore never disagree about how far along the demo is.
- A step that cannot happen yet does not burn a notch. While the friend is typing there is no coach target, so the step stays bought and fires the moment the chat is ready. A fast scroll never skids past a reply nobody saw.
- Scrolling up rewinds nothing. `spent` is a high-water mark; scrolling back down resumes where it was, and scrolling further up simply leaves the section.
- Sixty steps covered the whole demo when it was measured a notch at a time. The budget is 76; the slack is for a visitor going their own way (opening a panel they then close costs two steps, a nudged answer costs a couple more).

**Why it changed.** Scroll used to address the chat: `active = floor(progress × chats)`. A conversation therefore ended when its slice of the page ran out rather than when it was finished, so scrolling walked out of a chat halfway through. Arpit (22 Sep): "the scroll feels a little unnatural, i said if user doesnt perform actions they should perform on scrol but scrol is taking to next chat ... so like consider everystep as a scroll action ... and if he scrolls further, the next action happens".

**The chat list is a shortcut, not a position.** Picking a chat from the list (or a banner) sets the active chat directly. It used to scroll to that chat's slice of the page, which is the same arithmetic that made plain scrolling leave a chat unfinished.

**Scroll position is read off the section, not through `useScroll`.** One `getBoundingClientRect` and one subtraction in a passive `scroll` listener. Framer's `useScroll` with a `target` is a motion value polled on rAF; the plain listener is easier to reason about and has no opinion about when it is allowed to measure. Trap when testing: `window.scrollBy()` called from a devtools/CDP evaluation does **not** dispatch `scroll` events, so a probe written that way sees a frozen timeline and looks like a bug in the page. Drive it with real wheel events instead.

Other chapter behaviour, unchanged:

- Changing chat animates the headline (blur and rise), swaps the thread, resets the keyboard for that chat and starts the friend's first messages the first time the chat is opened.
- Finishing a chat shows the friend's tapback on your bubble, their reply, then a notification banner from the next friend. The banner slides away after 6 seconds (iOS style), so on phones it never sits over the back button. After the last chat the banner reads "That's everyone. Get Glyf first →" and tapping it scrolls to the finale form.

### 3.4 Scenario engine

Scenarios live in `components/chat/scenarios.ts`. Each chat has `beats`. A beat has:

- `them`: the friend's lines, typed out with a typing-dots delay each.
- `prefill`: text already in the draft (used for Neha's messy draft).
- `lang` / `pay`: hints that preset the translate language or the wallet payment.
- `autotype(snapshot)`: what the keyboard types for the visitor at this moment (rule: **never make the visitor type**).
- `goal(sent)`: whether the sent message completes the beat.
- `coach(snapshot, ui)`: which target to highlight next, computed from live keyboard state, so any path the visitor takes still works.
- `reply`: the friend's answer (fixed lines or a function of what was sent).
- `tapback`: the reaction on your bubble.
- `nudge`: what the friend says if you send something that doesn't meet the goal.

Messages sent while the friend is still typing are queued and judged once they finish (this fixed a "she stayed silent" bug).

### 3.5 Scroll autopilot (ghost pointer)

Arpit (15 Sep, 19:10): "if the user is nto doing actions and just scrolling, u shud do the action on further scrolling and maybe use a fake mouse pointer and perform it".

- If a visitor only scrolls, a pointer (a Mac arrow on desktop, a fingertip on touch) glides to the coached target and performs that step.
- One step of scroll buys one action (section 3.3). It used to be a per-chapter budget: the first step at 14% of the chapter's scroll, then one more every 7.5%, which is why a chat could run out of page before it ran out of steps.
- It holds keys when the coach label starts with "Hold", taps otherwise, opens the Copy menu on Semi's address bubble, and so on.
- Doing a step yourself does **not** stop the pointer any more. It used to: a single real touch handed that chat back for good, so a visitor who tapped once and then scrolled got nothing but a jump to the next chat. Both routes now count the same step, and scrolling on continues from wherever the visitor got to.
- When the pointer is behind by more than one step the visitor is scrolling quickly, so it stops explaining itself: the dwell before a tap drops from 560ms to 180ms.
- Before acting it re-checks that the chat and the coached target are unchanged. Key holds are also cancelled when the chat changes, so a hold started in Neha's chat can never fire in Rohan's (this was a real bug: Rohan's chat was opening the AI panel).
- Autopilot is skipped for reduced-motion visitors.

### 3.6 The 8 chats, word for word (current order)

Order decided by Arpit on 15 Sep, 23:40 ("move mumma on top, replace script of mumma and sakshi ... sakshi will be on top with coffee script") and 23:42 ("mummi wont say ghar ka khana, just say beta and the script").

**1. Sakshi ☕ · tag "Maps" · headline "Where to meet? / Maps, mid-chat."**
- Sakshi: "free this evening? 😊", "let's get coffee ☕ where should we meet?"
- Visitor: Search, Maps tab, "Cafés near me", tap a café card to share it (arrives as a map card).
- Tapback ❤️. Reply: "perfect 🙌 <café name> at 6 then", "can't wait to catch up!"
- Nudge: "send me a place 😄"

**2. Mumma 🎁 · tag "Vault" · headline "Never type your / address again."**
- Mumma: "hi beta 🎉", "sending you something for your birthday", "what's your address?"
- Visitor: hold S (or the vault in the toolbar, or the contextual vault chip), tap Home, send.
- Tapback ❤️. Reply: "got it beta ❤️", "it'll be there by friday"
- Nudge: "beta, what's your address? 🙈"

**3. Semi 🏆 · tag "Private pay + swaps" · headline "Pay on Solana. / Privately."**
- Semi: "the server bill just hit 😩", "can you send $200 for server costs? usdc on sol", then his Solana address as its own bubble (`8QvS3nE5d1YwZk7pLr2mXh9TbF4cJaGuVy6oKe1RtNqP`, a demo address).
- Visitor: tap the address bubble, an iMessage-style Copy menu appears, tap Copy (also copies to the real clipboard when a human does it). A Paste chip appears, tap it. Glyf recognises a Solana address and shows a Pay chip. Tap Pay: the wallet opens with $200 USDC to Semi prefilled and "Private · MagicBlock" on. Tap "Send privately": three steps tick off ("Enclave verified · Intel TDX", "In a Private Ephemeral Rollup · MagicBlock", "Sent privately · settled on Solana"). The draft becomes a dark payment card. Send.
- Tapback 🙏. Reply: "got it, thank you" (Arpit asked to remove the 🙏 that followed it), "and nobody onchain can see who paid lol 🥷"
- Nudge: "did it go through? 👀"
- The chat list and banner show "can you send $200 for server costs? usdc on sol" as the preview, never the raw address.

**4. Neha 💼 · tag "AI rewrite" · headline "Type it messy. / Send it polished."**
- Neha: "Hi! Could you send the Q3 deck to the client by EOD?"
- Draft is prefilled: "ya ill send it by 6 dont worry"
- Visitor: hold the space bar (labelled "glyf") to open the AI actions, pick Professional ("Absolutely, I'll share the Q3 deck with the client by 6 PM today."), send.
- Tapback 👍. Reply: "Perfect, thank you! 🙌"
- Nudge: "Haha, maybe a little more formal? 😅"

**5. Rohan 🏏 · tag "Hinglish autocorrect" · headline "Fixes the typos. / Keeps the yaar."**
- Rohan: "bhai kal match dekhne chal raha? 🏏"
- Keyboard types "haan yaar pakak". Coach "Tap pakka" on the suggestion chip. Then it types "definately", coach "Tap definitely". Then it types "aa raha hoon 🙌". Send. "yaar" and "haan" are never changed.
- This chat must never open the AI panel (Arpit: "in rohon why does it goes to ai while its a hinglish suggestion case").
- Tapback 😂. Reply: "haha pakka 😂", "7 baje gate pe milte hain"
- Nudge: "aa raha hai ya nahi? 😅"

**6. Zoya 🍝 · tag "Math + UPI" · headline "Do the math. / Get paid."**
- Beat 1. Zoya: "dinner was so good 😭", "bill was ₹3480 for 4 of us. how much do I send you?" Keyboard types "3480/4" itself (switching to the 123 layout on screen). Visitor taps the calc chip, draft becomes "3480/4 = 870" (Arpit: "after tapping it should say 3480/4 = 870 and not just 870"). Send. Reply: "sending now 💸". Nudge: "wait, how much though? 😅"
- Beat 2. Zoya: "what's your UPI?" Keyboard types "my upi id is ". Visitor taps the UPI chip. Send. Tapback 👍. Reply: "done ✅ ₹870 sent". Nudge: "your UPI? 🙏"

**7. Kabir 🚗 · tag "YouTube + Google" · headline "Send the song, / not the search."**
- Beat 1. Kabir: "road trip tomorrow 🚗", "send me something good for the drive". Visitor: Search, YouTube, "Road trip songs", tap a video to share (arrives as a video card "Road trip hits: non-stop highway mix"). Tapback 🔥. Reply: "ok this slaps 🔥". Nudge: "send a song 😄"
- Beat 2 (Maya's old chat merged in). Kabir: "also, terrace at sunset today? 🌇", "what time is sunset?" Visitor: Search, Google, "Sunset time today", share the answer ("Sunset's at 6:24 PM 🌇"). Tapback ❤️. Reply: "see you up there ☀️". Nudge: "what time though? 🌅"

**8. Sofía 🌊 · tag "Translate" · headline "Reply in Spanish. / No lessons."**
- Sofía: "¡Hola! 👋", "¿Nos vemos mañana?"
- Visitor: hold T. The keyboard types "see you tomorrow", the translate bar shows "hasta mañana", tap Replace, send.
- Tapback ❤️. Reply: "¡Perfecto! Hasta mañana 🌊"
- Nudge: "¿Cómo? 😅"

### 3.7 Chat history of the scripts (what changed and why)

- First v8 cut (15 Sep, 17:57): Riya (address), Neha (rewrite), Arjun (maps), Zoya (math, visitor typed 3480/4), Kabir (YouTube), Sofía (visitor typed the English), Maya (sunset), Dev (crypto wallet then Instagram from the vault).
- 15 Sep, 18:14, Arpit: Riya becomes Sakshi; vault Home becomes "123, A-block, Delhi 110001"; Dev becomes Semi and moves right after Sakshi; Solana, not EVM (`4j8FqYuNix7RfFgKmiRZnCE1acNnTarqm1SbZYdQZmFA`), and Semi replies "sent u 1000 usdc on sol"; Arjun becomes Mumma, "coffee script is perfect" but she must reply after getting the location; Zoya: the keyboard types, the visitor only taps; Maya merged into Kabir; translate chat: the keyboard types.
- 15 Sep, 19:08: Rohan added (Hinglish autocorrect), after Arpit asked to "show auto correct etc in local languages too ... like yaar".
- 15 Sep, 23:02, Arpit: Semi now asks for $200 for server costs, sends his wallet, visitor copies and pastes it and pays privately with MagicBlock on Solana; show a swap UI powered by Jupiter but do not demo it; remove the Instagram ask. 23:11: show the balance in the keyboard wallet.
- 15 Sep, 23:34: remove the 🙏 after "thank you" in Semi's reply.
- 15 Sep, 23:40 to 23:42: coffee chat moves to the top and belongs to Sakshi; the address chat belongs to Mumma with "beta" lines. An interim version where Mumma said "beta, sending you ghar ka khana 🍱" was rejected.

---

## 4. The demo keyboard (`components/kb/`)

One keyboard component is used in the chat stage. It is a faithful web version of the real Glyf keyboard, with the same features the apps have, restyled for the site. Arpit: "i like ui ux on website dont copy mobile for that, its shit in mobile rn".

Files:
- `Keyboard.tsx`: the keyboard, its panels, gestures and an imperative API (`KeyboardApi.run(target, hold)`) the autopilot uses.
- `data.ts`: vault values, clipboard items, emoji, search suggestions and canned result cards, answer cards, autocorrect word lists (including Hinglish), rewrite families, translation, the calculator parser, Solana address detection, swap rate.
- `visuals.tsx`: Google G mark, sun arc widget, weather glyph, clock face.
- `brands.tsx`: MagicBlock logo and mark (from MagicBlock's own site header SVG), SOL and USDC icons (`public/brands/sol.png`, `public/brands/usdc.png`, from the official Solana token list, downscaled to 96px).
- `icons.tsx`: stroke icons (search, clipboard, vault, wallet, emoji, translate, mic, plus, send, paste, swap, shield, etc.).
- `hub.ts`: small shared state helper.

### 4.1 Features

- **Keys:** QWERTY with a 123 layout, shift, backspace, return. The space bar says **"glyf"** (Arpit: "space key should say glyf and not space").
- **Micro-interactions ported from the iOS keyboard code:** enlarged letter balloon on press (1.55× wide, 1.35× tall), a 2pt charge ring on hold that scales 1.18 to 1, the key flashing the accent colour when a skill fires, and a purple ripple across the board (delay about distance × 26ms).
- **Hold gestures:** hold space to open Glyf actions on the typed text (rewrite in tones, act); hold S for the vault; hold T for live translate.
- **Suggestion strip priority:** Pay chip (a Solana address in the draft) > Paste chip (fresh clipboard) > calculator result > contextual vault chip (for example your UPI after "my upi id is") > word suggestions (hidden when the draft is a payment card) > toast > autocorrect fix > toolbar.
- **Autocorrect:** fixes common typos and Hinglish spellings (pakak→pakka, yaaar, thik, kese, bhot, hna) while leaving real Hinglish words alone.
- **Calculator:** detects expressions like `3480/4` and offers "= 870".
- **Toolbar:** Search, Clipboard, Vault, Wallet, Emoji, Translate. The g menu also lists Wallet (the Skills item was removed).
- **Search panel:** Google, YouTube and Maps tabs, suggestion rows, result cards. Sharing a card inserts a rich message (📍 place, ▶ video, answer text).
- **Answer card:** the Google sunset answer is a widget (dusk gradient, Google G badge, big "6:24 PM", sun path arc with 6:08 AM / 6:24 PM, sunrise, daylight and last light facts). Arpit asked for this with "this should look better".
- **Vault panel:** name, Home address, UPI, Solana wallet, Instagram, X, LinkedIn, email, phone.
- **Clipboard panel:** four items. The first is the Rick Roll link `https://youtu.be/dQw4w9WgXcQ?si=ms6HzsvNvsPeLhH_`; tapping it opens YouTube in a new tab instead of pasting (Arpit, 16 Sep 00:24). The others paste: "meet.google.com/xk2-pqr-7ty", "Flight PNR · QR7GH2", "the figma link from standup". Ages: Just now, 2 min, 1 hr, Yesterday.
- **Translate panel:** Hindi, Spanish and French; live translation of the draft; Replace.
- **AI panel:** tone rows (Polite, Shorter, Professional, Hinglish, Emoji) with live previews of the rewrite.
- **Wallet panel:**
  - Balance header: total in dollars with USDC 1,240.18 and SOL 8.42 (all demo numbers). The balance drops after the $200 payment and changes after a swap, and carries across chats.
  - Send tab: amount + token → recipient (shortened address), a Private toggle with the MagicBlock mark and logo, "Send privately", then the three steps.
  - Swap tab: "Routes by Jupiter", Sell 1.5 SOL / Buy ≈ 213.41 USDC, flip button, "1 SOL ≈ 142.27 USDC · best route via Jupiter". It is UI only; no chat walks through it.
  - On phones the header shows only the MagicBlock logo (the words "Private sends by" are hidden under 480px so nothing clips).
- **Physical keyboard:** on desktop, typing on a real keyboard presses the demo keys.

### 4.2 Demo vault data (placeholders and Arpit's real links)

| Field | Value |
|---|---|
| Name | Arpit Singh |
| Home | 123, A-block, Delhi 110001 |
| UPI | arpit@okbank (placeholder) |
| Solana | 4j8FqYuNix7RfFgKmiRZnCE1acNnTarqm1SbZYdQZmFA |
| Instagram | instagram.com/Arpitx35 |
| X | x.com/Arpitx35 |
| LinkedIn | linkedin.com/in/Arpitx35 |
| Email | arpit@tryglyf.com |
| Phone | +91 98765 43210 (placeholder) |

Arpit rejected @handles: "dont use @arpitx35, use links bro, it should type x.com/Arpitx35". Only the wallet is shortened on vault cards (`4j8F…ZmFA`); the full value goes into the message.

### 4.3 MagicBlock and Jupiter facts used in the copy

- MagicBlock private payments run in a Private Ephemeral Rollup: an Intel TDX trusted execution environment combined with an ephemeral rollup on Solana. Confidential transfers hide balances and counterparties, and the setup is described as compliant and attestable. The step wording was taken from MagicBlock's site and docs.
- Jupiter is only referenced as the swap router ("Routes by Jupiter"); the swap UI is the site's own design, not a copy of jup.ag, per Arpit: "for ui ux use our site ui ux only dont demo jup".
- Open point: check MagicBlock, Solana and Circle brand guidelines (or ask MagicBlock) before a public launch uses their marks.

---

## 5. Backdrop keyboard in the hero (`components/BackdropKeys.tsx`)

Arpit (15 Sep, 19:09): "the type less gly more screen should show the keyboard behind very subtly". Then: "it should also press keys if i press key on real keyboard", "i think subtle keyboard to only stay in hero section, elsewhere it looks shit".

- A fixed, perspective keyboard (rotateX 52°, lying back) at low opacity (0.34 light, 0.30 dark) behind the hero, masked with a radial gradient.
- It types "type less glyf more" by itself, holds space now and then, and fires a purple ripple across the keys.
- Real keyboard presses light up the same keys; holding space for about half a second fires the ripple. Self-typing pauses while the visitor types, when the tab is hidden, or when scrolled away.
- It tilts further back, drops and fades as the hero scrolls away (gone by 65% of the viewport height), so it never shows behind the chats.
- The page background is on `html`, and `body` must stay transparent, otherwise the z-index -1 layer is painted over (this made it invisible once).
- On phones (700px and below) it is bigger and reaches higher: rows `clamp(40px, 8.6svh, 76px)`, 230vw wide, a wider mask, bottom edge 18px below the screen (44px below on screens 600px tall or less), bigger key labels.

---

## 6. Hero layout rules

**Desktop:** the hero content (headline, subline, badges, form) is centered in a `min(92svh, 860px)` tall band.

**Phones (700px and below)**, after three rounds of feedback on 16 Sep:
1. "i dont like the space after join waitlist and keyboard it can be reduced i feel in mobile". A first attempt pushed the text down, which Arpit rejected: "this looks more bad now ... i wanted keyboard to go up a bit and be bigger on mobile".
2. The keyboard was made bigger and higher instead.
3. "move type less glyf more a little above make it little bigger, fucking design it properly for mobile".

The result:
- The hero is a full-height flex column: `min-height: 100svh`, padding `72px 0 calc(32.1svh + 25px)` (72px = the 64px nav plus a little air).
- The headline is bigger (`clamp(54px, min(19vw, 10.5svh), 84px)`, about 68 to 71px on common phones) and sits near the top. Auto margins split the free space between "above the headline" and "between the subline and the badges".
- Store badges and the form sit about 33px above the backdrop keyboard's top edge at every phone size.
- Short phones (700px tall or less): headline `clamp(46px, min(17vw, 9.4svh), 84px)`, tighter spacing. 600px tall or less (SE in Safari): keyboard tucked lower and headline `min(15vw, 8.8svh)`.
- Narrow phones: badges shrink at 480px and again at 340px so both stay on one row. The subline uses `clamp(17px, 5.6vw, 21px)`.
- Measured results before the nav grew to 64px (form to keyboard gap / nav to headline gap): 375×772: 33 / 59px; 357×774: 32 / 64px; 390×664: 33 / 35px; 414×736: 33 / 41px; 430×932: 41 / 103px; 375×553: 33 / 23px; 320×568: 32 / 19px. After the bigger nav and inline wordmark: 375×772: 33 / 55px; 390×664: 33 / 31px; 320×568: 32 / 15px. Headline always two lines, badges always one row, no overlap, no sideways scroll.

Lesson recorded: when Arpit says the gap to the keyboard is too big, change the keyboard (bigger, higher), not the content position.

---

## 7. Waitlist

### 7.1 Form (`components/Waitlist.tsx`)

- States: idle, busy ("Joining…"), done, error.
- Messages: "You're on the list. We'll email you when Glyf ships." or "You're already on the list." plus an "Add another" button.
- The hero and footer forms mirror each other through window events (`glyf:joined`, `glyf:reset`). A done state is remembered in `localStorage` (`glyf-waitlist`); "Add another" clears it for both forms.
- A hidden honeypot field named `company`.
- The visible count ("#3 on the list") was dropped on purpose: a tiny number looks empty on launch night.

### 7.2 Email checks (`lib/email.ts`, shared by form and API)

- Normalised with trim and lowercase.
- Messages: "Enter your email.", "That email is too long.", "That email is missing an @.", "That email has two dots in a row.", "That email doesn't look complete.", "That email doesn't look right."
- Shape regex: `^[a-z0-9._%+-]{1,64}@[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*\.[a-z]{2,}$` (case-insensitive). A shape check, not deliverability.

### 7.3 API (`app/api/waitlist/route.ts`)

`POST /api/waitlist` with `{ email, source, company }`:
1. Bad JSON → 400 "Bad request."
2. Honeypot filled → 200 `{ ok: true }` and nothing stored.
3. More than 8 tries per IP per minute (per server instance) → 429 "Too many tries. Give it a minute."
4. Email problem → 400 with the message above.
5. No `DATABASE_URL` → 503 "The list isn't open yet. Try again soon."
6. `INSERT ... ON CONFLICT ((lower(email))) DO NOTHING RETURNING id`. If the table is missing (Postgres error 42P01) it creates it and retries.
7. Response `{ ok: true, already: <true if the email existed> }`.
8. CHECK constraint violation (23514) → 400 "That email doesn't look right."; anything else → 502 "Couldn't join right now. Try again in a bit."

Also stored: `source` (hero or footer), `country` (from Vercel's `x-vercel-ip-country` header), `referrer`.

### 7.4 Database (`db/waitlist.sql`, safe to re-run, already applied to Neon)

- Table `waitlist`: `id bigserial primary key`, `email text not null`, `created_at timestamptz default now()`, `source text`, `country text`, `referrer text`.
- Unique index on `lower(email)`.
- CHECK constraint `waitlist_email_format`: length ≤ 254, the same shape regex, no `..`.
- Index on `created_at desc`.
- Verified 15 Sep: valid email saved lowercase; the same email in caps reported as already on the list; bad formats rejected; honeypot stored nothing; a malformed email inserted straight into the DB was refused; a real hero signup landed tagged "hero". All test rows deleted, count 0.
- Arpit's plan: the same Neon database will later hold app sign-ups ("we will have a sign up page at first also, then onboarding then if users want more features from google etc they will be pinged to allow").

See signups:

```bash
psql "$DATABASE_URL" -c "select email, source, created_at from waitlist order by created_at desc;"
```

---

## 8. Brand, type and colour

- **Wordmark:** "glyf" with the accent dot at the top right after the f, raised so the dot's bottom sits at the f's top (dot 0.18em, gap 0.16em, rise 0.74em). This is the canonical mark shared with the apps (standardised 14 Sep after Arpit: "i need the dot on top right after f as we have on our keyboard").
- **Accent:** `#7c5cff`, used only as the brand dot, key dots, coach ring and highlights. Never as purple washes or borders.
- **Type:** Inter variable (local `public/fonts/Inter-Variable.ttf`), weight 600 headlines with tight tracking, Apple-like.
- **Light tokens:** background #ffffff / #f5f5f7, ink #1d1d1f, secondary #6e6e73, black pills with white text. iMessage blue #0a84ff, grey bubbles #e9e9eb. Keyboard #d5d8de with white keys.
- **Dark:** full token swap under `prefers-color-scheme: dark` and `[data-theme="dark"]`.
- **Favicon and Apple touch icon:** the app icon (`app/icon.png`, `app/apple-icon.png`).
- **Metadata:** title "Glyf · Type less. Glyf more.", description "The AI keyboard for iPhone and Android. Hold a key to search, rewrite, translate and fill in your details, right where you type. Join the waitlist.", canonical and Open Graph based on `SITE_URL`.
- **Share image (Open Graph and Twitter):** the hero itself, 1200×630 (`app/opengraph-image.png` and `app/twitter-image.png`, alt text in the matching `.alt.txt` files). Arpit, 16 Sep: "use the hero section as the og image also, set it properly". It is drawn by `tools/make_og_image.py` from the page's real layout rules (nav, headline with the inline wordmark, subline, greyed store badges, waitlist form, and the faint perspective keyboard with the same tilt, opacity and mask). Re-run `python3 tools/make_og_image.py` from the repo root whenever the hero copy or styles change. Twitter uses `summary_large_image`. Verified in the build output: `og:image` and `twitter:image` point at `https://tryglyf.com/...` with width 1200 and height 630.
- **Copy rules:** no explainer lines anywhere; no em dashes anywhere (Arpit, 16 Sep: "they look fucking disgusting ai made"); headlines are short two-line statements.

---

## 9. Theme toggle and cursor

- **Theme:** follows the system by default. The toggle stores `glyf-theme` in localStorage, and an inline script in `layout.tsx` sets `data-theme` before paint, so there is no flash. Theme colours for the browser UI are set for both schemes.
- **Cursor** (Arpit chose "Caret → keycap" on 15 Sep after hating the old dot and ring): a slim text caret follows the mouse 1:1 and grows to the size of the text under it. Over anything clickable it snaps into a keycap outline around the element and sinks on press. Mouse devices only; touch and reduced-motion visitors keep the system cursor.

---

## 10. Mobile checks done (15 to 16 Sep)

A full pass at 375×812 played all 8 chats with the autopilot, the Messages list, the finale and the footer. Found and fixed:
- Semi's list preview and banner showed the raw address.
- The footer form stayed "done" after "Add another" in the hero.
- Store badge text wrapped at 375px.
- The final banner covered the back button (banners now auto-dismiss after 6s).
- The wallet header "Private sends by MagicBlock" was clipped.
- The "Professional" label ran into its preview text (label column widened to 92px on phones).
- Messages scrolled visibly behind the contact name (header now has an iOS 26 style blur and fade).
- Tapback bubbles slightly covered the first letter (moved 3px up and left).

Not checked on phone: dark mode on the phone layout, the Messages list screen after the banner fix, and the header blur and wallet header by eye (the Browser pane was hidden, so these were checked by measurement).

---

## 11. Build, verify and traps

- **Production build:** run `next build` in a copy of `site/` (with `node_modules` symlinked) instead of inside `site/`, because building in place clobbers the running dev server's `.next` and the local site loses its CSS ("i cant see css on localhost", 13 Sep).
- **Screenshots:** use the in-app browser: navigate, screenshot, read the page. Arpit does not want page JavaScript run on other people's sites, headless Chrome scripts or background browsing agents (they triggered repeated permission prompts: "why are u asking for perms so much ... tf u executing js").
- **Hidden Browser pane:** when the pane is hidden, animation frames stop. Screenshots fail, framer-motion scroll effects freeze and CSS entrance animations stay at their first frame. Layout can still be measured with element rectangles.
- **Clicking near the bottom edge** with element refs scrolls the page and can switch chapters; click by coordinates.
- **Typing with the browser tool** does not fire keydown events, so it does not drive the demo keys.

---

## 12. Deploy on Vercel (Arpit does this)

1. Rotate the Neon password first (the connection string was pasted in chat twice). Update `site/.env.local` locally too.
2. Vercel → Add New → Project → import `The-x-35/glyf` (give Vercel's GitHub app access to the private repo if it isn't listed).
3. **Root Directory: `site`.** Framework preset Next.js, default build settings.
4. Environment variables: `DATABASE_URL` = the Neon pooled connection string (Production and Preview). `SITE_URL` is optional; leave it unset or set it to `https://www.tryglyf.com`.
5. Deploy, then Settings → Domains: add `tryglyf.com` and `www.tryglyf.com`, and set the DNS records Vercel shows at the registrar.

Done by Arpit on 16 Sep 2026: the site is live on `www.tryglyf.com`, with the apex redirecting to it. Checked right after: the page and both share images answered 200. The first deploy's canonical link and share tags pointed at the apex, which redirects, so the default `SITE` in `app/layout.tsx` was changed to `https://www.tryglyf.com`. It was pushed at 03:17 and live at 03:18, with canonical, `og:url`, `og:image` and `twitter:image` all on www and the image answering 200.

**Deploys are automatic:** the Vercel project is connected to the GitHub repo, so every push to `main` redeploys the site within about a minute. Commit and push only what should go live.

`.vercelignore` excludes `.archive` and `.env.local`.

---

## 13. Version history

**v1 · 13 Sep, about 16:41 to 19:00.** Arpit: "i want a website in next js typescript and react to showcase this glyf product, it will have a cool keyboard on site and should respond to keypresses and checkout acti and heyclicky websites ... we can show button to downloand apple and google play store ansd also a join waitlist area". Built: interactive hero keyboard (physical keys mirrored, hold P/T/U for canned skills with streamed results, 5 theme pills), features grid, black CTA with store buttons, waitlist proxied to the backend server's `/waitlist` (kv storage).

**v2 · 13 Sep, 20:33.** "use framer and motions and show functionality ... i hate explainer lines they look shit remove that ... google yt and maps search by u is soo shit we need to show results here only". Framer-motion everywhere, `SearchSuite` demo with real-looking result cards (sunset card, video cards, map card), self-looping feature demos, explainer copy removed.

**v3 · 13 Sep, 20:44 to 21:49.** "position important things and features accordingly", "also modify mouse cursor to something cool", "all the features need not be same column", "vault clipboard etc shud work too and glyf bar too", "glyf button should also work on site like on app". Sections: hero keyboard, search suite, Builder demo ("Make a key yours."), g menu ("Press g. It's all in there."), feature loops, Privacy demo ("Secrets don't leave."), Pricing ($0 40/day, $4.99 400/day, $19.99 unlimited), CTA. Custom cursor: accent dot with a ring over pressables. A CSS outage happened because a build ran while the dev server was up.

**v4 · 13 Sep, 22:37.** "the website still looks really bad, i need you to see mobbin refs, heyclicky.com openacti.com". Design-system rebuild with a big gradient headline, ambient blooms, badge pills, dot-grid texture, a dark band for search, key-to-tool marquee, stroke icons instead of emoji.

**v5 · 13 Sep, 23:03 to 23:11.** "still looks soo fucking shittt, are u idiot, see apple's design lang and make". Full Apple rewrite: only #fff / #f5f5f7 / #000 full-bleed bands, type as the design at weight 600, one lede line per section, product shown large with no decoration, black pills, thin nav. Mistakes never to repeat from v4: gradient blobs, dot grids, gradient-filled words, purple eyebrow pills everywhere, scattered chips, floating cards with big shadows, 800-weight type. Then "why is header so small, why u remove made for thumbs i love that line": nav back to 66px with a black pill, "Made for thumbs." restored as a footer statement.

**Domain and logo · 13 to 14 Sep.** Arpit bought tryglyf.com (glyf.so could not be bought). "wire it up in app and everywhere ... no need to change the glyf logo". The wordmark dot was standardised across site, iOS and Android (see section 8).

**Search UI loved · 14 Sep, 13:52.** "now the google yt and maps search u implemented on website, it looks perfect, we need that in our keyboard with exact ui ux like that". The site's search cards became the spec for the in-keyboard search suite on both apps.

**v6 · 14 Sep, 20:09.** "it still feels not good, content and things are good but not layout ... design from first principles". Split hero with the live keyboard inside a phone frame, zig-zag feature sections, bento grid, a typographic privacy moment, "Made for thumbs." as a huge sign-off, zoom steps for short laptop screens, a key remount fix.

**v7 · 15 Sep, 14:44 to 15:58.** "i need to work on website and releae it by tonight to we can have a waitlist ready. i dont like the the hero it has heading and then phone device ... i dont like every key is a glyf line ... see apple has heading and below it it had the device, so we need heading and below it the keyboard and dont show mobile on hero ... the demo keyboards on page shud share the same thing ... check xome.bot ... the dot and circle design for pointer i dont like". Decisions taken through questions: tagline "Type less. Glyf more." (after rejecting the first options as cliché), "It's all in the keys.", "Caret → keycap" cursor, "Apple highlights + sections", light and dark on site and later apps, Neon for the waitlist, Vercel + tryglyf.com. Built: hero heading with a big live keyboard below (no phone), one shared full-featured keyboard in every section with a short per-section autoplay, "It's all in the keys." tabs (Rewrite, Search, Vault, Translate, Skills), four stat sections (Hold space; Autocorrect "Fixes teh. Leaves yaar alone."; Vault on a black band; Search), a 23 Glyfs grid, FAQ, "Hold space for launch." finale, Neon waitlist route. Old site files moved to `site/.archive/v6/`.

**v8 · 15 Sep, 17:20 to 17:57.** "i dont need explainer lines anywhere, i need you to highlight vaults, search yt maps, and ai rewrite etc, and also doing calculations in keyboard, space key should say glyf ... show animations and micro interactions ... everything is happening way to fast, sections are not clearly switchable, use framer and make user go thru each section on scroll and can jump in sections on clicking ... make it premium ... you keyboard now knows stuff about u like ur name address upi id wallet addres, socials". Then the guided chat brief (section 3.1). Built: the pinned scroll stage with 8 iMessage chats, coach ring and pills, the send morph (text forms a blue bubble and glides into the thread), tapbacks, banners, list jumps with checkmarks. Nothing autoplays.

**v8.1 to v8.6 · 15 Sep evening.** Script changes (section 3.7); iMessage layout on both sizes after the WhatsApp detour; Rohan chat; sunset widget; hero backdrop keyboard; scroll autopilot; "Made for your thumbs." with a hold-space Rick Roll easter egg; vault links; scroll cue removed; greyed store badges; hardened Neon waitlist; Semi private payment with MagicBlock, wallet balance and Jupiter swap UI; real SOL/USDC icons and MagicBlock logo; Rohan AI bug fixed; Sakshi/Mumma swap.

**v8.7 · 16 Sep, 00:10 to 02:13.** Mobile verification fixes (section 10); keyboard bigger and higher on phones; Rick Roll link moved into the keyboard clipboard and the hold-space egg removed ("did u implement rick roll on space long press on last screen remove it then we dont need that"); mobile hero redesigned (section 6); em dashes removed from all copy, messages and metadata.

**v8.8 · 16 Sep, after 02:20.** The hero became the share image (Open Graph and Twitter, generated by `tools/make_og_image.py`); the nav grew to 64px with a 28px wordmark; "glyf" in the headline is now the wordmark with its raised dot.

---

## 14. Known issues and open items

- Live on www.tryglyf.com. Rotate the Neon password if that hasn't been done (it was pasted in chat twice), then update it in Vercel.
- A push to `main` deploys to production immediately (section 12).
- Brand marks (MagicBlock, Solana, USDC/Circle, Apple, Google Play) appear on a public page; check each brand's guidelines.
- Placeholders still in the vault: UPI `arpit@okbank`, phone `+91 98765 43210`.
- The waitlist throttle is per server instance (a rough limit, not a guarantee on serverless).
- Dark mode on the phone layout and the Messages list after the banner change were not re-checked visually.
- The Semi tapback 🙏 on the payment card is still there (only the emoji after "thank you" was removed; Arpit was asked and didn't reply).
- Arpit's message "and i think we can re…" (15 Sep, 23:34) was cut off; never clarified.

---

## 15. File map

```
site/
  app/
    layout.tsx            metadata, theme pre-paint script, Inter font, icons
    page.tsx              nav, hero (headline with inline wordmark, subline, store badges, form), chat stage, finale, footer
    opengraph-image.png   share image (the hero), plus twitter-image.png and .alt.txt files
    globals.css           all styles: tokens, hero, backdrop keyboard, chat, keyboard, wallet, waitlist, mobile rules
    api/waitlist/route.ts Neon insert with checks, honeypot, throttle
    icon.png, apple-icon.png
  components/
    BackdropKeys.tsx      faint perspective keyboard behind the hero
    Cursor.tsx            caret to keycap cursor
    ThemeToggle.tsx       light/dark toggle
    Waitlist.tsx          hero and footer form
    chat/Experience.tsx   pinned scroll stage, threads, banners, autopilot
    chat/scenarios.ts     the 8 chats
    kb/Keyboard.tsx       demo keyboard and panels
    kb/data.ts            vault, clipboard, search data, autocorrect, translate, calc, Solana helpers
    kb/brands.tsx         MagicBlock, SOL, USDC marks
    kb/visuals.tsx        answer card visuals
    kb/icons.tsx          icons
    kb/hub.ts             shared keyboard state helper
  lib/email.ts            email normalise and check
  db/waitlist.sql         table, unique index, check constraint
  public/fonts/Inter-Variable.ttf
  public/brands/sol.png, usdc.png
  .archive/v6/            the v6 site (not built, excluded from tsconfig and Vercel)
  .env.example            DATABASE_URL, SITE_URL
```

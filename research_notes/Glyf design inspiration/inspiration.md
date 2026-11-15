# Glyf design inspiration (researched 12 Nov 2026)

Scope: the AI chip on the keyboard strip first, then the app. Every link below was opened and returned 200 on 12 Nov 2026. Mobbin links need a Mobbin login to open. Dribbble and Pinterest render with JavaScript and gave no readable content to the fetcher, so no shots from them are cited; the Mobbin screens stand in for them.

## The short diagnosis

Today's chip is a 2pt angular gradient that rotates forever around a glass face. That is the same recipe as the iOS 18 Siri edge glow (an AngularGradient stroke with a 4 s linear repeatForever rotation, blur 9; see ref 6). Three things count against it now:

1. **Apple dropped it.** In iOS 27 the rainbow bezel glow is gone. Siri is now a dark Liquid Glass orb, and colour stays only *inside* it, in the waveform (refs 4, 5). The look Glyf borrows has been retired by the company that made it popular.
2. **It never stops.** The chip sits on the most-used surface in the phone. Emil Kowalski and Benji Taylor (Family) both say the same thing: frequent surfaces get subtle motion, and loud motion goes to rare moments (refs 21, 27). A loop that runs on every pause in typing wears people out.
3. **It is the generic AI tell.** A rotating purple-blue-pink gradient plus a glow is the most-cited "AI slop" signal of 2026 (refs 30, 31).

The fix is not "no colour". It is **colour that means something**: colour while the AI is working, quiet when it has an answer, and the brand violet held back for the one tappable verb.

---

## 1. References (30)

### A. AI suggestion surfaces and the strip

| # | Reference | What it shows | The one idea for Glyf |
|---|---|---|---|
| 1 | [Apple, WWDC25 "Meet Liquid Glass"](https://developer.apple.com/videos/play/wwdc2025/219/) | Rules for the material. Glass bends light (lensing) instead of blurring it. Elements *materialize* by ramping up the lensing, not by fading opacity. Tint only primary actions. Never put glass on glass. On touch, light starts under the finger and spreads. Small elements flip between light and dark with what's behind them. | Tint only the verb ("Insert"), never the whole chip. Make the chip appear by lensing in, not by fading. On press, put the light under the thumb. |
| 2 | [Apple Newsroom, Liquid Glass launch (Jun 2025)](https://www.apple.com/newsroom/2025/06/apple-introduces-a-delightful-and-elegant-new-software-design/) | Controls live in their own layer and morph when they need more options. Specular highlights react to device motion. | The chip is a control, so it should *morph* (grow wider for an answer, taller for a trade) rather than swap out for a new view. |
| 3 | [Apple, WWDC25 "Get to know the new design system"](https://developer.apple.com/videos/play/wwdc2025/356/) | Concentric shapes (inner radius = outer radius minus padding), capsules, hierarchy carried by layout. | Make the chip's corner radius concentric with the strip and the g key, so the pieces look like one family and not a sticker on top. |
| 4 | [MacStories, iOS 27 review: The New Siri](https://www.macstories.net/stories/ios-and-ipados-27-review/5/) | The bezel glow is gone. A dark Liquid Glass orb drops from the Dynamic Island. The multicolour waveform *inside* it is the only colour left. While thinking, the orb shrinks to a loading state. Answers come back as cards (Reminders, Notes, photos), not chat bubbles. | **Colour inside, not around.** One small coloured core with a calm frame. Shrink while thinking, expand into a card for rich answers. |
| 5 | [MacRumors, iOS 27 Siri pill grows from the Dynamic Island](https://www.macrumors.com/2026/06/16/iphone-18-could-make-siri-a-circle/) | Siri grows out of a fixed hardware anchor, and the animation hides the cutout. | The chip should grow out of the **g key** (its anchor) and shrink back into it when dismissed. |
| 6 | [vp0, Apple Intelligence glow border in SwiftUI](https://vp0.com/blogs/apple-intelligence-glow-border-effect-code-ios-free-ios-template-vibe-coding-gui) | The recipe behind today's chip: AngularGradient stroke, 4 s linear rotation, blur 9. It advises binding the animation to a real processing state so it stops when idle. | If any glow survives, it runs **only while the AI is working** and stops the moment an answer lands. |
| 7 | [Apple Support, Writing Tools](https://support.apple.com/guide/iphone/use-writing-tools-iph3f0b1cb6f/ios) | Proofread sends a glow through the text while it works, then marks each change with a glowing underline. Rewritten text arrives in segments. | **Ink underline.** Mark AI output with a thin coloured underline, not a box. Stream the answer in in segments. |
| 8 | [9to5Google, Gemini Intelligence (May 2026)](https://9to5google.com/2026/05/12/gemini-intelligence-announcement/) | Gemini's smarter autofill shows up *in Gboard's normal suggestion strip*, marked with a small spark badge. | The AI suggestion can live in the native suggestion slot, marked with a **badge** (Glyf's violet dot) instead of a decorated container. |
| 9 | [9to5Google, Gboard Rambler (Aug 2026)](https://9to5google.com/2026/08/13/gboard-rambler-prompt/) | Voice mode takes over the whole strip with a waveform and a checkmark to finish. | A mode (voice, thinking) takes over the whole strip cleanly. It doesn't pile up next to other chips. |
| 10 | [Grammarly, keyboard suggestions bar](https://support.grammarly.com/hc/en-us/articles/360009187612) | You tap a suggestion in the bar to apply it, and the brand icon in the top-left corner opens the explanation. | Tapping the brand key = "why / more". Tapping the chip = do it. Keep that split. |
| 11 | [Superhuman, Instant Reply](https://blog.superhuman.com/superhuman-ai-instant-reply/) | Draft replies are worked out before you open the email, so "you never have to wait". | The calmest loading state is none at all. Pre-fetch likely answers on pause, so the chip arrives already done more often. |
| 12 | [Raycast iOS changelog, custom keyboard (Oct 2025)](https://www.raycast.com/changelog/ios/4) | Raycast's keyboard runs AI commands, and v1.1.2 added a **cancel** action for running AI commands and dictation. | A thinking chip always has a visible way out (the ✕ cancels the request; it doesn't just hide the chip). |
| 13 | [TechCrunch, Acti (Jun 2026)](https://techcrunch.com/2026/06/30/acti-puts-ai-agents-directly-into-your-smartphone-keyboard) | Hold the Acti Bar for AI. Long-press a letter to run a Skill ("T" translates, "C" sends a meeting link). Skills are built from plain language and shared in a Skill Hub. | Skills belong *on the keys*, so the strip chip can stay about one thing: the current suggestion. |
| 14 | [AI SDK Elements, Shimmer](https://ai-sdk.dev/elements/components/shimmer) | The standard "thinking" label: a gradient sweeps through the text (about 2 s), and the text stays readable to screen readers. | For thinking, shimmer the *words* ("Working out $13…") instead of spinning the border. |
| 15 | [Mobbin, Meta AI thinking state](https://mobbin.com/screens/ccc6cae2-ce09-4d1f-8182-0ca64d9472cb) | A soft field of dots in blue tints, density drifting, under a small grey "Thinking" label. | A dot or particle loader that fits inside a 30pt chip. It also echoes the dot in Glyf's g key. |
| 16 | [NN/g, The AI sparkles icon problem](https://www.nngroup.com/articles/ai-sparkles-icon-problem/) | No participant linked ✨ to AI, and 73% read a star as save or favourite. The advice: always add a text label. | Don't add a sparkle. The violet dot plus a verb label already says "Glyf did this". |
| 17 | [Studio Output, When did AI brands become just a sparkle?](https://www.studio-output.com/thought/when-did-ai-brands-become-just-a-sparkle/) | Every AI brand converged on the same sparkle and gradient. Notion moved away on purpose. | Glyf's mark (the g plus violet dot) is the distinctive asset. Make *it* the AI signifier everywhere. |

### B. Calm and system-feel references

| # | Reference | What it shows | The one idea for Glyf |
|---|---|---|---|
| 18 | [Linear, "A calmer interface for a product in motion" (Mar 2026)](https://linear.app/now/behind-the-latest-design-refresh) | Warmer, less saturated greys, a dimmer sidebar, softer separators, fewer and smaller icons. The principles: "Don't compete for attention you haven't earned" and "structure should be felt, not seen". | The chip has to *earn* emphasis: quiet by default, louder only when it holds something worth acting on (money, a trade). |
| 19 | [Linear, "Design for the AI age"](https://linear.app/now/design-for-the-ai-age) | Chat is a weak default. AI should be a tool placed on a purpose-built "workbench", with design shaping and narrowing its output. | Glyf's AI should come back as *structured* chips (money, trade, plan), not chat text. The app is the workbench, not a chatbot. |
| 20 | [Granola via Wonder Tools](https://wondertools.substack.com/p/granolaguide) | Your own points show in black and the AI's additions in grey. | Treat AI text as a second voice: secondary label colour until accepted, primary once inserted. |

### C. App, wallet, and motion

| # | Reference | What it shows | The one idea for Glyf |
|---|---|---|---|
| 21 | [Benji Taylor, "Family Values" (Family wallet)](https://benji.org/family-values) | Trays: compact overlays, one action each, varying heights so each step reads, dark trays in dark flows. Button text morphs ("Continue" to "Confirm") and reuses shared letters. The amount travels into the confirm screen. The "delight-impact curve": rare features get bold moments, frequent ones get subtle touches. | Use trays for the trade and calendar confirms that grow out of the chip. Morph the verb ("Insert" to "Inserted", "Review" to "Confirm"). Keep the loud delight for rare moments (first trade, backup). |
| 22 | [Design Protocol, Rainbow's colour strategy](https://designprotocol.substack.com/p/rainbows-color-strategy) | One signature gradient with fixed angle and stops, used only at a few touchpoints (pull-to-refresh, icon fills). Warm neutral greys everywhere else, with calm success and error colours. | If Glyf keeps a multicolour signature, give it **one fixed recipe** and **two or three places** to appear (thinking core, onboarding hero, app icon). Everything else stays neutral. |
| 23 | [925 Studios, Phantom design breakdown](https://www.925studios.co/blog/phantom-wallet-design-breakdown) | Plain-language transaction previews (what leaves, what arrives) before signing. One decision per screen. Restrained colour signals safety. | The trade chip's confirm says it in plain words: "You pay $10 · You get 0.033 TSLAx". |
| 24 | [Mobbin, Phantom trade screen](https://mobbin.com/screens/69408841-8479-48ad-b7d2-2a0d13d5d049) and [Fuse swap](https://mobbin.com/screens/7aba1ed6-413b-44c1-912d-fd0ad795efd8) | Fuse has huge numerals, labels in grey, one black Review button, and nothing else. Phantom has dark cards with token pills and a lavender primary. | Wallet screens are type-led: the number is the hero and every other element steps back. |
| 25 | [Mobbin, Lightyear limit order](https://mobbin.com/screens/85a6fa25-2a92-4e90-9f58-5f104ea5d1a0) and [Revolut market buy](https://mobbin.com/screens/6c1ea3b9-4e4b-47ef-b08d-a87ac9377b47) | Lightyear puts the condition in a pill under the title ("If it drops to $2.95 or less"). Revolut leads with the amount (-US$1.99), lists the facts in a grey card, and ends with one Submit. | The trade chip reads like Lightyear's pill: "Buy $10 TSLA · at $300". The tray reads like Revolut: amount, then facts, then one button. |
| 26 | [Mobbin, Notion "Create automation"](https://mobbin.com/screens/3bb80d6e-3fab-4fd4-a8f7-04a596ae67af) | A sentence-shaped builder: **When** (trigger card, + Add trigger), a thin connector line, then **Do** (action card, + Add action). | The "build your own action" screen is a When / Do sentence, not a form. |
| 27 | [Emil Kowalski, "Great Animations"](https://emilkowal.ski/ui/great-animations) | Keep most motion under 300 ms. Ease-out. Make it interruptible. Springs over curves. Don't animate actions people repeat hundreds of times a day. Respect reduced motion. | Chip entry under 250 ms with a spring. No idle loop. Typing-triggered changes don't animate. |
| 28 | [9to5Google, Android 16 Material 3 Expressive](https://9to5google.com/2025/05/13/android-16-material-3-expressive-redesign/) | Motion as a theme: *spatial* springs for movement, *effects* springs for colour and opacity. | One spring set across both keyboards: a spatial spring for the chip growing out of the g, an effects spring for the tint fading in. Android gets parity for free. |
| 29 | [Create with Swift, numericText content transition](https://createwithswift.com/animating-numeric-text-in-swiftui-with-the-content-transition-modifier) | Digits roll up or down when a number changes. Use `.monospacedDigit()` so they don't jitter. | Live prices in the money and trade chips *roll* to the new value instead of blinking. |
| 30 | [Mobbin, Wispr Flow keyboard setup flow](https://mobbin.com/flows/a743edfe-4338-4537-984b-17f173f3212d) | Big serif display headlines ("Let's set up Flow"), a lavender accent, a progress bar, and a step where you *try it live*: dictate an email and watch it get formatted. | Onboarding has the user perform the magic inside a real text field (Glyf's site already does this with chat levels). An editorial display face for headlines only, never in the keyboard. |

### Supporting (trends and things to avoid)

- [Six Colors, "Soaping up Liquid Glass" (Nov 2025)](https://sixcolors.com/post/2025/11/soaping-up-liquid-glass-less-transparency-more-contrast/) and [TidBITS, iOS 26.1 Tinted option](https://tidbits.com/2025/10/21/ios-26-1-to-add-optional-opacity-to-liquid-glass/): people pushed back on Clear glass legibility, so Apple added Tinted. Test the chip with Tinted on and with Reduce Transparency on.
- [Apple HIG, Playing haptics](https://developer.apple.com/design/human-interface-guidelines/playing-haptics): pair one light impact with appear (or none), one selection tick on Insert, and a success notification only for a confirmed trade.
- [Nothing OS](https://lk.nothing.tech/nothing-os): the dot-matrix identity is now "applied more selectively" for readability. Dots work as an *accent*, not as a typeface for content.
- [Design Compass, Dia browser](https://designcompass.org/en/2025/06/13/dia-ai-web-browser/): AI lives inside a familiar control (the address bar) rather than a new surface. It backs the "native slot" chip.
- [925 Studios, AI slop design tells](https://www.925studios.co/blog/ai-slop-design-tells) and [Creative Boom, trends creatives are over in 2026](https://www.creativeboom.com/insight/10-trends-creatives-are-so-over-in-2026/): the purple-blue gradient, glow on everything, and generic Inter-plus-gradient looks.
- [Mobbin, Revolut / Fidelity / Wealthsimple / QuestMobile order reviews](https://mobbin.com/screens/4bd5c3cc-8fef-441d-a707-3c5aff325873): all four use the same proven layout (title, then a facts list, then one button).
- [Mobbin, Glow "Slide to Swap" with Retry pill](https://mobbin.com/screens/0b82feb8-e8e1-42ca-bd46-1ab3f100b415): when a quote fails, the error shows as a grey *Retry* pill in place of the value, not a red banner.

---

## 2. Strip chip: seven directions

Fixed for all of them: a ~30pt tall chip, vertically centred, the g key on the left, ✕ on the left of the chip, the verb on the right, and the keyboard following the host's light/dark setting. "Accent" means #7C5CFF. In dark mode, lift it to about #9B85FF for contrast on dark glass (check that it reaches 4.5:1 on the verb text).

### D1. Aurora Core (keeps colour, done with taste) ★ recommended pair with D3
- **Look, light:** a neutral glass capsule (Liquid Glass regular, or on iOS 18 and Android a `secondarySystemBackground` with a 0.5pt separator hairline). **No coloured border.** Inside the leading edge, just right of the ✕, sits a 14pt blurred *core*: a three-stop mesh of violet #7C5CFF, indigo ~#5B6CFF and orchid ~#C35CF0 at about 70% opacity. Text in label colour. Verb in accent, semibold.
- **Look, dark:** same structure. The core glows a little more (it gains a 6pt outer blur), and the text is white at 92%.
- **Motion:** idle has no loop; the core holds still. **Thinking:** the core drifts slowly (8–10 s) and its light leaks along the bottom edge as a 1pt line that travels left to right. **Answer:** the core settles over 300 ms and the leak fades.
- **Accent:** the core and the verb carry it, and nothing else does.
- **Backed by:** iOS 27 Siri (colour inside the orb, ref 4), Rainbow's one-recipe, few-touchpoints rule (22), Liquid Glass "tint primary only" (1), vp0's "bind the glow to state" (6).

### D2. Liquid Lens (most Apple-native)
- **Look:** a real iOS 26 `glassEffect(.regular)` capsule whose radius matches the g key's (3). The verb segment is the only tinted part, `.tint(accent)`, so it reads as a small violet glass button inside the chip. In dark mode, the glass picks up the host's darkness on its own.
- **Motion:** the chip **materializes** as the lensing ramps up (1) from the g key's position (5), with a spatial spring (28). On press, light spreads from the thumb (1). Dismissing it morphs it back into the g key.
- **Accent:** only the tint on the verb.
- **Backed by:** refs 1, 2, 3, 5. Android needs a fallback (frosted surface plus hairline), so this one costs more to keep in parity.

### D3. Ink Line (quiet, typographic) ★
- **Look:** no container at all. The suggestion text sits in the strip at the size of Apple's suggestion bar (17pt, ref: Glyf keyboard-parity notes) in secondary label colour, like Granola's grey AI voice (20). A **1.5pt accent underline** runs under the suggestion. The verb is accent-coloured text with no background. The ✕ is a 13pt SF Symbol in tertiary colour.
- **Dark:** the underline goes to the lifted violet. Nothing else changes.
- **Motion:** on arrival the underline *draws* left to right in 220 ms (ease-out) and the text fades up 2pt. On Insert, the underline collapses to the left in 120 ms and the verb morphs to "Inserted" (21).
- **Accent:** the underline and the verb.
- **Backed by:** Writing Tools' glowing underline (7), Linear's calm (18), Emil's under-300 ms rule (27).

### D4. Native Slot (quietest, Gboard-style)
- **Look:** the chip *is* a suggestion-bar slot. Same hairline dividers as the three word slots, same 17pt type. A **6pt violet dot** (the dot from the g key) sits before the text as a badge, like Gemini's spark (8). When the AI chip shows, it takes the full width of the strip. The verb is plain accent text at the far right.
- **Motion:** the word slots crossfade into the AI slot (effects spring, 180 ms). No other motion.
- **Accent:** the dot and the verb.
- **Backed by:** Gboard plus the Gemini spark (8), Dia's AI-in-a-familiar-control (supporting), NN/g's "label it, skip the sparkle" (16).

### D5. Quiet Halo (single-hue breathing glow)
- **Look:** a solid surface capsule (keyboard key colour, so it reads as a wide key) with a 0.5pt separator border. While thinking, a 1pt **inner** ring of accent breathes between 0% and 40% opacity; nothing outside the chip glows. At rest it is just a calm key-coloured pill with an accent verb.
- **Motion:** the breathing runs at 2.4 s, ease-in-out, **thinking only**. When the answer lands, the ring flashes to 60% once and settles to 0 over 400 ms, so you see it finish.
- **Accent:** the ring (while thinking) and the verb.
- **Backed by:** refs 6, 18, 27. It is the cheapest to build on both keyboards.

### D6. Dot Field (brand-driven thinking state)
- **Look:** the idle and answer states can be D3 or D4. The thinking state is a 5×3 grid of 2pt dots in the leading slot, in accent tints, rippling in density (like Meta AI's field, ref 15). It **resolves into the violet dot** of the badge when the answer arrives.
- **Motion:** the ripple runs at 1.2 s per wave. On resolve, the dots converge into the badge dot with a spatial spring.
- **Accent:** the dots, then the badge dot.
- **Backed by:** Meta AI (15), Nothing's selective dot-matrix (supporting), the g plus dot mark (17).

### D7. Grow-from-g (motion system; layers on any of D1–D6)
- **Look:** the g key and the chip share one shape. The chip is literally the g pill stretching right.
- **Motion:** appearing stretches the pill from 41pt to the chip's width (spatial spring, response ~0.35, damping ~0.85), with the text fading in after 60% of the stretch. ✕ shrinks it back into the g. The verb morphs letters ("Insert" to "Inserted", "Review" to "Confirm") as in Family (21). Trade and calendar chips continue *up* into a tray above the keyboard instead of opening the app.
- **Backed by:** the iOS 27 Siri pill grows out of the Dynamic Island (5), Family trays and text morph (21), Material 3 Expressive springs (28).

**Recommendation:** use **D3 Ink Line or D4 Native Slot for idle and answer states, D1 Aurora Core *only* while thinking, and D7 for motion.** Colour then means "Glyf is working", and calm means "here's your answer". Build D5 as the fallback for low-power mode and Reduce Motion.

---

## 3. Best pattern for each state

| State | Best pattern found | Concretely for Glyf | Refs |
|---|---|---|---|
| **Idle suggestion** | A labelled suggestion in the native slot with a small brand badge | Violet dot, then text in secondary colour, then the verb in accent. Static. A light haptic on appear, or none. | 8, 16, 20 |
| **Thinking** | A coloured core or shimmer bound to real work, with a visible cancel | The prompt echo shimmers ("Converting $13…", ~2 s sweep) or the Aurora core drifts. ✕ cancels the request. After about 4 s the label turns to "Still working…". Never an endless spinning border. | 4, 6, 12, 14 |
| **AI answer** | Arrives in segments and grows to fit; precomputed when possible | The chip widens with a spring while the text streams in segments. The verb appears only when the answer is complete. Text shifts from secondary to primary on Insert. | 7, 11, 20, 21 |
| **Money / price** | Two-tone type with rolling digits | "$13 = **€12.04**": source in secondary, result in primary semibold, monospaced digits. Live prices roll with numericText. A tiny 4pt green or red tick only on a change, never a constant pulse. (Per Glyf's global-product rule, demos use $ and €, not ₹.) | 24, 29 |
| **Trade / order** | A condition pill plus a plain-language review tray | Chip: "Buy $10 TSLA · at $300" with the verb **Review** (not "Buy"). Tapping grows a Family-style tray: big amount, "You pay $10 · You get 0.033 TSLAx", price rolling, then Phantom approval. The success haptic fires only after the signature. | 21, 23, 25 |
| **Calendar plan** | A card that shows the result, not the request | "Thu 3:00–3:30 · you're free" with a 3-dot mini day bar (busy, free, busy). Verb: **Add**. Tapping grows a tray with the event card and a Meet toggle, like Siri's answer cards. | 4, 21 |
| **Error** | A neutral state with a Retry pill, not red alarm | The chip drops its colour (no core, no underline). Grey text says one plain reason ("No price for $XYZ") and the verb becomes **Retry**. A `.warning` haptic. It auto-hides after 4 s and feeds the ✕ cooldown. | Glow Retry pill (supporting), 18 |

---

## 4. The app: four visual directions

### App-1. Calm Workbench (Linear × Granola × Things)
Warm greys (less blue than iOS defaults), one accent, dense grouped lists, few icons and small ones, dimmed navigation. AI output shows in grey until accepted. The home screen is a quiet "today" list: recent glyfs, wallet balance in one line, and the next plan. **For:** home, settings, My glyfs. **Refs:** 18, 19, 20.

### App-2. Trays and Morphs (Family)
Every action is a tray over the current screen, with varying heights per step and a dark tray in dark flows. Button labels morph. Amounts travel between screens. Delight is saved for rare moments: the first trade, wallet connect, and code redeem (confetti is fine there and nowhere else). **For:** wallet, trade, onboarding sub-steps, gift codes. **Refs:** 21, 25.

### App-3. Native Glass (iOS 26 / 27 done right)
The tab bar and toolbars are system Liquid Glass. Content is flat and opaque (no glass cards). The accent tints only primary buttons. The tab bar shrinks on scroll. Test with Tinted and Reduce Transparency. This is cheapest on iOS and most "Apple-like simple", but needs a Material 3 Expressive mapping on Android. **For:** the app shell and settings. **Refs:** 1, 2, 3, 28, Six Colors.

### App-4. Editorial Money (Fuse × Phantom × Wispr Flow)
Type-led: huge tabular numerals for balances and amounts, labels in grey, one primary button. A display serif (or Inter Display tight) appears only for onboarding and empty-state headlines, and never inside the keyboard. Onboarding is "try it live" in a real text field. **For:** wallet and trade, onboarding, the paywall. **Refs:** 24, 25, 30.

**Suggested mix:** App-3 shell + App-1 lists + App-2 flows + App-4 money screens. The "build your own action" screen is Notion's **When / Do** sentence (26). Its natural-language box sits at the top, like Acti (13): type "when I write a $ amount, show it in euros", and Glyf fills in the When and Do cards, which the user can then edit.

---

## 5. Motion and material: use vs. avoid

**Use (current, 2025–26):**
- Springs over curves. One spatial spring for movement and one effects spring for colour and opacity, shared on iOS and Android (27, 28).
- Liquid Glass *only* on controls, materializing (lensing in) rather than fading. Tint only the primary action (1).
- Shape continuity: grow from an anchor (the g key), morph instead of swap (2, 5, 21).
- Text morph on button labels, and rolling digits on prices (21, 29).
- Haptics paired with meaning: a selection tick on Insert, success only on a signed trade, a warning on an error. Nothing on plain appear (HIG haptics).
- State-bound glow that runs only while working (6).

**Dated or overused (avoid):**
- **Rotating rainbow or conic borders** (the 2024 Siri glow). Apple retired it in iOS 27, and it is exactly what the chip does today.
- Unlabelled ✨ sparkle icons (16, 17).
- Purple-to-blue gradients and glow on every card, the top "AI slop" tell (supporting refs).
- Endless idle loops on frequent surfaces (27, 21).
- Glass on glass, glass content cards, and Clear glass without dimming (1, Six Colors).
- Generic AI orbs and blobs as the loader in every app (Mobbin shows Linktree, Brainly and Beside all doing it).
- "Typing…" three-dot bubbles for AI, chat bubbles for structured answers (19), and confetti on routine actions.

# Strip policy: words or a chip, and what a ✕ means

Decided 4 Nov 2026, after Arpit: "sometimes when the suggestion strip chips come and the user crosses it (✕), it comes again and again ... it should not be irritating and it should be useful at the same time." Both keyboards follow this table. The code is `StripPolicy` (iOS `GlyfKeyboard/Engine/StripPolicy.swift`, Android `ime/StripPolicy.kt`), with the same numbers and the same tests (`RunnerTests/StripPolicyTests.swift`, `StripPolicyTest.kt`). The chips keep their look and rules (magic border, ✕ on the left, Insert as the default, centred on the g key, money with cents, an instant "AI answer" for questions); this page only decides **when** a chip shows.

## 1. Which one owns the strip (first match wins)

| # | Situation | The strip shows |
|---|---|---|
| 1 | Password or secure field | Nothing |
| 2 | One-time code, card number, number, phone or date box | Only a saved detail, a copy (digits only on a digit pad) or a temp-mail code. No answers, AI, plans or pay. |
| 3 | The "original" undo slot right after an autocorrect fix | Words (the undo, then predictions) |
| 4 | Typing a word that has word suggestions, with a fix pending (space would change it) | Words, always |
| 5 | Typing a word that has suggestions, no fix pending | Words. A chip may take over after a **1.0 s** pause. |
| 6 | At a word boundary (after a space or punctuation), or the word has no suggestions (digits, "2+5") | The chip, once the fingers have been still for **0.4 s** |
| 7 | A saved detail completing the word being typed ("ar" → your name) | The chip, after 0.4 s; it counts as a word, so rule 5 doesn't hold it back |
| 8 | A chip already on screen that still applies | It stays (no flicker while rates or the AI answer land) |
| 9 | Nothing to offer, or the chip isn't allowed (section 2) | Words, or the tools |

When several chips could show, roughly the existing order in `Smart.chip` and `updateSmartChip` still picks one: a temp-mail code, then the field's own ask (an empty email box), a copy, on-phone answers (sums, money, conversions, dates, weather), a saved detail the sentence leads into, plans and booking pages, pay, then "AI answer" and the server's suggestion (asked only after a 700 ms pause). The chip leaves as soon as the person types again and the offer no longer applies.

## 2. Dismissal memory

| Event | Effect | Number |
|---|---|---|
| ✕ on a chip | That chip (its kind and what it offers) never comes back in this field, even for the same text typed again. | Field's lifetime |
| ✕ on a chip | No other new chip of any kind for a short while. | 8 s |
| ✕ on a chip | That kind of chip rests in this app. The kinds are fill, paste, answer, ai, plan, pay and mail. | 10 min |
| 3 ✕ of one kind within a day, in any apps | That kind rests everywhere. | 24 h |
| Typed past: 2 new words while the chip was up for at least 1 s, unused | That chip is gone for the field, and the 8 s quiet starts. | |
| Typed past twice for one kind in one app | Counts as one ✕ for that kind. | 2 |
| Tapping a chip | The typed-past count for that kind in that app starts over. | |
| A copy's chip | Once per copy: used, ✕ or typing in the field ends it. It is offered only for 3 min after the copy (the clipboard panel keeps it 10 min, history 48 h). A ✕ on one copy doesn't rest the next copy in that app, but it does count toward the daily 3. | 3 min |
| A temp-mail code | Never muted: a code is what the field is waiting for. Each mail's chip shows once, as before. | |
| The tour | Not under this policy: the coach keeps the chips it teaches. | |

**What counts as the app.** On iOS this is the host's bundle id via `HostAppID`, unless `voiceReturn` is off. iOS 26.4 and later answer nil, and then the field's `documentIdentifier` stands in, so on those versions the 10 minutes rest that kind in that field. On Android it is `EditorInfo.packageName`. The field is the document id on iOS, and `packageName/fieldId` on Android.

**Storage.** iOS keeps it in `strip-policy.json` in the App Group bridge folder. Android keeps it in the `glyf_ime` prefs under `stripPolicy`. Expired entries are pruned on every ✕, at most 48 entries per map are kept, and a field's own memory is never stored. Scenario runs reset it: iOS `open()` deletes the file, and Android's `fresh()` sends the `policyreset` debug tool.

## 3. Why these numbers

- **0.4 s settle.** Fast typists' keys land 150 to 250 ms apart, so 400 ms is a real pause, and a chip that appears in the middle of a burst gets typed past. Smart Compose has to answer within about 60 to 100 ms, but it fires on almost every keystroke and only above a confidence bar ([Chen et al., KDD 2019](https://arxiv.org/abs/1906.00080)). VS Code can hold inline suggestions back with `editor.inlineSuggest.minShowDelay` ([Posit docs](https://deploy-preview-228--positron-posit-co.netlify.app/assistant-completions.html)). Horvitz's LookOut waited for the user's attention before offering anything ([CHI 1999](https://www.erichorvitz.com/chi99horvitz.pdf)). On-phone answers are still instant once the fingers stop.
- **Words win mid-word, and a fix always shows.** Apple's QuickType puts the original word in quotes in the left slot when autocorrect would change it, so you always see what space will do ([iMore](https://www.imore.com/how-use-quicktype-keyboard-iphone-and-ipad), [MacMost](https://macmost.com/how-to-troubleshoot-iphone-auto-correct-problems.html)). In the iOS 27 beta, Write with Siri shrinks to a small button beside the three predictions as soon as you type ([9to5Mac](https://9to5mac.com/2026/06/22/ios-27-beta-write-with-siri/)). Quinn and Zhai found that looking at suggestions costs time, and that showing them too often slows typing even when they save keystrokes ([CHI 2016](https://research.google/pubs/a-costbenefit-study-of-text-entry-suggestion-interaction/)).
- **A ✕ is remembered.** Apple's HIG says to act on explicit feedback at once, persist it, and make sure hidden content doesn't show up elsewhere ([HIG, Machine learning](https://developer.apple.com/design/human-interface-guidelines/machine-learning)). Microsoft's Guidelines for Human-AI Interaction ask for efficient dismissal and memory of recent interactions ([Amershi et al. 2019](https://www.microsoft.com/en-us/research/project/guidelines-for-human-ai-interaction/)). Gboard's "remove suggestion" is permanent ([Gboard help](https://support.google.com/gboard/answer/7068415)). Grammarly's dismiss applies to that suggestion, and "turn off suggestions like this" applies to the whole category ([Grammarly](https://support.grammarly.com/hc/en-us/articles/360045784631)).
- **10 min per app.** That is about one conversation. Android 16's notification cooldown quiets a repeating source for up to 2 minutes ([Android Authority](https://androidauthority.com/android-16-notification-cooldown-3501276)); a chip the person put away by hand gets longer. Kept to that app, so one Messages thread doesn't decide for every app.
- **3 a day → 24 h.** Three separate no's in a day are a pattern, not a mood. A day, not forever, because Google's PAIR guidebook treats a dismissal as an ambiguous signal ([PAIR, Feedback + Control](https://pair.withgoogle.com/chapter/People%20+%20AI%20Guidebook%20-%20Feedback%20+%20Control.pdf)); the Suggestions switch is still there for "never".
- **Typed past twice = one ✕.** Ignoring a chip is a weaker no than a ✕ (PAIR again). LookOut's ignored offers stepped back on their own (Horvitz 1999). Two words past is the soonest that is clearly not a glance. The 1 s minimum means a chip that only flashed by isn't held against anyone.
- **8 s quiet.** About one sentence at 40 words a minute, so the next chip doesn't land on the same thought as the ✕.
- **3 min for a copy, shown once.** Copying and switching to paste takes seconds. Gboard and SwiftKey keep the copy itself about an hour, and SwiftKey offers it in the prediction bar ([Android Authority](https://www.androidauthority.com/manage-clipboard-on-android-3255552/), [SwiftKey support](https://support.microsoft.com/swiftkey-keyboard/how-to-use-microsoft-swiftkey-keyboard-to-copy-and-paste-text-between-swiftkey-and-windows)). How long Gboard's chip itself lasts isn't published. Glyf's panel keeps the copy 10 min and its history 48 h, so the strip doesn't need to keep offering it.
- **Codes never muted.** A temp-mail code is the person's own request, and each mail already shows once. Glyf has no warning chips to protect (the send-guard was dropped, 3 Oct 2026).

Not verified anywhere public: Gboard's paste-chip lifetime, whether its chip returns after typing past, and Acti's chip rules. Acti's features all start from the user (the Acti Bar, holding a letter); nothing public describes chips that appear on their own ([TechCrunch](https://techcrunch.com/2026/06/30/acti-puts-ai-agents-directly-into-your-smartphone-keyboard)).

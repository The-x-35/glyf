# Strip backlog: what the strip could answer next

From a research pass on 7 Oct 2026 (Raycast, Apple's keyboard, Gboard, SwiftKey, Wispr Flow, Fleksy, Typewise, TextExpander/Text Blaze, Samsung Writing Assist) against what Glyf's strip already does, after Arpit asked for suggestions that feel "crazy helpful in all scenarios". Each line: what the person types → what the strip shows → what a tap does. Effort S/M/L. **Status** is for the iPhone; Android follows (OPEN-ITEMS.md section 7).

## Done on 7 Oct

| # | Trigger → chip → tap | Status |
|---|---|---|
| 1 | "pizza", "happy birthday", "lol" → 🍕 🎂 😂 in the last slot → adds it after the word | Done |
| 4 | A form box declared as city or state → the city/state from the saved address → Insert (email, phone, name, postcode, address, company already worked) | Done |
| 5 | "need: milk, eggs, bread" → "• List", "1. List" → one item a line, in place | Done |
| 21 | "when are you free?", "send me your calendar link" → the person's own booking page → Insert | Done |
| 6 | "pizza, burgers or pasta?" (three or more options) → "Make it a poll" → the options on 1️⃣ 2️⃣ 3️⃣ lines plus "reply with a number" | Done |
| 8 | "hop on a quick call?", "can we talk", "send me the meet link" → "Add a Meet link" (Meet connected) → the link in the message | Done |
| – | The person's own name(s) from the vault are words to the engine ("hi arpit" no longer offers armpit) | Done |
| – | "100 usd to inr", "0.5 btc", "half of 350", "sqrt 81", "what time is it in tokyo", "how long until 5pm" → the answer (found by the message probe, not the research) | Done |

## Done on 8 Oct (both keyboards)

From a second probe of 150 everyday messages and a research pass (Raycast, Alfred, Espanso, Text Blaze, Gboard, Omni calculators):

| Trigger → chip | Notes |
|---|---|
| "time difference with london", "how far ahead is tokyo" → London is 5h ahead | |
| "100f in c", "30 c to f" → 37.8°C | no degree sign needed |
| "5'10", "whats 5'10 in cm" → 178 cm · 1.78 m | |
| "bmi 70kg 175cm", "my bmi at 180 lbs and 5'10" → BMI 22.9 | only with the word "bmi" |
| "be there in 15", "call you back in 5" → the clock time then | minutes left unsaid |
| "was $120, now $90" → -25% · save $30 | |
| "3 pack for 12.99", "1.5kg for 9" → 4.33 each, 6/kg | no currency sign needed |
| "add 18% tip to 64", "emi 500000 at 9% 5 years" | wider wording |
| "what day is 25 december 2026" → Friday; "what week is it" → Week 41 | |
| "roman numeral 2026" → MMXXVI; "MMXXVI in numbers" → 2026 | |
| "rgb 255 87 51" → #FF5733; "base64 hello"; "uuid" | in place |
| "tracking number 9400…" → USPS tracking | |
| "emergency number uk" → 999 · UK; "emergency number" → where the phone is | checked table only |
| "what does ngl mean", "iykyk meaning" → not gonna lie | ~130 chat abbreviations |
| "lets meet at blue bottle on 3rd st", "im at central park" → Add a map link | Google Maps search link after the place; not times, "home", "the airport" |
| "got 43/50 on the quiz" → 86% | needs a score word |
| "avg of 85, 92, 78" → 85 avg · median 85; "sum of 12, 30 and 8" → 50 | |
| "extra 10% off 20% off $80" → $57.60 · 28% off; "buy 2 get 1 free $12 each" → $8 each | |
| "save $500/mo for 10 yrs at 7%" → $86,542 | |
| "300 miles at 65 mph" → 4 h 37 min | |
| "when do the clocks change" → Sun, Nov 1 · back 1 h | from the phone's zone |
| "zone 2 heart rate age 34" → Zone 2: 112–130 bpm | 220 − age |
| "x^2" → x², "\alpha" → α; "solve 2x+5=17" → x = 6; "x^2-5x+6=0" → x = 2, 3 | |
| "chicken internal temp" → 165°F · 74°C; "substitute for buttermilk" | USDA chart; ~30 swaps |
| "ooo until monday" → a one-line out-of-office reply with the date | in place |
| "Best," on its own line → Sign as (saved name) | |
| A copied message with a code → the code first in the paste chip | |
| Fixes: Amazon order numbers aren't sums, "per my last email" offers nothing, "what are you doing tonight" isn't a plan, "3pm pst" keeps PST (est/ist/gmt/utc too) | |

Still open from the research: calories per food (USDA table, ~100 KB), several zones for one meeting time, shoe and clothing sizes (brands differ; needs care), airport codes, sunset/golden hour, carry-on limits, inflation, exact fractions.

## Done on 14 Oct (both keyboards)

| Trigger → chip | Notes |
|---|---|
| "thank you in spanish", "how do you say good night in japanese" → gracias, おやすみなさい | 27 everyday phrases in 13 languages, in place, no AI run; gendered ones stay quiet |
| "lunch friday 1pm?" → "Lunch · Fri 1 PM · busy: Dentist" | the plan chip says when the calendar already has something then |
| Typing the first words of a sentence sent three times → the rest | phone only, never passwords, codes, links or long numbers; forgotten after 60 days |
| "remind me to call mom tomorrow" → a 9 AM event | a reminder with a day and no time |
| "sunset", "sunrise tomorrow", "golden hour" → Sunset 8:35 PM | computed on the phone (NOAA) where it last was |
| "is it going to rain", "weather tomorrow" → No rain expected tomorrow (1%) | Open-Meteo, keyless, from the phone; needs the shared location |
| Currency rates | straight from Frankfurter; the server only as a fallback |

## Next, no server needed

| # | Trigger → chip → tap | Effort |
|---|---|---|
| 3 | Return means Send (iMessage, WhatsApp) and a new line is wanted → hold Return inserts a line break (Gboard-style) | S |
| 7 | "sam's number", "ria's email", "mum's address" → "Sam Lee · (415) 555-0123" from Contacts → Insert (needs Contacts access in the keyboard; the Search suite has it in the app) | M |
| 2 | "are you free friday?", "does 3pm work?" → "Fri · 2 events · free after 3 PM" from the phone's calendar → Insert or open the day | M |
| 9 | "meet at Blue Bottle on 3rd st" → "Add a map link" → an Apple/Google Maps search link | S |
| 11 | "remind me to call the bank tomorrow", "call me in 5 minutes" → "Remind · Tomorrow 9 AM" → a Reminder (EventKit, needs the permission) | M |
| 12 | The same 15+ character phrase committed three times in a month → "Save ';omw' for this" → the shorthand editor, prefilled | M |
| 14 | A sentence ends and the engine knows of words it would have fixed → "2 typos · Fix" → spelling fixes only, instant | M |
| 15 | After an autocorrect, for a few seconds → "Changed 'ket' to 'key' · Undo" | S |
| 17 | X/Threads fields (keyboardType .twitter) → a quiet "212/280" count, red past the limit | S |
| 18 | "you owe me $20", "send me 20 usdc" → "Request $20 · Solana Pay link" → a solana: URL Phantom opens | M |
| 13 | Shorthand with arguments: ";meet {who} at {time}" asks for each when expanded; {clipboard}, {date format=…}, {calculator} | M |
| 16 | Inline grey completion of the person's own repeated phrases ("on my" → "way!"), space accepts | L |
| 10 | "where are you", "I'm here" → "Send my location" (needs the keyboard's own location permission) | M |
| 20 | Text selected in WhatsApp/Telegram/Slack (Android knows the app) → Bold · Italic · Strike · Mono with that app's markup | M |

## Needs the server or a provider decision

| # | Trigger → chip → tap | Note |
|---|---|---|
| 22 | "thanks in spanish", "how do you say sorry in french" → "gracias · Insert" | translate route; spends the suggest allowance |
| 23 | "what does ephemeral mean" → the definition · Insert | the AI answers today; a keyless system-dictionary path is worth checking |
| 26 | A copy over ~600 characters → the paste chip gains "Summarize" | AI |
| 27 | A fresh screenshot → "Reply to this" → three replies | needs a vision-capable model in the chain |
| 28 | WhatsApp vs Gmail (Android) → "Tidy this up" keeps slang or goes formal | Android only; iOS can't know the host app |
| 29 | "Tidy this up" shows a count ("3 fixes · Tidy") | S |
| 30 | "Shorter · Softer · More formal" under any AI result | S |
| 19 | "lol", "congrats" → one KLIPY sticker tile | KLIPY key still owed on Railway |
| 24 | "how long to get to the airport" → "28 min by car" | MapKit on iOS; Android needs a provider the founder names |
| 25 | "is it raining there", "weather tomorrow?" | no weather provider chosen yet |

## Raycast, translated

1. The strip is root search: every on-device answer shows within a frame of the word boundary, the tap is only the action.
2. Chain answers: hold a chip for Insert · Copy · Replace · "Use as input" ("$120 split 4" → "30 each" → "30 in inr" → "₹2,500").
3. Placeholders and arguments in shorthand (#13).
4. A Builder glyf with a strip keyword (";fr" → translate to French, output replaces the sentence).
5. Quick Fix as a gesture: double-tap Shift fixes the sentence's spelling on the phone (#14).

## Anti-patterns to keep out

Correcting a word the person already fixed; any chip work on the typing thread; sending the sentence to get a chip; upsells in the keyboard; putting words in people's mouths (feelings only on request, never auto-inserted); half answers (a range, a lone weekday, "50% sure" stay quiet); two strips or stacked chips; re-ranking a chip while it is visible; explainer lines and consent pop-ups in the strip; changing key geometry or the person's tool order.

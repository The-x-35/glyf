# Glyf scenario run

Run on 17 September 2026: the real keyboards (iPhone 17 Pro simulator, Android API 36 emulator) and the dev server with live models. Scripts: `qa/server-scenarios.mjs`, `app/ios/GlyfM0UITests/GlyfScenarioUITests.swift`, `qa/android-scenarios.mjs`.

99 pass, 2 need a key, 0 fail, of 101.

| ID | Where | Scenario | Result |
| --- | --- | --- | --- |
| S01 | Server | Rough reply to a manager: 'ya ok will send deck b4 6' | pass |
| S02 | Server | Apology for being late: 'sry running late traffic is crazy' | pass |
| S03 | Server | Hinglish offered in India: 'kal meeting shift kar do please' | pass |
| S04 | Server | No Hinglish row for someone in the US | pass |
| S05 | Server | Shorter version is actually shorter | pass |
| S06 | Server | A rewrite never pastes a Google link | pass |
| S07 | Server | Chip intent forced to rewrite keeps the whole sentence | pass |
| S08 | Server | Friend asks for your address; your saved address fills in | pass |
| S09 | Server | Details are never volunteered where nobody asked | pass |
| S10 | Server | 'best biryani near indiranagar' gives a list of places | pass |
| S11 | Server | 'nearest atm' gives the one place | pass |
| S12 | Server | 'cafes near me' uses the phone's rough location | pass |
| S13 | Server | 'send me the dune part 2 trailer' finds the video | pass |
| S14 | Server | 'weather in bangalore tomorrow' is a live answer, not a guess | needs a key |
| S15 | Server | Nothing found inserts nothing (no link pasted) | pass |
| S16 | Server | Maths in a question: '18% of 2450' answers 441 | pass |
| S17 | Server | A rough message gets 'Tidy this up' | pass |
| S18 | Server | A place list gets 'Show me places' | pass |
| S19 | Server | A plain question gets no 'Look it up' chip | pass |
| S20 | Server | Three words in, no chip yet | pass |
| S21 | Server | Hinglish 'kal milte hain office ke baad' comes out in English | pass |
| S22 | Server | English goes to your other language (Hindi) | pass |
| S23 | Server | Devanagari detected without asking the model | pass |
| S24 | Server | Tamil message comes back in English | pass |
| S25 | Server | Tapping the direction to Spanish sends it to Spanish | pass |
| S26 | Server | A Spanish-speaking phone: Spanish text goes to English second language | pass |
| S27 | Server | Web search for 'ipl points table' | needs a key |
| S28 | Server | YouTube search for 'arijit singh live' | pass |
| S29 | Server | Maps search for 'third wave coffee' | pass |
| S30 | Server | Tap 'Say no, politely' and a glyf is made | pass |
| S31 | Server | Tap 'Turn it into a LinkedIn post' and it is made | pass |
| S32 | Server | The preview runs the new glyf on a sample message | pass |
| S33 | Server | A description too short to build is refused cleanly | pass |
| S34 | Server | Wallet config is there for the app's Privy login | pass |
| S35 | Server | A card number is hidden from the model and comes back exactly in every version | pass |
| S36 | Server | Bad requests get a 400, not a crash | pass |
| S37 | Server | An OTP in a message survives every rewrite untouched | pass |
| S38 | Server | Translating a message keeps the account number exactly | pass |
| S39 | Server | '100 usd to inr' converts at today's rate | pass |
| S40 | Server | 'what is a black hole' answers from Wikipedia | pass |
| S41 | Server | 'sunset' gives today's sunset where you are | pass |
| S42 | Server | 'lofi beats playlist' finds a video to send | pass |
| S43 | Server | 'hotels in goa' lists hotels in Goa | pass |
| S44 | Server | Emoji-heavy banter keeps its meaning | pass |
| S45 | Server | A normal rewrite comes back in under 6 seconds | pass |
| S46 | Server | A long rambling message still gets every version | pass |
| S47 | Server | A message in Hinglish still gets 'Tidy this up' | pass |
| S48 | Server | 'Fix my grammar' becomes a glyf that works on a sample | pass |
| S49 | Server | Mixed Hinglish with English words detected as Hindi | pass |
| S50 | Server | A place's own name finds that place | pass |
| S51 | iPhone | A typo in a sentence is fixed on space | pass |
| S52 | iPhone | Two spaces end the sentence | pass |
| S53 | iPhone | The next word is predicted | pass |
| S54 | iPhone | Backspace right after a fix puts the word back | pass |
| S55 | iPhone | A space after a number brings the letters back | pass |
| S56 | iPhone | Holding delete clears words | pass |
| S57 | iPhone | Sliding on the space bar moves the cursor | pass |
| S58 | iPhone | Return starts a new line | pass |
| S59 | iPhone | Shorthand expands | pass |
| S60 | iPhone | A sum in a message offers the answer | pass |
| S61 | iPhone | Asked for your address, it is one tap away | pass |
| S62 | iPhone | Asked for your UPI, it is one tap away | pass |
| S63 | iPhone | A rough message offers Tidy this up | pass |
| S64 | iPhone | Hold space: pick the Professional version | pass |
| S65 | iPhone | Holding a version copies it instead | pass |
| S66 | iPhone | Hold space on a place search sends places | pass |
| S67 | iPhone | Hold space on a trailer sends the video | pass |
| S68 | iPhone | Hold space on a currency sum answers it | pass |
| S69 | iPhone | Hold space with nothing typed opens Ask | pass |
| S70 | iPhone | g opens the tool menu, not Vault | pass |
| S71 | iPhone | Menu → Vault card types the detail | pass |
| S72 | iPhone | Something just copied pastes from the clipboard | pass |
| S73 | iPhone | Recent screenshots show in the clipboard | pass |
| S74 | iPhone | The emoji key inserts an emoji | pass |
| S75 | iPhone | Emoji pages swipe sideways, like Apple’s | pass |
| S76 | iPhone | Emoji search finds pizza | pass |
| S77 | iPhone | Translate as you type, then Replace | pass |
| S78 | iPhone | The direction can be changed | pass |
| S79 | iPhone | Search YouTube and send the video | pass |
| S80 | iPhone | Hold T to translate | pass |
| S81 | iPhone | Hold S for Vault | pass |
| S82 | iPhone | Dark mode keys are dark, light mode keys white | pass |
| S83 | iPhone | Strip tools open in one tap | pass |
| S84 | Android | A typo in a sentence is fixed on space | pass |
| S85 | Android | Texting shorthand stays as typed | pass |
| S86 | Android | A space after a number brings the letters back | pass |
| S87 | Android | A sum in a message offers the answer | pass |
| S88 | Android | Asked for your address, it is one tap away | pass |
| S89 | Android | Asked for your UPI, it is one tap away | pass |
| S90 | Android | A rough message offers Tidy this up | pass |
| S91 | Android | Hold space: pick the Professional version | pass |
| S92 | Android | Hold space on a place search sends places | pass |
| S93 | Android | The g button opens the tool menu | pass |
| S94 | Android | Copied text pastes from the strip | pass |
| S95 | Android | Translate as you type, then Replace | pass |
| S96 | Android | Emoji key inserts an emoji | pass |
| S97 | Android | Slide left from delete removes whole words | pass |
| S98 | Android | A screenshot you just took is in the clipboard | pass |
| S99 | App | Make a glyf from an idea and hold its key | pass |
| S100 | App | Onboarding, then the guided tour | pass |
| S101 | Android | Dark mode keys are dark, light mode keys are light | pass |

## Fixed during the run

- Server: Card numbers, CVVs, OTPs, PINs, passwords, ID numbers, API keys and recovery phrases went to the AI models inside messages. Masked before every model call and put back in the reply. No model sees one; the rewrite still has it.
- Server: A search with nothing found pasted a Google link into the message. Nothing goes in; the panel says Nothing found and keeps Google one tap away.
- Server: “best biryani near indiranagar” and “nearest atm” found no places; addresses read like database rows. The area is found first and searched around; addresses read the way a person writes them.
- Server: Picking Spanish on the translate strip still translated to Hindi; Hinglish showed as “Hindi (Hinglish)”. A hand-picked direction always wins; languages show by plain name.
- Server: A stalled model left a rewrite hanging 9 to 12 seconds. A model that hasn’t started answering in 4 seconds is skipped for the next.
- Server: Rewrites turned “b4 6” into “before you”; Basic came back unchanged. Every version keeps times, numbers and names; Basic cleans the message up.
- Server: A built glyf answered a chat message with a formal email full of [Name] placeholders. Glyfs write text ready to send, as long as the message they answer.
- Android: The strip had no sum answers, no “my address is” details, no Pay chip and no Tidy this up. The whole smart strip is ported from iOS, rule for rule, with the same tests.
- Android: Holding space didn’t pass saved details to the AI. It does, when “Let AI use your saved details” is on, like iOS.
- iPhone: Tidy this up never appeared when a message ended with a space. Fixed: the suggestion is matched on the trimmed sentence.
- Both: After a number and a space, the keyboard stayed on numbers. Letters come back after the space, like Apple’s keyboard and Gboard.
- Both: “sry” was autocorrected to “dry”. 92 everyday shorthand words (sry, tmrw, rn, lmk, omw, ngl…) are left as typed.
- Both: Rewrite versions showed two and a half rows over a wasted bottom bar. The list fills the panel; retry sits in the header.
- iPhone: The clipboard didn’t offer what you had just copied. “Paste what you copied” sits on top until it is used.
- Both: VoiceOver couldn’t reach menu tiles, clipboard cards, versions or the strip chip; toasts were silent; TalkBack read out internal ids. Every control has a spoken name; toasts are announced.
- App: Screens said “Translation HUD”, “Vault picker”, “Humanize”, with explainer lines under options. Vault, Translate, Rewrite. No explainers.
- App: Onboarding’s Google step showed a server setup error naming environment variables. The step only appears when Google sign-in works; errors never name server settings.
- Both: glyf:// links (the tour, Build your own, Pay) opened a second Home on top of the right screen. Flutter’s own link routing is off; the app handles its links.
- App: On Android the tour started with the keyboard down, or up but not reading the message. Each level brings the keyboard up attached to the message box.
- Both: A tour closed by force left its rings on the keyboard. Hints expire and are cleared when the app starts.

## Needs a key or account

- Web results: Brave Search API key. S27 shows only the Google hand-off row without it.
- Weather answers: Google Weather or web search key. S14 honestly says nothing found without it.
- Google sign-in: OAuth client id and secret. The onboarding step stays hidden until then.
- Ratings and open now: Google Places key (or Geoapify, free, for no-card places). Places come from OpenStreetMap on the dev server today.

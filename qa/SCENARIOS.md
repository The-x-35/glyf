# Glyf scenario run

Run on 24 and 25 September 2026 (the two app flows, S99 and S100, by hand on 17 September): the real keyboards (iPhone 17 Pro simulator, Android API 36 emulator) and the dev server with live models. Scripts: `qa/server-scenarios.mjs`, `app/ios/GlyfM0UITests/GlyfScenarioUITests.swift`, `qa/android-scenarios.mjs`.

128 pass, 2 need a key, 2 fail, of 132.

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
| S102 | iPhone | Emoticons type straight into the message | pass |
| S103 | iPhone | The GIF tab shows GIFs and copies one | pass |
| S104 | iPhone | The Stickers tab shows stickers and copies one | pass |
| S105 | iPhone | GIF search shows results for the word | pass |
| S106 | Android | Emoticons type straight into the message | pass |
| S107 | Android | The GIF tab shows GIFs and hands one over | fail |
| S108 | Android | The Stickers tab shows stickers and hands one over | fail |
| S109 | iPhone | New Event from the keyboard's calendar lands in the calendar | pass |
| S110 | iPhone | A plan in a message offers Add to calendar | pass |
| S111 | Android | New Event from the keyboard's calendar lands in the calendar | pass |
| S112 | Android | A plan in a message offers Add to calendar | pass |
| S113 | iPhone | A Meet link, then a time on a Cal.com page | pass |
| S114 | iPhone | A Meet-only grant: the event on the phone with a Meet link | pass |
| S115 | iPhone | Book a time on your page for someone, with a guest | pass |
| S117 | Android | Without Google, the camera sends no other kind of call link | pass |
| S118 | Android | Book a time on your own page for someone, with a guest | pass |
| S120 | Android | Someone's booking page in a message offers Book | pass |
| S121 | iPhone | A Meet link from the calendar, with Google connected | pass |
| S122 | iPhone | New Event with a guest goes to Google Calendar, which invites them | pass |
| S123 | iPhone | Without Google: no call link, no Video call, the event goes into the message | pass |
| S124 | iPhone | A key held for a Meet link | pass |
| S125 | Android | A Meet link from the calendar, with Google connected | pass |
| S126 | Android | New Event with a guest goes to Google Calendar, which invites them | pass |
| S127 | Android | Without Google, New Event goes into the message | pass |
| S128 | Android | A key held for a Meet link | pass |
| S129 | iPhone | The strip starts with Glyf's key, the site's pill a little taller, light and dark | pass |
| S130 | Android | The strip starts with Glyf's key, the site's pill a little taller, light and dark | pass |
| S131 | iPhone | Snake from the g menu turns with a swipe | pass |
| S132 | iPhone | Chomp eats its way along the maze | pass |
| S133 | Android | Snake from the g menu turns with a swipe | pass |
| S134 | Android | Chomp eats its way along the maze | pass |

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
- Both: glyf:// links (the tour, Build your own, Pay) opened a second Home on top of the right screen, and a link that started the app was dropped. The app handles its own links, including the one that launched it.
- App: On Android the tour started with the keyboard down, or up but not reading the message. Each level brings the keyboard up attached to the message box.
- Both: A tour closed by force left its rings on the keyboard. Hints expire and are cleared when the app starts.
- iPhone: The g button, the suggestion card and Close sat 3pt above the keyboard’s top edge, where VoiceOver and UI tests can’t reach them. They stay inside the keyboard and keep their centre.
- Server: “18% of 2450” and “what is 12 x 12?” were tidied as messages; an answer pasted as “441 — 18% of 2450”. Worded sums reach the calculator and paste the card’s sentence: “18% of 2450 is 441”.
- Server: The Tidy this up chip took about 9 seconds: two model calls ran one after the other. They run together; the chip shows in about 3.5 seconds.
- Android: Search suggestions went out without the signed-in session and were turned away. They carry the session like every other call.
- Both: A 38-character webhook secret (whsec_…) reached clipboard history, and Android refused a copied Ethereum address. One shared filter on both keyboards: known key prefixes (webhook, Stripe, GitLab, AWS, Google and more), JWTs and random tokens are never kept; wallet addresses are.
- Both: An emoticon glued itself to the word before it (“swqaerm:-)”). It is spaced off the word, the way an emoji is.
- Android: The keyboard asked the photo index for screenshots on its main thread; right after a screenshot, with storage busy, Android reported it as not responding. Screenshots load in the background and join the clipboard when found; GIF and sticker files are written off the main thread too.
- Android: After a screenshot was copied, the strip’s paste chip read the image as text: its label held the PNG’s bytes, about 200,000 characters, read on the main thread. Only text (or a web link) counts as a copy for the chip, Paste, the g bar, skills and history; a picture is left as a picture.
- Both: Refusals and limit messages used dashes (“Too fast — wait a moment”). Plain sentences: “Too fast. Wait a moment and try again”.
- Android: Book a time glued its line to the link before it (“cal.com/sam-lee/introBooked for…”). Whatever the calendar types is a sentence of its own, as on iPhone.

## Needs a key or account

- AI suggestions and quick hold space: Credit on OpenRouter (the $10), and FAST_MODELS on Railway set to the new chain in server/.env.example. The strip's suggestions read on small paid models through OpenRouter (about $20 to $30 a million reads) and never spend a run; hold space and chip taps write on Gemini 2.5 Flash-Lite through OpenRouter, all six versions in about 1.3 s. The key answered on 25 September with no credit, which won't last: without it the chip shows only what the phone's rules catch, and hold space falls back to Gemini's free tier (about 4 s).
- GIFs and stickers in the emoji board: KLIPY_APP_KEY on Railway (it is in the local server/.env since 24 September). Without it the GIF tab says GIFs aren't set up yet and Stickers shows Noto animated emoji. Real KLIPY GIFs and stickers were checked on both keyboards with the local key.
- Google Calendar and Meet: The Calendar API and Meet REST API switched on, and their two scopes added to the consent screen, in Google Cloud. No key or secret: the phone talks to Google. S121 to S128 ran against qa/fake-google.mjs, and the booking scenarios against qa/fake-scheduling.mjs, never a real account or a real person's calendar.
- Web results: Brave Search API key. S27 shows only the Google hand-off row without it.
- Weather answers: Google Weather or web search key. S14 honestly says nothing found without it.
- Google sign-in: OAuth client id and secret. The onboarding step stays hidden until then.
- Ratings and open now: Google Places key. Places come from Geoapify on the dev server today, without ratings.

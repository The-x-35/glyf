# What the server does, and what could run on the phone

Written 10 Oct 2026 after Arpit asked: "i need to know what all is happening from railway server, and out of it what all of it can we shift to local device, ig conversions etc are happening thru formulas only that dont need net or server, but i need to know other things too, tell me in detail". From a read of every route in `server/src/routes/`, the libraries in `server/src/lib/`, the 30 tools in `server/src/registry/tools/`, `server/src/env.ts`, and every place the iOS keyboard, Android keyboard, Flutter app and website call the server. Nothing was changed while writing it. BACKEND.md is the full reference for each route; this page is the map of what runs where.

The server runs on Railway at `https://api.tryglyf.com` (BACKEND.md section 13).

## In one paragraph

Almost everything the strip works out (sums, units, money maths, dates, time zones, lists, polls, BMI, calories and the rest of `Smart.quickAnswer`) and all of typing (autocorrect, predictions, learning, glide) already run on the phone with no network. The server does three jobs: **AI** (the AI key must stay secret, and the server counts each account's daily runs), **calls to providers that need a secret or paid key** (web search, YouTube, Google Places, map images, the paid Solana RPC), and **anything kept in the shared database** (sign-in, plans and purchases, gift codes, usage limits, reports, telemetry, the Skills hub). A few routes pass through the server with no real reason and can move to the phone: currency rates, token prices, animated emoji stickers, Cal.com booking, and the keyless tools.

## AI model chains

All AI goes through OpenRouter (`OPENROUTER_API_KEY`); a model id prefixed `groq:`, `gemini:`, `cerebras:`, `mistral:` or `inception:` goes to that provider's own key instead. The chains are code constants in `server/src/env.ts` (environment variables don't change them; see the AI models notes).

| Chain | Models, in order | Used by |
|---|---|---|
| fast | Qwen 3.7 Flash → Gemini 2.5 Flash Lite (nitro) → Gemini 2.5 Flash Lite | Act's router, rewrite and write; glyf runs; translate; vocabulary packs |
| smart | Ling 3.0 Flash → Gemini 2.5 Flash Lite… | Builder |
| answer | Gemini 3.1 Flash Lite → Qwen 3.7 Flash → … | Factual answers |
| suggest | Qwen 3.7 Flash → Gemini 2.5 Flash Lite → Ling 3.0 Flash | The strip's AI read |

## The database on every request

Two things touch Neon whatever the route: the gate in `server/src/lib/protect.ts` spends a per-IP and a per-user minute counter in `glyf_usage`, and with `DATABASE_URL` set the `glyf_kv` mirror is refreshed before each request (`server/src/index.ts`, around line 65). Sessions are checked against `SESSION_SECRET` with no database read. "Metered" below means the run is counted against the account's plan (free: 20 runs, 100 suggestions and 100 translations a day).

## Every route

| Route | What it does | Who calls it, and when | Outside services and keys | Database | On the phone instead? |
|---|---|---|---|---|---|
| POST /act | Hold space: works out whether you want places, a video, an answer, a rewrite (six streamed versions) or writing, then does it | Both keyboards: hold space, or a strip chip that acts | OpenRouter fast + answer; Places, Geoapify, YouTube through search; Jupiter prices; Open-Meteo; Serper or Brave when set | Metered (a run is spent only when a model is asked) | **Partly.** The keyboards already answer sums and simple questions themselves first (`Smart.instantAnswer`); the model step needs the secret key and the metering |
| GET /p/:id | The shared places page a /act link opens | Whoever opens the link in a chat | none | `pages` | **No:** needs a public website |
| POST /glyf/run | Runs a glyf (prompt chain plus tools) as a stream | Both keyboards: hold a bound letter, or the Glyf Bar | OpenRouter; the tools' sites; Google and Notion tokens kept on the server | Metered; `connections`, `userglyfs` | **No:** the prompts and keys are private |
| GET /glyf/catalog | Lists the shipped glyfs | nobody (the app has its own copy) | none | none | Already static in the app; the route is unused |
| POST /suggest | The strip's AI chip: rules first, then the suggest model | Both keyboards: a pause while typing | OpenRouter suggest | Own daily allowance | **Partly:** the rules are already twinned in Smart; the model read stays |
| POST /translate | The translate bar | Both keyboards | OpenRouter fast | Own daily allowance | **No**, short of an on-device translation model |
| POST /search | Web, YouTube and Maps tabs as cards | Both keyboards: Search, YouTube, Maps | Serper (`SERPER_API_KEY`), Brave (`BRAVE_SEARCH_KEY`), YouTube (`YOUTUBE_API_KEY`), Google Places (`GOOGLE_PLACES_KEY`), Geoapify (`GEOAPIFY_KEY`), Nominatim (development only), Open-Meteo, Jupiter; the answer chain as a last resort | Metered only for the AI fallback | **No** for the providers (keys; Brave's terms forbid caching). Its instant answers are already on the phone |
| GET /search/photo | A Places photo, fetched so the key stays hidden | Both keyboards: Maps card pictures | Google Places | none | **No:** key |
| GET /search/staticmap | A map picture for a place with no photo | Both keyboards | Geoapify | none | **No:** key |
| GET /search/suggest | What a tab shows before you type: trends, popular or liked videos, places nearby | Both keyboards: opening a tab | Google Trends RSS (keyless); YouTube (key, or the person's Google token on the server); Places Nearby (key) | `connections` | **Partly:** the web trends are keyless; YouTube and Maps need keys |
| GET /search/status | Which search providers are set up | nobody | none | none | — |
| GET /rates/fiat | Currency rates per dollar | Both keyboards: money chip, money in hold space | Frankfurter (European Central Bank figures), keyless | none | **Yes, easily** |
| GET /rates/crypto | A cashtag's price (token or tokenized stock) | Both keyboards: `$sol`, `$aapl` | Jupiter lite API, keyless | none | **Yes** (the app already calls Jupiter) |
| GET /rates/token | What a copied Solana address is | Both keyboards: address chip, Pay panel | Jupiter lite API | none | **Yes** |
| POST /wallet/rpc | Passes a short allowlist of Solana calls to the network | Both keyboards' Pay panels; the app's wallet | `SOLANA_RPC_URL` (paid; **not yet set on Railway**) | none | **Partly:** a free public endpoint works but is slow and rate-limited |
| GET /media/config | Hands the KLIPY key to a signed-in phone | Both keyboards: GIFs and stickers | `KLIPY_APP_KEY` (**not yet set on Railway**) | none | **Keep:** the key can be changed without an app update. KLIPY itself is already called from the phone |
| GET /media/emoji-stickers | Searches Google's animated emoji list (a 29 KB file) | Both keyboards: Stickers tab | none (the images load from fonts.gstatic.com) | none | **Yes:** bundle the file |
| GET /scheduling/slots, POST /scheduling/book | Open times on someone's Cal.com page; books one | Both keyboards: Book a time | Cal.com v2, keyless (120 calls a minute per address) | none | **Yes**, and better spread across phones |
| POST /tools/run | Runs one keyless tool | nobody (the keyboards have the call but never use it) | the tool's site | none | **Yes** for the keyless tools |
| POST /report | Flags an AI result | Both keyboards: Report in the AI panel | none | `glyf_reports` | **No:** shared database |
| GET /meter/:deviceId | Runs left today and the plan | iPhone keyboard (runs chip); app (plan card) | none | usage, users | **No** |
| POST /vocab/generate | Word and phrase packs from a description | App | OpenRouter fast | Metered | **No** |
| POST /builder/generate, /builder/test | Builder writes and tries a glyf | App | OpenRouter smart, fast | Metered | **No** |
| /glyfs (list, save, delete) | The person's own glyfs | App | none | `userglyfs` | **Partly:** could live on the phone, but sharing needs the server |
| /skills, /skills/creators, /skills/get, /hub/publish, /hub/list, /hub/install, /account/name, /account/:id/creator | Skills hub | App (/hub/list and /hub/install unused) | none | `userglyfs`, `hub`, accounts, installs | **No:** shared |
| /connectors/status, /oauth/*/start, callbacks, /connectors/disconnect | Connects Notion, Slack, GitHub, Linear, Todoist, Calendly, Zoom, Spotify (Google too, though Google now signs in on the phone) | App | each provider's `*_CLIENT_ID` and `*_CLIENT_SECRET`, `OAUTH_REDIRECT_BASE` | `oauth_pending`, `connections` | **No:** client secrets |
| /connector/mockcal/* | A demo calendar | nobody | none | none | Delete |
| /auth/config, /auth/session, /auth/review | Sign in with Apple or Google → a Glyf session; the App Review account | App | Apple's and Google's signing keys; `SESSION_SECRET`, `REVIEW_PASSWORD`, `REVIEW_MODE` | users, purchases | **No** |
| /me, /me/prefs, /me/events, /me/plan, DELETE /me | Account, settings, events, plan, deleting the account | App (/me/plan unused; needs `PLAN_SELF_SERVE`) | none | users, prefs, events | **No** |
| /billing/apple, /billing/apple/notifications | Checks App Store purchases; Apple's server notices | App; Apple | Apple's signature, `APPLE_BUNDLE_ID` | purchases, users | **No:** otherwise anyone could give themselves Max |
| POST /codes/redeem | Gift code → plan | App | none | `glyf_codes`, purchases | **No** |
| POST /telemetry, GET /telemetry/funnel | Counts | App (/funnel unused) | none | `telemetry`, `devices` | **No** |
| POST /waitlist, GET /waitlist/count | Waitlist | **nobody**: the website writes its own Neon table (`site/app/api/waitlist/route.ts`) | none | `waitlist` | Dead code |
| GET /health | Which providers are set up | App (status dot) | none | none | — |

The website never calls the server.

## The 30 tools

Tools run inside glyfs (`/glyf/run`) and act; the code is `server/src/lib/tools.ts`.

| Tool | Provider (as coded) | Key | On the phone? |
|---|---|---|---|
| time.now | computed | none | Fully on the phone |
| fx.convert | Frankfurter | none | On the phone with the cached rates |
| holidays.next | Nager.Date | none | Keyless call, or on the phone (`Smart.holiday` already knows many) |
| country.info | REST Countries | none | Keyless, or bundled data |
| quote.crypto | Jupiter lite API (the tool's description wrongly says CoinGecko) | none | Keyless |
| stocks.quote | Jupiter tokenized stocks (the description wrongly says Stooq) | none | Keyless |
| weather.now | Open-Meteo forecast + geocoding | none | Keyless |
| air.quality | Open-Meteo air quality + geocoding | none | Keyless |
| route.eta | Open-Meteo geocoding + the OSRM demo server | none | Keyless, but the OSRM demo isn't for production use |
| wiki.summary | Wikipedia | none | Keyless |
| dict.define | dictionaryapi.dev (flaky) | none | Keyless |
| word.synonyms | Datamuse | none | Keyless |
| urban.define | Urban Dictionary | none | Keyless |
| books.search | Open Library | none | Keyless |
| news.tech | Hacker News (Algolia) | none | Keyless |
| sports.next | TheSportsDB | public test key | Keyless |
| recipes.search | TheMealDB | public test key | Keyless |
| food.info | Open Food Facts | none | Keyless |
| repo.info | GitHub (60 calls an hour per address) | none | Keyless, better spread across phones |
| joke.random, quote.inspire, advice.random, fact.random | icanhazdadjoke, ZenQuotes, Advice Slip, uselessfacts | none | Keyless |
| web.search | DuckDuckGo Instant Answer | none | Keyless |
| url.unfurl | Fetches the given link | none | **Better on the phone**: see the security risk below |
| maps.search, places.search | Nominatim | none | Partly: OpenStreetMap allows one call a second and wants an app name; fine per phone |
| yt.search | YouTube Data API | `YOUTUBE_API_KEY` | Server |
| calendar.today | Google Calendar with the token on the server | Google client secret | Could move: the phones already hold their own Google sign-in |
| notion.search | Notion | Notion client secret | Server |

## Already on the phone, no server

- **Typing:** autocorrect, predictions, learning, glide typing (`Engine/Typing/*`, `ime/typing/*`).
- **The strip's instant answers** (`Smart.quickAnswer`, both keyboards): sums and sums in words, units, temperatures, heights, money maths with the cached rates, time zones and city times, time differences, "until 5pm", "back in 15", bills, tips, splits, discounts, loans, savings, unit prices, dates and days of the week, holidays, ages, week numbers, clock changes, cooking, safe temperatures, kitchen swaps, calories, BMI, heart-rate zones, pace, drive time, roman numerals, equations, x², colours, base64, UUIDs, tracking and flight links, phone links, slang meanings, emergency numbers, map links, lists, polls, out-of-office lines, sign-offs, coins and dice. List with examples: STRIP-BACKLOG.md.
- **Hold space, first try:** `Smart.instantAnswer` answers sums and simple questions before anything is sent.
- **Your details:** vault detection ("my email is"), form boxes, completions, sign-offs (Smart's `details` twin of the server's `details.ts`).
- **Question detection** for the "AI answer" chip (Smart's twin of the server's `infoQuestion` and `rightNow`).
- **Temp mail:** mail.tm, called from the phone (its terms forbid proxying).
- **GIFs and stickers:** KLIPY, called from the phone (only the key comes from the server).
- **Google Calendar and Meet:** created with the phone's own Google sign-in; Android also writes to the phone's calendar.
- **Wallet:** Jupiter swaps and Phantom signing from the phone; MagicBlock private sends from the app.

**Computation the server and phones share.** `units.ts` and the maths, days, clock and currency parts of `answers.ts` are duplicated in Smart. Server only: `sun.ts` (sunrise and sunset; Smart has none), the weather, Wikipedia and geocoding parts of `answers.ts`, and the rule half of the act router (`planByRules`, `needsTidy`, `roughEnough`, `checkPlan` in `act.ts`). `reading.ts` is the AI read for the strip, not a formula.

## What could move to the phone, best first

| Move | Effort | What it gains |
|---|---|---|
| Currency rates straight from Frankfurter, cached for an hour | Very small | The money chip works without the server |
| **Done 14 Oct 2026.** Animated emoji stickers bundled (the 29 KB list plus its search): `NotoStickers` + `NotoCatalogue` on both keyboards, regenerated by `tools/gen_noto_stickers.py`, held to `shared/stickers/noto-cases.json` (recorded from the server's search). /media/emoji-stickers stays for older versions | Small | Instant, works offline |
| **Done 14 Oct 2026.** Cashtag and token prices straight from Jupiter: `TokenLookup` on both keyboards (the server's `tokenQuote`, `tokenAt`, `pickToken`, `pickStock`, the name list), /rates/crypto and /rates/token only when Jupiter can't be asked | Medium | `$sol`, `$aapl` and copied addresses work without the server |
| **Done 14 Oct 2026.** Cal.com booking from the phone: `CalBooking` on both keyboards (the link parsing, `bookingUrl`, the slots, event-types and bookings calls); /scheduling/slots when Cal.com can't be reached, /scheduling/book only when the booking never left the phone (or Cal.com said 429), so nothing is booked twice. Calendly links out, as before. The setting `calcomBase` points the phones at qa/fake-scheduling.mjs | Medium | No shared rate limit |
| Weather and sunrise/sunset as strip answers (Open-Meteo, keyless, plus a port of `sun.ts`, about 100 lines) | Small to medium | New answers that cost no AI runs |
| Web trends for the Search tab's landing (Google Trends RSS, keyless) | Small | One fewer server call |
| Keyless tools as strip answers (definitions, synonyms, Wikipedia, holidays, country facts, recipes) | Medium each | Answers without spending runs. Inside glyfs they still run on the server: moving those means splitting the glyf engine, which is a large job |
| /glyf/catalog and the demo calendar | None | Delete; the app has its own catalog |

## Must stay on the server

- **AI:** act's model step, glyf runs, the strip's AI read, translate, vocabulary packs, Builder and the search AI fallback. They need the AI keys, the private prompts, and per-account metering and burst limits. The only alternative is a model on the phone.
- **Search providers and their images:** Google Places, YouTube, Geoapify, Serper and Brave keys; Brave's terms forbid caching.
- **The wallet relay:** the paid RPC key.
- **The KLIPY key handout:** so the key can be rotated.
- **Shared data:** sign-in, accounts, purchases, gift codes, reports, telemetry, usage limits, the Skills hub, the OAuth broker (client secrets and stored tokens), and the shared places pages.

## Problems found (10 Oct 2026)

| # | Severity | Problem | Where | Fix |
|---|---|---|---|---|
| 1 | High | **url.unfurl fetches any link it's given**, including private and internal addresses (an SSRF risk: someone could make the server read Railway's internal network) | `server/src/lib/tools.ts`, around line 201 | Refuse private, loopback, link-local and metadata addresses after resolving the name (and on every redirect); or run it on the phone |
| 2 | Medium | **Every request touches Neon** (the minute counters and the KV refresh), even /health and /rates | `server/src/lib/protect.ts`, `server/src/index.ts` | Skip the gate and the refresh for public read-only routes; count in memory with a short flush |
| 3 | Low | Dead code: /waitlist (the website writes its own table), /connector/mockcal, /glyf/catalog, /tools/run (no caller), /me/plan, /hub/list, /hub/install, /telemetry/funnel | routes | Remove, or keep with a note |
| 4 | Low | Two tool descriptions name the wrong provider: quote.crypto says CoinGecko, stocks.quote says Stooq; both use Jupiter | `server/src/registry/tools/quote.crypto.json`, `stocks.quote.json` | Correct the descriptions |
| 5 | Owed | `SOLANA_RPC_URL` and `KLIPY_APP_KEY` are not set on Railway | Railway variables | Arpit adds them |

None of these were fixed when this was written; Arpit was asked whether to go ahead (moves in the order above, the security fix first).

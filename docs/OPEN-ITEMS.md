# Open items

Everything pending, blocked or owed, in one place. **Owner** is who has to act: Arpit (accounts, keys, money, logins, design calls) or Build (code work). Area docs have more detail: [WEBSITE.md](WEBSITE.md), [APPS.md](APPS.md), [BACKEND.md](BACKEND.md).

Last updated: Tue 22 Sep 2026 (IST).

---

## 1. Launch the website

| # | Item | Owner |
|---|---|---|
| W1 | Rotate the Neon database password (it was pasted in chat twice). Update it in Vercel and `site/.env.local` | Arpit |
| W2 | ~~Deploy on Vercel with domains~~ **Done 16 Sep:** live on www.tryglyf.com, apex redirects to www | Arpit |
| W3 | ~~Point canonical and share URLs at www~~ **Done 16 Sep 03:18:** pushed to `main`, Vercel redeployed automatically (the project is connected to the GitHub repo), and the live page now uses `https://www.tryglyf.com` everywhere | Build |
| W4 | Sign up once on the live site and check the row lands in Neon. The live API answers (email checks verified), but the database connection wasn't tested, to avoid putting a test row into the real list | Arpit |
| W5 | Share the link somewhere (iMessage, WhatsApp, X, LinkedIn) to see the preview card. Tags and images are live and correct | Arpit |
| W6 | Brand use: MagicBlock, Solana, USDC (Circle), App Store and Google Play marks appear on the page. Check their guidelines or ask MagicBlock | Arpit |
| W7 | Replace the vault placeholders if wanted: UPI `arpit@okbank`, phone `+91 98765 43210` | Arpit |
| W8 | Decide whether Semi's 🙏 reaction on the payment card stays (only the emoji after "thank you" was removed) | Arpit |
| W9 | Arpit's message "and i think we can re…" (15 Sep, 23:34) was cut off and never clarified | Arpit |
| W10 | Visually re-check on a phone: dark mode, the Messages list screen, the header blur, and the hero after the nav and wordmark changes (checked by measurement while the preview pane was hidden) | Build |
| W11 | The waitlist rate limit is per server instance; add a shared limit if spam shows up | Build |

## 2. Backend deployment and keys

| # | Item | Owner |
|---|---|---|
| B1 | Deploy `server/` to a host and point `api.tryglyf.com` at it. Until then, release app builds and TestFlight testers have no AI | Arpit (host choice) + Build |
| B2 | Add `GEMINI_API_KEY` (aistudio.google.com/apikey) and `GROQ_API_KEY` (console.groq.com/keys) to `server/.env`. Free OpenRouter models are slow and often out of quota | Arpit |
| B3 | Add `GEOAPIFY_KEY` (free, no card) for Maps and nearby places | Arpit |
| B4 | Optional: `BRAVE_SEARCH_KEY` for real web result links (needs a "Powered by Brave" line) | Arpit |
| B5 | YouTube Data API key: add restrictions, file the quota extension early (default 100 searches a day), regenerate after deploy | Arpit |
| B6 | Google OAuth client (`GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET`) with redirect URIs for local and `https://api.tryglyf.com/oauth/google/callback` | Arpit |
| B7 | OAuth client pairs for Notion, Slack, GitHub, Linear, Todoist, Calendly, Zoom, Spotify (each lights up when its pair is in `server/.env`) | Arpit |
| B8 | `KLIPY_APP_KEY` for GIFs (free at partner.klipy.com; request production access once "Search KLIPY" shows). The GIF, sticker and emoticon tabs are built; stickers work without it (Noto) | Arpit |
| B9 | About $10 of OpenRouter credit, if OpenRouter stays in the model chain | Arpit |
| B10 | Benchmark Hinglish quality on the chosen models with about 50 real messages once keys are in | Build |
| B11 | Gemini free tier terms: it trains on what's sent and excludes apps likely used by under-18s. Paying removes most of this | Arpit (decision) |

## 3. Apps

| # | Item | Owner |
|---|---|---|
| A1 | Upload TestFlight build 3 (version 1.0.0, build 3, export compliance set). Build 2 is the last confirmed upload | Arpit |
| A2 | App Store Connect: create the Plus ($4.99) and Max ($19.99) in-app purchase products; then Build adds StoreKit and server receipt validation | Arpit, then Build |
| A3 | Google Play Console setup and a signed Android release build | Arpit + Build |
| A4 | Real-device checks the simulator can't do: the 45 MB keyboard memory budget, haptics, the real microphone for dictation, the ripple performance profile | Arpit (device) + Build |
| A5 | Lock the final bundle IDs and signing team before real users (changing later breaks update persistence) | Arpit |
| A6 | App sign-up page backed by the Neon database, then onboarding, then incremental Google permission requests (Arpit's plan from 15 Sep) | Build |
| A7 | Light and dark mode in the apps (the site has it; the keyboard already follows the host) | Build |
| A8 | Android round 2: in-keyboard AI prompt bar and clipboard history parity, automated tests | Build |
| A9 | Emoji suggestions from AOSP's emoji list (downloaded, not wired) | Build |
| A10 | M8 crypto (Privy wallet, Jupiter swaps, platform fee) as a separate release; Privy dashboard setup | Arpit + Build, later |
| A11 | Paper design port: the keyboard page and website page were unfinished when the Paper free plan's weekly MCP limit hit. Resume after the reset or on Paper Pro | Arpit (plan) + Build |
| A12 | Mobbin connector: authorize it if design references from Mobbin are wanted | Arpit |

## 4. Code problems found while writing the docs (not fixed yet)

Found by reading the code on 16 Sep. Nothing was changed, because that task was documentation only. Full lists: [BACKEND.md](BACKEND.md) section 16 (28 items) and [APPS.md](APPS.md) section 11 (21 items). The most important:

| # | Problem | Where | Owner |
|---|---|---|---|
| C1 | The CI secrets check scans zero files (a quoted file-type pattern matches nothing), so it always passes | `ci/check_no_secrets.sh` | Build |
| C2 | The AI run cache isn't per user and includes tool results, so a shared skill could show one person's calendar or Notion results to another within 24h | `server/src/routes/glyf.ts` | Build |
| C3 | `url.unfurl` fetches any address, including internal ones, once the server is public | `server/src/lib/tools.ts` | Build |
| C4 | No real accounts: the device ID works as a login for editing skills and connectors | server routes | Build (with the planned sign-up) |
| C5 | The paywall grants Plus or Max without payment, and the server trusts whatever plan the phone sends | app paywall + server meter | Build (with A2) |
| C6 | Test launch arguments, including one that writes the decrypted vault to disk, are not removed from release builds | iOS app | Build |
| C7 | Onboarding calls the Google permissions "Read-only", but the Calendar and Gmail scopes can write | Flutter onboarding | Build |
| C8 | The Android vault refuses 6 field types the app offers (name, GST, wallet, social, bio, reply) | Android vault store | Build |
| C9 | Android keyboard gaps versus iOS: no delete repeat, multi-touch, accents or caps lock; holding Translate, Vault or Calendar keys only opens the app | Android IME | Build |
| C10 | Web search tries Serper before Brave (the opposite of the 14 Sep decision), and "Connect your account first" errors reach users as "Tap to retry" | server search and run routes | Build |
| C11 | TestFlight builds 2 and 3 were likely built before the release server address existed, and the server isn't deployed, so testers probably have no AI | apps + B1 | Build + Arpit |

## 5. Repo and housekeeping

| # | Item | Owner |
|---|---|---|
| R1 | The gate recordings `docs/evidence/*.mp4` exist only on the dev Mac (too big for GitHub). Back them up somewhere (Git LFS, Drive) if they matter | Arpit |
| R2 | The stray Xcode template project in `/glyf` (its own git repo, unrelated to the app) can be deleted if not needed | Arpit |
| R3 | Re-run `python3 tools/make_og_image.py` whenever the hero copy or styles change | Build |

## 6. Open as of 22 Sep 2026

| # | Item | Owner |
|---|---|---|
| N1 | **Set Paste from Other Apps to Allow** (Settings → Glyf) on the test phone. Until then iOS asks once per copy, which is the only thing between the clipboard and filling itself. No app can write this setting | Arpit |
| N2 | **Turn on Recent screenshots** once (Glyf app → Keyboard). That tap is the only moment Glyf can ask for the photo library | Arpit |
| N3 | Confirm on a real device whether tapping "Allow Paste" on iOS's own banner also flips the per-app setting, or only allows that one read. The simulator cannot settle it | Arpit |
| N4 | Bump the build past 7 before the next TestFlight upload. Everything since build 7 (the whole toolbar and clipboard run) is unreleased | Build |
| N5 | About fifteen local commits are unpushed. Arpit pushes | Arpit |
| N6 | Android parity for this week's iOS work: the vault's images, the clipboard's categories and screenshots, and the toolbar's apps grid are iOS-only. Android has not been run since | Build |
| N7 | `Surfaces/ClipContextStrip.swift` is dead code (never instantiated) and its comment claims `UIPasteControl` is inert, which is wrong. Delete it | Build |
| N8 | The site has a pre-existing hydration mismatch in `BackdropKeys` (NaN transforms on first paint). It renders correctly after hydration but logs two console errors | Build |
| N9 | App strings still contain em dashes; only the site was cleaned (D88 era) | Build |

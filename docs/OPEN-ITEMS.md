# Open items

Everything pending, blocked or owed, in one place. **Owner** is who has to act: Arpit (accounts, keys, money, logins, design calls) or Build (code work). Area docs have more detail: [WEBSITE.md](WEBSITE.md), [APPS.md](APPS.md), [BACKEND.md](BACKEND.md).

Last updated: Wed 16 Sep 2026 (IST).

---

## 1. Launch the website

| # | Item | Owner |
|---|---|---|
| W1 | Rotate the Neon database password (it was pasted in chat twice). Update it in Vercel and `site/.env.local` | Arpit |
| W2 | ~~Deploy on Vercel with domains~~ **Done 16 Sep:** live on www.tryglyf.com, apex redirects to www | Arpit |
| W3 | Redeploy once so the canonical link and share-image URLs use `https://www.tryglyf.com` (code default changed after the first deploy). A push to `main` redeploys automatically if the Vercel project is connected to the GitHub repo. If `SITE_URL` was set in Vercel to the apex, change it to the www address or remove it | Arpit |
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
| B8 | `GIPHY_API_KEY` for the GIF panel (the GIF tab isn't built until then) | Arpit, then Build |
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

## 4. Repo and housekeeping

| # | Item | Owner |
|---|---|---|
| R1 | The gate recordings `docs/evidence/*.mp4` exist only on the dev Mac (too big for GitHub). Back them up somewhere (Git LFS, Drive) if they matter | Arpit |
| R2 | The stray Xcode template project in `/glyf` (its own git repo, unrelated to the app) can be deleted if not needed | Arpit |
| R3 | Re-run `python3 tools/make_og_image.py` whenever the hero copy or styles change | Build |

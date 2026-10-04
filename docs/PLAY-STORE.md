# Glyf on Google Play

Everything the Play Console asks for, as of 2026-10-03: the listing, the graphics, the App content answers, how to build and sign a release, and what still has to happen before the first upload. Counts are characters as Play counts them.

## Before the first upload

Done in the code:

- **"What Glyf sends"** (Play's User Data policy, prominent disclosure): an onboarding step before Turn on Glyf, and a one-time sheet for anyone set up earlier (`app/lib/core/ai_consent.dart`). Agree and turn on: AI suggestions as you type plus saved details with AI requests. Not now: both off. The keyboards send neither until it is answered.
- **Report** (Play's AI-Generated Content policy): a flag beside ↻ on any result the AI wrote, on both keyboards, to `POST /report` (`glyf_reports` in Postgres).
- **Account deletion page**: https://www.tryglyf.com/delete-account (`site/app/delete-account/page.tsx`), with the privacy policy's "Deleting your account and data" section at `/privacy#delete`.
- **Privacy policy** matches the code (consent, details with every AI request once agreed, two days of screenshots, mail.tm, price lookups, the Solana relay, KLIPY's random ID, reports).
- **Release signing** from `android/key.properties` (below).
- Android asks nothing unasked from a field that wants no learning (an incognito tab).

Still to decide or do (Arpit):

1. ~~**Package name**~~ **Done 2026-10-04:** `com.arpit.glyf` everywhere (debug and release, and the Kotlin package), the iPhone app's ID too. The first bundle (1.0.0, build 13) went to internal testing with it.
2. **Delete account inside the app.** Play requires an in-app path for any app where accounts are created (the web page alone isn't enough). It was removed on 2026-09-29; `Auth.deleteAccount` and `DELETE /me` still exist, so a quiet row (or a link to the web page) brings it back.
3. **Recent screenshots on Android** use `READ_MEDIA_IMAGES`. Play's Photo and Video Permissions policy allows it only when broad photo access is core to the app, and needs a declaration form. Dropping the permission and the Android switch is the safe choice.
4. **Wallet on Play.** The Financial features form must be answered either way. Phantom signs and Glyf holds no keys (non-custodial), but buying tokenized stocks (xStocks) is a regulated-looking feature its issuer doesn't offer in the US, UK, Canada or Australia. Ship the wallet without stock buys on Android, or leave the wallet out of the Play build.
5. **Developer account.** A personal account needs a closed test with at least 12 testers for 14 days before production; an organization account needs a D-U-N-S number but skips that.
6. **Upload key**: create it (below) and register both SHA-1s (upload key and Play App Signing) on the Android OAuth client in Google Cloud, or Sign in with Google fails in the Play build.
7. **Deploy before the new builds go out**: push the server (`POST /report`, miles) and the site (privacy policy, `/delete-account`). Push to main deploys both.
8. **KLIPY_APP_KEY on Railway**, or cut "GIFs and stickers (search KLIPY)" from the description.

## Store listing

| Field | Value |
|---|---|
| App name (30) | **Glyf: AI Keyboard** (17). The launcher label stays "Glyf". "Glyf : Draw to Launch" already uses the bare name on Play |
| Short description (80) | **The AI keyboard that does the rest. Rewrite, translate and answer as you type.** (78) |
| Category | Productivity (Play lists keyboards there; Grammarly is there too) |
| Tags (up to 5) | Keyboard, Personal assistant, Emoji, Calendar, plus an AI or translator tag if offered |
| Contact email | arpit@tryglyf.com |
| Website | https://www.tryglyf.com |
| Privacy policy | https://www.tryglyf.com/privacy |
| Delete-account URL | https://www.tryglyf.com/delete-account |
| Price | Free. No Play Billing in this build (Android's paywall says "Plans open soon"), so no "In-app purchases" label |

Full description (3,669 of 4,000):

```text
Glyf is an Android keyboard with AI on the space bar. Type the way you always do. When you want more, hold space and Glyf works on what you wrote, right where you are typing.

HOLD SPACE, AND GLYF DOES THE REST
• Rewrite a message five ways: fixed up, professional, polite, shorter or with emoji. Pick one and it replaces your text.
• Ask a question and the answer goes into your message.
• Translate what you typed.
• Find a place with a map, or a video, and paste it in one tap.
• On an empty field, hold space to ask Glyf anything.
• Put an action on a letter key and hold the letter to run it. Describe a new action in plain words and Glyf builds it.

ANSWERS IN THE STRIP, WORKED OUT ON YOUR PHONE
As you type, the strip above the keys offers what you need. No AI is involved, so it is instant:
• Bills and tips: "$90 between 4 people" gives $22.50 each
• Units: "10 inches" is 25.4 cm, "72°F" is 22.2°C
• Money at today's rate: "50 euros in dollars"
• Time zones: "8:30pm in Tokyo" in your own time
• Dates: "days until Christmas", "10 working days from today"
• Pay and tax: "$45/hr" is $93,600 a year, "£120 inc VAT" is £100 + £20 VAT
• Cooking: "2 cups flour" is 240 g, "bake at 350" is 180°C
• Running pace, fuel economy and download times
• Links without their trackers, tracking numbers that open the carrier's page, faces like /shrug, a coin flip or a dice roll

A KEYBOARD FIRST
• Autocorrect and next-word suggestions run on your phone and learn the words you use.
• Glide along the space bar to move the cursor.
• Clipboard with your last 20 copies, and pins for the ones you keep. Anything that looks like a password or key is left out.
• Every emoji, found by what you mean, plus GIFs and stickers (search KLIPY), animated emoji and emoticons.
• Style your text: bold, italic, strikethrough, script, bubble letters and more, or UPPERCASE and Title Case, with a word count.
• Two looks, Glyf and Glass, in light or dark.

YOUR DETAILS, ONE TAP AWAY
Save your email, phone number, address and links in the Vault, encrypted on your phone. When a form field or a sentence asks for one ("my email is"), it waits in the strip. Shorthand turns ;sig into your signature, with blanks for the date or time.

MORE INSIDE THE KEYBOARD
• Search YouTube, places nearby and your contacts, and paste a result.
• Calendar: see your day, add an event, invite people through Google Calendar, make a Google Meet link or book a time on a Cal.com page.
• Temp mail: a throwaway address from mail.tm, with verification codes in the strip.
• Games: Snake and Chomp, for when you are waiting.

PRIVACY
• Typing, the words Glyf learns, notes, clipboard history and contacts stay on your phone. The Vault is encrypted on your phone.
• Text goes to Glyf's server only for features that need it: AI actions you start, searches and translations, and, if you agree when you set up, the sentence you are typing when you pause, so the strip can suggest an action.
• If you agree, AI requests also carry your saved details, such as your email or address, so answers can fill them in. Both can be turned off in the app.
• Nothing is sent from password fields. Card numbers, one-time codes, passwords and keys are masked before text reaches an AI model, and AI providers don't keep or train on it.
• Report any AI result with the flag beside it.
• Approximate location is used for nearby search only if you turn it on.
• No ads, and your data is never sold.

GETTING STARTED
Open Glyf, sign in with Google and follow the steps to turn the keyboard on. Android shows its usual notice for any new keyboard. Glyf is free, with a daily allowance of AI actions. The keyboard types in English.
```

If the wallet ships on Android, this goes before PRIVACY (220 characters; never mention stock buys):

```text
WALLET (OPTIONAL)
Connect Phantom to send SOL or USDC, or buy a token, from the chat. A copied wallet address offers Send, and a cashtag like $SOL shows its price. Phantom signs every payment; Glyf never holds your keys.
```

## Graphics

All in `marketing/play/`, made by `python3 marketing/play/src/frame.py` (headless Chrome) from `src/captures/` and `src/feature.html`:

| Asset | File | Spec |
|---|---|---|
| App icon | `icon-512.png` | 512 x 512, 32-bit PNG, from the iOS 1024 icon; Play rounds the corners |
| Feature graphic | `feature-graphic.png` | 1024 x 500, 24-bit PNG: "Type less. glyf more." over the keyboard with its "$22.50 each" chip |
| Phone screenshots | `phone/01-rewrite.png` … `06-style.png` | 1080 x 1920 (9:16), 24-bit PNG, caption above the real screen |

The captures are Google Messages on the emulator at 1080 x 1920 (`adb shell wm size 1080x1920`, `wm density 420`, SystemUI demo mode, New York time, US examples, demo contacts "Mom" and "Sofía" with 555 numbers, a demo vault: Alex Morgan, alex@example.com, 123 Market St, San Francisco). Screenshot text must not say "best", "#1", "top", "new", prices or "download now". Tablet screenshots are optional and need the app checked on a tablet first.

## App content

| Section | Answer |
|---|---|
| Privacy policy | https://www.tryglyf.com/privacy |
| Ads | No ads |
| App access | Sign-in required. On the sign-in screen tap "App Review sign-in" (shown while the server's `REVIEW_MODE=true`): review@tryglyf.com with the password in `REVIEW_PASSWORD`. Keep `REVIEW_MODE` on while a review can happen. To turn the keyboard on: Settings › System › Keyboard › On-screen keyboard › Manage keyboards › Glyf Keyboard |
| Content rating | IARC questionnaire, "All other app types"; say yes to web search, GIF search and AI answers |
| Target audience | 18 and over (simplest with crypto and open AI answers); never an under-13 group |
| News, Government, Health | No, no, none |
| Financial features | "Cryptocurrency wallet" if the wallet ships (non-custodial); otherwise "My app doesn't provide any financial features" |
| Advertising ID | No (no AD_ID permission) |
| Photo and video permissions | Only if `READ_MEDIA_IMAGES` stays (see decision 3) |

### Data safety

Collected = sent off the phone; shared = handed to a third party for its own use (service providers working for Glyf, and transfers the person starts, aren't sharing). Encrypted in transit: yes. Account creation: yes (Sign in with Google). Deletion: in the app once decision 2 lands, and by email at /delete-account. Ephemeral: no.

| Data type | Collected | Shared | Optional? | Purposes | What |
|---|---|---|---|---|---|
| Location: approximate | Yes | No | Optional (Nearby search) | App functionality | A coarse fix (about 1 km) with searches and hold-space requests |
| Personal info: name, email, user IDs | Yes | No | Required | Account management, App functionality; IDs also Fraud prevention | The Google account; daily limits per account |
| Personal info: address, phone, other info | Yes | No | Optional ("What Glyf sends", "Let AI use your saved details") | App functionality | Saved details with each AI request once agreed |
| Financial info: user payment info | Yes | No | Optional (same switch) | App functionality | A saved payment ID with AI requests; card numbers are masked first |
| Financial info: other | Yes, if the wallet ships | No | Optional | App functionality | Wallet address, balances, signed transactions relayed to Solana |
| Calendar events | Yes | No | Optional (Calendar, Google Meet) | App functionality | Events to Google Calendar, Meet, Cal.com bookings |
| App activity: app interactions | Yes | No | Required | Analytics | Event names and counts, never text |
| App activity: in-app search history | Yes | No | Optional | App functionality | Search, YouTube, Maps and GIF searches |
| App activity: other user-generated content | Yes | No | Optional | App functionality; reports also Fraud prevention, security, and compliance | Text you run AI on; with AI suggestions on, the sentence on a pause (last 120 characters); AI results you report |
| Device or other IDs | Yes | No | Required | App functionality, Analytics, Fraud prevention | A random install ID; a separate random ID for KLIPY |
| Messages, photos, audio, files, contacts, health, web browsing, crash logs | No | | | | Kept on the phone or not touched |

Judgment calls: KLIPY gets GIF searches and its own random ID straight from the phone under a "Search KLIPY" field (treated as a transfer the person starts; marking them shared costs little). Gift codes aren't purchases. When Play Billing ships, add Purchase history.

## Building a release

Create the upload key once (Arpit; keep the file and passwords out of the repo, in a password manager):

```bash
keytool -genkeypair -v -keystore ~/glyf-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Then `app/android/key.properties` (gitignored, like every `*.jks`):

```properties
storeFile=/Users/arpitsingh/glyf-upload.jks
storePassword=…
keyAlias=upload
keyPassword=…
```

`app/android/app/build.gradle.kts` signs release builds with it, or with the debug key when the file is missing (which Play refuses). Build the bundle:

```bash
cd app && flutter build appbundle --release
```

The bundle is `app/build/app/outputs/bundle/release/app-release.aab`; its version code is the `+N` in `pubspec.yaml`, and each upload needs a higher one. Turn on Play App Signing, then add the SHA-1 Play shows for the app signing key, and the upload key's (`keytool -list -v -keystore ~/glyf-upload.jks -alias upload`), to the Android OAuth client in Google Cloud. Target API 36 is already met.

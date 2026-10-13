# Security audit

Date: 14 Oct 2026

## Scope

- **Server** (`server/`, Fastify on Railway at api.tryglyf.com, Neon Postgres). Covered:
  - sign-in and sessions, the route lock (`lib/protect.ts`), plan caps (`lib/guard.ts`, `lib/limits.ts`)
  - every route's input checks, and whether one user can read or change another's data
  - billing and gift codes, the OAuth broker
  - every place the server fetches a URL, `/wallet/rpc`, the `/p/:id` page
  - rate limits, CORS, logs, error messages, `npm audit`
- **iOS** (`app/ios/GlyfKeyboard`, `app/ios/Runner`). Covered:
  - vault encryption and keychain use, what the keyboard logs, what sits in the App Group in plain text
  - clipboard history, opening links that come from the AI, ATS settings
  - test hooks in Release builds, the backend URL
- **Android** (`app/android/app/src/main`). Covered:
  - the manifest, the debug broadcast receiver, cleartext and backup settings
  - the Keystore vault, logs, plain files, password fields
- **Flutter app** (`app/lib`): token storage, deep links, web views.
- **Repo**: committed secrets, and `ci/check_no_secrets.sh`.

How it was done:
- The code was read. No secret values were opened or printed.
- `server/.env` was not opened.
- Nothing ran against production.

Tests after the fixes:

| Check | Result |
|---|---|
| `server`: `npx tsc --noEmit` | clean |
| `server`: `npm test` (with `DATABASE_URL` empty) | 345 tests pass, including the new `test/safefetch.test.ts` |
| `app/android`: `./gradlew :app:testDebugUnitTest` | 121 tests pass |
| `app`: `flutter analyze lib` | no issues |
| `ci/check_no_secrets.sh` | no secrets in 719 files |

iOS tests were not run because the simulators were in use. Every changed Swift file passes `swiftc -parse`.

## Findings

Severity: **High** is reachable now and exposes data or money. **Medium** needs a precondition or is a serious gap. **Low** is defence in depth. **Info** is noted only.

### Server

| # | Severity | What | Where | Status |
|---|---|---|---|---|
| S1 | High | `url.unfurl` fetched any URL a signed-in user gave it, on `/tools/run` and in glyf steps. That included loopback, private ranges, cloud metadata (169.254.169.254) and Railway's private network, with redirects followed. | `server/src/lib/tools.ts` | Fixed. New `server/src/lib/safefetch.ts` allows only http/https, web ports and no credentials in the URL. It checks the resolved address at connect time, which also stops DNS rebinding. It refuses loopback, private, link-local, CGNAT, multicast, reserved and IPv6 local or embedded-IPv4 addresses. It follows at most 4 redirects by hand, checking each one, and caps the body size. Tests are in `server/test/safefetch.test.ts`. |
| S2 | High | A community (hub) glyf could build a `url.unfurl` address from the installer's calendar, profile, earlier steps or input, and send it to a site its author runs. That leaks data to the author. | `server/src/lib/userglyfs.ts` (`validateUserDef`) | Fixed. A user glyf's link preview may only open `{{input}}`. The rule is checked on save and on publish. No shipped glyf uses `url.unfurl`. |
| S3 | High | `npm test` on a laptop loads `server/.env`. The user, code and report stores then default to its `DATABASE_URL`, which is production, so test runs could write test accounts to the live database. | `server/src/env.ts` | Fixed. Under vitest, the `.env` file's `DATABASE_URL` is skipped. A value set in the real environment is left alone. Verified: a vitest process no longer sees it. |
| S4 | Medium | StoreKit "Xcode" transactions skip Apple's certificate chain. Anyone can sign one, and they were accepted whenever `NODE_ENV` was not `production`, so one missing Railway variable would hand out free Max plans. | `server/src/routes/billing.ts` | Fixed. They are refused on Railway whatever `NODE_ENV` says. |
| S5 | Medium | `deviceId` (a random UUID made by each phone) works as a password for that phone's saved glyfs, hub installs, creator stats, OAuth connections (Google tokens used by tools) and disconnect. Any signed-in account that knows another phone's `deviceId` can act as that phone. It is not tied to the account, and it is written to Railway logs on `/glyf/run`, `/act` and `/vocab`. | `routes/hub.ts`, `routes/builder.ts`, `routes/glyf.ts`, `routes/connector.ts` | Needs Arpit. Key these records by account (`req.glyfUser`), with a one-time move of existing rows, and stop logging the raw id. This changes stored data, so it was not done here. |
| S6 | Medium | `/oauth/*/start` was open to anyone without a session. Anyone could also create pending sign-ins in the shared store. | `server/src/lib/protect.ts` | Fixed. Only `/oauth/<provider>/callback` is open now; the app already sends its session on start. **Still open:** the OAuth `state` is not tied to the browser that started it. A phished consent could therefore attach a victim's Google to an attacker's phone. This goes with S5. |
| S7 | Medium | OAuth access and refresh tokens are stored unencrypted in Postgres (the `connections` collection). | `routes/connector.ts`, `lib/store.ts` | Needs Arpit. Encrypt them with a key held in a Railway variable (new variable). |
| S8 | Medium | Sessions last 180 days and can't be revoked. Sign-out and deleting the account leave the token working. Deleting the account doesn't remove device-keyed data (connections, glyfs, installs, telemetry) or the `glyf_purchases` rows. | `lib/identity.ts`, `routes/me.ts`, `lib/users.ts` | Needs Arpit. Add a per-user token version (or deny-list) checked in `verifySession`, and delete device-keyed data on account deletion (after S5). |
| S9 | Low | `/connectors/status` is an open path. Given a `deviceId`, it showed which providers were connected and the connected email address, with no session. | `server/src/routes/connector.ts` | Fixed. Connection details are only returned with a valid session. |
| S10 | Low | The OAuth callback put the provider name from the URL path into the `glyf://connected?provider=…` redirect without encoding it. | `server/src/routes/connector.ts` | Fixed (encoded). |
| S11 | Low | Unhandled 5xx errors sent Fastify's default body, which includes the raw error message (for example, database errors). | `server/src/index.ts` | Fixed. A custom error handler logs the message and returns only "Internal Server Error". 4xx answers are unchanged. |
| S12 | Low | `/p/:id` shared pages: all fields are escaped and links are limited to http(s), so no XSS was found. The pages had no CSP. | `server/src/routes/act.ts`, `lib/pages.ts` | Fixed (hardening): `Content-Security-Policy` with no scripts, framing or forms, plus `nosniff` and `no-referrer`. |
| S13 | Low | Logs of a bad `/act` or `/search` request included Zod issues, which can echo a typed value (for example, an enum's `received`). | `routes/act.ts`, `routes/search.ts` | Fixed. Only the path and code of each issue are logged. |
| S14 | Low | `/report`'s 10-an-hour limit was counted per `deviceId`, which costs nothing to change. | `server/src/routes/report.ts` | Fixed. It is counted per account when signed in. |
| S15 | Low | The per-IP limits use the first `X-Forwarded-For` entry. If Railway's edge passes a client's own header through, the per-IP limit can be dodged. Railway's forum answers disagree on whether it does. | `server/src/lib/protect.ts` | Needs Arpit. Send one request with a made-up `X-Forwarded-For` to production and check the logged address. If it shows through, switch to `X-Real-IP` or the last entry. |
| S16 | Low | Signed-in callers can grow the `telemetry`, `devices`, `installs` and `skill-installs` collections without limit (new event names, new `deviceId`s). Postgres KV keeps every row in memory. | `routes/telemetry.ts`, `lib/skills.ts`, `lib/userglyfs.ts` | Needs Arpit (cap rows per day or per account). |
| S17 | Low | Wrong reviewer passwords are counted per `req.ip`, which is Railway's proxy, so in practice there is one limit of 10 an hour for everyone. Anyone can lock App Review out for an hour. | `server/src/routes/auth.ts` | Accepted risk. It is the safer failure for brute force, and `REVIEW_MODE` is only on during a review. |
| S18 | Low | `npm audit`: fastify below 5.12.5 (HTTP/2 trailer DoS; HTTP/2 isn't used) and fast-uri (moderate), both runtime. The test toolchain (vitest 2, vite, tinypool, esbuild) has critical and high advisories. | `server/package-lock.json` | Runtime fixed with `npm audit fix` (fastify 5.12.7, fast-uri patched; lockfile only). Dev-only: needs Arpit, because vitest 2 to 5 is a major upgrade. |
| S19 | Low | The `fx.convert` tool put currency codes into the upstream query without encoding. | `server/src/lib/tools.ts` | Fixed. |
| S20 | Info | Sandbox (TestFlight) purchases are signed by Apple and grant real plans on production. | `routes/billing.ts` | Accepted. App Review purchases are sandbox. Revisit if a public TestFlight link is opened. |
| S21 | Info | `/scheduling/book` lets a signed-in user have Cal.com email an invite to any address, the same as Cal.com's own page. | `routes/scheduling.ts` | Accepted. |
| S22 | Info | `/health` is public and lists which providers are configured and `NODE_ENV` (true/false values only, no keys). | `routes/health.ts` | Accepted. |
| — | Checked, fine | Areas reviewed with no issue found:<br>• Sign-in: Apple and Google ID tokens checked for issuer, audience, expiry, nonce and RS256 signature; HS256 sessions with a constant-time compare.<br>• Gift codes: the claim is one atomic UPDATE; misses are capped per account.<br>• Apple transactions: chain pinned to Apple Root G3; a transaction stays with the account that first sent it.<br>• `/wallet/rpc`: 6-method allowlist; the RPC key never leaves the server.<br>• `/search/photo` only proxies Places resource names; the static map takes only numbers.<br>• Cal.com calls go only to the fixed API host.<br>• No CORS headers are sent.<br>• The plan comes from the database, not the client.<br>• Body limit is 512 KB. | | |

### Repo

| # | Severity | What | Where | Status |
|---|---|---|---|---|
| R1 | Medium | The secrets check scanned zero files. Three causes: `--include='*.{swift,…}'` is a brace pattern grep does not expand; the private-key pattern starting with `-----` was read as an option; and Android, the site and tools weren't scanned. | `ci/check_no_secrets.sh` | Fixed. It now scans every committable file (tracked plus new and not ignored), with more key shapes (Google OAuth secrets, GitHub, Stripe live, database URLs with passwords). Hits print as file:line only. Secret-scanner test fixtures are skipped. Result: no secrets in 719 files. |
| R2 | Info | No key files are tracked: `.p8`, keystores, `key.properties` and `.env` are all ignored. The App Store Connect script reads its `.p8` from outside the repo. | `.gitignore`, `tools/appstore/asc.mjs` | Fine. |

### iOS

| # | Severity | What | Where | Status |
|---|---|---|---|---|
| I1 | Medium | Search-card links from `/act` and `/suggest` were opened with any scheme: `tel:`, `sms:`, other apps' schemes, `glyf://` actions. | `app/ios/GlyfKeyboard/Surfaces/ActSurface.swift` | Fixed (https only). |
| I2 | Medium | Clipboard history kept copies a password manager marks as concealed, for 48 h or forever if pinned. | `app/ios/GlyfKeyboard/Engine/ClipboardStore.swift` | Fixed. Copies carrying `org.nspasteboard.ConcealedType`, `TransientType` or 1Password's type are skipped; reading the types never asks iOS. **Still open:** an ordinary password typed into a notes app and copied still passes `SecretScanner`. |
| I3 | Medium | With AI suggestions on, text from fields declared as card number, one-time code or password (not secure-entry) could go to `/suggest`. `typingPolicy` also re-read the content type, which iOS can return as nil later, so learning could switch back on in those fields. | `app/ios/GlyfKeyboard/GlyfKeyboardViewController.swift` | Fixed. `/suggest` skips those field types and any text `SecretScanner` flags. `typingPolicy` uses the content type kept for the field. |
| I4 | Low | A Release build kept any saved `backendURL` that wasn't localhost, and sent the session token there (keyboard and Flutter app). | `Engine/SettingsStore.swift`, `app/lib/core/glyf_api.dart`, `app/lib/core/auth.dart` | Fixed. Release builds always use `https://api.tryglyf.com`. |
| I5 | Low | `--glyf-dump-vault` wrote the decrypted vault into the App Group in Release builds; it needs a launch argument. | `app/ios/Runner/AppDelegate.swift` | Fixed. It is debug-only, and Release deletes any leftover file. |
| I6 | Low | Release builds honour the other test launch arguments (skip onboarding and consent, seed the vault, reset state). They are only reachable through Xcode or devicectl. | `app/ios/Runner/AppDelegate.swift` | Needs Arpit. Wrap them in `#if DEBUG` once the QA harness is confirmed to run Debug builds. |
| I7 | Low | The `tempMailBase` setting worked in Release builds, which would send the mail.tm login elsewhere. | `app/ios/GlyfKeyboard/Engine/MailTM.swift` | Fixed (debug-only). |
| I8 | Low | Phantom session secrets are kept in the shared keychain group, so the keyboard extension can read them. | `app/ios/Runner/WalletSecrets.swift` | Needs Arpit (move to the app's own group, with a migration). |
| I9 | Low | The vault key is `AfterFirstUnlock`, not `…ThisDeviceOnly`, so it travels in encrypted backups together with `vault.enc`. | `Engine/VaultStore.swift` | Needs Arpit. This is a product choice: the vault survives a restore today. |
| I10 | Low | `clipboard.json`, `contacts.json` and `tempmail.json` in the App Group are plain JSON and included in backups. | App Group `bridge/` | Needs Arpit. Set `isExcludedFromBackup` after each write. |
| I11 | Info | The performance log would record key ids publicly if switched on; `Perf.on` is a constant `false`. | `GlyfKeyboardViewController.swift` | Accepted. |
| — | Checked, fine | Areas reviewed with no issue found:<br>• Session token is in the keychain (ThisDeviceOnly).<br>• Vault is AES-GCM with its key in the keychain, and refuses passwords, cards, seeds and IDs.<br>• No typed text, clipboard, vault or token in logs.<br>• No ATS exceptions.<br>• Every AI, clipboard and translate path is skipped in secure-entry fields.<br>• The Runner's `openURL` is https only.<br>• Keyboard debug hooks are `#if DEBUG`. | | |

### Android

| # | Severity | What | Where | Status |
|---|---|---|---|---|
| A1 | High | Clipboard history kept copies marked `IS_SENSITIVE` (password managers) in plain text, showed them on the paste chip, and used them as AI input when the field was empty. | `app/android/.../store/ClipboardStore.kt` | Fixed. Sensitive copies are never captured, shown or sent. Only the paste key may still paste one. |
| A2 | Medium | In password fields, Rewrite, Translate, My glyfs and Tones still sent the field's text to the server. Only space-hold and the chips were blocked. | `app/android/.../ime/GlyfIME.kt` (`startAct`, `startSkill`, `runTranslateOnField`, `translateDraftChanged`) | Fixed. All four return early in a password field. |
| A3 | Medium | Auto Backup was on with no rules. Clipboard history, the temp-mail login and the Google Calendar copy went to Google Drive and to device transfer. | `AndroidManifest.xml` | Fixed. New `res/xml/backup_rules.xml` and `data_extraction_rules.xml` exclude those three. Notes, contacts and settings still back up so a restore keeps them: **needs Arpit** to decide if that should change. Vault, session and wallet keys were already safe (Keystore, `noBackupFilesDir`). |
| A4 | Low | In debug builds, the `DEBUG_TOOL` receiver accepted broadcasts from any installed app. That covers clearing fields, editing the vault and pointing Google calls at another host. It is not registered in release builds. | `GlyfIME.kt` | Fixed. Senders must hold `DUMP`; adb has it, apps don't. |
| A5 | Low | In incognito (no-learning) fields, tapping the literal word, undo, and backspace-after-correction still taught the typing engine. | `GlyfIME.kt` | Fixed (checks the learning policy). |
| A6 | Low | A release build kept any saved `backendURL` that wasn't localhost (session token sent there), and honoured `tempMailBase`. | `store/Stores.kt`, `GlyfIME.kt` | Fixed. Release builds use production only, and the stand-in mail server is debug-only. |
| A7 | Low | The temp-mail login is in plain SharedPreferences. | `ime/TempMail.kt` | Partly fixed (kept out of backup by A3). Needs Arpit to decide on Keystore sealing. |
| A8 | Low | Release builds keep `Log` calls. `GET /search/suggest` puts `deviceId`, latitude and longitude in the URL, which a failure log prints. | `ime/BackendClient.kt`, ProGuard rules | Needs Arpit. Strip `Log.d/i/v` in release, and move those values out of the query string. |
| A9 | Low | The `glyf://` scheme can be claimed by another app; there are no verified App Links. | `AndroidManifest.xml` | Accepted. Phantom's replies are encrypted to a key only Glyf holds. |
| — | Checked, fine | Areas reviewed with no issue found:<br>• Only `MainActivity` and the IME (behind `BIND_INPUT_METHOD`) are exported.<br>• Cleartext is allowed only to emulator and localhost addresses.<br>• Vault, session and wallet use AES-GCM with AndroidKeyStore keys and random IVs.<br>• No learning, suggestions or AI in password, email or URL fields, or with no-suggestions set.<br>• No `Intent.parseUri`, no WebViews.<br>• Launch-arg test hooks are `BuildConfig.DEBUG` only. | | |

### Flutter app

| # | Severity | What | Where | Status |
|---|---|---|---|---|
| F1 | High | Any web page or app can open `glyf://open?path=pay?kind=send&to=…&amount=…`. Glyf builds the transaction and opens Phantom (or Mobile Wallet Adapter) to sign straight away, with no step inside Glyf. The token's mint, symbol and decimals come from the link and are marked verified, so Glyf's own screen can show a fake token. The wallet's confirmation screen is the only safeguard left. | `app/lib/main.dart`, `app/lib/wallet/pay_launch_screen.dart` | Needs Arpit, because it changes the Send/Buy flow. Recommended fix: the keyboard writes a one-time nonce to the shared container and puts it in the link; the app refuses pay links without a matching nonce, or shows a "Review and pay" button for them. Look up the token by mint, never from the link. |
| F2 | Info | `--glyf-test-prefill-card` isn't gated by `kReleaseMode`. It only pre-fills a test card into the vault form, which refuses it. | `app/lib/vault/vault_screen.dart` | Accepted. |
| — | Checked, fine | Areas reviewed with no issue found:<br>• The session token stays in native secure storage (keychain or Keystore), not SharedPreferences.<br>• No WebViews and no `url_launcher`; native `openURL` is https only.<br>• Phantom replies need the pending key.<br>• Dart sign-in test hooks are gated by `kReleaseMode`. | | |

## Needs Arpit

1. **F1:** pay deep links run without a step inside Glyf. Add a nonce or a review button, and resolve tokens by mint.
2. **S5, S6, S8:** tie `deviceId` data (glyfs, installs, OAuth connections) to the account, move existing rows once, and stop logging the raw id.
   - Add revocable sessions.
   - Delete device-keyed data when an account is deleted.
3. **S7:** encrypt OAuth tokens at rest. This needs a new Railway variable holding the key.
4. **S15:** check whether Railway passes through a client-supplied `X-Forwarded-For`. Send one test request and read the log.
5. **S16:** cap the telemetry, device and install collections.
6. **S18:** upgrade vitest to 5 (dev-only advisories).
7. **I6:** put the Release launch-argument hooks under `#if DEBUG` after confirming the QA harness builds Debug.
8. **I8, I9, I10:** decide on the following (each is a product choice or needs a migration):
   - the wallet secrets' keychain group;
   - the vault key's backup class;
   - backup exclusion for the App Group's clipboard, contacts and temp-mail files.
9. **A3, A7, A8:** decide on the following:
   - whether notes, contacts and settings should leave Android backups;
   - Keystore-sealing the temp-mail login;
   - stripping `Log` calls in release;
   - moving `deviceId` and location out of the `/search/suggest` URL.
10. **Deploy:** none of the server fixes are live until main is pushed. The `npm audit fix` lockfile change ships with them.

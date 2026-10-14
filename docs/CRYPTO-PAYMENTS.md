# Paying for Plus and Max in USDC

Arpit, 2026-10-14: "enable to receive crypto payments from phantom for pro plan".

Plus ($2 a month, $20 a year) and Max ($5 a month, $50 a year) can be paid in USDC on Solana. The payment is a Solana Pay transfer to Glyf's treasury wallet, and the server checks it on Solana before the plan starts. Only the Solana dApp Store build offers it. The App Store and Google Play builds never show it.

## 1. What the stores allow (checked 14 Oct 2026)

| Channel | Pay in crypto inside the app? | Mention it or link to it from the app? | Use a plan paid elsewhere? |
|---|---|---|---|
| Solana dApp Store build | **Yes** | Yes | Yes |
| tryglyf.com (web) | Yes: a web page isn't under any store's rules | n/a | n/a |
| iOS App Store, US storefront | No: 3.1.1 names crypto as a banned way to unlock | **Yes**: a button or link to a web page that takes crypto is allowed in US apps | Yes, under 3.1.3(b), as long as the same plans are also sold as in-app purchases (they are) |
| iOS App Store, other storefronts | No | No: no buttons, links or calls to action (except the region-specific StoreKit External Purchase entitlements) | Yes, under 3.1.3(b), but the app may not say where to buy |
| Google Play, US | Only through Google's Alternative Billing program (enrolment, Google's APIs, service fees reported from 1 Oct 2026) | Only through the External Content Links program (enrolment, fees, downloads reported by 1 Dec 2026) | Yes |
| Google Play, other countries | No: Play Billing is required for subscriptions | No: in-app steering to another payment method is banned | Yes |

### Apple

- **3.1.1**: "If you want to unlock features or functionality within your app, (by way of example: subscriptions…), you must use in-app purchase. Apps may not use their own mechanisms to unlock content or functionality, such as license keys, augmented reality markers, QR codes, cryptocurrencies and cryptocurrency wallets, etc." A crypto checkout inside the iOS app is out, on every storefront. ([App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/))
- **3.1.1(a) and 3.1.3, US storefront**: the guidelines now say the StoreKit External Purchase Link entitlements "are not required for developers to include buttons, external links, or other calls to action in their United States storefront apps", and the 3.1.3 ban on encouraging other purchase methods doesn't apply "on the United States storefront". Apple made this change on 30 April / 1 May 2025, after the Epic v. Apple contempt order. ([guidelines](https://developer.apple.com/app-store/review/guidelines/), [MacTrast, May 2025](https://www.mactrast.com/2025/05/apple-makes-updates-to-its-u-s-app-review-guidelines-in-wake-of-epic-games-ruling/amp/), [Pocket Gamer.biz](https://www.pocketgamer.biz/apple-updates-app-store-rules-to-allow-external-payment-after-court-ruling))
- **What is still open**: in December 2025 the Ninth Circuit upheld the contempt finding. It also found the outright ban on any commission for linked-out purchases too broad, and sent that question back to the district court. Apple then took it to the Supreme Court. So Apple may later be allowed a "reasonable" commission on US link-outs. The link itself stays allowed. ([Fenwick](https://www.fenwick.com/insights/publications/ninth-circuit-largely-upholds-ruling-in-epic-v-apple), [MacRumors, June 2026](https://macrumors.com/2026/06/11/apple-fights-back-against-epic/), [The Next Web](https://thenextweb.com/news/supreme-court-apple-epic-contempt-app-store-commission))
- **3.1.3(b) Multiplatform Services**: apps "may allow users to access content, subscriptions, or features they have acquired in your app on other platforms or your web site… provided those items are also available as in-app purchases within the app." A plan paid in USDC on the web or on the Seeker works on the iPhone once the person signs in with the same account. Plus and Max must stay on sale as App Store subscriptions.
- **3.1.5 (Cryptocurrencies)**: (i) wallets need an organisation developer account, and (iii) exchanges need licensing. Neither applies to taking a payment, which is 3.1.1's question.
- **Gift codes**: typing a code that unlocks a plan is close to 3.1.1's "license keys". That is why a USDC payment puts the plan straight on the signed-in account and never makes a code.

### Google Play

- The Payments policy: "Google Play's billing system is required for developers offering in-app purchases of digital goods", and "Within an app, developers may not lead users to a payment method other than Google Play's billing system." It says nothing specific about crypto, so crypto is just another non-Play payment method. ([Understanding Google Play's Payments policy](https://support.google.com/googleplay/android-developer/answer/10281818?hl=en), [Payments policy](https://support.google.com/googleplay/android-developer/answer/9858738?hl=en))
- **US**: after the Epic v. Google injunction (Supreme Court refused a stay in October 2025, compliance 29 October 2025), Google launched the Alternative Billing and External Content Links programs for US users on 9 December 2025. Enrolled developers must report transactions and pay service fees from 1 October 2026; for External Content Links, downloads and fees are due by 1 December 2026. Both need enrolment and Google's APIs. They are not free switches. ([Google: changes for US users](https://support.google.com/googleplay/android-developer/answer/15582165?hl=en), [Stash, on the October fees](https://www.stash.gg/blog/googles-october-1-external-link-fees-what-changes-and-what-developers-still-dont-know))
- Outside the app, developers "are free to communicate with users about alternative purchase options".

### Solana dApp Store

- "Solana Mobile Inc. does not currently collect any fees on in-app purchases, app purchases, or subscriptions, nor are any fees collected on its behalf by apps in the catalog." ([Solana Mobile FAQ](https://docs.solanamobile.com/get-started/faq.md))
- The Publisher Policy (last updated 21 July 2026) has no in-app payment rule. It only bars apps "designed to process transactions… that violate Applicable Law", and asks apps offering regulated financial services for their licences. Selling a subscription for USDC is neither. ([Publisher Policy](https://legal.solanamobile.com/publisher-policy-web))

### Paying on the web, using it in the app

- **Apple**: allowed under 3.1.3(b), because the plans are also IAP. Outside the US, the iOS app must not say that the web or USDC is an option. In the US it may.
- **Google Play**: a plan bought outside the app may be used in it. The app may not point to the web checkout unless enrolled in External Content Links (US).
- **dApp Store**: no restriction.

### So

- **Built**: USDC checkout in the **dApp Store build** (Android, `GLYF_CRYPTO_PAY=true`). A plan paid this way works on every Glyf app the person signs in to, iPhone included.
- **Allowed, not built**: a **tryglyf.com** checkout. The site has no Glyf sign-in yet, and the plan has to land on an account. The server routes are ready for it once the site can sign people in.
- **Allowed, not built (a choice for Arpit)**: an iOS **US-storefront-only** "Pay with USDC on the web" link. It needs the storefront check (StoreKit `Storefront.current?.countryCode == "USA"`) and the web checkout above. Apple may later charge a commission on it.
- **Not allowed without a Google program**: anything in the Google Play build.
- **How the app may talk about it**: the dApp Store build may show and name it freely. The App Store and Play builds must not mention it, except the US link above. The website, email and social posts may mention it anywhere ("communications outside of the app").

## 2. What is built

**Server** (`server/src/lib/cryptopay.ts`, `server/src/routes/cryptopay.ts`, registered in `src/index.ts`):

- `GET /billing/crypto` (signed in): `{enabled:false}` unless `GLYF_TREASURY` is a valid Solana address, `SOLANA_RPC_URL` is set and the database is on. Otherwise `{enabled:true, token:"USDC", mint, prices}`.
- `POST /billing/crypto/request {plan: plus|max, period: month|year}` (signed in): makes a fresh 32-byte `reference` and stores the request in `glyf_crypto_payments` (reference, user, plan, period, amount in base units, mint, treasury). It answers with the Solana Pay URL: `solana:<treasury>?amount=2&spl-token=<USDC>&reference=<ref>&label=Glyf&message=Glyf%20Plus%2C%201%20month`.
- `POST /billing/crypto/verify {reference}` (signed in, the owner only):
  - It calls `getSignaturesForAddress(reference)` and then `getTransaction(jsonParsed)` on `SOLANA_RPC_URL`.
  - It counts what the treasury gained in that mint, from `pre/postTokenBalances` by owner, so either an existing USDC account or a newly opened one works.
  - Failed transactions are skipped.
  - Answers:
    - `202 {pending:true}` until the transfer lands.
    - `402` if it was short.
    - `409` if that transaction already paid another request.
    - `404` if it isn't the caller's request.
    - `200 {plan, paidPlan, period, signature, expiresAt}` once paid.
- **One payment per reference, one reference per transaction**:
  - The row is marked paid with one `update … where signature is null`.
  - `signature` is `unique`.
  - The plan's end is fixed in the row at that moment, so asking again never adds days.
  - If saving the plan failed, the next verify finishes it with the same end.
- **The plan**: the payment becomes a purchase named `sol:<signature>`, with product `sol.<plan>.<period>` and environment `solana` (or `solana-test` on another mint). It is stacked like a gift code:
  - A month is 30 days and a year is 365.
  - The days start where the same plan already ends.
  - Max outranks Plus (`Users.refreshPlan`).
- The table is created on first use (`create table if not exists`, the same as `glyf_codes`). There is no migration step.
- **Tests**: `server/test/cryptopay.test.ts` (18) uses a pretend Solana and a pretend Postgres. It covers:
  - the base58 round trip and the URL
  - balance arithmetic
  - pending, paid, short and failed transactions
  - USDC sent to the wrong owner, and the wrong token
  - idempotence, including no RPC calls once paid
  - stacking
  - one transaction carrying two references
  - another account's reference
  - recovery after a failed save
  - off without a treasury or a node

**App** (Flutter):

- `app/lib/wallet/crypto_pay.dart`:
  - `CryptoPay.allowed` is `bool.fromEnvironment('GLYF_CRYPTO_PAY') && Platform.isAndroid`. Store builds compile it out of sight.
  - The paywall also asks `GET /billing/crypto`, so the server can switch it off.
  - Paying:
    - With a Mobile Wallet Adapter wallet on the phone (Seed Vault, Phantom, Solflare), the app builds the USDC transfer itself: CreateIdempotent for the treasury's account, then TransferChecked with the reference as a read-only account, the way Solana Pay does it. The wallet signs it, and it is sent through the existing `/wallet/rpc` relay.
    - Without one, the app opens the `solana:` link in whatever wallet takes it.
  - It then polls verify every 3 s for up to 3 minutes.
  - Unfinished references are kept in shared settings (`cryptoPending`, at most 5). They are asked about again at launch and on resume for a week.
- `app/lib/profile/paywall_sheet.dart`:
  - When USDC is on and the App Store isn't selling, the plan cards become selectable and the button reads **Pay 2 USDC**, Pay 20, 5 or 50.
  - When both are on sale, it is a second button under Get Plus.
  - Statuses: "Waiting for Solana", and "Not on Solana yet. Your plan starts when it lands".
- `app/lib/core/glyf_api.dart`: `cryptoConfig`, `cryptoRequest`, `cryptoVerify`.
- `app/lib/main.dart`: `CryptoPay.resume()` next to `Billing.sync()`.
- `GlyfBridge.kt`: `openURL` also opens `solana:` links, and answers false when no wallet takes them.
- **Tests**: `app/test/wallet/crypto_pay_test.dart`:
  - The transfer's bytes: the reference is read-only and unsigned, it is the last account of TransferChecked, and the amount is exactly 5 USDC.
  - The request parsing.
  - The store builds never show USDC.

## 3. What Arpit sets

On **Railway** (the API service):

| Variable | Value | Notes |
|---|---|---|
| `GLYF_TREASURY` | The public address of the wallet that receives (for example a separate Phantom account kept for Glyf) | Public, not a secret. Unset means the feature is off everywhere. |
| `SOLANA_RPC_URL` | A mainnet RPC URL with its key | Already owed for the wallet. The feature stays off without it. |
| `GLYF_USDC_MINT` | Leave unset on Railway | Mainnet USDC is the default. Only for devnet tests. |

The **dApp Store build** is built with:

```
flutter build apk --release --dart-define=GLYF_CRYPTO_PAY=true
```

Once the `dappStore` flavor from [SOLANA-DAPP-STORE.md](SOLANA-DAPP-STORE.md) lands, add `--flavor dappStore` to the same command. The flavor picks the signing key; the define is what turns USDC on.

The App Store and Google Play builds are built without it, as now. Don't upload a Play build with the flag on.

## 4. Testing

**Devnet (free), against a local server, never production:**

1. In a shell, not in `server/.env`, which holds production:
   ```
   cd server
   DATABASE_URL=<a throwaway Neon branch or local Postgres> \
   GLYF_TREASURY=<your devnet wallet address> \
   GLYF_USDC_MINT=4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU \
   SOLANA_RPC_URL=https://api.devnet.solana.com \
   MOCK_AI=true npm run dev
   ```
   `4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU` is Circle's devnet USDC. Get some at faucet.circle.com, and devnet SOL for fees at faucet.solana.com.
2. Point a debug Android build at that server, built with `--dart-define=GLYF_CRYPTO_PAY=true`. Switch Phantom or Solflare to devnet, open Upgrade, pick Plus monthly, and tap **Pay 2 USDC**.
3. Or without the app:
   - `POST /billing/crypto/request` with a session token, which gives the `url`.
   - Open that `solana:` URL as a QR code in a devnet wallet.
   - Call `POST /billing/crypto/verify` until it answers 200.
   - Check `glyf_crypto_payments` and the `sol:<signature>` row in `glyf_purchases`.

**Mainnet, small**: with `GLYF_TREASURY` set on Railway, buy Plus monthly from the Seeker build. It costs 2 USDC plus a fraction of a cent in SOL, and the money goes to the treasury you own. Check that the plan shows on the phone and on the iPhone signed in to the same account.

## 5. Not done

- **Refunds**: a USDC payment can't be pulled back. Refund by sending USDC from the treasury, then shorten the `sol:` purchase's `expires_at`.
- **Renewal**: each payment is one month or one year. Nothing renews by itself. Solana has no pull payments without a delegate approval, which Glyf doesn't ask for.
- **Accounting and tax**: the treasury's incoming transfers are the record. Each `glyf_crypto_payments` row links a transfer to an account.

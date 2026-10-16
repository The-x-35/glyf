# Glyf on the Solana dApp Store

How to get the Android app onto the Solana dApp Store (Seeker and Saga, and any Android phone with the store installed), as researched on 2026-10-14. What Arpit has to do himself, what is ready in the repo, the policy answers (crypto subscriptions included), and the risks. The listing itself is in [`dapp-store/config.yaml`](../dapp-store/config.yaml). Sources are numbered [S1]… at the end.

## In short

- **Free to list, 0% commission.** Solana Mobile takes no cut of app sales, in-app purchases or subscriptions [S13][S15]. Costs are network fees and storage: keep about **0.2 SOL** in the publisher wallet for the first submission [S1]. Each later release mints a new NFT for about **0.015 SOL** (the CLI won't start below 0.016 SOL) [S6].
- **How it works now:** sign up in the **Publisher Portal** (publish.solanamobile.com), pass KYC/KYB, connect a browser wallet as the publisher wallet, add the app (this mints the **App NFT**), then upload a signed release **APK** (this uploads the files to Arweave and mints a **Release NFT**) [S1]. Review takes **3–5 business days** [S1][S13].
- **The CLI only does updates.** `@solana-mobile/dapp-store-cli` 1.0.x (Sep 2026) uploads a new APK for an app that already exists in the portal. The old `config.yaml` commands (`init`, `create`, `validate`, `publish submit|update`) are gone [S2][S3]. `dapp-store/config.yaml` keeps the last config format as the source for the portal's forms.
- **APK only, no AAB; release build, not debuggable; a new signing key**, separate from Play's [S8][S9][S10]. Every update needs a higher `versionCode` and the same key [S9][S11].
- **Crypto subscriptions: yes.** On the dApp Store, Glyf can sell Plus and Max for USDC or SOL paid from Phantom or Seed Vault Wallet. There is no Google Play Billing requirement and no store fee. Glyf has to run its own checkout, because the dApp Store has no payment system. The USDC checkout is built and on in the `dappStore` flavor whenever the server has `GLYF_TREASURY` set; the Play and iPhone builds never show it. See [Crypto subscriptions](#crypto-subscriptions-the-pro-plan-paid-from-phantom).

## Checklist

### Arpit does these (needs his keys, accounts or money)

1. **Decide two things first.**
   - **Package name.** The recommendation is to keep `com.arpit.glyf`: Google sign-in, the `glyf://` link Phantom returns to, the MWA identity and the server all already work with it. The cost: a phone that has the Play build can't install the dApp Store build over it, and vice versa (different signing keys). Switching means uninstalling, which deletes the on-phone vault and learned words. The alternative is `com.arpit.glyf.dapp`, which needs its own OAuth client and would show two "Glyf" keyboards on a phone that has both. See [Risks](#risks).
   - **What v1 contains.** The recommendation is to ship v1 free (daily allowance and gift codes, "Plans open soon" as today), with the wallet but **without Buy on tokenized stocks**. Add USDC plans in v1.1, after the server side is built (each update is reviewed again). Since 2026-10-17 the `dappStore` build already hides stock buys, and its USDC plans open only once `GLYF_TREASURY` is set on Railway, so leaving it unset ships v1 free.
2. **Make the publisher wallet** and back up its seed phrase offline. Losing it means no more submissions for the app [S1]. Use Phantom, Solflare or Backpack as a browser extension [S1]. To publish updates from the CLI later, the CLI's `--keypair` must be this same wallet (the portal checks the signer against the publisher address [S7]). So create it as a keypair file yourself (`solana-keygen new -o ~/.config/solana/glyf-dapp-store-publisher.json`, outside the repo) and import that key into the browser wallet. Write the address into `publisher_wallet.address` in the config; it is public.
3. **Fund it with about 0.25 SOL.** The portal asks for about 0.2 SOL for fees and the ArDrive upload [S1]. The release APK is about 62 MB, and the portal's storage cost tool gives the exact figure. Keep at least 0.02 SOL for each later release [S6].
4. **Publisher Portal:** create the account at https://publish.solanamobile.com, fill in the publisher profile, finish **KYC/KYB** (18+; access can be held until it's done [S15]), and accept the Developer Agreement and Publisher Policy [S1][S14][S15]. Choose **ArDrive** storage and top up its balance when asked [S1].
5. **Back up the dApp Store signing key. Done 2026-10-17, except the backup.** The key exists: `app/android/dappstore.jks` (PKCS12, RSA 4096, alias `dappstore`, valid to 2054, gitignored by `**/*.jks`). Its password is in the gitignored `app/android/key.properties` as `dappStoreStoreFile`, `dappStoreStorePassword`, `dappStoreKeyAlias`, `dappStoreKeyPassword` (one password for store and key, as PKCS12 wants). It is not the Play upload key [S9][S10]. **Copy the `.jks` and its password into the password manager and a second place off this Mac now.** Losing either ends dApp Store updates for good: every update must be signed with this exact key [S9][S11].
   - SHA-1 `94:C3:42:F1:4D:30:5F:A8:A3:B7:9A:36:5B:41:AB:12:AC:6D:89:9A`
   - SHA-256 `0A:78:0E:62:CA:08:65:40:46:95:6D:E4:17:10:A3:C0:CA:CB:1F:4A:36:12:AC:62:AF:AE:B7:6E:A8:B1:32:20`
6. **Google sign-in for the new key.** Add an Android OAuth client in Google Cloud project glyf-508610 for `com.arpit.glyf` with the SHA-1 above. Without it, Google turns sign-in down with "[16] Account reauth failed", the same failure PLAY-STORE.md recorded on 2026-10-05.
7. **Android developer verification.** Since 2026-09-30, certified Android phones in Brazil, Indonesia, Singapore and Thailand block installs from developers who haven't registered with Google, store installs included. This goes global in 2027 [S20]. In Play Console's developer verification, register `com.arpit.glyf` with the dApp Store key as well. Play registers only what it signs [S20].
8. **Site: deploy the Terms page.** `site/app/terms/page.tsx` (effective 17 October 2026) is built and linked from the site's footer and the app; it goes live at https://www.tryglyf.com/terms on the next push to main. The listing's license and copyright URLs in `dapp-store/config.yaml` point there [S5].
9. **Server, before and during review:**
   - `REVIEW_MODE=true` (the "App Review sign-in" button) and the review password, which goes in the portal's testing field and never in the repo.
   - `SOLANA_RPC_URL` on Railway, still owed. Reviewers are told to test wallet connect and signing [S8].
   - `KLIPY_APP_KEY`, or cut "(search KLIPY)" from the description.
10. **Graphics:** make the banner (1200 × 600) and the feature graphic (1200 × 1200). Optionally add a wallet screenshot and an Android video. See the [asset plan](#asset-plan).
11. **Build** (the [flavors](#build-change-a-dappstore-flavor) are in since 2026-10-17):
    ```bash
    cd app && flutter build apk --release --flavor dappStore
    apksigner verify --print-certs build/app/outputs/flutter-apk/app-dappstore-release.apk   # must show the dApp Store key, not the Play upload key
    aapt2 dump badging build/app/outputs/flutter-apk/app-dappstore-release.apk | grep -c debuggable  # must print 0
    ```
    Test it on a phone or emulator, including Mobile Wallet Adapter with Phantom (and Solflare if possible) [S8]. A Seeker isn't needed [S13].
12. **Submit in the portal:** "Add a dApp" > "New dApp", filled from `dapp-store/config.yaml`. Then the app's Home > **New Version** > upload the APK > Submit. **Approve every signing prompt and skip none**, or assets go missing [S1].
13. **Review:** the answer comes by email from publishersupport@dappstore.solanamobile.com in 3–5 business days. With no answer after 5 days, ask in `#dev-answers` on the Solana Mobile Discord [S1]. An approved release goes live at once [S1][S11].
14. **Updates:** see [Updates](#updates).

### Ready in the repo

- `dapp-store/config.yaml`: every listing field filled from PLAY-STORE.md and the code:
  - name, the 30-character short description and the long description (Play's text, with the vault, clipboard and wallet lines brought up to date)
  - what's new, the Seeker features, testing instructions, URLs, locales, the Play package, and media paths to existing files
  - clear `<<PLACEHOLDERS>>` for the publisher name, wallet, keypair path, Terms URL and review password
- `dapp-store/.gitignore` keeps keypairs (`*.json`), keystores and APKs in that folder out of git.
- In the app:
  - **Seeker wallet support:** Mobile Wallet Adapter with Seed Vault Wallet, Phantom as the fallback (commit e3f7e07)
  - a `solana-wallet` `<queries>` entry, so the app can find a wallet
  - Glyf never holds keys
- Already in place for the policy:
  - **privacy policy** (https://www.tryglyf.com/privacy)
  - **account deletion** page (https://www.tryglyf.com/delete-account)
  - **Report** on AI results (the policy asks for in-app reporting where there is user-generated content [S14])
  - an encrypted vault (the policy asks for regulated data to be encrypted [S14])
  - no WebViews loading untrusted pages (forbidden by the policy [S14])
- Release signing from `key.properties`, minSdk 28, and Play's target SDK. No dApp Store rule on min or target SDK was found.

## How publishing works

| | Publisher Portal | `dapp-store` CLI 1.0.x |
|---|---|---|
| Account, KYC, publisher profile | Yes | No |
| Create the app (mints the App NFT) | Yes | No: the app must already exist with its App NFT [S2][S3] |
| First release and updates | Yes: New Version > upload APK > sign | Yes: `dapp-store --apk-file app.apk --keypair <publisher keypair> --whats-new "…"` with `DAPP_STORE_API_KEY` (made at publish.solanamobile.com/dashboard/settings/api-keys) [S2] |
| Edit listing text and media | Yes: shown only once a new version is approved [S11] | No |
| Signer | The connected browser wallet | A keypair file, which must be the publisher wallet [S7] |

The CLI finds the app from the APK's package name, uploads the APK, mints the Release NFT through the portal's backend and can `resume` a half-finished publication [S3]. It is meant for CI, but it needs the publisher key on the CI machine, so publishing by hand from the portal is safer for now.

**The NFTs** [S18]:

| NFT | What it is | When it is minted |
|---|---|---|
| Publisher | A Metaplex certified collection over its apps | In the portal era the publisher is mainly the portal account plus the publisher wallet |
| App | A collection over its releases | When the app is created in the portal; `app.address` is its mint |
| Release | Immutable, one per version, with the listing, media hashes and APK hash | At every submission; `release.address` |

The files are stored on Arweave, through ArDrive or Turbo, or in your own S3 bucket [S1].

## APK requirements

| Question | Answer |
|---|---|
| APK or AAB? | **APK only.** "The dApp Store requires an APK instead" [S9] |
| Signing key | **A new key just for the dApp Store.** "You cannot use the same signing key for both Google Play and the dApp Store" [S10]. Every update must use the same key [S9][S11] |
| Debuggable build? | **Refused.** "Debug builds will not be accepted" [S8]. The older CLI checked for `application-debuggable` and rejected the APK [S4] |
| minSdk / targetSdk | No published rule [S8][S9]. The release metadata records `min_sdk` [S4]. Glyf: minSdk 28, target from Flutter (36, like Play) |
| versionCode | Higher on every update; versionName too [S9][S11]. If the package stays `com.arpit.glyf`, share one counter with Play (the `+N` in `pubspec.yaml`) so the numbers never go backwards |
| Size | No limit published. Glyf's universal release APK is about 62 MB; keep it universal (arm64 and arm) |
| Test account | Required when content is gated [S8]: the App Review sign-in |

## Asset plan

Rules: icon 512 × 512 [S12][S4]; banner exactly 1200 × 600 and feature graphic exactly 1200 × 1200 [S4]; screenshots at least 1080 px on both sides, one orientation and one aspect ratio [S12]; videos `.mp4`, at least 720 px on both sides, 1920 × 1080 strongly recommended [S12]; at least 4 screenshots and videos together [S4]; JPEG, PNG or WebP [S4]. The current portal still takes `icon`, `banner`, `featureGraphic`, `screenshot` and video media [S3].

| Asset | Status | Source |
|---|---|---|
| App icon 512 × 512 | **Reuse** | `marketing/play/icon-512.png` |
| Release icon 512 × 512 | **Reuse** | Same file |
| Screenshots 1080 × 1920 (×6) | **Reuse** | `marketing/play/phone/01-rewrite.png` … `06-style.png`: real Android captures, portrait, same ratio, all meet the 1080 px minimum |
| Wallet screenshot 1080 × 1920 | **Missing, recommended** | The store's audience is crypto, so show "Send" from a copied address or the `$SOL` Buy card. Capture on the emulator the way PLAY-STORE.md describes, add it to `SHOTS` in `marketing/play/src/frame.py`, and save it as `dapp-store/media/07-wallet.png` (or under `marketing/play/phone/`) |
| Banner 1200 × 600 | **Missing, required** | Re-lay `marketing/play/src/feature.html` (the 1024 × 500 Play feature graphic: "Type less. glyf more." over the keyboard with the "$22.50 each" chip) at 1200 × 600 and shoot it with the same headless-Chrome `shoot()` from `frame.py`. `site/public/brands/glyf-x-banner.png` (1500 × 500) is the wrong ratio; cropping it loses the edges |
| Feature graphic 1200 × 1200 | **Missing, optional in the template** | The same scene stacked: headline above, keyboard below |
| Video | **Missing, optional** | The existing clips show the **iPhone/iPad** keyboard (`marketing/clips/01-split-the-bill.mp4` 1080 × 1920; `site/public/brands/glyf-waitlist.mp4` 1920 × 1080). They meet the size rules, but an Android store listing showing iOS is "misleading" under the policy [S14]. Record on the Android emulator (`adb shell screenrecord`) and frame it at 1920 × 1080 |

Put new files in `dapp-store/media/`; the paths in `config.yaml` already point there.

## Review, fees, SOL and updates

- **Review:** in submission order, 3–5 business days, by email; ask on Discord after 5 days [S1][S11]. Approved releases go live at once [S1]. Solana Mobile can remove an app "at any time and for any or for no reason" [S15].
- **Fees:** none for listing, and 0.0% commission (§4.3), which "may be revised" [S15]. The FAQ's word is "currently" [S13].
- **SOL:** about 0.2 SOL for the first submission (transactions and ArDrive) [S1]. About 0.015 SOL of rent and fees per Release NFT, and the CLI refuses to start below 0.016 SOL [S6].
- <a id="updates"></a>**Updates:**
  1. Raise the versionCode and versionName, and sign with the same dApp Store key.
  2. In the portal, the app's Home > New Version: upload the APK, or "use existing APK" to change only the listing. Fill in "What's new" and sign each prompt.
  3. The release is reviewed again and goes live when approved [S11].
  4. Or, from a terminal: `DAPP_STORE_API_KEY=… dapp-store --apk-file …/app-dappstore-release.apk --keypair <publisher keypair> --whats-new "…"` [S2].

  Listing edits show only after a new version is approved [S11].

## Policy answers

| Question | Answer |
|---|---|
| In-app crypto payments | Allowed. The policy has no payments section at all [S14]. The Agreement lets the developer set prices "including subscription or periodic fees" (§4.1) through a payment processor the developer chooses, with the developer as seller of record (§4.2), responsible for refunds (§4.5) and taxes (§4.4) [S15] |
| Subscriptions | Allowed (§4.1), 0% commission [S13][S15] |
| Google Play Billing | **Not required.** Play's Payments policy binds apps distributed on Google Play [S19]; no dApp Store document asks for it [S13][S14][S15]. The Play build must keep Play Billing and must not link to or mention the crypto checkout [S19] |
| A dApp Store payment system (IAP, Solana Pay, SKR)? | **None.** The docs have no in-app purchase or Solana Pay pages [S22]. Third-party articles about paying in SKR inside the store are unconfirmed. Glyf builds its own checkout |
| Seed Vault | Apps reach it through Mobile Wallet Adapter. The Seed Vault SDK is for wallet makers only, so Glyf already does the right thing [S16] |
| Seeker Genesis Token (SGT) | Optional. One per Seeker, in the Seed Vault Wallet's primary account; check it with `@solana-mobile/skr-genesis-token` [S17]. Possible perk: a free month of Plus per Seeker. Check that the wallet holds an SGT, have the user sign a message, and record the SGT's mint so it can't claim twice (it moves between a user's own accounts) [S17]. Up to 10 SGT wallets can be early testers (`alpha_testers`) [S4][S5] |
| Restricted content | Illegal content, hate speech, deceptive listings, malware, untrusted WebViews, and features that break third-party terms [S14]. Regulated financial services must supply the documentation the law asks for [S14]. That applies to buying **tokenized stocks** (xStocks): hide that Buy in the dApp Store build |
| User data | Disclose it, encrypt regulated data in transit and at rest, offer account deletion, and use no coercive consent [S14]. Glyf has the privacy policy, the deletion page, "What Glyf sends" and the encrypted vault |
| Keyboards | **No keyboard-specific rule** in the policy, agreement or docs [S14][S15]. Things to watch: (1) give reviewers step-by-step setup and point to Android's own "this keyboard can see what you type" notice; (2) "induces users to change security settings" counts as misleading [S14], so describe turning on a keyboard plainly; (3) the keyboard sees regulated data (passwords, cards), so state the masking and the on-phone vault; (4) the listing needs at least 4 screenshots of the real Android keyboard |

## Crypto subscriptions: the "pro plan paid from Phantom"

**The answer: yes, on the dApp Store, with no Play Billing and no store fee** [S13][S15][S19]. It must not appear in the Play build (Play forbids in-app links or wording that steers people to other payments for digital goods [S19]) or the iPhone build (Apple's 3.1.1 [S23]). A plan bought with crypto is held on the Glyf account, so it can still work when the same person signs in on another platform. Before showing that anywhere on iOS, check it against Apple's multiplatform rule, 3.1.3(b) [S23].

**State on 2026-10-17:** built (commit 3967e16); [CRYPTO-PAYMENTS.md](CRYPTO-PAYMENTS.md) is the reference. It shows only in the `dappStore` flavor, only on Android, and only while the server has `GLYF_TREASURY` set. The `play` flavor never shows it, even with `--dart-define=GLYF_CRYPTO_PAY=true`. The outline below gives the dApp Store's requirements it meets:

1. **dApp Store build only:** the paywall offers "Pay with USDC" at the store prices: Plus $2 a month or $20 a year, Max $5 a month or $50 a year.
2. `POST /billing/solana/quote` (signed-in) returns:
   - the treasury's USDC address
   - the exact amount
   - a fresh random **reference** key, the Solana Pay pattern
   - an expiry
3. The app builds the transfer with the reference as an extra read-only account, using the wallet's existing build → sign → broadcast path. Seed Vault Wallet or Phantom signs it over MWA, or Phantom by deeplink.
4. `POST /billing/solana/confirm {signature}`: the server reads the finalized transaction (`SOLANA_RPC_URL`) and checks:
   - the USDC mint
   - the recipient
   - the amount
   - that the reference is present
   - that the signature hasn't been used before

   It then sets the plan with an end date: 30 or 365 days, **prepaid**. Crypto can't auto-renew without asking the user to approve a token delegation, which is best avoided. Remind people before the end date.
5. Needs:
   - a treasury wallet Arpit controls, with its key never on the server
   - a `glyf_crypto_payments` table
   - a privacy-policy line (the paying wallet address and the transaction are tied to the account)
   - a refund line in the Terms
   - tax handling as seller of record [S15]

   The Agreement's §6 also warns that tokens may be treated as securities; paying in USDC keeps that simple [S15].

## Build change: a `dappStore` flavor

**Made 2026-10-17.** The sketch below is close to what `app/android/app/build.gradle.kts` now holds; the real file differs in the names (`dappStoreStoreFile` etc.), sets each flavor's `signingConfig` inside `productFlavors`, and marks `play` `isDefault` (that only picks Android Studio's variant: `flutter` still needs `--flavor`). It follows Solana Mobile's recipe of two flavors, each with its own key [S10]:

```kotlin
android {
    flavorDimensions += "store"
    productFlavors {
        create("play") { dimension = "store" }
        create("dappStore") { dimension = "store" }   // same applicationId com.arpit.glyf (see Checklist 1)
    }
    signingConfigs {
        // existing "upload" stays; add:
        if (uploadKey.getProperty("dappStoreStoreFile") != null) {
            create("dappStore") {
                storeFile = rootProject.file(uploadKey.getProperty("dappStoreStoreFile"))
                storePassword = uploadKey.getProperty("dappStoreStorePassword")
                keyAlias = uploadKey.getProperty("dappStoreKeyAlias")
                keyPassword = uploadKey.getProperty("dappStoreKeyPassword")
            }
        }
    }
    // A build type's signingConfig beats a flavor's, so release must no longer set one.
    productFlavors.getByName("play").signingConfig =
        signingConfigs.findByName("upload") ?: signingConfigs.getByName("debug")
    productFlavors.getByName("dappStore").signingConfig =
        signingConfigs.findByName("dappStore") ?: signingConfigs.getByName("debug")
    buildTypes { release { /* remove the signingConfig line */ } }
}
dependencies {
    // Play Billing only in the Play flavor (it also adds the BILLING permission).
    "playImplementation"("com.android.billingclient:billing-ktx:9.1.0")   // instead of implementation(...)
}
```

What it does:

- **Builds:** `flutter build appbundle --release --flavor play` for Play (`bundle/playRelease/app-play-release.aab`), and `flutter build apk --release --flavor dappStore` for the dApp Store (`flutter-apk/app-dappstore-release.apk`). Every Android `flutter run` and `flutter build` needs `--flavor`; day-to-day debug builds use `flutter build apk --debug --flavor play` (`app-play-debug.apk`). Debug builds of both flavors sign with the debug key.
- **Play Billing:** the Gradle dependency is `playImplementation`, so the dApp Store APK has neither the library nor its BILLING permission. No Flutter plugin brings billing; the Android paywall doesn't sell through Play yet (`Billing.available` is iPhone-only).
- **Dart:** `lib/core/flavor.dart` reads `appFlavor`. `CryptoPay.allowed` is on in the `dappStore` flavor by itself (no define needed) and never in `play`. `Flavor.stockBuys` is false in `dappStore`: `WalletFlow.buy` refuses a token Jupiter tags `stocks`, `equities` or `xstocks`, and the Buy screen says "Stocks can't be bought in this version of Glyf".
- **Kotlin:** `RatesStore.stockBuys` reads `BuildConfig.FLAVOR`. In `dappStore` a cashtag priced through a tokenized stock (`$aapl`) keeps its price chip but loses Buy, and a copied xStock address shows Paste without Buy (`TokenLookup.MintQuote.stock`, `Smart.AddressKind.Token.buy`). The server fallback (`/rates/crypto`, `/rates/token`) doesn't say which tokens are stocks yet, so a quote that came from the server keeps Buy in the keyboard; the app still refuses the buy.
- **Nothing else changes:** `com.arpit.glyf` on both, the iPhone build, the server's bundle ids and the `glyf://` scheme stay as they are.

## Risks

1. **Losing the publisher wallet or the dApp Store keystore** ends updates for good [S1][S9]. Back up both in two places.
2. **Two stores, one package name, two keys.** Installing one build over the other fails. Switching needs an uninstall, which deletes the on-phone vault and learned words. Say so in support replies, or choose a separate package name.
3. **Google sign-in breaks** in the dApp Store build until its SHA-1 has an Android OAuth client (checklist 6).
4. **Android developer verification:** installs are blocked in BR, ID, SG and TH now, and everywhere in 2027, unless the dApp Store key is registered [S20].
5. **Tokenized stock buys** fall under the policy's regulated financial services rule [S14]. Hide them in the dApp Store build.
6. **iOS footage** in an Android listing could be taken as misleading [S14].
7. **Review breaks** if REVIEW_MODE is off, `SOLANA_RPC_URL` is missing (wallet), or the Terms URL is a placeholder.
8. **Crypto plans make Glyf the seller of record**, with taxes, refunds and no auto-renew [S15]. They must never leak into the Play or iPhone builds [S19][S23].
9. **Terms can change:** "currently" no fees [S13], the commission "may be revised" [S15], and removal is at Solana Mobile's discretion [S15].
10. **The CLI changed format in 2026.** Older guides, including Helius's from 2024 [S21], describe `config.yaml` commands that no longer exist.

## Sources

- [S1] Submit a new app (portal, publisher wallet ~0.2 SOL, ArDrive, review 3–5 days): https://docs.solanamobile.com/dapp-store/submit-new-app
- [S2] Publishing CLI: https://docs.solanamobile.com/dapp-store/publishing-cli
- [S3] dapp-publishing repo: README (legacy flows removed), CLI 1.0.1 (2026-09-14), portal media purposes in `packages/cli/src/portal/releaseMetadata.ts`: https://github.com/solana-mobile/dapp-publishing
- [S4] Legacy CLI validator (icon 512, banner 1200×600, feature graphic 1200×1200, screenshots ≥1080, video ≥720 mp4, ≥4 media, short description ≤30, debuggable refused, ≤10 alpha testers): https://github.com/solana-mobile/dapp-publishing/blob/12fa1ce6f09d7cdb837fbcc6e3c0ef96dd5f07c2/packages/cli/src/config/PublishDetails.ts
- [S5] Legacy config template and example: https://github.com/solana-mobile/dapp-publishing/blob/12fa1ce6f09d7cdb837fbcc6e3c0ef96dd5f07c2/packages/cli/src/prebuild_schema/publishing_source.yaml, https://github.com/solana-mobile/dapp-publishing/blob/main/example/config.yaml
- [S6] CLI funding preflight (~0.015 SOL per Release NFT, 0.016 minimum): https://github.com/solana-mobile/dapp-publishing/blob/main/packages/cli/src/publication/fundingPreflight.ts
- [S7] Signer must be the publisher address: https://github.com/solana-mobile/dapp-publishing/blob/main/packages/core/src/portal/workflow/execution.ts
- [S8] Publishing checklist: https://docs.solanamobile.com/dapp-store/checklist
- [S9] Build and sign an APK: https://docs.solanamobile.com/dapp-store/build-and-sign-an-apk
- [S10] Publishing from Google Play (separate key, flavors): https://docs.solanamobile.com/dapp-store/publishing-from-google-play, https://docs.solanamobile.com/recipes/general/publishing-from-google-play
- [S11] Submit an update: https://docs.solanamobile.com/dapp-store/submit-an-update
- [S12] Listing page guidelines: https://docs.solanamobile.com/dapp-publishing/listing-page-guidelines
- [S13] FAQ (no fees on in-app purchases, app purchases or subscriptions; review 3–5 days; no Seeker needed): https://docs.solanamobile.com/get-started/faq
- [S14] Publisher Policy (last updated 2026-07-21): https://legal.solanamobile.com/publisher-policy-web
- [S15] Developer Agreement (last updated 2026-06-30; §1.3, §2.5, §3, §4.1–4.5, §6): https://legal.solanamobile.com/developer-agreement-web
- [S16] Seed Vault: https://docs.solanamobile.com/solana-mobile-stack/seed-vault
- [S17] Seeker Genesis Token: https://docs.solanamobile.com/solana-mobile-stack/seeker-genesis-token
- [S18] dApp Store NFT spec v0.4.0: https://github.com/solana-mobile/dapp-publishing/blob/main/publishing-spec/SPEC.md
- [S19] Google Play Payments policy: https://support.google.com/googleplay/android-developer/answer/10281818
- [S20] Android developer verification: https://developer.android.com/developer-verification
- [S21] Helius, publishing Solana mobile apps (2024, pre-portal): https://www.helius.dev/blog/publishing-solana-mobile-apps
- [S22] Solana Mobile docs index: https://docs.solanamobile.com/llms.txt
- [S23] App Store Review Guidelines 3.1.1 and 3.1.3(b): https://developer.apple.com/app-store/review/guidelines/

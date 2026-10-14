# Swap fee (Jupiter referral)

Glyf takes 0.5% of each buy through Jupiter's referral fee. The fee stays off until a referral account address is pasted into the code. Until then, buys work exactly as they did before (GO-TO-MARKET.md 4.6).

## What Arpit does once

1. **Create the referral account.**
   - Open https://referral.jup.ag/ and connect your own wallet (Phantom).
   - Create a referral account under the **Jupiter Ultra** project. Swap V2 `/order` uses Ultra's referral project, `DkiqsTrw1u1bYFumumC7sCG2S8K25qc2vemJFHyW2wJc`. Don't pick the old "Jupiter Swap" project, `45ruCyfd…`. That one is for the Metis and Trigger APIs.
   - Rent is about 0.003 SOL. You pay it once.
2. **Create a referral token account for each fee coin.**
   - Make them in the same dashboard: SOL (`So11111111111111111111111111111111111111112`), USDC (`EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v`) and USDT (`Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCE8BenwNYB`).
   - Each one costs about 0.002 SOL in rent.
   - Jupiter picks the fee coin itself, in this order: SOL, then stablecoins, then liquid staking tokens, then bluechips, then the rest. A buy paid in SOL or USDC pays its fee in SOL or USDC.
   - If the token account for a swap's fee coin is missing, the swap still goes through but pays Glyf nothing.
3. **Paste the referral account address** into all three constants below. Use the referral account itself, not a token account. The address is public, not a secret.
4. Build and ship.

## Where the setting lives

| Client | File | Constant |
|---|---|---|
| App (builds the real order, iOS and Android) | `app/lib/wallet/wallet_api.dart` | `SwapFee.referralAccount` |
| iOS keyboard (Buy panel quote) | `app/ios/GlyfKeyboard/Engine/TokenLookup.swift` | `SwapFee.referralAccount` |
| Android keyboard (Buy panel quote) | `app/android/app/src/main/kotlin/com/arpit/glyf/ime/SwapFee.kt` | `SwapFee.REFERRAL_ACCOUNT` |

- The rate is `bps = 50` (`BPS` on Android), next to each constant. Jupiter accepts 50 to 255.
- Fill all three with the same address. The app makes the order Phantom signs. The keyboards only show the price, so a keyboard left empty shows a price without the fee.
- The app constant covers both iOS and Android, because one Flutter build serves both. GO-TO-MARKET.md suggests Android first. To do that, the app constant needs an Android-only switch, which hasn't been built.

## How it works

- Each `/swap/v2/order` call adds `referralAccount=<address>&referralFee=50`.
- Jupiter keeps 20% of the fee and charges nothing else, so Glyf keeps 0.4% of each buy. Jupiter's own default fee (0 to 10 bps for most pairs, measured at 10 bps on SOL to BONK) is replaced, not added on top.
- The quote's `outAmount` already has the fee taken off. The "You get" figures show what lands.
- The Buy panel shows "Fee 0.5%" in the You get line, and the app's Buy screen shows it under the quote. Each appears only when Jupiter's answer names our `referralAccount`.
- If Jupiter refuses the referral account (for example "Please check that referralAccount is initialized under REFER4Zgmy… for project DkiqsTrw1…"), every client asks again without it. The buy goes through with no Glyf fee.

Measured on 14 Oct 2026, quote only, for 0.1 SOL to BONK:

| | `outAmount` | `feeBps` |
|---|---|---|
| No referral | 336,063,497,862 | 10 |
| With a referral at 50 | 334,717,898,271 | 50 |

- The difference is 0.40%: the 50 bps fee minus the 10 bps it replaced.
- `feeMint` was SOL for SOL to BONK, and USDC for both USDC to BONK and BONK to USDC.

## How to check the fee is working

1. **Before shipping**, run this with the referral account in place of `<REF>`:
   ```
   curl -s "https://api.jup.ag/swap/v2/order?inputMint=So11111111111111111111111111111111111111112&outputMint=EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v&amount=10000000&referralAccount=<REF>&referralFee=50"
   ```
   - The answer should carry `"referralAccount": "<REF>"`, `"feeBps": 50` and `"feeMint"`.
   - An `error` about `referralAccount` means the account isn't under the Ultra project.
2. **On a phone:** the Buy panel's You get line should show "Fee 0.5%".
3. **After a real buy** (yours, with a few dollars):
   - Check the referral dashboard, or the referral token account for that coin on Solscan.
   - The balance should grow by 0.4% of the swap.
   - Collect it through the dashboard.

## Sources

- Jupiter, Swap V2 fees (referral parameters, 50 to 255 bps, 20% share, fee coin order, missing token account): https://developers.jup.ag/docs/swap/fees
- Jupiter, Swap V2 order and execute (response fields `feeBps`, `feeMint`, `platformFee`, `referralAccount`; router eligibility): https://developers.jup.ag/docs/swap/v2/order-and-execute
- Jupiter, add fees to Ultra (project key `DkiqsTrw…`, referral account and token accounts): https://developers.jup.ag/docs/ultra/add-fees-to-ultra
- Jupiter, add fees to the Metis Swap API (`platformFeeBps` and `feeAccount`, which Glyf doesn't use): https://developers.jup.ag/docs/swap/add-fees-to-swap

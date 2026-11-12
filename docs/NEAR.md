# Glyf × NEAR: NEAR Intents in every chat

**Built at NEAR HACKATHON (1–14 Nov 2026).** Glyf is an AI keyboard for iPhone
and Android. This entry puts NEAR Intents where people already talk about
money: in the chat itself.

Type `swap 20 usdc on base to sol` or `send 5 usdc to alice.near` in any app.
Glyf's keyboard reads it on the phone, without a model, and shows a live NEAR
Intents quote: what you pay, what you get, and about how many seconds it
takes. One tap hands it to the Glyf app, and your own wallet sends the
deposit: MetaMask on EVM chains, Phantom on Solana. NEAR Intents (1Click)
settles it on the destination chain, and the app follows it until it lands.
Glyf never holds a key.

- **Repository:** https://github.com/The-x-35/glyf, branch `near-hackathon`
- **What was built during the hackathon:** everything after the tag `near-baseline`, which is Glyf as it stood before the NEAR work:
  https://github.com/The-x-35/glyf/compare/near-baseline...near-hackathon
- **Also by the same author:** the NEAR investment thesis, https://github.com/The-x-35/near-thesis. The two projects are independent and share no code.

## The problem

Money talk happens in chats ("you owe me $22.50", "send it to my sol"), but
moving money means leaving the chat, opening a wallet, and finding the right
bridge, chain and coin. People pay each other on different chains, and most
wallets only know one.

## What Glyf does with NEAR

| You type (any app) | What happens | Track |
|---|---|---|
| `swap 20 usdc on base to sol` | Live NEAR Intents quote, a deposit from MetaMask, SOL lands in Phantom in about 30 s | Unstoppable DeFi |
| `swap 0.2 sol to usdc on base` | A deposit from Phantom, USDC lands on Base | Unstoppable DeFi |
| `swap 50 usdc on arbitrum to btc to bc1q…` | Native BTC to a Bitcoin address | Unstoppable DeFi |
| `move 50 usdc from base to solana` | The same coin, moved across chains | Unstoppable DeFi |
| `send 5 usdc to alice.near` | Pays exactly 5 USDC (EXACT_OUTPUT) to a NEAR account; you pay from Base USDC. The .near name is checked on NEAR RPC first | Real-World Money |
| `pay bob.near 10 usdc with sol` | Pays from SOL instead | Real-World Money |
| `dinner was $90 for the four of us` | The strip offers "$22.50 each" and a **pay link**. Each friend opens it, picks the coin and chain they hold (USDC on any chain, SOL, BTC, ZEC, NEAR…), and gets a deposit address and QR code. The requester is paid exactly $22.50 on their own chain. The page shows "2 of 4 paid" | Social Money, Real-World Money |
| A pay link to `trip.sputnik-dao.near` | Everyone pays into a Sputnik DAO treasury: a shared pot. Its page shows what the pot holds and who's in it, read live from the DAO | Social Money |
| `how much is in the trip pot` | The pot's balance (NEAR, plus USDC/USDT held directly or inside NEAR Intents), members, how many approvals a payout needs ("2 of 3"), and its open proposals with their votes, all from Sputnik DAO views on NEAR RPC | Social Money |
| `pay the caterer $120 from the pot` | A payout to propose: Glyf links Trezu's payment form with the recipient and token filled in, and gives the line to post in the group ("Proposing 120 USDC to caterer.near from the trip pot. Vote: …"). The members vote in Trezu | Social Money, Real-World Money |
| `put $50 to work` / `put 0.5 sol to work` | **Earn** through 1Click: USDC goes into Morpho's Gauntlet USDC Prime vault on Base, SOL into Kamino's SOL Balanced vault, with the APY read from Morpho's and Kamino's own public APIs (4.5% and 4.24% on 13 Nov). The deposit is a plain NEAR Intents quote, so the same MetaMask/Phantom flow pays it | Unstoppable DeFi, Real-World Money |
| `take my usdc out of earn` / `take 20 usdc out of earn` | The reverse quote: vault shares back to USDC, everything or exactly 20 | Unstoppable DeFi |
| `you owe me 22.50 for dinner, I'm on solana` | The AI suggestion strip offers "Request $22.50 on Solana · NEAR Intents". The model only picks from a fixed list of tools, and every value is checked on the server against the words actually typed | Agent Economy |
| Any send | **Guard** checks it before anything is signed: address poisoning (a lookalike of someone you paid before), a .near account that doesn't exist, a recipient that can't receive on that chain, a first-time recipient, your daily limit, large amounts. A block stops the button | AI Security & Defense |
| Profile › Keyboard › Private AI on NEAR | Glyf's writing and answers run only on NEAR AI Cloud's private models, inside a TEE. Each answer leaves a receipt: NEAR AI's ECDSA signature over the hashes of the exact request and response bytes, checked against the model's attestation report | Privacy & Private AI |
| Any origin Glyf can't sign for (BTC, ZEC, TON…) | "Send from any wallet": deposit address, exact amount, memo and QR code, then live tracking | Open Innovation |

NEAR Intents is used through its 1Click API. Quotes cover 21 chains and 230
assets: Solana ↔ EVM, Bitcoin, Zcash, NEAR, TON, Tron, XRP, Dogecoin,
Litecoin, Sui, Aptos, Stellar and Cardano. Same-chain swaps stay on Uniswap
(EVM) and Jupiter (Solana), which Glyf already had. NEAR Intents takes
everything those can't reach.

## Try it (do X, see Y)

Needs Node 20+ and npm. No keys, no account, no phone.

```bash
git clone -b near-hackathon https://github.com/The-x-35/glyf && cd glyf/server
npm install
npm run near:quote -- "swap 20 usdc on base to sol"
```

You'll see a live NEAR Intents quote. It's a dry quote, so nothing moves:

```
  Venue        NEAR Intents (1Click, dry quote: nothing moves)
  You pay      20 USDC on Base ($19.99)
  You get      0.2446 SOL on Solana ($19.98)
  Time         about 32 s after the deposit confirms
```

More phrases to try:

```bash
npm run near:quote -- "send 5 usdc to illia.near"               # exact output to a NEAR account; Guard: first time paying
npm run near:quote -- "send 5 usdc to nobody-glyf-zz9.near"     # Guard blocks: no such NEAR account
npm run near:quote -- "swap 0.2 sol to usdc on base"
npm run near:quote -- "swap 50 usdc on arbitrum to btc"
npm run near:quote -- "move 50 usdc from base to solana"
npm run near:quote -- "put 50 usdc to work"                     # Earn: vault, APY from Morpho, live 1Click quote
npm run near:quote -- "put 0.5 sol to work"                     # Earn: Kamino SOL Balanced
npm run near:quote -- "take 20 usdc out of earn"                # Earn: the reverse quote
npm run near:pot -- build.sputnik-dao.near                      # a real Sputnik DAO pot: balance, members, "3 of 5", proposals
npm run near:pot -- build.sputnik-dao.near "pay efiz.near \$120 from the pot for catering"   # the Trezu link that proposes it
```

Tests (no network; every external call is faked):

```bash
cd server && SESSION_SECRET=any-test-secret npm test     # 570 tests, NEAR ones in test/near*.test.ts, sputnik.test.ts, pay.test.ts, privateai.test.ts, names.test.ts, actions.test.ts
cd app && flutter test test/near_flow_test.dart test/near_trade_screen_test.dart test/private_ai_near_test.dart
cd app/ios && xcodebuild test -workspace Runner.xcworkspace -scheme Runner -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:RunnerTests/TradeIntentTests
```

The live API is https://api.tryglyf.com. Its NEAR routes need a Glyf
session, except the public pay pages at `/pay/<id>`.

## Where the code is

| Part | Files |
|---|---|
| NEAR Intents client (1Click: tokens, quote, status, deposit submit, 21 chains, address formats, deposit building) | `server/src/lib/nearintents.ts` |
| Guard | `server/src/lib/nearguard.ts` |
| Phrase reader for the CLI | `server/src/lib/nearphrase.ts`, `server/scripts/near-quote.ts`, `server/scripts/near-pot.ts` |
| Routes: `/near/quote`, `/near/status`, `/near/submit`, `/near/requests`, `/near/earn/vaults`, `/near/earn/quote`, `/near/pot`, `/near/pot/propose-link` | `server/src/routes/near.ts` |
| Earn (1Click receipt-token quotes, vault list, Morpho/Kamino APY) | `server/src/lib/nearearn.ts` |
| The group pot (Sputnik DAO views, vote thresholds, Trezu propose links) | `server/src/lib/sputnik.ts` |
| Pay links (`/pay/:id` page, quote, status) | `server/src/routes/pay.ts`, `server/src/lib/payrequests.ts`, `server/src/lib/paypage.ts` |
| .near names (NEAR RPC `view_account`) | `server/src/lib/names.ts`, `server/src/routes/names.ts` |
| Private AI on NEAR AI Cloud, receipts | `server/src/lib/privateai.ts`, `server/src/providers/openrouter.ts` |
| AI-suggested NEAR actions | `server/src/lib/actions.ts`, `server/src/routes/suggest.ts` |
| iPhone keyboard: reading phrases, chip, trade panel, g menu | `app/ios/GlyfKeyboard/Engine/TradeIntent.swift`, `Surfaces/TradeSurface.swift`, `Engine/SponsorMenu.swift` |
| App: deposit through MetaMask or Phantom, tracking, QR | `app/lib/near/`, `app/lib/evm/trade_flow.dart`, `app/lib/evm/trade_screen.dart` |
| Android keyboard | `app/android/app/src/main/kotlin/com/arpit/glyf/ime/` |
| Contract between the parts | `docs/NEAR-SPEC.md` |

## Honest limits

- **Glyf has no NEAR wallet of its own**, so it can't sign NEAR-chain deposits. Swaps into NEAR are fine (to a .near account). Paying from NEAR, BTC or ZEC uses "Send from any wallet".
- **Keyless 1Click** adds its 0.2% fee. With a 1Click JWT (`NEAR_INTENTS_JWT`), that fee goes away.
- **Private AI on NEAR** needs NEAR AI Cloud credits on the deploying account. The switch is off by default, and without a key the server ignores it.
- **Confidential Intents** need wallet-signed auth. Not built.
- **The pot is read-only in Glyf.** Proposing and voting happen in Trezu with the member's own NEAR wallet (Trezu prefills the recipient and token; the amount and note are typed there). Glyf also returns the raw `add_proposal` call for a NEAR wallet to sign later.
- **Earn's APY** comes from each vault's protocol, not from NEAR Intents, and isn't guaranteed. Taler USDC has no public rate API, so Glyf shows none for it. Steakhouse USDC is listed by 1Click but had no liquidity on 13 Nov, so it isn't offered.

## Tools and AI use

- **Server:** TypeScript, Fastify, zod, viem, and `qrcode` for pay-link QR codes.
- **App:** Flutter, with `qr_flutter`.
- **iPhone keyboard:** Swift.
- **Android keyboard:** Kotlin.
- **AI coding assistants (Claude Code)** wrote much of the code under the author's direction. The author reviewed it, and it's covered by the tests above.

## License

Source-available, all rights reserved. Reading and running the code to
evaluate it, including judging, is allowed. See [LICENSE](../LICENSE).

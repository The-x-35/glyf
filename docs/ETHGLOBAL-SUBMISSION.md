# Glyf at ETHGlobal Mumbai (Continuity Track)

Glyf is an AI keyboard for iPhone and Android. It's on TestFlight, and its Solana wallet (Phantom), search, calendar and AI features run in any app. At Mumbai the iPhone keyboard learned to trade on Ethereum and its L2s **from the words you type in any chat**:

- "swap 0.05 eth to usdc on base" → a Uniswap swap.
- "sell my eth if it drops below 3000", "take profit eth at 4500", "my eth: take profit 4500, stop loss 3000", "protect my eth with a 5% trail", "buy $100 of eth if it dips below 2800", "buy $20 of eth every day for a week", "move 50 usdc from base to arbitrum" → Definitive Flash advanced orders.
- "send 5 usdc to vitalik.eth" / "pay arpit.sol 5 usdc" → ENS / SNS names resolved, then a transfer.
- "sell 0.1 sol if it drops below 100" → the same Flash orders on Solana, signed in Phantom.
- After a trade, **Share in chat** puts it in the conversation as a link; a friend's **Copy this trade** opens the same order in their Glyf.
- The keyboard's AI runs privately on **0G's Private Computer** (TEE-verified), with each answer's request id in the app.

Signing stays in the wallet: the Glyf wallet (an on-device key), **MetaMask by its own deeplinks** (Ethereum and L2s) or **Phantom by its deeplinks** (Solana). Glyf builds every transaction on the phone, and the wallet app only signs.

Also built at Mumbai, but not entered (ETHGlobal allows three partners): USDT requests on Whitechain ("request 20 usdt") and the Vault's encrypted backup on Arkiv.

## Before and during

- **Before (the starting point):** commit `f42b9c0` on `main`, 4 Nov 2026 17:48 IST, already Glyf as shipped on TestFlight: Solana only, Phantom signing, no EVM code anywhere.
- **During:** every commit on branch `ethglobal-mumbai` after `f42b9c0` (`git log f42b9c0..ethglobal-mumbai`). Nothing EVM-related existed before.

| Piece | Where | New at Mumbai |
|---|---|---|
| Plain-words trade reader | `app/ios/GlyfKeyboard/Engine/TradeIntent.swift` | all of it (19 tests: `app/ios/RunnerTests/TradeIntentTests.swift`) |
| Trade panel in the keyboard | `app/ios/GlyfKeyboard/Surfaces/TradeSurface.swift` | all of it |
| Glyf wallet (on-device EVM key, EIP-1559, EIP-712) | `app/lib/evm/evm_wallet.dart` | all of it |
| Swaps, Flash orders, sends, requests | `app/lib/evm/trade_flow.dart`, `trade_screen.dart` | all of it |
| Names, EVM relay, Flash proxy, Uniswap | `server/src/routes/{names,evm,flash,uniswap}.ts`, `server/src/lib/{names,evm,tokens,uniswap}.ts` | all of it (42 tests) |
| GlyfPayRequest (Whitechain) | `contracts/` | all of it (13 tests + fork test) |
| Vault on Arkiv | `app/lib/evm/arkiv_vault.dart`, `arkiv/` | all of it (byte-for-byte with the Arkiv SDK) |
| MetaMask by deeplink | `app/lib/evm/metamask_link.dart`, `evm_signer.dart` | all of it (tests: `app/test/evm_signer_test.dart`) |
| Flash on Solana through Phantom | `app/lib/wallet/flash_solana.dart` | all of it (18 tests: `app/test/wallet/flash_solana_test.dart`) |
| Share and copy a trade | `server/src/routes/tradeshare.ts`, `app/lib/evm/trade_share.dart`, the keyboard's Share trade chip | all of it (10 tests) |
| Private AI on 0G | `server/src/lib/privateai.ts`, `server/src/providers/openrouter.ts`, Keyboard › 0G receipts | all of it (5 tests: `server/test/privateai.test.ts`) |

## Partner by partner

### Definitive (Flash): "Most Creative Use of Flash Advanced Orders"

- **Voice-or-chat trading, which Definitive's prize text names.** Every Flash order type is reachable by typing a sentence in any app:
  - stop-loss, take-profit, limit, stop buy;
  - bracket, both on a holding and attached to a market buy;
  - trailing stop, TWAP (as DCA), and cross-chain market.
- **Code:**
  - `server/src/routes/flash.ts` maps symbols to assets and builds the `/order` draft.
  - `app/lib/evm/trade_flow.dart` (`flashBody`, `_flash`) sends the approval and the wrap, signs `evmOrderTypedData` (plus Permit2 and the attached bracket), and submits.
  - `app/lib/evm/flash_orders.dart` lists open orders with Cancel, which signs Flash's own cancel message.
  - `app/lib/wallet/flash_solana.dart`: the same orders on Solana. One setup transaction is built on the phone from Flash's instructions; Phantom signs it and the order message by deeplink, each checked with Ed25519 first.
- **Social:** a placed trade shares into the chat (`/t/<id>`), and Copy this trade opens it in a friend's Glyf (`server/src/routes/tradeshare.ts`, `app/lib/evm/trade_share.dart`).
- **Proof:** live quotes from Flash during the build. For example, 0.01 ETH stop-loss on Base returns `approveTx` to the Flash vault, `wrap.evmTx` and `evm.orderTypedData`, with a fee of about $0.04.
  - **ARPIT:** add the demo's order id and its onchain fill.

### Uniswap Foundation: "Build with Uniswap"

- Swaps on Base, Ethereum, Arbitrum, Optimism, Polygon and Unichain from the keyboard.
- **Code:** see `FEEDBACK.md`, which lists every file and line range.
- **Proof:** a live v3 quote on Base, 0.05 ETH = 111.71 USDC, shown on the keyboard. The swap calldata was simulated with a balance override.
  - **ARPIT:** add the demo swap's transaction hash.
- **Feedback:** `FEEDBACK.md`. Also send it through the form at developers.uniswap.org/hackathon-feedback.

### 0G: "Keep Building on 0G"

- **Every AI call of this build runs on 0G's Private Computer.** That covers hold-space answers, rewrites, the strip's suggestions and Build your own.
- **How it's called:** `router-api.0g.ai` with Private trust mode and `verify_tee`, on `0gm-1.0-35b-a3b-sia` (the plain 0gm build behind it, nothing outside 0G).
- **Receipts:** each answer's `x_0g_trace` (request id, provider, `tee_verified`, cost) is kept as a receipt, listed in the app under Profile › Keyboard › 0G receipts.
- **Before:** no 0G code at all; Glyf's AI ran on OpenRouter and Google. Everything 0G is new from 6 Nov.
- **Proof:** a production answer on 6 Nov came back as request `dd07c98d-8a45-4f68-8d49-b2eb551a40b9`, `tee_verified: true`, $0.000155.
- **Scope:** the builds already on TestFlight never send the 0G header and keep the usual models (`docs/DECISIONS.md` D109).

### Also built (not entered)

- **Whitechain:** `GlyfPayRequest` on Whitechain Sepolia (`contracts/`, `app/lib/evm/pay_request*.dart`, `WHITECHAIN_FEEDBACK.md`).
- **Arkiv:** the Vault's encrypted backup (`app/lib/evm/arkiv_vault.dart`, `arkiv/`), byte-for-byte with the Arkiv SDK.

> ETHGlobal allows **three partner prizes** per project: **Definitive, Uniswap and 0G**. Every form field, ready to paste, is in `docs/ETHGLOBAL-FORM.md`.

## How AI was used

Glyf is built by Arpit with an AI coding assistant, and that's true of this hackathon's work too.

- **Arpit decided** the product, the partners, the UX rules (the keyboard owns paying, the Glyf look, no extra explanation lines) and every trade-off.
- **The assistant wrote most of the code and tests** to those instructions:
  - the Swift keyboard parts, the Dart app parts, the TypeScript server routes, the Solidity contract and the Arkiv port;
  - it ran the simulator scenarios and checked the work against live Flash, Uniswap, ENS and Arkiv endpoints.
- **The plan and research** are in `docs/ETHGLOBAL-MUMBAI.md`; every decision, with Arpit's words, is in `docs/DECISIONS.md`. There are no separate spec-kit files.

## Run it

- **Server:** `cd server && npm install && npm test` (444 tests). Needs `SESSION_SECRET`, plus `MOCK_AI=true` for the AI suites.
  - `FLASH_API_KEY` enables Flash; `UNISWAP_API_KEY` switches swaps to the Trading API, otherwise on-chain v3 is used.
- **App:** `cd app && flutter test` (Dart tests, including `test/evm_test.dart` and `test/arkiv_test.dart`), then build for the iOS simulator.
  - The keyboard scenarios are `GlyfScenarioUITests/testS300_TradesInWordsOpenTheTradePanel` and `testS301_TheSwapButtonSignsInTheApp`.
- **Contracts:** `cd contracts && npm install && npm test`.
- **Arkiv reference:** `cd arkiv && npm install && node vectors.mjs`.

## The demo (2 to 4 minutes, Arpit's own voice)

The full script with timings is `docs/DEMO-SCRIPT.md`: Definitive Flash on Base and Solana, sharing a trade, a Uniswap swap, private AI on 0G, then Glyf's own calendar, search and Build your own.

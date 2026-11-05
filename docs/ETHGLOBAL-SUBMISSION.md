# Glyf at ETHGlobal Mumbai (Continuity Track)

Glyf is an AI keyboard for iPhone and Android. It's on TestFlight, and its Solana wallet (Phantom), search, calendar and AI features run in any app. At Mumbai the iPhone keyboard learned to trade on Ethereum and its L2s **from the words you type in any chat**:

- "swap 0.05 eth to usdc on base" → a Uniswap swap.
- "sell my eth if it drops below 3000", "take profit eth at 4500", "my eth: take profit 4500, stop loss 3000", "protect my eth with a 5% trail", "buy $100 of eth if it dips below 2800", "buy $20 of eth every day for a week", "move 50 usdc from base to arbitrum" → Definitive Flash advanced orders.
- "send 5 usdc to vitalik.eth" / "pay arpit.sol 5 usdc" → ENS / SNS names resolved, then a transfer.
- "request 20 usdt" → a USDT payment request on Whitechain; the pay link is typed into the chat.
- Vault › Backup → the saved details encrypted on the phone and kept on Arkiv, restorable on a new phone.

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

## Partner by partner

### Definitive (Flash): "Most Creative Use of Flash Advanced Orders"

- **Voice-or-chat trading, which Definitive's prize text names.** Every Flash order type is reachable by typing a sentence in any app:
  - stop-loss, take-profit, limit, stop buy;
  - bracket, both on a holding and attached to a market buy;
  - trailing stop, TWAP (as DCA), and cross-chain market.
- **Code:**
  - `server/src/routes/flash.ts` maps symbols to assets and builds the `/order` draft.
  - `app/lib/evm/trade_flow.dart` (`flashBody`, `_flash`) sends the approval and the wrap, signs `evmOrderTypedData` (plus Permit2 and the attached bracket), and submits.
  - `app/lib/evm/flash_orders.dart` lists open orders with Cancel.
- **Proof:** live quotes from Flash during the build. For example, 0.01 ETH stop-loss on Base returns `approveTx` to the Flash vault, `wrap.evmTx` and `evm.orderTypedData`, with a fee of about $0.04.
  - **ARPIT:** add the demo's order id and its onchain fill.

### Uniswap Foundation: "Build with Uniswap"

- Swaps on Base, Ethereum, Arbitrum, Optimism, Polygon and Unichain from the keyboard.
- **Code:** see `FEEDBACK.md`, which lists every file and line range.
- **Proof:** a live v3 quote on Base, 0.05 ETH = 111.71 USDC, shown on the keyboard. The swap calldata was simulated with a balance override.
  - **ARPIT:** add the demo swap's transaction hash.
- **Feedback:** `FEEDBACK.md`. Also send it through the form at developers.uniswap.org/hackathon-feedback.

### Whitechain: "Continuity · Bring Your Product to Whitechain"

- `GlyfPayRequest` on Whitechain Sepolia (1874): request, pay (approve or EIP-2612 permit), cancel, refund, and Receipt events. It never holds funds.
- **Code:**
  - `contracts/src/GlyfPayRequest.sol`;
  - `app/lib/evm/pay_request.dart` and `pay_request_screen.dart`;
  - the keyboard types the link into the chat (`showPayOutcomeIfFresh`).
- **Why onchain:** see `WHITECHAIN_FEEDBACK.md`.
- **ARPIT:** the deployed and verified address, and one USDT payment's explorer link (needs test WBT and test USDT, below).

### Arkiv: "Build on Arkiv (existing projects)"

- The Vault's details, shorthand and combos, AES-256-GCM-encrypted per item, as wallet-owned Arkiv entities.
  - The owner key is derived from a secret in iCloud Keychain, so a new phone finds and opens them.
  - One transaction writes what changed, deletes what was removed and extends what's near expiry.
- **Code:** `app/lib/evm/arkiv_vault.dart`, `app/lib/evm/arkiv_backup_card.dart`, and `arkiv/` (protocol, design, judge files).
- **Proof:** `app/test/arkiv_test.dart` matches the official SDK's bytes, signed transactions included. Restore queries run live on Rabdi.
  - **ARPIT:** the backup key's address (shown in the Vault) needs test GLM, then one backup's transaction.

> ETHGlobal allows **three partner prizes** per project. All four are built. Pick three at submission (see the end of `docs/ETHGLOBAL-MUMBAI.md`).

## How AI was used

Glyf is built by Arpit with an AI coding assistant, and that's true of this hackathon's work too.

- **Arpit decided** the product, the partners, the UX rules (the keyboard owns paying, the Glyf look, no extra explanation lines) and every trade-off.
- **The assistant wrote most of the code and tests** to those instructions:
  - the Swift keyboard parts, the Dart app parts, the TypeScript server routes, the Solidity contract and the Arkiv port;
  - it ran the simulator scenarios and checked the work against live Flash, Uniswap, ENS and Arkiv endpoints.
- **The plan and research** are in `docs/ETHGLOBAL-MUMBAI.md`. There are no separate spec-kit files.

## Run it

- **Server:** `cd server && npm install && npm test` (426 tests). Needs `SESSION_SECRET`, plus `MOCK_AI=true` for the AI suites.
  - `FLASH_API_KEY` enables Flash; `UNISWAP_API_KEY` switches swaps to the Trading API, otherwise on-chain v3 is used.
- **App:** `cd app && flutter test` (Dart tests, including `test/evm_test.dart` and `test/arkiv_test.dart`), then build for the iOS simulator.
  - The keyboard scenarios are `GlyfScenarioUITests/testS300_TradesInWordsOpenTheTradePanel` and `testS301_TheSwapButtonSignsInTheApp`.
- **Contracts:** `cd contracts && npm install && npm test`.
- **Arkiv reference:** `cd arkiv && npm install && node vectors.mjs`.

## The demo (2 to 4 minutes, Arpit's own voice)

1. In Messages, type "swap 0.002 eth to usdc on base". Show the chip, the Uniswap quote card, Swap, and the Basescan link.
2. Type "sell my eth if it drops below 2000". Show the Flash card, Place stop-loss, and the order under Profile › Wallet › Ethereum › Orders.
3. Type "request 5 usdt". The link lands in the chat. Open it on the second phone, Pay, and show the Receipt on the Whitechain explorer.
4. Vault › Backup › Back up. Show the Arkiv explorer, then Restore on a fresh install.

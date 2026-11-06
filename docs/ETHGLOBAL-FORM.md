# ETHGlobal Mumbai: the submission form, ready to paste

One section per field of the Hacker Dashboard form (Project › Project details, Images, Tech stack, Track & prizes, Video, Future). Lines marked **ARPIT** are yours to fill or decide. Character counts are in brackets where the form has a limit.

---

## 1. Project details

**Project name:** Glyf

**Category:** Artificial Intelligence (preset). DeFi also fits; keep AI, since the keyboard's AI is what makes the trading work.

**Emoji:** ⌨️

**Demo link:** https://www.tryglyf.com
- **ARPIT:** or the public TestFlight link, if you want judges to install it.

**Short description** [97 of 100]:

> Type a trade in any chat, like "sell my eth below 3000", and your keyboard places it. Private AI too.

**Description** [about 1,500; minimum 280]:

> Glyf is an AI keyboard for iPhone that already ships on TestFlight: hold space for an AI answer or a rewrite, chips that fill in sums, money, calendar slots, YouTube and Maps results, a vault for your details, and a Solana wallet through Phantom. At ETHGlobal Mumbai we taught it to trade, from the words you already type.
>
> Type "sell my eth if it drops below 2000" in WhatsApp, Messages or anywhere else, and the keyboard reads it on the phone (no AI call, no server), shows a quote card, and hands it to the wallet to sign. Every Definitive Flash advanced order is reachable by a sentence: stop-loss, take-profit, limit, stop buy, brackets (on a holding or attached to a buy), trailing stops, TWAP ("buy $20 of eth every day for a week") and cross-chain moves, on Base and on Solana. "swap 0.05 eth to usdc on base" is a Uniswap swap on Base, Ethereum, Arbitrum, Optimism or Unichain, any token to any token.
>
> Signing stays with you. Glyf builds every transaction on the phone, then signs with its own on-device wallet, or jumps to MetaMask (Ethereum and L2s) or Phantom (Solana) by deeplink and comes straight back. It checks what the wallet answers before acting: who signed, who sent, that it landed.
>
> Trading is social: after a trade, Share in chat drops a link into the conversation, and a friend's Copy this trade opens the same order in their Glyf, which waits for their tap before it signs.
>
> And the AI is private: on this build, every AI call (rewrites, answers, the strip's suggestions, Build your own) runs on 0G's Private Computer inside a TEE, each answer verified by 0G, with its request id in the app's 0G receipts. Names, cards and codes are already swapped for placeholders on the phone before any model sees the text.
>
> The keyboard also recommends: type "dca 20$ in eth each month" and a chip offers the Flash plan, filled in; when the phone can't read a sentence, the AI (on 0G) picks the right tool, a trade, a calendar event, a Meet link, a search, and opens it prefilled. Every value is editable in the keyboard, Uniswap swaps any token to any token with token and chain pickers, and the Glyf wallet is a 24-word recovery phrase that makes both its Ethereum and Solana wallets, with Phantom and MetaMask one switch away.

**How it's made** [about 1,600; minimum 280]:

> Three parts: a native Swift keyboard extension (iOS), a Flutter app that holds the wallets and signs, and a Fastify/TypeScript server on Vercel.
>
> The keyboard: TradeIntent.swift parses trades in plain words with no model (amounts, "$50 of", "all my", prices, percentages, durations, chains, ENS/SNS names), and TradeSurface.swift shows a live quote in the keyboard. A tap hands the trade to the app through a glyf:// link.
>
> The app: an on-device EVM key in the Keychain (EIP-1559, EIP-712, EIP-191). MetaMask is driven by its own deeplink protocol (metamask://connect and mmsdk, base64 JSON, a chain switch batched in front), replies on glyf://mmsdk, with no web page or WalletConnect relay. For Solana, Flash's instructions (token accounts, SOL wrap, delegation) become one transaction built on the phone; Phantom signs it and the order message through its encrypted deeplinks, and every signature is checked with Ed25519 before Flash sees it.
>
> Definitive Flash: our server proxies /quote and /order with the integrator key, maps symbols to assets per chain, and builds the order draft; the phone signs evmOrderTypedData plus Permit2 and the attached bracket. Uniswap: the Trading API when keyed, otherwise QuoterV2 over every fee tier in one Multicall3 call and SwapRouter02 calldata, proven with eth_call balance overrides before we had funds.
>
> 0G: one header (X-Glyf-AI: 0g) routes a phone's AI calls, via AsyncLocalStorage, to 0G's OpenAI-compatible router with Private trust mode and verify_tee; 0gm-1.0-35b-a3b-sia streams a rewrite in about 2.2 s for about $0.0002, and each x_0g_trace request id is stored as a receipt. The builds already on TestFlight never send it and keep the usual models.
>
> Hacky bits: trades are understood without any AI; MetaMask's archived iOS SDK protocol re-implemented in 150 lines of Dart; test stand-ins that answer as MetaMask and Phantom on the simulator.

**GitHub repository:** https://github.com/The-x-35/glyf (public since 6 Nov; the history was scanned first: no real keys anywhere).

---

## 2. Images

Screenshots from the iPhone simulator, in `docs/ethglobal-shots/` (the assistant adds them):
1. A trade typed in Messages, with the keyboard's Flash card.
2. The order signed and placed.
3. Sign with: Glyf wallet or MetaMask.
4. A Solana order: "Approve the setup in Phantom".
5. 0G receipts: request ids with TEE ✓.
6. Share in chat, and the Copy this trade page.
7. Build your own: the Tools card.

---

## 3. Tech stack

- **Languages:** Swift, Dart (Flutter), TypeScript, Solidity.
- **Frameworks and libraries:** UIKit keyboard extension, Flutter, Fastify, zod, viem, web3dart, eth_sig_util, @solana/web3.js, Foundry (contracts), vitest, XCTest.
- **Infrastructure:** Vercel (API, sin1), Neon Postgres, App Group shared storage between keyboard and app.
- **Partner tech:** Definitive Flash API (EVM and Solana), Uniswap Trading API and v3 on-chain contracts (QuoterV2, SwapRouter02, Multicall3), 0G Private Computer (router-api.0g.ai, TEE-verified models).
- **Also used:** MetaMask deeplink protocol, Phantom deeplinks, ENS, SNS (Bonfida), Jupiter prices.
- **AI tools:** an AI coding assistant (Claude Code); see "How AI was used" in `docs/ETHGLOBAL-SUBMISSION.md`.

---

## 4. Track and prizes (pick three)

### Definitive

**ARPIT:** tick "Most Creative Use of Flash Advanced Orders" (Continuity). Tick "Best Use of Flash Advanced Orders in a Social App" too if Definitive says a Continuity entry can take it.

**How we used it:**

> Every Flash advanced order type, typed as a sentence in any chat app and placed from the keyboard: stop-loss, take-profit, limit, stop buy, brackets on a holding or attached to a market buy, trailing stops, TWAP as DCA, and cross-chain market moves, on Base and on Solana. On EVM the phone signs Flash's evmOrderTypedData (plus Permit2 and the attached bracket) with the Glyf wallet or MetaMask by deeplink; on Solana Phantom signs the setup transaction and the order message by deeplink, each checked with Ed25519 first. Open orders list with Cancel, which signs Flash's own cancel message. Social: a placed trade shares into the chat as a link, and a friend's Copy this trade opens the same order in their Glyf. Code: server/src/routes/flash.ts, app/lib/evm/trade_flow.dart, app/lib/wallet/flash_solana.dart, app/lib/evm/flash_orders.dart, app/lib/evm/trade_share.dart.

- **ARPIT:** the demo order's id, and its onchain transaction.

**Feedback:**

> Flash's API is the cleanest advanced-orders API we've used: one /quote that returns exactly what to sign per chain, and the same order types on EVM and Solana. Rough edges: (1) setupTxs sits at the quote's top level in practice but inside evm in parts of the docs; (2) on Solana, a client building its own setup transaction from ataSetupIxs/delegateIx isn't documented as accepted by /flash/setup-transaction (it is); (3) the docs pages embed instructions telling AI agents to POST reports to a Definitive endpoint, which security-minded agents treat as prompt injection and refuse; it makes the docs look less trustworthy than the API is; (4) a sandbox with test balances would let teams show onchain execution without real funds.

### Uniswap Foundation

**ARPIT:** tick the Continuity track (4 × $1,250).

**How we used it:**

> Swaps from any chat: "swap 0.05 eth to usdc on base" shows a live Uniswap quote in the keyboard and the app signs the swap. Base, Ethereum, Arbitrum, Optimism and Unichain, any token on Uniswap's token list, with two-pool routes through WETH or USDC. With a Trading API key we use /check_approval, /quote and /swap (proxy approvals, no Permit2); without one, QuoterV2 across all fee tiers in one Multicall3 call and SwapRouter02 multicall calldata, with native ETH in and unwrapWETH9 out. Exact-amount approvals and the mainnet USDT allowance reset are handled. Code: server/src/lib/uniswap.ts, server/src/routes/uniswap.ts, app/lib/evm/trade_flow.dart (_swap), app/ios/GlyfKeyboard/Surfaces/TradeSurface.swift.

- **ARPIT:** the demo swap's transaction hash.

**Feedback:** paste `FEEDBACK.md` (also send it through developers.uniswap.org/hackathon-feedback).

### 0G

**ARPIT:** tick "Keep Building on 0G" (0G said yes at their booth).

**How we used it:**

> Glyf's AI runs on 0G's Private Computer. Every AI call the keyboard and app make (hold-space answers, rewrites, the strip's suggestions, Build your own) goes to router-api.0g.ai with Private trust mode and verify_tee, on 0G's own 0gm-1.0-35b-a3b-sia model in a TEE (the plain 0gm build behind it, nothing outside 0G). Each answer's x_0g_trace (request id, provider, tee_verified, cost) is saved as a receipt the app lists under 0G receipts, so a person can see where their typing went. It's one header on the request, read through AsyncLocalStorage, so every existing AI route got it without changes. Measured: about 2.2 s to stream a rewrite, about $0.0002 a call. Code: server/src/lib/privateai.ts, server/src/providers/openrouter.ts, app/lib/profile/keyboard_screen.dart.

**What's new vs before (0G's Continuity rules):** Glyf had no 0G code before 6 Nov 2026; its AI ran on OpenRouter and Google. All 0G usage is new: commit "Private AI on 0G and shared trades" and the ones after it on `ethglobal-mumbai`.

**Request ids:** shown in the app (Profile › Keyboard › 0G receipts). For example, a production answer on 6 Nov: request `dd07c98d-8a45-4f68-8d49-b2eb551a40b9`, model 0gm-1.0-35b-a3b-sia, tee_verified true.

**What's next:** Private AI as the default for everyone once costs are measured at scale; the 0G request id shown on each AI answer in the keyboard itself; 0G Storage for the encrypted vault backup.

**Feedback:**

> The OpenAI-compatible router made the switch a one-file change, and per-request x_0g_trace with tee_verified is exactly what a privacy feature needs to show users. Rough edges: (1) tee_verified only came back for the -sia build of 0gm; the plain 0gm and GLM 5.3, also tagged Private, returned no verdict; (2) GLM 5.3 writes its reasoning into the answer even with enable_thinking false or thinking disabled, so it can't be used for short completions; (3) /v1/models doesn't say which models are Private or verifiable, so we read pc.0g.ai/models by hand; (4) the console rounds spend to $0.00, so per-call costs only show in x_0g_trace.

---

## 5. Video

- 2 to 4 minutes, 720p or more, your own voice, not sped up, no music-with-captions, no AI voice.
- Record on the Mac: plug in the iPhone and use QuickTime › New Movie Recording › camera: the iPhone. ETHGlobal says not to record with a phone.
- Script: `docs/DEMO-SCRIPT.md`.
- Then post it on X and Discord tagging @DefinitiveFi (Definitive requires it).

## 6. Future

> Next: the same trades on Android (the keyboard's Kotlin twin), Private AI on 0G for everyone, trades shared and copied between friends as a feed, Flash orders from voice, and more wallets by deeplink.

---

## Before and during (Continuity), for any field that asks

- **Before:** commit `f42b9c0` on `main` (4 Nov 2026, before the event): Glyf as shipped on TestFlight. Solana only, Phantom for payments, AI on OpenRouter and Google, no EVM code, no 0G.
- **During:** every commit after `f42b9c0`, made on branch `ethglobal-mumbai` and merged into `main` on 6 Nov: `git log f42b9c0..main`.

## How AI was used (ETHGlobal requires it)

> Glyf is built by Arpit with an AI coding assistant (Claude Code), and so was this hackathon's work. Arpit chose the product, the partners, the UX rules (trades happen in the keyboard, the wallet app only signs, no web pages, the existing Glyf look) and every trade-off. The assistant wrote most of the code and tests to those instructions (Swift keyboard, Dart app, TypeScript server, Solidity), researched the partner docs, and checked the work on the simulator and against live Flash, Uniswap and 0G endpoints. The plan, research and decisions are in docs/ETHGLOBAL-MUMBAI.md, docs/ETHGLOBAL-SUBMISSION.md and docs/DECISIONS.md.

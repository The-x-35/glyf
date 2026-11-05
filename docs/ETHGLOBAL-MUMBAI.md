# ETHGlobal Mumbai (5 to 7 Nov 2026)

Glyf enters the **Continuity Track** (already selected on the ETHGlobal project page). This branch, `ethglobal-mumbai`, holds every hackathon change, so `main` (which deploys api.tryglyf.com and the site) is untouched.

- **Starting point (prior state):** commit `f42b9c0` on `main`, 4 Nov 2026 17:48 IST. Everything after it on this branch is hackathon work.
- **Deadline:** Saturday 7 Nov 2026, 09:00 IST, on the Hacker Dashboard.
- **Partner prizes:** at most **3 partners** per project. All of one partner's tracks count as one pick.
- **Continuity entries** only compete for the prizes marked "only available to Continuity Track participants" (plus the Top 10 finalist round, if chosen).
- **Video:** 2 to 4 minutes, at least 720p, not sped up, no text-to-speech or AI voice.
- **Repo:** has to be public and keep a steady commit history. One big upload on the last day is marked down by 1inch and Whitechain, and by ETHGlobal itself.
- **AI use:** the README has to say where and how AI tools were used, and include any spec or planning files.

## Every partner, and what a continuity entry can get

| Partner | Continuity prize | What it asks for | Fit for Glyf |
|---|---|---|---|
| **Definitive (Flash)** | Most Creative Use of Flash Advanced Orders, $2,500 | A working trading flow on Flash advanced orders (limit, stop, stop-loss, take-profit, TWAP, bracket, trailing stop) with onchain execution in the demo. Short video posted on X and Discord tagging @DefinitiveFi. Their examples include "voice or chat interfaces for trading". | **Best fit.** Type or say "sell my ETH if it drops below 3,000" in any app and the keyboard places a Flash stop-loss. Flash supports Solana too, so the existing Phantom wallet can sign Solana orders today. |
| **Uniswap Foundation** | Build with Uniswap, $5,000 (four equal $1,250 places) | Any Uniswap stack integration (Trading API, v2/v3/v4). Public repo, `FEEDBACK.md`, and the Uniswap developer feedback form. README must point at the integration lines. | **Strong fit.** "swap 0.05 ETH to USDC on Base" from the keyboard, quoted by the Uniswap Trading API and signed in the user's wallet. Four equal places are the best odds on the board. |
| **World** | Agent Pass, $2,500, plus [Cont] Best Use of IDKit, $2,500 (one pick covers both) | A meaningful action that needs a fresh human check, with the result validated on our server. The demo must also show a refused or expired path where the action doesn't happen. | **Good fit.** When Glyf's AI is about to move money (a swap, an order, a payment over a limit), it asks for a fresh World ID check first, validated on our server. |
| **ENS** | Best Integration of ENSv2 into an Existing Project, $3,000 | ENSv2 on mainnet, central to the product, not cosmetic. Live demo, open source. | **Medium.** "pay arpit.eth 20 USDC" resolves in the keyboard. Plain resolution is "a library update" by ENS's own docs, so to place it would need ENSv2 subnames for Glyf users (for example `arpit.glyfapp.eth`). That needs a .eth name on mainnet, which you would buy. |
| **Arkiv** | Build on Arkiv (existing projects), $4,000, plus Arkiv + Swarm bonus, $500 | Move part of the product's data to Arkiv testnet, with a user-visible feature that reads it back. Five judging files under `/arkiv/`. | **Medium.** Vault items encrypted on the phone and stored as wallet-owned Arkiv entities, which a second phone restores. Testnet only, so no spending. The written part is heavy. |
| **Whitechain** | Continuity: Bring Your Product to Whitechain, $3,000 | A contract deployed and verified on Whitechain Sepolia (chain id 1874), a real USDT payment in the main flow, `WHITECHAIN_FEEDBACK.md`, and a before-and-during section. | **Low-medium.** USDT pay-from-keyboard on Whitechain. Needs a contract of our own, and a plain transfer button "won't place". |
| **0G** | Keep Building on 0G, up to 2 × $1,500 | 0G in the new work (a 0G Compute request id, Storage root or Chain contract), a dated changelog, and "what's next". | **Cheap.** 0G Private Computer is OpenAI-compatible, so one Glyf AI step (for example the trade-intent parser) could run there. The prize wording leans toward projects that already use 0G. |
| **Arc (Circle)** | Continuity: Bring Your Project to Arc, $3,000 | Must start in Arc Studio, with a shareable Studio project URL and a frontend plus backend plus diagram. | **Low.** Arc Studio builds web apps, and Glyf is a native keyboard. Flash already lists `arc` as a chain if we want it for free. |
| **Ethereum Foundation** | Best CROPS Upgrade to an Existing Project, $1,500 | One new censorship-resistance, open-source, privacy or security property, with a CROPS section in the README and a before-and-after video. | **Low-medium.** Wallet balance reads through Anon-RPC, for example. Small prize. |
| **Hedera** | Built on Hedera (Continuity), 2 × $750 | The project must already exist on Hedera. | **Not eligible.** Glyf has never been on Hedera. |
| **1inch** | Build an Aqua App, Continuity, $2,000 | A DeFi position built on Aqua/SwapVM contracts. | **Not a fit.** That's a protocol build, not a keyboard. |
| **Chainlink** | none for continuity | CCIP inside our own contracts. | **Not eligible.** |

## Recommended picks (3)

1. **Definitive:** the best fit, they already like Glyf, and natural-language trading is the thing they asked for.
2. **Uniswap:** four equal places, and swaps on Ethereum and the L2s are the core of "Glyf on Ethereum".
3. **World:** two continuity prizes from one pick, and the human check before money moves is a real product feature, not a login screen.

ENS and SNS name resolution ("pay arpit.eth", "pay arpit.sol") gets built anyway, because both Definitive and Uniswap demos need it. It just isn't one of the three picks. Arkiv is the swap-in if World's integration turns out to fight a native app.

## What gets built (shared pieces first)

1. **Ethereum wallet in the app.** Connect an EVM wallet (MetaMask, Rainbow, Phantom EVM, and others) for Ethereum, Base, Arbitrum and Optimism. The wallet signs; Glyf holds no keys, the same rule as Phantom today. This needs WalletConnect (Reown) and a free Reown project id. Waiting on Arpit's OK, since it's a new provider.
2. **Names.** `.eth` through ENS (Universal Resolver, chain-specific addresses) and `.sol` through SNS, both on the server, answered in the keyboard as a chip: "arpit.eth → 0x12…ab".
3. **Intent parser.** Phrases like "swap 0.05 eth to usdc on base", "sell my eth if it drops below 3000", "take profit at 4500" and "buy $20 of eth over a day" are turned into a structured order and shown as a confirm card. Nothing moves without the wallet's signature.
4. **Uniswap swap.** Trading API `/quote`, then `/swap` (plus an approval or Permit2 when needed), then the wallet sends.
5. **Flash orders.** `/quote` returns the payload to sign: EIP-712 on EVM, an Ed25519 message on Solana through Phantom. Then `/order`, and `/orders` is polled. The result comes back to the keyboard as a toast. DCA isn't a Flash order type, so "every day" becomes a TWAP over the period.
6. **World ID check.** Before an AI-built order or payment over a set amount, IDKit runs and our server validates the proof. The demo shows both an approved and a refused path.
7. **Submission files.** README "before and during" section, `FEEDBACK.md` (Uniswap), the Flash and World integration notes, the AI-use section, and the demo video. Arpit records the video in his own voice.

## Keyboard ideas beyond the brief

- **Paste or type an address** and the chip names it: an ENS or SNS name if it has one, and a warning if you've never paid it before.
- **Request money:** "request 20 usdc" makes a payment link and QR (an EIP-681 link on Ethereum, a Solana Pay link on Solana).
- **Bracket in one line:** "buy 0.1 eth, take profit 4500, stop 3000" becomes Flash's attached bracket on a market order.
- **Trailing stop:** "protect my eth with a 5% trail".
- **Cheapest chain:** "send 10 usdc to arpit.eth" picks whichever L2 the recipient already has funds on.
- **Cross-chain:** "move 50 usdc from base to arbitrum" uses Flash's cross-chain market order.
- **Explain a transaction:** paste a tx hash and the chip says what it did.
- **Share a trade:** after a fill, "share" writes a short trade card into the chat. This is the social angle for Definitive's other track, if continuity entries turn out to be allowed there.

## Owed by Arpit

- **Partner picks:** confirm the three, or change them.
- **Public repo:** ETHGlobal needs one, and `The-x-35/glyf` is private. Pick one:
  - make it public (the history was scrubbed on 16 Sep, but `.env`-style files still need a check first), or
  - publish only this branch's new code as a public repo.
- **Keys:** a Flash API key (Definitive), a Uniswap API key (developers.uniswap.org), a World developer-portal app id, and a Reown project id if WalletConnect is OK.
- **Funds for the demo:** a few dollars on Base (and SOL for the Solana Flash order) in your own wallet. Flash and Uniswap execute on mainnet, and you sign every transaction.

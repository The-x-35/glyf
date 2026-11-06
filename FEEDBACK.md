# Uniswap developer feedback (Glyf, ETHGlobal Mumbai)

Glyf is an AI keyboard for iPhone. At Mumbai it learned to swap on Ethereum and its L2s from any chat. You type "swap 0.05 eth to usdc on base", the keyboard shows Uniswap's quote, and the app signs the swap with the on-phone Glyf wallet.

## Where Uniswap is in the code

- `server/src/lib/uniswap.ts` holds both routes.
  - **Trading API route**: `/check_approval`, `/quote`, `/swap` with `x-permit2-disabled: true`. It is used when a `UNISWAP_API_KEY` is set.
  - **On-chain v3 fallback**: QuoterV2 over fee tiers 100/500/3000/10000 in one Multicall3 call, then SwapRouter02 `multicall(deadline, [...])`. Native ETH in goes as `value`. ETH out swaps to the router and calls `unwrapWETH9`.
  - The deployment addresses come from Uniswap's `deployments.json` and are cited in the file.
- `server/src/routes/uniswap.ts`: `POST /uniswap/quote` and `POST /uniswap/swap`, which return plain transactions, an exact-amount approval, and an allowance reset for mainnet USDT.
- `app/lib/evm/trade_flow.dart` (`_swap`): sends the allowance reset, then the approval, then the swap, and waits for each receipt.
- `app/ios/GlyfKeyboard/Surfaces/TradeSurface.swift`: the keyboard's live quote card, styled like Glyf's Solana Buy panel.
- `app/ios/GlyfKeyboard/Engine/TradeIntent.swift`: reads the words; 19 unit tests in `app/ios/RunnerTests/TradeIntentTests.swift`.

## What worked

- QuoterV2 through `eth_call` worked first time on all seven chains we tried. Simulating a swap with an `eth_call` balance override let us prove the calldata before any funds existed.
- `deployments.json` is the single most useful file: one place for every address on every chain.
- The proxy-approval mode (`x-permit2-disabled`) suits a keyboard. An on-device EOA can send a plain approve and a plain swap without carrying Permit2 signatures between the keyboard and the app.

## Where we got stuck

- **API keys.** The Trading API needs a key, and getting one isn't instant self-serve for a hackathon team at 2 am, so we built the v3 fallback first. A rate-limited, keyless sandbox key for hackathons would have saved hours.
- **Multi-hop pairs.** On-chain v3 quoting is pool by pool, so a pair without a direct pool returns nothing. We wrote our own two-pool routing through WETH or USDC (QuoterV2's path quote), but multi-hop routing is exactly what the API is for. A documented, keyless way to route multi-hop on-chain (even just a recommended list of hub tokens per chain) would help mobile builders.
- **Sources disagree.** The docs and third-party guides disagree on the Trading API host (`trade-api.gateway.uniswap.org` vs `trade.api.uniswap.org`) and on how keys are issued.
- **UniswapX minimum.** Its 300 USDC minimum isn't on the quote page we read first, and keyboard-sized swaps are far below it.

## The one change with the biggest impact

A free hackathon tier of the Trading API with no approval step, and the host named in one canonical place.

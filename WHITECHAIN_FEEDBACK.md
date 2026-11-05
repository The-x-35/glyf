# Whitechain feedback (Glyf, ETHGlobal Mumbai)

At Mumbai, Glyf (an AI keyboard for iPhone) gained USDT requests on Whitechain. You type "request 20 usdt" in any chat. The Glyf wallet creates a `GlyfPayRequest` on Whitechain Sepolia, and the keyboard types the pay link into the chat. The other person opens it and pays it, and the contract emits a receipt both sides can check.

## Why onchain stablecoin settlement

The request and its receipt are public state that nobody has to host. The payee's keyboard and the payer's phone read the same `getRequest(id)`, so an edited link can't change what's paid. Refunds go back to whoever paid. A card rail or a bank transfer can't give two strangers in a chat that shared, checkable record without an intermediary holding the money.

## What worked

- Plain EVM and OP Stack: viem, Hardhat and Blockscout verification all worked unchanged.
- The test USDT (`0xcedf…55a7`, TetherTokenV2) supports EIP-2612 `permit`, with domain `{"Tether USD", "1", 1874}`, and EIP-3009. That makes a one-signature pay flow possible.

## Where we got stuck

- **Two test USDT contracts.** The prize text names `0xcedfB56113143d55b2358b8CFbB0dEB5Ad2f55a7`. Whitechain's own token list for chain 1874 has `0xaa7962d073935D387e8d442DA1D7149C81388f46`, which reports itself as `USDT.e`.
- **No way to get test USDT.** Minting is owner-only, and the docs don't say how a builder gets test USDT. We had to ask at the booth.
- **The faucet needs a GitHub sign-in and a captcha.** An agent-driven or CI workflow can't fund a fresh deployer.
- **Permit and EIP-3009 support aren't documented.** Both matter most for wallet-less, one-tap payments.
- **Forking Whitechain Sepolia in Hardhat 3** fails with "No known hardfork for execution on historical block" until you add `chainDescriptors: {1874: {hardforkHistory: {prague: {blockNumber: 0}}}}`. A ready snippet in the docs would save time.

## What the docs were missing

- A "get test stablecoins" section.
- The explorer's verification API (Blockscout v2 standard input).
- A note on which USDT address is canonical for each network.

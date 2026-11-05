# ETHGlobal Mumbai: onchain pieces (status, 6 Nov 2026)

Two new folders on `ethglobal-mumbai`: `contracts/` (Whitechain) and `arkiv/` (Arkiv). Nothing in `app/` or `server/` was touched; wiring them into the app is separate work.

## Whitechain: `contracts/`

- `GlyfPayRequest.sol`: payment requests with onchain receipts. Create (token, amount, memo ≤ 140 bytes, optional named payer, optional expiry), pay with approve or EIP-2612 permit, cancel, full or partial refund. Never holds funds, no owner, no upgrades. Details and the ABI the app needs: `contracts/README.md`.
- Tests: `npm test` (13 tests on an in-process Hardhat chain, including a USDT mock that returns no bool and a reentrant token) and `npm run test:fork` (the real test USDT on a local fork of Whitechain Sepolia: approve + pay, permit + pay, refund). All pass.
- Not deployed yet: the throwaway deployer `0x2a1cB3CDA2d72e02d4BaF04C809145c0869975D7` needs test WBT from https://faucet.testnet.whitechain.io (GitHub sign-in, captcha, 0.5 WBT a day; the deploy costs about 0.006 WBT). Then `npm run deploy` deploys, writes `contracts/deployments/whitechain-sepolia.json` and verifies on Blockscout.
- Request link: `glyf://pay-request?chain=1874&contract=0x…&id=…`, web fallback `https://www.tryglyf.com/pay?…` (the `/pay` page isn't built).

Notes for `WHITECHAIN_FEEDBACK.md` (from this work):
- Two "test USDT" contracts: the prize text names `0xcedfB56113143d55b2358b8CFbB0dEB5Ad2f55a7` (TetherTokenV2, `name()` "Tether USD"), while Whitechain's own token list for chain 1874 has USDT at `0xaa7962d073935D387e8d442DA1D7149C81388f46`, whose contract reports `USDT.e`. The docs don't say how a builder gets either one on testnet (mint is owner-only). Ask the Whitechain booth for test USDT for the demo wallets.
- The test USDT supports EIP-2612 permit with domain `{name: "Tether USD", version: "1", chainId: 1874}` and EIP-3009 `transferWithAuthorization`; neither is mentioned in the docs, and both matter for one-tap payments.
- Forking Whitechain Sepolia in Hardhat 3 fails until you add a chain descriptor (`chainDescriptors: {1874: {hardforkHistory: {prague: {blockNumber: 0}}}}`): "No known hardfork for execution on historical block". A ready config snippet in the Hardhat docs page would help.
- Verification: Blockscout at `https://explorer.testnet.whitechain.io/api/` (Foundry) and `/api/v2/smart-contracts/{address}/verification/via/standard-input`; it supports solc `v0.8.30+commit.73712a01` and EVM `prague`.

## Arkiv: `arkiv/`

- Vault items encrypted on the phone (AES-256-GCM), one entity each, owned by a key derived from a 32-byte secret in iCloud Keychain, restored on a second phone by querying the owner. `arkiv/DESIGN.md`.
- `arkiv/PROTOCOL.md`: Arkiv 1.0 writes are a plain EIP-1559 call of `execute((uint8,bytes)[])` on `0x44…44` with ABI calldata (no RLP, no compression); reads are `arkiv_query` / `arkiv_getEntity`.
- `node vectors.mjs`: our hand-rolled encoding and the official SDK produce identical signed transactions for create, patch, extend, delete and a 2-item batch.
- `node ref.mjs`: checked on the live Rabdi node with no funds (create → patch → extend → delete in one `eth_estimateGas`; restore queries run). The write steps wait for tGLM on the throwaway owner `0x76C58702b86004Aa820F58Ed5F1130Aa34B7E6F8` (https://hub.arkiv.network/faucet).
- Judging files drafted: `arkiv/schema.md`, `friction.md`, `reach.md`, `why-arkiv.md`, `how-you-use-arkiv.md`. Marked **ARPIT** where his numbers or decisions go.
- Arkiv is still "ruled out" in the picks above (at most 3 partners). These files only matter if it replaces one.

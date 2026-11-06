# GlyfPayRequest (Whitechain Sepolia)

USDT payment requests from the keyboard, settled onchain with a receipt.

"request 20 usdt for dinner" in a chat makes a request onchain and inserts a link. The other person taps it, their own wallet pays it, and both keyboards show the receipt. The contract never holds money: `pay` moves USDT straight from the payer to the payee, and `refund` moves it straight back.

- Contract: [`src/GlyfPayRequest.sol`](src/GlyfPayRequest.sol) (Solidity 0.8.30, optimizer 200 runs, EVM `prague`, no imports)
- ABI: [`abi/GlyfPayRequest.json`](abi/GlyfPayRequest.json)
- Deployment record (after deploy): `deployments/whitechain-sepolia.json`
- Network: Whitechain Sepolia, chain id `1874`, RPC `https://rpc.testnet.whitechain.io`, explorer `https://explorer.testnet.whitechain.io`
- Test USDT: `0xcedfB56113143d55b2358b8CFbB0dEB5Ad2f55a7` (TetherTokenV2 behind an EIP-1967 proxy, 6 decimals, EIP-2612 `permit` with domain `{name: "Tether USD", version: "1", chainId: 1874, verifyingContract: <token>}`, also EIP-3009)

## Design

| Rule | How |
|---|---|
| Requests are immutable | Token, amount, payee, named payer, expiry and memo are fixed at creation, so a payer can't be front-run into paying something else. |
| No custody | `pay` is `transferFrom(payer → payee)`, `refund` is `transferFrom(payee → payer)`. The contract's balance is always zero. |
| Only the caller's own money | `pay` always pulls from `msg.sender`, `refund` always from the payee (`msg.sender`). There is no "pay from someone else". |
| USDT-safe | Low-level `transferFrom`; accepts empty return data (old USDT) or `true`; rejects `false`, short return data, reverts, and addresses with no code. |
| Checks-effects-interactions | Status is written before the token call; events after. |
| Reentrancy | A single lock on `pay`, `payWithPermit` and `refund` (the only functions that call out). |
| Permit can't be griefed | `payWithPermit` wraps `permit` in `try/catch`: if someone submits the signature first, the allowance is already there and the payment still goes through. |
| No owner, no upgrade, no fee | Nothing to administer. |
| Not supported | Fee-on-transfer or rebasing tokens (the receipt records the requested amount). |

Status: `0 None`, `1 Open`, `2 Paid`, `3 Cancelled`, `4 Refunded` (refunded in full; a partial refund stays `Paid` with `refunded > 0`).

## Run the tests

```bash
cd contracts
npm install
npm test            # compile with npm solc 0.8.30, then 13 tests on an in-process Hardhat (EDR) chain via viem
npm run test:fork   # same contract against the REAL test USDT on an in-process fork of Whitechain Sepolia
```

`npm test` uses `test/mocks/Mocks.sol`: a USDT that returns **no bool** from `approve`/`transfer`/`transferFrom` (and has EIP-2612 permit), a token that returns `false`, one that returns 1 byte, and one that re-enters from inside `transferFrom`. Covered: approve + pay, Receipt fields, no double pay, create validation, named payer, payee can't pay itself, expiry, missing allowance/balance leaves the request open, cancel rules, partial and full refunds and over-refund, permit pay, front-run permit, bad permit, false/short returns, reentrancy on `pay` and `refund`.

`npm run test:fork` reads the chain over the public RPC but sends nothing to it: it forks locally, impersonates a USDT holder on the fork to fund a test account, then runs approve + pay, `payWithPermit` (checking the token's `DOMAIN_SEPARATOR` equals `{ "Tether USD", "1", 1874, token }`) and a partial refund. Gas on the real token: `pay` about 132k, `payWithPermit` about 137k (both including the first-time storage writes).

## Deploy and verify

```bash
cd contracts
npm run keygen      # once: fresh throwaway key in .deployer.key (chmod 600, gitignored), address in .deployer-address
npm run status      # deployer balance and the deploy cost (about 1.14M gas, about 0.006 WBT at 5 gwei)
npm run deploy      # build, deploy, write deployments/whitechain-sepolia.json, verify on the explorer
npm run verify      # verify again later (or: npm run verify -- 0xADDRESS)
```

Fund the deployer address first at <https://faucet.testnet.whitechain.io> (GitHub sign-in, 0.5 WBT per 24 h). The key is never printed.

Verification goes to Whitechain's Blockscout with the exact standard JSON input `scripts/build.mjs` compiled (`out/GlyfPayRequest.input.json`, compiler `v0.8.30+commit.73712a01`): first `POST /api/v2/smart-contracts/{address}/verification/via/standard-input`, then, if it isn't verified after a minute, the Etherscan-compatible `POST /api?module=contract&action=verifysourcecode` (the one `forge verify-contract --verifier blockscout --verifier-url https://explorer.testnet.whitechain.io/api/` uses). The script polls `GET /api/v2/smart-contracts/{address}` until `is_verified`.

Try it after deploying (the deployer is the payee):

```bash
node scripts/cli.mjs create 20 "dinner"          # prints the request id and both links
node scripts/cli.mjs create 5 "cab" 0xPAYER 24   # only 0xPAYER may pay, for 24 hours
node scripts/cli.mjs show 1
```

## What the phone app needs

All calls go to the deployed address on chain 1874. Amounts are USDT base units (6 decimals: 20 USDT = `20000000`).

### Functions

| Selector | Function | Who |
|---|---|---|
| `0xdd0bacc1` | `createRequest(address token, uint256 amount, string memo, address payer, uint64 expiresAt) returns (uint256 requestId)` | payee. `payer = 0x0` means anyone; `expiresAt = 0` means never; memo ≤ 140 bytes UTF-8 |
| `0xc290d691` | `pay(uint256 requestId)` | payer, after `USDT.approve(contract, amount)` |
| `0xee241fd5` | `payWithPermit(uint256 requestId, uint256 deadline, uint8 v, bytes32 r, bytes32 s)` | payer, one transaction: sign an EIP-2612 `Permit{owner: payer, spender: contract, value: amount, nonce: USDT.nonces(payer), deadline}` |
| `0x40e58ee5` | `cancel(uint256 requestId)` | payee, while Open |
| `0x5af36e3e` | `refund(uint256 requestId, uint256 amount)` | payee, after `USDT.approve(contract, amount)`; goes to whoever paid |
| `0xc58343ef` | `getRequest(uint256 requestId) view returns (Request)` | anyone |
| `0xa2811f1b` | `canPay(uint256 requestId, address who) view returns (bool)` | anyone (ignores balance/allowance) |
| `0x5badbe4c` | `requestCount() view returns (uint256)` | anyone |
| `0x88ba1c20` | `MAX_MEMO_BYTES() view returns (uint256)` | 140 |

`Request` is returned as one dynamic tuple (it holds a string), in this order:
`(address token, uint64 expiresAt, uint8 status, address payee, uint64 createdAt, address payer, uint64 paidAt, address paidBy, uint256 amount, uint256 refunded, string memo)`.

Permit vs approve: with `payWithPermit` the wallet shows one signature (typed data) plus one transaction, instead of two transactions. Use it when the wallet supports `eth_signTypedData_v4`; fall back to approve + pay otherwise. Whether the payer already has enough allowance can be read with `USDT.allowance(payer, contract)`.

### Events (topic0)

| topic0 | Event (indexed fields first three after the name) |
|---|---|
| `0xd988cc93adff19f054abec3efa515e5ea9b6f67c969949885793ca43d89639b3` | `RequestCreated(uint256 indexed requestId, address indexed payee, address indexed payer, address token, uint256 amount, uint64 expiresAt, string memo)` |
| `0xa8d5b711a6274f37116b478a9f049bbb500c5b61104acd5f4a6b687c393e7f29` | `Receipt(uint256 indexed requestId, address indexed payer, address indexed payee, address token, uint256 amount, string memo, uint256 timestamp)` |
| `0xe0d7665e06e7db1fc500d66d4e3898d1d4a5533d7efe54b352fcdaa177c22783` | `RequestCancelled(uint256 indexed requestId, address indexed payee)` |
| `0x3d83841932e824726c32c3fd876e971fad7179cb54f9b1e12ff00bc340ac29fd` | `Refunded(uint256 indexed requestId, address indexed payer, address indexed payee, address token, uint256 amount, uint256 totalRefunded, uint256 timestamp)` |

The request id of a new request is topic1 of the `RequestCreated` log in the `createRequest` receipt. To show "paid" on the payee's keyboard, poll `getRequest(id).status` or `eth_getLogs` with `topics: [Receipt topic0, id as 32 bytes]` (or `[Receipt, null, null, payee]` for every receipt to one person).

### Errors (4-byte selectors, for friendly messages)

`ZeroAmount 0x1f2a2005`, `NotAToken 0x851f69d0`, `MemoTooLong 0x3fd3f150`, `AlreadyExpired 0xa0d64f8a`, `PayerIsPayee 0xc319c677`, `UnknownRequest 0x6d080297`, `NotOpen 0xddafad98` (already paid or cancelled), `Expired 0x203d82d8`, `NotNamedPayer 0x48788980`, `NotPayee 0x56cab67b`, `NotPaid 0x34e4a710`, `RefundTooLarge 0x020123b0`, `TokenTransferFailed 0x045c4b02` (balance or allowance too low), `Reentrancy 0xab143c06`.

Regenerate these tables with `node scripts/selectors.mjs`.

## Request link format

```
glyf://pay-request?chain=1874&contract=0xCONTRACT&id=42
https://www.tryglyf.com/pay?chain=1874&contract=0xCONTRACT&id=42
```

- `chain` decimal chain id (1874), `contract` the GlyfPayRequest address (checksummed), `id` decimal request id.
- The link carries nothing else on purpose. The app reads amount, token, payee, named payer, expiry, memo and status from `getRequest(id)` and shows those, so an edited link can't change what is paid. The app should also only accept a `contract` it knows (the address in `deployments/whitechain-sepolia.json`) and show the token's symbol from the token, not from the link.
- The https form is for people without Glyf: it opens the app through a universal / app link when installed, and otherwise the site can show the request and a "pay with your wallet" page. That `/pay` page is not built here.

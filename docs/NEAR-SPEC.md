# Glyf × NEAR: build spec (NEAR Hackathon, 1–14 Nov 2026)

Internal contract for the NEAR work. Every part (server, iPhone keyboard,
app, Android keyboard) builds to this file. The public write-up is docs/NEAR.md.

Deadline: development ends 14 Nov 2026 23:59 UTC. Baseline tag `near-baseline`
(40a04ae); everything after it on `near-hackathon` is the NEAR work.

## What the person does

They type in any chat and the strip's chip offers the trade. A tap opens the
trade panel, which shows a live NEAR Intents quote. The button hands off to the
Glyf app, which asks MetaMask (EVM chains) or Phantom (Solana) to send the
deposit, then follows the swap until it lands.

| Typed | Kind | Route |
|---|---|---|
| `swap 20 usdc on base to sol` | swap, Base → Solana | NEAR Intents |
| `swap 0.2 sol to usdc on base` | swap, Solana → Base | NEAR Intents |
| `swap 50 usdc on arbitrum to btc to bc1q…` | swap to Bitcoin, to a typed address | NEAR Intents |
| `swap 20 usdc on base to near` / `… to zec` | swap to NEAR or Zcash, recipient needed | NEAR Intents |
| `move 50 usdc from base to solana` | the same coin across chains | NEAR Intents |
| `send 5 usdc to alice.near` | pay a NEAR account exactly 5 USDC (EXACT_OUTPUT), paid from Base USDC | NEAR Intents |
| `send 0.001 btc to bc1q…` | pay a Bitcoin address exactly, paid from Base USDC | NEAR Intents |
| `pay bob.near 10 usdc with sol` | pay from SOL on Solana | NEAR Intents |

Rules:
- **Uniswap, Jupiter and Flash keep everything they already do.** That covers
  same-chain swaps, EVM↔EVM cross-chain swaps through Uniswap's BRIDGE route,
  Flash orders and moves between EVM chains, and .eth/.sol sends.
- **NEAR Intents takes any trade that touches a chain the others can't
  reach.** That means Solana on one side and an EVM chain on the other, or
  Bitcoin, Zcash, NEAR, TON, Tron, XRP, Dogecoin, Litecoin, Sui, Aptos, Stellar
  or Cardano anywhere.
- **It also takes every send to a .near name, a NEAR implicit account (64 hex
  characters), a Bitcoin address or a Zcash t-address.**
- **Venue word** on the chip and panel: "NEAR Intents".
- **Who signs.** Glyf can only deposit from EVM chains (MetaMask) and Solana
  (Phantom). For any other origin chain (e.g. `swap 0.01 btc to usdc on base`),
  the app shows the deposit address and the exact amount with Copy and a QR
  code ("Send from any wallet"), then tracks the deposit.
- **Default pay-from for sends:** USDC on Base. `with sol` / `with eth` /
  `from solana` / `with usdc on arbitrum` change it.
- **Default recipient for swaps:** the person's own wallet on the destination
  chain (the MetaMask address for EVM, the Phantom address for Solana). NEAR,
  Bitcoin, Zcash and other chains need a typed `to <address|name.near>`, or the
  saved setting `nearAccount` for NEAR. When neither exists, the panel asks for
  one.
- **Refunds** go to the person's own address on the origin chain
  (`refundType: ORIGIN_CHAIN`).

## Chains (Glyf name → 1Click `blockchain`)

| Glyf | 1Click | Glyf | 1Click |
|---|---|---|---|
| base | base | solana | sol |
| ethereum | eth | near | near |
| arbitrum | arb | bitcoin | btc |
| optimism | op | zcash | zec |
| polygon | pol | ton | ton |
| bsc | bsc | tron | tron |
| avalanche | avax | xrp | xrp |
| gnosis | gnosis | dogecoin | doge |
| | | litecoin | ltc |
| | | sui | sui |
| | | aptos | aptos |
| | | stellar | stellar |
| | | cardano | cardano |

Words for chains: "on bitcoin", "on btc" (as a chain) etc. Native coins:
BTC→bitcoin, ZEC→zcash, NEAR→near, TON→ton, TRX→tron, XRP→xrp, DOGE→dogecoin,
LTC→litecoin, SUI→sui, APT→aptos, XLM→stellar, ADA→cardano, SOL→solana.

Today "btc" means WBTC on Base for Uniswap. A swap that says `to btc` where
the other side is Solana, or that names `on bitcoin`, or that sends to a
Bitcoin address, means native BTC through NEAR Intents.

## Server API (server/src/routes/near.ts, lib/nearintents.ts)

Base: the Glyf API (https://api.tryglyf.com). Session-gated like every route.
1Click is called keyless at https://1click.chaindefuser.com, with
`referral: "glyf"`. If `NEAR_INTENTS_JWT` is set, it is sent as Bearer, which
removes 1Click's 0.2% keyless fee.

### POST /near/quote
Request:
```json
{
  "sell": "USDC", "sellChain": "base",
  "buy": "SOL", "buyChain": "solana",
  "amount": "20",
  "exact": "in",
  "refundTo": "0x…",
  "recipient": "7xKX…",
  "slippage": 1,
  "recent": ["0x…", "alice.near"],
  "dailyLimitUsd": 200, "spentTodayUsd": 40
}
```
- `amount` is in whole coins: of `sell` when `exact: "in"`, of `buy` when
  `exact: "out"` (sends).
- Without `refundTo` or `recipient`, the quote is a dry one (no deposit
  address): the keyboard panel's preview.
- `slippage` is in percent. The default is 1.
- `recent` lists earlier recipients the phone remembers, so Guard can catch
  poisoning. `dailyLimitUsd` and `spentTodayUsd` are optional.

Response (`ok: true`):
```json
{
  "ok": true, "dry": false, "venue": "NEAR Intents",
  "sell": {"symbol":"USDC","chain":"base","decimals":6,"assetId":"nep141:base-0x8335….omft.near","address":"0x8335…"},
  "buy":  {"symbol":"SOL","chain":"solana","decimals":9,"assetId":"nep141:sol.omft.near","address":null},
  "amountIn": "20", "amountInBase": "20000000", "amountInUsd": "19.99",
  "amountOut": "0.2438", "amountOutBase": "243803197", "amountOutUsd": "19.88",
  "minAmountOut": "0.2413",
  "timeSeconds": 32,
  "depositAddress": "0x7899…", "depositMemo": null, "deadline": "2026-11-15T18:34:40Z",
  "deposit": {"kind":"erc20","chain":"base","chainId":8453,"to":"0x8335…","data":"0xa9059cbb…","value":"0","amountBase":"20000000","token":"0x8335…","depositAddress":"0x7899…"},
  "explorer": "https://explorer.near-intents.org/transactions/0x7899…",
  "guard": {"level":"ok|warn|block","checks":[{"id":"lookalike","level":"block","text":"Looks like 0xAb12…9fE0 you paid before, but it isn't"}]}
}
```
`deposit.kind` is one of:
- `erc20`: a plain EVM tx `{to: token, data: transfer(depositAddress, amount), value:"0"}`.
- `native`: `{to: depositAddress, value: amount, data:"0x"}`, with `chainId`.
- `sol`: a native SOL transfer, `{to: depositAddress, lamports}`.
- `spl`: `{to: depositAddress, mint, amountBase, decimals}`.
- `manual`: any other chain; show the address, amount and memo.

Failures look like `{ok:false, error:"Plain words for the person"}`, sent
with 400 or 502 (for example, below the minimum swap size: "Too small for
NEAR Intents: at least $X").

### GET /near/status?deposit=<depositAddress>[&memo=]
Returns `{ok, status: "PENDING_DEPOSIT|INCOMPLETE_DEPOSIT|PROCESSING|SUCCESS|REFUNDED|FAILED", done: bool, amountOut?, destinationTx?: {hash, url}, originTx?: {hash,url}, explorer}`.

### POST /near/submit `{depositAddress, txHash, memo?}`
Tells 1Click about the deposit tx, which speeds up pickup. Returns `{ok}`.

### GET /names/resolve?name=alice.near
This adds `.near` (and NEAR implicit 64-hex accounts) to the existing route.
It checks the account through NEAR RPC `view_account`
(https://rpc.mainnet.near.org, or `NEAR_RPC_URL`). The answer keeps the
existing shape plus `{chain: "near", address: "alice.near", exists: true}`.
An unknown name gives `exists: false`, and the keyboard says "No NEAR account
alice.near".

### Guard (lib/nearguard.ts), for the AI Security track
Every live quote with a recipient runs these checks. A `block` check stops
the panel's button until the person taps "Send anyway".
- **lookalike** (block): the recipient shares its first 4 and last 4
  characters with a `recent` address but isn't that address (address
  poisoning).
- **no-account** (block): a .near recipient that doesn't exist on NEAR.
- **new-recipient** (warn): not in `recent`.
- **over-limit** (warn): `amountInUsd + spentTodayUsd > dailyLimitUsd`.
- **big** (warn): over $1,000.
- **chain-mismatch** (block): the recipient's format doesn't match the
  destination chain (an EVM address for SOL, and so on).

### Private AI on NEAR AI Cloud (Privacy & Private AI track)
The header `X-Glyf-AI: near` (keyboard BackendClient and app GlyfApi, setting
`privateAI = "near"`) routes Glyf's model calls to NEAR AI Cloud's private
models. NEAR AI Cloud is OpenAI-compatible (`https://cloud-api.near.ai/v1`,
key `NEARAI_API_KEY`) and runs models in TEEs. Each answer's attestation or
verification is kept as a receipt (GET /ai/receipts). With no key the header
is ignored. Port the shape of `server/src/lib/privateai.ts` from branch
`ethglobal-mumbai`, where 0G did the same.

## Server as built (branch near-server, 13 Nov)

Everything above holds. What the server adds or decides where the spec was
open, so the clients can rely on it:

- **POST /near/quote** also returns `exact` ("in"/"out"), `recipient` and
  `refundTo` (null on a dry quote). On exact-in, `amountInBase` and
  `deposit.amountBase` are the typed amount in base units, exactly; on a send
  (exact-out) they are 1Click's `amountIn`, which carries the slippage (the
  excess is refunded). A dry quote is priced with valid stand-in addresses
  that are never shown. NEAR's coin is listed by 1Click as wNEAR
  (`nep141:wrap.near`) and is shown as `NEAR`. 1Click's "too low" becomes
  "Too small for NEAR Intents: at least $0.15".
- **A recipient that can't be on the destination chain** (an EVM address for
  SOL) is not an error: the answer is a dry preview (`dry: true`, no
  deposit) with Guard's `chain-mismatch` block, so the panel can say why.
- **Guard texts:** "Looks like 0xAb12…9fE0 you paid before, but it isn't",
  "No NEAR account bob.near", "That's an EVM address, not Solana",
  "First time paying this address", "Over your $200 a day ($40 spent
  today)", "Over $1,000". When NEAR RPC can't be reached, `no-account` comes
  as a **warn** ("Couldn't check bob.near on NEAR"), not a block. Guard runs
  whenever `recipient` is sent, dry or live.
- **GET /near/status** maps 1Click's `KNOWN_DEPOSIT_TX` (seen, not yet
  confirmed) to `PROCESSING`. A refund adds `refunded` (whole coins). An
  address 1Click doesn't know is a 404.
- **GET /names/resolve** for `.near`: found is 200 `{ok, found: true, name,
  chain: "near", address, exists: true, addresses: {near}}`; unknown is 404
  `{ok: false, found: false, name, chain, address, exists: false}` (as ENS
  and SNS misses already are). A 64-hex implicit account is always
  `exists: true` (it is paid into being) with `implicit: true` and `funded`.
- **Private AI:** NEAR AI Cloud's base URL is `https://cloud-api.near.ai/v1`
  (checked). The chain is `Qwen/Qwen3.6-35B-A3B-FP8` then
  `z-ai/glm-5.3-flash`, both NEAR-run models with model attestation reports,
  thinking off. Receipts are checked when the app asks: GET /ai/receipts
  returns `{ok, provider: "NEAR AI Cloud", verifyUrl:
  "https://cloud.near.ai/verify", receipts: [{id, verified, chatId, model,
  requestHash, responseHash, at, status, signature?, reason?}]}`, newest
  first, `at` in ms, `verified` true, false, or null while pending (`status`
  pending, verified, failed, unavailable). A receipt is verified when NEAR's
  ECDSA signature (GET /v1/signature/{id}) recovers to its signing address,
  covers SHA-256 of the exact request and response bytes, and that address is
  in the model's attestation report.
- **For judges:** `cd server && npm install && npm run near:quote -- "swap 20
  usdc on base to sol"` prints a live dry quote (and Guard's checks for a
  phrase with a recipient), no session or .env needed.
- **Env (Vercel):** `NEARAI_API_KEY` (private AI; without it the header is
  ignored), optional `NEAR_INTENTS_JWT` (drops 1Click's 0.2% keyless fee),
  optional `NEAR_RPC_URL`.

## Hand-off keyboard → app

`glyf://open?path=trade?…` with TradeIntent.query, plus:
- `venue=near` (always for NEAR Intents trades)
- `buyChain=<glyf chain>` (swaps), `chain=<sell chain>`
- `to=<recipient as typed>`; for sends, `exact=out`, `amount` = what the recipient gets, `buy`/`buyChain` = what they get, `sell`/`chain` = what pays

## Tests
- Server: vitest with a fake fetch (no network in tests).
- iPhone: RunnerTests (TradeIntentTests).
- App: flutter test.
- Android: JVM unit tests.

Run iOS tests only on simulator 04652CB6 with `-parallel-testing-enabled NO`.

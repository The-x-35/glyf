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
  `Qwen/Qwen3.8-27B` (GLM 5.3 Flash dropped 13 Nov: it kept thinking with thinking off, 6.6 s), both NEAR-run models with model attestation reports,
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

## Pay links (Social Money, Real-World Money; server/src/routes/pay.ts)

"You owe me $22.50 for dinner" becomes a link. Whoever opens it pays with
whatever they hold; the requester gets exactly their share, in the coin and
on the chain they asked for, through one EXACT_OUTPUT NEAR Intents quote per
payer. A request to a Sputnik DAO account (`trip.sputnik-dao.near`) is a
shared pot: every payment lands in the DAO's treasury.

### POST /near/requests (session)
```json
{ "amount": "22.50", "coin": "USDC", "chain": "base", "to": "0x… | alice.near | trip.sputnik-dao.near",
  "note": "dinner", "each": true, "count": 4, "us": false }
```
- `amount`: a number or string (`"$1,200"` is fine), up to 6 decimals.
  The total when `each` is false and `count` is set; each payer's share when
  `each` is true.
- `coin` defaults to USDC; it must be one 1Click trades on `chain`
  ("NEAR Intents doesn't trade DOGE on Base").
- `chain` is where the requester is paid. Left out, it follows `to`: an EVM
  address is Base, a .near name or 64-hex account is NEAR, a Solana address
  is Solana, bc1… is Bitcoin. A `to` that can't be on `chain` is a 400 in
  Guard's words ("That's an EVM address, not Solana"). A .near name must
  exist ("No NEAR account bob.near"; when NEAR RPC can't say, it passes).
- `note`: one plain line, cut to 80 characters.
- `count`: 1–100, the people the link asks. `us: true` means the writer is
  one of `count` ("$90 for 4 of us"): the share is still total ÷ count, and
  the link asks `count - 1` people.
- The share rounds UP so the shares cover the bill (to the cent for USDC,
  USDT, DAI): $100 for 3 is $33.34 each.
- 100 links per account per day.

Answer:
```json
{ "ok": true, "id": "QsgAQOKA-Apb", "url": "https://api.tryglyf.com/pay/QsgAQOKA-Apb",
  "text": "Pay your $22.50 share for dinner: https://api.tryglyf.com/pay/QsgAQOKA-Apb",
  "amount": "22.5", "coin": "USDC", "chain": "base", "to": "0x…", "note": "dinner",
  "each": true, "count": 4, "pot": false }
```
`amount` is each payer's share. `text` is what goes in the chat:
- a pot: `Chip in $50 for the cabin: <url>`
- `each` or `count`: `Pay your $22.50 share for dinner: <url>`
- otherwise: `Pay $22.50 for dinner: <url>` (no note: `Pay $22.50: <url>`)

The link's base is `PUBLIC_BASE_URL`, else `https://api.tryglyf.com` in
production, else `http://127.0.0.1:<PORT>`.

### GET /pay/:id (open, HTML)
One self-contained page (no outside script, font or image; its one script
carries a per-response CSP nonce; `connect-src 'self'`; `no-store`), phone
first, light and dark. It shows "Pay request" (or "Shared pot"), the share,
"Dinner · $22.50 each to alice.near", "Paid as USDC on Base" (a pot: "Into
the trip DAO treasury · shared pot"), the tally with dots ("2 of 4 paid"),
then **Pay with** (USDC · Base / Arbitrum / Ethereum / Solana, ETH · Base,
SOL, BTC, ZEC, NEAR; the requester's own coin and chain left out), **Refund
address**, and **Get deposit address**. Then the QR, "Send exactly 22.725
USDC on Arbitrum", "alice.near gets 22.50 USDC on Base", the address with
Copy, Open in MetaMask (EVM deposits), and the status, polled every 5 s:
Waiting for your deposit → Paying alice.near… → Paid · View. When everyone
has paid: "Everyone's paid". An unknown id is a 404 page.

### POST /pay/:id/quote (open; 10 a minute per IP on the server's limiter)
`{"with": "usdc-arbitrum", "refundTo": "0x…"}` (`with` is one of usdc-base,
usdc-arbitrum, usdc-ethereum, usdc-solana, eth-base, sol, btc, zec, near).
```json
{ "ok": true, "venue": "NEAR Intents", "depositAddress": "0x…", "depositMemo": null,
  "amount": "22.725", "amountBase": "22725000", "amountUsd": "22.73", "coin": "USDC",
  "chain": "arbitrum", "chainName": "Arbitrum", "gets": "22.50 USDC on Base",
  "deadline": "2026-11-13T01:00:00.000Z", "timeSeconds": 20,
  "deposit": {"kind":"erc20","chain":"arbitrum","chainId":42161,"to":"0xaf88…","data":"0xa9059cbb…","value":"0","amountBase":"22725000","token":"0xaf88…","depositAddress":"0x…"},
  "qr": "data:image/svg+xml;base64,…", "uri": "0x…",
  "wallet": "https://metamask.app.link/send/0xaf88…@42161/transfer?address=0x…&uint256=22725000",
  "explorer": "https://explorer.near-intents.org/transactions/0x…" }
```
- 1Click is asked for `EXACT_OUTPUT` of the share, `recipient` = the
  request's `to` on its chain, `refundTo` = the payer's address on the chain
  they pay from (`refundType: ORIGIN_CHAIN`). `amount` carries 1Click's
  slippage; the excess is refunded.
- `uri` is what the QR holds: `bitcoin:<addr>?amount=`, `zcash:<addr>?amount=`,
  `solana:<addr>?amount=[&spl-token=<mint>]`, the bare address elsewhere.
  The QR is drawn on the server (qrcode 1.5.4).
- Errors are `{ok:false, error}`: 400 "Refunds need your Solana address",
  "Too small for NEAR Intents: at least $0.15", "That's what they asked for.
  Send USDC on Base straight to 0x…", "Pick what you pay with", "Add your
  refund address"; 404 "This pay link doesn't exist"; 409 "Everyone's paid";
  429 "Too many tries. Wait a minute" or "This link has had too many tries"
  (60 deposit addresses per link); 502 when 1Click doesn't answer.

### GET /pay/:id/status?deposit=<depositAddress>[&memo=] (open)
GET /near/status's answer for a deposit this link gave out, plus the tally,
and the payer is marked paid on `SUCCESS`:
```json
{ "ok": true, "status": "SUCCESS", "done": true, "amountOut": "22.5",
  "destinationTx": {"hash":"0x…","url":"https://basescan.org/tx/0x…"},
  "explorer": "https://explorer.near-intents.org/transactions/0x…",
  "tally": {"paid": 3, "count": 4, "words": "3 of 4 paid", "full": false} }
```
A deposit from another link is a 404 ("That deposit isn't for this link").
Without `deposit`, the link's pending payers (up to 6, each at most every
30 s, for a day) are asked about again and the answer is `{ok, tally}`.
`tally.words` is "2 of 4 paid", "All 4 paid", "Paid" (count 1), "1 paid"
(no count), or "" (no count, nobody yet).

### Storage
No new table and no migration: requests and payers are rows in the KV store
(`glyf_kv` in Postgres, server/data/*.json locally, memory in tests), as the
shared /p/ pages are. Collection `payreqs` (key = link id) holds the
request; `paypayers` (key = `<id>:<depositAddress>`) holds each payer's
deposit address, memo, what they paid with, amount, status and times, never
their refund address. One row per payer, so two payers never write the
same row.

## The strip's AI suggests NEAR payments (Agent Economy; lib/actions.ts)

A phone that sends `actions: true` to POST /suggest may get one of three
more tools. As with the others, the model only picks from the list, every
value is checked on the server and the chip's words are written there.

| Tool | Params (checked) | Chip |
|---|---|---|
| `near.swap` | `sell`, `buy` (NEAR Intents coins: USDC USDT ETH SOL BTC ZEC NEAR TON TRX XRP DOGE LTC SUI APT XLM ADA BNB), `amount?`, `sellChain?`, `buyChain?` (Glyf chain keys) | `Swap 20 USDC → SOL · NEAR Intents`; same coin: `Move 50 USDC to Solana · NEAR Intents` |
| `near.send` | `to` (.near name, 64-hex account, Bitcoin or Zcash address), `amount`, `coin` (default USDC; BTC for a Bitcoin address, ZEC for Zcash), `with?`, `withChain?` | `Send 5 USDC to alice.near · NEAR Intents`, `… with SOL · NEAR Intents` |
| `near.request` | `amount`, `coin?`, `chain?`, `each?`, `count?` (2–50), `us?`, `note?` (≤40, letters) | `Request $22.50 on Solana · NEAR Intents`, `Request $22.50 each · NEAR Intents` |

- `near.swap` is kept only when it crosses where Uniswap, Jupiter and Flash
  can't (Solana against EVM, or any other chain); a coin with no chain said
  sits on its own chain (SOL → Solana, BTC → Bitcoin) or Base.
- Grounding, stricter than for trades because these move money: an amount
  the words don't hold drops a send or request (a swap just loses its
  amount); a `to` not typed drops the send; swap coins must be typed; a
  chain counts only after on/to/from/in/via/into ("I'm on solana");
  `count`, `each` ("each", "per person", "apiece"), `us` ("of us", "we")
  and each word of `note` must be in the text, else they go. Then the
  action is checked again from the start.
- "you owe me 22.50 for dinner, I'm on solana" →
  `{"tool":"near.request","label":"Request $22.50 on Solana · NEAR Intents","params":{"amount":"22.5","chain":"solana","note":"dinner"}}`.
- "dinner was $90 for the four of us" →
  `{"tool":"near.request","label":"Request $22.50 each · NEAR Intents","params":{"amount":"90","count":4,"us":true,"note":"dinner"}}`.

## Hand-off: the keyboard's Request button (both keyboards)

On the bill-split chip ("$22.50 each") and on a `near.request` action chip:
1. Tap **Request**. The keyboard POSTs /near/requests with the session, as
   every BackendClient call does:
   - from the bill split: `{amount: <total typed>, count: <people>, us: <the
     words said "of us"/"we">, note: <what it was for, if the rules caught
     one>, to, chain}`. Or `{amount: <share>, each: true, count}` when the
     words gave the share.
   - from a `near.request` action: its `params` as they are, plus `to`.
   - `to` and `chain`: the requester's own receiving address. If `chain`
     came with the action, the address on that chain (Phantom for solana,
     MetaMask for EVM chains, the saved `nearAccount` for near); else Base
     and the MetaMask address; else the saved `nearAccount` on near. With
     none of these, the chip says "Add a wallet in Glyf to get paid" and
     nothing is posted. (A saved Sputnik DAO account makes it a pot.)
2. On `ok`, insert the answer's `text` at the cursor, as is:
   `Pay your $22.50 share for dinner: https://api.tryglyf.com/pay/QsgAQOKA-Apb`.
   No toast. On `ok: false`, show `error` on the chip.
3. Nothing else: the page does the rest. The app may list a person's links
   later; there is no list endpoint yet.

## Hand-off keyboard → app

`glyf://open?path=trade?…` with TradeIntent.query, plus:
- `venue=near` (always for NEAR Intents trades)
- `buyChain=<glyf chain>` (swaps), `chain=<sell chain>`
- `to=<recipient as typed>`; for sends, `exact=out`, `amount` = what the recipient gets, `buy`/`buyChain` = what they get, `sell`/`chain` = what pays

## Earn (DeFi, Real-World Money; branch near-earn, lib/nearearn.ts)

"Put $50 to work" parks idle USDC or SOL in a yield vault through NEAR
Intents 1Click Earn
(https://docs.near-intents.org/integration/distribution-channels/1click-api/earn).
Earn is no separate 1Click API: a deposit is an ordinary quote whose
destination is the vault's **receipt token** (its shares), and taking it out
is the reverse quote. So the answer is POST /near/quote's shape and the
app's NearFlow deposits it unchanged. 1Click returns no APY: each vault's
rate comes from its own protocol's public, keyless API, kept ten minutes,
and is `null` (never guessed) when that API doesn't answer.

Vaults (1Click's Earn listings whose shares land where Glyf's wallets are;
each quoted both ways live on 13 Nov 2026):

| id | Vault | Shares (1Click asset) | Chain | Takes | APY from |
|---|---|---|---|---|---|
| `gtusdcp` (USDC default) | Gauntlet USDC Prime (Morpho) | gtUSDCp `nep141:base-0x0bb69b79bc829e1cfcc34a740110886d98d2bd14.omft.near`, 18 decimals | Base | USDC | Morpho GraphQL `vaultByAddress(0xeE8F4eC5672F09119b96Ab6fB59C27E1b7e44b61, 8453).state.netApy` (1Click's 0x0bb6… is an ERC-4626 whose `asset()` is that Morpho vault) |
| `kamino-sol` (SOL default) | Kamino SOL Balanced | kV-gtSOLb `nep141:sol-0xa69aa1bcb03a369e338156a8718ad60271145803.omdep.near`, SPL mint `5EBsGgVTubrd7ShJgE89k6nC2bnLzqGCjXb2ejrhtdBK`, 9 decimals | Solana | SOL | Kamino `GET https://api.kamino.finance/kvaults/vaults/DcCRSdUMgAt6ZMeuL4BJAsZmJgND2LQd74Zq4z6ckhpg/metrics` `.apy` |
| `taler-usdc` | Taler USDC | TLO `nep141:eth-0x0f38f1ce62776d4a0038bc6cac66877a5687383b.omft.near`, 8 decimals | Ethereum | USDC | none found: `apy: null` |

Steakhouse USDC (steakUSDC on Ethereum) is listed by 1Click but answered
"No liquidity available" to every quote, so it isn't offered. A vault
1Click stops listing drops out of the list by itself. Any 1Click coin on
any chain can pay in (USDC on Solana into the Base vault works); the
shares always land on the vault's chain.

### GET /near/earn/vaults (session)
```json
{ "ok": true, "venue": "NEAR Intents", "vaults": [
  { "id": "gtusdcp", "name": "Gauntlet USDC Prime", "protocol": "Morpho", "chain": "base", "chainName": "Base",
    "receipt": "gtUSDCp", "assetId": "nep141:base-0x0bb6….omft.near", "underlying": "USDC",
    "apy": 4.5, "apyBasis": "net APY after the vault's fees", "apySource": "Morpho",
    "url": "https://app.morpho.org/base/vault/0xeE8F…/gauntlet-usdc-prime",
    "about": "Shares of Morpho's Gauntlet USDC Prime vault on Base", "default": true },
  { "id": "kamino-sol", "…": "…", "apy": 4.24, "apyBasis": "current APY", "apySource": "Kamino" },
  { "id": "taler-usdc", "…": "…", "apy": null, "apySource": null, "url": null, "default": false } ] }
```
`apy` is percent a year to two places (4.5 = 4.5%). `cache-control:
private, max-age=60`.

### POST /near/earn/quote (session)
```json
{ "coin": "USDC", "chain": "base", "amount": "50", "direction": "in",
  "vault": "gtusdcp", "refundTo": "0x…", "recipient": "0x…", "slippage": 1 }
```
- `direction`: `in` (default) puts `amount` of `coin` (whole coins, exact
  in) into the vault. `out` takes it back: `amount` = exactly what comes
  back (EXACT_OUTPUT; the shares it takes carry the slippage, the excess is
  refunded), or `shares` (base units, a string) to redeem that many shares
  exactly, which is how "everything" is sent.
- `coin` defaults to USDC. `vault` (id, receipt symbol, asset id or
  protocol word) defaults to the coin's vault: USDC → `gtusdcp`, SOL →
  `kamino-sol`. Any other coin without a vault is a 400.
- `chain` is where the coin is (in) or where the payout lands (out).
  Unsaid: the vault's chain for its own coin, Solana for SOL, else Base.
- `refundTo` + `recipient` make it live (a deposit address), else dry, as
  /near/quote. In: `recipient` holds the shares, so it is the person's
  address **on the vault's chain** (MetaMask for Base/Ethereum, Phantom for
  Solana) and `refundTo` their address on `chain`. Out: `refundTo` is
  their address on the vault's chain (the shares come back there on a
  refund), `recipient` their address on `chain`.

Answer: every field of /near/quote's answer (`dry`, `exact`, `sell`, `buy`,
`amountIn…`, `deposit`, `depositAddress`, `explorer`, `recipient`,
`refundTo`…), plus:
```json
{ "kind": "earn", "direction": "in", "vault": { "id": "gtusdcp", "name": "Gauntlet USDC Prime", "apy": 4.5, "…": "…" },
  "words": "≈ $49.75 in Gauntlet USDC Prime at 4.5% APY" }
```
Out: `words` is "20 USDC back on Base from Gauntlet USDC Prime". The
deposit of an `out` quote is the shares: an ERC-20 transfer of gtUSDCp
(`deposit.kind: "erc20"`, `token` 0x0bb6…) or an SPL transfer of
kV-gtSOLb (`spl`, mint 5EBs…). Morpho's shares count in the millions (20
USDC is about 17.8 M gtUSDCp): show `amountOutUsd`/`words`, never the raw
share count, as the headline.

Errors `{ok:false, error}`: 400 "amount?", "shares?", "Earn takes USDC or
SOL, not DOGE", "Glyf doesn't know that vault", "Gauntlet USDC Prime's
shares need your Base address", "The payout needs your Base address", "NEAR
Intents can't put that into Gauntlet USDC Prime right now" (1Click's "No
liquidity available"), "NEAR Intents can't take that out of … right now",
"Too small for NEAR Intents: at least $X"; 502 when 1Click doesn't answer.
Status after the deposit is GET /near/status, as for any swap.

## The group pot on Sputnik DAO (Social Money; branch near-earn, lib/sputnik.ts)

A pay link to `trip.sputnik-dao.near` fills a shared pot. These read it and
help pay out of it. Read-only: NEAR RPC function-call views (keyless,
https://rpc.mainnet.near.org or `NEAR_RPC_URL`), nothing signed. Payouts
are proposed and voted in **Trezu** (https://trezu.app, NEAR DevHub's
Sputnik app; AstroDAO's app no longer answers).

### GET /near/pot?dao=trip.sputnik-dao.near (session)
```json
{ "ok": true, "dao": "trip.sputnik-dao.near", "name": "trip", "purpose": "Lisbon trip, Nov 2026",
  "balance": { "near": "42.5", "tokens": [
    { "symbol": "USDC", "amount": "120.5", "contract": "17208628…36133a1", "inIntents": false },
    { "symbol": "USDC", "amount": "20", "contract": "17208628…36133a1", "inIntents": true } ] },
  "members": ["ana.near", "ben.near", "cy.near", "dee.near"], "memberCount": 4,
  "proposers": ["ana.near", "…"],
  "threshold": { "role": "council", "approvals": 2, "of": 3, "words": "2 of 3" },
  "bond": "0.1", "votingDays": 7, "lastProposalId": 8, "open": 2,
  "text": "The trip pot holds 42.5 NEAR · 140.5 USDC. 4 members, payouts need 2 of 3. 2 proposals open",
  "proposals": [
    { "id": 5, "kind": "Transfer", "description": "Caterer", "amount": "12.5", "coin": "NEAR", "receiver": "caterer.near",
      "proposer": "ben.near", "status": "InProgress", "votes": {"approve": 1, "reject": 0, "remove": 0},
      "voters": {"ben.near": "Approve"}, "approvalsNeeded": 1,
      "submitted": "2026-11-12T10:00:00.000Z", "expires": "2026-11-19T10:00:00.000Z",
      "url": "https://trezu.app/trip.sputnik-dao.near/requests/5" } ],
  "links": { "trezu": "https://trezu.app/trip.sputnik-dao.near/dashboard", "propose": "https://trezu.app/trip.sputnik-dao.near/payments" } }
```
- `balance.near`: `get_available_amount` (balance less storage and bonds
  held), or `view_account` less storage where that view panics (some DAOs'
  does). `tokens`: `ft_balance_of` on NEAR's USDC
  (17208628…36133a1) and USDT (usdt.tether-token.near), and
  `mt_batch_balance_of` on intents.near (USDC, USDT, wNEAR held inside NEAR
  Intents, as Trezu treasuries keep them). Only non-zero ones.
- `members`: everyone in a group role, at most 50 (`memberCount` is all).
  `proposers`: who may file a transfer, or `"everyone"`.
- `threshold`: the voting group role that passes a Transfer soonest, counted
  as the contract does (a ratio [n, d] of a group of g is min(floor(n·g/d)+1, g),
  a fixed weight is min(w, g), then at least the quorum). `null` when the
  vote is token-weighted.
- `proposals`: the latest 10 (`get_last_proposal_id` + `get_proposals`),
  newest first. `status` is Sputnik's (InProgress, Approved, Rejected,
  Removed, Moved, Failed), plus `Expired` for an open one past its voting
  period. `amount`/`coin`/`receiver` only for transfers. `approvalsNeeded`
  only while open. `url` is the proposal in Trezu, where members vote.
- Kept 30 s. Errors: 400 "dao?", "A pot is a Sputnik DAO, like
  trip.sputnik-dao.near"; 404 "No Sputnik DAO nope.sputnik-dao.near"; 502
  "NEAR didn't answer. Try again in a moment".

### GET /near/pot/propose-link?dao=&to=&amount=&coin=&note= (session)
`to`: a NEAR account (name or 64-hex). `coin`: NEAR, USDC (default) or
USDT, on NEAR. `amount`: whole coins, no more places than the coin has.
`note`: up to 120 characters.
```json
{ "ok": true, "dao": "trip.sputnik-dao.near",
  "url": "https://trezu.app/trip.sputnik-dao.near/payments?address=caterer.near&token=usdc&network=17208628…36133a1",
  "fill": { "amount": "120", "coin": "USDC", "note": "catering" },
  "votePage": "https://trezu.app/trip.sputnik-dao.near/requests",
  "text": "Proposing 120 USDC to caterer.near from the trip pot for catering. Vote: https://trezu.app/trip.sputnik-dao.near/requests",
  "call": { "contract": "trip.sputnik-dao.near", "method": "add_proposal", "deposit": "100000000000000000000000", "gas": "150000000000000",
    "args": { "proposal": { "description": "catering",
      "kind": { "Transfer": { "token_id": "17208628…36133a1", "receiver_id": "caterer.near", "amount": "120000000", "msg": null } } } } },
  "bond": "0.1", "proposers": "everyone", "threshold": { "words": "2 of 3", "…": "…" } }
```
- Trezu's payments page prefills **only** the recipient and token from its
  URL (`address`, `token`, `network`: `token=NEAR&network=near` for NEAR,
  a bare NEAR token contract as `network` for USDC/USDT; read from
  github.com/NEAR-DevHub/trezu `nt-fe/app/(treasury)/[treasuryId]/payments/page.tsx`
  and `utils/payments-deep-link.ts`). The amount and note are typed there:
  that's `fill`. The person must be a proposer and sign in to Trezu with
  their own NEAR wallet; filing costs the DAO's bond (`bond`, NEAR).
- `call` is Sputnik's own `add_proposal`, for a NEAR wallet that signs it
  directly later (HOT); attach `deposit` yoctoNEAR.
- Errors: 400 "to?" / "amount?" / "dao?", "Pay out to a NEAR account, like
  caterer.near", "That's the pot itself", "A pot pays out NEAR, USDC or
  USDT"; 404 and 502 as GET /near/pot. A bad payout is refused before any
  NEAR RPC call.

### The pot's pay page
GET /pay/:id for a pot (`pot: true`) adds two lines under "Into the trip
DAO treasury · shared pot", read live (at most 2.5 s; the page never waits
longer or fails for it): "Holds 42.5 NEAR · 140.5 USDC" and "4 members:
ana.near, ben.near, cy.near and 1 more".

### Example DAO for demos and tests
`build.sputnik-dao.near` (Build DAO, public, 391 proposals, NEAR and USDC
transfers, council "3 of 5", bond 0.1 NEAR) is the live example: `npm run
near:pot -- build.sputnik-dao.near`. Tests use a fake RPC shaped like its
answers.

## Earn and the pot in the keyboards and the app

### Phrases (server reads them in lib/nearphrase.ts; the keyboards read the same)
| Typed | Read |
|---|---|
| `put $50 to work`, `put 50 usdc to work`, `earn on 50 usdc`, `earn yield on $50`, `park 50 usdc`, `park $50 in earn` | Earn in: 50 USDC → Gauntlet USDC Prime |
| `put 0.5 sol to work`, `stake .5 sol in a vault` | Earn in: SOL → Kamino SOL Balanced |
| `put 50 usdc on solana to work`, `park 50 usdc on base` | Earn in, from that chain |
| `take my usdc out of earn`, `take my sol out of earn` | Earn out, everything |
| `take 20 usdc out of earn`, `withdraw $20 from earn`, `… out of earn to solana` | Earn out, exactly 20 back (to that chain) |
| `how much is in the trip pot`, `what's in the pot`, `check the trip pot`, `pot balance`, `how much is in build.sputnik-dao.near` | Pot: look |
| `pay the caterer $120 from the pot`, `pay caterer.near 120 usdc from the trip pot for catering`, `send bob.near 5 near out of the pot` | Pot: propose a payout |

`$` and "dollars"/"bucks" mean USDC. Left alone: "take it out", "put the
kids to work", "park the car", "pay the caterer $120" (no pot).

### The strip's AI tools (gated by `near: true`, like the other near.* tools)
| Tool | Params (checked) | Chip |
|---|---|---|
| `near.earn` | `amount?`, `coin` (USDC default, or SOL), `out?`, `chain?` | `Put 50 USDC to work · Morpho · NEAR Intents`, `Put 0.5 SOL to work · Kamino · NEAR Intents`, `Take your USDC out of Earn · NEAR Intents`, `Take 20 USDC out of Earn · NEAR Intents` |
| `near.pot` | `pot?` (the word before "pot"), `dao?` (*.sputnik-dao.near) | `See the trip pot · Sputnik DAO`, `See the pot · Sputnik DAO` |
| `near.pot.pay` | `to` (a NEAR account, or the name typed: "the caterer"), `amount`, `coin` (USDC default, NEAR, USDT), `pot?`, `dao?`, `note?` | `Propose $120 to caterer from the pot · Sputnik DAO`, `Propose 5 NEAR to bob.near from the trip pot · Sputnik DAO` |

Grounding: Earn's coin must be typed (`$`/dollars/bucks count for USDC); a
withdrawal needs out/withdraw/redeem words and a deposit earn/work/park/
yield/vault/stake words, else the action goes; an untyped amount goes. A
pot tool needs pot/treasury/kitty (or a sputnik-dao name) in the words;
a payout's `to` and `amount` must be typed, a coin other than USDC named;
`pot`, `dao` and `note` stay only when typed.

### Which pot
The app keeps one saved pot, a new setting `nearPot` (a
*.sputnik-dao.near; a Sputnik DAO saved as `nearAccount`, which already
makes pay links pots, counts when `nearPot` is empty). For a pot chip:
`params.dao` if any, else the saved pot, else `<params.pot>.sputnik-dao.near`
(a 404 says "No Sputnik DAO trip.sputnik-dao.near"); with none, the chip
says "Add your pot in Glyf" and nothing is asked.

### Hand-off: Earn
1. Chip tap (near.earn, or the keyboard's own phrase reading) opens the
   trade panel in Earn mode: POST /near/earn/quote dry (`coin`, `amount`,
   `direction`, `chain`), shows `words` ("≈ $49.75 in Gauntlet USDC Prime
   at 4.5% APY"), `vault.protocol`, `timeSeconds`, and "Yield isn't
   guaranteed; NEAR Intents doesn't run the vault" (1Click's ToS §7).
   GET /near/earn/vaults may be read once a session for a vault picker;
   show "APY n/a" when `apy` is null.
2. The button hands off to the app:
   `glyf://open?path=trade?venue=near&kind=earn&direction=in|out&coin=USDC&amount=50[&chain=base][&vault=gtusdcp][&all=1]`.
3. The app (NearFlow) POSTs /near/earn/quote live with `refundTo` and
   `recipient` as above (in: recipient = the wallet on `vault.chain`;
   out: refundTo = the wallet on `vault.chain`), then pays `deposit`
   exactly as a swap's (MetaMask for erc20/native, Phantom for sol/spl),
   POSTs /near/submit and follows GET /near/status.
4. Out with `all=1` ("take my usdc out of earn"): the app reads its share
   balance first, gtUSDCp `balanceOf(<MetaMask address>)` on Base at
   0x0bb69b79bc829e1cfcc34a740110886d98d2bd14 (an ERC-20), or the
   kV-gtSOLb SPL balance (mint 5EBsGgVTubrd7ShJgE89k6nC2bnLzqGCjXb2ejrhtdBK)
   of the Phantom address, and sends it as `shares` (base units). Zero
   shares: "Nothing in Earn yet".
5. On SUCCESS the chip/strip says "Earning on 50 USDC · Morpho" (in) or
   "20 USDC back on Base" (out). No toast.

### Hand-off: the pot
- **near.pot**: GET /near/pot?dao=… and show a card: `text`, then open
  proposals (`status` InProgress) as rows "#5 12.5 NEAR to caterer.near ·
  1 more approval" with **Vote** opening the row's `url` (Trezu). An
  **Insert** button puts `text` in the chat as is.
- **near.pot.pay**: if `to` isn't a NEAR account (`"the caterer"`), the
  panel asks "caterer's NEAR account" (checked with GET
  /names/resolve). Then GET /near/pot/propose-link and show "Propose
  $120 to caterer.near · needs 2 of 3 · bond 0.1 NEAR". **Propose in
  Trezu** opens `url` and copies nothing; the panel shows `fill` ("Type
  120 USDC, note: catering") so the person can finish there. Back in
  chat, **Insert** puts `text` at the cursor. When `proposers` is a list
  without the person's saved NEAR account, say "Only members can propose
  from this pot".
- The app may show the same card on its Pot screen (Profile › Pot), with
  the members and the Trezu dashboard link (`links.trezu`).

### CLI (no session, no .env)
`npm run near:quote -- "put 50 usdc to work"` prints the vault, its APY and
a live dry 1Click Earn quote (also "put 0.5 sol to work", "take 20 usdc out
of earn"); `npm run near:pot -- build.sputnik-dao.near ["pay efiz.near $120
from the pot for catering"]` prints the pot and the Trezu link.

## Tests
- Server: vitest with a fake fetch (no network in tests): nearintents, nearguard, nearphrase, pay (pay links), actions (NEAR tools), nearearn (Earn, fake 1Click/Morpho/Kamino), sputnik (the pot, fake NEAR RPC).
- iPhone: RunnerTests (TradeIntentTests).
- App: flutter test.
- Android: JVM unit tests.

Run iOS tests only on simulator 04652CB6 with `-parallel-testing-enabled NO`.

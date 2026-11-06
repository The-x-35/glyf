# Friction

What got in the way while building Glyf's Vault backup on Arkiv (SDK `@arkiv-network/sdk` 1.0.1, Rabdi testnet), 5–6 Nov 2026. Each item says how to reproduce it.

## 1. No SDK for the platforms a phone app runs on

Glyf is Flutter/Dart (app) and Swift (keyboard). There is only a TypeScript SDK, so we wrote the wire format out ourselves from the SDK source and docs ([PROTOCOL.md](PROTOCOL.md)), then proved it by building every write twice (our code and the SDK through a capturing transport) and comparing signed transactions byte for byte ([vectors.mjs](vectors.mjs), [vectors.json](vectors.json)). The docs page "Write transactions" was accurate and enough to start; the gaps were the SDK-side rules a port has to copy (attribute sorting, 128-byte `str` cap, `bytes` never indexed, gas headroom, reading keys from logs).

Ask: publish the `execute` encoding vectors (a create, patch, extend, delete with fixed inputs and the expected calldata) so every non-JS port can test against the same bytes.

## 2. The node rejects non-canonical ABI, which generic encoders don't always produce

`NonCanonicalOperationData(uint8)` fires on anything but the standard encoding. Dart's common Ethereum library has weak support for arrays of tuples with `bytes`, so a port is safer hand-rolling the four shapes it needs. Worth a line in the docs that "canonical" means standard head/tail order, zero padding and no trailing bytes.

## 3. `eth_call` of `execute` returns `0x`, not the declared `bytes32[] keys`

`execute` is declared `returns (bytes32[] keys)`, and the Arkiv address has no code (`eth_getCode` → `0x`), so the node handles it natively. `eth_call` of a valid create returns empty data, while a failing op does return its custom error. So you can't simulate a create to learn its key; you predict it (`entityNonce` + salt) or read `EntityCreated` from the receipt. The docs say the receipt doesn't carry the return value, but not that `eth_call` doesn't either.

Reproduce (any address works, no funds needed):

```bash
node -e '
const d=require("./vectors.json");
fetch("https://rpc.rabdi.db-chain.testnet.arkiv.network",{method:"POST",headers:{"content-type":"application/json"},
 body:JSON.stringify({jsonrpc:"2.0",id:1,method:"eth_call",params:[{from:d.keys.ownerAddress,to:"0x4400000000000000000000000000000000000044",data:d.writes.create.calldata},"latest"]})})
.then(r=>r.json()).then(console.log)'
# {"jsonrpc":"2.0","id":1,"result":"0x"}
```

## 4. Every user needs gas, and there is no sponsorship path

A per-user, phone-held owner key is the right shape for user-owned data, but each owner address needs tGLM before its first write. The faucet is a web page for a developer, not something an app can call for its users, and there is no paymaster or "someone else pays, the owner signs" option. Workarounds all cost something: a Glyf drip wallet that funds each user's owner address (Glyf's server then learns which owner address is whose), or a relayer that creates entities and transfers ownership (then `$creator` is Glyf, and every later edit still needs gas from the owner). For a consumer app this is the biggest blocker to shipping.

Ask: an app-level gas sponsor (or a per-app access key that also pays for writes from approved owners).

## 5. Old material describes a different protocol

Pre-1.0 SDKs (checked: `@arkiv-network/sdk@0.8.0-advanced.3`) brotli-compressed the payload, and the old address `0x…61726b6976` is still in `consts.ts` (commented out). Blog posts, examples and AI-generated code written against 0.x produce transactions today's Rabdi doesn't understand. The docs' "Conventions that trip up generated code" block in `llms.txt` helped a lot here; a one-line "1.0 changed the wire format, 0.x code will not work" note on the write-transactions page would save time.

## 6. The public RPC needs an access key for real use, and getting one needs an account

`rabdi()` throws without an `accessKey` argument (pass `""` to use the public endpoint, which logs a rate-limit warning). The key "is not a secret" and ships in the app, which is fine, but it has to be requested on hub.arkiv.network with an account, so it couldn't be part of an automated setup. We used the public endpoint for every read and simulation and did not hit a 429 at our volume (tens of calls).

## 7. Cost grows with lifetime, but there's no published formula

The docs say a shorter lifetime costs less. Measured `eth_estimateGas` for one 285-byte vault item on Rabdi: 1 day 141,231 gas, 30 days 178,112, 90 days 252,032, 182 days 365,375 (roughly 140k + 1.23k per day), and 10 creates in one batch 2,232,968. We picked 90 days plus renewal from these numbers; a published price per byte-block would let apps plan this without measuring.

## 8. Small inconsistencies in read responses

- `arkiv_getBlockTiming` returns plain JSON numbers in snake_case (`current_block`, `current_block_time`), while every other field on the API is a hex quantity in camelCase.
- `owner` comes back lowercase in `arkiv_query`, while `addr(...)` literals accept and the SDK prints EIP-55. Harmless, but a port comparing strings has to lowercase both sides.
- The explorer is reachable as both `rabdi.explorer.arkiv.network` and `indexer.rabdi.db-chain.testnet.arkiv.network` (same "Arkiv BlockExplorer" page), so it's unclear which one to link.

## 9. No expiry event

Nothing fires when an entity expires, so a client keeping a local map has to poll `$expiresAt`. Fine for a backup that renews on app open; an `EntityExpired` log (or a cheap "expiring before block N" index for one owner) would help apps that keep mirrors.

## What worked well

- One plain contract call for every write, atomic batches, and keys that can be predicted, so a whole first backup is one transaction.
- `$owner` filtering plus an HMAC'd `key` attribute gave us private lookups with no extra service.
- `permissionlessExtension` is exactly what a backup needs: anyone can keep it alive, only the owner can change it.
- Clear custom errors: `AttributesNotSorted()` (selector `0x3206846a`) came straight back from `eth_estimateGas` when we sent unsorted attributes on purpose.

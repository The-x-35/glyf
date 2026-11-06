# Schema

Glyf writes one kind of entity to Arkiv (Rabdi testnet, chain id 7794095): **one encrypted Vault item per entity**. Full format: [DESIGN.md](DESIGN.md). Wire bytes: [PROTOCOL.md](PROTOCOL.md), [vectors.json](vectors.json).

## `glyf-vault` (one per saved detail, shorthand or combo)

```ts
defineSchema("glyf-vault", {
  v:    u64().indexed(),   // format version, 1
  item: key().indexed(),   // HMAC-SHA256(item key, "field:<id>" | "snippet:<trigger>" | "combo:<id>")
  ct:   bytes(),           // 0x01 ‖ nonce(12) ‖ AES-256-GCM(padded JSON) ‖ tag(16)
})
// plus the SDK's tag: arkiv.schema = "glyf-vault" (str, indexed)
```

| Attribute | Type | Indexed | Holds | Readable by |
|---|---|---|---|---|
| `arkiv.schema` | str | yes | `glyf-vault` | everyone |
| `v` | u64 | yes | `1` | everyone |
| `item` | key | yes | keyed hash of the item id | everyone, but meaningless without the user's vault secret |
| `ct` | bytes | no | the encrypted item (kind, label, value, updatedAt), padded to 128-byte steps | only the user's devices |

**Owner:** an address derived on the phone from the user's 32-byte vault secret (HKDF → secp256k1), which lives in iCloud Keychain. It is used for nothing but this vault. Only it can patch or delete the entities. Glyf's servers never have the key.

**Creator:** the same address (the phone signs every write).

**Creation flags:** `permissionlessExtension` (anyone may extend the expiry, only the owner may change or delete), not read-only (edits are patches).

**Expiry:** 90 days from the last create or renewal (`minLifetime = 3,888,000` blocks). On app open, entities with under 30 days left are extended back to 90 days in one batch. Deleting an item in the app deletes its entity at once.

## Fields queried

| Query | Used for |
|---|---|
| `arkiv.schema = str('glyf-vault') AND $owner = addr(<owner>) ORDER BY $key ASC` (+ `AND $key > key(<last>)` per page of 100) | restore on a second phone; rebuild the local backup map |
| `… AND item = key(<hash>)` | find the one entity to patch or delete for an item |
| `… AND $expiresAt < u64(<current block + 1,296,000>)` | renewal: what has under 30 days left |
| `… AND v < u64(2)` | future format migration |

Every query is pinned to `$owner`, because anyone can write entities tagged `glyf-vault`.

## Run one

The writer address for the demo is the throwaway owner in `arkiv/.owner-address`:
`0x76C58702b86004Aa820F58Ed5F1130Aa34B7E6F8` (**ARPIT: confirm it has written entities after funding; `node ref.mjs` logs the txs to `arkiv/ref-run.json`. Replace with the demo phone's owner address once the app writes.**)

```bash
curl -s https://rpc.rabdi.db-chain.testnet.arkiv.network \
  -H 'content-type: application/json' --data @- <<'EOF'
{"jsonrpc":"2.0","id":1,"method":"arkiv_query","params":[
  "arkiv.schema = str('glyf-vault') AND $owner = addr(0x76C58702b86004Aa820F58Ed5F1130Aa34B7E6F8)",
  {"select":{"key":true,"owner":true,"expiresAt":true,"attributes":true,"count":true},"limit":"0x64"}]}
EOF
```

What it returns: keys, owner, expiry blocks, the `item` hashes and the `ct` ciphertexts. No label, kind or value is readable.

## Not on Arkiv

Vault images, the vault secret, the local backup map, everything else in Glyf (typing model, clipboard, AI requests, account, subscription, wallet). Reasons in [why-arkiv.md](why-arkiv.md).

# Arkiv at the JSON-RPC level

What a client with no Arkiv SDK (Glyf's Flutter app, its Swift keyboard) has to send and parse to write and read Arkiv entities. Taken from the `@arkiv-network/sdk` 1.0.1 source (`src/entity/operations.ts`, `src/schema/codec.ts`, `src/schema/attributes.ts`, `src/entity/key.ts`, `src/entity/expiry.ts`, `src/utils/arkivTransactions.ts`, `src/query/*`) and the docs at docs.arkiv.network (`json-rpc/mutating-entities`, `json-rpc/querying-data`, `reference/query-language`, `reference/limits`), then checked:

- every byte string in [`vectors.json`](vectors.json) is produced twice, by the hand-rolled [`vault.mjs`](vault.mjs) and by the SDK through a capturing transport, and the signed transactions match byte for byte (`node vectors.mjs`);
- the encodings were run on the live Rabdi node with `eth_estimateGas` (a create, patch, extend and delete of the same predicted key in one batch succeeds; an unsorted attribute list reverts with `AttributesNotSorted()`), and every read in `vectors.json` was sent to the live node (`node ref.mjs`).

There is **no RLP payload, no compression and no special transaction type** in 1.0: a write is an ordinary EIP-1559 contract call with plain Solidity ABI calldata. Pre-1.0 SDKs (checked: 0.8.0-advanced.3) brotli-compressed the payload, and older material names the address `0x…61726b6976` (still in `consts.ts`, commented out). Code or blog posts written against 0.x will not work on today's Rabdi.

## Network (Rabdi testnet)

| | |
|---|---|
| Chain id | `7794095` (`0x76edaf`) |
| RPC | `https://rpc.rabdi.db-chain.testnet.arkiv.network` (public, heavily rate limited) or `…/<accessKey>` (key from hub.arkiv.network/access-keys, "not a secret, restrict it to your origins") |
| WebSocket | `wss://rpc.rabdi.db-chain.testnet.arkiv.network[/<accessKey>]` |
| Explorer | `https://rabdi.explorer.arkiv.network` (also served at `https://indexer.rabdi.db-chain.testnet.arkiv.network`) |
| Gas token | tGLM, 18 decimals, faucet `https://hub.arkiv.network/faucet` |
| Node | reth 2.7.0; base fee 1 gwei (`0x3b9aca00`), `eth_maxPriorityFeePerGas` returns `0x0`, block gas limit 30M, per-tx cap 2^24 (EIP-7825) |
| Block time | 2 s. All lifetimes are counted in blocks |

## Writes

### The transaction

Every write is one transaction to the Arkiv address calling `execute`:

| Field | Value |
|---|---|
| `to` | `0x4400000000000000000000000000000000000044` (same on every Arkiv chain) |
| `value` | `0` |
| `data` | `execute((uint8 operation, bytes operationData)[] ops)`, selector `0x49650044` |
| type | EIP-1559 (type 2). Sign with any secp256k1 Ethereum signer, send with `eth_sendRawTransaction` |
| gas | `eth_estimateGas` + 25 % headroom (SDK), capped at 2^24. Measured: one vault create ≈ 252k, create+patch+extend+delete batch ≈ 365k |
| fees | `maxPriorityFeePerGas` may be 0; `maxFeePerGas` ≥ base fee (1 gwei). A create costs ≈ 0.0003 tGLM |

A batch is atomic: all ops apply or none; op *n+1* sees op *n*'s effects; each applied op emits one event. There is no `arkiv_*` write method.

Raw tx example (vectors.json `writes.delete.rawSignedTx`, nonce 3, gas 500000, maxFee 2 gwei, tip 0.001 gwei):

```
02                                           type 2
f9 0152                                      RLP list, 338 bytes
  83 76edaf                                  chainId 7794095
  03                                         nonce 3
  83 0f4240                                  maxPriorityFeePerGas 1,000,000
  84 77359400                                maxFeePerGas 2,000,000,000
  83 07a120                                  gas 500,000
  94 4400000000000000000000000000000000000044  to
  80                                         value 0
  b8 e4 49650044 …                           data (228 bytes, below)
  c0                                         accessList []
  80                                         yParity 0
  a0 53d3…293a                               r
  a0 0433…b96f                               s
```

### `execute` calldata

Standard Solidity ABI encoding of one dynamic array of `(uint8, bytes)` tuples. The node rejects anything that is not the **canonical** encoding (`NonCanonicalOperationData(uint8)`): offsets in standard order, zero padding, no trailing bytes. A delete of one entity (vectors.json `writes.delete.calldata`):

```
49650044                                                          selector
0x00 0000…0020   offset of ops[]
0x20 0000…0001   ops.length = 1
0x40 0000…0020   offset of ops[0] (relative to the start of the array body)
0x60 0000…0005   ops[0].operation = 5 (delete)
0x80 0000…0040   offset of ops[0].operationData (relative to the tuple)
0xa0 0000…0020   operationData.length = 32
0xc0 ad74b40e4505a52ccca1e8d73d594ef5357a57a6c116593689da3d37ba7af4c9   operationData = abi.encode((bytes32 entityKey))
```

### Operations

`operationData` is `abi.encode` of **one tuple** (so a create's payload starts with the `0x20` tuple offset, because the tuple is dynamic):

| Tag | Op | `operationData` = abi.encode of | Event |
|---|---|---|---|
| 1 | create | `(uint128 salt, uint64 expiresAt, uint64 minLifetime, uint8 creationFlags, (bytes32 name, uint8 typeId, bytes value)[] attributes)` | `EntityCreated(bytes32 indexed entityKey, address indexed owner, uint64 expiresAt, uint8 creationFlags)` |
| 2 | patch | `(bytes32 entityKey, (bytes32 name, uint8 typeId, bytes value)[] mutations)` | `EntityPatched(bytes32 indexed entityKey, address indexed owner)` |
| 3 | extend | `(bytes32 entityKey, uint64 expiresAt, uint64 minLifetime)` | `ExpiryExtended(bytes32 indexed entityKey, address indexed owner, uint64 expiresAt)` |
| 4 | transfer | `(bytes32 entityKey, address newOwner)` | `OwnershipTransferred(bytes32 indexed entityKey, address indexed previousOwner, address indexed newOwner)` |
| 5 | delete | `(bytes32 entityKey)` | `EntityDeleted(bytes32 indexed entityKey, address indexed owner)` |

Topic0 values: `keccak256` of the event signatures above (viem/`web3dart` compute them; they are in no other list here on purpose, so a port computes and checks them).

Only the owner may patch, extend (unless `permissionlessExtension`), transfer or delete. A patch only touches the attributes it names; it never changes the expiry. Extend can't move the expiry earlier.

### Attributes

```
struct Attribute { bytes32 name; uint8 typeId; bytes value; }
```

- `name`: ASCII, left-aligned and zero-padded to 32 bytes (`"ct"` → `0x6374 00…00`). Rules: `^[A-Za-z][A-Za-z0-9._-]*$`, ≤ 32 bytes, no `--`, not a query keyword or type name (`and or not true false between startswith exists typeof order by asc desc bool i32 u64 u256 dec bytes str addr key`, any case), `$…` reserved. `arkiv.schema` is the SDK's schema tag.
- `typeId`: low 7 bits = type, bit 7 (`0x80`) = indexed (filterable).

| typeId | type | `value` bytes | JSON-RPC rendering on read |
|---|---|---|---|
| 0 | tombstone | empty; patch only, unsets the attribute | n/a |
| 1 | bool | 32-byte word, 0 or 1 | `true` / `false` |
| 2 | i32 | 32-byte word, sign-extended | JSON number |
| 3 | u64 | 32-byte word | hex quantity `"0x2a"` |
| 4 | u256 | 32-byte word | hex quantity |
| 5 | dec | 32-byte word, signed int = value × 10^18 | decimal string `"4.5"` |
| 6 | reserved (node's `bytes32`; SDK reads it as key) | | |
| 7 | bytes | raw, ≤ 128 KiB, never indexed (`0x80` with 7 reverts) | hex data |
| 8 | str | raw UTF-8, ≤ 128 bytes | string |
| 9 | addr | 32-byte word, address right-aligned | hex data (lowercase) |
| 10 | key | 32 bytes | hex data |

The list must be **strictly ascending by the 32-byte `name`** (byte-wise), so each name once (`AttributesNotSorted()`, selector `0x3206846a`, otherwise). At most 32 attributes per op. All `bytes` values of one op ≤ 128 KiB. No tombstones in a create.

Byte-level create (vectors.json `writes.create.operations[0].operationData`, one Glyf vault item):

```
0x000 …0020                                tuple offset
0x020 …0123456789abcdef0123456789abcdef    salt (uint128)
0x040 …0000                                expiresAt = 0 (no absolute deadline)
0x060 …3b5380                              minLifetime = 3,888,000 blocks (90 days)
0x080 …0002                                creationFlags = 0b10 (permissionlessExtension)
0x0a0 …00a0                                offset of attributes (relative to tuple start)
0x0c0 …0004                                attributes.length = 4
0x0e0 …0080  0x100 …0120  0x120 …02c0  0x140 …0360     offsets of attributes[0..3]
0x160 61726b69762e736368656d61 00…          [0].name  "arkiv.schema"
0x180 …0088                                [0].typeId str|indexed
0x1a0 …0060                                [0].value offset
0x1c0 …000a  0x1e0 676c79662d7661756c74 00… [0].value "glyf-vault" (10 bytes, zero-padded)
0x200 6374 00…                              [1].name  "ct"
0x220 …0007                                [1].typeId bytes
0x240 …0060  0x260 …011d                    [1].value offset, length 285 = 1 + 12 + 256 + 16
0x280 01 0a0b0c0d0e0f101112131415 b86a6c…   [1].value: format 01, nonce, ciphertext+tag (zero-padded to 288)
0x3a0 6974656d 00…                          [2].name  "item"
0x3c0 …008a                                [2].typeId key|indexed
0x3e0 …0060  0x400 …0020  0x420 0503e7…c80e [2].value 32 bytes (HMAC of "field:addr-home")
0x440 76 00…                                [3].name  "v"
0x460 …0083                                [3].typeId u64|indexed
0x480 …0060  0x4a0 …0020  0x4c0 …0001       [3].value = 1 as a 32-byte word
```

### Expiry

Create and extend carry `(expiresAt, minLifetime)`; the node resolves `expiry = max(expiresAt, inclusionBlock + minLifetime)`.

| Want | expiresAt | minLifetime |
|---|---|---|
| lifetime of N blocks | 0 | N |
| absolute block B | B | 0 |
| B, but at least N | B | N |

Must be > inclusion block (`ExpiryDeadOnArrival`) and ≤ inclusion block + 7,884,000 (`ExpiryBeyondMaxLifetime`, about 182.5 days). Both 0 is rejected by the SDK. An extend by a duration counts from now, not from the old expiry; equal to the current expiry is a no-op, earlier reverts. No event fires when an entity expires: after its expiry block it is gone from queries and every op on it reverts with `EntityExpired`.

### Creation flags

Byte, fixed for life: bit 0 read-only (attributes can never change), bit 1 permissionless extension (anyone may extend), bits 2–7 must be 0.

### Entity keys

The node mints the key; a client can predict it:

```
key = keccak256( uint256 chainId || address 0x44…44 || address owner || uint64 entityNonce || uint128 salt )   // abi.encodePacked: 32+20+20+8+16 = 96 bytes
```

`entityNonce` is per owner, separate from the tx nonce, +1 per create (the *n*th create in a batch uses nonce+n). Read it with `eth_call {to: 0x44…44, data: 0x36917bfd ++ owner left-padded to 32}`. Salt: 128 random bits (SDK default) so only the creator can predict the key; 0 makes it public. Example: owner `0xbA9F…75Fe`, nonce 0, salt `0x0123…cdef` → `0xad74b40e…f4c9` (vectors.json `writes.predictedEntityKey`).

Read the key back from the receipt: logs from `0x44…44` with topic0 = `EntityCreated`, `topics[1]` = key. `execute` is declared to return `bytes32[] keys`, but `eth_call` of it returns `0x` on Rabdi, so don't rely on the return value; use the event or the prediction.

### Revert errors

ABI custom errors, also returned by `eth_call`/`eth_estimateGas` as `error.data`: `EmptyBatch()`, `InvalidOpType(uint8)`, `NonCanonicalOperationData(uint8)`, `AttributesNotSorted()`, `TooManyAttributes(uint256,uint256)`, `EmptyMutations(bytes32)`, `TombstoneInCreate(bytes32)`, `TombstoneValueNotEmpty(bytes32)`, `SystemAttributeNotWritable(bytes32)`, `InvalidValueType(bytes32,uint8)`, `Ident32Empty()`, `Ident32InvalidByte(uint256,bytes1)`, `EntityNotFound(bytes32)`, `EntityExpired(bytes32,uint64)`, `NotOwner(bytes32,address,address)`, `ReadOnlyEntity(bytes32)`, `ReservedCreationFlags(uint8)`, `ExpiryDeadOnArrival(uint64,uint64)`, `ExpiryBeyondMaxLifetime(uint64,uint64,uint64)`, `ExpiryNotExtended(bytes32,uint64,uint64)`, `TransferToZeroAddress(bytes32)`, `TransferToSelf(bytes32)`. Selector = first 4 bytes of keccak256 of the signature.

## Reads

Standard `eth_*` methods plus three `arkiv_*` methods.

### `arkiv_query`

```json
{"jsonrpc":"2.0","id":1,"method":"arkiv_query","params":[
  "arkiv.schema = str('glyf-vault') AND $owner = addr(0xbA9F3B70109Eb210a296637d1e61192Add4a75Fe) ORDER BY $key ASC",
  {"select":{"key":true,"owner":true,"expiresAt":true,"updatedAt":true,"attributes":true},"limit":"0x64"}
]}
```

- `params[0]`: the query string (grammar below).
- `params[1]` (optional): `select` = flat booleans `key owner creator createdAt updatedAt expiresAt creationFlags attributeSchema count`, and `attributes` = `true` or `{ "name": true, … }`. Everything but `key` defaults off. `limit` hex 1..100 (default 100, outside → `-32602`), `offset` hex.
- Result: `{ "data": [entity…], "blockNumber": "0x…", "count": "0x…" (only if selected) }`. Each entity carries only the selected fields; `owner` comes back lowercase; block numbers are hex; `creationFlags` is `{readonly, permissionlessExtension, raw}`; `attributes` is `[{ "name", "type", "value" }]` with `type` the tag (`str`, `bytes`, `u64`, …) and `value` rendered per the table above. Real response shape (live node):

```json
{"key":"0x22a7…e9f9","owner":"0x3f0f…c0fb","expiresAt":"0x95c09","updatedAt":"0x2193",
 "attributes":[{"name":"arkiv.schema","type":"str","value":"arkiv-chunking/manifest/v2"},
               {"name":"chunkcount","type":"u64","value":"0x3"},
               {"name":"complete","type":"bool","value":true},
               {"name":"metadata","type":"bytes","value":"0x7b2266…7d"}]}
```

- Paging: add `ORDER BY $key ASC` and either `offset` or, robust to concurrent writes, `AND $key > key(<last key>)`. A page with fewer rows than `limit` is the last.
- Errors: `-32001` parse (data has position/expected/found), `-32002` type, `-32003` literal, `-32004` limits (length, nesting).
- Reads the latest block; each page may be at a different block (`blockNumber` says which).

### Query grammar

```
expr     := term (OR term)*            ; AND binds tighter than OR, parentheses group
term     := factor (AND factor)*
factor   := name op literal | name BETWEEN literal AND literal | name STARTSWITH str('…')
          | EXISTS(name) | TYPEOF(name) = type | '(' expr ')'
op       := = | < | <= | > | >=
literal  := true | false | i32(-7) | u64(1700000000) | u256(…) | dec(4.5) | str('it''s')
          | addr(0x…40 hex) | key(0x…64 hex)     ; a bare number is i32
query    := expr [ORDER BY name:type ASC|DESC]    ; entity fields need no :type
```

- Keywords are case-insensitive; `--` starts a comment to end of line (so never let user text into a query unescaped; `str('…')` escapes `'` as `''`, there are no backslash escapes).
- A comparison matches only an **indexed** attribute stored with the **same type** (`score = i32(4)` doesn't match a `dec` score).
- Entity fields: `$key` (key), `$owner` (addr), `$creator` (addr), `$expiresAt` (u64) can be filtered and sorted; `$createdAt`, `$updatedAt`, `$creationFlags` can only be selected.
- `addr(…)` accepts lowercase, uppercase or valid EIP-55; mixed case with a bad checksum is a `-32003`.
- Anyone can write any entity, so every trusted read must filter on `$owner` (or `$creator`) and should also filter on the schema tag.

### `arkiv_getEntity`

`params: ["0x<32-byte key>"]` → the entity with every field except `attributeSchema`, or `null` if it never existed, was deleted, or has expired.

### `arkiv_getBlockTiming`

No params → `{"current_block": 263332, "current_block_time": 1793912424, "duration": 2}` (plain JSON numbers here, not hex). Use `current_block` to turn "renew when fewer than 30 days left" into `$expiresAt < u64(current_block + 1296000)`.

### Events

`eth_getLogs {address: 0x44…44, topics: [EntityCreated topic0, null, owner as 32 bytes]}` lists one owner's creates; the logs carry keys and expiries, not attribute values (those live in calldata and in node state).

## What the SDK adds on top (a port must do these itself)

1. Sort attributes by padded name; reject `bytes` with the indexed bit; enforce ≤ 32 attributes, ≤ 128-byte `str`, ≤ 128 KiB `bytes`.
2. Read `eth_blockNumber` to resolve "N days" into blocks and check the 182.5-day cap before sending.
3. Random 128-bit salt per create.
4. `eth_estimateGas` × 1.25, capped at 2^24; on a reverted receipt, re-simulate with `eth_call` to get the custom error.
5. Read created keys and resolved expiries from the receipt's `EntityCreated` / `ExpiryExtended` logs, in batch order.
6. Schema tag: a named schema writes `arkiv.schema` (str, indexed) on create and adds `arkiv.schema = str('<name>')` to every query, and drops rows whose attributes don't fit the schema.

# Glyf Vault backup on Arkiv: design

Glyf's Vault holds what people type again and again: saved details (name, email, phone, address, wallet address, links, card, password, anything) and shorthand (`;addr` → the full address). Today it lives only on the phone (iOS App Group / Android app storage). This design backs it up to Arkiv, encrypted on the phone, owned by a key only the user's devices can derive, and restorable on a second phone with nothing but the user's iCloud Keychain.

Reference code: [`vault.mjs`](vault.mjs) (format, no SDK), [`ref.mjs`](ref.mjs) (SDK run), [`vectors.json`](vectors.json) (bytes to match). Wire format: [`PROTOCOL.md`](PROTOCOL.md).

## Keys

```
vault secret S        32 random bytes, made once on the first phone that turns backup on
                      │
                      ├─ HKDF-SHA256(S, salt="glyf-vault-hkdf-v1", info="glyf/vault/v1/arkiv-owner" || 0x00) ─► owner key  (secp256k1; if 0 or ≥ n, retry with counter byte 0x01, 0x02 …)
                      ├─ HKDF-SHA256(S, salt, info="glyf/vault/v1/aes-256-gcm")                       ─► content key (AES-256-GCM)
                      └─ HKDF-SHA256(S, salt, info="glyf/vault/v1/item-id")                           ─► item key   (HMAC-SHA256)
```

All three are 32 bytes (HKDF L = 32). Nothing derived is ever stored; it is re-derived from S when needed and dropped.

**Where S lives**

- **iPhone:** a generic-password Keychain item, `kSecAttrService = "app.glyf.vault-backup"`, `kSecAttrAccount = "arkiv-vault-secret-v1"`, `kSecAttrSynchronizable = true`, `kSecAttrAccessible = kSecAttrAccessibleAfterFirstUnlock` (synchronizable items can't be `ThisDeviceOnly`). iCloud Keychain carries it end-to-end encrypted to the user's other Apple devices. In Flutter: `flutter_secure_storage` with `IOSOptions(synchronizable: true, accessibility: KeychainAccessibility.first_unlock)`. It stays in the **app's** keychain group, not the group shared with the keyboard: the keyboard never needs it, since backup and restore run in the app.
- **Android:** Google Block Store (`BlockstoreClient.storeBytes` with `setShouldBackupToCloud(true)`), which is end-to-end encrypted when the phone has a screen lock and restores on a new Android phone at setup. Not built yet.
- **Moving between iPhone and Android, or no iCloud Keychain:** a "Backup code" screen shows S as 52 base32 characters in groups of four. Typing it on the new phone is a restore. Not built yet.

Losing S means losing the backup (by design there is no server copy). Anyone with S can read every item ever backed up, including old versions (see "What stays public").

## One entity per vault item

Named schema `glyf-vault` (the SDK writes and filters the indexed `arkiv.schema` attribute). Four attributes, nothing else:

| Attribute | Type (typeId) | Indexed | Value | Why |
|---|---|---|---|---|
| `arkiv.schema` | str (`0x88`) | yes | `"glyf-vault"` | the app tag: every query filters on it |
| `ct` | bytes (`0x07`) | never | `0x01 ‖ nonce(12) ‖ AES-256-GCM(ciphertext ‖ tag 16)` | the item, encrypted |
| `item` | key (`0x8a`) | yes | `HMAC-SHA256(item key, UTF-8 item id)` | find and replace one item without saying what it is |
| `v` | u64 (`0x83`) | yes | `1` | format version, so a later format can be found and migrated |

Owner (`$owner`) is the address of the owner key. Entities are created with `permissionlessExtension` (flags `0b10`) and not read-only, so the owner can edit and delete, and anyone may extend (keep it alive) but nobody else can change or delete it.

**Item ids** (stable across devices, never shown on chain):

| Vault thing | item id | plaintext JSON |
|---|---|---|
| saved detail | `field:<field id>` | `{"id","type":"field","kind","label","value","updatedAt"}` |
| shorthand | `snippet:<trigger>` | `{"id","type":"snippet","trigger","text","updatedAt"}` |
| combo | `combo:<combo id>` | the combo object, plus `id`, `type`, `updatedAt` |

`updatedAt` is Unix milliseconds of the local edit. Vault **images** stay off Arkiv (size: a photo is far over the 128 KiB per-write limit, and they are the least "typed again" thing in the vault).

**Encryption.** AES-256-GCM, random 96-bit nonce per write, under the one content key. AAD = `"glyf-vault/v1" ‖ chainId (uint64 big-endian) ‖ owner (20 bytes) ‖ item hash (32 bytes)`, so a ciphertext can't be replayed onto another item, owner or chain. Plaintext = the UTF-8 JSON zero-padded to a multiple of 128 bytes (min 128), so lengths only show in 128-byte steps; JSON never contains `0x00`, so trailing zeros strip back off. After decrypting, the reader checks `HMAC(item key, plaintext.id) == item` and drops the entity if not.

Why AES-GCM over XChaCha20-Poly1305: the keyboard and app are Swift/Kotlin/Dart, and CryptoKit has AES-GCM (and IETF ChaCha20-Poly1305 with a 96-bit nonce) but no XChaCha; Android's `javax.crypto` and Dart's `cryptography` have AES-GCM natively. Random 96-bit nonces under one key are safe well past 2^32 messages; a vault sees a few hundred writes in its life. If a later version wants XChaCha, `ct[0]` is the format byte.

## Expiration and renewal

- Every create and renewal asks for **90 days** (`minLifetime = 3,888,000` blocks, `expiresAt = 0`).
- On every app open (at most once a day), the app queries the owner's entities with `$expiresAt < u64(currentBlock + 1,296,000)` (under 30 days left) and extends all of them to 90 days in one batch.
- Gas grows with lifetime (measured on Rabdi for one vault item: 1 day 141k, 30 days 178k, 90 days 252k, 182 days 365k), so 90 days with renewal costs less than the 182.5-day maximum while still surviving three months untouched.
- `permissionlessExtension` lets a Glyf keeper job extend a subscriber's entities without any user key, so a backup survives a phone that stays in a drawer. Not built yet; it needs only the owner address list and tGLM.
- An edit (patch) does not touch expiry. A delete removes the entity at once.

## Sync

Local, per device, not synced: a map `item hash → { entityKey, ctDigest, expiresAt }`.

| Local change | Arkiv op |
|---|---|
| new item | create (random 128-bit salt; key predicted from `entityNonce` + salt, confirmed from the `EntityCreated` log) |
| edited item | patch `{ct, v}` |
| deleted item (or shorthand renamed) | delete (rename = delete old id + create new id) |
| nothing changed | nothing |

Pending ops go out as one `execute` batch per backup (the 2^24 per-tx gas cap fits about 60 creates; bigger first backups split into several txs). The tx is signed on the phone with the owner key and sent with `eth_sendRawTransaction`.

## Restore on a second phone

1. iCloud Keychain delivers S. The app sees S but no local backup map, and offers "Restore your Vault".
2. Derive the owner address. Query, 100 at a time, paging by key:
   `arkiv.schema = str('glyf-vault') AND $owner = addr(<owner>) [AND $key > key(<last>)] ORDER BY $key ASC`, selecting `key, expiresAt, updatedAt, attributes`.
3. For each row: skip if `item` isn't a key or `ct` isn't bytes or `ct[0] != 1`; decrypt; check the item hash; keep it.
4. Two entities with the same `item` (two phones created it at once): keep the larger plaintext `updatedAt`, then delete the other.
5. Write the items into the local vault (`GlyfBridge.vaultUpsertField` / `vaultUpsertSnippet`), and fill the local backup map from the rows.

Filtering by `$owner` is what makes the read trustworthy: anyone can write entities tagged `glyf-vault`, but only the owner key can write entities owned by that address.

## Gas

Every owner address needs a little tGLM (one item ≈ 252k gas ≈ 0.00025 tGLM at Rabdi's 1 gwei base fee). For the hackathon demo the owner address is funded from the faucet by hand. For real users that needs a Glyf drip (the API sends a small amount of tGLM to a signed-in user's owner address once). That drip would tell Glyf's server which owner address belongs to which account; the contents stay unreadable. Not built.

## What stays public

Arkiv is a public database. Anyone can see, for one owner address: how many vault items there are, their sizes in 128-byte steps, when each was created, edited, extended and deleted, and the ciphertexts. Old ciphertexts stay in chain history (calldata) after a patch or delete, so deleting an item removes it from Arkiv's state, not from history. The owner address is used for nothing else and isn't linked on chain to the user's wallet or Glyf account. Item ids are hidden behind an HMAC, so nobody can test "does this person have a `card` item".

# Why Arkiv

## What users would lose with a conventional database

The obvious alternative is "Glyf stores your encrypted Vault on its own server" (Postgres on Neon, which Glyf already runs). Encryption on the phone would be the same. What changes is who holds and controls the copy.

| With Glyf's database | With Arkiv |
|---|---|
| Glyf decides whether your backup exists. An outage, a lapsed hosting bill, a shutdown or an acquisition can take it away. Rewind/Limitless users lost their data overnight when Meta bought it (docs/GO-TO-MARKET.md). | The backup is owned by an address only the user's devices can derive. Glyf can't delete or change it. With `permissionlessExtension`, anyone (the user, Glyf, or a future tool) can keep it alive. |
| Restoring needs Glyf's API, a Glyf account and Glyf's server code, forever. | Restoring needs the vault secret and any Arkiv RPC. The format is public ([DESIGN.md](DESIGN.md), [PROTOCOL.md](PROTOCOL.md)), so a user, or anyone they trust, can write their own restore tool. |
| The server can silently serve an old or edited copy, and the user can't tell. | Reads are filtered by `$owner`: only the owner key can write those entities, and every change is a signed, public transaction. |
| A breach of Glyf's database exposes everyone's ciphertexts plus who they belong to (Glyf account ids). | Ciphertexts are public anyway, so there is nothing extra to breach; the owner address isn't tied on chain to a person, an email or their wallet. |
| iCloud/CloudKit backup would be Apple-only. | Works the same for iPhone and Android (the key moves through iCloud Keychain, Block Store or a typed code). |

What it costs the user: a few seconds per backup batch and a tiny gas fee per write (≈ 252k gas per item at 1 gwei on Rabdi). The honest limit: testnet today, and every owner needs a little gas (see [friction.md](friction.md#4-every-user-needs-gas-and-there-is-no-sponsorship-path)).

## What we kept off Arkiv, and why

Arkiv is public: anything written is readable by everyone, and stays in chain history even after a patch or delete. So only ciphertext and non-revealing tags go on it.

| Kept off | Why |
|---|---|
| The vault secret and every key derived from it | It is the only thing protecting the backup. It lives in iCloud Keychain (Block Store on Android) and is never sent anywhere else. |
| Plaintext of any Vault item, its kind or label | Public forever. Even the kind ("card", "password") would say too much, so it is inside the ciphertext and the item id is hidden behind an HMAC. |
| Vault images | Over the 128 KiB per-write limit, and the least-used part of the Vault. Swarm would be the fit (encrypted, reference kept inside the ciphertext), not built. |
| The phone's local backup map (item → entity key) | Rebuilt from Arkiv on restore; no reason to publish it. |
| Typing model, learned words, clipboard, notes | Personal, high-volume, constantly changing; they stay on the phone, as today. |
| AI requests and answers | Sent to the AI providers under Glyf's no-data-collection terms; nothing to keep. |
| Glyf account, subscription, gift codes, rate limits | Need a server that can revoke, refund and erase (App Store rules, account deletion). A public, user-owned store is the wrong tool. |
| Wallet keys | Glyf never holds them; Phantom and the EVM wallet sign. |

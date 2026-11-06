# How Glyf uses Arkiv

Glyf backs up the Vault (saved details and shorthand) to Arkiv: one encrypted entity per item, owned by a key the user's phones derive from a secret in iCloud Keychain. A second phone restores by querying that owner. Design: [DESIGN.md](DESIGN.md). Wire format: [PROTOCOL.md](PROTOCOL.md). Code: [vault.mjs](vault.mjs) (format, no SDK), [ref.mjs](ref.mjs) (with `@arkiv-network/sdk`), [vectors.json](vectors.json).

**ARPIT: say here which of the user-visible parts below are in the demo build, and the demo video timestamps.**

## Each Arkiv feature, and what the user sees

| Arkiv feature | How Glyf uses it | What the user sees |
|---|---|---|
| **Wallet-owned entities** (`$owner`) | The owner is an address derived on the phone (HKDF → secp256k1) only for the Vault. Glyf's server never has the key. | "Restore your Vault" works on a new phone with no Glyf server involved; Glyf can't delete their backup. |
| **Filters on indexed attributes** | Restore: `arkiv.schema = str('glyf-vault') AND $owner = addr(<owner>)`, paged by `$key`. Edit/delete: `… AND item = key(<HMAC of item id>)`. | All their Vault items come back on the new phone. Editing one item updates only that one. |
| **Entity fields as filters** (`$expiresAt`, `$key`) | Renewal finds what has under 30 days left; paging uses `$key > key(…)` so nothing is skipped while another device writes. | Nothing to do: the backup quietly stays alive while they use Glyf. |
| **Edit permissions** (only the owner can patch/delete) | An edited item is a `patch` of `ct`; a deleted item deletes its entity. | Deleting a detail in Glyf deletes it from the backup too. |
| **`permissionlessExtension`** | Anyone may extend a vault entity, nobody but the owner may change it. Lets a keeper (Glyf or the user's other device) renew without the key. | A backup survives a phone left in a drawer (once the keeper job exists). |
| **Expiration** | 90-day lifetime, renewed on app open when under 30 days are left (one batch). Chosen from measured gas: 90 days ≈ 252k gas per item, 182 days ≈ 365k. | Nothing to do. If they stop using Glyf for good, the backup expires on its own instead of sitting somewhere forever. |
| **Atomic batches** + **predictable keys** | A first backup is one `execute` with one create per item (≈ 60 per tx under the gas cap); keys are predicted from `entityNonce` + salt and confirmed from `EntityCreated` logs. | Backing up a whole Vault is one step, and either all of it lands or none. |
| **`arkiv_getEntity`** | Reads one item back after a patch to confirm it. | The Vault shows the item as backed up. |

## Fit

- **Filters:** fit well. The only things we filter on are the app tag, owner, a keyed hash, expiry and version, all indexed. We never need to filter on content (it's encrypted), which is exactly where Arkiv's model (filter on indexed attributes, keep blobs in `bytes`) is strongest.
- **Edit permissions:** fit exactly. Owner-only patch and delete is the access model a personal backup wants, and `permissionlessExtension` splits "keep alive" from "change", which a conventional store would need custom ACLs for.
- **Expirations:** a good fit for a backup that should fade if abandoned, with one cost: a backup the user forgets about for 90 days without a keeper disappears. Renewal on app open plus `permissionlessExtension` covers it.

## Verified so far

- `node vectors.mjs`: 5 write vectors (create, patch, extend, delete, 2-item batch) built by hand and by the SDK, identical signed transactions.
- `node ref.mjs` (no funds): on the live Rabdi node, a batch of create → patch → extend → delete on the predicted key passes `eth_estimateGas` (≈ 365k–378k gas), one create ≈ 252k–263k, and unsorted attributes revert with `AttributesNotSorted()`; the restore, by-item and expiring-soon queries run and return.
- `node ref.mjs` (funded): create, restore by owner (SDK and raw JSON-RPC), patch and read back, find by item hash, extend, delete. **ARPIT: run after funding `0x76C58702b86004Aa820F58Ed5F1130Aa34B7E6F8`; the tx links land in `arkiv/ref-run.json`.**

## Run it

```bash
cd arkiv
npm install
node keygen.mjs      # throwaway vault secret in arkiv/.key (never printed); prints the owner address
node vectors.mjs     # rebuild vectors.json and compare against the SDK (offline)
node ref.mjs         # live simulation, then real writes if the owner has tGLM
```

Optional: `ARKIV_ACCESS_KEY=<key from hub.arkiv.network/access-keys>` to avoid the public rate limit.

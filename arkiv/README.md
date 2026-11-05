# arkiv/: Glyf Vault backup on Arkiv

Encrypted Vault items (saved details, shorthand) as wallet-owned entities on Arkiv's Rabdi testnet, restorable on a second phone.

| File | What |
|---|---|
| [DESIGN.md](DESIGN.md) | keys (iCloud Keychain secret → HKDF → owner key + AES key), entity layout, expiry and renewal, sync, restore |
| [PROTOCOL.md](PROTOCOL.md) | Arkiv's write and read wire format, byte by byte, for the Dart/Swift port |
| [vault.mjs](vault.mjs) | the format in ~200 lines with no Arkiv SDK (what a port copies) |
| [vectors.mjs](vectors.mjs) → [vectors.json](vectors.json) | fixed inputs → keys, ciphertexts, calldata, signed txs, queries; each write also built by the SDK and matched |
| [ref.mjs](ref.mjs) | live run with `@arkiv-network/sdk`: simulate on the node, then create, restore, patch, extend, delete |
| [keygen.mjs](keygen.mjs) | throwaway vault secret in `.key` (gitignored, mode 600), owner address in `.owner-address` |
| [schema.md](schema.md), [friction.md](friction.md), [reach.md](reach.md), [why-arkiv.md](why-arkiv.md), [how-you-use-arkiv.md](how-you-use-arkiv.md) | ETHGlobal Mumbai judging files |

```bash
npm install
node keygen.mjs    # once
node vectors.mjs   # offline; exits 1 if our bytes and the SDK's differ
node ref.mjs       # needs tGLM on the owner address for the write steps (faucet: https://hub.arkiv.network/faucet)
```

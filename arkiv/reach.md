# Reach

**ARPIT: every number marked ⟨…⟩ is yours to fill in. Nothing here is a guess.**

## Who uses Glyf today

Glyf is an AI keyboard for iPhone and Android: instant answers in the suggestion strip, AI on a held space bar, a Vault of saved details and shorthand, and a wallet. Site: https://www.tryglyf.com.

| | Number | Source |
|---|---|---|
| TestFlight build | 20 is out | docs/GO-TO-MARKET.md |
| Google Play | closed testing running | docs/GO-TO-MARKET.md |
| TestFlight testers | ⟨ARPIT⟩ | App Store Connect |
| Play testers | ⟨ARPIT⟩ | Play Console |
| Website waitlist signups | ⟨ARPIT⟩ | Neon `waitlist` table |
| Weekly active keyboards | ⟨ARPIT⟩ | telemetry funnel |
| People with at least one Vault item | ⟨ARPIT⟩ | telemetry `vault_field_saved` |
| Average Vault items per person | ⟨ARPIT⟩ | telemetry |

## Will they use the Arkiv part

The Vault is the part of Glyf people fill once and use every day (address, email, wallet address, shorthand like `;addr`). Today it lives only on the phone, so a new phone means typing it all in again. "Restore your Vault" on a new phone is the user-visible feature Arkiv powers: sign in on the new phone, iCloud Keychain brings the vault secret, Glyf reads the encrypted items back from Arkiv and the keyboard has everything again.

Who sees it: everyone with Vault items who sets up a second device or replaces a phone. ⟨ARPIT: share of testers with more than one device, if known.⟩

## Does it ship after Mumbai

- **During Mumbai:** the format, reference code, live-node checks and test vectors are done in `arkiv/`. ⟨ARPIT: state whether the app's Backup/Restore screens shipped in the demo build, and the build number.⟩
- **After Mumbai:** ⟨ARPIT decides⟩
  1. ship backup as an opt-in in TestFlight/Play testing on Rabdi (testnet) with a Glyf tGLM drip for each tester's owner address;
  2. add the Android key path (Block Store) and the typed backup code for iPhone ↔ Android moves;
  3. move to Arkiv mainnet when it exists, with gas sponsorship sorted (see friction.md §4).
- **What would stop it:** per-user gas with no sponsor (friction.md §4). Testnet data has no permanence guarantee, so testers are told it's a test backup.

## Links judges can check

- Writer address (demo): `0x76C58702b86004Aa820F58Ed5F1130Aa34B7E6F8` on https://rabdi.explorer.arkiv.network ⟨ARPIT: replace with the demo phone's owner address once it writes⟩
- Query: see [schema.md](schema.md#run-one)

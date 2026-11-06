# Glyf

AI keyboard for iPhone and Android. *Type less. glyf more.*

**Everything about the project (decisions, timeline, every part, open items, full chat history) is in [docs/README.md](docs/README.md).**

## ETHGlobal Mumbai (Continuity Track, 5–7 Nov 2026)

Type a trade in any chat and the keyboard places it: "sell my eth if it drops below 3000" is a Definitive Flash stop-loss, "swap 0.05 eth to usdc on base" is a Uniswap swap, and the keyboard's AI runs privately on 0G. The judges' guide is [docs/ETHGLOBAL-SUBMISSION.md](docs/ETHGLOBAL-SUBMISSION.md); the demo script is [docs/DEMO-SCRIPT.md](docs/DEMO-SCRIPT.md).

- **Before and during.** Before: commit `f42b9c0` (4 Nov 2026), Glyf as on TestFlight, with no EVM code, no Flash, no Uniswap and no 0G. During: every commit after it (`git log f42b9c0..main`), made on branch `ethglobal-mumbai` and merged into `main`.
- **Definitive Flash** (advanced orders on Base and Solana):
  - trades read in plain words, no AI: [TradeIntent.swift](app/ios/GlyfKeyboard/Engine/TradeIntent.swift);
  - quote, order, open orders, cancel, Solana setup: [server/src/routes/flash.ts#L249-L364](server/src/routes/flash.ts#L249-L364);
  - EVM signing (evmOrderTypedData, Permit2, brackets): [app/lib/evm/trade_flow.dart](app/lib/evm/trade_flow.dart);
  - Solana signing through Phantom, with Ed25519 checks: [app/lib/wallet/flash_solana.dart](app/lib/wallet/flash_solana.dart).
- **Uniswap** (swaps on Base, Ethereum, Arbitrum, Optimism and Unichain):
  - Trading API and v3 quoting (QuoterV2 over every fee tier in one Multicall3 call, two-pool routes) and SwapRouter02 calldata: [server/src/lib/uniswap.ts#L85-L243](server/src/lib/uniswap.ts#L85-L243);
  - routes: [server/src/routes/uniswap.ts#L252-L349](server/src/routes/uniswap.ts#L252-L349);
  - signing on the phone: [app/lib/evm/trade_flow.dart#L138](app/lib/evm/trade_flow.dart#L138);
  - feedback: [FEEDBACK.md](FEEDBACK.md).
- **0G Private Computer** (every AI call of this build, TEE-verified):
  - the X-Glyf-AI header, the receipts store and GET /ai/receipts: [server/src/lib/privateai.ts](server/src/lib/privateai.ts);
  - the 0G provider and its x_0g_trace: [server/src/providers/openrouter.ts#L22-L80](server/src/providers/openrouter.ts#L22-L80);
  - changelog: 6 Nov, Private AI on 0G with receipts; 6 Nov evening, AI action recommendations on 0G; next, Private AI as the default for everyone and 0G Storage for the encrypted vault backup.
- **Wallets:** the Glyf wallet (one 24-word phrase for Ethereum and Solana, [app/lib/wallet/hd_keys.dart](app/lib/wallet/hd_keys.dart)), MetaMask by deeplink ([app/lib/evm/metamask_link.dart](app/lib/evm/metamask_link.dart)) and Phantom by deeplink. No web pages and no WalletConnect relay.
- **How AI was used:** Glyf is built by Arpit with an AI coding assistant (Claude Code), and so was this work. Arpit chose the product, the partners, the UX rules and every trade-off, and tested on his iPhone; the assistant wrote most of the code and its unit tests to those instructions, read the partner docs, and checked the work on the simulator against live Flash, Uniswap and 0G endpoints. The plan and decisions are in [docs/ETHGLOBAL-MUMBAI.md](docs/ETHGLOBAL-MUMBAI.md) and [docs/DECISIONS.md](docs/DECISIONS.md).

**Design:** Apple-like and simple, no explainer lines. Apple-standard keyboard
metrics (260pt: 44 toolbar + 216 keys), liquid-glass keys by default, and the
keyboard follows the host's light or dark mode. The website has light and dark;
the apps get it later (this replaced the 12 Sep white-only lock). The accent
`#7C5CFF` appears only as the bound-key dot and small highlights, like the logo
(keycap `g`, concept 01 in `glyf-symbol-concepts.svg`, also the app icon).
Black pill CTAs. App shell: three tabs, Home · Build · Profile.

Full specification: [SPEC.md](SPEC.md). Work happens milestone by milestone
(M0 to M9, SPEC §9); each milestone has a hard acceptance gate.

## Status

| Milestone | State |
|---|---|
| **M0** — scaffold + spikes | ✅ done — [docs/SPIKES.md](docs/SPIKES.md), [docs/M0-GATE.md](docs/M0-GATE.md) |
| **M1** — daily-usable keyboard + onboarding | ✅ built & gate-tested on simulator — [docs/M1-M2-GATE.md](docs/M1-M2-GATE.md) (hardware re-verify pending) |
| **M2** — Glyf Bar + Glyf Keys + AI backend | ✅ built & gate-tested (mock + live OpenRouter) — same doc |
| **M3** — dictation (intent handoff + on-device speech + Raw/Clean/Formal) | ✅ built & gate-tested on simulator — [docs/M3-M4-GATE.md](docs/M3-M4-GATE.md) (real-mic device pass pending) |
| **M4** — vault & shorthand (encrypted, S-key picker, `;sig`) | ✅ built & gate-tested on simulator — same doc |
| **M5** — Builder + Hub + Packs + step engine + §6.13 map | ✅ built & gate-tested on simulator — [docs/M5-GATE.md](docs/M5-GATE.md) |
| **M6** — connectors | ✅ buildable core (keyless tools · ConnectorSurface on demo calendar · OAuth broker skeleton) — real providers blocked on OAuth client credentials, see same doc |
| **M7** — polish/perf/monetization | ✅ buildable core (paywall + pro flag · tone learning · telemetry sink · funnels) — StoreKit product + receipt validation at ship, see same doc |
| M8, crypto | a Phantom wallet (Glyf builds, Phantom signs, no keys held): Send, private sends, Jupiter buys, and Send/Buy chips in both keyboards (27 Sep 2026) |
| M9 — Android | built early by Arpit's call (13 Sep): Flutter app + Kotlin keyboard covering the main features, verified on the emulator, not published. The keyboard still trails iOS in places (see the parity table in [docs/APPS.md](docs/APPS.md)). Chaining UI and more languages still pending |
| Website | `site/`, the tryglyf.com waitlist site, built and verified locally, not deployed yet. See [docs/WEBSITE.md](docs/WEBSITE.md) |

Run the backend before using AI features:

```bash
cd server && npm run dev
```

## Repo map (SPEC §3)

```
app/                  Flutter container app (Dart package name: glyf)
app/ios/GlyfKeyboard/ native Swift keyboard extension — NO FLUTTER HERE, ever (§1.1)
app/android/          Android app + native Kotlin keyboard (IME)
server/               Fastify backend (AI, search, OAuth)
site/                 tryglyf.com website — Next.js; Vercel root directory, needs DATABASE_URL
shared/contracts/     JSON Schemas, single source of truth for cross-process payloads
shared/typing/        typing-engine dictionary format + golden test cases
ci/                   guard scripts (Flutter-free keyboard §1.1, no client secrets §1.6)
tools/                repo automation (Xcode target wiring, dictionary builder, contracts codegen, share image)
docs/                 project docs (start at docs/README.md), spike findings, milestone gate evidence
```

## Build & run (simulator — iPhone 17 Pro, SPEC §10)

```bash
cd app
flutter build ios --simulator --debug
xcrun simctl boot "iPhone 17 Pro"
xcrun simctl install booted build/ios/iphonesimulator/Runner.app
xcrun simctl launch booted com.arpit.glyf
```

Enable the keyboard once per simulator reset:
`Settings → General → Keyboard → Keyboards → Add New Keyboard → Glyf`
(then `Glyf → Allow Full Access` for the gated features).

Logs:

```bash
xcrun simctl spawn booted log stream --level=debug --predicate 'subsystem == "so.glyf.keyboard"'
```

## CI guards

```bash
ci/check_keyboard_clean.sh   # fails if the keyboard extension links/embeds Flutter
ci/check_no_secrets.sh       # fails on key-shaped strings in client/server source
```

`check_keyboard_clean.sh` also runs automatically as the "Glyf CI Guard" build
phase on every Runner build.

## Xcode project wiring

The GlyfKeyboard target is added by a reproducible script, not by hand:

```bash
tools/xcodeproj-env.sh tools/add_keyboard_target.rb
```

## Non-negotiables (SPEC §1 — read before writing code)

1. The keyboard extension is native Swift. Flutter never links into it.
2. The keyboard never holds keys, never signs, never broadcasts.
3. No secrets in any client bundle.
4. Everything must keep working with Full Access off (typing, layouts, local data).
5. Never rebind Return/Shift/Delete/globe; long-press is additive.

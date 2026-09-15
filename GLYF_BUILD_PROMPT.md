# GLYF — Build Specification (v2, complete)

> Keep as `SPEC.md` at repo root. Work milestone by milestone.
> **Do not attempt M0→M9 in one session.** Each milestone has a hard acceptance gate. Finish and verify one before starting the next.

---

## 0. MISSION

Build **Glyf** — an agentic AI keyboard for iOS (Android later) that replaces the system keyboard and turns any text field into an action surface.

The unit of action is a **Glyf**: one bindable action. Rewrite this. Translate it. Find that Notion doc. Drop a Meet link. Paste my address. Swap 0.5 SOL into BONK.

**Line:** *"Every key is a glyf."*

Four surfaces:
1. **Glyf Bar** — long-press space → run AI on the field contents
2. **Glyf Keys** — long-press any letter → fire the Glyf bound to it
3. **Glyf Builder** — describe an action in plain English → runnable, bindable Glyf
4. **Dictation** — speak anywhere you type

Plus **Connectors** (OAuth to the user's real accounts), a **Solana wallet** (Privy), and **swaps** (Jupiter) with our platform fee.

### 0.1 Competitive position — read this once
We are building against **Acti** (Singapore, $5.3M seed led by BITKRAFT, launched June 2026, Gemini-backed). Most of this spec is **parity work**. Be honest about that internally.

What they already ship: Acti Bar, Skill Keys, Skill Builder, Skill Hub with a creator community, persona packs, AI Dictation, "Liquid Glass" design, OAuth connectors (Gmail/Slack/Notion/Calendar), a 150+ keyless API library, multi-language, free tier with planned subscription.

What their founder has publicly confirmed they **do not** have: layered workflows / conditional actions in Skills, and context/memory in Skills. Plus they have no wallet — their "Crypto Degen" pack reads prices, it doesn't move money.

**Our four real edges:** Glyf chaining with conditionals · per-contact memory and tone learning · the crypto execution layer (shipped as an optional connector, post-v1) · paste-guard security. Everything else on this list is table stakes.

---

## 1. NON-NEGOTIABLE CONSTRAINTS — READ BEFORE WRITING ANY CODE

### 1.1 Flutter cannot render the iOS keyboard
iOS keyboard extensions are memory-capped at roughly **40–70 MB**. Flutter's own guidance: only use Flutter for extension UI where the limit exceeds 100 MB (share extensions, 120 MB). **The keyboard extension is native Swift. Period.**

- Flutter app and keyboard extension are **separate processes**.
- Platform channels **do not** work between them.
- `Flutter.framework` must **never** link into the keyboard target. CI fails the build if it does.

### 1.2 The keyboard cannot read the conversation
`UITextDocumentProxy` exposes only the attached field — not the chat above it. Every feature must source input from: typed field content, the clipboard (needs Full Access), or explicit selection. Design around this; do not build screen-reading.

### 1.3 Full Access required, but the keyboard must work without it
Apple 4.4.1 requires keyboards to remain functional without full access.
- **Works OFF:** typing, layouts, autocorrect, emoji, local snippets, vault (local), clipboard (local).
- **Gated ON:** AI, connectors, dictation, crypto, sync.

### 1.4 Do not repurpose standard keys in a banned way
4.4.1 prohibits repurposing keys (its example: hold Return to launch camera). Mitigation:
- Long-press is **additive**. Release early or with nothing bound → types the letter.
- Space long-press opens the Glyf Bar **inside the keyboard frame**; tap still inserts a space.
- Never rebind Return, Shift, Delete, or the globe key. Globe must always work.

### 1.5 The keyboard NEVER holds keys and NEVER signs
Single most important rule in the codebase.
- Private keys live only in the Flutter app via Privy.
- Keyboard builds an **unsigned intent**, writes it to the App Group, hands off.
- App simulates, requires Face ID, signs, executes, writes back a result.
- Keyboard reads the result and pastes a link.

A signing keyboard is a prompt-injection pipeline attached to a wallet. Someone will craft a tweet designed to make our parser resolve to their contract. Architecture must make that structurally impossible.

### 1.6 No secrets in any client bundle
OpenRouter keys, Jupiter keys, RPC creds, and **all OAuth tokens** live on the backend only. Clients hold opaque IDs. CI greps `ios/` and `lib/` for known key prefixes and fails on a hit.

---

## 2. STACK (PINNED)

| Layer | Choice | Notes |
|---|---|---|
| Container app | Flutter 3.27+ / Dart 3.x | onboarding, vault, builder, hub, connectors, wallet, confirm sheets |
| iOS keyboard | Swift 5.9+, UIKit, `UIInputViewController` | KeyboardKit optional for layout boilerplate |
| Android keyboard | Kotlin `InputMethodService` | **M9 only — do not start until iOS ships** |
| Wallet | `privy_flutter` | Solana embedded wallet |
| Swaps | Jupiter Swap V2 `https://api.jup.ag/swap/v2` | `/order` → sign → `/execute`, `x-api-key` header |
| AI | OpenRouter (OpenAI-compatible) | backend only, never from device |
| OAuth broker | Backend, `@fastify/oauth2` or Arctic | tokens server-side only |
| Backend | Node 20 + Fastify + TypeScript + Postgres | local in dev |
| Shared store | App Group + shared SQLite | `group.so.glyf.shared` |
| Secrets | Keychain access group | `$(AppIdentifierPrefix)so.glyf.shared` |
| Payments | StoreKit 2 | in Flutter app only |

### 2.1 Privy caveat — verify in M0, not M5
The Privy Flutter SDK documents `signMessage` for Solana but **not `signTransaction`**; broadcasting is listed as Ethereum-only. SDK is young (0.10.x).

**Spike B:** create a Solana wallet, attempt to sign a real serialized transaction. If Flutter can't, bridge the native Privy iOS SDK over a platform channel. Answer this before M5.

### 2.2 Jupiter caveat
Jupiter is **mainnet-only**. No devnet.
- Build a `SwapProvider` interface: `JupiterSwapProvider` + `MockSwapProvider`.
- All simulator work uses the mock — deterministic quotes, fake signatures, simulated latency and failures.
- Live swaps only behind `--dart-define=GLYF_LIVE_SWAPS=true`, real device, tiny amounts.

---

## 3. REPO STRUCTURE

```
glyf/
├── SPEC.md
├── app/                                  # Flutter container app
│   ├── lib/
│   │   ├── core/          # theme, tokens, router, result types
│   │   ├── onboarding/    # install → enable → full access funnel
│   │   ├── vault/         # personal info + shorthand snippets
│   │   ├── builder/       # Glyf Builder incl. chain editor
│   │   ├── hub/           # browse / install / publish / creator profiles
│   │   ├── connectors/    # OAuth link + revoke UI
│   │   ├── packs/         # persona bundles
│   │   ├── wallet/        # Privy, balances, address book
│   │   ├── confirm/       # tx simulation + Face ID sheet
│   │   ├── dictation/     # mic capture sheet
│   │   ├── paywall/       # StoreKit 2
│   │   ├── bridge/        # App Group I/O, deep links
│   │   └── api/           # backend client
│   └── ios/
│       ├── Runner/
│       └── GlyfKeyboard/                 # Swift extension target
│           ├── GlyfKeyboardViewController.swift
│           ├── Layout/                   # key grid, rows, accent popups
│           ├── Engine/                   # autocorrect, candidates, shorthand
│           ├── Surfaces/                 # GlyfBar, KeyPopup, ResultStrip, HUD
│           ├── Bridge/                   # AppGroupStore, IntentWriter, HostAppOpener
│           ├── Design/                   # GlassTokens.swift
│           └── Info.plist                # RequestsOpenAccess = YES
├── server/
│   ├── src/routes/{glyf,builder,hub,connectors,oauth,swap,risk,meter,health}.ts
│   ├── src/providers/{openrouter,jupiter,solana,risk,storekit}.ts
│   ├── src/registry/tools/*.json         # keyless API + OAuth tool registry
│   └── src/schemas/                      # zod, generated from shared/contracts
└── shared/
    └── contracts/                        # JSON Schema — single source of truth
```

Generate Swift structs and Dart classes from `shared/contracts/`. **Never hand-write both sides.**

---

## 4. PROCESS MODEL & DATA FLOW

```
┌──────────────────────┐        ┌───────────────────────┐
│ GlyfKeyboard (Swift) │        │ Glyf App (Flutter)    │
│ separate process     │        │ holds Privy keys      │
│ ~50MB budget         │        │ no memory limit       │
└──────────┬───────────┘        └───────────┬───────────┘
           │      App Group container       │
           │      group.so.glyf.shared      │
           │  ┌──────────────────────────┐  │
           └─►│ intents/ results/ vault/ │◄─┘
              │ glyfs/ bindings/ packs/  │
              └──────────────────────────┘
                          │
                 deep link handoff
                 glyf://intent?id=<uuid>
                          │
        ┌─────────────────▼──────────────────┐
        │ Backend (Fastify + Postgres)       │
        │ OpenRouter · OAuth broker · Tools  │
        │ Jupiter · Risk · Metering          │
        └────────────────────────────────────┘
```

**Fast path** (rewrite, translate, emoji): keyboard → backend → keyboard. Target < 1.5s, streaming.
**Connector path** (Notion, Calendar, Gmail): keyboard → backend → OAuth tool call → keyboard. Target < 2.5s.
**Value path** (swap, send): keyboard → backend quote → preview → confirm → intent → app → simulate → Face ID → sign → execute → result → keyboard pastes link.
**Dictation path**: keyboard mic → app records → transcribe + clean → result → keyboard inserts.

### 4.1 The handoff problem — solve in M0
Keyboard extensions cannot call `UIApplication.shared.open()`. The responder-chain workaround is fragile and carries review risk. **Three features depend on it: swaps, sends, and dictation.**

**M0 Spike A deliverable:** working `HostAppOpener`, plus a documented fallback UX ("Open Glyf to continue" card with intent ID on the clipboard). Decide before building anything downstream.

---

## 5. DESIGN LANGUAGE — TRANSPARENT GLASSMORPHIC

Simple, calm, one accent. Frosted glass over the user's wallpaper.

> **Reality check:** Acti already ships a full overhaul they call "Liquid Glass Design." Glass is **parity, not differentiation.** We win on frame rate, key feel, haptics, and how fast the Glyf Bar opens — not on translucency itself.

### 5.1 Tokens (`GlassTokens.swift` + Dart mirror)

```
glass.base        UIBlurEffect(.systemThinMaterial)
glass.raised      UIBlurEffect(.systemMaterial)
glass.overlay     UIBlurEffect(.systemThickMaterial)

fill.key          white 18% (dark) / white 62% (light)
fill.keyPressed   white 34% / white 88%
fill.keyGlyf      accent 16%          // key with a Glyf bound
fill.bar          white 10% / white 45%

stroke.hairline   white 12%, 0.5pt
stroke.focus      accent 60%, 1pt

accent.primary    #7C5CFF
accent.success    #32D583
accent.warning    #FDB022
accent.danger     #F04438

text.primary      label
text.secondary    secondaryLabel

radius.key        10pt
radius.card       18pt
radius.sheet      28pt
spacing.unit      4pt      (all spacing = multiples)
shadow.key        y:1 blur:2 black 8%
```

### 5.2 Rules
- **One blur layer per surface, never per key.** One `UIVisualEffectView` behind the whole keyboard; translucent fills on top. Per-key blur drops frames — the most common mistake in glass keyboards.
- No gradients, no inner shadows. Fills + hairline strokes only.
- Motion 180ms `easeOut`. Press scales 0.96 and brightens. Nothing bounces.
- Bound keys show a 2pt accent dot, top-right. Only decoration permitted.
- Honour `isReduceTransparencyEnabled` → solid fills. Honour `isReduceMotionEnabled` → no scale.
- Dark and light both first-class.
- Keyboard height: standard portrait. Glyf Bar expands to standard + 96pt, animated. Translation HUD adds a 44pt strip above.

### 5.3 Signature motion — the hold ripple
The one piece of motion the product is known for. Long-press a bound key → a purple ripple crosses the whole board → the surface opens.

**Timeline (defaults, all tunable via remote config):**

| t | Event |
|---|---|
| 0ms | Press begins. Key scales to 0.96, brightens to `fill.keyPressed`. |
| 0–320ms | **Charge ring** — a 2pt accent stroke contracts from 1.18× onto the key edge over the hold threshold, so the user can *see* the long-press arming. Releasing before 320ms cancels and types the letter. |
| 320ms | **Ignition.** Medium impact haptic. Origin key goes solid accent. |
| 320ms+ | **Propagation.** Each key tints accent then fades, delayed by `distance × 22ms` from the origin. Individual key tint: 150ms in/out. Board crossed in ~380ms. |
| 380ms | **Surface begins rising** — 60ms after ignition, not after the ripple finishes. It must feel *caused by* the ripple, not queued behind it. |

**Implementation — this matters more than the numbers:**
- Do **not** animate a real expanding radial gradient layer over the blurred backdrop. That forces offscreen compositing every frame and will drop frames inside a 45 MB extension.
- Implement as **staggered per-key tint**: precompute each key's distance from every other key once at layout time into a lookup table, then fire ~30 `CABasicAnimation`s on `backgroundColor` with staggered `beginTime`. Cheap, no rasterization, no offscreen passes.
- The lookup table is rebuilt only on layout change (rotation, layout switch), never per press.
- Ripple runs on the key layer only. The blur backdrop is never touched.

**Accessibility:** `isReduceMotionEnabled` → no ripple, no charge ring. Keep the haptic and a 120ms origin-key flash, then open the surface. The interaction must remain fully legible without motion.

**Reuse:** the same ripple fires from toolbar buttons and from the Glyf Bar on space long-press, with the origin set to the tapped element. One implementation, every entry point.

**Prototype:** `glyf-ripple-prototype.html` in the repo has the tuned timings and a control panel. Match it, then adjust from device testing.

### 5.4 Typography
System font only — custom fonts cost memory we don't have. Keys 22pt regular, results 15pt, labels 13pt medium.

---

## 6. FEATURE SPECIFICATION

### 6.1 Base keyboard — Gboard parity (M1)
Must feel like a *good keyboard* before it feels like an AI product. If typing is worse than stock, nothing else matters.

- QWERTY; letters / numbers / symbols layouts; shift + caps lock
- Long-press accents rendered **inside the keyboard frame** (extensions cannot draw outside bounds)
- Delete with accelerating repeat
- Autocorrect + 3-candidate strip; tap a corrected word to undo
- Emoji keyboard: recents, search, skin tones
- **Clipboard manager**: last 20, pinnable, 1h expiry unless pinned, App Group storage. Detect and refuse to store anything matching password / card / seed patterns.
- Number row toggle; one-handed mode; haptics toggle
- Space-swipe cursor control
- Globe key → next keyboard
- Dark/light auto

**Out of scope v1:** swipe/glide typing, handwriting.

### 6.2 Glyf Toolbar — the top strip (M1)
A persistent strip above the key grid, like Gboard's. 44pt tall. **This is the entry point to everything.**

Layout, left to right:
- **Glyf button** (accent, always leftmost) — opens the in-keyboard shell (§6.5)
- Divider hairline
- **Clipboard** · **Vault** · **Dictation (mic)** · **Emoji** · **Translation HUD toggle** · **Settings gear**
- Right edge: **remaining-runs chip** when the free cap is low, otherwise nothing

Rules:
- Horizontally scrollable if items overflow; never wraps, never shrinks icons below 20pt
- Icons are SF Symbols at 20pt. No custom art — memory.
- User reorders and hides items from Settings. Order persists in the App Group.
- When autocorrect candidates are showing, the toolbar **collapses to the Glyf button only** and candidates take the rest of the strip. Tapping the Glyf button restores the toolbar. Do not stack two strips — that steals too much screen.
- Long-press any toolbar item → its settings page inside the shell

### 6.3 In-keyboard shell — everything renders inside the frame (M1 chrome, filled through M6)
**Principle: the user should never have to leave the keyboard.** Settings, calendar, mail, Notion, vault, bindings, connector lists — all of it renders inside the keyboard frame. Opening the container app is an escape hatch, not the path.

**`GlyfShell`** — a lightweight navigation stack living inside the extension.

- Height: standard keyboard + 140pt when open, animated 180ms
- Chrome: back chevron (left) · title (center) · close ✕ (right), 36pt header
- Body: one scrollable content region, rows 44pt
- Footer when relevant: **`Open in Glyf app ↗`** — deep links out for anything the shell can't do
- Hardware back behaviour: back pops the stack; at root, closes the shell and returns to keys
- State survives keyboard dismissal for 60s — reopening returns to the same screen

**Screens that must render in-shell:**

| Screen | Contents |
|---|---|
| Root | Glyfs · Connectors · Vault · Clipboard · Packs · Settings · Account |
| Glyf Keys | keyboard diagram, tap a key to rebind, live preview |
| Glyf list | installed Glyfs, search, toggle, reorder |
| Connectors | connected accounts, status, reconnect, disconnect |
| Vault | browse and insert fields; **add/edit opens the app** |
| Clipboard | history, pin, clear |
| Packs | switch pack, see key diff |
| Settings | haptics, number row, one-handed, autocorrect, toolbar order, theme, language |
| Account | plan, runs remaining, upgrade → **opens app** (never sell inside the extension) |
| Calendar / Mail / Notion / Drive / Contacts | full ConnectorSurface pickers (§6.13) |

**What must NOT render in-shell** — hard rules, not preferences:
- Anything requiring the microphone → app (extension has no mic access)
- Anything requiring signing or Face ID → app
- Any purchase or paywall → app (Apple dislikes commerce UI in extensions)
- OAuth consent flows → app (needs a real browser and URL bar for user verification)
- Free-text secret entry (adding vault items, passwords) → app

**Memory discipline — this is the risk in this whole feature:**
A navigation stack inside a 45 MB budget is how keyboards die. Enforce:
- One reusable `UITableView`, never one per screen
- Screens are data, not view controllers — a `ShellScreen` struct describing rows, rendered by a single renderer
- Pop = discard the data, not tear down a VC tree
- No images beyond 20pt SF Symbols anywhere in the shell
- **Budget: the entire shell adds no more than 6 MB.** Add an automated test that fails the build if it exceeds that.

### 6.4 Glyf Bar (M2)
Long-press space → overlay rises inside the keyboard frame.

- Input: field content via `documentContextBeforeInput`/`After`, else clipboard
- Prompt field + horizontal row of quick Glyfs + remaining-runs chip when low
- Result in a **preview strip**: `Replace` · `Insert` · `Copy`. **Never auto-inserts.**
- Streaming tokens so it feels instant
- Quiet inline failure: "Couldn't reach Glyf. Tap to retry."

### 6.5 Glyf Keys (M2)
Long-press a letter → run bound Glyf; if none, show accents normally.

- Threshold 320ms. Below that, types the letter.
- Binding UI in the Flutter app: keyboard diagram, tap a key to bind
- Accent dot on bound keys; haptic on fire

### 6.6 Dictation (M3) — PARITY, MANDATORY
Acti ships "AI Dictation: Speak naturally anywhere you type." **Keyboard extensions cannot access the microphone.**

Two paths, in preference order:
1. **In-app capture + handoff.** Mic button → opens container app in a minimal recording sheet → transcribe → write to App Group → return → insert. Depends on Spike A.
2. **System dictation passthrough.** Surface the system mic, then post-process the transcript through our cleanup model.

**Post-processing is the product**, not transcription: strip filler words, fix punctuation and casing, apply the user's tone profile. Ship a `Raw / Clean / Formal` toggle. Wispr raised $280M at a $2B valuation on exactly this — treat it as first-class.

### 6.7 Vault & Shorthand (M4)
The feature users open the app for daily. Acti doesn't have it.

**Vault** — preset personal info, encrypted in App Group, Keychain-backed.
Fields: name, emails, phone, addresses, UPI ID, GST, wallet addresses, Calendly, socials, bio blurb, standard replies. Multi-field combos ("Shipping block" = name + address + phone, one tap).
Long-press `S` → picker → types it.

**Shorthand** — plain-prefix snippets. `;addr`, `;sig`, `;wa`. Inline expansion with undo. Prefix triggers only; predictable beats clever.

**Hard-blocked from the vault:** passwords, card numbers, seed phrases, government ID numbers. Refuse at input with an explanation.

### 6.8 Glyf Builder (M5)
Plain language → runnable Glyf. Lives in the Flutter app.

**The schema supports chaining and conditionals from day one** — this is our differentiator, and Acti's founder has publicly confirmed they don't have it. Even if the visual chain editor lands in M8, the format must support it now or we'll rewrite everything later.

```jsonc
{
  "id": "glyf_7x2k",
  "version": 1,
  "name": "Hindi casual",
  "icon": "translate",
  "input": "field | clipboard | selection | none",
  "requires": {
    "fullAccess": true,
    "connectors": ["notion"],
    "wallet": false
  },
  "discloses": ["the text in your current field", "your Notion workspace"],
  "vars": { "tone": "casual" },
  "steps": [
    { "id": "s1", "type": "llm",  "prompt": "...", "model": "fast", "out": "draft" },
    { "id": "s2", "type": "tool", "tool": "notion.search", "args": { "query": "{{draft}}" }, "out": "docs" },
    { "id": "s3", "type": "if",   "cond": "{{docs.length}} > 0",
                  "then": ["s4"], "else": ["s5"] },
    { "id": "s4", "type": "format", "template": "{{docs.0.title}} — {{docs.0.url}}", "out": "final" },
    { "id": "s5", "type": "format", "template": "No match found", "out": "final" }
  ],
  "output": { "mode": "replace | insert | copy | preview | hud", "from": "final" }
}
```

Step types: `llm` · `tool` · `format` · `if` · `map` · `ask` (prompt the user mid-chain).

- Builder flow: describe → preview generated definition → **test run with sample input** → name → bind or save
- Show the steps; let power users edit prompts and conditions directly
- `tool` steps resolve only against the server-side registry (§6.11). **No arbitrary URL fetching from user-authored Glyfs** — that is an exfiltration vector.
- Every Glyf must carry `discloses`, rendered verbatim before install.

### 6.9 Glyf Hub (M5)
- Browse, search, install. Categories: Writing, Social, Productivity, Crypto, Finance, Sports, Fun.
- Per Glyf: name, author, install count, description, **permission disclosure**
- **Creator profiles** with total Glyfs and total installs — Acti runs a visible creator leaderboard and it drives their supply side. Match it.
- Publish: private by default, one tap to publish
- Server-side moderation queue. Auto-reject any Glyf whose steps read vault or wallet data and send it to a non-registry destination.
- Versioning: installed Glyfs pin a version; updates require re-consent if `discloses` changed.

### 6.10 Packs (personas) (M5)
One-tap bundles that rebind the keyboard. Ship:
- **Writer** — rewrite, tighten, tone shift, grammar, expand
- **Operator** — meet link, calendar, summarize, action items, follow-up
- **Social** — reply drafts, hook rewrites, emoji-fy, thread splitter
- **Trader** — price, risk check, swap, portfolio, chart link
- **Desi** — Hinglish↔English, formal Hindi, UPI request, address block

Switching shows a brief overlay of what changed.

### 6.11 Connectors — OAuth + keyless API registry (M6) — DO NOT SKIP
Acti connects two ways: users link their own accounts via **secure OAuth (Gmail, Slack, Notion, Calendar and more)**, or tap a library of **150+ prebuilt APIs with no setup**. Their store copy promises summoning **Notion docs, LinkedIn profiles, Meet links, and Calendar actions**.

Without this, a Glyf can only transform text — it can never reach the user's real data. This is the largest single module in the spec.

**OAuth broker (backend-owned):**
- Tokens stored **server-side only**. Never on device, never in the App Group.
- Device holds an opaque `connectionId`. Keyboard sends `connectionId`, never a token.
- Launch set: Google (Gmail, Calendar, Drive, Meet, Contacts), Notion, Slack, Linear, Calendly, GitHub
- Scope minimisation — read-only unless a Glyf needs write; escalate with a fresh consent screen
- Refresh handling server-side; on revocation, Glyfs fail with a clean "Reconnect Notion" state
- Revocation UI in the app: per connector, with last-used timestamp and a scope list

**Keyless API registry:** public APIs needing no user auth — weather, sports fixtures and odds, stock and crypto quotes, places/nearby search, currency conversion, URL unfurl, translation, location links. Exposed to the Builder as named tools so a user can say "get the weather for {city}" without knowing what an API is.

**Registry entry** (`server/src/registry/tools/*.json`):
```jsonc
{
  "id": "notion.search",
  "label": "Search Notion",
  "auth": "oauth:notion",
  "inputs": [{ "name": "query", "type": "string", "required": true }],
  "output": "list<{title,url,lastEdited}>",
  "scopes": ["read_content"],
  "discloses": "your Notion workspace content",
  "rateLimit": { "perMin": 20 },
  "timeoutMs": 4000
}
```

`discloses` is rendered verbatim in the install sheet. Every tool must have one. A tool without a disclosure string fails schema validation and cannot ship.

**Target registry size:** 30 quality tools at launch beats 150 shallow ones. Expand from telemetry on what users try to build.

### 6.12 Connector Surfaces — in-keyboard pickers (M6)
A connector Glyf must not be a blind one-shot. Long-pressing `C` should **open a calendar inside the keyboard**, let the user browse and pick, then insert. Same for mail, Notion, Drive, Slack, contacts.

This is a distinct UI primitive from the Glyf Bar. Build it once, reuse it for every connector.

**`ConnectorSurface` spec:**
- Rises inside the keyboard frame, same glass treatment as the Glyf Bar, standard height + 140pt
- Three zones: **search field** (top, 36pt) · **result list** (scrollable, rows 44pt) · **action bar** (bottom, 36pt)
- Opens with a **default query already run** — never an empty state. Calendar opens on today. Mail opens on unread. Notion opens on recently edited.
- Type to filter; results refresh debounced at 250ms
- Tap a row → **insert menu**: `Link` · `Title + link` · `Summary` · `Full details`. Remember the user's last choice per connector.
- Long-press a row → preview card (event time and attendees, email subject and snippet, doc excerpt)
- Action bar holds connector-specific verbs: Calendar → `New event from my text`; Mail → `Draft reply`; Notion → `New page from my text`
- Not connected → single row: "Connect Google to use this" → deep links to the app's connector screen
- Token expired → "Reconnect Google", never a raw error
- Offline / Full Access off → explain which, in one line

**Performance budget:** surface visible in under 120ms with cached results, live results in under 1.2s. Cache the last successful result set per connector for 5 minutes so reopening feels instant.

**Memory:** the list is a plain `UITableView` with cell reuse. No images beyond 16pt SF Symbols. This surface must not add more than 4 MB to the extension footprint — measure it.

### 6.13 Shipped Glyf catalog (M5–M6)
Ship all of these as **real Glyf definitions in the Hub, not hard-coded Swift.** Acti makes this point explicitly — their actions "aren't features Acti hard-coded, each one is a Skill." Same rule here: if a default Glyf can't be expressed in our Builder format, the format is wrong.

★ = direct parity with Acti's published catalog. 🔌 = opens a ConnectorSurface picker.

**Integration keys — the daily drivers**

| Key | Glyf | Behaviour |
|---|---|---|
| `C` | **Calendar** 🔌 ★ | opens on today's agenda; search events; insert time/link/details; action bar: create event from typed text |
| `G` | **Gmail** 🔌 | opens on unread; search mail; insert thread link or summary; action bar: draft a reply to the selected thread |
| `N` | **Notion Summon** 🔌 ★ | opens on recently edited; search docs; insert title + link; action bar: new page from typed text |
| `D` | **Drive** 🔌 | opens on recent files; search; insert share link |
| `K` | **Slack** 🔌 | search channels and messages; insert permalink |
| `M` | **Meet link** ★ | instant — no picker, one tap, drops a fresh Meet link |
| `I` | **LinkedIn Summon** ★ | person name → profile link |
| `A` | **Contacts** 🔌 | search contacts; insert phone, email, or address |

**Text and AI keys**

| Key | Glyf | Behaviour |
|---|---|---|
| `T` | **Translation HUD** ★ | persistent 44pt strip above the keyboard while you type a reply — not a one-shot replace |
| `R` | **Humanize / Rewrite** ★ | tone picker: normal → professional → casual → Gen Z |
| `E` | **Emotion Detection** ★ | analyse mood of a copied message, return a reply strategy |
| `X` | **Super X Reply** ★ | copied X post link → reply draft in chosen tone |
| `J` | **Text to Emoji** ★ | rewrite the idea as emoji only |
| `B` | **Expand shorthand** | `;sig`, `;addr` style expansion |

**Data and utility keys**

| Key | Glyf | Behaviour |
|---|---|---|
| `V` | **Clipboard history** | `V` for paste — keyboard convention. Last 20, pinnable. |
| `S` | **Share My Info** | vault picker: name, email, address, UPI, GST, socials |
| `Q` | **Quote lookup** ★ | ticker → price, trend, related (stocks + crypto) |
| `L` | **Share location** ★ | drop a location link instantly |
| `F` | **Fixtures & odds** ★ | live sports schedule / odds snapshot |
| `O` | **Nearby** ★ | "best Italian near me" → places with links |

**Free by default** — `W` Weather (keyless API) · `P` Proofread (grammar only, distinct from Rewrite) · `Z` unbound

**Crypto keys — only exist once the Crypto connector is enabled (§6.14)**

| Key | Glyf | Behaviour |
|---|---|---|
| `W` | **Wallet address** | replaces Weather when Crypto is on |
| `P` | **Price + risk scan** | replaces Proofread when Crypto is on |
| `Z` | **Swap** | opens the swap composer |

Enabling the Crypto connector installs the Trader pack and rebinds these three keys, with a one-screen diff shown to the user. Disabling it restores the defaults and removes the keys entirely.

Users rebind anything. This is the shipped default map, and Packs (§6.10) rebind subsets of it in one tap.

### 6.14 Crypto Connector — OPTIONAL MODULE (M8, separate release)

**Crypto is a connector, not a core feature.** It is off by default, invisible to users who never enable it, and ships in a release *after* v1.0 is on the App Store.

**Why this is the right call:**
- **Review risk is quarantined.** Guideline 3.1.5(b)(iii) requires exchange services be offered only where you hold appropriate licensing, and the rejection letter demands documentary evidence of licensing per country, third-party exchange API details, and AML/KYC precautions. Uniswap needed a month and a rejected build to get through. Keeping crypto out of the v1.0 binary means the keyboard itself never waits on that.
- **Most users don't want a wallet in their keyboard.** Surfacing one to them is a trust cost, not a feature.
- **Geo-gating becomes trivial.** Enable per region as licensing allows. Jupiter blocks U.S. users under its own terms regardless.

**What "optional" does and does not mean on iOS — read carefully:**
- iOS forbids downloading executable code at runtime. The wallet **cannot** be dynamically fetched. It is compiled into the binary and **feature-flagged off**, served by a remote config flag plus a local user toggle.
- Apple reviews the whole binary regardless of flags. So the crypto release is still a full 3.1.5 review — it is just decoupled from v1.0's timeline.
- Consequence: **do not link the Privy SDK until M8.** Once linked it affects app size and review scope permanently. Keep it behind a Swift Package that is only added in the crypto release branch.

**Enabling flow:** Settings → Connectors → Crypto → explain custody, fees, and risk in plain language → age/region check → Privy login → wallet created → Trader pack installed → key diff shown.

#### 6.14.1 Wallet
- Privy embedded Solana wallet, email/OAuth login
- Balances, token list, portfolio value
- Receive: address + QR; one-tap paste from keyboard
- Address book with SNS (`.sol`) resolution — `@arpit` resolves
- **Paste guard:** when the clipboard holds a Solana address, verify against the address book and warn on mismatch. Clipboard-swap malware is real; no keyboard ships this defence.

#### 6.14.2 Swap
1. Keyboard detects intent — typed (`swap 0.5 sol to bonk`) or from clipboard (pasted CA or tweet)
2. Backend: resolve token → **risk scan** → Jupiter `GET /order`
3. Keyboard preview card: in/out, price impact, route, **our fee**, risk flags
4. `Confirm` → intent written → app opens
5. App: full simulation → Face ID → Privy signs
6. Backend `POST /execute` → signature
7. Result written → keyboard pastes the Solscan link

**Risk scan** before every preview, shown inline: mint/freeze authority active, LP locked or burned, top-holder concentration, token age, honeypot heuristics. Pluggable `RiskProvider` interface.

**Our fee:** Jupiter integrator fees are 5–10 bps and we keep 80%. Config constant `GLYF_FEE_BPS`, default 10. **Always display the fee in the preview.** Hidden fees on a keyboard that reads your messages is how you die.

### 6.15 Memory & tone learning (M8)
Acti's founder confirmed Skills **do not collect context or memory**. This is our opening.

- **Tone profile** learned from accepted vs rejected rewrites, stored **on device**
- **Per-recipient/app profiles**: the extension knows the host app in limited ways; combine with user labelling ("this is work")
- Feeds the `llm` step as a system-prompt fragment
- Fully inspectable and deletable in the app. A memory the user can't see is a liability.
- **Never syncs message content to the server.** Profiles are compact preference vectors, not transcripts.

### 6.16 Monetization (M8)
Acti is free with planned subscriptions for advanced models, higher daily limits, and premium features.

- **Free:** base keyboard, clipboard, vault, shorthand, N Glyf runs/day on a fast model
- **Glyf Pro:** unlimited runs, frontier models, unlimited custom Glyfs, connectors, cloud sync
- Metering server-side, keyed to account. Remaining-runs chip in the Glyf Bar when low.
- StoreKit 2 paywall **in the Flutter app only** — never commerce UI inside the extension
- Swap fees are a separate line; Pro does not waive them, and that is stated plainly
- **Because crypto ships after v1.0, subscription is the only revenue line at launch.** Model the business on Pro conversion alone; treat swap fees as upside that arrives a release later.

### 6.17 Languages (M9)
- **AI-side multilingual from day one** — translate/rewrite work in any language regardless of layout
- **Layout-side:** English QWERTY v1. Add Hindi (Devanagari + transliteration), Spanish, French, German, Portuguese, Indonesian in M9.
- **Hinglish code-switching cleanup** as a shipped default Glyf — underserved, and India is the largest keyboard market

### 6.18 Onboarding funnel (M1, refined throughout)
The highest-leverage screen in the product. Most keyboard apps die here.

1. Value screen — one animated demo of a Glyf firing
2. `Add Glyf to your keyboards` — deep link to Settings with an illustrated 3-step card
3. `Allow Full Access` — explain **exactly** what it does and what we never do (no keystroke logging, no message content off-device). This is the biggest drop-off; earn it with honesty, not urgency.
4. First-run binding: pick a Pack
5. First Glyf fire, in-app, in a sandbox field — user must feel it work before leaving the app

Instrument every step. Report the funnel weekly. **D1/D7/D30 retention of default-keyboard users is the only metric that decides whether this is a company.**

---

## 7. DATA CONTRACTS

`shared/contracts/` as JSON Schema. Generate both sides.

### 7.1 Intent (keyboard → app)
```jsonc
{
  "id": "uuid-v4",
  "version": 1,
  "createdAt": "ISO8601",
  "expiresAt": "ISO8601",          // 120s TTL, expired = refused
  "kind": "swap" | "send" | "sign_message" | "dictation",
  "origin": {
    "source": "typed" | "clipboard" | "glyf",
    "glyfId": "glyf_7x2k | null",
    "rawText": "string"             // exactly what the user saw
  },
  "payload": { /* kind-specific */ },
  "risk": { "score": 0, "flags": [] },
  "nonce": "random-32-bytes-base64"
}
```

### 7.2 Result (app → keyboard)
```jsonc
{
  "intentId": "uuid-v4",
  "status": "success" | "rejected" | "failed" | "expired",
  "payload": { /* signature + explorerUrl, or transcript */ },
  "error": { "code": "string", "message": "string" } | null,
  "completedAt": "ISO8601"
}
```

### 7.3 Rules
- Intents are **single-use**. App marks consumed; replay refused.
- Keyboard never writes anything signed.
- App **re-fetches its own quote** before signing; the intent's quote is used only to show the user what changed.
- TTL 120s, or the Jupiter quote TTL, whichever is shorter.

---

## 8. AI LAYER (OPENROUTER)

### 8.1 Access
- `https://openrouter.ai/api/v1/chat/completions`, OpenAI-compatible
- **Backend only.** Send `HTTP-Referer` and `X-Title` headers.

### 8.2 Free tier reality — plan around this
`:free` models cost $0/token but are **request-rate-limited**: 20 requests/minute always, and **50 requests/day on an unfunded account**, rising to **1,000/day once the account has ever purchased $10+**. Limits are account-wide, not per model; extra accounts don't help — capacity is governed globally.

**50/day blocks development on day one. Put $10 in the account.** Credits don't expire. Free models also rotate out without notice — never hard-code a single `:free` ID.

### 8.3 Model routing
`ModelRouter` with a fallback chain:
1. `openrouter/free` (Free Models Router, 200k context)
2. a named `:free` model
3. a cheap paid model behind a config flag

By task:
- **fast** (rewrite, tone, emoji, expand): smallest capable model, streaming
- **smart** (builder, intent parsing, risk summaries): largest free model available
- **strict** (anything producing a transaction intent): must return JSON validated against schema; one retry, then **fail closed**

### 8.4 Caching & dev ergonomics
- Cache on `hash(prompt + input + model)` for 24h — saves the rate limit during development
- `MOCK_AI=true` returns canned deterministic responses so UI work burns zero quota
- Log every call with latency and token counts in dev

---

## 9. BUILD MILESTONES

Strict order. Do not proceed past a failing gate.

> **Every gate in this section is verified on the `iPhone 17 Pro` simulator** using the commands in §10, unless the gate says otherwise. Do not mark a milestone complete without: (a) a screen recording of the gate flow captured via `xcrun simctl io booted recordVideo`, (b) the `GLYF_MEM` log line showing peak extension footprint, (c) the automated checks in §10.9 passing. Memory-sensitive gates must additionally be re-verified on physical hardware, because simulator memory behaviour does not match a device.

| # | Milestone | Days |
|---|---|---|
| M0 | Scaffold + two risky spikes | 1–2 |
| M1 | Keyboard good enough to use daily + onboarding | 5–7 |
| M2 | Glyf Bar + Glyf Keys + AI | 4–5 |
| M3 | Dictation | 3–4 |
| M4 | Vault & Shorthand | 3–4 |
| M5 | Builder + Hub + Packs + shipped catalog (non-connector) | 6–8 |
| M6 | Connectors (OAuth + registry) + connector Glyfs | 6–8 |
| M7 | Memory + monetization + polish → **v1.0 App Store submission** | 5–7 |
| M8 | Crypto connector (wallet + swap) — optional, **separate release** | 9–11 |
| M9 | Chaining UI, languages, then Android | ongoing |

### M0 — Scaffold & spikes
Flutter app + Swift extension in one Xcode project. App Group verified both directions. CI check for `Flutter.framework` in the keyboard target. Memory logging on every keyboard appearance.
- **Spike A:** `HostAppOpener` — can the extension open the app? Document result + fallback.
- **Spike B:** Privy Solana `signTransaction` — does it exist in Flutter? If not, wire native over a channel.

**Gate:** keyboard appears in simulator, types letters, writes a file the app reads. Both spikes answered in `docs/SPIKES.md`.

### M1 — Daily-usable keyboard
§6.1, §6.2, §6.3 (chrome only), §5, §6.18.
**Gate — all verified on the iPhone 17 Pro simulator, then re-verified on physical hardware:**
- Set Glyf as default; type 200 words in Notes without wanting to switch
- Toolbar renders, scrolls, collapses to the Glyf button when candidates show, and restores on tap
- Glyf button opens the shell; back/close work; state survives a 60s dismissal
- Extension under 45 MB throughout — shell contributes under 6 MB, measured
- No dropped frames on key press in either dark or light mode
- **Hold ripple** fires at 320ms with charge ring, crosses the board, and the surface starts rising 60ms after ignition — profiled in Instruments at a sustained 60fps with zero offscreen rendering passes
- Reduce Motion disables the ripple cleanly without breaking the interaction
- Onboarding funnel instrumented end to end

### M2 — Glyf Bar + Keys + AI
§6.2, §6.5, §8. Backend `/glyf/run` streaming.
**Gate:** Long-press space, "make this polite", result streams, Replace works. Long-press `T` translates. Degrades cleanly with Full Access off.

### M3 — Dictation
§6.6. Depends on Spike A.
**Gate:** Mic → record in app → clean transcript at cursor. Raw/Clean/Formal works. Under 4s for a 10s clip.

### M4 — Vault & Shorthand
§6.7.
**Gate:** Preset an address. Long-press `S` in Messages → pick → types. `;sig` expands inline. Blocked field types actually blocked.

### M5 — Builder, Hub, Packs
§6.8, §6.9, §6.10, and the non-connector half of §6.13.
**Gate:** Describe a Glyf, test-run, bind, fire from keyboard. Install from Hub with a permission sheet. Switch packs, bindings change. Translation HUD renders as a persistent strip.

### M6 — Connectors
§6.11, §6.12 + connector Glyfs from §6.13.
**Gate:** Link Google + Notion + Slack.
- Long-press `C` in Messages → calendar opens **on today's agenda**, visible in under 120ms → pick an event → insert time + link
- Long-press `G` → unread mail list → search → insert thread link → action bar drafts a reply
- Long-press `N` → recently edited Notion docs → search → insert title + link
- Long-press `D` → Drive recents → insert share link
- Long-press `A` → contact search → insert phone/email
- `M` drops a fresh Meet link with no picker
- Revoking Google in the app turns `C`, `G`, `D`, `A` into a clean "Reconnect Google" row, not an error
- Verify via proxy that **no OAuth token ever reaches the device**
- ConnectorSurface adds no more than 4 MB to the extension footprint

### M7 — Memory, monetization, v1.0 ship
§6.15, §6.16. Empty states, error states, App Store assets, privacy nutrition labels.
**No crypto code in this binary. Privy SDK not yet linked.**
**Gate:** Tone profile visibly changes a rewrite after 10 accepts. Free cap triggers the paywall cleanly. Full TestFlight pass on physical hardware with the 45 MB budget re-verified. **v1.0 submitted to App Store review.**

### M8 — Crypto connector (optional module, separate release)
§6.14. Link the Privy SDK on a dedicated branch. `MockSwapProvider` in simulator.
**Gate:**
- Crypto off by default; a fresh install shows no wallet UI anywhere
- Enable in Settings → Connectors → Crypto → custody/fee/risk explainer → Privy login → wallet created → Trader pack installed → key diff shown
- `W` pastes the address; `@name` resolves via SNS; paste guard fires on a mismatched address
- `swap 0.5 sol to bonk` → preview with risk flags and **visible fee** → confirm → app opens → simulation → Face ID → mock signature → Solscan link pasted
- Intent expiry and replay both refused
- Disabling the connector removes all three keys and restores Weather/Proofread
- Legal memo for 3.1.5 written **before** submission, not after rejection

### M9 — Chaining UI, languages, Android
§6.17, visual chain editor for §6.8 conditionals. **Only then** start Kotlin `InputMethodService`.

---

## 10. SIMULATOR TEST PLAN — iPhone 17 Pro (MANDATORY FOR EVERY MILESTONE)

Target device is **`iPhone 17 Pro`**. If that runtime is not installed, install it via `Xcode → Settings → Components` before starting — do not substitute another device and do not proceed without it.

### 10.1 Boot
```bash
xcrun simctl list devices | grep "iPhone 17 Pro"
xcrun simctl boot "iPhone 17 Pro"
open -a Simulator
```

### 10.2 Build & install
```bash
cd app
flutter build ios --simulator --debug
xcrun simctl install booted build/ios/iphonesimulator/Runner.app
xcrun simctl launch booted so.glyf.app
```
The extension ships inside the app bundle — installing the app installs the keyboard.

### 10.3 Enable the keyboard (manual, once per reset)
`Settings → General → Keyboard → Keyboards → Add New Keyboard → Glyf`, then `Glyf → Allow Full Access → Allow`.
```bash
xcrun simctl erase booted    # factory reset when state gets weird
```

### 10.4 Face ID
`Features → Face ID → Enrolled`, then `Features → Face ID → Matching Face` to approve.

### 10.5 Logs
```bash
xcrun simctl spawn booted log stream --level=debug \
  --predicate 'subsystem == "so.glyf.keyboard"'

xcrun simctl spawn booted log stream \
  --predicate 'eventMessage CONTAINS "GLYF_MEM"'
```

### 10.6 Deep links & OAuth callbacks
```bash
xcrun simctl openurl booted "glyf://intent?id=<uuid>"
xcrun simctl openurl booted "glyf://oauth/callback?code=<code>&state=<state>"
```

### 10.7 Capture
```bash
xcrun simctl io booted screenshot ~/Desktop/glyf.png
xcrun simctl io booted recordVideo ~/Desktop/glyf.mp4
```

### 10.8 Caveats
- Simulator memory behaviour **does not** match a real device; extension limits are enforced differently. **Re-verify M1's memory gate on physical hardware before believing it.**
- Clipboard behaves differently in simulator.
- Test dark/light and Reduce Transparency on/off.

### 10.9 Automated checks
- Unit: intent schema round-trip, TTL expiry, replay rejection, vault blocked-field rules
- Unit: Glyf step engine — `if` branching, `map`, var interpolation, tool timeout
- Unit: `MockSwapProvider` failure modes (quote expired, slippage exceeded, insufficient balance)
- Unit: registry schema — every tool has `discloses`, or the test fails
- Snapshot: layouts in light/dark, both transparency modes
- Budget guard: fails if measured extension footprint exceeds 45 MB
- Budget guard: fails if `GlyfShell` exceeds 6 MB or `ConnectorSurface` exceeds 4 MB
- Shell navigation: push/pop 20 screens in sequence, assert no view-controller growth and no memory climb
- Toolbar: collapse-on-candidates and restore-on-tap, in both orientations

---

## 11. SECURITY RULES — TREAT AS TESTS, NOT GUIDELINES

1. Keyboard never holds a key, never signs, never broadcasts.
2. No API keys or OAuth tokens in any client bundle. CI greps for key prefixes.
3. Vault refuses passwords, card numbers, seed phrases, government IDs.
4. Clipboard manager never persists password / card / seed patterns.
5. User-authored Glyfs cannot make arbitrary HTTP calls — server registry only.
6. Any Glyf touching vault, wallet, or a connector must declare it; declaration shown before install.
7. Every transaction intent is simulated and shown in human-readable form before Face ID.
8. Intents: single-use, 120s TTL, nonce-bound, replay-refused.
9. In `isSecureTextEntry` fields: all AI surfaces disabled, nothing sent, nothing logged, nothing cached.
10. Telemetry: never message content. Events and timings only.
11. Memory profiles stay on device. Compact preference vectors, never transcripts.
12. Treat every piece of clipboard text as hostile input to the intent parser. A pasted tweet is attacker-controlled.

---

## 12. TELEMETRY

Events only, never content. Minimum set:
`onboarding_step_view/complete` · `full_access_granted` · `keyboard_activated` · `glyf_fired {glyfId, latencyMs, success}` · `glyf_result_action {replace|insert|copy|discard}` · `builder_created` · `hub_install` · `connector_linked/revoked` · `dictation_used` · `swap_previewed/confirmed/completed/failed` · `paywall_view/purchase`

Dashboard from day one: **D1 / D7 / D30 retention of users who set Glyf as default.** Everything else is secondary.

---

## 13. WHAT NOT TO DO

- Don't put Flutter in the keyboard extension.
- Don't build swipe typing in v1.
- Don't start Android before iOS ships.
- Don't call OpenRouter, Jupiter, or any OAuth provider from the device.
- Don't auto-insert AI output without confirmation.
- Don't hide the swap fee.
- Don't store OAuth tokens on device.
- Don't build accessibility-service-based screen reading. Android 17 revokes AccessibilityService for non-accessibility apps under Advanced Protection, and Play requires a declaration plus prominent disclosure. Dead end.
- Don't hard-code default Glyfs in Swift — they go through the Builder format or the format is wrong.
- Don't build the shell as a stack of `UIViewController`s. Screens are data rendered by one reusable renderer, or the memory budget dies.
- Don't put mic, signing, purchase, OAuth consent, or secret entry inside the shell. Those open the app.
- Don't stack the toolbar above the candidate strip — collapse the toolbar instead.
- Don't link the Privy SDK before M8. It changes app size and review scope permanently.
- Don't ship any crypto UI in the v1.0 binary — not even hidden. Reviewers find flagged screens.
- **Don't skip the M1 gate to reach the crypto features faster.** If the keyboard isn't good, nobody stays long enough to swap anything.

---

## 14. FIRST SESSION INSTRUCTION

Start with **M0 only**.

1. Read this spec end to end.
2. Scaffold the repo per §3.
3. Wire the App Group; prove bidirectional read/write.
4. Run Spike A and Spike B. Write findings into `docs/SPIKES.md`.
5. Report back: what worked, what didn't, what you'd change in this spec before M1.

Do not write keyboard UI yet. Do not write the backend yet. M0 exists to de-risk, and both spikes can invalidate parts of this plan.

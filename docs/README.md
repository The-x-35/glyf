# Glyf docs

Everything about Glyf, written down: what it is, every decision and why, what was built each day, how each part works, what's still open, and the full conversation history the project was built through.

## Start here

| Doc | Read it for |
|---|---|
| [PROJECT.md](PROJECT.md) | The overview: what Glyf is, status, repo map, stack, identifiers, accounts and keys |
| [DECISIONS.md](DECISIONS.md) | Every decision in order (D1 to D92), with Arpit's words and what replaced what |
| [TIMELINE.md](TIMELINE.md) | What happened each day from 11 Sep 2026 |
| [OPEN-ITEMS.md](OPEN-ITEMS.md) | Everything pending, blocked or owed, and who acts |
| [WORKING-AGREEMENTS.md](WORKING-AGREEMENTS.md) | How Arpit wants the work done: design, product, engineering, tools, privacy |

## The parts

| Doc | Covers |
|---|---|
| [WEBSITE.md](WEBSITE.md) | tryglyf.com: the guided iMessage experience, all 8 chat scripts word for word, the demo keyboard, waitlist and Neon schema, mobile rules, share image, deploy steps, version history v1 to v8 |
| [APPS.md](APPS.md) | The iOS and Android apps and keyboards: architecture, every feature, design history, milestones, build and release recipes, traps |
| [BACKEND.md](BACKEND.md) | The server: every route, AI model routing, search suite, connectors and OAuth, env var names, tests, pending work |

## History

| File | What |
|---|---|
| [history/README.md](history/README.md) | How the history files are organised |
| [history/messages-from-arpit.md](history/messages-from-arpit.md) | All of Arpit's messages (118 so far), word for word, in order |
| [history/transcript-2026-09-11.md](history/transcript-2026-09-11.md) to [history/transcript-2026-09-16.md](history/transcript-2026-09-16.md) | The full conversation for each day: Arpit's messages and the assistant's written replies |
| [history/context-snapshots.md](history/context-snapshots.md) | Seven detailed state summaries written as the conversation grew long; the densest technical record |

## Milestone evidence (older, from the build)

| File | What |
|---|---|
| [SPIKES.md](SPIKES.md) | M0 spike findings and later platform discoveries |
| [M0-GATE.md](M0-GATE.md) | M0 gate: scaffold and spikes |
| [M1-M2-GATE.md](M1-M2-GATE.md) | M1 + M2 gate: keyboard, onboarding, Glyf Bar, Glyf Keys, AI backend |
| [M3-M4-GATE.md](M3-M4-GATE.md) | M3 + M4 gate: dictation, vault and shorthand |
| [M5-GATE.md](M5-GATE.md) | M5 gate plus M6/M7 buildable cores |
| `evidence/` | Screenshots and keyboard logs from the gates (the `.mp4` recordings are kept locally, not in git) |

## Conventions in these docs

- Times are India Standard Time (IST).
- Arpit's words are quoted as he wrote them.
- No secrets: env var names only, never values. Keys pasted in chat are redacted in the history files.
- No em dashes.

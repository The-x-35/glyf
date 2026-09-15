# shared/contracts — single source of truth

JSON Schemas for every payload that crosses a process boundary
(keyboard ⇄ app ⇄ backend). SPEC §3/§7: **Swift structs and Dart classes are
generated from these — never hand-write both sides.**

Status:

| Schema | State |
|---|---|
| `intent.schema.json` | v1 shape per SPEC §7.1. `payload` sub-schemas land with the milestone that uses them (M3 dictation, M8 swap/send). |
| `result.schema.json` | v1 shape per SPEC §7.2. |

Codegen (Swift + Dart emitters) is deliberately **not** built in M0 — nothing
crosses the boundary as a typed contract yet. Build it at the start of M2
alongside the first `/glyf/run` payloads, plus the §10.9 round-trip tests
(TTL expiry, replay rejection) which run against these schemas.

# Glyf typing engine — shared spec

One on-device engine, written twice (Swift `app/ios/GlyfKeyboard/Engine/Typing/`,
Kotlin `app/android/.../ime/typing/`), held to the same behavior by the golden
cases in `golden-cases.json`. Both test suites run every case against
`golden.glyd`. Change a constant here, change it in both engines and re-run
both suites.

## Dictionary file (`.glyd`, version 1)

Built offline by `tools/build_dictionary.py` from an AOSP combined word list
and memory-mapped read-only by both keyboards. Little-endian.

| Section | Layout |
|---|---|
| Header (44 bytes) | `"GLYD"`, u32 version, nodeCount, entryCount, bigramCount, stringBytes, nodesOffset, entriesOffset, bigramsOffset, stringsOffset, reserved |
| Node (16 bytes) | u32 `scalar \| maxProb << 24`, u32 firstChild (`0xFFFFFFFF` none), u16 childCount, u16 entryCount, u32 entryFirst |
| Entry (16 bytes) | u32 stringOffset, u16 stringLength, u8 probability, u8 flags, u32 bigramFirst, u16 bigramCount, u16 reserved |
| Bigram (8 bytes) | u32 targetEntry, u8 probability, 3 bytes padding |
| Strings | UTF-8 forms |

- Node 0 is the root. Nodes are breadth-first, so a node's children are
  contiguous and sorted by scalar.
- A node's path is the **key**: NFC, lowercase, apostrophes (`'` `’`) and
  hyphens dropped. All forms sharing a key hang off one node, most probable
  first (`its`/`it's`, `us`/`US`).
- `maxProb` is the highest probability of any suggestable entry in the subtree
  (best-first completion).
- Flags: 1 possibly offensive (known, never suggested), 2 not a word,
  4 whitelist (typing the key autocorrects to this form: `dont` → `don't`),
  8 form has an uppercase letter.
- Probabilities are AOSP's 0–255 log scale: `f = 255 + 8.59·log2(p)`.
  Bigram probabilities are absolute (the builder expands AOSP 4-bit ones).

## Scoring (ported from AOSP LatinIME, Apache-2.0)

Touch points are in key widths, relative to the keyboard's letter grid:
row `r`, column `k` → center `(k + 0.5 + offset[r], (r + 0.5) · rowPitch)`,
offsets `[0, 0.5, 1.5]`, `rowPitch` from the platform layout (default 1.44).
`nsd` = squared distance from the touch to a key center.

Sweet spot: `x < 0.25 → 0.24·x/0.25`, `x < 1 → (0.24·(1−x) + 1.2·(x−0.25))/0.75`, else `1.2`.

| Step | Cost |
|---|---|
| match | `0.1524·sweet(nsd)` |
| proximity (key edge within one key width) | match + `0.0694` (`0.072` first char) + `0.07788` on the first proximity of the path |
| substitution (far key) | `0.3806 + 0.1524·sweet(nsd)` |
| omission (word has a letter not typed) | `0.467`; `0.345` same letter as previous; `0.5256` first letter |
| insertion (typed an extra letter) | `0.7248`; `0.5508` same letter; `0.674` next to a proximity key; `+0.639` at the first letter; `+0.1524·nsd` |
| transposition | `0.5608 + 0.1524·(nsd₁ + nsd₂)` |
| terminal | `+0.0683` if any proximity, `+0.0362` if any edit, `+0.8128` per untyped trailing point |
| completion | `0.4836` first extra letter, `0.00624` each after |
| language | `1.1214·(255 − f)/255` |

Errors (omission, substitution, insertion, transposition) are only explored
while `spatial / (pointsConsumed + 1) < 0.095`. Beam: 310 states for the first
point, 170 after.

`score = 1 − cost/(1.1214 + 0.1·n)`, plus `1.1` for an exact match
(`−0.01` case, `−0.02` accent). Autocorrect confidence:
`score · (1 − DL(typed, candidate)/len(candidate))`.

Language `f` = max of: base unigram, base bigram (previous word), learned
unigram `255 + 8.59·log2((commits−1)/max(total, 8192)) − 32` (commits ≥ 2),
learned bigram `255 + 8.59·log2(pair/max(prev, 2)) − 4`, kept word 120,
pack word 160, word added in the app 160, contact name 40.

## When Glyf autocorrects

Never when: autocorrect is off or the field disallows it; the token has a
digit, two or more capitals, or any of `@ # . / : _`; the typed word is known
(one of its own spellings is in the dictionary incl. offensive, learned, kept,
in a pack, added, or a contact); the word is one letter; it is capitalized
mid-sentence; the user reverted this exact correction before.

Dictionary fixes (AOSP whitelist shortcuts):
- same letters, different apostrophes (`cant` → `can't`): applies unless the
  typed spelling is a real word less than 40 below the fix (`id` 99 stays,
  `I'd` is 136; `cant` 70 becomes `can't` 160);
- a different word (`alot` → `a lot`, `wierd` → `weird`): only when the typed
  spelling is no word at all — AOSP's `hum` → `him`, `bot` → `not`,
  `hid` → `his` never happen.

Same letters with other capitals: only into a lowercase form or a Title-case
proper noun with `f ≥ 60` (`delhi` → `Delhi`); never an acronym (`hsa` is not
`HSA`) or a capitalized contraction (`bas` is not `BA's`).

Otherwise the best candidate — never a spelling of the typed letters and
never a whitelist target — applies only if all hold:
- Damerau-Levenshtein ≤ 1 for typed length ≤ 4, ≤ 2 otherwise;
- confidence ≥ 0.185 (AOSP "modest");
- it beats the runner-up's confidence by ≥ 0.05, or ≥ 0.02 when it is two
  swapped letters and at least as common as the runner-up (`waht`);
- trust gates:
  - no far substitution of the first letter;
  - far substitution: never in words of ≤ 4 letters (`yaar` is not `year`),
    `f ≥ 90` from 7 letters (`definately`), else `f ≥ 150`;
  - an omission or insertion of a different letter, a completion or a
    trailing letter needs `f ≥ 120`;
  - two edits need `f ≥ 100` from 8 letters, else `f ≥ 150` from 6 letters;
  - finishing a word (letters missing at the end) needs 4 typed letters;
  - a lowercase word becomes a proper noun only if Title-case with
    `f ≥ 110` (`priya` is not `Oriya`), never an acronym (`ngl` is not `NFL`).

The applied form keeps the typed leading capital unless the form has its own
capitals (`Pune`, `I'm`). Alternatives never include a multi-word form for
other letters ("United States" is no completion for "u").

## Dictionary

`app/dict/en.glyd` = AOSP `en_wordlist.combined` (US + UK spellings, 165k
words, Apache-2.0) + `app/dict/supplement_en.combined` (texting words, Indian
names/apps/places, common word pairs). `shared/typing/real-cases.json` holds
both engines to the same answers on it.

## Packs

Packs come from `app/assets/vocab/packs.json`; words become known at `f 160`,
phrases teach word pairs at `f 180`. Until the user picks packs, phones set to
India start with `local.hinglish`.

## Learning

Committed words only, never in fields that disallow learning, never tokens
the gates above reject, never `SecretScanner` hits. An unknown word counts as
learned after 2 commits, or after 1 revert or literal tap (kept). A sentence's
auto-capitalized first word is learned lowercase when the lowercase form is a
word. Counts halve every 90 days; entries unused for 300 days are dropped.
Caps: 10,000 words, 30,000 word pairs. Reverting a correction blocks that
pair forever and un-learns one commit of the wrong word.

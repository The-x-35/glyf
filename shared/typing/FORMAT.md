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
| Header (44 bytes) | `"GLYD"`, u32 version, nodeCount, entryCount, bigramCount, stringBytes, nodesOffset, entriesOffset, bigramsOffset, stringsOffset, contextsOffset (0 = none) |
| Node (16 bytes) | u32 `scalar \| maxProb << 24`, u32 firstChild (`0xFFFFFFFF` none), u16 childCount, u16 entryCount, u32 entryFirst |
| Entry (16 bytes) | u32 stringOffset, u16 stringLength, u8 probability, u8 flags, u32 bigramFirst, u16 bigramCount, u16 reserved |
| Bigram (8 bytes) | u32 targetEntry, u8 probability, 3 bytes padding |
| Contexts | u32 contextCount, u32 reserved, then per context (16 bytes): u32 entry two back, u32 previous entry, u32 first row, u16 rowCount, u16 reserved |
| Strings | UTF-8 forms |

- Node 0 is the root. Nodes are breadth-first, so a node's children are
  contiguous and sorted by scalar.
- A node's path is the **key**: NFC, lowercase, apostrophes (`'` `’`) and
  hyphens dropped. All forms sharing a key hang off one node: words first,
  most probable first (`its`/`it's`, `us`/`US`), then the targets of
  dictionary fixes hung under a misspelling (below).
- `maxProb` is the highest probability of any suggestable entry in the subtree
  (best-first completion).
- A whitelist (dictionary fix) target spelled with other letters is stored
  under the misspelling's key flagged `2 | 4` (`have` under `nave`, `his`
  under `hid`): only typing exactly that key reaches it, never a search. The
  same form under its own key is the word itself, and bigrams point there.
- An entry's bigrams are its next words, most probable first, one row per
  target; only the word's own entry has them.
- A context is two words in a row (each the most probable form of its key,
  like a previous word) and the words seen after both, most probable first,
  in rows after all the bigrams. Contexts are sorted by (two back, previous)
  for a binary search. A file without them is version 1 all the same: the
  offset was the reserved slot.
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

Language `f` = max of: base unigram, learned unigram
`255 + 8.59·log2((commits−1)/max(total, 8192)) − 32` (commits ≥ 2), kept word
120, pack word 160, word added in the app 160, contact name 40 — and then,
after a previous word, the max of that and its **pair** evidence: base bigram,
learned bigram `255 + 8.59·log2(pair/max(prev, 2)) − 4`, pack phrase 180, and
the context row when the word two back and the previous word have one ("I
want" → to). The previous word's (and the one two back's) base entry is the
most probable form under its key. Learned unigrams and pairs count only for
the spelling the person last typed for that key (`'` and `’` alike): having
written "they were" never lifts `we're`.

A word the previous word has pairs for, but never this one (no pair evidence
at all), and that is no name (capitalized, not `I` or `I'…`), ranks lower:
`f' = max(min(f, floor), f − 45)`, `floor` = the previous word's rarest pair.
"your my" is no English; "your ket" is `key`, not `let`. Names are exempt:
pairs never predict them.

That penalty only counts when the previous word speaks to the choice: when
none of the three likeliest candidates (ranked as if unpenalized, ties by
form) has pair evidence, every candidate and every spelling of the typed
letters ranks as if alone ("the recieve" is still `receive`).

A name typed in lowercase (or capitalized only by the sentence start) that is
not exactly the typed letters ranks 40 lower (`I hsven` is never `Haven` or
`Hagen`).

Candidates: the decoder's, plus the context's rows and the previous word's
256 likeliest followers that the typed letters start with at most one slip
(none under three typed letters), at `0.45` a slip plus the completion cost of the letters left; a
word the decoder also found keeps the decoder's kinds, a new one counts as a
far slip and/or a completion. Each form keeps its best score.

The `+1.1` exact bonus goes only to spellings of the typed letters with
`f ≥ 60` (or from learned, pack and contact words): "wats" offers `was`,
not `wat's`. After a single letter the strip offers only words that start
with it ("k" never offers `I`).

Next-word predictions: the context's rows at their probability + 15, the
previous word's 64 likeliest pairs (each of its key's forms), learned pairs
and pack phrases; the three best of at least 150.

## When Glyf autocorrects

Never when: autocorrect is off or the field disallows it; the token has a
digit, two or more capitals, or any of `@ # . / : _`; the typed word is known
(one of its own spellings is in the dictionary incl. offensive, learned, kept,
in a pack, added, or a contact), save the name rule below; the word is one letter; it is capitalized
mid-sentence; the user reverted this exact correction before; the word is
stretched for emphasis, a letter three or more times in a row (`sooo`,
`yesss`, `cuteee`: 2026-09-29, `sooo` had become `solo`).

Dictionary fixes (AOSP whitelist shortcuts):
- same letters, different apostrophes (`cant` → `can't`): applies unless the
  typed spelling is a real word less than 40 below the fix (`id` 99 stays,
  `I'd` is 136; `cant` 70 becomes `can't` 160);
- a different word (`alot` → `a lot`, `wierd` → `weird`): only when the typed
  spelling is no word at all, or only a rare one (every spelling `f < 60`) and
  the previous word has pair evidence for the fix (`it os` is `it is`; `the
  os` stays) — AOSP's `hum` → `him`, `bot` → `not`, `hid` → `his` never
  happen. Such a fix gives way to the search's own pick (below) when that is
  likelier: by any margin when it has the fix's letters (`they wer` is
  `were`, not `we're`), by 40 otherwise.
- A fix held back is never put in by the search either.

Names are never changed (2026-11-04). The names the keyboard holds are the
words of contact names (iOS: the supplementary lexicon and the
`contacts.json` the app syncs for Contacts search; Android:
`contacts.json`) and of the details saved in the vault that are names: the
name (first and last), company, city and state ("own names", the same
standing as a contact). Spelled as the name is (`Sumit`, at a sentence start
too) the word is known and stays. Typed in other capitals (`sumit`), it takes
only a fix into its own letters (`pune` → `Pune`, `mike` → `Mike`) or into
one of the commonest words, base `f ≥ 200` (a contact `Teh` still lets `teh`
be `the`, 222); `sumit` is never `summit`, `anoop` never `snoop`.

A word typed with its own capital mid-sentence that autocorrect changed into
other letters anyway (`Wierd` → `Weird`, a dictionary fix) counts as a commit
of what was typed. Typed so twice it is learned, so it is never changed
again. A sentence start's capital proves nothing, and neither does a fix of
the same letters (`Im` → `I'm`).

A known word that is far more often a name becomes the name: a Title-case
form at least 40 above the typed spelling (`mike` 57 → `Mike` 122, `john` →
`John`; `bill` and `will` stay), unless the person uses the lowercase word.

Same letters with other capitals or apostrophes: only into a lowercase form
or a Title-case proper noun with `f ≥ 60` (`delhi` → `Delhi`); never an
acronym (`hsa` is not `HSA`) or a capitalized contraction (`bas` is not
`BA's`). When that form is a name (not a contact) or a rare spelling
(lowercase, `f < 120`: `ne'er`, `di's`), a search pick (below) with `f` 40
higher wins instead — for a name of `f ≥ 100`, only when its pair evidence is
that high too (`I've ben` → `been`; `call mike` stays `Mike`). If some
candidate one edit away is that strong but not sure enough to put in, the
word stays as typed (`Tom wats`).

Otherwise the search's best candidate — never a spelling of the typed
letters — applies only if all hold:
- the word is more than one letter, and not capitalized mid-sentence;
- Damerau-Levenshtein ≤ 1 for typed length ≤ 4, ≤ 2 otherwise;
- confidence ≥ 0.16;
- it beats the runner-up's confidence by ≥ 0.05, or ≥ 0.02 when it is two
  swapped letters and at least as common as the runner-up (`waht`);
- trust gates:
  - no far substitution of the first letter;
  - far substitution: never in words of ≤ 4 letters (`yaar` is not `year`),
    `f ≥ 90` from 7 letters (`definately`), else `f ≥ 150`;
  - an omission or insertion of a different letter, a completion or a
    trailing letter needs `f ≥ 100`, `f ≥ 60` from 7 typed letters;
  - two edits need `f ≥ 100` from 8 letters, else `f ≥ 150` from 6 letters;
  - a lowercase word becomes a proper noun only if Title-case with
    `f ≥ 110` (`priya` is not `Oriya`), never an acronym (`ngl` is not `NFL`).

Measured on 2,000 held-out Tatoeba sentences (`StripEval`, 2026-10-05): a
typo is fixed 76.5% of the time (58% before), fixed or shown 93% (87%),
turned into another word 1.8%; a correct word is changed 0.1%. The next word
is in the three predictions 38% (3%), and in the strip's two after one, two,
three letters 54%, 57%, 67% (19%, 22%, 39%).

The applied form keeps the typed leading capital unless the form has its own
capitals (`Pune`, `I'm`). Alternatives never include a multi-word form for
other letters ("United States" is no completion for "u").

## Dictionary

`app/dict/en.glyd` = AOSP `en_wordlist.combined` (US + UK spellings, 165k
words, Apache-2.0) + `app/dict/supplement_en.combined` (texting words, Indian
names/apps/places, chat word pairs that stay on top) +
`app/dict/ngrams_en.combined.gz` (294k word pairs and 263k word triples
counted by `tools/typing/build_ngrams.py` from Tatoeba's English sentences,
CC BY 2.0 FR, one in ten held out for measuring). `shared/typing/real-cases.json` holds
both engines to the same answers on it; `app/dict/NOTICE.md` has the rebuild
commands.

Word pairs: every pair seen 3 times, `f = 255 + 8.59·log2((count − 0.5)/n)`
with `n` the previous word's count, attached to the most probable form of its
key. Triples: seen 4 times, the 32 likeliest after each two words, `n` the
count of those two words followed by anything. Names never follow (Tatoeba's Tom and Mary), except days, months,
languages, a few others and all-capital words (`OK`, `TV`); a rare word far
more often a contraction missing its apostrophe counts as the contraction
(`wont` → `won't`). Words much commoner in sentences than in AOSP's list are
lifted (`f − 8` of their sentence frequency, at most 230), unless another
spelling of their letters is commoner (`ill` stays below `I'll`).

Parity: `TypingParity` (JUnit) and `testParityDump` (RunnerTests) write every
answer for the same `in.tsv`; the two files must be identical.

## Packs

Packs come from `app/assets/vocab/packs.json`; words become known at `f 160`,
phrases teach word pairs at `f 180`. Until the user picks packs, phones set to
India start with `local.hinglish`.

## Learning

Committed words only, never in fields that disallow learning, never tokens
the gates above reject, never `SecretScanner` hits. A field that turns
autocorrect off teaches nothing (iOS `autocorrectionType = .no` and
`.webSearch` keyboards; Android has no policy at all in `NO_SUGGESTIONS`,
password, URI, email and filter fields): "teh" typed twice into a search bar
was never fixed anywhere again. Where autocorrect is off but learning goes
on (the Autocorrect setting off; iOS's X composer) a word autocorrect would
have fixed is not learned, and neither is a fix shown but left standing
with "Correct automatically" off. Name and address fields learn what they
are given. An unknown word counts as
learned after 2 commits, or after 1 revert or literal tap (kept). A sentence's
auto-capitalized first word is learned lowercase when the lowercase form is a
word. Counts halve every 90 days; entries unused for 300 days are dropped.
Caps: 10,000 words, 30,000 word pairs. Reverting a correction blocks that
pair forever and un-learns one commit of the wrong word.

## Undo and reverts

Right after an autocorrect, while the caret is where the fix left it, the
strip's first slot is what was typed, in quotes (`“teh”`, Apple's way), and
the next-word predictions fill the other two once a space is in. What came
after the fixed word rides along: its space (`the `), or the punctuation that
made the fix and then one space (`the, `, `the!? `; three characters at
most, marks only before the space). Tapping the chip puts back the typed
word with that tail and is a revert (Learning: the pair is blocked, the typed word kept). Backspace straight after a fix
and its space is one too and leaves the typed word with the caret after it
(`teh|`); after punctuation backspace deletes as usual. Anything else typed,
deleted or moved to leaves the correction behind. Both keyboards:
`WordTracker.undoTail`/`undo` (iOS) and `WordContext.undoTail`/`undo`.

A revert is not only the backspace straight after a correction: going back
into a word the engine corrected in the last five minutes (backspacing
through it, or sliding it away with delete) and typing the original again
is one too, and is learned the same way. A typo simply typed twice (`teh`)
is still fixed, because its correction was never gone back into.
(2026-09-29: `cutee`, deleted and typed again, kept coming back corrected.) Forgetting a word ("My words" in the app) also forgets the corrections it
turned down, so the word is corrected again.

The strip offers the person's own words first: once at least three letters
are typed, their most used learned, kept or added word that starts with
them takes the first alternative slot (`cut` → their `cutee`, ahead of
`but` and `out`). It is offered, never applied by autocorrect, and only
with learning on.

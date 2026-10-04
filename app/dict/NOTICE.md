# Dictionary sources

`en.glyd` is compiled by `tools/build_dictionary.py` from:

- `source/en_wordlist.combined.gz` — English word list from the Android Open
  Source Project, `platform/packages/inputmethods/LatinIME`, `dictionaries/`
  (https://android.googlesource.com/platform/packages/inputmethods/LatinIME/+/refs/heads/main/dictionaries/).
  Copyright The Android Open Source Project, licensed under the Apache License,
  Version 2.0 (http://www.apache.org/licenses/LICENSE-2.0). Glyf compiles it to
  its own binary format; the words, frequencies and flags are unchanged.
- `source/en_emoji.combined.gz` — AOSP English emoji shortcuts, same source and
  licence (not yet compiled into the keyboards).
- `supplement_en.combined` — written for Glyf: everyday texting words, Indian
  names, apps and places the 2014 AOSP list lacks, and common word pairs.
- `bigrams_en.combined.gz` — which word follows which, and how often, counted
  by `tools/typing/build_bigrams.py` from the English sentences of Tatoeba
  (https://tatoeba.org), licensed under Creative Commons Attribution 2.0
  France (CC BY 2.0 FR, https://creativecommons.org/licenses/by/2.0/fr/).
  Only the counts are kept, never the sentences.

Rebuild:

    python3 tools/typing/build_bigrams.py ~/.cache/glyf-typing/eng_sentences.tsv \
        app/dict/bigrams_en.combined && gzip -9 -n -f app/dict/bigrams_en.combined
    python3 tools/build_dictionary.py app/dict/source/en_wordlist.combined.gz \
        app/dict/supplement_en.combined app/dict/bigrams_en.combined.gz app/dict/en.glyd

`eng_sentences.tsv` is Tatoeba's English export
(https://downloads.tatoeba.org/exports/per_language/eng/eng_sentences.tsv.bz2,
unpacked). Only `en.glyd` and this notice ship in the apps.

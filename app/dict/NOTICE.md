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

Rebuild:

    python3 tools/build_dictionary.py app/dict/source/en_wordlist.combined.gz \
        app/dict/supplement_en.combined app/dict/en.glyd

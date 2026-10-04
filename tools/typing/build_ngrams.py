#!/usr/bin/env python3
"""Word pairs and triples for the keyboards' dictionary, from everyday
English sentences.

Reads Tatoeba's English sentences (CC BY 2.0 FR, https://tatoeba.org) and
counts which word follows which, and which follows two given words, then
writes them in the AOSP "combined" format tools/build_dictionary.py merges
into app/dict/en.glyd (a triple sits under its middle word):

     word=I,f=0
      bigram=haven't,f=198
     word=want,f=0
      trigram=to,prev=I,f=247

A pair's f is the dictionary's own scale for P(next | previous):
255 + 8.59 * log2(p). Only words the dictionary already knows take part, and
a pair needs MIN_PAIR sightings: a word missing after a well-seen one is
evidence too (FORMAT.md "Language f"). Names never follow (Tatoeba writes
"Tom" and "Mary" everywhere) and nothing marked possibly offensive does. Words much commoner in everyday
sentences than in AOSP's list ("haven't", "gonna") get a lift of their own
single-word f, for corrections and completions with nothing before them.

A triple needs MIN_TRIPLE sightings and two words keep their TOP_TRIPLES
likeliest followers, with the same scale over how often the two were seen
together and followed by anything.

One sentence in ten (by id) is never counted: StripEval reads those, so
accuracy is measured on sentences the model has not seen.

    python3 tools/typing/build_ngrams.py \
        ~/.cache/glyf-typing/eng_sentences.tsv app/dict/ngrams_en.combined
"""
import collections
import math
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from build_dictionary import read_combined, word_key, FLAG_NOT_A_WORD, FLAG_OFFENSIVE  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SOURCES = [os.path.join(ROOT, "app/dict/source/en_wordlist.combined.gz"),
           os.path.join(ROOT, "app/dict/supplement_en.combined")]
MIN_PAIR = 3
TOP_PAIRS = 65535      # every pair seen MIN_PAIR times (an entry counts pairs in 16 bits)
MIN_TRIPLE = 4
TOP_TRIPLES = 32
# Capitalized words that are no one's name: these may follow ("on Monday",
# "speak English", "it's OK"). All-capital words (OK, TV) may too.
NOT_NAMES = {
    "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday",
    "January", "February", "March", "April", "May", "June", "July", "August", "September",
    "October", "November", "December", "Christmas", "Easter", "Halloween", "Thanksgiving",
    "English", "French", "Spanish", "German", "Chinese", "Japanese", "Italian", "Russian",
    "Arabic", "Portuguese", "Korean", "Hindi", "Dutch", "Greek", "Turkish", "Polish",
    "Swedish", "Irish", "British", "American", "Canadian", "Australian", "Indian", "Mexican",
    "European", "African", "Asian", "Christian", "Muslim", "Jewish", "Catholic", "God",
    "Internet", "Mr", "Mrs", "Ms", "Dr",
}
TOKEN = re.compile(r"[A-Za-z]+(?:['’][A-Za-z]+)*|\S")


def held_out(sentence_id):
    return sentence_id % 10 == 0


def dictionary():
    """key -> [(form, prob)], best first, as build_dictionary.py orders them;
    plus the forms never to predict."""
    forms = collections.defaultdict(dict)
    banned = set()
    for path in SOURCES:
        for word, prob, flags, *_ in read_combined(path):
            if flags & FLAG_NOT_A_WORD:
                continue
            if flags & FLAG_OFFENSIVE:
                banned.add(word)
            g = forms[word_key(word)]
            g[word] = max(g.get(word, 0), prob)
    ordered = {k: sorted(v.items(), key=lambda kv: (-kv[1], kv[0])) for k, v in forms.items()}
    return ordered, banned


def is_name(form):
    """Capitalized, and not one of I's own forms ("I", "I'm", "I've"), an
    all-capital word ("OK", "TV") or one of NOT_NAMES."""
    if form == "I" or form.startswith("I'") or form in NOT_NAMES:
        return False
    letters = [ch for ch in form if ch.isalpha()]
    if len(letters) >= 2 and all(ch.isupper() for ch in letters):
        return False
    return any(ch.isupper() for ch in form)


def to_form(token, first, forms):
    options = forms.get(word_key(token))
    if not options:
        return None
    exact = next((o for o in options if o[0] == token), None) or \
        next((o for o in options if o[0] == token.lower()), None)
    if exact is None:
        # "tom" mid-sentence is still Tom; "Let's" at the start is "let's".
        return options[0][0]
    # A rare word that is far more often a contraction missing its
    # apostrophe: Tatoeba's "wont" and "cant" are won't and can't.
    top, top_p = options[0]
    if "'" in top and "'" not in exact[0] and exact[1] < 80 and top_p >= exact[1] + 40:
        return top
    return exact[0]


def tokens(sentence):
    """Runs of words that follow one another directly (a comma, a number or
    a quote ends a run): [[word, ...], ...]."""
    runs, run = [], []
    for m in TOKEN.finditer(sentence.replace("’", "'")):
        t = m.group(0)
        if t[0].isalpha():
            run.append(t)
        else:
            if len(run) > 1:
                runs.append(run)
            run = []
    if len(run) > 1:
        runs.append(run)
    return runs


def main(argv):
    if len(argv) != 3:
        print(__doc__)
        return 2
    forms, banned = dictionary()
    top_form = {k: v[0][0] for k, v in forms.items()}
    pairs = collections.defaultdict(collections.Counter)
    followed = collections.Counter()
    triples = collections.defaultdict(collections.Counter)
    followed2 = collections.Counter()
    unigram = collections.Counter()
    total = 0
    sentences = 0
    with open(argv[1], encoding="utf-8") as fh:
        for line in fh:
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 3 or not parts[0].isdigit() or held_out(int(parts[0])):
                continue
            sentences += 1
            for run in tokens(parts[2]):
                mapped = [to_form(t, i == 0, forms) for i, t in enumerate(run)]
                for form in mapped:
                    if form:
                        unigram[form] += 1
                        total += 1
                for a, b in zip(mapped, mapped[1:]):
                    if not a:
                        continue
                    key = word_key(a)
                    followed[key] += 1
                    if b and not is_name(b) and b not in banned:
                        pairs[key][b] += 1
                for a, b, c in zip(mapped, mapped[1:], mapped[2:]):
                    if not a or not b:
                        continue
                    context = (word_key(a), word_key(b))
                    followed2[context] += 1
                    if c and not is_name(c) and c not in banned:
                        triples[context][c] += 1

    out = ["dictionary=main:en,locale=en,description=Glyf word pairs and triples from Tatoeba English "
           "sentences (CC BY 2.0 FR; tools/typing/build_ngrams.py),version=1"]
    kept_pairs = 0
    lifted = 0
    aosp = {f: p for opts in forms.values() for f, p in opts}
    # Single words: everyday commonness lifts a word the web list rates low,
    # unless another spelling of its letters is commoner ("ill" stays below
    # "I'll", so "ill" alone is still fixed).
    for form, c in unigram.items():
        if is_name(form) or form in banned or c < 20:
            continue
        if top_form[word_key(form)] != form:
            continue
        f = round(255 + 8.59 * math.log2(c / total)) - 8
        if f > aosp.get(form, 0) + 10:
            out.append(f" word={form},f={min(f, 230)}")
            lifted += 1
    by_middle = collections.defaultdict(list)     # key b -> [(key a, counter)]
    for (ka, kb), counter in triples.items():
        by_middle[kb].append((ka, counter))
    kept_triples = 0
    for key in sorted(set(pairs) | set(by_middle)):
        rows = [(b, c) for b, c in pairs.get(key, collections.Counter()).most_common(TOP_PAIRS) if c >= MIN_PAIR]
        tri = []
        for ka, counter in sorted(by_middle.get(key, [])):
            n2 = followed2[(ka, key)]
            for c_form, c in counter.most_common(TOP_TRIPLES):
                if c >= MIN_TRIPLE:
                    tri.append((top_form[ka], c_form, c, n2))
        if not rows and not tri:
            continue
        out.append(f" word={top_form[key]},f=0")
        n = followed[key]
        for b, c in rows:
            p = (c - 0.5) / n
            f = max(1, min(255, round(255 + 8.59 * math.log2(p))))
            out.append(f"  bigram={b},f={f}")
            kept_pairs += 1
        for a, c_form, c, n2 in tri:
            p = (c - 0.5) / n2
            f = max(1, min(255, round(255 + 8.59 * math.log2(p))))
            out.append(f"  trigram={c_form},prev={a},f={f}")
            kept_triples += 1
    with open(argv[2], "w", encoding="utf-8") as fh:
        fh.write("\n".join(out) + "\n")
    print({"sentences": sentences, "tokens": total, "words with pairs": sum(1 for k in pairs if any(c >= MIN_PAIR for c in pairs[k].values())),
           "pairs": kept_pairs, "triples": kept_triples, "lifted words": lifted})
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

#!/usr/bin/env python3
"""Compile an AOSP "combined" word list into Glyf's binary dictionary (.glyd).

Both keyboards memory-map the output read-only, so a 100k-word dictionary
costs the iOS extension almost nothing against its memory limit. The format
is specified in shared/typing/FORMAT.md; keep the two in sync.

    python3 tools/build_dictionary.py INPUT... OUTPUT.glyd [--min-prob=N]

    # the keyboards' English dictionary (AOSP list + Glyf supplement)
    python3 tools/build_dictionary.py app/dict/source/en_wordlist.combined.gz \
        app/dict/supplement_en.combined app/dict/en.glyd
    # the golden test dictionary both engines' tests load
    python3 tools/build_dictionary.py shared/typing/golden.combined shared/typing/golden.glyd

Several inputs merge: a word keeps its highest frequency and all its flags.

Input lines (AOSP CombinedFormatUtils):
    dictionary=main:en_us,locale=en_US,...
     word=the,f=222,flags=,originalFreq=222
      bigram=first,f=10
      shortcut=don't,f=whitelist
     word=dont,f=0,not_a_word=true,possibly_offensive=true
"""
import gzip
import struct
import sys
import unicodedata

MAGIC = b"GLYD"
VERSION = 1
NONE = 0xFFFFFFFF

FLAG_OFFENSIVE = 1
FLAG_NOT_A_WORD = 2
FLAG_WHITELIST = 4
FLAG_HAS_UPPER = 8

HEADER_FMT = "<4s10I"       # magic + 10 u32
NODE_FMT = "<IIHHI"         # scalar|maxProb<<24, firstChild, childCount, entryCount, entryFirst
ENTRY_FMT = "<IHBBIHH"      # stringOffset, stringLength, probability, flags, bigramFirst, bigramCount, reserved
BIGRAM_FMT = "<IB3x"        # targetEntry, probability


def word_key(word):
    """Lookup form shared by both engines: lowercase, apostrophes and
    hyphens dropped ("Don't" -> "dont", "follow-up" -> "followup")."""
    word = unicodedata.normalize("NFC", word)
    return "".join(ch for ch in word.lower() if ch not in "'’-")


def parse_attrs(line):
    attrs = {}
    # Values never contain commas except inside the word itself, which is
    # always the first attribute: split it off first.
    head, _, rest = line.partition(",")
    k, _, v = head.partition("=")
    attrs[k.strip()] = v
    for part in rest.split(","):
        if "=" in part:
            k, _, v = part.partition("=")
            attrs[k.strip()] = v.strip()
    return attrs


def read_combined(path):
    opener = gzip.open if path.endswith(".gz") else open
    words = []          # [word, prob, flags, bigrams[(target, f)], shortcuts[(target, f)]]
    current = None
    with opener(path, "rt", encoding="utf-8") as fh:
        for raw in fh:
            line = raw.rstrip("\n")
            stripped = line.strip()
            if not stripped or stripped.startswith("dictionary="):
                continue
            attrs = parse_attrs(stripped)
            if "word" in attrs:
                flags = 0
                if attrs.get("possibly_offensive") == "true":
                    flags |= FLAG_OFFENSIVE
                if attrs.get("not_a_word") == "true":
                    flags |= FLAG_NOT_A_WORD
                prob = int(attrs.get("f", "0") or 0)
                current = [attrs["word"], max(0, min(255, prob)), flags, [], []]
                words.append(current)
            elif "bigram" in attrs and current is not None:
                current[3].append((attrs["bigram"], int(attrs.get("f", "0") or 0)))
            elif "ngram" in attrs and current is not None:
                current[3].append((attrs["ngram"], int(attrs.get("f", "0") or 0)))
            elif "shortcut" in attrs and current is not None:
                current[4].append((attrs["shortcut"], attrs.get("f", "")))
    return words


def compile_words(words, min_prob=0):
    # Bigram probabilities come either 4-bit encoded (0..15, relative to the
    # target's unigram, AOSP v2) or absolute (0..255). Normalize to absolute.
    max_bigram = max((f for w in words for _, f in w[3]), default=0)
    four_bit = max_bigram <= 15
    unigram = {}
    for w in words:
        if not (w[2] & FLAG_NOT_A_WORD):
            unigram[w[0]] = max(unigram.get(w[0], 0), w[1])

    def bigram_prob(target, f):
        if not four_bit:
            return max(0, min(255, f))
        base = unigram.get(target, 0)
        step = (255 - base) / (1.5 + 15)
        return min(255, base + int((f + 1) * step))

    # key -> {form: [prob, flags]}
    groups = {}
    bigrams = {}   # form -> [(target_form, prob)]

    def add_form(form, prob, flags):
        key = word_key(form)
        if not key:
            return
        g = groups.setdefault(key, {})
        if form in g:
            g[form][0] = max(g[form][0], prob)
            g[form][1] |= flags
        else:
            g[form] = [prob, flags]

    for word, prob, flags, bgs, shortcuts in words:
        if flags & FLAG_NOT_A_WORD:
            # Not typable as itself, but its whitelist shortcuts still apply:
            # "dont" -> "don't". Stored under the typed key.
            for target, f in shortcuts:
                if f == "whitelist":
                    key = word_key(word)
                    target_prob = unigram.get(target, 200)
                    g = groups.setdefault(key, {})
                    entry = g.setdefault(target, [target_prob, 0])
                    entry[1] |= FLAG_WHITELIST
            continue
        if prob < min_prob and not (flags & FLAG_OFFENSIVE):
            continue
        upper = FLAG_HAS_UPPER if any(ch.isupper() for ch in word) else 0
        add_form(word, prob, flags | upper)
        for target, f in shortcuts:
            if f == "whitelist":
                g = groups.setdefault(word_key(word), {})
                entry = g.setdefault(target, [unigram.get(target, prob), 0])
                entry[1] |= FLAG_WHITELIST
        if bgs:
            bigrams.setdefault(word, []).extend((t, bigram_prob(t, f)) for t, f in bgs)

    # Trie over keys (scalars), children sorted, laid out breadth-first so a
    # node's children are contiguous.
    root = {"children": {}, "forms": None}
    for key in sorted(groups):
        node = root
        for ch in key:
            node = node["children"].setdefault(ch, {"children": {}, "forms": None})
        node["forms"] = groups[key]

    # Entries: grouped per key, in BFS node order.
    order = [(root, 0)]
    nodes = []
    head = 0
    while head < len(order):
        node, scalar = order[head]
        head += 1
        nodes.append([node, scalar, 0, 0])
        for ch in sorted(node["children"]):
            order.append((node["children"][ch], ord(ch)))

    index_of = {id(n[0]): i for i, n in enumerate(nodes)}
    entries = []
    entry_index = {}
    for n in nodes:
        forms = n[0]["forms"]
        if not forms:
            continue
        n[3] = len(entries)
        # Most probable form first within a key.
        for form, (prob, flags) in sorted(forms.items(), key=lambda kv: (-kv[1][0], kv[0])):
            if any(ch.isupper() for ch in form):
                flags |= FLAG_HAS_UPPER
            entry_index[form] = len(entries)
            entries.append([form, prob, flags, NONE, 0])

    # Subtree max probability (suggestable entries only), bottom-up.
    max_prob = [0] * len(nodes)
    for i in range(len(nodes) - 1, -1, -1):
        node = nodes[i][0]
        best = 0
        forms = node["forms"] or {}
        for prob, flags in forms.values():
            if not (flags & (FLAG_OFFENSIVE | FLAG_NOT_A_WORD)):
                best = max(best, prob)
        for child in node["children"].values():
            best = max(best, max_prob[index_of[id(child)]])
        max_prob[i] = best

    bigram_rows = []
    for e in entries:
        pairs = bigrams.get(e[0])
        if not pairs:
            continue
        rows = sorted(((entry_index[t], p) for t, p in pairs if t in entry_index), key=lambda r: -r[1])
        if rows:
            e[3] = len(bigram_rows)
            e[4] = len(rows)
            bigram_rows.extend(rows)

    strings = bytearray()
    entry_bytes = bytearray()
    for form, prob, flags, bfirst, bcount in entries:
        data = form.encode("utf-8")
        entry_bytes += struct.pack(ENTRY_FMT, len(strings), len(data), prob, flags, bfirst, min(bcount, 0xFFFF), 0)
        strings += data

    node_bytes = bytearray()
    for i, (node, scalar, _, entry_first) in enumerate(nodes):
        children = sorted(node["children"])
        first_child = index_of[id(node["children"][children[0]])] if children else NONE
        forms = node["forms"] or {}
        node_bytes += struct.pack(
            NODE_FMT,
            (scalar & 0xFFFFFF) | (max_prob[i] << 24),
            first_child,
            len(children),
            len(forms),
            entry_first if forms else NONE,
        )

    bigram_bytes = bytearray()
    for target, prob in bigram_rows:
        bigram_bytes += struct.pack(BIGRAM_FMT, target, prob)

    header_size = struct.calcsize(HEADER_FMT)
    nodes_off = header_size
    entries_off = nodes_off + len(node_bytes)
    bigrams_off = entries_off + len(entry_bytes)
    strings_off = bigrams_off + len(bigram_bytes)
    header = struct.pack(
        HEADER_FMT, MAGIC, VERSION, len(nodes), len(entries), len(bigram_rows), len(strings),
        nodes_off, entries_off, bigrams_off, strings_off, 0,
    )
    return header + node_bytes + entry_bytes + bigram_bytes + bytes(strings), {
        "nodes": len(nodes), "entries": len(entries), "bigrams": len(bigram_rows),
        "bigramScale": "4-bit" if four_bit else "absolute",
    }


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--min-prob=")]
    min_prob = next((int(a.split("=", 1)[1]) for a in argv[1:] if a.startswith("--min-prob=")), 0)
    if len(args) < 2 or not args[-1].endswith(".glyd"):
        print(__doc__)
        return 2
    words = []
    for path in args[:-1]:
        words += read_combined(path)
    blob, stats = compile_words(words, min_prob=min_prob)
    with open(args[-1], "wb") as fh:
        fh.write(blob)
    stats["bytes"] = len(blob)
    stats["words"] = len(words)
    print(stats)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

#!/usr/bin/env python3
"""Builds the emoji board's table for both keyboards (shared/emoji/emoji.tsv).

Every emoji on Apple's keyboard, in Apple's eight tabs and Apple's order
(shared/emoji/sources/apple-keyboard-ios26.5.json, read from iOS 26.5's
EmojiFoundation), with what Unicode says of each: its name and Emoji version
(emoji-test.txt), its skin-tone variants and their versions, and CLDR's
English keywords for search (Unicode License v3, shared/emoji/LICENSE-UNICODE.txt).

Writes:
  shared/emoji/emoji.tsv                          the table
  app/ios/GlyfKeyboard/Design/EmojiData.swift      the table, between its GENERATED marks
  app/android/app/src/main/assets/emoji.tsv        the table, for the Android keyboard

Usage: python3 tools/emoji/build.py [--src DIR]
  DIR may hold emoji-test.txt, annotations_en.xml and annotationsDerived_en.xml;
  whatever is missing is downloaded (Unicode 17.0, CLDR 48.2).
"""
import json, os, re, sys, urllib.request
import xml.etree.ElementTree as ET

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
SOURCES = {
    'emoji-test.txt': 'https://www.unicode.org/Public/17.0.0/emoji/emoji-test.txt',
    'annotations_en.xml': 'https://raw.githubusercontent.com/unicode-org/cldr/release-48-2/common/annotations/en.xml',
    'annotationsDerived_en.xml': 'https://raw.githubusercontent.com/unicode-org/cldr/release-48-2/common/annotationsDerived/en.xml',
}
TABS = [('Smileys & People', 'smileys'), ('Animals & Nature', 'animals'), ('Food & Drink', 'food'),
        ('Activity', 'activity'), ('Travel & Places', 'travel'), ('Objects', 'objects'),
        ('Symbols', 'symbols'), ('Flags', 'flags')]
TONES = set(range(0x1F3FB, 0x1F400))
# Frequently Used before anything has been used: the world's most used emoji
# (Unicode's 2021 emoji frequency ranking, home.unicode.org/emoji/emoji-frequency).
SEED = ['😂', '❤️', '🤣', '👍', '😭', '🙏', '😘', '🥰', '😍', '😊', '🎉', '😁', '💕', '🥺', '😅', '🔥', '☺️', '🤦',
        '♥️', '🤷', '🙄', '😆', '🤗', '😉', '🎂', '🤔', '👏', '🙂', '😳', '🥳']


def source(name, src):
    if src and os.path.exists(os.path.join(src, name)):
        return open(os.path.join(src, name), encoding='utf-8').read()
    cache = os.path.join(os.path.expanduser('~'), '.cache', 'glyf-emoji')
    os.makedirs(cache, exist_ok=True)
    path = os.path.join(cache, name)
    if not os.path.exists(path):
        urllib.request.urlretrieve(SOURCES[name], path)
    return open(path, encoding='utf-8').read()


def bare(s):
    return s.replace('\ufe0f', '')


def unicode_entries(text):
    """Base emoji by bare string: name, version, toned variants (matched by
    name, not file order: two-tone pairs follow the women's entry)."""
    line_re = re.compile(r'^([0-9A-F ]+?)\s*;\s*([a-z-]+)\s*#\s*(\S+)\s+E(\d+\.\d+)\s+(.*)$')
    group, by_name, by_bare = None, {}, {}
    for raw in text.splitlines():
        if raw.startswith('# group:'):
            group = raw[len('# group:'):].strip()
        m = line_re.match(raw)
        if not m or m.group(2) != 'fully-qualified' or group == 'Component':
            continue
        cps = [int(x, 16) for x in m.group(1).split()]
        s, version, name = ''.join(chr(c) for c in cps), m.group(4), m.group(5)
        if any(c in TONES for c in cps):
            head, _, quals = name.partition(': ')
            rest = [q for q in quals.split(', ') if q and not q.endswith('skin tone')]
            base = by_name.get(head + ': ' + ', '.join(rest) if rest else head) or by_name.get(head)
            if base is not None:
                base['tones'].append((s, version))
            continue
        entry = {'emoji': s, 'name': name, 'version': version, 'tones': []}
        by_name[name] = entry
        by_bare[bare(s)] = entry
    return by_bare


def keywords(*xml_texts):
    out = {}
    for text in xml_texts:
        for a in ET.fromstring(text.encode('utf-8')).iter('annotation'):
            if a.get('type') == 'tts' or not a.text:
                continue
            words = [w.strip().lower() for w in a.text.split('|') if w.strip()]
            out.setdefault(bare(a.get('cp')), words)
    return out


def main():
    src = sys.argv[sys.argv.index('--src') + 1] if '--src' in sys.argv else None
    apple = json.load(open(os.path.join(ROOT, 'shared/emoji/sources/apple-keyboard-ios26.5.json'), encoding='utf-8'))
    uni = unicode_entries(source('emoji-test.txt', src))
    kw = keywords(source('annotations_en.xml', src), source('annotationsDerived_en.xml', src))
    lines, missing = [], []
    for tab, cat in TABS:
        for e in apple['tabs'][tab]:
            u = uni.get(bare(e))
            if u is None:
                missing.append(e)
                continue
            name = u['name']
            # Keywords the name doesn't already say.
            said = set(re.findall(r"[\w']+", name.lower()))
            extra = [w for w in kw.get(bare(e), []) if w != name.lower() and not set(re.findall(r"[\w']+", w)) <= said]
            tones = [t for t, _ in u['tones']]
            versions = sorted({v for _, v in u['tones']})
            tone_versions = versions[0] if len(versions) == 1 else ','.join(v for _, v in u['tones'])
            lines.append('\t'.join([cat, e, u['version'], name, '|'.join(extra), ','.join(tones),
                                    tone_versions if tones else '']))
    if missing:
        sys.exit('not in emoji-test.txt: ' + ' '.join(missing))
    on_board = {bare(l.split('\t')[1]) for l in lines}
    if any(bare(e) not in on_board for e in SEED):
        sys.exit('seed emoji not on the board: ' + ' '.join(e for e in SEED if bare(e) not in on_board))
    head = [
        '# Glyf emoji board: every emoji on Apple\'s keyboard (iOS 26.5), in its tabs and order.',
        '# tab, emoji, Emoji version, name, keywords, skin-tone variants, their versions (one, or one each).',
        '# Built by tools/emoji/build.py from Unicode emoji-test.txt 17.0 and CLDR 48.2 annotations',
        '# (Copyright Unicode, Inc., Unicode License v3: shared/emoji/LICENSE-UNICODE.txt).',
        '# seed: ' + ' '.join(SEED),
    ]
    table = '\n'.join(head + lines) + '\n'
    open(os.path.join(ROOT, 'shared/emoji/emoji.tsv'), 'w', encoding='utf-8').write(table)
    assets = os.path.join(ROOT, 'app/android/app/src/main/assets')
    os.makedirs(assets, exist_ok=True)
    open(os.path.join(assets, 'emoji.tsv'), 'w', encoding='utf-8').write(table)
    swift_path = os.path.join(ROOT, 'app/ios/GlyfKeyboard/Design/EmojiData.swift')
    swift = open(swift_path, encoding='utf-8').read()
    start, end = '    // GENERATED by tools/emoji/build.py: do not edit.\n', '    // END GENERATED\n'
    a, b = swift.index(start) + len(start), swift.index(end)
    body = '    static let table = #"""\n' + table + '"""#\n'
    open(swift_path, 'w', encoding='utf-8').write(swift[:a] + body + swift[b:])
    counts = {}
    for l in lines:
        counts[l.split('\t')[0]] = counts.get(l.split('\t')[0], 0) + 1
    toned = sum(1 for l in lines if l.split('\t')[5])
    print(len(lines), 'emoji', counts, toned, 'with skin tones,', len(table.encode('utf-8')) // 1024, 'KB')


if __name__ == '__main__':
    main()

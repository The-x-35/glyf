#!/usr/bin/env python3
"""Builds the keyboard themes' key-face fonts (docs/THEMES.md §4.4).

    python3 tools/gen_theme_fonts.py SRC_DIR

SRC_DIR holds what the google/fonts repo publishes, one folder per family as
in its ofl/ tree (SRC_DIR/jost/Jost[wght].ttf, SRC_DIR/jost/OFL.txt):

    B=https://raw.githubusercontent.com/google/fonts/main/ofl
    curl -fL -o SRC_DIR/jost/Jost[wght].ttf "$B/jost/Jost%5Bwght%5D.ttf"
    curl -fL -o SRC_DIR/jost/OFL.txt "$B/jost/OFL.txt"

The family folder is the last part of each theme's font.source in
shared/themes/themes.json. Output goes to app/assets/fonts/themes/: one copy
that the Flutter previews declare in pubspec.yaml and the Android keyboard
reads from flutter_assets (like Inter). `--out DIR` writes elsewhere (the
iPhone keyboard's copy lives in app/ios/GlyfKeyboard/Fonts/).

Names: a static file keeps its published name (CourierPrime-Regular.ttf), an
instanced variable one becomes <Family>-<Weight>.ttf (Jost-Regular.ttf,
CormorantGaramond-SemiBold.ttf), and a Reserved Font Name file keeps its
name, its "[wght]" written "-Variable" in the app's copy (out_name).

- No Reserved Font Name: instanced to the theme's one weight (variable files)
  and subset to Basic Latin, Latin-1, General Punctuation and the currency
  signs the keyboard draws.
- A Reserved Font Name (rfn true): copied unmodified; a variable one is set to
  its weight at run time.
Each font's OFL.txt goes next to it as <Family>-OFL.txt.

Needs fonttools (pip install fonttools).
"""
import json
import os
import shutil
import sys

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'app', 'assets', 'fonts', 'themes')
UNICODES = ([*range(0x20, 0x7F)] + [*range(0xA0, 0x100)] + [*range(0x2010, 0x2028)]
            + [0x20A9, 0x20AC, 0x20B9])


WEIGHTS = {100: 'Thin', 200: 'ExtraLight', 300: 'Light', 400: 'Regular', 500: 'Medium',
           600: 'SemiBold', 700: 'Bold', 800: 'ExtraBold', 900: 'Black'}


def family_name(f):
    return f['family'].replace(' ', '')


def out_name(f, app=True):
    """The shipped file name. The iPhone keyboard's copy keeps a Reserved
    Font Name file's published name; the app's copy spells its "[wght]" as
    "-Variable" (Orbitron-Variable.ttf, like Inter-Variable.ttf), because
    Flutter percent-encodes brackets in asset paths and the Android keyboard
    opens these by name."""
    if f.get('rfn') or '[' not in f['file']:
        return f['file'].replace('[wght]', '-Variable') if app else f['file']
    return '%s-%s.ttf' % (family_name(f), WEIGHTS[f['weight']])


def main():
    args = sys.argv[1:]
    out = OUT
    if '--out' in args:
        i = args.index('--out')
        out = os.path.abspath(args[i + 1])
        del args[i:i + 2]
    if len(args) != 1:
        sys.exit(__doc__)
    src = args[0]
    themes = json.load(open(os.path.join(ROOT, 'shared', 'themes', 'themes.json')))
    os.makedirs(out, exist_ok=True)
    done = set()
    for t in themes:
        f = t.get('font') or {}
        if 'file' not in f or f['file'] in done:
            continue
        done.add(f['file'])
        slug = f['source'].rstrip('/').rsplit('/', 1)[1]
        path = os.path.join(src, slug, f['file'])
        dest = os.path.join(out, out_name(f, app=(out == OUT)))
        if f.get('rfn'):
            shutil.copyfile(path, dest)
        else:
            font = TTFont(path)
            if 'fvar' in font:
                font = instancer.instantiateVariableFont(font, {'wght': f['weight']})
            opts = subset.Options()
            opts.layout_features = ['*']
            opts.name_IDs = ['*']
            opts.name_languages = ['*']
            opts.notdef_outline = True
            opts.glyph_names = False
            sub = subset.Subsetter(opts)
            sub.populate(unicodes=UNICODES)
            sub.subset(font)
            font.save(dest)
        shutil.copyfile(os.path.join(src, slug, 'OFL.txt'),
                        os.path.join(out, family_name(f) + '-OFL.txt'))
        print('%-28s %7d bytes%s' % (os.path.basename(dest), os.path.getsize(dest),
                                     ' (unmodified, RFN)' if f.get('rfn') else ''))


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Re-checks every keyboard theme in themes.json against docs/THEMES.md §5.3.

    python3 shared/themes/check_contrast.py        # prints failures, exit 1 if any

Text >= 4.5:1, the bound-key dot >= 3:1 on its key. Keys against the Android
board (each stop) and the iPhone sheet of the variant's mode >= 1.15:1: a key
reads by its fill and Apple's 1pt bottom edge (Apple's own light keys are
1.27:1). The first pass demanded 3:1 here, which forced dark slabs onto the
light sheet and an outline on every key (Arpit, 2026-10-17: "v bad
aesthetically"). A key's boundary
may come from its fill, its 1pt border, or its 1pt bottom edge (a shadow with
offset 1 and radius 0, composited over the background).
"""
import json, os, sys

KEY_EDGE = 1.15

SHEETS = {'light': ['#E2E4E8', '#D1D4D9'], 'dark': ['#1B1B1D', '#292929']}

def rgb(c):
    c = c.lstrip('#')
    return [int(c[i:i + 2], 16) / 255 for i in (0, 2, 4)]

def lum(c):
    f = lambda v: v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = (f(v) for v in rgb(c))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b

def ratio(a, b):
    x, y = sorted((lum(a), lum(b)))
    return (y + 0.05) / (x + 0.05)

def blend(a, b, t):
    return '#' + ''.join('%02X' % round((x + (y - x) * t) * 255) for x, y in zip(rgb(a), rgb(b)))

def boundary(fill, cls, bg, v):
    best = ratio(fill, bg)
    b = v['border']
    if b and cls in b['appliesTo']:
        best = max(best, ratio(b['color'], bg))
    s = v['shadow']
    if s['offsetY'] >= 1 and s['radius'] == 0 and s['alpha'] > 0:
        best = max(best, ratio(blend(bg, s['color'], s['alpha']), bg))
    return best

def check(theme, mode, v):
    errs = []
    def need(what, val, lo):
        if val < lo - 1e-9:
            errs.append('%s %.2f < %.1f' % (what, val, lo))
    tex = theme.get('texture') or {}
    amp = tex.get('amplitude', 0) if (tex.get('targetIos') == 'keys' or 'keys' in tex.get('targetAndroid', '')) else 0
    need('key text', ratio(v['keyText'], blend(v['letterKey']['fill'], v['keyText'], amp)), 4.5)
    need('function glyph', ratio(v['functionGlyph'], v['functionKey']['fill']), 4.5)
    for k, o in v['keyOverrides'].items():
        need(k + ' glyph', ratio(o['glyph'], o['fill']), 4.5)
    need('return text', ratio(v['returnPrimary']['text'], v['returnPrimary']['fill']), 4.5)
    need('popup text', ratio(v['popup']['text'], v['popup']['fill']), 4.5)
    strip = v['board']['colors'] if v['strip']['background'] == 'board' else [v['strip']['background']]
    need('strip text', min(ratio(v['strip']['text'], s) for s in strip), 4.5)
    need('chip accent', ratio(v['chip']['accent'], v['chip']['face']), 4.5)
    need('bound dot', ratio(v['boundDot'], v['letterKey']['fill']), 3.0)
    keys = [('letter', v['letterKey']['fill']), ('function', v['functionKey']['fill']),
            ('space', v['spaceKey']['fill']), ('return', v['returnPrimary']['fill'])]
    keys += [('function', o['fill']) for o in v['keyOverrides'].values()]
    for where, bgs in (('board', v['board']['colors']), ('iPhone sheet', SHEETS[mode])):
        for cls, fill in keys:
            need('%s key vs %s' % (cls, where), min(boundary(fill, cls, bg, v) for bg in bgs), KEY_EDGE)
    return errs

def main():
    here = os.path.dirname(os.path.abspath(__file__))
    themes = json.load(open(os.path.join(here, 'themes.json')))
    bad = 0
    for t in themes:
        for mode in ('light', 'dark'):
            for e in check(t, mode, t['variants'][mode]):
                print('%s %s: %s' % (t['id'], mode, e))
                bad += 1
    print('%d themes, %d variants, %d failures' % (len(themes), 2 * len(themes), bad))
    sys.exit(1 if bad else 0)

if __name__ == '__main__':
    main()

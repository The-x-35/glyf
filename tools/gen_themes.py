#!/usr/bin/env python3
"""Writes the iOS keyboard's theme table from shared/themes/themes.json.

    python3 tools/gen_themes.py          # writes the Swift file
    python3 tools/gen_themes.py --check  # exit 1 if it is out of date

Output: app/ios/GlyfKeyboard/Design/KeyboardThemes.swift. Never edit that
file by hand and never copy a hex out of the JSON: change themes.json, run
shared/themes/check_contrast.py, then run this (docs/THEMES.md §8.2).

The iPhone keyboard paints no board (§0.3), so the board colours and the
strip background stay out of the Swift table; everything else iOS uses is
in it, for both variants: the key fills per class and their pressed shades,
the ink and the function glyph, the primary return, the shift and delete
overrides, the press popup, the chip's face and accent, the bound-key dot,
the shadow, the border, the font, the glyph style, the sound pack and the
key texture, and each variant's finish (shared/themes/styles.py): the faces
per key class, the legend style and the ornaments, as typed structs. A
theme's ornaments are one static table, shared by both variants when they
match.
"""
import json, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'shared', 'themes', 'themes.json')
OUT = os.path.join(ROOT, 'app', 'ios', 'GlyfKeyboard', 'Design', 'KeyboardThemes.swift')

# The roles each sound pack has its own sample for, as files under
# GlyfKeyboard/Sounds/ (tools/gen_theme_sounds.py). A role a pack leaves out
# plays the letter's sample, and a pack with no letter sample (sonar) keeps
# the system click for it.
SOUND_ROLES = {
    'system': [],
    'typewriter': ['letter', 'space', 'delete', 'return'],
    'shutter': ['letter', 'return'],
    'wood': ['letter', 'return'],
    'mech': ['letter', 'space'],
    'synth': ['letter', 'return'],
    'sonar': ['return'],
}


# The key textures iOS draws (§3: Marble's veins; Rose Gold's satin sheen on
# its function keys, a gradient rather than a picture). Any other theme with
# an iOS key texture fails the run until the keyboard knows how to draw it.
KEY_TEXTURES = {'marble': 'veins', 'rosegold': 'satin'}


def color(hexstr):
    h = hexstr.lstrip('#').upper()
    assert len(h) == 6, hexstr
    return '0x%s' % h


def swift_str(s):
    return '"%s"' % s.replace('\\', '\\\\').replace('"', '\\"')


def fill(f):
    return 'ThemeFill(fill: %s, pressed: %s)' % (color(f['fill']), color(f['pressed']))


def override(o):
    if not o:
        return 'nil'
    return 'ThemeOverride(fill: %s, glyph: %s, pressed: %s)' % (
        color(o['fill']), color(o['glyph']), color(o['pressed']))


def num(v):
    t = ('%.6f' % float(v)).rstrip('0').rstrip('.')
    return '0' if t in ('-0', '') else t


def per_mode(value, mode):
    """A colour that is either one hex or a hex per mode."""
    return value[mode] if isinstance(value, dict) else value


ROLES = {'ink': '.ink', 'fnInk': '.fnInk', 'accent': '.accent', 'accentInk': '.accentInk', 'fill': '.fill'}
TEXTURES = os.path.join(ROOT, 'shared', 'themes', 'textures')
# Symbols iOS would draw as colour emoji: asked for as text (U+FE0E), as
# the reference canvas draws them.
TEXT_PRESENTATION = set('\u2660\u2663\u2665\u2666')


def role(c, mode, where):
    c = per_mode(c, mode)
    if c in ROLES:
        return ROLES[c]
    if isinstance(c, str) and c.startswith('#'):
        return '.hex(%s)' % color(c)
    sys.exit('unknown colour role %r in %s' % (c, where))


def face(f, mode, where):
    tex = f.get('texture')
    if tex and not os.path.exists(os.path.join(TEXTURES, tex + '.png')):
        sys.exit('no texture %s.png for %s' % (tex, where))
    if f.get('shape', 'key') not in ('key', 'round'):
        sys.exit('unknown face shape in %s' % where)
    rnd = f.get('shape') == 'round'
    if rnd and not f.get('ring'):
        sys.exit('a round face needs a ring in %s' % where)
    sheen = f.get('sheen') or [0, 0]
    return ('ThemeFace(texture: %s, textureAlpha: %s, sheenTop: %s, sheenBottom: %s, highlight: %s, '
            'gloss: %s, metal: %s, fill2: %s, round: %s, ring: %s)') % (
        swift_str(tex) if tex else 'nil', num(f.get('textureAlpha', 0)), num(sheen[0]), num(sheen[1]),
        num(f.get('highlight', 0)), num(f.get('gloss', 0)), num(f.get('metal', 0)),
        color(per_mode(f['fill2'], mode)) if f.get('fill2') else 'nil',
        'true' if rnd else 'false', color(per_mode(f['ring'], mode)) if rnd else 'nil')


LEGENDS = ('ink', 'engraved', 'letterpress', 'foil', 'glow')


def legend(lg, where):
    if lg['style'] not in LEGENDS:
        sys.exit('unknown legend style in %s' % where)
    foil = lg.get('foil') or []
    if lg['style'] == 'foil' and len(foil) != 3:
        sys.exit('foil needs three colours in %s' % where)
    return 'ThemeLegend(style: .%s, foil: [%s])' % (lg['style'], ', '.join(color(c) for c in foil))


TARGETS = {'letter': '.letter', 'function': '.function', 'space': '.space', 'return': '.ret',
           'shift': '.shift', 'delete': '.delete'}
FONTS = ('system', 'mono', 'theme')


def ornament_op(o, mode, where):
    t, p = o['t'], o['p']
    c = (', color: %s' % role(o['color'], mode, where)) if o.get('color') else ''
    if t == 'line':
        assert len(p) == 4, where
        return '.line(%s, w: %s%s)' % (', '.join(num(v) for v in p), num(o['w']), c)
    if t == 'poly':
        assert len(p) >= 6 and len(p) % 2 == 0, where
        return '.poly([%s]%s)' % (', '.join(num(v) for v in p), c)
    if t == 'circle':
        assert len(p) == 3, where
        w = (', w: %s' % num(o['w'])) if o.get('w') else ''
        return '.circle(%s%s%s)' % (', '.join(num(v) for v in p), w, c)
    if t == 'rect':
        assert len(p) == 5, where
        w = (', w: %s' % num(o['w'])) if o.get('w') else ''
        return '.rect(%s%s%s)' % (', '.join(num(v) for v in p), w, c)
    if t == 'text':
        if o['font'] not in FONTS:
            sys.exit('unknown ornament font in %s' % where)
        s = o['s']
        if any(ch in TEXT_PRESENTATION for ch in s):
            s += '\ufe0e'
        return '.text(%s, %s, %s, size: %s, font: .%s, weight: %d, tracking: %s%s)' % (
            swift_str(s), num(p[0]), num(p[1]), num(o['size']), o['font'], int(o['weight']),
            num(o.get('tracking', 0)), c)
    sys.exit('unknown ornament op %s in %s' % (t, where))


def ornaments(orns, mode, where, ind):
    p = ' ' * ind
    if not orns:
        return '[]'
    out = ['[']
    for o in orns:
        if o['on'] not in TARGETS or o['anchor'] not in ('left', 'center', 'right'):
            sys.exit('bad ornament target or anchor in %s' % where)
        out.append(p + '    ThemeOrnament(on: %s, anchor: .%s, color: %s, alpha: %s, ops: [' % (
            TARGETS[o['on']], o['anchor'], role(o['color'], mode, where), num(o['alpha'])))
        for op in o['ops']:
            out.append(p + '        ' + ornament_op(op, mode, where) + ',')
        out.append(p + '    ]),')
    out.append(p + ']')
    return '\n'.join(out)


def ornament_name(tid, mode, shared):
    return 'ornaments_%s' % tid if shared else 'ornaments_%s_%s' % (tid, mode)


def ornaments_shared(t):
    return t['variants']['light']['style']['ornaments'] == t['variants']['dark']['style']['ornaments']


def style(t, mode, ind):
    p = ' ' * ind
    st = t['variants'][mode]['style']
    where = '%s %s' % (t['id'], mode)
    faces = st['faces']
    for k in ('letter', 'function', 'space', 'return'):
        if k not in faces:
            sys.exit('no %s face in %s' % (k, where))
    lines = [
        'ThemeStyle(',
        '    faces: ThemeFaces(',
        '        letter: %s,' % face(faces['letter'], mode, where),
        '        function: %s,' % face(faces['function'], mode, where),
        '        space: %s,' % face(faces['space'], mode, where),
        '        ret: %s),' % face(faces['return'], mode, where),
        '    legend: %s,' % legend(st['legend'], where),
        '    returnLegend: %s,' % legend(st['returnLegend'], where),
        '    ornaments: KeyboardTheme.%s)' % ornament_name(t['id'], mode, ornaments_shared(t)),
    ]
    return ('\n' + p).join(lines)


def variant(v, ind, theme=None, mode=None):
    p = ' ' * ind
    s, b = v['shadow'], v['border']
    border = 'nil' if not b else 'ThemeBorder(color: %s, width: %s, appliesTo: [%s])' % (
        color(b['color']), b['width'], ', '.join('.' + c.replace('return', 'ret') for c in b['appliesTo']))
    lines = [
        'ThemeVariant(',
        '    letter: %s,' % fill(v['letterKey']),
        '    function: %s,' % fill(v['functionKey']),
        '    space: %s,' % fill(v['spaceKey']),
        '    keyText: %s, functionGlyph: %s,' % (color(v['keyText']), color(v['functionGlyph'])),
        '    returnFill: %s, returnText: %s, returnPressed: %s,' % (
            color(v['returnPrimary']['fill']), color(v['returnPrimary']['text']),
            color(v['returnPrimary']['pressed'])),
        '    shift: %s,' % override(v['keyOverrides'].get('shift')),
        '    delete: %s,' % override(v['keyOverrides'].get('delete')),
        '    popupFill: %s, popupText: %s,' % (color(v['popup']['fill']), color(v['popup']['text'])),
        '    chipFace: %s, chipAccent: %s,' % (color(v['chip']['face']), color(v['chip']['accent'])),
        '    boundDot: %s,' % color(v['boundDot']),
        '    shadow: ThemeShadow(color: %s, alpha: %r, offsetY: %r, radius: %r),' % (
            color(s['color']), float(s['alpha']), float(s['offsetY']), float(s['radius'])),
        '    border: %s,' % border,
        '    style: %s)' % style(theme, mode, ind + 4),
    ]
    return ('\n' + p).join(lines)


def font(f):
    if f['family'] == 'system':
        return 'nil'
    file = f['file']
    if '[' in file and not f['rfn']:
        # Instanced to the one weight by tools/gen_theme_fonts.py.
        weights = {400: 'Regular', 500: 'Medium', 600: 'SemiBold', 700: 'Bold'}
        file = '%s-%s.ttf' % (file.split('[')[0], weights[f['weight']])
    name, ext = file.rsplit('.', 1)
    variable = '[' in file
    return 'ThemeFont(family: %s, file: %s, ext: %s, weight: %d, variable: %s)' % (
        swift_str(f['family']), swift_str(name), swift_str(ext), f['weight'],
        'true' if variable else 'false')


def sound(s):
    roles = SOUND_ROLES[s['pack']]
    return 'ThemeSoundPack(name: %s, roles: [%s])' % (
        swift_str(s['pack']), ', '.join('.' + r.replace('return', 'ret') for r in roles))


def render(themes):
    out = [
        '// Generated by tools/gen_themes.py from shared/themes/themes.json.',
        '// Do not edit: change the JSON, run shared/themes/check_contrast.py, then',
        '// run the generator (docs/THEMES.md §8.2).',
        '',
        'import UIKit',
        '',
        'extension KeyboardTheme {',
        '    /// The %d themes in the picker\'s order: materials, stories, archetypes.' % len(themes),
        '    static let all: [KeyboardTheme] = [',
    ]
    for t in themes:
        tex = t.get('texture')
        out += [
            '        KeyboardTheme(',
            '            id: %s, name: %s,' % (swift_str(t['id']), swift_str(t['name'])),
            '            font: %s,' % font(t['font']),
            '            glyphStyle: .%s,' % t['glyphStyle'],
            '            sound: %s,' % sound(t['sound']),
            '            keyTexture: %s,' % (
                'nil' if not tex or tex.get('targetIos', 'none') == 'none'
                else 'ThemeTexture(kind: .%s, amplitude: %r)' % (KEY_TEXTURES[t['id']], float(tex['amplitude']))),
            '            light: %s,' % variant(t['variants']['light'], 12, t, 'light'),
            '            dark: %s),' % variant(t['variants']['dark'], 12, t, 'dark'),
        ]
    out += ['    ]', '']
    out += ['    // MARK: Ornaments (shared/themes/styles.py), in units of the key\'s height', '']
    for t in themes:
        modes = ['light'] if ornaments_shared(t) else ['light', 'dark']
        for mode in modes:
            out.append('    static let %s: [ThemeOrnament] = %s' % (
                ornament_name(t['id'], mode, len(modes) == 1),
                ornaments(t['variants'][mode]['style']['ornaments'], mode, '%s %s' % (t['id'], mode), 4)))
            out.append('')
    out += ['}', '']
    return '\n'.join(out)


def main():
    themes = json.load(open(SRC))
    for t in themes:
        if t['sound']['pack'] not in SOUND_ROLES:
            sys.exit('unknown sound pack %s in %s' % (t['sound']['pack'], t['id']))
        tex = t.get('texture') or {}
        if tex.get('targetIos', 'none') not in ('none', 'keys'):
            sys.exit('unknown iOS texture target in %s' % t['id'])
        if tex.get('targetIos') == 'keys' and t['id'] not in KEY_TEXTURES:
            sys.exit('no iOS key texture for %s' % t['id'])
    text = render(themes)
    if '--check' in sys.argv:
        current = open(OUT).read() if os.path.exists(OUT) else ''
        if current != text:
            sys.exit('%s is out of date: run tools/gen_themes.py' % OUT)
        return
    with open(OUT, 'w') as f:
        f.write(text)
    print('wrote %s (%d themes)' % (os.path.relpath(OUT, ROOT), len(themes)))


if __name__ == '__main__':
    main()

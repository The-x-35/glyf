#!/usr/bin/env python3
"""Writes the app's keyboard-theme table from shared/themes/themes.json.

    python3 tools/gen_themes_dart.py

Output: app/lib/core/themes.dart, which the Keyboard screen's theme picker
draws its previews from (docs/THEMES.md §8.2), and the theme-font families
in app/pubspec.yaml (between its BEGIN/END theme fonts markers) from the
files tools/gen_theme_fonts.py writes to app/assets/fonts/themes/. Rerun after any change to the JSON; never edit
the output by hand.
"""
import json
import os
import shutil

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'shared', 'themes', 'themes.json')
OUT = os.path.join(ROOT, 'app', 'lib', 'core', 'themes.dart')
PUBSPEC = os.path.join(ROOT, 'app', 'pubspec.yaml')
TEXTURES = os.path.join(ROOT, 'shared', 'themes', 'textures')
APP_TEXTURES = os.path.join(ROOT, 'app', 'assets', 'themes', 'textures')
BEGIN = '    # BEGIN theme fonts (written by tools/gen_themes_dart.py)\n'
END = '    # END theme fonts\n'
WEIGHTS = {100: 'Thin', 200: 'ExtraLight', 300: 'Light', 400: 'Regular', 500: 'Medium',
           600: 'SemiBold', 700: 'Bold', 800: 'ExtraBold', 900: 'Black'}


def font_file(f):
    """The app's copy's name (tools/gen_theme_fonts.py's out_name)."""
    if f.get('rfn') or '[' not in f['file']:
        return f['file'].replace('[wght]', '-Variable')
    return '%s-%s.ttf' % (f['family'].replace(' ', ''), WEIGHTS[f['weight']])


def write_pubspec(themes):
    """The theme fonts' families in pubspec.yaml, between the markers."""
    lines = [BEGIN,
             "    # The keyboard themes' key faces (docs/THEMES.md §4.4, tools/gen_theme_fonts.py):\n",
             "    # the picker's previews, and the Android keyboard reads the same files\n",
             "    # from flutter_assets.\n"]
    seen = {}
    for t in themes:
        f = t.get('font') or {}
        if 'file' in f:
            seen.setdefault(f['family'], font_file(f))
    for family, name in seen.items():
        lines += ['    - family: %s\n' % family, '      fonts:\n',
                  '        - asset: assets/fonts/themes/%s\n' % name]
    lines.append(END)
    text = open(PUBSPEC).read()
    a = text.index(BEGIN)
    b = text.index(END) + len(END)
    with open(PUBSPEC, 'w') as fh:
        fh.write(text[:a] + ''.join(lines) + text[b:])


def copy_textures():
    """The finish textures into the app's assets (the picker and the Android
    keyboard both read them there); shared/themes/textures is the source."""
    os.makedirs(APP_TEXTURES, exist_ok=True)
    for name in sorted(os.listdir(TEXTURES)):
        if name.endswith('.png'):
            shutil.copyfile(os.path.join(TEXTURES, name), os.path.join(APP_TEXTURES, name))


def c(hex_):
    h = hex_.lstrip('#').upper()
    assert len(h) == 6, hex_
    return 'Color(0xFF%s)' % h


def s(v):
    return "'%s'" % v.replace('\\', '\\\\').replace("'", "\\'").replace('$', '\\$')


def fill(o):
    return 'KbFill(%s, %s)' % (c(o['fill']), c(o['pressed']))


def override(o):
    return 'null' if not o else 'KbFill(%s, %s, glyph: %s)' % (c(o['fill']), c(o['pressed']), c(o['glyph']))


def d(x):
    """A double literal, rounded so 1.7999999999999998 reads 1.8."""
    r = round(float(x), 5)
    return repr(r) if r != int(r) else '%d.0' % int(r)


def per_mode(x, mode):
    return x[mode] if isinstance(x, dict) else x


def face(o, mode):
    parts = []
    if o.get('texture'):
        parts += ['texture: %s' % s(o['texture']), 'textureAlpha: %s' % d(o['textureAlpha'])]
    for k in ('highlight', 'gloss', 'metal'):
        if o[k]:
            parts.append('%s: %s' % (k, d(o[k])))
    if o['sheen'][0] or o['sheen'][1]:
        parts += ['sheenTop: %s' % d(o['sheen'][0]), 'sheenBottom: %s' % d(o['sheen'][1])]
    if o.get('fill2'):
        parts.append('fill2: %s' % c(per_mode(o['fill2'], mode)))
    if o['shape'] == 'round':
        parts += ['round: true', 'ring: %s' % c(per_mode(o['ring'], mode))]
    return 'KbFace(%s)' % ', '.join(parts)


def legend(o, mode):
    parts = [s(o['style'])]
    if o.get('foil'):
        parts.append('foil: [%s]' % ', '.join(c(x) for x in o['foil']))
    if o.get('glow'):
        parts.append('glow: %s' % s(per_mode(o['glow'], mode)))
    return 'KbLegend(%s)' % ', '.join(parts)


def op(o, mode):
    parts = [s(o['t']), '[%s]' % ', '.join(d(x) for x in o['p'])]
    if 'w' in o:
        parts.append('w: %s' % d(o['w']))
    if o.get('color'):
        parts.append('color: %s' % s(per_mode(o['color'], mode)))
    if o['t'] == 'text':
        parts += ['s: %s' % s(o['s']), 'size: %s' % d(o['size']), 'font: %s' % s(o.get('font', 'system')),
                  'weight: %d' % o.get('weight', 400), 'tracking: %s' % d(o.get('tracking', 0))]
    return 'KbOp(%s)' % ', '.join(parts)


def style(st, mode):
    fa = st['faces']
    orns = ''.join('          KbOrnament(%s, %s, %s, %s, [\n%s          ]),\n' % (
        s(o['on']), s(o['anchor']), s(per_mode(o['color'], mode)), d(o['alpha']),
        ''.join('            %s,\n' % op(x, mode) for x in o['ops'])) for o in st['ornaments'])
    return ('KbStyle(\n        letter: %s,\n        function: %s,\n        space: %s,\n        ret: %s,\n'
            '        legend: %s,\n        returnLegend: %s,\n        ornaments: [%s],\n      )') % (
        face(fa['letter'], mode), face(fa['function'], mode), face(fa['space'], mode), face(fa['return'], mode),
        legend(st['legend'], mode), legend(st.get('returnLegend') or {'style': 'engraved'}, mode), ('\n' + orns + '        ') if orns else '')


def variant(v, mode):
    b = v['board']
    sh = v['shadow']
    bo = v['border']
    parts = [
        'board: [%s]' % ', '.join(c(x) for x in b['colors']),
        'boardAngle: %s' % ('null' if b['angle'] is None else float(b['angle'])),
        'letter: %s' % fill(v['letterKey']),
        'function: %s' % fill(v['functionKey']),
        'space: %s' % fill(v['spaceKey']),
        'keyText: %s' % c(v['keyText']),
        'functionGlyph: %s' % c(v['functionGlyph']),
        'returnPrimary: KbFill(%s, %s, glyph: %s)' % (
            c(v['returnPrimary']['fill']), c(v['returnPrimary']['pressed']), c(v['returnPrimary']['text'])),
        'shift: %s' % override(v['keyOverrides'].get('shift')),
        'delete: %s' % override(v['keyOverrides'].get('delete')),
        'shadow: KbShadow(%s, %s, %d, %d)' % (c(sh['color']), float(sh['alpha']), sh['offsetY'], sh['radius']),
        'border: %s' % ('null' if bo is None else 'KbBorder(%s, {%s})' % (
            c(bo['color']), ', '.join(s(x) for x in bo['appliesTo']))),
        'style: %s' % style(v['style'], mode),
    ]
    return 'KbVariant(\n' + ''.join('      %s,\n' % p for p in parts) + '    )'


def theme(t):
    f = t.get('font') or {}
    family = s(f['family']) if 'file' in f else 'null'
    weight = f.get('weight', 400)
    variable = 'true' if ('[wght]' in f.get('file', '') and f.get('rfn')) else 'false'
    sound = (t.get('sound') or {}).get('pack', 'system')
    return '''  KbTheme(
    id: %s,
    name: %s,
    category: %s,
    tier: %s,
    fontFamily: %s,
    fontWeight: %d,
    variableFont: %s,
    sound: %s,
    light: %s,
    dark: %s,
  ),
''' % (s(t['id']), s(t['name']), s(t['category']), s(t.get('tier', 'free')), family, weight, variable,
       s(sound), variant(t['variants']['light'], 'light'), variant(t['variants']['dark'], 'dark'))


HEADER = '''// GENERATED by tools/gen_themes_dart.py from shared/themes/themes.json.
// Do not edit by hand: change the JSON and rerun the script.

import 'dart:ui' show Color;

/// A key class's colour and its pressed shade; [glyph] for the keys that
/// carry their own (the return, a theme's shift or delete).
class KbFill {
  const KbFill(this.fill, this.pressed, {this.glyph});
  final Color fill;
  final Color pressed;
  final Color? glyph;
}

/// offsetY 1 with radius 0 is a 1pt edge under each key; radius 2 to 4 a glow.
class KbShadow {
  const KbShadow(this.color, this.alpha, this.offsetY, this.radius);
  final Color color;
  final double alpha;
  final int offsetY;
  final int radius;
}

/// A 1pt border drawn inside the key, on the classes named.
class KbBorder {
  const KbBorder(this.color, this.appliesTo);
  final Color color;
  final Set<String> appliesTo;
}

/// A key class's finish (shared/themes/styles.py; tools/theme_mock.py is the
/// reference drawing): [texture] names `assets/themes/textures/<name>.png`, laid
/// over the fill at [textureAlpha]; white from the top at [sheenTop] and
/// black from the bottom at [sheenBottom]; a 1px [highlight] along the top;
/// lacquer [gloss] over the top half; brushed [metal] bands; [fill2] this
/// mode's second fill (fill to fill2, diagonally). [round]: Typewriter's
/// round keycap, as wide as the key, in a chrome bezel of [ring].
class KbFace {
  const KbFace({
    this.texture,
    this.textureAlpha = 0,
    this.sheenTop = 0,
    this.sheenBottom = 0,
    this.highlight = 0,
    this.gloss = 0,
    this.metal = 0,
    this.fill2,
    this.round = false,
    this.ring,
  });
  final String? texture;
  final double textureAlpha;
  final double sheenTop;
  final double sheenBottom;
  final double highlight;
  final double gloss;
  final double metal;
  final Color? fill2;
  final bool round;
  final Color? ring;
}

/// ink, engraved, letterpress, foil ([foil]: three stops, top to bottom) or
/// glow ([glow] "self": the ink's own colour).
class KbLegend {
  const KbLegend(this.style, {this.foil, this.glow});
  final String style;
  final List<Color>? foil;
  final String? glow;
}

/// A vector primitive in key-height units from its ornament's anchor (x) and
/// the key's top (y): line, poly, circle, rect (filled, or stroked at [w])
/// or text [s] centred on its point.
class KbOp {
  const KbOp(this.t, this.p,
      {this.w = 0,
      this.color,
      this.s,
      this.size = 0,
      this.font = 'system',
      this.weight = 400,
      this.tracking = 0});
  final String t;
  final List<double> p;
  final double w;
  final String? color;
  final String? s;
  final double size;
  final String font;
  final int weight;
  final double tracking;
}

/// A theme's detail on the keys [on] names (space, return, shift, delete,
/// letter, or function: every function key but return), from its [anchor];
/// [color] a role (ink, fnInk, accent, accentInk, fill) or a hex, at [alpha].
class KbOrnament {
  const KbOrnament(this.on, this.anchor, this.color, this.alpha, this.ops);
  final String on;
  final String anchor;
  final String color;
  final double alpha;
  final List<KbOp> ops;
}

class KbStyle {
  const KbStyle({
    required this.letter,
    required this.function,
    required this.space,
    required this.ret,
    required this.legend,
    required this.returnLegend,
    required this.ornaments,
  });
  final KbFace letter;
  final KbFace function;
  final KbFace space;
  final KbFace ret;
  final KbLegend legend;

  /// The return key's glyph: always its own (engraved), never the theme's
  /// foil or glow, which vanish on a gold return.
  final KbLegend returnLegend;
  final List<KbOrnament> ornaments;

  /// letter, function, space or return.
  KbFace face(String cls) => switch (cls) {
        'letter' => letter,
        'space' => space,
        'return' => ret,
        _ => function,
      };
}

class KbVariant {
  const KbVariant({
    required this.board,
    required this.boardAngle,
    required this.letter,
    required this.function,
    required this.space,
    required this.keyText,
    required this.functionGlyph,
    required this.returnPrimary,
    required this.shift,
    required this.delete,
    required this.shadow,
    required this.border,
    required this.style,
  });

  /// One colour, or a two-stop gradient at [boardAngle] (CSS degrees).
  /// Painted on Android only; the iPhone keyboard sits on the system sheet.
  final List<Color> board;
  final double? boardAngle;
  final KbFill letter;
  final KbFill function;
  final KbFill space;
  final Color keyText;
  final Color functionGlyph;
  final KbFill returnPrimary;
  final KbFill? shift;
  final KbFill? delete;
  final KbShadow shadow;
  final KbBorder? border;

  /// The faces, legend and ornaments (shared/themes/styles.py).
  final KbStyle style;
}

/// Every texture a theme's face names (assets/themes/textures).
final Set<String> kbTextureNames = {
  for (final t in kbThemes)
    for (final v in [t.light, t.dark])
      for (final c in ['letter', 'function', 'space', 'return'])
        if (v.style.face(c).texture != null) v.style.face(c).texture!,
};

/// A keyboard theme (docs/THEMES.md §6). The "skin" setting holds its [id].
class KbTheme {
  const KbTheme({
    required this.id,
    required this.name,
    required this.category,
    required this.tier,
    required this.fontFamily,
    required this.fontWeight,
    required this.variableFont,
    required this.sound,
    required this.light,
    required this.dark,
  });

  final String id;
  final String name;

  /// material, story or archetype: the picker's groups.
  final String category;

  /// Paid-tier gating is not decided (THEMES.md §10.3): all "free" today.
  final String tier;

  /// The key-face family (pubspec.yaml), or null for today's face.
  final String? fontFamily;
  final int fontWeight;

  /// Still variable in the bundle (a Reserved Font Name file): draw it with
  /// a 'wght' of [fontWeight].
  final bool variableFont;

  /// The key-sound pack; "system" is today's click.
  final String sound;
  final KbVariant light;
  final KbVariant dark;

  KbVariant variant(bool dark) => dark ? this.dark : light;

  /// The id a setting names, or null for today's look.
  static KbTheme? byId(String? id) {
    for (final t in kbThemes) {
      if (t.id == id) return t;
    }
    return null;
  }
}

/// In the picker's order: materials, stories, archetypes.
const kbThemes = <KbTheme>[
'''


def main():
    themes = json.load(open(SRC))
    with open(OUT, 'w') as fh:
        fh.write(HEADER + ''.join(theme(t) for t in themes) + '];\n')
    write_pubspec(themes)
    copy_textures()
    print('wrote %s (%d themes) and the theme fonts in %s' % (
        os.path.relpath(OUT, ROOT), len(themes), os.path.relpath(PUBSPEC, ROOT)))


if __name__ == '__main__':
    main()

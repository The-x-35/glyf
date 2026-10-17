#!/usr/bin/env python3
"""Writes the Android keyboard's theme table from shared/themes/themes.json.

    python3 tools/gen_themes_kotlin.py

Output: app/android/app/src/main/kotlin/com/arpit/glyf/ime/KeyboardThemes.kt
(docs/THEMES.md §8.2: generate, don't transcribe). Colours become ARGB Ints,
so the table needs no android.* at all and JVM unit tests read it as is.
Rerun after any change to the JSON; never edit the output by hand.
"""
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, 'shared', 'themes', 'themes.json')
OUT = os.path.join(ROOT, 'app', 'android', 'app', 'src', 'main', 'kotlin',
                   'com', 'arpit', 'glyf', 'ime', 'KeyboardThemes.kt')

WEIGHTS = {100: 'Thin', 200: 'ExtraLight', 300: 'Light', 400: 'Regular', 500: 'Medium',
           600: 'SemiBold', 700: 'Bold', 800: 'ExtraBold', 900: 'Black'}


def font_file(f):
    """The shipped file's name (tools/gen_theme_fonts.py's rule)."""
    if f.get('rfn') or '[' not in f['file']:
        return f['file'].replace('[wght]', '-Variable')
    return '%s-%s.ttf' % (f['family'].replace(' ', ''), WEIGHTS[f['weight']])


def c(hex_):
    h = hex_.lstrip('#').upper()
    assert len(h) == 6, hex_
    return '0xFF%s.toInt()' % h


def s(v):
    return json.dumps(v, ensure_ascii=False).replace('$', '\\$')


def fill(o):
    return 'Fill(%s, %s)' % (c(o['fill']), c(o['pressed']))


def override(o):
    if not o:
        return 'null'
    return 'KeyOverride(%s, %s, %s)' % (c(o['fill']), c(o['glyph']), c(o['pressed']))


def f(x):
    """A Float literal, rounded so 1.7999999999999998 reads 1.8f."""
    r = round(float(x), 5)
    return ('%r' % r).replace('e', 'E') + 'f' if r != int(r) else '%d.0f' % int(r)


def per_mode(x, mode):
    """A colour the JSON gives once or per mode ({light, dark})."""
    return x[mode] if isinstance(x, dict) else x


def face(o, mode):
    fill2 = per_mode(o['fill2'], mode) if o.get('fill2') else None
    ring = per_mode(o['ring'], mode) if o.get('ring') else None
    return 'Face(%s, %s, %s, %s, %s, %s, %s, %s, %s, %s)' % (
        'null' if not o.get('texture') else s(o['texture']), f(o['textureAlpha']),
        f(o['sheen'][0]), f(o['sheen'][1]), f(o['highlight']), f(o['gloss']), f(o['metal']),
        'null' if fill2 is None else c(fill2), 'true' if o['shape'] == 'round' else 'false',
        'null' if ring is None else c(ring))


def legend(o, mode):
    foil = 'null' if not o.get('foil') else 'intArrayOf(%s)' % ', '.join(c(x) for x in o['foil'])
    glow = 'null' if not o.get('glow') else s(per_mode(o['glow'], mode))
    return 'Legend(%s, %s, %s)' % (s(o['style']), foil, glow)


def op(o, mode):
    args = ['%s' % s(o['t']), 'floatArrayOf(%s)' % ', '.join(f(x) for x in o['p'])]
    if 'w' in o:
        args.append('w = %s' % f(o['w']))
    if o.get('color'):
        args.append('color = %s' % s(per_mode(o['color'], mode)))
    if o['t'] == 'text':
        args += ['s = %s' % s(o['s']), 'size = %s' % f(o['size']), 'font = %s' % s(o.get('font', 'system')),
                 'weight = %d' % o.get('weight', 400), 'tracking = %s' % f(o.get('tracking', 0))]
    return 'Op(%s)' % ', '.join(args)


def ornaments(orns, mode, ind):
    if not orns:
        return 'emptyList()'
    pad = ' ' * ind
    out = []
    for o in orns:
        ops = ''.join('%s        %s,\n' % (pad, op(x, mode)) for x in o['ops'])
        out.append('%s    Ornament(%s, %s, %s, %s, listOf(\n%s%s    )),\n' % (
            pad, s(o['on']), s(o['anchor']), s(per_mode(o['color'], mode)), f(o['alpha']), ops, pad))
    return 'listOf(\n' + ''.join(out) + pad + ')'


def style(st, mode, ind):
    fa = st['faces']
    pad = ' ' * ind
    return ('Style(\n%s    letter = %s,\n%s    function = %s,\n%s    space = %s,\n%s    ret = %s,\n'
            '%s    legend = %s,\n%s    returnLegend = %s,\n%s    ornaments = %s,\n%s)') % (
        pad, face(fa['letter'], mode), pad, face(fa['function'], mode), pad, face(fa['space'], mode),
        pad, face(fa['return'], mode), pad, legend(st['legend'], mode), pad,
        legend(st.get('returnLegend') or {'style': 'engraved'}, mode), pad,
        ornaments(st['ornaments'], mode, ind + 4), pad)


def variant(v, ind, mode):
    b = v['board']
    sh = v['shadow']
    bo = v['border']
    st = v['strip']['background']
    lines = [
        'board = intArrayOf(%s)' % ', '.join(c(x) for x in b['colors']),
        'boardAngle = %s' % ('null' if b['angle'] is None else '%sf' % b['angle']),
        'letter = %s' % fill(v['letterKey']),
        'function = %s' % fill(v['functionKey']),
        'space = %s' % fill(v['spaceKey']),
        'keyText = %s' % c(v['keyText']),
        'functionGlyph = %s' % c(v['functionGlyph']),
        'returnPrimary = KeyOverride(%s, %s, %s)' % (
            c(v['returnPrimary']['fill']), c(v['returnPrimary']['text']), c(v['returnPrimary']['pressed'])),
        'shift = %s' % override(v['keyOverrides'].get('shift')),
        'delete = %s' % override(v['keyOverrides'].get('delete')),
        'popupFill = %s' % c(v['popup']['fill']),
        'popupText = %s' % c(v['popup']['text']),
        'stripBackground = %s' % ('null' if st == 'board' else c(st)),
        'stripText = %s' % c(v['strip']['text']),
        'chipFace = %s' % c(v['chip']['face']),
        'chipAccent = %s' % c(v['chip']['accent']),
        'boundDot = %s' % c(v['boundDot']),
        'shadow = Shadow(%s, %sf, %d, %d)' % (c(sh['color']), sh['alpha'], sh['offsetY'], sh['radius']),
        'border = %s' % ('null' if bo is None else 'Border(%s, %d, setOf(%s))' % (
            c(bo['color']), bo['width'], ', '.join(s(x) for x in bo['appliesTo']))),
        'style = %s' % style(v['style'], mode, ind + 4),
    ]
    pad = ' ' * ind
    return 'Variant(\n' + ''.join('%s    %s,\n' % (pad, l) for l in lines) + pad + ')'


def fn_name(t):
    """Each theme is built in its own function: one initializer holding
    every ornament would pass the JVM's 64KB method limit."""
    return 'theme' + ''.join(p[:1].upper() + p[1:] for p in t['id'].replace('-', '_').split('_'))


def theme(t):
    f = t.get('font') or {}
    if 'file' in f:
        font = 'Font(%s, %s, %d, %s, %s)' % (
            s(f['family']), s('flutter_assets/assets/fonts/themes/' + font_file(f)), f['weight'],
            # Only a Reserved Font Name file ships still variable.
            'true' if ('[wght]' in f['file'] and f.get('rfn')) else 'false',
            'true' if f.get('rfn') else 'false')
    else:
        font = 'null'
    tex = t.get('texture')
    # texture.kind names a texture in ThemeTextures' library; without one
    # the theme's id stands in (the first JSON's themes, mapped there).
    texture = 'null' if not tex else 'Texture(%s, %s, %s, %sf)' % (
        s(tex.get('kind', t['id'])), s(tex['targetAndroid']), s(tex['targetIos']), tex['amplitude'])
    sound = (t.get('sound') or {}).get('pack', 'system')
    return '''    private fun %s() = Theme(
            id = %s,
            name = %s,
            category = %s,
            tier = %s,
            heroMode = %s,
            font = %s,
            glyphStyle = %s,
            soundPack = %s,
            texture = %s,
            light = %s,
            dark = %s,
        )

''' % (fn_name(t), s(t['id']), s(t['name']), s(t['category']), s(t.get('tier', 'free')), s(t['heroMode']),
       font, s(t['glyphStyle']), s(sound), texture,
       variant(t['variants']['light'], 12, 'light'), variant(t['variants']['dark'], 12, 'dark'))


HEADER = '''package com.arpit.glyf.ime

// GENERATED by tools/gen_themes_kotlin.py from shared/themes/themes.json.
// Do not edit by hand: change the JSON and rerun the script.

/**
 * The keyboard themes (docs/THEMES.md §6), one light and one dark variant
 * each. Colours are ARGB. A theme recolours, repaints the board and swaps the
 * key-face font and sound; it never changes a size (§0.1).
 */
object KeyboardThemes {
    class Fill(val fill: Int, val pressed: Int)
    /** A key drawn apart from its class: fill, glyph (or text) and pressed. */
    class KeyOverride(val fill: Int, val glyph: Int, val pressed: Int)
    /** offsetY 1 and radius 0 is a hard 1dp edge; radius 2 to 4 a glow. */
    class Shadow(val color: Int, val alpha: Float, val offsetY: Int, val radius: Int)
    /** Drawn inside the key's bounds, on the classes named (letter,
     *  function, space, return). */
    class Border(val color: Int, val width: Int, val appliesTo: Set<String>)
    /** [asset] is the path inside the APK's assets; [variable] files take
     *  their [weight] as a 'wght' setting at load. */
    class Font(val family: String, val asset: String, val weight: Int, val variable: Boolean, val rfn: Boolean)
    /** [kind] names one of ThemeTextures' textures; [android] says where
     *  it goes there (board, board+keys or none). */
    class Texture(val kind: String, val android: String, val ios: String, val amplitude: Float)

    /**
     * A key class's finish (shared/themes/styles.py; tools/theme_mock.py is
     * the reference drawing). [texture] names shared/themes/textures/<name>.png,
     * tiled at one image pixel per device pixel over the fill at
     * [textureAlpha]; [sheenTop] white fading in from the top and
     * [sheenBottom] black from the bottom; [highlight] a 1px white line along
     * the inside top; [gloss] white over the top 48%; [metal] three soft
     * light bands; [fill2] this mode's second fill (diagonal fill to fill2).
     * [round]: a typewriter's round keycap, its diameter the key's width,
     * centred in the key's own cell, in a chrome bezel of [ring].
     */
    class Face(
        val texture: String?,
        val textureAlpha: Float,
        val sheenTop: Float,
        val sheenBottom: Float,
        val highlight: Float,
        val gloss: Float,
        val metal: Float,
        val fill2: Int?,
        val round: Boolean,
        val ring: Int?,
    )

    /** How the letters and glyphs are inked: ink, engraved, letterpress,
     *  foil (three [foil] stops, top to bottom) or glow ([glow] "self" is the
     *  ink's own colour, else a hex). */
    class Legend(val style: String, val foil: IntArray?, val glow: String?)

    /** One vector primitive in key-height units from the ornament's anchor
     *  (x) and the key's top (y): line [x0 y0 x1 y1], poly [x y ...] filled,
     *  circle [cx cy r] and rect [x y w h radius], filled or stroked at
     *  [w] (0: filled), text [s] centred at [x y]. [color] overrides the
     *  ornament's. */
    class Op(
        val t: String,
        val p: FloatArray,
        val w: Float = 0f,
        val color: String? = null,
        val s: String? = null,
        val size: Float = 0f,
        val font: String = "system",
        val weight: Int = 400,
        val tracking: Float = 0f,
    )

    /** A theme's detail drawn on the keys [on] names (space, return, shift,
     *  delete, letter, or function: every function key but return), from
     *  its [anchor] (left, center or right edge). [color] is a role (ink,
     *  fnInk, accent, accentInk, fill) or a hex, times [alpha]. */
    class Ornament(val on: String, val anchor: String, val color: String, val alpha: Float, val ops: List<Op>)

    class Style(
        val letter: Face,
        val function: Face,
        val space: Face,
        val ret: Face,
        val legend: Legend,
        /** The return key's glyph: always its own (engraved), never the
         *  theme's foil or glow, which vanish on a gold return. */
        val returnLegend: Legend,
        val ornaments: List<Ornament>,
    ) {
        /** letter, function, space or return. */
        fun face(cls: String) = when (cls) {
            "letter" -> letter
            "space" -> space
            "return" -> ret
            else -> function
        }
    }

    /** What the style's fields may name (the tests hold the JSON to them). */
    val LEGENDS = setOf("ink", "engraved", "letterpress", "foil", "glow")
    val ANCHORS = setOf("left", "center", "right")
    val ORNAMENT_KEYS = setOf("space", "return", "shift", "delete", "letter", "function")
    val COLOR_ROLES = setOf("ink", "fnInk", "accent", "accentInk", "fill")
    val OPS = setOf("line", "poly", "circle", "rect", "text")
    val OP_FONTS = setOf("system", "mono", "theme")

    class Variant(
        /** One colour, or a two-stop gradient at [boardAngle] (CSS degrees). */
        val board: IntArray,
        val boardAngle: Float?,
        val letter: Fill,
        val function: Fill,
        val space: Fill,
        val keyText: Int,
        val functionGlyph: Int,
        val returnPrimary: KeyOverride,
        val shift: KeyOverride?,
        val delete: KeyOverride?,
        val popupFill: Int,
        val popupText: Int,
        /** Null: the strip shows the board. */
        val stripBackground: Int?,
        val stripText: Int,
        val chipFace: Int,
        val chipAccent: Int,
        val boundDot: Int,
        val shadow: Shadow,
        val border: Border?,
        /** The faces, legend and ornaments (shared/themes/styles.py). */
        val style: Style,
    )

    class Theme(
        val id: String,
        val name: String,
        /** material, story or archetype: the picker's groups. */
        val category: String,
        /** Paid-tier gating is not decided (§10.3): every theme is "free". */
        val tier: String,
        val heroMode: String,
        /** Null: today's face (Inter). */
        val font: Font?,
        /** standard, light or bold (§5.4). */
        val glyphStyle: String,
        /** system, typewriter, shutter, wood, mech, synth or sonar (§4.3). */
        val soundPack: String,
        val texture: Texture?,
        val light: Variant,
        val dark: Variant,
    ) {
        fun variant(dark: Boolean) = if (dark) this.dark else light
    }

    /** The id a setting names, or null for today's look ("" or unknown;
     *  a theme removed later falls back the same way). */
    fun byId(id: String?): Theme? = if (id.isNullOrEmpty()) null else ALL.firstOrNull { it.id == id }

'''


def main():
    themes = json.load(open(SRC))
    body = (HEADER + '    /** In the picker\'s order: materials, stories, archetypes. */\n'
            '    val ALL: List<Theme> = listOf(\n' + ''.join('        %s(),\n' % fn_name(t) for t in themes) +
            '    )\n\n' + ''.join(theme(t) for t in themes) + '}\n')
    with open(OUT, 'w') as fh:
        fh.write(body)
    print('wrote %s (%d themes)' % (os.path.relpath(OUT, ROOT), len(themes)))


if __name__ == '__main__':
    main()

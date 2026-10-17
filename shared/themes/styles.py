"""The themes' finish: what makes a key a material, not a colour.

Third pass (Arpit, 2026-10-17: "these look sooo low effort and cheap just
colours, fucking add some class in themes"). design.py chooses the palette;
this file chooses, per theme, three things the keyboards draw on top of it:

1. A FACE per key class (letter, function, space, return):
   texture       one of shared/themes/textures/<kind>.png, tiled at its own
                 pixel size, laid over the fill at `textureAlpha`
   sheen         a vertical gradient, `[top, bottom]`: white at the top at
                 `top` alpha fading to black at the bottom at `bottom` alpha
                 (a sculpted keycap catches light on its top edge)
   highlight     a hairline (1px) of white along the inside top edge, alpha
   gloss         lacquer: white over the top 45% fading to clear, alpha
   metal         brushed metal's bands: three soft horizontal light bands
   fill2         a second fill colour per mode: the face runs fill -> fill2
                 diagonally (aurora, gem, sunset)
2. A LEGEND style for the letters and glyphs on those keys:
   ink           as today
   engraved      a light hairline under each glyph (stamped into the key)
   letterpress   ink pressed into paper: the light hairline plus a 0.4px
                 soft bleed of the ink itself
   foil          the glyph filled top-to-bottom with three colours (gold or
                 rose-gold leaf), with a dark hairline above it
   glow          the glyph's own colour bleeding out (phosphor, neon)
3. ORNAMENTS: one signature detail per theme, drawn as vector primitives on
   a key, in that key's own coordinates. Every size is a fraction of the
   key's HEIGHT (h), measured from an anchor (`left`, `center` or `right`
   edge, and the top), so a detail keeps its shape on every phone and never
   changes a key. Primitive ops:
     line      [x0, y0, x1, y1], width w
     poly      [x0, y0, x1, y1, ...] closed, filled
     circle    [cx, cy, r], filled, or stroked when w is set
     rect      [x, y, w, h, radius], filled, or stroked when w is set
     text      s at [x, y] (its centre), size, font ("system", "mono",
               "theme"), weight, tracking
   `color` names a role (ink, fnInk, accent, accentInk, fill) or a hex per
   mode; `alpha` multiplies it.

Never a dimension, never a type size: details live inside a key's bounds.
"""
import math


def face(texture=None, textureAlpha=0.0, sheen=(0.0, 0.0), highlight=0.0, gloss=0.0,
         metal=0.0, fill2=None, shape='key', ring=None):
    # shape 'round': a typewriter's round keycap, its diameter the key's
    # width, centred in the key's own cell (the cell, its touch area and the
    # layout never change); ring: its chrome bezel colour per mode.
    return {'texture': texture, 'textureAlpha': textureAlpha, 'sheen': list(sheen),
            'highlight': highlight, 'gloss': gloss, 'metal': metal, 'fill2': fill2,
            'shape': shape, 'ring': ring}


# A sculpted keycap: a touch of light on top, a touch of shade below.
CAP = dict(sheen=(0.06, 0.07), highlight=0.35)
SOFT = dict(sheen=(0.04, 0.05), highlight=0.25)


def legend(style='ink', foil=None, glow=None):
    return {'style': style, 'foil': foil, 'glow': glow}


GOLD = ['#F6E2A8', '#D4AE5A', '#9C7430']
ROSEGOLD = ['#F6D5C8', '#D49A82', '#9E6450']
BRASS = ['#F0D9A0', '#C9A14E', '#8A6526']


def op(t, **k):
    d = {'t': t}
    d.update(k)
    return d


def orn(on, anchor, ops, color='ink', alpha=0.35):
    return {'on': on, 'anchor': anchor, 'ops': ops, 'color': color, 'alpha': alpha}


# -- Ornament geometry (units of key height) ---------------------------------

def ruler():
    """A typewriter's paper scale along the space bar's foot: a tick every
    0.09h, a longer one every fifth, numbered every tenth."""
    ops = [op('line', p=[-1.9, 0.86, 1.9, 0.86], w=0.018)]
    for i in range(-21, 22):
        x = i * 0.09
        tall = 0.12 if i % 5 == 0 else 0.06
        ops.append(op('line', p=[x, 0.86, x, 0.86 - tall], w=0.016))
    for i in (-20, -10, 10, 20):
        ops.append(op('text', s=str(abs(i) // 10 * 10 + 50 if i > 0 else 50 - abs(i) // 10 * 10),
                      p=[i * 0.09, 0.64], size=0.13, font='mono', weight=500, tracking=0.0))
    return ops


def focus_scale():
    """A lens's focus scale engraved along the space bar's foot."""
    marks = ['\u221e', '10', '5', '3', '2', '1.5', '1', '.7']
    ops = []
    n = len(marks)
    for i, m in enumerate(marks):
        x = -1.70 + i * (3.4 / (n - 1))
        ops.append(op('text', s=m, p=[x, 0.80], size=0.12, font='system', weight=500, tracking=0.02))
        ops.append(op('line', p=[x, 0.885, x, 0.94], w=0.018))
    ops.append(op('line', p=[-1.80, 0.94, 1.80, 0.94], w=0.014))
    return ops


def deco_fans():
    """An Art Deco frame on the space bar: a double gold rule along its top
    and foot, each ending in a small diamond."""
    ops = []
    for y in (0.16, 0.84):
        ops.append(op('line', p=[-1.70, y, 1.70, y], w=0.016))
        ops.append(op('line', p=[-1.55, y + (0.05 if y < 0.5 else -0.05), 1.55, y + (0.05 if y < 0.5 else -0.05)], w=0.010))
        for x in (-1.82, 1.82):
            ops.append(op('poly', p=[x - 0.07, y, x, y - 0.05, x + 0.07, y, x, y + 0.05]))
    return ops


def sunburst():
    """Gatsby's return: gold rays from the foot of the key."""
    ops = []
    for i in range(11):
        a = math.radians(200 + i * 14)
        ops.append(op('line', p=[0, 1.02, 0.95 * math.cos(a), 1.02 + 0.95 * math.sin(a)], w=0.018))
    return ops


def nameplate(text):
    """A small engraved brass plate at the space bar's right end."""
    return [op('rect', p=[-0.88, 0.30, 0.66, 0.40, 0.06]),
            op('text', s=text, p=[-0.55, 0.505], size=0.22, font='theme', weight=600, tracking=0.08,
               color='#3A2A12')]


def suits():
    return [op('text', s='♠', p=[0.42, 0.52], size=0.30, font='system', weight=400, tracking=0, color='ink'),
            op('text', s='♥', p=[0.78, 0.52], size=0.30, font='system', weight=400, tracking=0, color='accent')]


def suits_right():
    return [op('text', s='♣', p=[-0.78, 0.52], size=0.30, font='system', weight=400, tracking=0, color='ink'),
            op('text', s='♦', p=[-0.42, 0.52], size=0.30, font='system', weight=400, tracking=0, color='accent')]


def seal():
    """A vermilion hanko at the space bar's right end: a square seal with an
    abstract carved mark (no real characters)."""
    s = 0.40
    x, y = -0.62, 0.30
    return [op('rect', p=[x, y, s, s, 0.05], color='#B3262B'),
            op('rect', p=[x + 0.06, y + 0.06, s - 0.12, s - 0.12, 0.02], w=0.03, color='#F8F2E8'),
            op('line', p=[x + 0.12, y + 0.14, x + 0.28, y + 0.14], w=0.035, color='#F8F2E8'),
            op('line', p=[x + 0.20, y + 0.10, x + 0.20, y + 0.32], w=0.035, color='#F8F2E8'),
            op('line', p=[x + 0.12, y + 0.26, x + 0.28, y + 0.30], w=0.035, color='#F8F2E8')]


def gold_flecks():
    import random
    r = random.Random(7)
    return [op('circle', p=[r.uniform(-1.1, 1.1), r.uniform(0.12, 0.88), r.uniform(0.012, 0.028)])
            for _ in range(16)]


def bauhaus():
    return [op('circle', p=[-1.02, 0.5, 0.13], color='#D63A2B'),
            op('rect', p=[-0.80, 0.37, 0.26, 0.26, 0.0], color='#2B5BA8'),
            op('poly', p=[-0.40, 0.63, -0.25, 0.37, -0.10, 0.63], color='#F2C230')]


def prompt():
    return [op('text', s='>_', p=[0.42, 0.50], size=0.30, font='mono', weight=500, tracking=0.02)]


def skyline():
    pts = [0, 1, 0.0, 0.78, 0.18, 0.78, 0.18, 0.62, 0.30, 0.62, 0.30, 0.70, 0.42, 0.70, 0.42, 0.50,
           0.47, 0.50, 0.47, 0.44, 0.52, 0.44, 0.52, 0.50, 0.58, 0.50, 0.58, 0.72, 0.74, 0.72, 0.74, 0.58,
           0.86, 0.58, 0.86, 0.66, 0.96, 0.66, 0.96, 0.54, 1.02, 0.50, 1.08, 0.54, 1.08, 0.80, 1.24, 0.80,
           1.24, 0.66, 1.36, 0.66, 1.36, 0.76, 1.50, 0.76, 1.50, 1]
    # Anchored at the right end, drawn leftwards.
    return [op('poly', p=[-v if i % 2 == 0 else v for i, v in enumerate(pts)])]


def orbit():
    ops = []
    for i in range(40):
        a0 = 2 * math.pi * i / 40
        a1 = 2 * math.pi * (i + 1) / 40
        ops.append(op('line', p=[-0.62 + 0.42 * math.cos(a0), 0.5 + 0.13 * math.sin(a0),
                                 -0.62 + 0.42 * math.cos(a1), 0.5 + 0.13 * math.sin(a1)], w=0.018))
    ops.append(op('circle', p=[-0.62, 0.5, 0.09]))
    ops.append(op('circle', p=[-0.25, 0.42, 0.035], color='accent'))
    return ops


def rivets():
    """Four rivets in a function key's corners."""
    d = 0.12
    return [op('circle', p=[d, d, 0.028]), op('circle', p=[-d, d, 0.028]),
            op('circle', p=[d, 1 - d, 0.028]), op('circle', p=[-d, 1 - d, 0.028])]


def petals():
    def blossom(cx, cy, r):
        out = []
        for i in range(5):
            a = math.radians(i * 72 - 90)
            out.append(op('circle', p=[cx + r * 0.9 * math.cos(a), cy + r * 0.9 * math.sin(a), r * 0.62]))
        out.append(op('circle', p=[cx, cy, r * 0.35], color='fill'))
        return out
    return blossom(-0.55, 0.40, 0.11) + blossom(-0.88, 0.66, 0.075) + blossom(-0.30, 0.70, 0.055)


def wave():
    ops = []
    for i in range(60):
        x0 = -1.8 + i * 0.06
        x1 = x0 + 0.06
        y = lambda x: 0.80 + 0.05 * math.sin(x * 5.2)
        ops.append(op('line', p=[x0, y(x0), x1, y(x1)], w=0.02))
    return ops


def dunes():
    ops = []
    for k, (amp, base) in enumerate(((0.06, 0.82), (0.04, 0.72))):
        for i in range(50):
            x0 = -1.7 + i * 0.068
            x1 = x0 + 0.068
            y = lambda x: base - amp * math.cos(x * 1.9 + k)
            ops.append(op('line', p=[x0, y(x0), x1, y(x1)], w=0.02))
    return ops


def synth_sun():
    """A 1986 sunset: a sun whose lower half is cut by widening gaps."""
    cx, cy, r = -0.62, 0.50, 0.30
    ops = [op('circle', p=[cx, cy, r], color='#F7A33B')]
    for i, y in enumerate((0.52, 0.60, 0.67, 0.73)):
        ops.append(op('rect', p=[cx - r - 0.02, y, 2 * r + 0.04, 0.022 + i * 0.012, 0], color='fill'))
    ops.append(op('rect', p=[cx - r - 0.02, 0.78, 2 * r + 0.04, 0.10, 0], color='fill'))
    return ops


def fern():
    ops = [op('line', p=[0.30, 0.82, 1.10, 0.30], w=0.02)]
    for i in range(1, 8):
        t = i / 8
        x = 0.30 + 0.80 * t
        y = 0.82 - 0.52 * t
        l = 0.16 * (1 - t * 0.6)
        ops.append(op('line', p=[x, y, x - l * 0.2, y - l], w=0.016))
        ops.append(op('line', p=[x, y, x + l, y + l * 0.15], w=0.016))
    return ops


def crescent():
    """A thin crescent moon over two distant stars."""
    return [op('circle', p=[0.62, 0.48, 0.20]),
            op('circle', p=[0.70, 0.43, 0.18], color='fill'),
            op('circle', p=[0.98, 0.34, 0.018]), op('circle', p=[1.12, 0.58, 0.012])]


def pearls():
    """A strand of seed pearls along the space bar's foot."""
    return [op('circle', p=[-1.75 + i * 0.125, 0.86 + 0.012 * math.cos(i * 0.9), 0.026]) for i in range(29)]


def panel():
    """A cockpit panel: two fasteners at each end of the space bar."""
    out = []
    for x in (-1.98, 1.98):
        for y in (0.22, 0.78):
            out.append(op('circle', p=[x, y, 0.035], w=0.014))
            out.append(op('line', p=[x - 0.022, y, x + 0.022, y], w=0.012))
    return out


def vents():
    return [op('rect', p=[-1.02 + i * 0.13, 0.36, 0.06, 0.28, 0.03]) for i in range(5)]


def hazard():
    return [op('poly', p=[-0.20 + i * 0.22, 1.0, -0.06 + i * 0.22, 1.0, 0.30 + i * 0.22, 0.0, 0.16 + i * 0.22, 0.0])
            for i in range(-3, 4)]


def chevrons():
    return [op('line', p=[-0.90 + i * 0.14, 0.38, -0.80 + i * 0.14, 0.5], w=0.03) for i in range(3)] + \
           [op('line', p=[-0.80 + i * 0.14, 0.5, -0.90 + i * 0.14, 0.62], w=0.03) for i in range(3)]


def facets():
    """A cut gem's facets across the return key."""
    return [op('line', p=[-0.0, 0.0, 0.5, 0.5], w=0.014), op('line', p=[0.5, 0.5, 0.0, 1.0], w=0.014),
            op('line', p=[0.5, 0.5, 1.4, 0.5], w=0.014)]


def gauge():
    ops = [op('circle', p=[-0.62, 0.5, 0.30], w=0.03), op('circle', p=[-0.62, 0.5, 0.22], w=0.015)]
    for i in range(12):
        a = 2 * math.pi * i / 12
        ops.append(op('line', p=[-0.62 + 0.22 * math.cos(a), 0.5 + 0.22 * math.sin(a),
                                 -0.62 + 0.27 * math.cos(a), 0.5 + 0.27 * math.sin(a)], w=0.012))
    ops.append(op('line', p=[-0.62, 0.5, -0.62 + 0.18, 0.5 - 0.10], w=0.02))
    return ops


def inlay():
    return [op('line', p=[-1.95, 0.16, 1.95, 0.16], w=0.022), op('line', p=[-1.95, 0.84, 1.95, 0.84], w=0.022)]


# -- Per theme -----------------------------------------------------------------
# faces: letter, function, space (defaults to letter), return.

S = {
    'typewriter': dict(
        faces={'letter': face('paper', 0.08, sheen=(0.10, 0.06), highlight=0.0, gloss=0.10, shape='round',
                              ring={'light': '#A9A9A4', 'dark': '#9A9A94'}),
               'function': face('paper', 0.07, **CAP),
               'return': face(gloss=0.28, sheen=(0.0, 0.10), highlight=0.3)},
        legend=legend('letterpress'),
        ornaments=[orn('space', 'center', ruler(), 'ink', 0.38)]),
    'beigebox': dict(
        faces={'letter': face('paper', 0.05, sheen=(0.08, 0.12), highlight=0.45),
               'function': face('paper', 0.05, sheen=(0.08, 0.12), highlight=0.35),
               'return': face(sheen=(0.06, 0.12), highlight=0.3)},
        legend=legend('ink'),
        ornaments=[orn('space', 'right', vents(), 'fnInk', 0.22)]),
    'rangefinder': dict(
        faces={'letter': face('brushed', 0.07, sheen=(0.10, 0.08), highlight=0.6, metal=0.06),
               'function': face('leather', 0.22, sheen=(0.04, 0.10), highlight=0.12),
               'return': face('leather', 0.22, sheen=(0.04, 0.10), highlight=0.12)},
        legend=legend('engraved'),
        ornaments=[orn('space', 'center', focus_scale(), 'ink', 0.45)]),
    'walnut': dict(
        faces={'letter': face('linen', 0.05, **CAP), 'function': face('wood', 0.30, sheen=(0.06, 0.12), highlight=0.25),
               'return': face('brushed', 0.05, sheen=(0.14, 0.12), highlight=0.5, metal=0.08)},
        legend=legend('engraved'),
        ornaments=[orn('space', 'center', inlay(), '#B8924A', 0.55)]),
    'carrara': dict(
        faces={'letter': face('marble', 0.09, sheen=(0.06, 0.05), highlight=0.5, gloss=0.10),
               'function': face('marble', 0.10, sheen=(0.04, 0.06), highlight=0.35),
               'return': face('brushed', 0.05, sheen=(0.16, 0.12), highlight=0.5, metal=0.08)},
        legend=legend('engraved'), ornaments=[]),
    'graphite': dict(
        faces={'letter': face(sheen=(0.05, 0.06), highlight=0.7),
               'function': face('brushed', 0.05, sheen=(0.08, 0.10), highlight=0.35, metal=0.06),
               'return': face(gloss=0.22, sheen=(0.02, 0.10), highlight=0.3)},
        legend=legend('ink'), ornaments=[]),
    'terminal': dict(
        faces={'letter': face('scanlines', 0.06, **SOFT), 'function': face('scanlines', 0.06, **SOFT),
               'return': face(sheen=(0.10, 0.10), highlight=0.3)},
        legend=legend('glow', glow='self'),
        ornaments=[orn('space', 'left', prompt(), 'ink', 0.55)]),
    'primary': dict(
        faces={'letter': face('paper', 0.06, **CAP), 'function': face('paper', 0.06, **CAP),
               'return': face('paper', 0.05, **CAP)},
        legend=legend('ink'),
        ornaments=[orn('space', 'right', bauhaus(), 'ink', 1.0)]),
    'greenhouse': dict(
        faces={'letter': face('washi', 0.07, **CAP), 'function': face('linen', 0.10, **CAP),
               'return': face(sheen=(0.06, 0.10), highlight=0.3)},
        legend=legend('ink'),
        ornaments=[orn('space', 'left', fern(), 'fnInk', 0.30)]),
    'sakura': dict(
        faces={'letter': face('washi', 0.08, **CAP), 'function': face('washi', 0.08, **CAP),
               'return': face(gloss=0.18, sheen=(0.04, 0.08), highlight=0.3)},
        legend=legend('ink'),
        ornaments=[orn('space', 'right', petals(), 'accent', 0.55)]),
    'tide': dict(
        faces={'letter': face(sheen=(0.10, 0.04), highlight=0.6, gloss=0.14),
               'function': face(sheen=(0.10, 0.06), highlight=0.5, gloss=0.12),
               'return': face(gloss=0.22, sheen=(0.04, 0.10), highlight=0.4)},
        legend=legend('ink'),
        ornaments=[orn('space', 'center', wave(), 'accent', 0.35)]),
    'sahara': dict(
        faces={'letter': face('sand', 0.06, **CAP), 'function': face('sand', 0.12, **CAP),
               'return': face('sand', 0.08, sheen=(0.06, 0.12), highlight=0.3)},
        legend=legend('ink'),
        ornaments=[orn('space', 'center', dunes(), 'fnInk', 0.28)]),
    'moss': dict(
        faces={'letter': face('linen', 0.06, **CAP), 'function': face('velvet', 0.14, **SOFT),
               'return': face('brushed', 0.05, sheen=(0.14, 0.12), highlight=0.5, metal=0.08)},
        legend=legend('ink'),
        ornaments=[orn('space', 'left', fern(), 'accent', 0.40)]),
    'arctic': dict(
        faces={'letter': face('frost', 0.08, sheen=(0.08, 0.04), highlight=0.6, gloss=0.10),
               'function': face('frost', 0.08, sheen=(0.06, 0.06), highlight=0.4),
               'return': face(gloss=0.20, highlight=0.4,
                              fill2={'light': '#4F9A9E', 'dark': '#A3D9C9'})},
        legend=legend('ink'), ornaments=[]),
    'lunar': dict(
        faces={'letter': face('paper', 0.05, **CAP), 'function': face('paper', 0.05, **CAP),
               'return': face(sheen=(0.08, 0.12), highlight=0.35)},
        legend=legend('ink'),
        ornaments=[orn('function', 'left', rivets()[::2], 'fnInk', 0.35),
                   orn('function', 'right', rivets()[1::2], 'fnInk', 0.35),
                   orn('space', 'center', panel(), 'fnInk', 0.35)]),
    'blush': dict(
        faces={'letter': face('velvet', 0.05, **SOFT), 'function': face('velvet', 0.06, **SOFT),
               'return': face(gloss=0.24, sheen=(0.02, 0.10), highlight=0.3)},
        legend=legend('ink'),
        ornaments=[orn('space', 'center', pearls(), '#FFFFFF', 0.55)]),
    'champagne': dict(
        faces={'letter': face('linen', 0.04, **SOFT),
               'function': face('brushed', 0.05, sheen=(0.12, 0.08), highlight=0.5, metal=0.07),
               'return': face('brushed', 0.05, sheen=(0.16, 0.12), highlight=0.55, metal=0.08)},
        legend=legend('ink'), ornaments=[]),
    'midnight': dict(
        faces={'letter': face(sheen=(0.06, 0.08), highlight=0.3),
               'function': face(sheen=(0.06, 0.08), highlight=0.3),
               'return': face(highlight=0.35, gloss=0.14, fill2={'light': '#7A3FC2', 'dark': '#7B4BE0'})},
        legend=legend('glow', glow='self'),
        ornaments=[orn('space', 'right', synth_sun(), 'accent', 0.85)]),
    'noir': dict(
        faces={'letter': face('paper', 0.05, sheen=(0.10, 0.10), highlight=0.5),
               'function': face('paper', 0.05, sheen=(0.10, 0.10), highlight=0.4),
               'return': face(gloss=0.30, sheen=(0.0, 0.12), highlight=0.3)},
        legend=legend('ink'),
        ornaments=[orn('space', 'right', chevrons(), 'accent', 0.70)]),
    'rooftop': dict(
        faces={'letter': face(sheen=(0.10, 0.06), highlight=0.45),
               'function': face(sheen=(0.08, 0.08), highlight=0.35),
               'return': face(gloss=0.16, sheen=(0.06, 0.10), highlight=0.35)},
        legend=legend('ink'),
        ornaments=[orn('space', 'right', skyline(), 'fnInk', 0.22)]),
    'overclock': dict(
        faces={'letter': face(sheen=(0.05, 0.06), highlight=0.4),
               'function': face(sheen=(0.06, 0.10), highlight=0.35),
               'return': face(gloss=0.16, sheen=(0.04, 0.10), highlight=0.35)},
        legend=legend('ink'),
        ornaments=[orn('shift', 'left', hazard(), '#121212', 0.12),
                   orn('delete', 'left', hazard(), '#121212', 0.12)]),
    'orbit': dict(
        faces={'letter': face(sheen=(0.06, 0.06), highlight=0.55),
               'function': face('brushed', 0.06, sheen=(0.06, 0.08), highlight=0.4),
               'return': face(sheen=(0.06, 0.12), highlight=0.35)},
        legend=legend('ink'),
        ornaments=[orn('space', 'right', orbit(), 'fnInk', 0.40)]),
    'samurai': dict(
        faces={'letter': face('washi', 0.08, sheen=(0.06, 0.08), highlight=0.35, gloss=0.0),
               'function': face(gloss=0.26, sheen=(0.02, 0.14), highlight=0.3),
               'return': face(gloss=0.24, sheen=(0.02, 0.14), highlight=0.3)},
        legend=legend('foil', foil=GOLD),
        ornaments=[orn('space', 'right', seal(), 'ink', 0.92),
                   orn('return', 'center', gold_flecks(), '#D9B570', 0.75)]),
    'baker': dict(
        faces={'letter': face('paper', 0.09, **CAP), 'function': face('herringbone', 0.16, **CAP),
               'return': face('leather', 0.14, sheen=(0.06, 0.14), highlight=0.25)},
        legend=legend('letterpress'),
        ornaments=[orn('space', 'right', nameplate('221B'), '#C9A14E', 0.95)]),
    'wonderland': dict(
        faces={'letter': face('paper', 0.10, **CAP), 'function': face('crosshatch', 0.16, **CAP),
               'return': face(gloss=0.20, sheen=(0.02, 0.10), highlight=0.3)},
        legend=legend('letterpress'),
        ornaments=[orn('space', 'left', suits(), 'ink', 0.55),
                   orn('space', 'right', suits_right(), 'ink', 0.55)]),
    'emerald': dict(
        faces={'letter': face(sheen=(0.08, 0.08), highlight=0.5, gloss=0.08),
               'function': face('velvet', 0.08, **SOFT),
               'space': face('bricks', 0.10, **CAP),
               'return': face(gloss=0.26, highlight=0.45, fill2={'light': '#2E9A6E', 'dark': '#F0D27A'})},
        legend=legend('ink'),
        ornaments=[orn('return', 'left', facets(), 'accentInk', 0.22)]),
    'nautilus': dict(
        faces={'letter': face('paper', 0.05, **CAP), 'function': face('patina', 0.16, **CAP),
               'return': face('brushed', 0.05, sheen=(0.14, 0.12), highlight=0.5, metal=0.08)},
        legend=legend('engraved'),
        ornaments=[orn('return', 'left', rivets()[::2], 'accentInk', 0.40),
                   orn('return', 'right', rivets()[1::2], 'accentInk', 0.40),
                   orn('space', 'right', gauge(), 'fnInk', 0.32)]),
    'gatsby': dict(
        faces={'letter': face(sheen=(0.06, 0.06), highlight=0.45, gloss=0.10),
               'function': face('brushed', 0.05, sheen=(0.08, 0.08), highlight=0.4, metal=0.08),
               'return': face(gloss=0.24, sheen=(0.04, 0.12), highlight=0.4)},
        legend=legend('foil', foil=GOLD),
        ornaments=[orn('space', 'center', deco_fans(), 'accent', 0.65),
                   orn('return', 'center', sunburst(), 'accentInk', 0.30)]),
    'dracula': dict(
        faces={'letter': face('velvet', 0.08, **SOFT), 'function': face('velvet', 0.10, **SOFT),
               'return': face(gloss=0.26, sheen=(0.02, 0.14), highlight=0.3)},
        legend=legend('engraved'),
        ornaments=[orn('space', 'left', crescent(), 'fnInk', 0.45)]),
}

# Light-mode legend overrides: foil reads only on a dark key, so a theme
# whose light letters are pale wears ink by day.
LIGHT_LEGEND = {'samurai': legend('letterpress'), 'gatsby': legend('engraved')}
DARK_LEGEND = {'terminal': legend('glow', glow='self'), 'midnight': legend('glow', glow='self')}
LIGHT_ONLY_INK = {'terminal': legend('ink'), 'midnight': legend('ink')}


def style_for(tid, mode):
    s = S[tid]
    faces = dict(s['faces'])
    faces.setdefault('space', dict(faces['letter'], shape='key', ring=None))
    lg = s['legend']
    if mode == 'light':
        lg = LIGHT_LEGEND.get(tid, LIGHT_ONLY_INK.get(tid, lg))
    # Return wears its own ink, engraved: foil or glow on the accent key
    # (gold on gold) lost the arrow.
    return {'faces': faces, 'legend': lg, 'returnLegend': legend('engraved'), 'ornaments': s['ornaments']}

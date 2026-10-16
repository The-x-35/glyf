#!/usr/bin/env python3
"""The keyboard themes, designed as keycap colourways, written to themes.json.

    python3 shared/themes/design.py      # rewrites shared/themes/themes.json

Second pass (Arpit, 2026-10-17: "what shit have u made, v bad aesthetically
... research designs learn and then make properly"). The first pass painted
whole boards, outlined every key and chased 3:1 between keys and the iPhone's
sheet, which forced dark slabs onto a light sheet. This pass follows how the
best keycap sets are built (GMK 9009, Olivia, Godspeed, Botanical, Laser,
Red Samurai; GMK's own plastic codes where a set uses them):

  - three tiers only: letters (the lightest, or the darkest, keys), the
    function keys one quiet step away, and ONE accent, on return;
  - legends in a dark, low-chroma ink (or a cream on dark), never neon,
    never an outline on a key;
  - a light variant whose letters are lighter than Apple's light sheet
    (#E2E4E8) and a dark one whose letters sit a step above the dark sheet
    (#1B1B1D), so the keys belong on the sheet iOS draws behind them;
  - the press callout is the letter key itself (Apple's), never a new colour;
  - special faces only where the object has one (a typewriter's slab serif,
    a terminal's mono, a Victorian Caslon, an engraving's Fell, Deco caps).

Every value below is a choice; nothing here is computed except the pressed
shades, the Android board and the chip, which follow the palette.
"""
import json, os

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, 'themes.json')
OLD = json.load(open(OUT)) if os.path.exists(OUT) else []

# Font and sound records from the first pass, by family / pack (files ship
# already: app/ios/GlyfKeyboard/Fonts, tools/gen_theme_sounds.py).
FONTS = {t['font']['family']: t['font'] for t in OLD if t.get('font') and t['font'].get('family') not in (None, 'system')}
SOUNDS = {t['sound']['pack']: t['sound'] for t in OLD if t.get('sound') and t['sound'].get('pack') not in (None, 'system')}
SYSTEM_FONT = {'family': 'system'}
SYSTEM_SOUND = {'pack': 'system'}


def rgb(c):
    c = c.lstrip('#')
    return [int(c[i:i + 2], 16) / 255 for i in (0, 2, 4)]


def hexc(v):
    return '#' + ''.join('%02X' % max(0, min(255, round(x * 255))) for x in v)


def mix(a, b, t):
    return hexc([x + (y - x) * t for x, y in zip(rgb(a), rgb(b))])


def lum(c):
    f = lambda v: v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = (f(v) for v in rgb(c))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def pressed(fill, dark):
    # Apple darkens a light key and lightens a dark one when pressed.
    return mix(fill, '#FFFFFF', 0.12) if dark else mix(fill, '#000000', 0.12)


# id, name, category, mood, font family, sound pack,
# light (A, AL, M, ML, R, RL), dark (A, AL, M, ML, R, RL), extras
# A letter key, AL its legend, M function keys, ML their glyphs,
# R the return (the one accent), RL its legend.
T = [
    # -- Objects -----------------------------------------------------------
    ('typewriter', 'Typewriter', 'Objects',
     'An Italian portable: ivory keys, warm grey shift, a Valentine-red return.',
     'Courier Prime', 'typewriter',
     ('#FBF8F1', '#1D1B18', '#D6CFC2', '#2A2723', '#C8322B', '#FFF8EE'),
     ('#33302B', '#EFE8DA', '#23211E', '#D9D1C2', '#C8322B', '#FFF3E6'), {}),
    ('beigebox', 'Beige Box', 'Objects',
     'A 1984 desktop computer: putty letters, khaki function keys, a rose return.',
     'system', 'mech',
     ('#EEE9DD', '#171718', '#B9B3A2', '#171718', '#C87E74', '#171718'),
     ('#3A3832', '#E8E1CF', '#2A2924', '#C9C1AD', '#C87E74', '#1A1716'), {}),
    ('rangefinder', 'Rangefinder', 'Objects',
     'A film camera: satin chrome keys, a black leatherette return with a yellow legend.',
     'system', 'shutter',
     ('#F4F4F1', '#1A1A1A', '#C3C3BE', '#1A1A1A', '#1F1F1F', '#F2C230'),
     ('#2F2F2F', '#EDEDE8', '#1F1F1F', '#C3C3BE', '#D8D8D3', '#1A1A1A'), {}),
    ('walnut', 'Walnut', 'Objects',
     'A writing desk: walnut function keys, brass on the return.',
     'system', 'wood',
     ('#F8F2E9', '#3B2A1F', '#B98C65', '#2A1C12', '#3B2A1F', '#E3C17A'),
     ('#3B2C22', '#EBD9BC', '#2A1F18', '#C9A46A', '#B8924A', '#21170F'), {}),
    ('carrara', 'Carrara', 'Objects',
     'Polished marble and a brass inlay.',
     'system', 'system',
     ('#FDFCFA', '#3A3835', '#E2DED7', '#3A3835', '#B49A6A', '#221C12'),
     ('#3A3836', '#F1EEE8', '#272624', '#D8D3CA', '#C9AE7C', '#221D14'), {}),
    ('graphite', 'Graphite', 'Objects',
     'Machined aluminium and anodised black.',
     'system', 'system',
     ('#F5F5F7', '#1C1C1E', '#48484A', '#F5F5F7', '#1C1C1E', '#FFFFFF'),
     ('#2C2C2E', '#F2F2F7', '#1C1C1E', '#AEAEB2', '#F2F2F7', '#1C1C1E'), {}),
    ('terminal', 'Terminal', 'Objects',
     'A green-screen terminal: phosphor letters, monospaced.',
     'JetBrains Mono', 'mech',
     ('#F3F6F1', '#1F3B26', '#D2DDCE', '#1F3B26', '#2E7D46', '#F3F6F1'),
     ('#1C221D', '#86EFA0', '#121713', '#5CC77A', '#35C46A', '#08110B'), {}),
    ('primary', 'Primary', 'Objects',
     'A Bauhaus poster: cream keys, a red shift, a blue delete, a yellow return.',
     'system', 'system',
     ('#F7F3EA', '#1F1F1F', '#E2DACB', '#1F1F1F', '#F2C230', '#1F1F1F'),
     ('#2A2A2A', '#F5F1E8', '#1C1C1C', '#E2DACB', '#F2C230', '#1F1F1F'),
     {'overrides': {
         'light': {'shift': ('#D63A2B', '#FFFFFF'), 'delete': ('#2B5BA8', '#FFFFFF')},
         'dark': {'shift': ('#C8392B', '#FFFFFF'), 'delete': ('#3A6BC0', '#FFFFFF')}}}),
    # -- Nature ------------------------------------------------------------
    ('greenhouse', 'Greenhouse', 'Nature',
     'Sage leaves and a deep fern return.',
     'system', 'system',
     ('#F2F4ED', '#2F3B2F', '#AFC4A9', '#22301F', '#3F6B4A', '#F2F4ED'),
     ('#2E3A31', '#DDE7D5', '#202A23', '#A8BFA3', '#9CC096', '#16201A'), {}),
    ('sakura', 'Sakura', 'Nature',
     'Blossom paper and plum ink.',
     'system', 'system',
     ('#FFF8F8', '#4A2E35', '#F2D5DA', '#4A2E35', '#B85571', '#FFFFFF'),
     ('#3A2A31', '#F7CDD7', '#2A1E24', '#E9A3B7', '#E58AA3', '#2A1A20'), {}),
    ('tide', 'Tide', 'Nature',
     'Sea glass and deep water.',
     'system', 'system',
     ('#F5FAFC', '#1D3B4F', '#C8DEE9', '#1D3B4F', '#246FA3', '#FFFFFF'),
     ('#1D3142', '#C4E4F5', '#14232F', '#7FB8DA', '#4BA3DD', '#0D1A24'), {}),
    ('sahara', 'Sahara', 'Nature',
     'Warm sand and a terracotta return.',
     'system', 'system',
     ('#FBF5EC', '#4A3524', '#E3CFB3', '#4A3524', '#B0532D', '#FFFFFF'),
     ('#3A3027', '#F1E2CC', '#2A221C', '#D9BE98', '#D9774C', '#1F140D'), {}),
    ('moss', 'Moss', 'Nature',
     'Lichen and old gold.',
     'system', 'wood',
     ('#F4F5EE', '#2D3626', '#BAC3A3', '#2D3626', '#A8862F', '#1F1A0A'),
     ('#2C3328', '#DCE5CF', '#1F241C', '#B6C59E', '#C9A646', '#1D1708'), {}),
    ('arctic', 'Arctic', 'Nature',
     'Snow, frost and polar night.',
     'system', 'system',
     ('#FAFBFC', '#2E3440', '#D8DEE9', '#3B4252', '#4C6E99', '#FFFFFF'),
     ('#3B4252', '#ECEFF4', '#2E3440', '#D8DEE9', '#88C0D0', '#2E3440'), {}),
    ('lunar', 'Lunar', 'Nature',
     'A 1969 cockpit: cream switches, powder-blue panels, an orange abort.',
     'system', 'system',
     ('#F5EFE2', '#2B2B2B', '#AFC7DB', '#1F2A36', '#E8833A', '#1E140C'),
     ('#2C3138', '#EDE6D6', '#1F242A', '#AFC7DB', '#E8833A', '#1E140C'), {}),
    # -- Moods -------------------------------------------------------------
    ('blush', 'Blush', 'Moods',
     'Ivory and rose; black keys with rose legends at night.',
     'system', 'system',
     ('#FCF8F7', '#2A2A2A', '#ECC6C3', '#3A2A2A', '#2A2A2A', '#ECC6C3'),
     ('#2F2C2D', '#ECC6C3', '#222021', '#ECC6C3', '#ECC6C3', '#2A2A2A'), {}),
    ('champagne', 'Champagne', 'Moods',
     'Porcelain and rose gold.',
     'system', 'system',
     ('#FFFAF7', '#4E3830', '#EBD3C7', '#4E3830', '#9E6A55', '#FFFFFF'),
     ('#3A2F2C', '#F2D0C2', '#2A2220', '#E2B09C', '#D49A82', '#2A1A14'), {}),
    ('midnight', 'Midnight Drive', 'Moods',
     'A coastal road at 2am: violet keys, cyan letters, a magenta return.',
     'system', 'synth',
     ('#F6F2FB', '#2B2342', '#D9CCEE', '#2B2342', '#C2347E', '#FFFFFF'),
     ('#2D2545', '#8CE8F2', '#1F1932', '#E58BCB', '#C42F80', '#FFFFFF'), {}),
    ('noir', 'Noir', 'Moods',
     'Black and white, and one red.',
     'system', 'typewriter',
     ('#FFFFFF', '#111111', '#D9D9D9', '#111111', '#B3141E', '#FFFFFF'),
     ('#2B2B2B', '#F5F5F5', '#161616', '#CFCFCF', '#C21A24', '#FFFFFF'), {}),
    ('rooftop', 'Rooftop', 'Moods',
     'A city roof at night, under a sodium streetlight.',
     'system', 'system',
     ('#FFFFFF', '#222831', '#CBD2DC', '#222831', '#E9A23B', '#1F1608'),
     ('#262C35', '#F1E6D0', '#1A1F26', '#D9B27A', '#F2B04C', '#1A1206'), {}),
    ('overclock', 'Overclock', 'Moods',
     'Acid yellow function keys and a hot-pink return.',
     'system', 'synth',
     ('#FFFFFF', '#121212', '#F2E33A', '#121212', '#FF2D87', '#120010'),
     ('#1E1E1E', '#F2F2F2', '#F2E33A', '#121212', '#FF2D87', '#120010'), {}),
    ('orbit', 'Orbit', 'Moods',
     'A white hull and a mission-orange return.',
     'system', 'sonar',
     ('#FFFFFF', '#1E2433', '#D3D9E4', '#1E2433', '#EE6A33', '#1A0E07'),
     ('#222B40', '#E8ECF4', '#161C2B', '#F29A6B', '#F07A3F', '#160C05'), {}),
    ('samurai', 'Samurai', 'Moods',
     'Washi paper, a vermilion seal, gold leaf; red lacquer keys at night.',
     'system', 'wood',
     ('#F8F2E8', '#1F1B1A', '#B3262B', '#F3D9A4', '#1F1B1A', '#E1BE72'),
     ('#8E2126', '#EFD18E', '#211D1C', '#D9B570', '#D9B570', '#211D1C'), {}),
    # -- Stories (public-domain books, the book's look only: docs/THEMES.md §1)
    ('baker', '221B', 'Stories',
     'A Victorian study by gaslight: tweed, Caslon type, an oxblood return.',
     'Libre Caslon Text', 'system',
     ('#F6F1E6', '#2B2520', '#CFC2A8', '#2B2520', '#6E1E22', '#F6F1E6'),
     ('#35302A', '#EADFC8', '#26221E', '#CDBF9F', '#8E2A2E', '#F6EBDD'), {}),
    ('wonderland', 'Wonderland', 'Stories',
     'An 1865 engraving: cream paper, black ink, a playing-card red.',
     'IM Fell English', 'system',
     ('#FCF8EF', '#1A1917', '#E4DAC6', '#1A1917', '#A82A2A', '#FCF8EF'),
     ('#2D2A26', '#F1E8D6', '#1F1D1A', '#D8CCB4', '#B83232', '#FCF4E6'), {}),
    ('emerald', 'Emerald City', 'Stories',
     'Jewel green and gold, as the 1900 book drew it.',
     'system', 'system',
     ('#F3F7F3', '#123B2E', '#BCD6C6', '#123B2E', '#1D6B4D', '#F2E3B3'),
     ('#17402F', '#EAD9A2', '#0F2C21', '#C9B47A', '#C9A44C', '#0F2C21'), {}),
    ('nautilus', 'Nautilus', 'Stories',
     'Brass and verdigris, twenty thousand leagues down.',
     'system', 'sonar',
     ('#F5F1E6', '#23393A', '#A9C2B8', '#1E3132', '#A87A34', '#1B1306'),
     ('#1F3437', '#E6D3A3', '#142527', '#9EC1B6', '#C29848', '#142527'), {}),
    ('gatsby', 'Gatsby', 'Stories',
     'West Egg, 1925: ivory and champagne by day, black lacquer and gold by night.',
     'Marcellus', 'system',
     ('#FBF8F0', '#1E1C19', '#E6D7AE', '#1E1C19', '#1E1C19', '#E3C276'),
     ('#222120', '#E6C77A', '#161514', '#C9A85A', '#D4B062', '#161514'), {}),
    ('dracula', 'Dracula', 'Stories',
     'Candlelight, bone and oxblood.',
     'system', 'system',
     ('#F7F2EF', '#2A1F24', '#D8CCCB', '#2A1F24', '#7D1A28', '#F7EDEA'),
     ('#2E2228', '#EADCCB', '#1F161B', '#C9A27A', '#8E1C2C', '#F4E6DC'), {}),
]

# The Android board: the letter key's own tint a step down, as Apple's sheet
# sits under its keys (a board in the function keys' colour turned whole
# keyboards yellow or blue). Light: the letter key 10% darker; dark: the
# letter key well into black.
def board(mode, a, m):
    return mix(a, '#20201E', 0.11) if mode == 'light' else mix(a, '#000000', 0.62)


DARK_SHEET = '#1B1B1D'


def lift(c, lo):
    """Lightens a dark key until it stands lo:1 off iOS's dark sheet."""
    t = 0.0
    while _ratio(c, DARK_SHEET) < lo and t < 1:
        t += 0.01
        c2 = mix(c, '#FFFFFF', t)
        if _ratio(c2, DARK_SHEET) >= lo:
            return c2
    return c if t == 0 else mix(c, '#FFFFFF', t)


def variant(mode, pal, overrides):
    a, al, m, ml, r, rl = pal
    dark = mode == 'dark'
    if dark:
        # Apple's dark board layers: sheet, function keys a step up, letters
        # a step above those. A key darker than the sheet disappears on it.
        if lum(m) < lum(a):
            m = lift(m, 1.3)
            a = lift(a, 1.6)
        else:
            a = lift(a, 1.6)
    v = {
        'board': {'colors': [board(mode, a, m)], 'angle': None, 'paintedOn': 'android'},
        'letterKey': {'fill': a, 'pressed': pressed(a, dark)},
        'functionKey': {'fill': m, 'pressed': pressed(m, dark)},
        'spaceKey': {'fill': a, 'pressed': pressed(a, dark)},
        'keyText': al,
        'functionGlyph': ml,
        'returnPrimary': {'fill': r, 'text': rl, 'pressed': pressed(r, dark)},
        'keyOverrides': {k: {'fill': f, 'glyph': g, 'pressed': pressed(f, dark)}
                         for k, (f, g) in (overrides or {}).items()},
        # Apple's callout is the key it grows from.
        'popup': {'fill': a, 'text': al},
        'strip': {'background': 'board', 'text': al if not dark else mix(al, '#FFFFFF', 0.0),
                  'ios': 'clear (system sheet)'},
        # The chip wears the letter key's face and the accent.
        'chip': {'face': a, 'accent': r if _readable(r, a) else al},
        'boundDot': r if _readable(r, a, 3.0) else al,
        # Apple's own: a hard 1pt edge under each key.
        'shadow': {'color': '#000000', 'alpha': 0.55 if dark else 0.28, 'offsetY': 1, 'radius': 0},
        'border': None,
    }
    # The strip text sits on the Android board.
    v['strip']['text'] = al if _readable(al, v['board']['colors'][0]) else ml
    return v


def _ratio(x, y):
    a, b = sorted((lum(x), lum(y)))
    return (b + 0.05) / (a + 0.05)


def _readable(fg, bg, lo=4.5):
    return _ratio(fg, bg) >= lo


def main():
    out = []
    for (tid, name, cat, mood, fam, pack, light, dark, extra) in T:
        font = FONTS.get(fam, SYSTEM_FONT) if fam != 'system' else SYSTEM_FONT
        sound = SOUNDS.get(pack, SYSTEM_SOUND) if pack != 'system' else SYSTEM_SOUND
        ov = extra.get('overrides', {})
        out.append({
            'id': tid, 'name': name, 'category': cat, 'mood': mood,
            'heroMode': 'light', 'modes': ['light', 'dark'],
            'source': 'Public-domain book, original design' if cat == 'Stories' else 'Original',
            'font': font,
            'glyphStyle': 'standard',
            'sound': sound,
            'texture': None,
            'tier': 'free',
            'variants': {'light': variant('light', light, ov.get('light')),
                         'dark': variant('dark', dark, ov.get('dark'))},
        })
    json.dump(out, open(OUT, 'w'), indent=1, ensure_ascii=False)
    open(OUT, 'a').write('\n')
    print('%d themes -> %s' % (len(out), OUT))


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""The tryglyf.com logo: what Google's sign-in consent screen shows, and the
same lettering in the site's footer (Google's brand check looks for the
uploaded logo on the homepage).

"glyf" in ink, "try" and "com" softer, the "." in Glyf's purple (the
wordmark's dot), in the site's Inter at 700. Writes, in site/public/brand/:
tryglyf-logo-120.png (the upload: 120x120 on white), tryglyf-logo-1024.png
(its master), and tryglyf-logo-light.png / -dark.png (the footer's, on
transparent ground). Run from the repo root: python3 tools/make_domain_logo.py
"""
import os

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT = os.path.join(ROOT, "site/public/fonts/Inter-Variable.ttf")
OUT = os.path.join(ROOT, "site/public/brand/")
TEXT = "tryglyf.com"
ACCENT = (124, 92, 255, 255)
LIGHT = ((110, 110, 115, 255), (29, 29, 31, 255))   # soft, ink
DARK = ((161, 161, 166, 255), (245, 245, 247, 255))
SIZE = 166   # fills 82% of the 1024 square


def font(size):
    f = ImageFont.truetype(FONT, size)
    f.set_variation_by_axes([32, 700])
    return f


def colours(soft, ink):
    return [soft] * 3 + [ink] * 4 + [ACCENT] + [soft] * 3


def draw(d, x, baseline, f, fills):
    tr = -0.03 * f.size
    for i, ch in enumerate(TEXT):
        d.text((x + f.getlength(TEXT[:i]) + tr * i, baseline), ch, font=f, fill=fills[i], anchor="ls")


def main():
    f = font(SIZE)
    tr = -0.03 * SIZE
    w = f.getlength(TEXT) + tr * (len(TEXT) - 1)
    probe = ImageDraw.Draw(Image.new("RGBA", (10, 10)))
    top, bottom = probe.textbbox((0, 0), TEXT, font=f, anchor="ls")[1::2]

    # The upload: centred on the letters' ink, on white.
    n = 1024
    im = Image.new("RGBA", (n, n), (255, 255, 255, 255))
    draw(ImageDraw.Draw(im), (n - w) / 2, n / 2 - (top + bottom) / 2, f, colours(*LIGHT))
    im = im.convert("RGB")
    im.save(OUT + "tryglyf-logo-1024.png", optimize=True)
    im.resize((120, 120), Image.LANCZOS).save(OUT + "tryglyf-logo-120.png", optimize=True)

    # The footer's, tight around the letters.
    pad = 8
    for name, pair in (("light", LIGHT), ("dark", DARK)):
        im = Image.new("RGBA", (int(w + pad * 2), int(bottom - top + pad * 2)), (0, 0, 0, 0))
        draw(ImageDraw.Draw(im), pad, pad - top, f, colours(*pair))
        im.save(OUT + f"tryglyf-logo-{name}.png", optimize=True)
    print("wrote tryglyf-logo-120.png, -1024.png, -light.png, -dark.png")


if __name__ == "__main__":
    main()

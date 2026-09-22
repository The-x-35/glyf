#!/usr/bin/env python3
"""Render the tryglyf.com hero as an X (Twitter) profile banner, 1500x500.

Shares its drawing with `make_og_image.py` (the same Inter setup, the same
wordmark, the same keyboard lying back behind the words), so the banner cannot
drift away from the page it is taken from. What differs is what a banner is
for: no nav, no store badges, no waitlist form. A banner is the headline, the
line under it, and the keyboard.

Two things a 1500x500 banner has to respect that a share card does not:

  - X lays the profile picture over the bottom left. The avatar is about 133px
    across on desktop and hangs below the banner's edge, so the lower left
    corner is not ours to use.
  - X crops the sides on narrow windows and keeps the middle. Everything that
    has to be read is centred.

Run from the repo root:

    python3 tools/make_x_banner.py [out.png]

Defaults to site/public/brands/glyf-x-banner.png. Needs Pillow.
"""

import math
import os
import sys

from PIL import Image, ImageChops, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_og_image as og  # noqa: E402  (path set above)

W, H = 1500, 500
og.W, og.H, og.S = W, H, 2  # the shared helpers read these

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "site/public/brands/glyf-x-banner.png")

TITLE_SIZE = 86.0
SUB_SIZE = 25.0
# The avatar's corner, in banner points: keep the drawing out of it.
AVATAR = (24, H - 96, 24 + 150, H)


def backdrop():
    """The hero's keyboard, laid back and faded, sized for a 3:1 banner.

    `make_og_image.backdrop()` is tuned for a 630px-tall card: on 500px the
    board would fill the frame and swallow the words. This keeps the same
    tilt and the same radial fade, and simply sits the board lower and
    smaller so the type has the middle of the banner to itself.
    """
    flat, bw, bh = og.keyboard_layer()
    tilt = math.radians(52)
    persp, ox, oy = 1500.0, W / 2, H * 0.12
    bottom = H + 96.0
    f = persp / (persp + bh * math.sin(tilt))
    y_top = oy + (bottom - bh * math.cos(tilt) - oy) * f
    left, right = ox - bw / 2, ox + bw / 2
    dst = [
        (og.px(ox + (left - ox) * f), og.px(y_top)),
        (og.px(ox + (right - ox) * f), og.px(y_top)),
        (og.px(right), og.px(bottom)),
        (og.px(left), og.px(bottom)),
    ]
    src = [(0, 0), (flat.width, 0), (flat.width, flat.height), (0, flat.height)]
    layer = flat.transform((og.px(W), og.px(H)), Image.PERSPECTIVE,
                           og.perspective_coeffs(dst, src), Image.BICUBIC)

    # The page's radial mask, widened for the aspect, TIMES a fade up the
    # frame. On the page the board's own top edge is far above the viewport,
    # so the radial alone is enough; in 500px that edge lands in shot and
    # draws a hard line across the banner. The vertical term is what lets the
    # keyboard rise out of the bottom instead of starting somewhere.
    mw, mh = 300, 100
    rise_from, rise_to = 0.60, 0.92     # transparent here, full by here
    vals = []
    for j in range(mh):
        y = (j + 0.5) / mh
        rise = min(1.0, max(0.0, (y - rise_from) / (rise_to - rise_from))) ** 1.6
        for i in range(mw):
            dx = ((i + 0.5) / mw * W - W * 0.5) / (W * 0.62)
            dy = (y * H - H * 0.88) / (H * 0.78)
            dist = math.hypot(dx, dy)
            k = 1.0 if dist <= 0.2 else 0.0 if dist >= 0.76 else 1 - (dist - 0.2) / 0.56
            vals.append(int(255 * 0.34 * k * rise))
    mask = Image.new("L", (mw, mh))
    mask.putdata(vals)
    mask = mask.resize((og.px(W), og.px(H)), Image.BILINEAR)
    layer.putalpha(ImageChops.multiply(layer.getchannel("A"), mask))
    return layer


def headline(d, top):
    """"Type less. " + the wordmark "glyf" with its raised dot + " more."."""
    tf, mf = og.font(TITLE_SIZE, 600), og.font(TITLE_SIZE, 700)
    ttr, mtr = -0.05 * og.px(TITLE_SIZE), -0.045 * og.px(TITLE_SIZE)
    head, mark, tail = "Type less. ", "glyf", " more."
    gap, dot = og.px(TITLE_SIZE * 0.16), og.px(TITLE_SIZE * 0.18)
    w_head = og.text_width(tf, head, ttr) + ttr
    w_mark = og.text_width(mf, mark, mtr) + mtr
    w_tail = og.text_width(tf, tail, ttr)
    x = (og.px(W) - (w_head + w_mark + gap + dot + w_tail)) / 2
    baseline = og.px(top + TITLE_SIZE * 0.8)
    og.draw_text(d, x, baseline, head, tf, ttr, og.INK)
    x += w_head
    og.draw_text(d, x, baseline, mark, mf, mtr, og.INK)
    x += w_mark + gap
    d.ellipse((x, baseline - og.px(TITLE_SIZE * 0.74) - dot,
               x + dot, baseline - og.px(TITLE_SIZE * 0.74)), fill=og.ACCENT)
    x += dot
    og.draw_text(d, x, baseline, tail, tf, ttr, og.INK)


def main():
    out_path = sys.argv[1] if len(sys.argv) > 1 else OUT
    canvas = Image.new("RGBA", (og.px(W), og.px(H)), og.BG + (255,))
    canvas.alpha_composite(backdrop())
    d = ImageDraw.Draw(canvas)

    # The words sit above the middle: the keyboard rises from the bottom, and
    # the avatar takes the bottom left.
    block = TITLE_SIZE + 20 + SUB_SIZE * 1.2
    top = (H - block) / 2 - 26

    headline(d, top)
    y = top + TITLE_SIZE + 20
    sf = og.font(SUB_SIZE, 500)
    tr = -0.02 * og.px(SUB_SIZE)
    sw = og.text_width(sf, og.SUB, tr)
    og.draw_text(d, (og.px(W) - sw) / 2, og.px(y + SUB_SIZE * 0.95), og.SUB, sf, tr, og.INK_2)

    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    canvas.convert("RGB").resize((W, H), Image.LANCZOS).save(out_path, "PNG", optimize=True)
    print("wrote", os.path.relpath(out_path, ROOT), os.path.getsize(out_path), "bytes")


if __name__ == "__main__":
    main()

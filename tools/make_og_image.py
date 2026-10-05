#!/usr/bin/env python3
"""Render the tryglyf.com hero as the site's Open Graph / Twitter image.

Draws the desktop hero at 1200x630 the way the page lays it out: nav with the
wordmark and "Join waitlist" pill, "Type less. Glyf more.", the subline, the
greyed store badges, the waitlist form, and the faint Glyf keyboard lying back
behind it (same perspective, opacity and radial mask as BackdropKeys.tsx).

Run from the repo root after changing the hero copy or styles:

    python3 tools/make_og_image.py

Writes site/app/opengraph-image.png and site/app/twitter-image.png. Needs Pillow.
"""

import math
import os
import re

from PIL import Image, ImageChops, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT = os.path.join(ROOT, "site/public/fonts/Inter-Variable.ttf")
OUT = [os.path.join(ROOT, "site/app/opengraph-image.png"), os.path.join(ROOT, "site/app/twitter-image.png")]

W, H = 1200, 630
S = 2  # supersample, downscaled at the end

BG = (255, 255, 255)
INK = (29, 29, 31)
INK_2 = (110, 110, 115)
INK_3 = (161, 161, 166)
ACCENT = (124, 92, 255)
KB = (213, 216, 222)
KB_FN = (181, 186, 195)
# The key face and the shadow under it. Separate from KB so the same drawing
# can run in the site's dark palette (see make_x_banner.py), where a key is
# not white and the edge is not a shade of the board.
KEY = (255, 255, 255)
EDGE = None  # None = derive from KB, which is what the light hero does

TITLE = "Type less. Glyf more."
SUB = "The AI keyboard that does the rest."


def px(v):
    return int(round(v * S))


def font(size, weight):
    f = ImageFont.truetype(FONT, px(size))
    f.set_variation_by_axes([max(14, min(32, size)), weight])
    return f


def text_width(f, text, tracking):
    return f.getlength(text) + tracking * (len(text) - 1)


def draw_text(d, x, baseline, text, f, tracking=0.0, fill=INK):
    """Left/baseline text with CSS-style letter-spacing (keeps the font's kerning)."""
    for i, ch in enumerate(text):
        d.text((x + f.getlength(text[:i]) + tracking * i, baseline), ch, font=f, fill=fill, anchor="ls")


def rounded(d, box, r, fill, outline=None, width=1):
    d.rounded_rectangle(box, radius=r, fill=fill, outline=outline, width=width)


# ---------- minimal SVG path flattening (M L H V C S Z, abs + rel) ----------

def path_polys(path, scale, ox, oy, steps=18):
    tokens = re.findall(r"[MmLlHhVvCcSsZz]|-?(?:\d+\.\d*|\.\d+|\d+)(?:e-?\d+)?", path)
    polys, cur, pts = [], (0.0, 0.0), []
    start, last_ctrl, cmd, i = (0.0, 0.0), None, None, 0

    def num():
        nonlocal i
        v = float(tokens[i])
        i += 1
        return v

    def emit(p):
        pts.append((ox + p[0] * scale, oy + p[1] * scale))

    while i < len(tokens):
        t = tokens[i]
        if re.fullmatch(r"[A-Za-z]", t):
            cmd = t
            i += 1
            if cmd in "Zz":
                if pts:
                    polys.append(pts)
                pts, cur, last_ctrl = [], start, None
                continue
        rel = cmd.islower()
        c = cmd.upper()
        if c == "M":
            x, y = num(), num()
            cur = (cur[0] + x, cur[1] + y) if rel else (x, y)
            if pts:
                polys.append(pts)
            pts, start, last_ctrl = [], cur, None
            emit(cur)
            cmd = "l" if rel else "L"
        elif c == "L":
            x, y = num(), num()
            cur = (cur[0] + x, cur[1] + y) if rel else (x, y)
            emit(cur)
            last_ctrl = None
        elif c == "H":
            x = num()
            cur = (cur[0] + x, cur[1]) if rel else (x, cur[1])
            emit(cur)
            last_ctrl = None
        elif c == "V":
            y = num()
            cur = (cur[0], cur[1] + y) if rel else (cur[0], y)
            emit(cur)
            last_ctrl = None
        elif c in "CS":
            if c == "C":
                x1, y1 = num(), num()
                if rel:
                    x1, y1 = cur[0] + x1, cur[1] + y1
            else:
                x1, y1 = (2 * cur[0] - last_ctrl[0], 2 * cur[1] - last_ctrl[1]) if last_ctrl else cur
            x2, y2, x, y = num(), num(), num(), num()
            if rel:
                x2, y2, x, y = cur[0] + x2, cur[1] + y2, cur[0] + x, cur[1] + y
            p0 = cur
            for k in range(1, steps + 1):
                u = k / steps
                a, b, cc, dd = (1 - u) ** 3, 3 * u * (1 - u) ** 2, 3 * u * u * (1 - u), u ** 3
                emit((a * p0[0] + b * x1 + cc * x2 + dd * x, a * p0[1] + b * y1 + cc * y2 + dd * y))
            cur, last_ctrl = (x, y), (x2, y2)
    if pts:
        polys.append(pts)
    return polys


APPLE = "M17.05 12.53c-.03-2.9 2.37-4.29 2.48-4.36-1.35-1.97-3.45-2.24-4.2-2.27-1.79-.18-3.49 1.05-4.4 1.05-.9 0-2.3-1.02-3.79-1-1.95.03-3.74 1.13-4.74 2.87-2.02 3.5-.52 8.68 1.45 11.52.96 1.39 2.11 2.95 3.62 2.9 1.45-.06 2-.94 3.76-.94s2.25.94 3.79.91c1.56-.03 2.55-1.42 3.51-2.82 1.1-1.62 1.56-3.19 1.58-3.27-.03-.02-3.03-1.16-3.06-4.59zM14.16 4c.8-.97 1.34-2.32 1.19-3.66-1.15.05-2.55.77-3.38 1.73-.74.86-1.39 2.23-1.22 3.55 1.29.1 2.6-.65 3.41-1.62z"
PLAY = [
    ("M3.6 1.8c-.36.38-.6.97-.6 1.73v16.94c0 .76.24 1.35.6 1.73l.1.09 9.49-9.49v-.22L3.7 1.71l-.1.09z", 1.0),
    ("M16.35 15.95l-3.16-3.16v-.22l3.16-3.16.07.04 3.75 2.13c1.07.6 1.07 1.6 0 2.21l-3.75 2.12-.07.04z", 0.75),
    ("M16.42 15.9L13.19 12.7 3.6 22.2c.35.37.93.42 1.59.05l11.23-6.35z", 0.55),
    ("M16.42 8.1L5.19 1.75C4.53 1.38 3.95 1.43 3.6 1.8l9.59 9.5 3.23-3.2z", 0.9),
]


# ---------- the faint keyboard behind the hero (BackdropKeys.tsx) ----------

BOUND = set("qwertpsjxc")


def keyboard_layer():
    board_w, pad, col_gap, row_gap, row_h = 1380.0, 19.2, 9.6, 14.4, 74.4
    board_h = 4 * row_h + 3 * row_gap + 2 * pad
    img = Image.new("RGBA", (px(board_w), px(board_h)), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    rounded(d, (0, 0, px(board_w) - 1, px(board_h) - 1), px(36), KB + (255,))
    col_w = (board_w - 2 * pad - 19 * col_gap) / 20
    letter_f, fn_f, space_f = font(31.2, 400), font(20.4, 400), font(21.6, 500)
    edge = (EDGE or tuple(int(c * 0.76) for c in KB)) + (255,)

    rows = [
        [(k, 2, None) for k in "qwertyuiop"],
        [(k, 2, 2 if j == 0 else None) for j, k in enumerate("asdfghjkl")],
        [("shift", 3, None)] + [(k, 2, None) for k in "zxcvbnm"] + [("del", 3, None)],
        [("123", 3, None), ("emoji", 2, None), ("space", 10, None), (".", 2, None), ("return", 3, None)],
    ]
    for r, row in enumerate(rows):
        col = 1
        y = pad + r * (row_h + row_gap)
        for key, span, start in row:
            if start:
                col = start
            x = pad + (col - 1) * (col_w + col_gap)
            w = span * col_w + (span - 1) * col_gap
            col += span
            fn = key in ("shift", "del", "123", "emoji", ".", "return")
            box = (px(x), px(y), px(x + w), px(y + row_h))
            rounded(d, (box[0], box[1] + px(2), box[2], box[3] + px(2)), px(12), edge)
            rounded(d, box, px(12), (KB_FN if fn else KEY) + (255,))
            cx, cy = px(x + w / 2), px(y + row_h / 2)
            if len(key) == 1 and key.isalpha():
                d.text((cx, cy), key, font=letter_f, fill=INK + (255,), anchor="mm")
                if key in BOUND:
                    dot = 6.6
                    dx, dy = x + w * 0.88 - dot, y + row_h * 0.12
                    d.ellipse((px(dx), px(dy), px(dx + dot), px(dy + dot)), fill=ACCENT + (255,))
            elif key == "space":
                d.text((cx, cy), "glyf", font=space_f, fill=INK + (102,), anchor="mm")
            elif key in ("123", "."):
                d.text((cx, cy), key, font=fn_f, fill=INK + (255,), anchor="mm")
            elif key == "shift":
                a = px(9)
                d.polygon([(cx, cy - a), (cx + a, cy), (cx + a / 2, cy), (cx + a / 2, cy + a), (cx - a / 2, cy + a), (cx - a / 2, cy), (cx - a, cy)], outline=INK + (255,), width=px(1.6))
            elif key == "del":
                a = px(9)
                d.polygon([(cx - a * 1.4, cy), (cx - a * 0.6, cy - a), (cx + a * 1.2, cy - a), (cx + a * 1.2, cy + a), (cx - a * 0.6, cy + a)], outline=INK + (255,), width=px(1.6))
            elif key == "return":
                a = px(8)
                d.line([(cx + a, cy - a), (cx + a, cy + a * 0.4), (cx - a, cy + a * 0.4)], fill=INK + (255,), width=px(1.8))
                d.line([(cx - a * 0.5, cy - a * 0.1), (cx - a, cy + a * 0.4), (cx - a * 0.5, cy + a * 0.9)], fill=INK + (255,), width=px(1.8))
            elif key == "emoji":
                a = px(9)
                d.ellipse((cx - a, cy - a, cx + a, cy + a), outline=INK + (255,), width=px(1.6))
                d.arc((cx - a * 0.55, cy - a * 0.4, cx + a * 0.55, cy + a * 0.55), 20, 160, fill=INK + (255,), width=px(1.6))
    return img, board_w, board_h


def solve(a, b):
    n = len(b)
    m = [row[:] + [b[i]] for i, row in enumerate(a)]
    for c in range(n):
        p = max(range(c, n), key=lambda r: abs(m[r][c]))
        m[c], m[p] = m[p], m[c]
        for r in range(n):
            if r != c:
                f = m[r][c] / m[c][c]
                for k in range(c, n + 1):
                    m[r][k] -= f * m[c][k]
    return [m[i][n] / m[i][i] for i in range(n)]


def perspective_coeffs(dst, src):
    """Coefficients mapping output (dst) points back to input (src) points."""
    a, b = [], []
    for (x, y), (u, v) in zip(dst, src):
        a.append([x, y, 1, 0, 0, 0, -u * x, -u * y])
        b.append(u)
        a.append([0, 0, 0, x, y, 1, -v * x, -v * y])
        b.append(v)
    return solve(a, b)


def backdrop():
    flat, bw, bh = keyboard_layer()
    tilt = math.radians(52)
    persp, ox, oy = 1500.0, W / 2, H * 0.30
    bottom = H + 84.0  # lower than the page's -10svh so the badges stay clear on a 630px card
    f = persp / (persp + bh * math.sin(tilt))
    y_top = oy + (bottom - bh * math.cos(tilt) - oy) * f
    left, right = ox - bw / 2, ox + bw / 2
    dst = [(px(ox + (left - ox) * f), px(y_top)), (px(ox + (right - ox) * f), px(y_top)), (px(right), px(bottom)), (px(left), px(bottom))]
    src = [(0, 0), (flat.width, 0), (flat.width, flat.height), (0, flat.height)]
    layer = flat.transform((px(W), px(H)), Image.PERSPECTIVE, perspective_coeffs(dst, src), Image.BICUBIC)

    # radial-gradient(ellipse 62% 70% at 50% 78%, #000 20%, transparent 74%) x opacity 0.34
    mw, mh = 300, 158
    mask = Image.new("L", (mw, mh))
    vals = []
    for j in range(mh):
        for i in range(mw):
            dx = ((i + 0.5) / mw * W - W * 0.5) / (W * 0.62)
            dy = ((j + 0.5) / mh * H - H * 0.78) / (H * 0.70)
            dist = math.hypot(dx, dy)
            k = 1.0 if dist <= 0.2 else 0.0 if dist >= 0.74 else 1 - (dist - 0.2) / 0.54
            vals.append(int(255 * 0.34 * k))
    mask.putdata(vals)
    mask = mask.resize((px(W), px(H)), Image.BILINEAR)
    layer.putalpha(ImageChops.multiply(layer.getchannel("A"), mask))
    return layer


# ---------- hero pieces ----------

def wordmark(d, x, center_y):
    size = 28
    f = font(size, 700)
    tr = -0.045 * px(size)
    baseline = px(center_y) + px(size * 0.36)
    draw_text(d, px(x), baseline, "glyf", f, tr, INK)
    end = px(x) + text_width(f, "glyf", tr)
    dot = px(size * 0.18)
    dx = end + px(size * 0.16)
    dy = baseline - px(size * 0.74) - dot
    d.ellipse((dx, dy, dx + dot, dy + dot), fill=ACCENT)


NAV_H = 64


def nav(d):
    mid = NAV_H / 2
    d.rectangle((0, px(NAV_H), px(W), px(NAV_H) + px(1)), fill=(235, 235, 235))
    wrap_left, wrap_right = (W - 1180) / 2 + 22, W - (W - 1180) / 2 - 22
    wordmark(d, wrap_left, mid)
    f = font(14, 500)
    label = "Join waitlist"
    tw = f.getlength(label) / S
    pill_w, pill_h = tw + 36, 35
    x1 = wrap_right
    x0 = x1 - pill_w
    rounded(d, (px(x0), px(mid - pill_h / 2), px(x1), px(mid + pill_h / 2)), px(pill_h / 2), INK)
    d.text((px(x0 + pill_w / 2), px(mid)), label, font=f, fill=(255, 255, 255), anchor="mm")
    # theme toggle (moon), 38px button 10px left of the pill
    cx, cy, r = x0 - 10 - 19, mid, 8.5
    d.ellipse((px(cx - r), px(cy - r), px(cx + r), px(cy + r)), outline=INK_2, width=px(1.7))
    d.ellipse((px(cx - r + 5), px(cy - r - 3.4), px(cx + r + 5), px(cy + r - 3.4)), fill=BG)


def store_badge(canvas, x, y, mark, small, big):
    h = 52.0
    small_f, big_f = font(10.5, 500), font(18, 600)
    small_tr, big_tr = 0.01 * px(10.5), -0.02 * px(18)
    mark_size = 24.0 if mark == "apple" else 22.0
    lines_w = max(text_width(small_f, small, small_tr), text_width(big_f, big, big_tr)) / S
    w = 14 + mark_size + 9 + lines_w + 18
    layer = Image.new("RGBA", (px(w), px(h)), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    rounded(d, (0, 0, px(w) - 1, px(h) - 1), px(12), INK + (255,))
    mx, my = 14, (h - mark_size) / 2
    if mark == "apple":
        for poly in path_polys(APPLE, px(mark_size) / 24, px(mx), px(my)):
            d.polygon(poly, fill=(255, 255, 255, 255))
    else:
        for p, op in PLAY:
            for poly in path_polys(p, px(mark_size) / 24, px(mx), px(my)):
                d.polygon(poly, fill=(255, 255, 255, int(255 * op)))
    tx = px(14 + mark_size + 9)
    top = (h - (10.5 * 1.1 + 18 * 1.1)) / 2
    draw_text(d, tx, px(top + 10.5 * 0.9), small, small_f, small_tr, (255, 255, 255))
    draw_text(d, tx, px(top + 10.5 * 1.1 + 18 * 0.88), big, big_f, big_tr, (255, 255, 255))
    a = layer.getchannel("A").point(lambda v: int(v * 0.32))
    layer.putalpha(a)
    canvas.alpha_composite(layer, (px(x), px(y)))
    return w


def main():
    canvas = Image.new("RGBA", (px(W), px(H)), BG + (255,))
    canvas.alpha_composite(backdrop())
    d = ImageDraw.Draw(canvas)
    nav(d)

    # hero content, centred like .hero (min-height 92svh, padding 120/90)
    title_size = 112.0
    sub_size = 28.8
    block = title_size + 21.6 + sub_size * 1.21 + 36 + 52 + 31.2 + 50
    hero_h = 0.92 * H
    top = 120 + ((hero_h - 90) - 120 - block) / 2
    top = max(top, NAV_H + 40)  # keep clear of the nav on a short card

    # "Type less. " + wordmark "glyf" with its raised dot + " more."
    tf, mf = font(title_size, 600), font(title_size, 700)
    ttr, mtr = -0.05 * px(title_size), -0.045 * px(title_size)
    head, mark, tail = "Type less. ", "glyf", " more."
    gap, dot = px(title_size * 0.16), px(title_size * 0.18)
    w_head = text_width(tf, head, ttr) + ttr
    w_mark = text_width(mf, mark, mtr) + mtr
    w_tail = text_width(tf, tail, ttr)
    total = w_head + w_mark + gap + dot + w_tail
    x = (px(W) - total) / 2
    baseline = px(top + title_size * 0.8)
    draw_text(d, x, baseline, head, tf, ttr, INK)
    x += w_head
    draw_text(d, x, baseline, mark, mf, mtr, INK)
    x += w_mark + gap
    d.ellipse((x, baseline - px(title_size * 0.74) - dot, x + dot, baseline - px(title_size * 0.74)), fill=ACCENT)
    x += dot
    draw_text(d, x, baseline, tail, tf, ttr, INK)
    y = top + title_size + 21.6

    sf = font(sub_size, 500)
    str_ = -0.02 * px(sub_size)
    sw = text_width(sf, SUB, str_)
    draw_text(d, (px(W) - sw) / 2, px(y + sub_size * 0.95), SUB, sf, str_, INK_2)
    y += sub_size * 1.21 + 36

    # badges: measure first, then centre the pair
    probe = Image.new("RGBA", (10, 10))
    w1 = store_badge(probe, 0, 0, "apple", "Coming soon on", "App Store")
    w2 = store_badge(probe, 0, 0, "play", "Coming soon on", "Google Play")
    bx = (W - (w1 + 12 + w2)) / 2
    store_badge(canvas, bx, y, "apple", "Coming soon on", "App Store")
    store_badge(canvas, bx + w1 + 12, y, "play", "Coming soon on", "Google Play")
    y += 52 + 31.2

    # waitlist form (.wl-box, max-width 460)
    d = ImageDraw.Draw(canvas)
    fw, fh = 460.0, 50.0
    fx = (W - fw) / 2
    rounded(d, (px(fx), px(y), px(fx + fw), px(y + fh)), px(fh / 2), (255, 255, 255), outline=(219, 219, 219), width=px(1))
    pf = font(16, 400)
    d.text((px(fx + 22), px(y + fh / 2)), "you@email.com", font=pf, fill=INK_3, anchor="lm")
    bf = font(15, 500)
    blabel = "Join the waitlist"
    bw = bf.getlength(blabel) / S + 36
    bh = 38.0
    bx1 = fx + fw - 6
    rounded(d, (px(bx1 - bw), px(y + (fh - bh) / 2), px(bx1), px(y + (fh + bh) / 2)), px(bh / 2), INK)
    d.text((px(bx1 - bw / 2), px(y + fh / 2)), blabel, font=bf, fill=(255, 255, 255), anchor="mm")

    out = canvas.convert("RGB").resize((W, H), Image.LANCZOS)
    for path in OUT:
        out.save(path, "PNG", optimize=True)
        print("wrote", os.path.relpath(path, ROOT), os.path.getsize(path), "bytes")


if __name__ == "__main__":
    main()

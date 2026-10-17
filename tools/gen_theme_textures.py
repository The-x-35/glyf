#!/usr/bin/env python3
"""Draws the keyboard themes' surface textures as seamless tiles.

    <python with numpy + Pillow> tools/gen_theme_textures.py

Writes shared/themes/textures/<kind>.png: 256x256 grey+alpha tiles that wrap on
every edge. Each pixel is white (lifts the surface) or black (sinks it) with
an alpha for how much, so a tile lays over ANY key colour at the theme's own
strength: one normal-blend pass, the same on iOS (pattern fill), Android
(BitmapShader) and the app's previews. Third pass on the themes (Arpit,
2026-10-17: "these look sooo low effort and cheap just colours, fucking add
some class in themes"): real materials on the keys.

Everything is drawn here from seeded noise and geometry: no photographs, no
downloads, nothing to license.
"""
import os
import numpy as np
from PIL import Image

N = 256
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'shared', 'themes', 'textures')
yy, xx = np.mgrid[0:N, 0:N].astype(np.float64)


def periodic_noise(seed, lo, hi, aniso=(1.0, 1.0)):
    """Band-limited noise that tiles: random phases filtered in frequency
    space between wavelengths N/hi and N/lo, scaled -1..1."""
    rng = np.random.default_rng(seed)
    spec = np.fft.fft2(rng.standard_normal((N, N)))
    fy = np.fft.fftfreq(N)[:, None] * N / aniso[1]
    fx = np.fft.fftfreq(N)[None, :] * N / aniso[0]
    f = np.sqrt(fx ** 2 + fy ** 2)
    band = (f >= lo) & (f <= hi)
    out = np.real(np.fft.ifft2(spec * band))
    out -= out.mean()
    m = np.abs(out).max() or 1
    return out / m


def save(name, v, strength=1.0):
    """v in -1..1: positive lifts (white), negative sinks (black)."""
    v = np.clip(v * strength, -1, 1)
    lum = np.where(v > 0, 255, 0).astype(np.uint8)
    a = ((np.abs(v) * 255).astype(np.uint8) // 8 * 8)   # 32 levels: smaller files, the same look at a few percent
    # Grey + alpha (PNG "LA"): the same pixels as RGBA in half the bytes.
    os.makedirs(OUT, exist_ok=True)
    Image.fromarray(np.dstack([lum, a]), 'LA').save(os.path.join(OUT, name + '.png'), optimize=True)


def paper():
    grain = periodic_noise(1, 60, 128)
    mottle = periodic_noise(2, 3, 9)
    fib = periodic_noise(3, 20, 60, aniso=(4.0, 0.6))
    fib = np.where(np.abs(fib) > 0.55, fib, 0)
    return 0.6 * grain + 0.12 * mottle + 0.45 * fib


def washi():
    base = paper()
    long = periodic_noise(4, 8, 30, aniso=(8.0, 0.4))
    long = np.where(long > 0.5, long, 0)
    return 0.7 * base + 0.8 * long


def brushed():
    streak = periodic_noise(5, 2, 128, aniso=(0.04, 1.0))
    fine = periodic_noise(6, 60, 128, aniso=(0.2, 1.0))
    return 0.8 * streak + 0.3 * fine


def wood():
    warp = periodic_noise(7, 1, 4)
    knot = periodic_noise(8, 2, 6)
    # Quarter-sawn walnut: long straight grain lines, gently drifting.
    rings = np.sin(2 * np.pi * (yy / N * 22 + 0.35 * warp + 0.12 * knot))
    figure = periodic_noise(9, 30, 128, aniso=(0.05, 1.0))
    return 0.55 * np.sign(rings) * np.abs(rings) ** 4 + 0.5 * figure


def marble():
    turb = sum(periodic_noise(10 + i, 2 ** i, 2 ** (i + 1)) / (i + 1) for i in range(0, 3))
    v = np.sin(2 * np.pi * ((xx + yy) / N * 1) + 3.2 * turb)
    vein = -np.exp(-np.abs(v) * 6) - 0.5 * np.exp(-np.abs(v - 0.6) * 14)   # soft veins
    cloud = 0.25 * periodic_noise(20, 2, 6)
    return vein + cloud


def herringbone():
    # Tweed: twill blocks that change direction every 16px, with yarn noise.
    band = ((yy // 16) % 2) * 2 - 1
    twill = np.sin(2 * np.pi * (xx + band * yy) / 6)
    yarn = periodic_noise(21, 40, 128)
    fleck = np.where(periodic_noise(22, 60, 128) > 0.75, 1.0, 0)
    return 0.55 * twill + 0.35 * yarn + 0.5 * fleck


def leather():
    # Pebble grain: Worley cells, seams where the two nearest seeds are
    # about as near (F2 - F1 small), domed in between.
    rng = np.random.default_rng(23)
    pts = rng.random((700, 2)) * N
    f1 = np.full((N, N), 1e9); f2 = np.full((N, N), 1e9)
    for px, py in pts:
        dx = np.abs(xx - px); dx = np.minimum(dx, N - dx)
        dy = np.abs(yy - py); dy = np.minimum(dy, N - dy)
        d = np.sqrt(dx * dx + dy * dy)
        f2 = np.where(d < f1, f1, np.minimum(f2, d))
        f1 = np.minimum(f1, d)
    seam = np.clip((f2 - f1) / 2.5, 0, 1)
    dome = 1 - np.clip(f1 / 6.0, 0, 1)
    return 0.6 * (seam * 2 - 1) * 0.6 + 0.35 * dome + 0.2 * periodic_noise(24, 50, 128)


def scanlines():
    rows = np.where(yy % 3 == 0, -1.0, 0.0)
    return rows + 0.15 * periodic_noise(25, 60, 128)


def sand():
    grain = periodic_noise(26, 70, 128)
    ripple = np.sin(2 * np.pi * (yy / N * 7 + 0.6 * periodic_noise(27, 1, 3)))
    return 0.6 * grain + 0.35 * ripple


def crosshatch():
    jitter = 0.6 * periodic_noise(28, 4, 12)
    a = np.cos(2 * np.pi * ((xx + yy) / 8 + jitter))
    b = np.cos(2 * np.pi * ((xx - yy) / 8 + jitter))
    lines = -(np.clip(a - 0.85, 0, 1) + np.clip(b - 0.85, 0, 1)) / 0.15
    return 0.8 * lines + 0.2 * paper()


def velvet():
    return 0.7 * periodic_noise(29, 2, 7) + 0.2 * periodic_noise(30, 70, 128)


def patina():
    blot = periodic_noise(31, 3, 12)
    return np.where(blot > 0.2, blot, blot * 0.3) + 0.25 * periodic_noise(32, 50, 128)


def knurl():
    a = np.abs(((xx + yy) % 8) - 4) / 4
    b = np.abs(((xx - yy) % 8) - 4) / 4
    return 1 - 2 * np.minimum(a, b) * 1.6


def bricks():
    row = yy // 16
    off = (row % 2) * 16
    mortar = ((yy % 16) < 1.5) | (((xx + off) % 32) < 1.5)
    face = 0.3 * periodic_noise(33, 20, 80)
    return np.where(mortar, -1.0, face)


def linen():
    warp = np.sin(2 * np.pi * xx / 4)
    weft = np.sin(2 * np.pi * yy / 4)
    slub = periodic_noise(34, 8, 40, aniso=(6.0, 0.3))
    return 0.3 * warp * weft + 0.35 * slub + 0.3 * periodic_noise(35, 60, 128)


def frost():
    flake = periodic_noise(36, 30, 90)
    return np.where(flake > 0.45, flake, 0) + 0.3 * periodic_noise(37, 2, 6)


KINDS = {
    'paper': (paper, 1.0), 'washi': (washi, 1.0), 'brushed': (brushed, 1.0),
    'wood': (wood, 1.0), 'marble': (marble, 1.0), 'herringbone': (herringbone, 1.0),
    'leather': (leather, 1.0), 'scanlines': (scanlines, 1.0), 'sand': (sand, 1.0),
    'crosshatch': (crosshatch, 1.0), 'velvet': (velvet, 1.0), 'patina': (patina, 1.0),
    'knurl': (knurl, 1.0), 'bricks': (bricks, 1.0), 'linen': (linen, 1.0), 'frost': (frost, 1.0),
}


def main():
    for name, (fn, k) in KINDS.items():
        save(name, fn(), k)
        print('wrote', os.path.join('shared/themes/textures', name + '.png'))


if __name__ == '__main__':
    main()

"""Crops the real Settings screens behind onboarding's "Turn on Glyf" guide.

The captures are full-screen screenshots: an iPhone 17 Pro simulator on
iOS 26.5 (1206x2622, status bar set to 9:41) and the Pixel emulator on
Android 16 (1280x2856), taken while turning Glyf on. Each step keeps one
band of the screen at a 1.2:1 ratio; the ring the app draws over it is
given as fractions of that band (printed as Dart for setup_guide.dart).

    python3 tools/setup_guide/make_guide.py <captures-dir> [--preview]

<captures-dir> holds ios/raw-*.png and android/raw-*.png. --preview also
writes each band with its ring drawn, to check the numbers by eye.
"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parents[2] / "app" / "assets" / "setup"
WIDTH = 720  # 3x of a 240pt-wide card; text stays sharp, files stay ~50 KB

# name: (capture, top of the band in capture pixels, ring as x0, y0, x1, y1
# in capture pixels)
IOS = {
    "ios-keyboards-row": ("raw-glyf-page.png", 760, (40, 1560, 1166, 1722)),
    "ios-glyf-switch": ("raw-kb-off.png", 170, (880, 410, 1140, 552)),
    "ios-full-access-switch": ("raw-kb-on-fa-off.png", 170, (880, 570, 1140, 714)),
    "ios-allow": ("raw-fa-alert.png", 850, (600, 1590, 1050, 1756)),
    "ios-back-to-glyf": ("raw-kb-both-on.png", 0, (10, 80, 190, 165)),
    "ios-globe-menu": ("raw-globe-menu.png", 1617, (36, 1750, 676, 1902)),
    "ios-default-order": ("raw-kb-list-glyf-top.png", 170, (52, 396, 1154, 594)),
}
ANDROID = {
    "android-glyf-switch": ("raw-list-off.png", 160, (1050, 980, 1250, 1110)),
    "android-ok": ("raw-attention.png", 950, (962, 1576, 1174, 1758)),
    "android-ok-again": ("raw-reboot.png", 900, (962, 1467, 1174, 1649)),
    "android-back": ("raw-list-on.png", 120, (20, 180, 160, 310)),
    "android-pick-glyf": ("raw-picker.png", 1690, (290, 2250, 1180, 2480)),
}


def band(img: Image.Image, top: int) -> tuple[int, int, int, int]:
    w = img.width
    h = round(w / 1.2)
    top = max(0, min(top, img.height - h))
    return (0, top, w, top + h)


def main() -> None:
    src = Path(sys.argv[1])
    preview = "--preview" in sys.argv
    OUT.mkdir(parents=True, exist_ok=True)
    dart = []
    for folder, table in (("ios", IOS), ("android", ANDROID)):
        for name, (raw, top, ring) in table.items():
            img = Image.open(src / folder / raw).convert("RGB")
            box = band(img, top)
            crop = img.crop(box)
            scale = WIDTH / crop.width
            out = crop.resize((WIDTH, round(crop.height * scale)), Image.LANCZOS)
            out.save(OUT / f"{name}.jpg", quality=82, optimize=True, progressive=True)
            x0, y0, x1, y1 = ring
            bw, bh = box[2] - box[0], box[3] - box[1]
            fr = ((x0 - box[0]) / bw, (y0 - box[1]) / bh, (x1 - box[0]) / bw, (y1 - box[1]) / bh)
            dart.append(f"  '{name}': Rect.fromLTRB({fr[0]:.3f}, {fr[1]:.3f}, {fr[2]:.3f}, {fr[3]:.3f}),")
            if preview:
                p = out.copy()
                d = ImageDraw.Draw(p)
                d.rounded_rectangle([fr[0] * p.width, fr[1] * p.height, fr[2] * p.width, fr[3] * p.height],
                                    radius=18, outline=(124, 92, 255), width=5)
                p.save(src / f"preview-{name}.jpg", quality=80)
    print("\n".join(dart))


if __name__ == "__main__":
    main()

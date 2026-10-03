"""Google Play graphics from the emulator captures (docs/PLAY-STORE.md).

  python3 marketing/play/src/frame.py

Writes marketing/play/phone/0N-*.png (1080 x 1920, 24-bit PNG: a caption above
the real screen, in the site's Inter and colours) from captures/, and
marketing/play/feature-graphic.png (1024 x 500) from feature.html, with
headless Chrome. Captures are 1080 x 1920 emulator screenshots (adb shell wm
size 1080x1920, wm density 420, SystemUI demo mode at 7:41), US examples only.
"""
import html, os, subprocess, tempfile
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
PLAY = os.path.dirname(HERE)
ROOT = os.path.dirname(os.path.dirname(PLAY))
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
FONT = "file://" + os.path.join(ROOT, "site/public/fonts/Inter-Variable.ttf")

SHOTS = [
    ("01-rewrite", "rewrite-1", "Hold space.<br>Glyf does the rest.", "Five rewrites of your message: basic, professional, polite, shorter or with emoji."),
    ("02-answers", "bill-1", "Answers as you type", "Splits, tips, units and time zones, worked out on your phone."),
    ("03-translate", "translate-7", "Reply in their language", "Translate what you typed, check it, then Replace."),
    ("04-details", "vault-1", "Your details,<br>one tap away", "Saved encrypted on your phone. Glyf offers them when a message asks."),
    ("05-emoji", "emoji-1", "Find any emoji<br>by what you mean", "Search “tears”, “party” or “love”, with every skin tone."),
    ("06-style", "style-1", "Style any message", "Bold, italic, script, bubble letters and more, with a word count."),
]

PAGE = """<!doctype html><html><head><meta charset="utf-8"><style>
@font-face {{ font-family: "InterV"; src: url("{font}") format("truetype"); font-weight: 100 900; }}
html, body {{ margin: 0; padding: 0; }}
body {{ width: 1080px; height: 1920px; overflow: hidden; position: relative;
  background: #f5f5f7; color: #1d1d1f; font-family: "InterV", -apple-system, sans-serif; -webkit-font-smoothing: antialiased; }}
.cap {{ position: absolute; left: 80px; right: 80px; top: 92px; display: flex; flex-direction: column; align-items: center; gap: 22px; text-align: center; }}
h1 {{ margin: 0; font-weight: 800; font-size: 74px; line-height: 1.04; letter-spacing: -0.04em; text-wrap: balance; }}
p {{ margin: 0; font-weight: 500; font-size: 36px; line-height: 1.3; letter-spacing: -0.01em; color: #6e6e73; text-wrap: balance; max-width: 860px; }}
.shot {{ position: absolute; left: 50%; transform: translateX(-50%); bottom: -64px; width: 828px; border-radius: 56px; overflow: hidden;
  box-shadow: 0 40px 90px -36px rgba(0,0,0,.38), 0 0 0 1.5px rgba(0,0,0,.07); background: #fff; }}
.shot img {{ display: block; width: 100%; }}
</style></head><body>
<div class="cap"><h1>{title}</h1><p>{sub}</p></div>
<div class="shot"><img src="file://{img}"></div>
</body></html>"""


def shoot(page, out, size):
    raw = out + ".raw.png"
    subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
                    f"--window-size={size[0]},{size[1]}", "--allow-file-access-from-files",
                    f"--screenshot={raw}", f"file://{page}"], check=True, capture_output=True)
    im = Image.open(raw).convert("RGB")   # Play wants no alpha
    assert im.size == size, im.size
    im.save(out, optimize=True)
    os.remove(raw)
    print(os.path.relpath(out, ROOT), im.size)


os.makedirs(os.path.join(PLAY, "phone"), exist_ok=True)
with tempfile.TemporaryDirectory() as tmp:
    for name, shot, title, sub in SHOTS:
        page = os.path.join(tmp, f"{name}.html")
        with open(page, "w", encoding="utf-8") as f:
            f.write(PAGE.format(font=FONT, title=title, sub=html.escape(sub),
                                img=os.path.join(HERE, "captures", shot + ".png")))
        shoot(page, os.path.join(PLAY, "phone", f"{name}.png"), (1080, 1920))
shoot(os.path.join(HERE, "feature.html"), os.path.join(PLAY, "feature-graphic.png"), (1024, 500))

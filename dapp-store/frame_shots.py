"""Solana dApp Store screenshots (docs/SOLANA-DAPP-STORE.md): a headline over the real screen.

  python3 dapp-store/frame_shots.py

Writes dapp-store/media/shots/0N-*.png (1080 x 1920) from marketing/play/src/captures/
with headless Chrome, in the site's Inter. Captures are emulator screenshots of the
dappStore build (1080 x 1920, density 420, demo clock 7:41, US examples).
"""
import html, os, subprocess, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CAPTURES = os.path.join(ROOT, "marketing/play/src/captures")
OUT = os.path.join(ROOT, "dapp-store/media/shots")
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
FONT = "file://" + os.path.join(ROOT, "site/public/fonts/Inter-Variable.ttf")

SHOTS = [
    ("01-buy", "sol-buy", "Buy crypto<br>as you type"),
    ("02-swap", "jup-swap", "Swap on Jupiter<br>from any chat"),
    ("03-calendar", "calendar-event", "Plans go straight<br>to your calendar"),
    ("04-vault", "vault-1", "Your details,<br>one tap away"),
    ("05-tempmail", "tempmail", "A throwaway inbox<br>in your keyboard"),
    ("06-ai", "rewrite-1", "Hold space.<br>Glyf does the rest."),
    ("07-keys", "keys", "Put any action<br>on any key"),
    ("08-search", "youtube", "Search YouTube and Maps<br>without leaving the chat"),
]

PAGE = """<!doctype html><html><head><meta charset="utf-8"><style>
@font-face {{ font-family: "InterV"; src: url("{font}") format("truetype"); font-weight: 100 900; }}
html, body {{ margin: 0; padding: 0; }}
body {{ width: 1080px; height: 1920px; overflow: hidden; position: relative;
  background: #f5f5f7; color: #1d1d1f; font-family: "InterV", -apple-system, sans-serif; -webkit-font-smoothing: antialiased; }}
h1 {{ position: absolute; left: 70px; right: 70px; top: 104px; margin: 0; text-align: center;
  font-weight: 800; font-size: 80px; line-height: 1.04; letter-spacing: -0.04em; text-wrap: balance; }}
.shot {{ position: absolute; left: 50%; transform: translateX(-50%); bottom: -64px; width: 828px; border-radius: 56px; overflow: hidden;
  box-shadow: 0 40px 90px -36px rgba(0,0,0,.38), 0 0 0 1.5px rgba(0,0,0,.07); background: #fff; }}
.shot img {{ display: block; width: 100%; }}
</style></head><body>
<h1>{title}</h1>
<div class="shot"><img src="file://{img}"></div>
</body></html>"""

os.makedirs(OUT, exist_ok=True)
with tempfile.TemporaryDirectory() as tmp:
    for name, shot, title in SHOTS:
        page = os.path.join(tmp, f"{name}.html")
        with open(page, "w", encoding="utf-8") as f:
            f.write(PAGE.format(font=FONT, title=title, img=os.path.join(CAPTURES, shot + ".png")))
        out = os.path.join(OUT, f"{name}.png")
        subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--force-device-scale-factor=1",
                        "--window-size=1080,1920", "--allow-file-access-from-files",
                        f"--screenshot={out}", f"file://{page}"], check=True, capture_output=True)
        print(os.path.relpath(out, ROOT))

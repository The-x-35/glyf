from PIL import Image, ImageDraw, ImageFont
import sys
FONT = "/Users/arpitsingh/Projects/glyf/app/assets/fonts/Inter-Variable.ttf"
W, H = 1080, 1920
def font(size, weight=700):
    f = ImageFont.truetype(FONT, size)
    try:
        f.set_variation_by_axes([weight])
    except Exception:
        pass
    return f
def wrap(draw, text, f, maxw):
    words, lines, line = text.split(), [], ""
    for w in words:
        t = (line + " " + w).strip()
        if draw.textlength(t, font=f) <= maxw:
            line = t
        else:
            lines.append(line); line = w
    if line: lines.append(line)
    return lines
out, headline, kicker = sys.argv[1], sys.argv[2], sys.argv[3]
img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
d = ImageDraw.Draw(img)
fh, fk = font(58, 700), font(34, 500)
y = 72
for line in wrap(d, headline, fh, W - 140):
    d.text((W / 2, y), line, font=fh, fill=(23, 24, 28, 255), anchor="ma")
    y += 70
d.text((W / 2, y + 6), kicker, font=fk, fill=(138, 143, 152, 255), anchor="ma")
# Wordmark, bottom centre.
fw = font(44, 800)
d.text((W / 2 - 6, H - 108), "glyf", font=fw, fill=(23, 24, 28, 255), anchor="ma")
d.ellipse([(W / 2 + 52, H - 104), (W / 2 + 68, H - 88)], fill=(124, 92, 255, 255))
img.save(out)
print("wrote", out)

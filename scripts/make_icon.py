"""Generate the 1024x1024 app icon into the asset catalog.

Usage: python3 scripts/make_icon.py   (needs Pillow: pip3 install pillow)
Writes SleepDiary/Assets.xcassets/AppIcon.appiconset/icon-1024.png and points
the icon set's Contents.json at it.
"""
import json
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
ICONSET = ROOT / "SleepDiary" / "Assets.xcassets" / "AppIcon.appiconset"
S = 1024


def gradient():
    im = Image.new("RGB", (S, S))
    d = ImageDraw.Draw(im)
    for y in range(S):
        t = y / S
        d.line([(0, y), (S, y)], fill=(int(18 + 20 * t), int(24 + 30 * t), int(64 + 50 * t)))
    return im


img = gradient()
d = ImageDraw.Draw(img)
d.ellipse([250, 220, 700, 670], fill=(250, 226, 150))           # moon
mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).ellipse([380, 160, 840, 620], fill=255)   # crescent cut-out
img.paste(gradient(), (0, 0), mask)
d = ImageDraw.Draw(img)
for x, y, r in [(760, 250, 10), (820, 420, 7), (680, 140, 6), (200, 180, 6)]:
    d.ellipse([x - r, y - r, x + r, y + r], fill=(255, 255, 255))
for i, y in enumerate([760, 830, 900]):                         # diary lines
    d.rounded_rectangle([220, y, 804 - i * 120, y + 30], radius=15, fill=(200, 210, 240))

ICONSET.mkdir(parents=True, exist_ok=True)
img.save(ICONSET / "icon-1024.png")
(ICONSET / "Contents.json").write_text(json.dumps({
    "images": [{"filename": "icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
    "info": {"author": "xcode", "version": 1},
}, indent=2) + "\n")
print("wrote", ICONSET / "icon-1024.png")

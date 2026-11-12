"""Framed Apple Watch images for publit.eu: each watch simulator screenshot inside Apple's
Watch Ultra 3 bezel (same bezel and code as tools/appstore/compose.py), transparent background,
saved as WebP at 600 px height (the iPhone/Pixel screens on the site are about 1300 px tall at 600 px wide).

usage: watch_frames.py <screenshots dir> <bezel root> <out dir>
input:  watch-<screen>.png (English) and watch-<screen>-de.png (German)
output: <out>/web-watch-<screen>.webp (de) and web-watch-<screen>-en.webp
"""
import glob, os, sys
from PIL import Image
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "appstore"))
import compose

src, root, out = sys.argv[1:4]
os.makedirs(out, exist_ok=True)
for f in sorted(glob.glob(os.path.join(src, "watch-*.png"))):
    name = os.path.basename(f)[6:-4]                 # home, home-de
    lang = "de" if name.endswith("-de") else "en"
    screen = name[:-3] if lang == "de" else name
    dev = compose.device(root, "watch", Image.open(f))
    dev = dev.crop(dev.getbbox())
    h = 600
    dev = dev.resize((round(dev.width * h / dev.height), h), Image.LANCZOS)
    stem = f"web-watch-{screen}" + ("" if lang == "de" else "-en")
    dev.save(os.path.join(out, stem + ".webp"), quality=90, method=6)
    print(stem, dev.size)

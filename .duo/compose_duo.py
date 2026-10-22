#!/usr/bin/env python3
"""Compose the iPhone Duo App Store mockups (cover display + unfolded inner display).

usage: compose_duo.py SHOTS_DIR CHROME_DIR OUT_DIR   (FONT env = Noto Sans variable font)
SHOTS_DIR has <lang>/outer-<scene>.png (1398x2034) and <lang>/inner-<scene>.png (2853x2007).
CHROME_DIR holds Apple's chrome from Xcode (iPhone Duo.simdevicetype + phone15.devicechrome PDFs).
"""
import sys, os, io, math, subprocess
from PIL import Image, ImageDraw, ImageFont, ImageFilter
FONT = os.environ.get("FONT", "/data/w/NotoSans-VF.ttf")
def font(size, w):
    f = ImageFont.truetype(FONT, size)
    f.set_variation_by_axes([w, 100]); return f
CAP = {
 "nearby": ("Die Karte im Mittelpunkt.", "Abfahrten und alle Stationen um dich herum, auf einer Karte im Vollbild.",
            "The map, front and centre.", "Departures and every station around you, on a full-screen map."),
 "plan":   ("Alle Wege auf der Karte.", "Verbindungen vergleichen, die gewählte in den Farben ihrer Linien.",
            "Every route on the map.", "Compare connections side by side, the chosen one in the colours of its lines."),
 "route":  ("Jeder Schritt der Route.", "Steige, Umstiege und Verspätungen, mit dem ganzen Weg auf der Karte.",
            "Every step of the route.", "Platforms, changes and delays, with the whole way on the map."),
 "live":   ("Deine Fahrt, live.", "Deine Linie, die Minuten bis zum Ziel und wo du aussteigst. Auch als Live-Aktivität.",
            "Your trip, live.", "Your line, the minutes left and where to get off. Also as a Live Activity."),
 "dark":   ("Für Tag und Nacht.", "Jeder Bildschirm ist hell und dunkel gestaltet und auch um Mitternacht gut lesbar.",
            "For day and night.", "Every screen is designed light and dark, easy to read even at midnight."),
}
ORDER = ["nearby", "plan", "route", "live", "dark"]


def glyph(height, ink):
    """The publit P with the yellow dot (docs/brand/glyph.svg), drawn at 8x and scaled down."""
    S = 8; N = 1024 * S
    im = Image.new("RGBA", (N, N), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    ox, oy = -38, -18
    def P(x, y): return ((x + ox) * S, (y + oy) * S)
    pts = [(400, 790), (400, 420)]
    cx, cy, r = 550, 420, 150   # three-quarter arc, clockwise, from (400,420) over the top to (550,570)
    for i in range(0, 271):
        a = math.radians(180 + i)
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    pts += [(400, 570)]
    w = 96 * S
    for a, b in zip(pts, pts[1:]):
        d.line([P(*a), P(*b)], fill=ink + (255,), width=w)
    for p in pts:
        x, y = P(*p); d.ellipse([x - w/2, y - w/2, x + w/2, y + w/2], fill=ink + (255,))
    x, y = P(550, 420); rr = 58 * S
    d.ellipse([x - rr, y - rr, x + rr, y + rr], fill=(255, 197, 49, 255))
    im = im.crop(im.getbbox())
    return im.resize((max(1, round(im.width * height / im.height)), height), Image.LANCZOS)

def render(pdf, dpi=216):
    out = subprocess.run(["pdftocairo", "-png", "-transp", "-r", str(dpi), "-singlefile", pdf, "-"], capture_output=True, check=True).stdout
    return Image.open(io.BytesIO(out)).convert("RGBA")

def wrap(d, text, f, maxw):
    lines, cur = [], ""
    for word in text.split():
        t = (cur + " " + word).strip()
        if d.textlength(t, font=f) <= maxw: cur = t
        else: lines.append(cur); cur = word
    if cur: lines.append(cur)
    return lines

class Chrome:
    def __init__(self, root):
        res = f"{root}/simdevicetype-resources"
        self.comp = render(f"{root}/phone15.devicechrome/Contents/Resources/PhoneComposite.pdf")   # 1542x2118
        self.mask_outer = render(f"{res}/1C896A2B-F0D7-405C-8D0F-66E4B80AD044.pdf").getchannel("A")  # 1398x2034
        self.mask_inner = render(f"{res}/BF0DC480-5EE2-4EC1-B02B-C75E94759832.pdf").getchannel("A")  # 3:4.26 portrait
    def outer_device(self, shot):
        """Apple's own cover-display chrome from Xcode with the screenshot in its exact screen shape."""
        shot = shot.convert("RGB")
        assert shot.size == self.mask_outer.size, shot.size
        dev = self.comp.copy()
        dev.paste(shot, (78, 42), self.mask_outer)
        return dev
    def inner_device(self, shot, dark):
        """No inner-display chrome ships with Xcode: same metal frame look around Apple's inner screen shape."""
        shot = shot.convert("RGB"); w, h = shot.size
        m = self.mask_inner if h > w else self.mask_inner.rotate(90, expand=True)
        m = m.resize((w, h), Image.LANCZOS)
        bez = 62
        r_screen = int(w * 0.0645)
        fw, fh = w + 2*bez, h + 2*bez
        dev = Image.new("RGBA", (fw, fh), (0, 0, 0, 0)); d = ImageDraw.Draw(dev)
        d.rounded_rectangle([0, 0, fw-1, fh-1], r_screen + bez, fill=(74, 74, 76, 255))           # metal edge
        d.rounded_rectangle([5, 5, fw-6, fh-6], r_screen + bez - 5, fill=(38, 38, 40, 255))       # body
        d.rounded_rectangle([bez-6, bez-6, fw-bez+5, fh-bez+5], r_screen + 6, fill=(0, 0, 0, 255)) # screen edge
        dev.paste(shot, (bez, bez), m)
        return dev

def compose(chrome, src, scene, lang, kind, out):
    """kind: outer (cover display, portrait), innerp (inner display portrait), innerl (inner display landscape)"""
    dark = scene == "dark"
    bg, ink, sub = ((17,17,17), (244,244,242), (161,161,166)) if dark else ((244,244,242), (17,17,17), (102,102,107))
    W, H = {"outer": (1398, 2034), "innerp": (2007, 2853), "innerl": (2853, 2007)}[kind]
    portrait = kind != "innerl"
    k = W / 1398 if portrait else 1.0
    c = Image.new("RGB", (W, H), bg); d = ImageDraw.Draw(c)
    t, s = (CAP[scene][0], CAP[scene][1]) if lang == "de" else (CAP[scene][2], CAP[scene][3])
    if portrait: x0, hs, ss, ws, gs, railx, gy = int(104*k), int(98*k), int(40*k), int(40*k), int(52*k), int(58*k), int(80*k)
    else:        x0, hs, ss, ws, gs, railx, gy = 150, 124, 46, 48, 60, 96, 84
    dot_y = int(262*k) if portrait else 300
    d.line([(railx, 0), (railx, dot_y + (28 if not portrait else int(28*k)))], fill=ink, width=5)
    rd = int(17*k) if portrait else 17
    d.ellipse([railx-rd, dot_y-rd, railx+rd, dot_y+rd], fill=(255,197,49))
    g = glyph(gs, ink)
    c.paste(g, (x0, gy), g)
    d.text((x0 + g.width + int(18*k), gy + gs//2), "publit", font=font(ws, 700), fill=ink, anchor="lm")
    hf, sf = font(hs, 800), font(ss, 450)
    maxw = W - x0 - (int(60*k) if portrait else 150)
    y = (gy + int(110*k)) if portrait else 210
    for ln in wrap(d, t, hf, maxw):
        d.text((x0, y), ln, font=hf, fill=ink); y += int(hs * 1.1)
    y += int(38*k) if portrait else 30
    for ln in wrap(d, s, sf, maxw):
        d.text((x0 + 3, y), ln, font=sf, fill=sub); y += int(ss * 1.42)
    top = y + (int(44*k) if portrait else 60)
    shot = Image.open(src)
    dev = chrome.outer_device(shot) if kind == "outer" else chrome.inner_device(shot, dark)
    margin_x = int(70*k) if portrait else x0
    avail_h = H - top - (int(50*k) if portrait else 40)
    scale = avail_h / dev.height
    if dev.width * scale > W - 2*margin_x: scale = (W - 2*margin_x) / dev.width
    dev = dev.resize((int(dev.width*scale), int(dev.height*scale)), Image.LANCZOS)
    fx, fy = (W - dev.width)//2, top
    sh = Image.new("L", (W, H), 0)
    sh.paste(dev.getchannel("A").point(lambda v: 120 if v > 128 else 0), (fx, fy + 22))
    sh = sh.filter(ImageFilter.GaussianBlur(34))
    c.paste(Image.new("RGB", (W, H), (0, 0, 0)), (0, 0), sh)
    c.paste(dev, (fx, fy), dev)
    c.save(out, optimize=True)

PLAN = [("nearby", "innerl"), ("plan", "innerl"), ("route", "innerp"), ("live", "innerp"), ("dark", "innerp")]
SRCNAME = {"outer": "outer", "innerp": "innerp", "innerl": "inner"}

if __name__ == "__main__":
    shots, chrome_dir, outdir = sys.argv[1:4]
    chrome = Chrome(chrome_dir)
    for lang in ("de", "en"):
        os.makedirs(f"{outdir}/{lang}", exist_ok=True)
        i = 0
        for scene, inner in PLAN:
            for kind in ("outer", inner):
                p = f"{shots}/{lang}/{SRCNAME[kind]}-{scene}.png"
                if not os.path.exists(p): print("missing", p); continue
                i += 1
                compose(chrome, p, scene, lang, kind, f"{outdir}/{lang}/{i:02d}-{scene}-{kind}.png")
    print("ok")

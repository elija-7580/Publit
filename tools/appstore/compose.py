#!/usr/bin/env python3
"""App Store mockups for every device, always inside Apple's real device bezels.

RULE: every mockup shows the screenshot inside Apple's official product bezel PNG
(https://developer.apple.com/design/resources/, "Product Bezels"). No drawn frames.

usage: compose.py RAW_DIR BEZEL_DIR OUT_DIR      (FONT env = Noto Sans variable font)
RAW_DIR layout:  iphone/<lang>/as-*.png  ipad/<lang>/as-*.png  duo/<lang>/{outer,inner,innerp}-*.png  watch/<lang>/*.png
BEZEL_DIR: the PNG folders unpacked from the Bezel-*.dmg downloads (see BEZEL below).
Each bezel's transparent screen opening is found by flood fill and matches the raw screenshot size exactly.
"""
import sys, os, math
from PIL import Image, ImageDraw, ImageFont, ImageFilter
FONT = os.environ.get("FONT", "NotoSans-VF.ttf")
BEZEL = {
 "iphone": "Bezel-iPhone-18/PNG/iPhone 18 Pro Max/iPhone 18 Pro Max - Black - Portrait.png",
 "ipad":   'Bezel-iPad-Pro-(M5)/PNG/iPad Pro (M5) 13" - Space Black - Landscape.png',
 "outer":  "Bezel-iPhone-Duo/PNG/iPhone Duo - Night Sky - Outer Closed Portrait.png",
 "innerp": "Bezel-iPhone-Duo/PNG/iPhone Duo - Night Sky - Inner Open Portrait.png",
 "innerl": "Bezel-iPhone-Duo/PNG/iPhone Duo - Night Sky - Inner Open Landscape.png",
 "watch":  "Bezel-Apple-Watch-Ultra-3-2025/PNG/Ocean Band/AW Ultra 3 - Black + Ocean Band Black.png",
}
CANVAS = {"iphone": (1320, 2868), "ipad": (2752, 2064), "outer": (1398, 2034), "innerp": (2007, 2853),
          "innerl": (2853, 2007), "watch": (422 * 3, 514 * 3)}   # watch drawn at 3x, saved at 422x514
CAP = {  # scene: (de title, de sub, en title, en sub)
 "nearby": ("Abfahrten um dich herum.", "Linie, Steig und Live-Zeiten für jede Haltestelle in der Nähe.",
            "Departures around you.", "Line, platform and live times for every stop nearby."),
 "plan":   ("Alle Wege auf einer Zeitachse.", "Sieh, wer zuerst ankommt, wo du umsteigst und wo es knapp wird.",
            "Every route on one timeline.", "See who arrives first, where you change and where it gets tight."),
 "live":   ("Deine Fahrt, live.", "Deine Linie, die Minuten bis zum Ziel und wo du aussteigst. Auch als Live-Aktivität.",
            "Your trip, live.", "Your line, the minutes left and where to get off. Also as a Live Activity."),
 "route":  ("Jeder Schritt der Route.", "Karte und Schritte in den Farben der Linien, mit Steigen und Verspätungen.",
            "Every step of the route.", "Map and steps in the colours of the lines, with platforms and delays."),
 "map":    ("Cafés, Apotheken, Supermärkte.", "Finde auf der Karte, was in der Nähe ist, und komm mit einem Tipp hin.",
            "Cafés, pharmacies, supermarkets.", "Find what is nearby on the map and get there with one tap."),
 "passes": ("Deine Tickets in der App.", "Aus PDF, Foto oder Screenshot. Gelesen auf dem Gerät, nichts wird hochgeladen.",
            "Your tickets in the app.", "From a PDF, photo or screenshot. Read on the device, nothing is uploaded."),
 "dark":   ("Für Tag und Nacht.", "Jeder Bildschirm ist hell und dunkel gestaltet und auch um Mitternacht gut lesbar.",
            "For day and night.", "Every screen is designed light and dark, easy to read even at midnight."),
 "duomap": ("Die Karte im Mittelpunkt.", "Abfahrten und alle Stationen um dich herum, auf einer Karte im Vollbild.",
            "The map, front and centre.", "Departures and every station around you, on a full-screen map."),
 "duoplan":("Alle Wege auf der Karte.", "Verbindungen vergleichen, die gewählte in den Farben ihrer Linien.",
            "Every route on the map.", "Compare connections side by side, the chosen one in the colours of its lines."),
 "w-home":  ("Dein Ticket zuerst.", "", "Your ticket, first thing.", ""),
 "w-ticket":("Code zeigen am Eingang.", "", "Show the code at the gate.", ""),
 "w-trip":  ("Deine Reise am Handgelenk.", "", "Your trip on your wrist.", ""),
 "w-leg":   ("Jede Fahrt, Schritt für Schritt.", "", "Every ride, step by step.", ""),
 "w-legmap":("Die Karte für jede Fahrt.", "", "The map for every leg.", ""),
 "w-nearby":("Abfahrten in der Nähe.", "", "Departures around you.", ""),
 "w-gap":   ("Warnt, wo Daten fehlen.", "", "Warns where data is missing.", ""),
}
PLANS = {  # device: [(scene, raw file, bezel kind)]
 "iphone": [("nearby", "as-01-nearby"), ("plan", "as-02-plan"), ("live", "as-04-live"), ("route", "as-03-route"),
            ("map", "as-05-map"), ("passes", "as-08-passes"), ("dark", "as-06-dark")],
 "ipad":   [("plan", "as-02-plan"), ("live", "as-04-live"), ("route", "as-03-route"),
            ("passes", "as-08-passes"), ("dark", "as-06-dark")],
 "duo":    [("duomap", "outer-nearby", "outer"), ("duomap", "inner-nearby", "innerl"), ("duoplan", "outer-plan", "outer"),
            ("duoplan", "inner-plan", "innerl"), ("route", "outer-route", "outer"), ("route", "innerp-route", "innerp"),
            ("live", "outer-live", "outer"), ("live", "innerp-live", "innerp"), ("dark", "outer-dark", "outer"),
            ("dark", "innerp-dark", "innerp")],
 "watch":  [("w-home", "home"), ("w-ticket", "ticket"), ("w-trip", "trip"), ("w-leg", "leg"), ("w-legmap", "legmap"),
            ("w-nearby", "nearby"), ("w-gap", "gap")],
}

def font(size, w):
    f = ImageFont.truetype(FONT, size); f.set_variation_by_axes([w, 100]); return f

def glyph(height, ink):
    """The publit P with the yellow dot (docs/brand/glyph.svg)."""
    S = 8; N = 1024 * S
    im = Image.new("RGBA", (N, N), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    def P(x, y): return ((x - 38) * S, (y - 18) * S)
    pts = [(400, 790), (400, 420)] + [(550 + 150 * math.cos(math.radians(180 + i)), 420 + 150 * math.sin(math.radians(180 + i))) for i in range(271)] + [(400, 570)]
    w = 96 * S
    for a, b in zip(pts, pts[1:]): d.line([P(*a), P(*b)], fill=ink + (255,), width=w)
    for p in pts:
        x, y = P(*p); d.ellipse([x - w/2, y - w/2, x + w/2, y + w/2], fill=ink + (255,))
    x, y = P(550, 420); r = 58 * S; d.ellipse([x - r, y - r, x + r, y + r], fill=(255, 197, 49, 255))
    im = im.crop(im.getbbox())
    return im.resize((max(1, round(im.width * height / im.height)), height), Image.LANCZOS)

_dev = {}
def bezel(root, kind):
    if kind not in _dev:
        fr = Image.open(os.path.join(root, BEZEL[kind])).convert("RGBA")
        hole = fr.getchannel("A").point(lambda v: 255 if v < 128 else 0)
        ImageDraw.floodfill(hole, (fr.width // 2, fr.height // 2), 128)
        hole = hole.point(lambda v: 255 if v == 128 else 0)
        _dev[kind] = (fr, hole, hole.getbbox())
    return _dev[kind]

def device(root, kind, shot):
    fr, hole, box = bezel(root, kind)
    w, h = box[2] - box[0], box[3] - box[1]
    shot = shot.convert("RGB")
    if (shot.width > shot.height) != (w > h):   # iPad captures are stored portrait with the landscape UI turned
        shot = shot.rotate(90, expand=True)
    if shot.size != (w, h): shot = shot.resize((w, h), Image.LANCZOS)
    dev = Image.new("RGBA", fr.size, (0, 0, 0, 0))
    dev.paste(shot, box[:2], hole.crop(box))
    return Image.alpha_composite(dev, fr)

def wrap(d, text, f, maxw):
    lines, cur = [], ""
    for word in text.split():
        t = (cur + " " + word).strip()
        if d.textlength(t, font=f) <= maxw: cur = t
        else: lines.append(cur); cur = word
    return lines + ([cur] if cur else [])

def compose(root, src, scene, lang, kind, out):
    dark = scene == "dark"
    bg, ink, sub = ((17, 17, 17), (244, 244, 242), (161, 161, 166)) if dark else ((244, 244, 242), (17, 17, 17), (102, 102, 107))
    W, H = CANVAS[kind]
    land = W > H
    k = (W / 1398) if not land else 1.0
    if kind == "watch": k = W / 1398 * 1.25
    c = Image.new("RGB", (W, H), bg); d = ImageDraw.Draw(c)
    t, s = CAP[scene][0:2] if lang == "de" else CAP[scene][2:4]
    if land: x0, hs, ss, ws, gs, railx, gy, dot_y = 150, 124, 46, 48, 60, 96, 84, 300
    else: x0, hs, ss, ws, gs, railx, gy, dot_y = int(104*k), int(98*k), int(40*k), int(40*k), int(52*k), int(58*k), int(80*k), int(262*k)
    if kind == "watch": gy, dot_y = int(50*k), int(200*k)
    d.line([(railx, 0), (railx, dot_y)], fill=ink, width=max(3, int(5*k)))
    rd = max(8, int(17*k)); d.ellipse([railx-rd, dot_y-rd, railx+rd, dot_y+rd], fill=(255, 197, 49))
    g = glyph(gs, ink); c.paste(g, (x0, gy), g)
    d.text((x0 + g.width + int(18*k), gy + gs//2), "publit", font=font(ws, 700), fill=ink, anchor="lm")
    hf, sf = font(hs, 800), font(ss, 450)
    maxw = W - x0 - (int(60*k) if not land else 150)
    y = (gy + int(110*k)) if not land else 210
    if kind == "watch": y = gy + int(90*k)
    for ln in wrap(d, t, hf, maxw): d.text((x0, y), ln, font=hf, fill=ink); y += int(hs * 1.1)
    if s:
        y += int(38*k) if not land else 30
        for ln in wrap(d, s, sf, maxw): d.text((x0 + 3, y), ln, font=sf, fill=sub); y += int(ss * 1.42)
    top = y + (int(44*k) if not land else 60)
    dev = device(root, kind, Image.open(src))
    if kind == "watch":
        # The band runs off the canvas; the screen and case sit fully in view under the caption.
        fr, hole, box = bezel(root, kind)
        dev = dev.crop((0, box[1] - 150, dev.width, dev.height))
        scale = (H - top - 40) / (box[3] - box[1] + 150 + 30)
        dev = dev.resize((int(dev.width*scale), int(dev.height*scale)), Image.LANCZOS)
        fx, fy = (W - dev.width)//2, top
        fade = int(110*scale)   # band fades into the background at the top edge
        a = dev.getchannel("A")
        grad = Image.linear_gradient("L").resize((dev.width, fade))
        a.paste(Image.composite(a.crop((0, 0, dev.width, fade)), Image.new("L", (dev.width, fade), 0), grad), (0, 0))
        dev.putalpha(a)
    else:
        mx = int(70*k) if not land else x0
        scale = (H - top - (int(50*k) if not land else 40)) / dev.height
        if dev.width * scale > W - 2*mx: scale = (W - 2*mx) / dev.width
        dev = dev.resize((int(dev.width*scale), int(dev.height*scale)), Image.LANCZOS)
        fx, fy = (W - dev.width)//2, top
    sh = Image.new("L", (W, H), 0)
    sh.paste(dev.getchannel("A").point(lambda v: 110 if v > 128 else 0), (fx, fy + int(22*k)))
    sh = sh.filter(ImageFilter.GaussianBlur(max(6, int(34*k))))
    c.paste(Image.new("RGB", (W, H), (0, 0, 0)), (0, 0), sh)
    c.paste(dev, (fx, fy), dev)
    if kind == "watch": c = c.resize((422, 514), Image.LANCZOS)
    c.save(out, optimize=True)

if __name__ == "__main__":
    raw, root, outdir = sys.argv[1:4]
    only = sys.argv[4:] or list(PLANS)
    for dev in only:
        for lang in ("en", "de"):
            od = f"{outdir}/{dev}/{lang}"; os.makedirs(od, exist_ok=True)
            for i, item in enumerate(PLANS[dev], 1):
                scene, name = item[0], item[1]
                kind = item[2] if len(item) > 2 else dev
                p = f"{raw}/{dev}/{lang}/{name}.png"
                if not os.path.exists(p) and dev == "watch": p = f"{raw}/{dev}/en/{name}.png"  # watch shots are English only
                if not os.path.exists(p): print("missing", p); continue
                compose(root, p, scene, lang, kind, f"{od}/{i:02d}-{scene}-{kind}.png")
    print("ok")

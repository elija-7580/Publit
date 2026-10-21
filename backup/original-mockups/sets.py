import sys, os
from compose import *
GLYPH = "/data/w/as/glyph.png"
PH = {
 "as-01-nearby": ("Abfahrten\num dich herum.", "Linie, Steig und Live-Zeiten für jede\nHaltestelle in der Nähe.",
                  "Departures\naround you.", "Line, platform and live times\nfor every stop nearby."),
 "as-02-plan":   ("Alle Wege auf\neiner Zeitachse.", "Sieh sofort, wer früher ankommt, wo du\numsteigst und wo es knapp wird.",
                  "Every route on\none timeline.", "See who arrives first, where you change\nand where it gets tight."),
 "as-04-live":   ("Deine Fahrt,\nlive.", "Deine Linie, die Minuten bis zum Ziel und\nwo du aussteigst. Auch als Live-Aktivität.",
                  "Your trip,\nlive.", "Your line, the minutes left and where to\nget off. Also as a Live Activity."),
 "as-03-route":  ("Jeder Schritt\nder Route.", "Mit Steig, Haltestellen und Verspätungen.\nIn den Kalender legen oder teilen.",
                  "Every step\nof the route.", "Platforms, stops and delays.\nAdd it to your calendar or share it."),
 "as-05-map":    ("Cafés, Apotheken,\nSupermärkte.", "Finde, was in der Nähe ist,\nund fahr mit einem Tipp hin.",
                  "Cafés, pharmacies,\nsupermarkets.", "Find what is nearby on the map\nand get there with one tap."),
 "as-08-passes": ("Deine Tickets\nin der App.", "Aus PDF, Foto oder Screenshot. Auf dem\niPhone ausgelesen, nichts wird hochgeladen.",
                  "Your tickets\nin the app.", "From a PDF, photo or screenshot. Read on\nyour iPhone, nothing is uploaded."),
 "as-06-dark":   ("Für Tag\nund Nacht.", "Jeder Bildschirm ist hell und dunkel gestaltet\nund auch um Mitternacht gut lesbar.",
                  "For day\nand night.", "Every screen is designed light and dark,\neasy to read even at midnight."),
}
PH_ORDER = ["as-01-nearby", "as-02-plan", "as-04-live", "as-03-route", "as-05-map", "as-08-passes", "as-06-dark"]
PAD_ORDER = ["as-01-nearby", "as-02-plan", "as-03-route", "as-04-live", "as-05-map", "as-08-passes", "as-06-dark"]
from importlib import util
spec = util.spec_from_file_location("ci", "/data/w/as/compose_ipad.py"); ci = util.module_from_spec(spec)
src = open("/data/w/as/compose_ipad.py").read().split('if __name__')[0]; exec(compile(src, "ci", "exec"), ci.__dict__)
PAD = ci.CAP
def colors(dark):
    return ((17,17,17), (244,244,242), (161,161,166)) if dark else ((244,244,242), (17,17,17), (102,102,107))
def brand(c, d, ink, dark, x0, rail_x, rail_h, gs, gy, fs):
    d.line([(rail_x, 0), (rail_x, rail_h)], fill=ink, width=max(4, gs//14))
    r = gs//4; d.ellipse([rail_x-r, rail_h-r, rail_x+r, rail_h+r], fill=(255,197,49))
    g = Image.open(GLYPH).convert("RGBA").resize((gs, gs))
    if dark: a = g.split()[3]; g = Image.new("RGBA", g.size, ink+(255,)); g.putalpha(a)
    c.paste(g, (x0-gs//5, gy), g)
    d.text((x0+gs*3//4, gy+gs//8), "publit", font=font(fs, 700), fill=ink)
def iphone(src, name, lang, out):
    dark = name == "as-06-dark"; bg, ink, sub = colors(dark)
    W, H = 1320, 2868
    c = Image.new("RGB", (W, H), bg); d = ImageDraw.Draw(c)
    t, s = (PH[name][0], PH[name][1]) if lang == "de" else (PH[name][2], PH[name][3])
    if lang == "en": s = s.replace("iPhone", "iPhone")
    x0 = 120
    brand(c, d, ink, dark, x0, 66, 470, 64, 150, 44)
    d.multiline_text((x0, 270), t, font=font(116, 800), fill=ink, spacing=6)
    d.multiline_text((x0+3, 560), s, font=font(42, 450), fill=sub, spacing=14)
    dev, sil = device(src, "iphone-dark" if dark else "iphone")
    w = 1100; put(c, dev, sil, (W-w)//2, 760, w)
    c.save(out, optimize=True)
def ipad(src, name, lang, out):
    dark = name == "as-06-dark"; bg, ink, sub = colors(dark)
    W, H = 2752, 2064
    c = Image.new("RGB", (W, H), bg); d = ImageDraw.Draw(c)
    t, s = (PAD[name][0], PAD[name][1]) if lang == "de" else (PAD[name][2], PAD[name][3])
    x0 = 170
    brand(c, d, ink, dark, x0, 96, 330, 72, 90, 48)
    d.text((x0, 200), t, font=font(124, 800), fill=ink)
    d.text((x0+4, 370), s, font=font(46, 450), fill=sub)
    dev, sil = device(src, "ipad")
    w = 2150; put(c, dev, sil, (W-w)//2, 520, w)
    c.save(out, optimize=True)
if __name__ == "__main__":
    A, O = sys.argv[1], sys.argv[2]
    for kind, sub, order, fn in [("iphone", "iPhone-17-Pro-Max", PH_ORDER, iphone), ("ipad", "iPad-Pro-13-inch-M5", PAD_ORDER, ipad)]:
        for lang in ("en", "de"):
            os.makedirs(f"{O}/{kind}/{lang}", exist_ok=True); i = 0
            for n in order:
                p = f"{A}/{sub}/{lang}/{n}.png"
                if not os.path.exists(p): print("missing", kind, lang, n); continue
                i += 1; fn(p, n, lang, f"{O}/{kind}/{lang}/{i:02d}-{n[3:]}.png")
    print("ok")

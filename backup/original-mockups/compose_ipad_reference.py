import sys, os, json
from PIL import Image, ImageDraw, ImageFont, ImageFilter
FONT = "/usr/share/fonts/google-noto-vf/NotoSans[wght].ttf"
def font(size, w):
    f = ImageFont.truetype(FONT, size); f.set_variation_by_axes([w]); return f
W, H = 2752, 2064
ROT = int(os.environ.get("ROT", "90"))
CAP = {
 "as-01-nearby": ("Die Karte im Mittelpunkt.", "Abfahrten und alle Stationen um dich herum, auf einer Karte im Vollbild.",
                  "The map, front and centre.", "Departures and every station around you, on a full-screen map."),
 "as-02-plan":   ("Alle Wege auf der Karte.", "Verbindungen vergleichen, die gewählte in den Farben ihrer Linien.",
                  "Every route on the map.", "Compare connections side by side, the chosen one in the colours of its lines."),
 "as-03-route":  ("Jeder Schritt der Route.", "Steige, Umstiege und Verspätungen, mit dem ganzen Weg auf der Karte.",
                  "Every step of the route.", "Platforms, changes and delays, with the whole way on the map."),
 "as-04-live":   ("Deine Fahrt, live.", "Deine Linie, die Minuten bis zum Ziel und wo du aussteigst. Auch als Live-Aktivität.",
                  "Your trip, live.", "Your line, the minutes left and where to get off. Also as a Live Activity."),
 "as-05-map":    ("Cafés, Apotheken, Supermärkte.", "Finde, was in der Nähe ist, und fahr mit einem Tipp hin.",
                  "Cafés, pharmacies, supermarkets.", "Find what is nearby and get there with one tap."),
 "as-08-passes": ("Deine Tickets in der App.", "Aus PDF, Foto oder Screenshot. Auf dem iPad ausgelesen, nichts wird hochgeladen.",
                  "Your tickets in the app.", "From a PDF, photo or screenshot. Read on your iPad, nothing is uploaded."),
 "as-06-dark":   ("Für Tag und Nacht.", "Jeder Bildschirm ist hell und dunkel gestaltet und auch um Mitternacht gut lesbar.",
                  "For day and night.", "Every screen is designed light and dark, easy to read even at midnight."),
}
ORDER = ["as-01-nearby", "as-02-plan", "as-03-route", "as-04-live", "as-05-map", "as-08-passes", "as-06-dark"]
def compose(src, name, lang, out):
    dark = name == "as-06-dark"
    bg, ink, sub = ((17,17,17), (244,244,242), (161,161,166)) if dark else ((244,244,242), (17,17,17), (102,102,107))
    c = Image.new("RGB", (W, H), bg); d = ImageDraw.Draw(c)
    t, s = (CAP[name][0], CAP[name][1]) if lang == "de" else (CAP[name][2], CAP[name][3])
    x0 = 150
    # rail + dot like the iPhone set
    d.line([(96, 0), (96, 330)], fill=ink, width=5)
    d.ellipse([96-17, 300-17, 96+17, 300+17], fill=(255,197,49))
    g = Image.open("glyph.png").convert("RGBA").resize((72, 72))
    if dark:
        a = g.split()[3]; g = Image.new("RGBA", g.size, ink + (255,)); g.putalpha(a)
        # keep the yellow dot visible
    c.paste(g, (x0-14, 88), g)
    d.text((x0+56, 96), "publit", font=font(48, 700), fill=ink)
    d.text((x0, 210), t, font=font(124, 800), fill=ink)
    d.text((x0+4, 380), s, font=font(46, 450), fill=sub)
    # device
    shot = Image.open(src).convert("RGB")
    sw, sh = shot.size
    if sw < sh: shot = shot.rotate(ROT, expand=True); sw, sh = shot.size
    top = 500; bez = 34
    dh = H - top - 40
    scale = (dh - 2*bez) / sh
    if (sw*scale + 2*bez) > W - 2*x0: scale = (W - 2*x0 - 2*bez) / sw
    shot = shot.resize((int(sw*scale), int(sh*scale)), Image.LANCZOS)
    fw, fh = shot.width + 2*bez, shot.height + 2*bez
    fx, fy = (W - fw)//2, top
    sh_ = Image.new("L", (W, H), 0); ImageDraw.Draw(sh_).rounded_rectangle([fx, fy+24, fx+fw, fy+fh+24], 90, fill=110)
    sh_ = sh_.filter(ImageFilter.GaussianBlur(40))
    c.paste(Image.new("RGB", (W, H), (0,0,0)), (0,0), sh_)
    d = ImageDraw.Draw(c)
    d.rounded_rectangle([fx, fy, fx+fw, fy+fh], 90, fill=(20,20,22) if not dark else (58,58,62))
    m = Image.new("L", shot.size, 0); ImageDraw.Draw(m).rounded_rectangle([0,0,shot.width-1,shot.height-1], 58, fill=255)
    c.paste(shot, (fx+bez, fy+bez), m)
    c.save(out, optimize=True)

if __name__ == "__main__":
    srcdir, outdir = sys.argv[1], sys.argv[2]
    for lang in ("en", "de"):
        os.makedirs(f"{outdir}/{lang}", exist_ok=True)
        i = 0
        for n in ORDER:
            p = f"{srcdir}/{lang}/{n}.png"
            if not os.path.exists(p): print("missing", p); continue
            i += 1
            compose(p, n, lang, f"{outdir}/{lang}/{lang}-{i}-{n[6:] if False else n[3:]}.png")
    print("ok")

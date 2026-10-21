import sys
from compose import *
A = sys.argv[1]; O = sys.argv[2]
W, H = 5244, 2950
for lang, t1, t2, sub in [("en", "Public transport,", "without the noise.", "Free. No ads.\nNo account. No tracking."),
                          ("de", "Öffis ohne", "Schnickschnack.", "Kostenlos. Ohne Werbung.\nOhne Konto. Ohne Tracking.")]:
    c = Image.new("RGB", (W, H), (244,244,242)); d = ImageDraw.Draw(c)
    x0 = 620
    d.line([(x0-110, 0), (x0-110, 1150)], fill=(17,17,17), width=10)
    d.ellipse([x0-110-34, 1100-34, x0-110+34, 1100+34], fill=(255,197,49))
    g = Image.open("/data/w/as/glyph2.png").convert("RGBA").resize((180,180)); c.paste(g, (x0, 720), g)
    d.text((x0+220, 755), "publit", font=font(100, 700), fill=(17,17,17))
    d.text((x0, 1010), t1, font=font(172, 800), fill=(17,17,17))
    d.text((x0, 1215), t2, font=font(172, 800), fill=(17,17,17))
    d.multiline_text((x0+6, 1480), sub, font=font(74, 450), fill=(102,102,107), spacing=30)
    dev, sil = device(f"{A}/iPad-Pro-13-inch-M5/{lang}/as-01-nearby.png", "ipad")
    put(c, dev, sil, 2900, 560, 2150)
    dev, sil = device(f"{A}/iPhone-17-Pro-Max/{lang}/as-03-route.png", "iphone")
    put(c, dev, sil, 2480, 820, 820)
    c.save(f"{O}/header-{lang}.png", optimize=True)
    c.resize((1400, 788)).save(f"{O}/header-{lang}-s.png")
print("ok")

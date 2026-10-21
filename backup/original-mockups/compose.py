import sys, os
from PIL import Image, ImageDraw, ImageFont, ImageFilter
sys.path.insert(0, "/data/w/as")
FONT = "/usr/share/fonts/google-noto-vf/NotoSans[wght].ttf"
def font(s, w):
    f = ImageFont.truetype(FONT, s); f.set_variation_by_axes([w]); return f
BZ = "/data/w/bz"
FR = {
 "iphone": f"{BZ}/x-iphone/Bezel-iPhone-17/PNG/iPhone 17 Pro Max/iPhone 17 Pro Max - Silver - Portrait.png",
 "iphone-dark": f"{BZ}/x-iphone/Bezel-iPhone-17/PNG/iPhone 17 Pro Max/iPhone 17 Pro Max - Deep Blue - Portrait.png",
 "ipad": f"{BZ}/x-ipad/Bezel-iPad-Pro-(M5)/PNG/iPad Pro (M5) 13\" - Space Black - Landscape.png",
}
_cache = {}
def frame(kind):
    if kind in _cache: return _cache[kind]
    b = Image.open(FR[kind]).convert("RGBA"); w, h = b.size
    a = b.split()[3]
    # screen = transparent region connected to centre
    m = a.point(lambda v: 255 if v < 250 else 0)
    ImageDraw.floodfill(m, (w//2, h//2), 128)
    scr = m.point(lambda v: 255 if v == 128 else 0)
    box = scr.getbbox()
    # device silhouette = everything not transparent-outside: screen + opaque
    sil = Image.eval(a, lambda v: 255 if v > 0 else 0); sil.paste(255, (0,0), scr)
    _cache[kind] = (b, scr, box, sil); return _cache[kind]
def device(shot_path, kind, rot=90):
    b, scr, box, sil = frame(kind)
    s = Image.open(shot_path).convert("RGB")
    bw, bh = box[2]-box[0], box[3]-box[1]
    if (s.width > s.height) != (bw > bh): s = s.rotate(rot, expand=True)
    s = s.resize((bw, bh), Image.LANCZOS)
    out = Image.new("RGBA", b.size, (0,0,0,0))
    layer = Image.new("RGBA", b.size, (0,0,0,0)); layer.paste(s, box[:2])
    out.paste(layer, (0,0), scr)
    out = Image.alpha_composite(out, b)
    return out, sil
def put(c, dev, sil, x, y, w, shadow=True):
    h = int(dev.height * w / dev.width)
    dev = dev.resize((w, h), Image.LANCZOS); sil = sil.resize((w, h), Image.LANCZOS)
    if shadow:
        sh = Image.new("L", c.size, 0); sh.paste(sil.point(lambda v: v*45//100), (x, y + w//40))
        sh = sh.filter(ImageFilter.GaussianBlur(w//30))
        c.paste((0,0,0), (0,0), sh)
    c.paste(dev, (x, y), dev)
    return w, h

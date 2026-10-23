#!/usr/bin/env python3
"""Builds Sources/Models/CoverageAtlasData.swift: where open timetable data is missing.

The app asks this atlas (offline, nothing leaves the phone) whether a place lies in an area
where Transitous has no or only partial timetable data, and says so before anyone relies on a
connection there. The source is the coverage map on https://publit.eu/abdeckung/ (repository
elija-7580/publit-site, folder abdeckung/data, refreshed monthly) plus a short hand-checked list.

    pip install numpy shapely
    python3 tools/coverage/make_atlas.py --site ../publit-site/abdeckung/data \
        --places pp.geojson            # Natural Earth ne_10m_populated_places_simple.geojson

Without --places the file is downloaded from Natural Earth. Run it after the monthly update of
the website data and commit the result; `docs/COVERAGE.md` explains the rules.

Rules (all numbers are constants below):
  none    region of the map without a single stop (category "n"); a whole country with at most 5 stops
  sparse  a whole country with fewer than TINY_COUNTRY_STOPS stops (Malta, Armenia, Belarus, Kosovo …)
  sparse  region with fewer than SPARSE_STOPS stops and a town of at least SPARSE_TOWN people
          (category "v": under 5 % of the area is near a stop)
  sparse  town (>= THIN_POP people) with at most THIN_STOPS stops within 3 km of its centre,
          in a country where at least THIN_SHARE of such towns look like that (stations only)
  partial hand-checked: which kind of service is missing (Carinthia, Istanbul, Kyiv, Pristina, Madrid)
"""
import argparse, glob, json, math, os, re, sys, unicodedata, urllib.request
import numpy as np
from collections import defaultdict
from shapely.geometry import Polygon, Point
from shapely.ops import unary_union
from shapely.strtree import STRtree

# Projection of the coverage map (same constants as publit-site/tools/coverage/build.py).
K = 0.6156614753256583; SX = 22.87703162651752; Y1 = 1.81486224426954; S = K * SX

TINY_COUNTRY_STOPS = 100  # a country with fewer stops than this (and under half of it near a stop) is flagged as a whole
SPARSE_STOPS = 100      # a region with fewer stops than this is "very little data" ...
SPARSE_TOWN = 20000     # ... if it contains a town with at least this many people
THIN_POP = 30000        # towns checked for a thin network
THIN_STOPS = 15         # at most this many stops within 3 km of the centre
THIN_SHARE = 0.2        # country counts only if this share of its towns is thin
MIN_AREA = 0.002        # square degrees; smaller regions (Vatican) are skipped
NE_PLACES = 'https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_10m_populated_places_simple.geojson'

# Hand-checked areas. gaps: L local and regional buses, C city buses, M metro, T trams,
# F ferries, S suburban trains.  Checked against api.transitous.org (/api/v1/map/stops) and
# docs/COVERAGE.md in October 2026.
CURATED = [
    dict(id='at-carinthia', region=('at', 'Carinthia'), gaps='L', en='Carinthia', de='Kärnten'),
    dict(id='es-madrid', iso='es', circle=(40.42, -3.70, 22000), gaps='MC', en='Madrid', de='Madrid'),
    dict(id='tr-istanbul', iso='tr', circle=(41.01, 28.98, 45000), gaps='MTFS', en='Istanbul', de='Istanbul'),
    dict(id='ua-kyiv', iso='ua', circle=(50.45, 30.52, 30000), gaps='MTS', en='Kyiv', de='Kiew'),
    dict(id='xk-pristina', iso='xk', circle=(42.66, 21.17, 15000), gaps='C', en='Pristina', de='Pristina'),
]
# Natural Earth spells a few towns oddly.
TOWN_NAMES = {
    'Alba Lulia': 'Alba Iulia', 'Turnovo': 'Veliko Tarnovo', 'Khaskovo': 'Haskovo', 'Lovec': 'Lovech',
    'Sfintu-Gheorghe': 'Sfântu Gheorghe', 'Tirgu Mures': 'Târgu Mureș', 'Rimnicu Vilcea': 'Râmnicu Vâlcea',
    'Piatra-Neamt': 'Piatra Neamț', 'Miercurea Cuic': 'Miercurea Ciuc', 'Komatini': 'Komotini',
    'Hania': 'Chania', 'Mahilyow': 'Mogilev', 'Homyel': 'Gomel', 'Hrodna': 'Grodno', 'Vitsyebsk': 'Vitebsk',
    'Mykolayiv': 'Mykolaiv', 'Khmelnytskyy': 'Khmelnytskyi', 'Vinnytsya': 'Vinnytsia', 'Zaporizhzhya': 'Zaporizhzhia',
    'Kryvyy Rih': 'Kryvyi Rih', 'Kamyanets-Podilskyy': 'Kamianets-Podilskyi', 'Drohobych': 'Drohobych',
    'St.  Petersburg': 'Saint Petersburg', 'Archangel': 'Arkhangelsk', 'Icel': 'Mersin', 'Ṭarābulus': 'Tripoli',
}

ALPH = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_'
AIDX = {c: i for i, c in enumerate(ALPH)}


def unproj(x, y):
    lon = x / S - SX
    lat = (2 * math.atan(math.exp(Y1 - y * math.pi / (180 * S))) - math.pi / 2) * 180 / math.pi
    return lon, lat


def region_geom(d, scale):
    geom = None
    for part in d.split('z'):
        part = part.strip()
        m = re.match(r'M(-?\d+) (-?\d+)l?(.*)$', part)
        if not m:
            continue
        x, y = int(m.group(1)), int(m.group(2))
        nums = [int(v) for v in m.group(3).split()] if m.group(3).strip() else []
        pts = [(x, y)]
        for i in range(0, len(nums) - 1, 2):
            x += nums[i]; y += nums[i + 1]
            pts.append((x, y))
        ring = [unproj(px / scale, py / scale) for px, py in pts]
        if len(ring) < 3:
            continue
        pg = Polygon(ring)
        if not pg.is_valid:
            pg = pg.buffer(0)
        if pg.is_empty:
            continue
        geom = pg if geom is None else geom.symmetric_difference(pg)
    return geom


def load_regions(site):
    out = []
    for f in sorted(glob.glob(os.path.join(site, '??.json'))):
        d = json.load(open(f))
        for r in d.get('regions', []):
            g = region_geom(r['d'], d['scale'])
            if g is None or g.is_empty:
                continue
            out.append(dict(iso=d['iso'], id=r['id'], en=r['en'], de=r['de'], cat=r['cat'], stops=r['stops'], geom=g))
    return out


def vdec(s):
    vals, prev, d, sh = [], -1, 0, 0
    for ch in s:
        v = AIDX[ch]
        if v >= 32:
            d |= (v & 31) << sh; sh += 5
        else:
            d |= v << sh
            prev = prev + d + 1
            vals.append(prev); d = 0; sh = 0
    return vals


def load_stops(site):
    pts = []
    for f in glob.glob(os.path.join(site, 't', '*.txt')):
        tx, ty = [int(v) for v in os.path.basename(f)[:-4].split('_')]
        for line in open(f).read().split('\n')[:2]:
            for c in vdec(line):
                iy, ix = divmod(c, 2000)
                pts.append(((ty * 2000 + iy) / 1000.0, (tx * 2000 + ix) / 1000.0))
    return np.array(pts)


def stops_within(grid, arr, lat, lon, km=3.0, cell=0.05):
    r = int(math.ceil(km / (cell * 111)))
    cy, cx = int(math.floor(lat / cell)), int(math.floor(lon / cell))
    n = 0
    for dy in range(-r, r + 1):
        for dx in range(-2 * r, 2 * r + 1):
            for i in grid.get((cy + dy, cx + dx), ()):
                p = arr[i]
                if math.hypot((p[0] - lat) * 111.2, (p[1] - lon) * 111.2 * math.cos(math.radians(lat))) <= km:
                    n += 1
    return n


# ---- encoding -------------------------------------------------------------------------
def venc(v):
    z = (v << 1) if v >= 0 else ((-v) << 1) - 1
    out = []
    while True:
        g = z & 31; z >>= 5
        if z:
            out.append(ALPH[g | 32])
        else:
            out.append(ALPH[g]); break
    return ''.join(out)


def enc_ring(coords):
    pts = [(round(la * 1000), round(lo * 1000)) for lo, la in coords]
    if pts[0] == pts[-1]:
        pts = pts[:-1]
    dedup = [pts[0]]
    for p in pts[1:]:
        if p != dedup[-1]:
            dedup.append(p)
    if len(dedup) < 3:
        return None
    s, la0, lo0 = [], 0, 0
    for la, lo in dedup:
        s.append(venc(la - la0) + venc(lo - lo0)); la0, lo0 = la, lo
    return ''.join(s), len(dedup)


def enc_geom(g):
    polys = list(g.geoms) if hasattr(g, 'geoms') else [g]
    rings, count = [], 0
    for p in polys:
        if p.is_empty or p.area < MIN_AREA / 4:
            continue
        for ring in [p.exterior] + list(p.interiors):
            e = enc_ring(list(ring.coords))
            if e:
                rings.append(e[0]); count += e[1]
    return '/'.join(rings), count


def simplify(g):
    area = g.area
    if area < 1:
        # Small countries and islands (Malta, San Marino): the map's outline is coarse, so widen it a little
        # (about 1.5 km) rather than miss a harbour town.
        g = g.buffer(0.015)
    tol = 0.005 if area < 1 else 0.02 if area < 5 else 0.05 if area < 60 else 0.1
    s = g.simplify(tol, preserve_topology=True)
    return s if s.is_valid else s.buffer(0)


def clean(s):
    assert '|' not in s and '"' not in s and '\\' not in s, s
    return s


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--site', default='../publit-site/abdeckung/data')
    ap.add_argument('--places', default=None)
    ap.add_argument('--out', default='Sources/Models/CoverageAtlasData.swift')
    ap.add_argument('--report', action='store_true', help='print what was flagged')
    a = ap.parse_args()

    eu = json.load(open(os.path.join(a.site, 'europe.json')))
    regs = load_regions(a.site)
    if a.places and os.path.exists(a.places):
        places_raw = json.load(open(a.places))['features']
    else:
        print('downloading', NE_PLACES, file=sys.stderr)
        places_raw = json.load(urllib.request.urlopen(NE_PLACES))['features']
    towns = []
    for f in places_raw:
        p = f['properties']; la, lo = p['latitude'], p['longitude']
        if -25 < lo < 45.5 and 34 < la < 71.5 and p['pop_max'] >= 10000:
            towns.append((p['name'], la, lo, p['pop_max']))
    tree = STRtree([r['geom'] for r in regs])
    town_region = {}
    for i, (n, la, lo, pop) in enumerate(towns):
        hit = tree.query(Point(lo, la), predicate='within')
        town_region[i] = int(hit[0]) if len(hit) else None

    names = {c['iso']: (c['en'], c['de']) for c in eu['countries']}
    lines, report = [], []

    # 1. hand-checked areas
    for c in CURATED:
        if 'region' in c:
            iso, rid = c['region']
            r = next(r for r in regs if r['iso'] == iso and r['en'] == rid)
            enc, nv = enc_geom(simplify(r['geom']))
            shape = 'p' + enc
        else:
            la, lo, rad = c['circle']
            shape, nv = 'c%d,%d,%d' % (round(la * 1000), round(lo * 1000), rad), 1
        link = '%s/%s' % (c['region'][0], next(r for r in regs if r['iso'] == c['region'][0] and r['en'] == c['region'][1])['id']) if 'region' in c else c['iso']
        lines.append('|'.join(['A', c['id'], 'p', c['gaps'], clean(c['en']), clean(c['de']), clean(link), shape]))
        report.append(('partial', c['id'], nv))

    # 2. towns with a thin network (stations only)
    arr = load_stops(a.site)
    cell = 0.05
    grid = defaultdict(list)
    for i, (la, lo) in enumerate(arr):
        grid[(int(math.floor(la / cell)), int(math.floor(lo / cell)))].append(i)
    counts = {}
    tot, thin = defaultdict(int), defaultdict(int)
    for i, (n, la, lo, pop) in enumerate(towns):
        if pop < THIN_POP or town_region[i] is None:
            continue
        iso = regs[town_region[i]]['iso']
        counts[i] = stops_within(grid, arr, la, lo)
        tot[iso] += 1
        if counts[i] <= THIN_STOPS:
            thin[iso] += 1
    systemic = {iso for iso in tot if thin[iso] >= 3 and thin[iso] / tot[iso] >= THIN_SHARE}

    # 3. regions
    flagged = {'n': defaultdict(list), 's': defaultdict(list)}
    town_by_region = defaultdict(list)
    for i, (n, la, lo, pop) in enumerate(towns):
        if town_region[i] is not None:
            town_by_region[town_region[i]].append(pop)
    for idx, r in enumerate(regs):
        if r['geom'].area < MIN_AREA:
            continue
        if r['cat'] == 'n':
            flagged['n'][r['iso']].append(r)
        elif r['cat'] == 'v' and r['stops'] < SPARSE_STOPS and max(town_by_region.get(idx, [0])) >= SPARSE_TOWN:
            flagged['s'][r['iso']].append(r)

    # A country with next to no stops is flagged as a whole (the region polygons of Malta or
    # Azerbaijan are too small to catch a town).
    whole = {}
    for c in eu['countries']:
        if c.get('stops') is not None and c['stops'] < TINY_COUNTRY_STOPS and (c.get('area') or 0) < 0.5:
            whole[c['iso']] = 'n' if c['stops'] <= 5 else 's'
    for iso, lvl in whole.items():
        for l in ('n', 's'):
            flagged[l].pop(iso, None)
        flagged[lvl][iso] = [r for r in regs if r['iso'] == iso]

    region_union = {}
    for lvl in ('n', 's'):
        for iso, rs in sorted(flagged[lvl].items()):
            u = unary_union([r['geom'] for r in rs])
            region_union[(lvl, iso)] = u

    # towns: circle for each thin town of a systemic country, unless already in a flagged region
    allflag = unary_union(list(region_union.values()))
    thin_towns = []
    for i, cnt in counts.items():
        n, la, lo, pop = towns[i]
        iso = regs[town_region[i]]['iso']
        if cnt > THIN_STOPS or iso not in systemic:
            continue
        if allflag.contains(Point(lo, la)):
            continue
        if any('circle' in c and math.hypot((c['circle'][0] - la) * 111.2, (c['circle'][1] - lo) * 111.2 * math.cos(math.radians(la))) < c['circle'][2] / 1000 for c in CURATED):
            continue
        rad = 4000 if pop < 80000 else 5000 if pop < 150000 else 7000 if pop < 400000 else 10000
        thin_towns.append((pop, TOWN_NAMES.get(n, n), la, lo, rad, cnt, iso))
    thin_towns.sort(reverse=True)
    for pop, n, la, lo, rad, cnt, iso in thin_towns:
        lines.append('|'.join(['A', 'town-%s-%s' % (iso, re.sub(r'[^a-z]', '', unicodedata.normalize('NFKD', n.lower()).encode('ascii', 'ignore').decode())), 's', '', clean(n), clean(n), iso,
                               'c%d,%d,%d' % (round(la * 1000), round(lo * 1000), rad)]))
        report.append(('town', '%s %s pop %d, %d stops' % (iso, n, pop, cnt), 1))

    for lvl, letter in (('n', 'n'), ('s', 's')):
        for (l2, iso), u in sorted(region_union.items()):
            if l2 != lvl:
                continue
            shape, nv = enc_geom(simplify(u))
            if not shape:
                continue
            en, de = names.get(iso, (iso.upper(), iso.upper()))
            lines.append('|'.join(['A', '%s-%s' % (iso, 'none' if lvl == 'n' else 'sparse'), letter, '', clean(en), clean(de), iso, 'p' + shape]))
            report.append(('none' if lvl == 'n' else 'sparse', iso + ' ' + ', '.join(sorted(r['en'] for r in flagged[lvl][iso]))[:160], nv))

    payload = '\n'.join(lines)
    swift = '''// Generated by tools/coverage/make_atlas.py from the coverage map data (https://publit.eu/abdeckung/). Do not edit by hand.
// One area per line: A|id|level (n none, s sparse, p partial)|gaps|name en|name de|map link (country or country/region)|shape
// shape: c<lat*1000>,<lon*1000>,<radius m> or p<ring>/<ring>... (zigzag varint deltas in 1/1000 degree, even-odd rule)

enum CoverageAtlasData {
    static let date = "%s"
    static let payload = """
%s
"""
}
''' % (eu['date'], payload)
    open(a.out, 'w').write(swift)
    total_v = sum(r[2] for r in report)
    print('areas', len(lines), 'vertices', total_v, 'bytes', len(payload), 'systemic thin countries', sorted(systemic), file=sys.stderr)
    if a.report:
        for r in report:
            print(r)


if __name__ == '__main__':
    main()

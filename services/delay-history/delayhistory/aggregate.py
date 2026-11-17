"""Nightly: raw events → one compact table per region, gzip, published like the coverage atlas.

File format (one line per row, `|`-separated, delays in seconds, quantiles 5/20/50/80/95):

    D|<date built>|<days of history>|<first day>
    S|<routeId>|<stopId>|<win>|<arrival q>|<departure q>|<cancel ‰>|<n>   route at one stop
    R|<routeId>|<win>|<arrival q>|<departure q>|<cancel ‰>|<n>            route
    O|<feed>|<agency name>|<win>|<arrival q>|<departure q>|<cancel ‰>|<n> operator
    M|<mode>|<win>|<arrival q>|<departure q>|<cancel ‰>|<n>               mode in this region
    H|<mode>|<minutes ahead>|<error q>|<n>                                live forecast error

`routeId`/`stopId` carry the Transitous feed prefix (`de-DELFI_…`), exactly like `Leg.routeId` and
`Place.stopId` in the app. Windows: p weekday peak, w weekday other, e weekend, n night. The app
looks up S → R → O → M and uses its old estimate when none matches. S rows are only written where
the stop differs from its route by a minute or more (keeps the files small).
"""
import gzip, itertools, json, os
from datetime import date, timedelta

from . import model

MIN_N = {'S': 30, 'R': 30, 'O': 50, 'M': 50, 'H': 50}


def _country(feed: str) -> str:
    return feed.split('-', 1)[0]


def _stream(db, keys: str, where: str, since: str, k: int):
    """Yields (key tuple, {'a': bins, 'd': bins, 'c': cancelled, 'n': total}) sorted by key."""
    sql = f"""
      SELECT {keys}, 'a', arr_bin, count(*) FROM events WHERE day >= :s AND cancelled = 0 AND arr_bin IS NOT NULL {where} GROUP BY {keys}, arr_bin
      UNION ALL
      SELECT {keys}, 'd', dep_bin, count(*) FROM events WHERE day >= :s AND cancelled = 0 AND dep_bin IS NOT NULL {where} GROUP BY {keys}, dep_bin
      UNION ALL
      SELECT {keys}, 'c', cancelled, count(*) FROM events WHERE day >= :s {where} GROUP BY {keys}, cancelled
      ORDER BY {', '.join(str(i + 1) for i in range(k))}"""
    rows = db.execute(sql, {'s': since})
    for key, group in itertools.groupby(rows, key=lambda r: r[:k]):
        g = {'a': {}, 'd': {}, 'c': 0, 'n': 0}
        for r in group:
            kind, b, n = r[k], r[k + 1], r[k + 2]
            if kind == 'c':
                g['n'] += n
                if b:
                    g['c'] += n
            else:
                g[kind][b] = g[kind].get(b, 0) + n
        yield key, g


def _q(bins):
    return ','.join(str(v) for v in model.quantiles_from_bins(bins)) if bins else ''


def _fields(g):
    return [_q(g['a']), _q(g['d']), str(round(1000 * g['c'] / g['n'])) if g['n'] else '0', str(g['n'])]


def _differs(a, b, secs=60, permille=20):
    """True if the stop row adds something over its route row."""
    for i in (0, 1):
        qa, qb = a[i].split(',') if a[i] else [], b[i].split(',') if b[i] else []
        if len(qa) != len(qb):
            return True
        if any(abs(int(x) - int(y)) >= secs for x, y in zip(qa[2:], qb[2:])):   # p50, p80, p95
            return True
    return abs(int(a[2]) - int(b[2])) >= permille


def build(db, today: str, days: int = 90) -> dict:
    """Returns {country: [lines]}."""
    since = (date.fromisoformat(today) - timedelta(days=days)).isoformat()
    first = db.execute('SELECT min(day) FROM events WHERE day >= ?', (since,)).fetchone()[0] or today
    out = {}

    def add(country, line):
        out.setdefault(country, []).append(line)

    routes = {}
    for (feed, route, win), g in _stream(db, 'feed, route, win', '', since, 3):
        if g['n'] >= MIN_N['R']:
            f = _fields(g)
            routes[(feed, route, win)] = f
            add(_country(feed), '|'.join(['R', f'{feed}_{route}', win, *f]))
    for (feed, route, stop, win), g in _stream(db, 'feed, route, stop, win', 'AND stop IS NOT NULL', since, 4):
        if g['n'] < MIN_N['S']:
            continue
        f = _fields(g)
        parent = routes.get((feed, route, win))
        if parent is None or _differs(f, parent):
            add(_country(feed), '|'.join(['S', f'{feed}_{route}', f'{feed}_{stop}', win, *f]))
    for (feed, agency, win), g in _stream(db, 'feed, agency, win', 'AND agency IS NOT NULL', since, 3):
        if g['n'] >= MIN_N['O']:
            add(_country(feed), '|'.join(['O', feed, agency.replace('|', '/'), win, *_fields(g)]))
    region = "substr(feed, 1, instr(feed || '-', '-') - 1)"
    for (country, mode, win), g in _stream(db, f'{region}, mode, win', '', since, 3):
        if g['n'] >= MIN_N['M']:
            add(country, '|'.join(['M', mode, win, *_fields(g)]))
    for h in model.HORIZONS:
        err = f"(COALESCE(act_arr - sched_arr, act_dep - sched_dep) - h{h})"
        rows = db.execute(f"""SELECT {region} AS c, mode, (({err}) / {model.BIN}) * {model.BIN} AS b, count(*)
                              FROM events WHERE day >= ? AND cancelled = 0 AND h{h} IS NOT NULL AND {err} IS NOT NULL
                              GROUP BY c, mode, b ORDER BY c, mode""", (since,))
        for (country, mode), group in itertools.groupby(rows, key=lambda r: r[:2]):
            bins = {}
            for r in group:
                b = max(model.MIN_DELAY, min(model.MAX_DELAY, r[2]))
                bins[b] = bins.get(b, 0) + r[3]
            n = sum(bins.values())
            if n >= MIN_N['H']:
                add(country, '|'.join(['H', mode, str(h), _q(bins), str(n)]))
    head = f'D|{today}|{(date.fromisoformat(today) - date.fromisoformat(first)).days + 1}|{first}'
    return {c: [head] + lines for c, lines in out.items()}


def publish(tables: dict, out_dir: str, today: str) -> dict:
    """Writes <country>.txt.gz atomically plus index.json. Old files stay when a country has no rows."""
    os.makedirs(out_dir, exist_ok=True)
    index_path = os.path.join(out_dir, 'index.json')
    try:
        index = json.load(open(index_path))
    except Exception:
        index = {'regions': {}}
    for country, lines in tables.items():
        data = gzip.compress(('\n'.join(lines) + '\n').encode('utf-8'), mtime=0)
        tmp = os.path.join(out_dir, f'.{country}.tmp')
        with open(tmp, 'wb') as fh:
            fh.write(data)
        os.replace(tmp, os.path.join(out_dir, f'{country}.txt.gz'))
        index['regions'][country] = {'date': today, 'rows': len(lines) - 1, 'bytes': len(data)}
    index['date'] = today
    tmp = index_path + '.tmp'
    json.dump(index, open(tmp, 'w'), indent=1, sort_keys=True)
    os.replace(tmp, index_path)
    return index

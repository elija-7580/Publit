"""Back-test: are the chances right? Pairs real feeder arrivals with real departures at the same
station (2–15 min apart, other trip), predicts each change with the old formula and with the new
one (history from the days before the test period only) and compares with what happened.

Output: Markdown with the Brier score and a calibration curve per mode (docs/calibration.md).
Assumption, stated in the report: a fixed walk of WALK seconds, because the real walk of each pair
is unknown on the server. That makes the test about delays, not about walking.
"""
import random
from collections import defaultdict
from datetime import date, timedelta

from . import aggregate, chance

WALK = 180


def _table(db, today, days):
    """{(routeId, stopId|None, win) or ('M', mode, win): (arr_q, dep_q, cancel, n)} from build()."""
    t = {}
    for lines in aggregate.build(db, today, days).values():
        for line in lines[1:]:
            f = line.split('|')
            def q(s):
                return [int(x) for x in s.split(',')] if s else None
            if f[0] == 'S':
                t[(f[1], f[2], f[3])] = (q(f[4]), q(f[5]), int(f[6]) / 1000, int(f[7]))
            elif f[0] == 'R':
                t[(f[1], None, f[2])] = (q(f[3]), q(f[4]), int(f[5]) / 1000, int(f[6]))
            elif f[0] == 'M':
                t[('M', f[1], f[2])] = (q(f[3]), q(f[4]), int(f[5]) / 1000, int(f[6]))
    return t


def _lookup(t, feed, route, stop, mode, win):
    rid, sid = f'{feed}_{route}', f'{feed}_{stop}'
    return t.get((rid, sid, win)) or t.get((rid, None, win)) or t.get(('M', mode, win))


def run(db, test_days=14, history_days=90, max_pairs=200_000, seed=1):
    last = db.execute('SELECT max(day) FROM events').fetchone()[0]
    if not last:
        return None
    split = (date.fromisoformat(last) - timedelta(days=test_days - 1)).isoformat()
    table = _table(db, (date.fromisoformat(split) - timedelta(days=1)).isoformat(), history_days)
    rows = db.execute("""
      SELECT a.feed, a.route, a.stop, a.mode, a.win, a.sched_arr, a.act_arr, a.cancelled,
             d.route, d.stop, d.mode, d.win, d.sched_dep, d.act_dep, d.cancelled
      FROM events a JOIN stops sa ON sa.feed = a.feed AND sa.stop = a.stop
      JOIN stops sd ON sd.feed = a.feed AND COALESCE(sd.parent, sd.stop) = COALESCE(sa.parent, sa.stop)
      JOIN events d ON d.feed = a.feed AND d.stop = sd.stop AND d.day = a.day AND d.trip != a.trip
      WHERE a.day >= ? AND a.sched_arr IS NOT NULL AND d.sched_dep IS NOT NULL
        AND d.sched_dep - a.sched_arr BETWEEN 120 AND 900""", (split,)).fetchall()
    random.Random(seed).shuffle(rows)
    per = defaultdict(lambda: {'old': [], 'new': []})
    for (feed, r1, s1, m1, w1, sa, aa, c1, r2, s2, m2, w2, sd, ad, c2) in rows[:max_pairs]:
        if aa is None and not c1 or ad is None and not c2:
            continue
        ok = 0 if (c1 or c2) else int(aa + WALK <= ad)
        gap = sd - sa
        per[m1]['old'].append((chance.old_chance((gap - WALK) / 60, WALK, m1), ok))
        hin, hout = _lookup(table, feed, r1, s1, m1, w1), _lookup(table, feed, r2, s2, m2, w2)
        if hin and hout and hin[0] and hout[1]:
            p = chance.chance(gap, hin[0], hout[1], WALK, hin[2], hout[2], min(hin[3], hout[3]), walk_factor=1.0)
        else:
            p = chance.old_chance((gap - WALK) / 60, WALK, m1)
        per[m1]['new'].append((p, ok))
    return {'split': split, 'last': last, 'pairs': sum(len(v['old']) for v in per.values()), 'modes': per}


def brier(pairs):
    return sum((p - o) ** 2 for p, o in pairs) / len(pairs) if pairs else None


def curve(pairs, bins=10):
    out = []
    for b in range(bins):
        sel = [(p, o) for p, o in pairs if b / bins <= p < (b + 1) / bins or (b == bins - 1 and p == 1)]
        if sel:
            out.append((b / bins, (b + 1) / bins, len(sel), sum(p for p, _ in sel) / len(sel), sum(o for _, o in sel) / len(sel)))
    return out


def report(result) -> str:
    if not result or not result['pairs']:
        return ('# Calibration of change chances\n\nNo data yet: the delay-history service has not collected '
                'enough stop events. Thresholds (Safe ≥ 90 %, likely ≥ 70 %) stay as they are until this report '
                'has real numbers.\n')
    lines = ['# Calibration of change chances', '',
             f"Test period {result['split']} – {result['last']}, {result['pairs']} real changes (feeder arrival → departure "
             f'at the same station, 2–15 min apart). History for the new model only from before the test period. '
             f'Fixed walk of {WALK} s (the real walk of each pair is unknown on the server).', '',
             '| Mode (feeder) | Changes | Brier old | Brier new |', '|---|---:|---:|---:|']
    for mode, v in sorted(result['modes'].items(), key=lambda kv: -len(kv[1]['old'])):
        lines.append(f"| {mode} | {len(v['old'])} | {brier(v['old']):.4f} | {brier(v['new']):.4f} |")
    lines += ['', 'Lower is better. Calibration curves (predicted vs. observed share that worked):', '']
    for mode, v in sorted(result['modes'].items(), key=lambda kv: -len(kv[1]['old'])):
        lines += [f'### {mode}', '', '| Predicted | Old: changes · worked | New: changes · worked |', '|---|---:|---:|']
        old, new = {c[0]: c for c in curve(v['old'])}, {c[0]: c for c in curve(v['new'])}

        def cell(c):
            return f'{c[2]} · {c[4]:.0%}' if c else '–'
        for lo in sorted(set(old) | set(new)):
            lines.append(f'| {lo:.0%}–{lo + 0.1:.0%} | {cell(old.get(lo))} | {cell(new.get(lo))} |')
        lines.append('')
    return '\n'.join(lines) + '\n'

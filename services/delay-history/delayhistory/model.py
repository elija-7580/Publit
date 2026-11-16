"""Shared rules: time windows, delay bins, GTFS route types → app modes, quantiles."""
from datetime import datetime
from zoneinfo import ZoneInfo

# Quantiles published for every distribution (percent). 50/80/95 as asked; 5 and 20 so the app
# can rebuild the early side too (a connection that leaves early hurts, a feeder that is early helps).
QUANTILES = (5, 20, 50, 80, 95)

BIN = 30                 # seconds per delay bin
MIN_DELAY = -600         # earlier than 10 min early is clamped
MAX_DELAY = 7200         # later than 2 h is clamped (still counts as "very late")

HORIZONS = (5, 15, 30, 60)   # minutes before the event at which the live forecast is remembered

WINDOWS = ('p', 'w', 'e', 'n')   # weekday peak, weekday other, weekend, night


def window(local: datetime) -> str:
    """p = Mon–Fri 06–09 and 16–19, n = 22–05 every day, e = Sat/Sun otherwise, w = Mon–Fri otherwise."""
    h, wd = local.hour, local.weekday()
    if h >= 22 or h < 5:
        return 'n'
    if wd >= 5:
        return 'e'
    if 6 <= h < 9 or 16 <= h < 19:
        return 'p'
    return 'w'


def local_time(ts: int, tz: str) -> datetime:
    return datetime.fromtimestamp(ts, ZoneInfo(tz))


def delay_bin(seconds: int) -> int:
    s = max(MIN_DELAY, min(MAX_DELAY, seconds))
    return (s // BIN) * BIN


def mode(route_type) -> str:
    """GTFS (incl. extended) route_type → the MOTIS mode names the app uses on `Leg.mode`."""
    try:
        t = int(route_type)
    except (TypeError, ValueError):
        return 'OTHER'
    exact = {0: 'TRAM', 1: 'SUBWAY', 2: 'RAIL', 3: 'BUS', 4: 'FERRY', 5: 'CABLE_CAR', 6: 'AERIAL_LIFT',
             7: 'FUNICULAR', 11: 'BUS', 12: 'RAIL', 101: 'HIGHSPEED_RAIL', 102: 'LONG_DISTANCE',
             103: 'REGIONAL_FAST_RAIL', 105: 'NIGHT_RAIL', 106: 'REGIONAL_RAIL', 109: 'SUBURBAN',
             200: 'COACH', 201: 'COACH', 202: 'COACH', 400: 'SUBWAY', 401: 'SUBWAY', 402: 'SUBWAY',
             403: 'SUBURBAN', 405: 'SUBWAY', 900: 'TRAM', 1000: 'FERRY', 1200: 'FERRY',
             1300: 'AERIAL_LIFT', 1400: 'FUNICULAR', 1500: 'BUS', 1700: 'OTHER'}
    if t in exact:
        return exact[t]
    for lo, hi, m in ((100, 199, 'RAIL'), (200, 299, 'COACH'), (400, 499, 'SUBWAY'), (700, 799, 'BUS'),
                      (800, 899, 'BUS'), (900, 999, 'TRAM'), (1000, 1099, 'FERRY'), (1300, 1399, 'AERIAL_LIFT')):
        if lo <= t <= hi:
            return m
    return 'OTHER'


def quantiles_from_bins(bins: dict) -> tuple:
    """Quantiles (seconds, bin start + half a bin) from {bin: count}. Linear inside the bin."""
    total = sum(bins.values())
    if total == 0:
        return ()
    out, keys, acc, i = [], sorted(bins), 0, 0
    for q in QUANTILES:
        target = total * q / 100
        while i < len(keys) and acc + bins[keys[i]] < target:
            acc += bins[keys[i]]
            i += 1
        k = keys[min(i, len(keys) - 1)]
        frac = (target - acc) / bins[k] if bins[k] else 0.5
        out.append(int(round(k + BIN * min(1, max(0, frac)))))
    return tuple(out)

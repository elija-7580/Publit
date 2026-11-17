"""Reference implementation of the change chance (same maths as SmartRouting.swift / Android).

    chance = (1 − cancel_in) · (1 − cancel_out) · P(arrival delay + walk ≤ gap + departure delay)

Each delay is a distribution rebuilt from five quantiles (5/20/50/80/95 %); the probability is
counted over equally likely samples of all three (feeder, walk, connection). tests/vectors.json
holds cases that the iOS and Android tests check too, so the three implementations stay equal.
"""
import math

P = (0.05, 0.20, 0.50, 0.80, 0.95)
SAMPLES = 20                               # per delay distribution
WALK_SPREAD = 0.15                         # log-normal sigma of the walk time
WALK_Z = (-1.465, -0.792, -0.366, 0.0, 0.366, 0.792, 1.465)   # 7 equally likely normal points


def quantile(q, p):
    """Quantile function through the five knots; linear outside, the late tail twice as steep."""
    if p <= P[0]:
        return q[0] - (P[0] - p) / (P[1] - P[0]) * (q[1] - q[0])
    if p >= P[-1]:
        return q[-1] + 2 * (p - P[-1]) / (P[-1] - P[-2]) * (q[-1] - q[-2])
    for i in range(len(P) - 1):
        if p <= P[i + 1]:
            t = (p - P[i]) / (P[i + 1] - P[i])
            return q[i] + t * (q[i + 1] - q[i])
    return q[-1]


def samples(q, n=SAMPLES):
    return [quantile(q, (i + 0.5) / n) for i in range(n)]


def walk_samples(seconds, median_factor=1.05, sigma=WALK_SPREAD):
    return [seconds * median_factor * math.exp(sigma * z) for z in WALK_Z]


def p_on_time(gap, arr_q, dep_q, walk):
    """P(a + w ≤ gap + d) with a, d from quantiles (seconds) and walk samples (seconds)."""
    a, d = samples(arr_q), samples(dep_q)
    d.sort()
    hit = 0
    for x in a:
        for w in walk:
            need = x + w - gap          # the connection must be at least this late
            # count d_j ≥ need (binary search on sorted d)
            lo, hi = 0, len(d)
            while lo < hi:
                mid = (lo + hi) // 2
                if d[mid] < need:
                    lo = mid + 1
                else:
                    hi = mid
            hit += len(d) - lo
    return hit / (len(a) * len(walk) * len(d))


def live_quantiles(forecast_delay, error_q):
    return [forecast_delay + e for e in error_q]


def cap(p, n):
    """No near-certainty from few observations: at most 1 − 1/(n+2), at least 1/(n+2)."""
    if n is None:
        return p
    lo = 1 / (n + 2)
    return min(1 - lo, max(lo, p))


def chance(gap, arr_q, dep_q, walk_seconds, cancel_in=0.0, cancel_out=0.0, n=None, walk_factor=1.05):
    p = p_on_time(gap, arr_q, dep_q, walk_samples(walk_seconds, walk_factor))
    return cap((1 - cancel_in) * (1 - cancel_out) * p, n)


# The formula used until now (fallback without history), as in SmartRouting.chance.
def spread(mode):
    if mode in ('HIGHSPEED_RAIL', 'LONG_DISTANCE', 'NIGHT_RAIL', 'AIRPLANE'):
        return 4
    if mode in ('RAIL', 'REGIONAL_RAIL', 'REGIONAL_FAST_RAIL', 'SUBURBAN', 'COACH'):
        return 2.5
    if mode in ('TRAM', 'CABLE_CAR', 'FUNICULAR', 'AERIAL_LIFT', 'AREAL_LIFT'):
        return 1.5
    if mode in ('SUBWAY', 'METRO'):
        return 1
    return 2


def old_chance(spare_minutes, walk_seconds, mode, real_time=False):
    s = spread(mode) * (0.6 if real_time else 1)
    margin = spare_minutes - walk_seconds / 60 * 0.1
    x = (margin + 0.5 - s / 2) / (s * 0.6)
    return min(0.995, max(0.01, 1 / (1 + math.exp(-x))))

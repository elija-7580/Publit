"""Reads GTFS-RT TripUpdates and turns forecasts into observed stop events.

GTFS-RT carries forecasts, not a log. A stop event is taken as observed once its forecast time
lies FINAL_AFTER seconds in the past: the last forecast before the vehicle got there is the best
available record of what happened (feeds stop updating a stop once it is served). Stops with only
an absolute `time` and no `delay` are skipped – the scheduled time would need the full stop_times.
"""
import zlib
from datetime import datetime, timezone
from google.transit import gtfs_realtime_pb2 as rt

from . import model

FINAL_AFTER = 120        # seconds after the forecast time
STALE_AFTER = 6 * 3600   # pending rows nobody updated for this long are dropped

SKIPPED = rt.TripUpdate.StopTimeUpdate.SKIPPED
NO_DATA = rt.TripUpdate.StopTimeUpdate.NO_DATA
CANCELED = rt.TripDescriptor.CANCELED


def parse(data: bytes) -> rt.FeedMessage:
    msg = rt.FeedMessage()
    msg.ParseFromString(data)
    return msg


def _event(ev):
    """(time, delay) of a StopTimeEvent; time may be derived, delay must be given."""
    if not ev.HasField('delay') and not ev.HasField('time'):
        return None, None
    d = ev.delay if ev.HasField('delay') else None
    t = ev.time if ev.HasField('time') and ev.time > 0 else None
    return t, d


def _start_ts(td, tz):
    """Trip start as unix time from start_date + start_time (for cancelled trips without stops)."""
    try:
        h, m, s = (int(x) for x in td.start_time.split(':'))
        base = datetime.strptime(td.start_date, '%Y%m%d').replace(tzinfo=model.local_time(0, tz).tzinfo)
        return int(base.timestamp()) + h * 3600 + m * 60 + s
    except Exception:
        return None


def ingest(db, feed: dict, msg, now: int) -> dict:
    """Upserts forecasts into `pending`. Returns counters for the health page."""
    tag, tz = feed['tag'], feed.get('tz', 'Europe/Vienna')
    stats = {'trips': 0, 'stops': 0, 'no_delay': 0}
    today = datetime.fromtimestamp(now, timezone.utc).strftime('%Y%m%d')
    rows = []
    for ent in msg.entity:
        if not ent.HasField('trip_update'):
            continue
        tu = ent.trip_update
        td = tu.trip
        if not td.trip_id:
            continue
        stats['trips'] += 1
        sdate = td.start_date or today
        route = td.route_id or None
        if td.schedule_relationship == CANCELED:
            t = _start_ts(td, tz) or now
            rows.append((tag, td.trip_id, sdate, -1, None, route, t, 0, None, None, 0, 1))
            continue
        for stu in tu.stop_time_update:
            if stu.schedule_relationship == NO_DATA:
                continue
            seq = stu.stop_sequence if stu.HasField('stop_sequence') else None
            stop = stu.stop_id or None
            if seq is None and stop is None:
                continue
            key_seq = seq if seq is not None else zlib.crc32(stop.encode()) & 0x7FFFFFFF
            at, ad = _event(stu.arrival)
            dt, dd = _event(stu.departure)
            skipped = 1 if stu.schedule_relationship == SKIPPED else 0
            if ad is None and dd is None and not skipped:
                stats['no_delay'] += 1
                continue
            # Derive missing times from the other side (dwell unknown → same time).
            if at is None and ad is not None and dt is not None and dd is not None:
                at = dt - dd + ad
            if dt is None and dd is not None and at is not None and ad is not None:
                dt = at - ad + dd
            if at is None and dt is None and not skipped:
                stats['no_delay'] += 1
                continue
            rows.append((tag, td.trip_id, sdate, key_seq, stop, route, at, ad, dt, dd, skipped, 0))
            stats['stops'] += 1
    for r in rows:
        _upsert(db, r, now)
    db.commit()
    return stats


def _upsert(db, r, now):
    tag, trip, sdate, seq, stop, route, at, ad, dt, dd, skipped, cancelled = r
    old = db.execute('SELECT h5,h15,h30,h60,stop,route FROM pending WHERE feed=? AND trip=? AND sdate=? AND seq=?',
                     (tag, trip, sdate, seq)).fetchone()
    hs = list(old[:4]) if old else [None] * 4
    t = at if at is not None else dt
    d = ad if ad is not None else dd
    if t is not None and d is not None:
        before = (t - now) / 60
        for i, h in enumerate(model.HORIZONS):
            # The forecast as it stood about h minutes ahead (not one made much later).
            if hs[i] is None and h / 2 < before <= h:
                hs[i] = d
    stop = stop or (old[4] if old else None)
    route = route or (old[5] if old else None)
    db.execute('INSERT OR REPLACE INTO pending VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
               (tag, trip, sdate, seq, stop, route, at, ad, dt, dd, skipped, cancelled, *hs, now))


def finalize(db, feeds: dict, now: int) -> int:
    """Moves stop events whose time has passed into `events`. Returns how many."""
    done = db.execute('SELECT * FROM pending WHERE COALESCE(dep_t, arr_t) < ?', (now - FINAL_AFTER,)).fetchall()
    out = []
    for (tag, trip, sdate, seq, stop, route, at, ad, dt, dd, skipped, cancelled, h5, h15, h30, h60, _) in done:
        feed = feeds.get(tag, {})
        tz = feed.get('tz', 'Europe/Vienna')
        if route is None:
            row = db.execute('SELECT route FROM trips WHERE feed=? AND trip=?', (tag, trip)).fetchone()
            route = row[0] if row else None
        if route is None:
            continue   # cannot be grouped
        info = db.execute('SELECT mode, agency FROM routes WHERE feed=? AND route=?', (tag, route)).fetchone()
        mode, agency = info if info else (feed.get('mode', 'OTHER'), None)
        sa = at - ad if at is not None and ad is not None else None
        sd = dt - dd if dt is not None and dd is not None else None
        sched = sa if sa is not None else sd
        if sched is None:
            sched = at or dt
        loc = model.local_time(sched, tz)
        out.append((loc.strftime('%Y-%m-%d'), tag, trip, route, stop, mode, agency,
                    sa, at, sd, dt, 1 if (cancelled or skipped) else 0, loc.weekday(), loc.hour, model.window(loc),
                    model.delay_bin(ad) if ad is not None else None, model.delay_bin(dd) if dd is not None else None,
                    h5, h15, h30, h60))
    db.executemany('INSERT INTO events VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)', out)
    db.execute('DELETE FROM pending WHERE COALESCE(dep_t, arr_t) < ? OR last_seen < ?', (now - FINAL_AFTER, now - STALE_AFTER))
    db.commit()
    return len(out)


def purge(db, keep_days: int, today: str):
    """Deletes raw events older than keep_days (by local service day)."""
    from datetime import date, timedelta
    cutoff = (date.fromisoformat(today) - timedelta(days=keep_days)).isoformat()
    n = db.execute('DELETE FROM events WHERE day < ?', (cutoff,)).rowcount
    db.commit()
    return n

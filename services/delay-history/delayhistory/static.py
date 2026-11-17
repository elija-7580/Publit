"""Loads routes (mode, operator), trips (trip → route) and stops (parent station) from a feed's
static GTFS zip. TripUpdates carry neither the mode nor always the route; this fills that in."""
import csv, io, os, tempfile, urllib.request, zipfile

from . import model


def _rows(z, name):
    try:
        with z.open(name) as fh:
            yield from csv.DictReader(io.TextIOWrapper(fh, encoding='utf-8-sig'))
    except KeyError:
        return


def load(db, tag: str, zip_path: str):
    with zipfile.ZipFile(zip_path) as z:
        agencies = {r.get('agency_id', ''): r.get('agency_name', '') for r in _rows(z, 'agency.txt')}
        only = next(iter(agencies.values()), None) if len(agencies) == 1 else None
        db.execute('DELETE FROM routes WHERE feed=?', (tag,))
        db.executemany('INSERT OR REPLACE INTO routes VALUES (?,?,?,?)',
                       ((tag, r['route_id'], model.mode(r.get('route_type')),
                         agencies.get(r.get('agency_id', ''), only)) for r in _rows(z, 'routes.txt')))
        db.execute('DELETE FROM trips WHERE feed=?', (tag,))
        db.executemany('INSERT OR REPLACE INTO trips VALUES (?,?,?)',
                       ((tag, r['trip_id'], r['route_id']) for r in _rows(z, 'trips.txt')))
        db.execute('DELETE FROM stops WHERE feed=?', (tag,))
        db.executemany('INSERT OR REPLACE INTO stops VALUES (?,?,?)',
                       ((tag, r['stop_id'], r.get('parent_station') or None) for r in _rows(z, 'stops.txt')))
    db.commit()


def refresh(db, feed: dict, user_agent: str):
    """Downloads the static zip to a temp file (they can be large) and loads it."""
    url = feed.get('static')
    if not url:
        return False
    fd, path = tempfile.mkstemp(suffix='.zip')
    os.close(fd)
    try:
        req = urllib.request.Request(url, headers={'User-Agent': user_agent})
        with urllib.request.urlopen(req, timeout=600) as r, open(path, 'wb') as out:
            while chunk := r.read(1 << 20):
                out.write(chunk)
        load(db, feed['tag'], path)
        return True
    finally:
        os.unlink(path)

"""SQLite storage. Only public timetable data; nothing about app users ever reaches this service."""
import sqlite3

SCHEMA = """
PRAGMA journal_mode=WAL;
-- Stop events still ahead: the newest forecast per stop of a running trip.
CREATE TABLE IF NOT EXISTS pending (
  feed TEXT, trip TEXT, sdate TEXT, seq INTEGER, stop TEXT, route TEXT,
  arr_t INTEGER, arr_d INTEGER, dep_t INTEGER, dep_d INTEGER,
  skipped INTEGER DEFAULT 0, cancelled INTEGER DEFAULT 0,
  h5 INTEGER, h15 INTEGER, h30 INTEGER, h60 INTEGER,
  last_seen INTEGER,
  PRIMARY KEY (feed, trip, sdate, seq)
);
-- Raw stop events (deleted after RETENTION_DAYS). Times are unix seconds.
CREATE TABLE IF NOT EXISTS events (
  day TEXT, feed TEXT, trip TEXT, route TEXT, stop TEXT, mode TEXT, agency TEXT,
  sched_arr INTEGER, act_arr INTEGER, sched_dep INTEGER, act_dep INTEGER,
  cancelled INTEGER, weekday INTEGER, hour INTEGER, win TEXT,
  arr_bin INTEGER, dep_bin INTEGER,
  h5 INTEGER, h15 INTEGER, h30 INTEGER, h60 INTEGER
);
CREATE INDEX IF NOT EXISTS events_day ON events(day);
-- From the static GTFS of each feed (refreshed weekly).
CREATE TABLE IF NOT EXISTS routes (feed TEXT, route TEXT, mode TEXT, agency TEXT, PRIMARY KEY (feed, route));
CREATE TABLE IF NOT EXISTS trips (feed TEXT, trip TEXT, route TEXT, PRIMARY KEY (feed, trip));
CREATE TABLE IF NOT EXISTS stops (feed TEXT, stop TEXT, parent TEXT, PRIMARY KEY (feed, stop));
CREATE TABLE IF NOT EXISTS meta (k TEXT PRIMARY KEY, v TEXT);
"""


def connect(path: str) -> sqlite3.Connection:
    db = sqlite3.connect(path, timeout=60, check_same_thread=False)
    db.executescript(SCHEMA)
    return db


def get_meta(db, k, default=None):
    row = db.execute('SELECT v FROM meta WHERE k=?', (k,)).fetchone()
    return row[0] if row else default


def set_meta(db, k, v):
    db.execute('INSERT OR REPLACE INTO meta VALUES (?,?)', (k, str(v)))

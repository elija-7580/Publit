"""python -m delayhistory run | nightly | calibrate [--out docs/calibration.md]

`run` collects all feeds in a loop, runs the nightly job at NIGHTLY_HOUR (local), refreshes static
GTFS weekly and serves the published tables on PORT (/<country>.txt.gz, /index.json, /health).
"""
import argparse, json, os, sys, threading, time, traceback, urllib.request
from datetime import datetime
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from zoneinfo import ZoneInfo

from . import aggregate, calibrate, collect, static, store

ENV = os.environ.get
DB = ENV('DB_PATH', '/data/history.sqlite')
OUT = ENV('OUT_DIR', '/data/public')
FEEDS = ENV('FEEDS', os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'feeds.json'))
INTERVAL = int(ENV('INTERVAL_SECONDS', '60'))
RETENTION = int(ENV('RETENTION_DAYS', '90'))
NIGHTLY_HOUR = int(ENV('NIGHTLY_HOUR', '3'))
TZ = ZoneInfo(ENV('TZ_NAME', 'Europe/Vienna'))
UA = ENV('USER_AGENT', 'Publit-DelayHistory/0.1 (+https://publit.eu)')

status = {'started': int(time.time()), 'feeds': {}}


def load_feeds():
    """feeds.json; headers like {"Authorization": "env:CH_OTD_KEY"} come from the environment.
    A feed whose secret is not set is skipped (and shown as such on /health)."""
    feeds = {}
    for f in json.load(open(FEEDS)):
        headers, missing = {}, False
        for k, v in f.get('headers', {}).items():
            if v.startswith('env:'):
                v = ENV(v[4:], '')
                missing |= not v
            headers[k] = v
        f['headers'] = headers
        if missing:
            status['feeds'][f['tag']] = {'skipped': 'no key set'}
            continue
        feeds[f['tag']] = f
    return feeds


def fetch(feed):
    req = urllib.request.Request(feed['url'], headers={'User-Agent': UA, **feed['headers']})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read()


def nightly(db, feeds):
    today = datetime.now(TZ).date().isoformat()
    purged = collect.purge(db, RETENTION, today)
    tables = aggregate.build(db, today, RETENTION)
    index = aggregate.publish(tables, OUT, today)
    store.set_meta(db, 'nightly', today)
    db.commit()
    status['nightly'] = {'date': today, 'purged': purged, 'regions': index['regions']}


def run():
    db = store.connect(DB)
    feeds = load_feeds()
    handler = partial(Handler, directory=OUT)
    os.makedirs(OUT, exist_ok=True)
    threading.Thread(target=ThreadingHTTPServer(('', int(ENV('PORT', '8080'))), handler).serve_forever, daemon=True).start()
    while True:
        t0 = time.time()
        now = int(t0)
        for tag, feed in feeds.items():
            st = status['feeds'].setdefault(tag, {})
            try:
                if feed.get('static') and now - int(store.get_meta(db, f'static:{tag}', 0)) > 7 * 86400:
                    static.refresh(db, feed, UA)
                    store.set_meta(db, f'static:{tag}', now)
                    db.commit()
                msg = collect.parse(fetch(feed))
                st.update(collect.ingest(db, feed, msg, now), ok=now, error=None)
            except Exception as e:
                st.update(error=f'{type(e).__name__}: {e}', failed=now)
        try:
            status['finalized'] = status.get('finalized', 0) + collect.finalize(db, feeds, now)
            local = datetime.now(TZ)
            if local.hour == NIGHTLY_HOUR and store.get_meta(db, 'nightly') != local.date().isoformat():
                nightly(db, feeds)
        except Exception:
            status['last_error'] = traceback.format_exc(limit=3)
        time.sleep(max(1, INTERVAL - (time.time() - t0)))


class Handler(SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            ok = any(isinstance(v, dict) and v.get('ok') for v in status['feeds'].values())
            body = json.dumps(status, indent=1).encode()
            self.send_response(200 if ok else 503)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        super().do_GET()

    def end_headers(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Cache-Control', 'public, max-age=3600')
        super().end_headers()

    def log_message(self, *args):   # no access log: nothing about who downloads what is kept
        pass


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('cmd', choices=['run', 'nightly', 'calibrate'])
    ap.add_argument('--out')
    a = ap.parse_args()
    if a.cmd == 'run':
        run()
    elif a.cmd == 'nightly':
        nightly(store.connect(DB), load_feeds())
        print(json.dumps(status.get('nightly'), indent=1))
    else:
        text = calibrate.report(calibrate.run(store.connect(DB)))
        (open(a.out, 'w').write(text) if a.out else sys.stdout.write(text))


if __name__ == '__main__':
    main()

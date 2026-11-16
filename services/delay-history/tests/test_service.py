import gzip, json, os, sys, tempfile, unittest
from datetime import datetime
from zoneinfo import ZoneInfo

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from google.transit import gtfs_realtime_pb2 as rt  # noqa: E402
from delayhistory import aggregate, calibrate, chance, collect, model, store  # noqa: E402

TZ = ZoneInfo('Europe/Berlin')
FEED = {'tag': 'de-T', 'tz': 'Europe/Berlin'}


def ts(y, mo, d, h, mi=0):
    return int(datetime(y, mo, d, h, mi, tzinfo=TZ).timestamp())


def message(trips):
    """trips: [(trip_id, route_id, [(seq, stop, arr_time, arr_delay, dep_time, dep_delay)], cancelled)]"""
    m = rt.FeedMessage()
    m.header.gtfs_realtime_version = '2.0'
    for trip, route, stops, cancelled in trips:
        e = m.entity.add()
        e.id = trip
        e.trip_update.trip.trip_id = trip
        e.trip_update.trip.start_date = '20261116'
        e.trip_update.trip.start_time = '08:00:00'
        if route:
            e.trip_update.trip.route_id = route
        if cancelled:
            e.trip_update.trip.schedule_relationship = rt.TripDescriptor.CANCELED
        for seq, stop, at, ad, dt, dd in stops:
            u = e.trip_update.stop_time_update.add()
            u.stop_sequence = seq
            u.stop_id = stop
            if at is not None: u.arrival.time = at
            if ad is not None: u.arrival.delay = ad
            if dt is not None: u.departure.time = dt
            if dd is not None: u.departure.delay = dd
    return m


def db_with_static():
    db = store.connect(':memory:')
    db.execute("INSERT INTO routes VALUES ('de-T','R1','REGIONAL_RAIL','Bahn A')")
    db.execute("INSERT INTO routes VALUES ('de-T','R2','BUS','Bus B')")
    db.execute("INSERT INTO trips VALUES ('de-T','t-noroute','R1')")
    return db


class Model(unittest.TestCase):
    def test_windows(self):
        self.assertEqual(model.window(datetime(2026, 11, 16, 7, 30)), 'p')   # Monday morning
        self.assertEqual(model.window(datetime(2026, 11, 16, 12)), 'w')
        self.assertEqual(model.window(datetime(2026, 11, 21, 12)), 'e')      # Saturday
        self.assertEqual(model.window(datetime(2026, 11, 21, 23)), 'n')
        self.assertEqual(model.window(datetime(2026, 11, 17, 4)), 'n')

    def test_modes(self):
        self.assertEqual(model.mode('2'), 'RAIL')
        self.assertEqual(model.mode(109), 'SUBURBAN')
        self.assertEqual(model.mode(704), 'BUS')
        self.assertEqual(model.mode('x'), 'OTHER')

    def test_quantiles(self):
        bins = {0: 50, 60: 30, 300: 20}
        q = model.quantiles_from_bins(bins)
        self.assertEqual(len(q), 5)
        self.assertEqual(list(q), sorted(q))
        self.assertLess(q[2], 60)            # median inside the first bin
        self.assertGreaterEqual(q[4], 300)   # 95 % in the late bin
        self.assertEqual(model.delay_bin(10_000), model.MAX_DELAY)
        self.assertEqual(model.delay_bin(-45), -60)


class Collect(unittest.TestCase):
    def test_forecast_becomes_event_with_horizons(self):
        db = db_with_static()
        t = ts(2026, 11, 16, 8, 30)
        # 60, 30 and 10 minutes ahead the forecast says 1, 2 and 3 minutes late; then it passes.
        for ahead, delay in ((55, 60), (25, 120), (2, 180)):
            now = t - ahead * 60
            collect.ingest(db, FEED, message([('t1', 'R1', [(5, 'S1', t + delay, delay, t + delay + 60, delay)], False)]), now)
        self.assertEqual(collect.finalize(db, {'de-T': FEED}, t + 10), 0)    # not passed yet
        self.assertEqual(collect.finalize(db, {'de-T': FEED}, t + 600), 1)
        row = db.execute('SELECT route, stop, mode, agency, sched_arr, act_arr, win, arr_bin, h5, h15, h30, h60 FROM events').fetchone()
        self.assertEqual(row[:4], ('R1', 'S1', 'REGIONAL_RAIL', 'Bahn A'))
        self.assertEqual(row[5] - row[4], 180)
        self.assertEqual(row[6], 'p')
        self.assertEqual(row[7], 180)
        self.assertEqual(row[8:], (180, None, 120, 60))
        self.assertEqual(db.execute('SELECT count(*) FROM pending').fetchone()[0], 0)

    def test_route_from_static_cancel_and_missing_delay(self):
        db = db_with_static()
        t = ts(2026, 11, 16, 12)
        stats = collect.ingest(db, FEED, message([
            ('t-noroute', None, [(1, 'S1', t, 30, None, None)], False),
            ('t-time-only', 'R1', [(1, 'S1', t, None, None, None)], False),
            ('t-cancel', 'R2', [], True),
            ('t-unknown', None, [(1, 'S9', t, 0, None, None)], False)]), t - 600)
        self.assertEqual(stats['no_delay'], 1)
        collect.finalize(db, {'de-T': FEED}, t + 4 * 3600)
        rows = db.execute('SELECT trip, route, cancelled FROM events ORDER BY trip').fetchall()
        # t-unknown has no route anywhere and cannot be grouped
        self.assertEqual(rows, [('t-cancel', 'R2', 1), ('t-noroute', 'R1', 0)])

    def test_purge(self):
        db = db_with_static()
        db.execute("INSERT INTO events (day) VALUES ('2026-08-01'), ('2026-11-01')")
        self.assertEqual(collect.purge(db, 90, '2026-11-17'), 1)


def fill(db, route, stop, mode, delays, cancelled=0, day='2026-11-16', win='w', agency='Bahn A', feed='de-T'):
    db.executemany('INSERT INTO events VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)', [
        (day, feed, f'trip{i}', route, stop, mode, agency, 1000, 1000 + d, 1060, 1060 + d, cancelled, 0, 12, win,
         model.delay_bin(d), model.delay_bin(d), d, None, None, None) for i, d in enumerate(delays)])


class Aggregate(unittest.TestCase):
    def test_levels_and_fallback_rows(self):
        db = store.connect(':memory:')
        fill(db, 'R1', 'S1', 'REGIONAL_RAIL', [0] * 40)
        fill(db, 'R1', 'S2', 'REGIONAL_RAIL', [600] * 40)    # always 10 min late here
        fill(db, 'R1', 'S3', 'REGIONAL_RAIL', [0] * 5)       # too few for a stop row
        fill(db, 'R1', 'S1', 'REGIONAL_RAIL', [0] * 2, cancelled=1)
        lines = aggregate.build(db, '2026-11-17')['de']
        kinds = [l.split('|')[0] for l in lines]
        self.assertTrue(lines[0].startswith('D|2026-11-17|2|2026-11-16'))
        self.assertIn('R', kinds); self.assertIn('O', kinds); self.assertIn('M', kinds); self.assertIn('H', kinds)
        stops = [l for l in lines if l.startswith('S|')]
        self.assertTrue(any('|de-T_S2|' in s for s in stops))
        self.assertFalse(any('|de-T_S3|' in s for s in stops))
        r = next(l for l in lines if l.startswith('R|')).split('|')
        self.assertEqual(r[1], 'de-T_R1')
        self.assertEqual(int(r[5]), round(1000 * 2 / 87))
        h = next(l for l in lines if l.startswith('H|')).split('|')
        self.assertEqual(h[1:3], ['REGIONAL_RAIL', '5'])
        self.assertTrue(all(0 <= int(x) < model.BIN for x in h[3].split(',')))   # forecast equalled the outcome

    def test_publish_keeps_other_regions(self):
        with tempfile.TemporaryDirectory() as d:
            aggregate.publish({'de': ['D|x', 'R|a'], 'ch': ['D|x']}, d, '2026-11-16')
            idx = aggregate.publish({'de': ['D|y', 'R|b', 'R|c']}, d, '2026-11-17')
            self.assertEqual(set(idx['regions']), {'de', 'ch'})
            self.assertEqual(idx['regions']['de']['rows'], 2)
            self.assertEqual(gzip.decompress(open(os.path.join(d, 'de.txt.gz'), 'rb').read()).decode(), 'D|y\nR|b\nR|c\n')


class Chance(unittest.TestCase):
    def test_vectors(self):
        v = json.load(open(os.path.join(os.path.dirname(__file__), 'vectors.json')))
        for c in v['cases']:
            got = chance.chance(c['gap'], c['arr'], c['dep'], c['walk'], c['cin'], c['cout'], c['n'])
            self.assertAlmostEqual(got, c['expected'], places=5, msg=c['name'])

    def test_late_connection_helps_and_more_time_helps(self):
        arr = [-60, 0, 90, 240, 480]
        punctual = chance.chance(240, arr, [0, 0, 0, 0, 30], 180)
        late = chance.chance(240, arr, [0, 60, 180, 300, 600], 180)
        self.assertLess(punctual, late)
        self.assertLess(chance.chance(120, arr, [0] * 5, 60), chance.chance(600, arr, [0] * 5, 60))
        self.assertLessEqual(chance.chance(3600, [0] * 5, [0] * 5, 60, n=10), 1 - 1 / 12)


class Calibrate(unittest.TestCase):
    def test_no_data_report(self):
        self.assertIn('No data yet', calibrate.report(calibrate.run(store.connect(':memory:'))))

    def test_pairs(self):
        db = store.connect(':memory:')
        db.execute("INSERT INTO stops VALUES ('de-T','A1','A'), ('de-T','A2','A')")
        rows = []
        for day in ('2026-11-01', '2026-11-16'):
            for i in range(40):
                d = (i % 5) * 60
                rows.append((day, 'de-T', f'in{i}', 'R1', 'A1', 'BUS', 'X', 1000 + i * 10_000, 1000 + i * 10_000 + d, None, None, 0, 0, 12, 'w', model.delay_bin(d), None, None, None, None, None))
                rows.append((day, 'de-T', f'out{i}', 'R2', 'A2', 'BUS', 'X', None, None, 1000 + i * 10_000 + 360, 1000 + i * 10_000 + 360, 0, 0, 12, 'w', None, 0, None, None, None, None))
        db.executemany('INSERT INTO events VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)', rows)
        res = calibrate.run(db, test_days=1)
        self.assertEqual(res['pairs'], 40)
        text = calibrate.report(res)
        self.assertIn('| BUS | 40 |', text)
        # Delays 0–4 min with 6 min gap and 3 min walk: 4 of 5 work.
        self.assertAlmostEqual(sum(o for _, o in res['modes']['BUS']['new']) / 40, 0.8)



class SharedVectors(unittest.TestCase):
    def test_ios_copy_is_identical(self):
        here = os.path.dirname(os.path.abspath(__file__))
        ios = os.path.join(here, '..', '..', '..', 'Tests', 'Fixtures', 'change-chance-vectors.json')
        self.assertEqual(json.load(open(ios)), json.load(open(os.path.join(here, 'vectors.json'))))


if __name__ == '__main__':
    unittest.main()

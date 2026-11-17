# Delay history (Smart Routing)

Collects how late public transport really runs, from the open GTFS-Realtime feeds that Transitous also uses, and publishes a small table per country. The app uses it to compute the chance that a change works (`SmartRouting.swift`, Android `SmartRouting.kt`).

**Only public timetable data.** The service never receives anything from the app or its users: it reads operators' feeds, and the app downloads the finished table like any other static file. No access log is written.

## What it does

1. **Collect** (every `INTERVAL_SECONDS`, default 60): reads each feed in `feeds.json`, keeps the newest forecast per stop of every running trip, and also remembers the forecast as it stood about 5, 15, 30 and 60 minutes ahead (to learn how good live forecasts are).
2. **Observe:** two minutes after a stop's forecast time has passed, the last forecast is stored as what happened: feed, route, mode, operator, stop, scheduled and actual arrival/departure, cancelled/skipped, weekday, hour, time window.
3. **Nightly** (03:00 Vienna): deletes raw events older than `RETENTION_DAYS` (90) and builds one table per country from the last 90 days: delay quantiles 5/20/50/80/95 % for arrival and departure, cancellation rate, number of observations, for
   - route × stop × window (only where the stop differs from the whole route by ≥ 1 min or ≥ 2 % cancellations),
   - route × window, operator × window, mode × country × window (fallbacks, in this order),
   - plus the live forecast error per mode for 5/15/30/60 minutes ahead.
   Windows: weekday peak (Mon–Fri 6–9, 16–19), weekday other, weekend, night (22–5). Groups with fewer than 30 observations (50 for operator, mode and forecast error) are left out rather than guessed.
4. **Serve:** `/<country>.txt.gz`, `/index.json`, `/health`. publit.eu mirrors the files weekly (workflow in publit-site) to `https://publit.eu/verspaetung/data/<country>.txt.gz`; the app downloads only the countries of the routes the user plans and keeps the old file if a download fails.

File format: see the docstring of `delayhistory/aggregate.py`.

## Limits (honest list)

- **Observed = last forecast.** GTFS-RT has no log of actual times. The last forecast before a stop is served is usually within seconds of reality, but feeds that stop updating early make delays look smaller.
- **Stops with only an absolute time and no delay** are skipped (the scheduled time would need the full `stop_times.txt`). The count is on `/health` as `no_delay`.
- **Delay propagation** (a feed sending one delay for the rest of the trip) is not expanded; only stops present in the feed are recorded.
- **Austria and northern Italy have no usable open TripUpdates today.** Transitous' Austrian real-time sources are on-demand services only; the northern Italian ones (BusOne proxy) need Transitous' private keys. These regions keep the old estimate until an open feed appears. See docs/DATA-SOURCES.md §6.
- **Switzerland** needs a free key from opentransportdata.swiss (`CH_OTD_KEY`). Without it the feed is skipped.
- **Disk:** Germany (DELFI) produces roughly 1–2 million stop events a day; at ~120 bytes each, 90 days are about 15–25 GB of SQLite (an estimate: check `finalized` on `/health` after the first day). Lower `RETENTION_DAYS` if the server is small; the tables then cover fewer days (the `D|` line says how many).

## Calibration

```bash
docker compose exec delay-history python -m delayhistory calibrate > ../../docs/calibration.md
```

Pairs real arrivals and departures at the same station (2–15 min apart), predicts each change with the old formula and with the new model (history only from before the test period) and reports the Brier score and a calibration curve per mode. Needs a few weeks of data first.

## Run

```bash
pip install -r requirements.txt
python -m unittest discover -s tests -v
DB_PATH=./h.sqlite OUT_DIR=./public python -m delayhistory run      # :8080
```

On the server (behind Caddy, shared external network `caddy`):

```bash
docker compose up -d --build
```

```
delay.publit.eu {
    reverse_proxy delay-history:8080
}
```

`tests/vectors.json` holds change-chance cases that the Python reference (`delayhistory/chance.py`), the iOS tests and the Android tests all check, so the three stay equal.

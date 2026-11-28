<!-- SPDX-License-Identifier: AGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich -->

# Own routing server (MOTIS) with commercially usable data

The public Transitous API may not be used commercially. Publit's own MOTIS server (MIT licence) may, as long as
every timetable it loads allows commercial use. `commercial_feeds.py` builds that feed list from the Transitous
list (CC0) and writes a licence verdict for every European feed (`licences.csv`) plus the attribution list.

Result on 2026-11-23: 1,584 of 2,201 active European feeds allowed; Austria, Germany, Switzerland, France, Spain,
Poland covered. Not allowed or unclear: most of Italy (BusOne, GTT), feeds without any licence (Hungary, Slovenia,
Slovakia, Lithuania, Romania, …), a few CC BY-NC-SA feeds.

To add a feed after a publisher allows it in writing, list it in `permissions.json`:

```json
{ "hu/mav": "E-Mail von MÁV vom 2026-12-01, abgelegt unter …" }
```

The key is `<region file>/<source name>` as in Transitous' `feeds/*.json`. Run the script again and redeploy.

## Extra feeds (`extras.json`)

Some publishers offer the same timetable openly that Transitous takes from a non-commercial proxy, or offer feeds
Transitous does not load. List them in `extras.json` under their region, in Transitous' source format, with a
`license` (or an `mdb-id`, whose licence then comes from the Mobility Database catalogue) and optionally
`replaces` (Transitous source names it stands in for). An extra is only used, and only replaces anything, when its
own licence allows commercial use.

Currently: Tuscany from the Regione Toscana open data portal (CC BY): Autolinee Toscane, GEST, TFT, Toremar and
regional Trenitalia trains, instead of the BusOne copies.

## Running the server

`build.sh` does everything with Docker (or `DOCKER=podman`):

```sh
REGIONS="at de ch" ./build.sh import   # allowed feeds + Geofabrik DACH map, then motis import
./build.sh serve                        # MOTIS on 127.0.0.1:8080, put HTTPS in front (Caddy, nginx)
```

It clones Transitous for their unchanged tools (`fetch.py`, `generate-motis-config.py`, AGPL-3.0-or-later) and
container recipe (CC0), swaps their feed list for the allowed one from `commercial_feeds.py`, and runs
`own_config.py` on the generated config: our map, Publit as client, no map tiles, and no realtime or sharing URLs
that go through Transitous' own servers (feed proxy, crowdsourcing). For all of Europe use
`REGIONS="*" OSM_URL=https://download.geofabrik.de/europe-latest.osm.pbf`; that needs a machine with much more
memory (measure on the first import). Run `import` again for timetable updates (e.g. nightly).

Then point the apps (`ROUTER_URL` build setting) and the ticket shop (`ROUTER_URL`, for `/v1/journeys`) at it.

`python3 -m unittest test_own_config` tests the config step (needs `ruamel.yaml`).

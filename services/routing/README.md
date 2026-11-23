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

Server setup follows the Transitous docs (MOTIS 2 with their import scripts); point it at `out/feeds/` instead of
Transitous' full list.

# Coverage in Europe (Transitous)

Publit plans with [Transitous](https://transitous.org), which merges open timetable (GTFS) and live (GTFS-RT, SIRI) feeds. What a city gets depends entirely on what its operators publish. Checked on 14 October 2026: the feed list of the Transitous repository (`feeds/*.json`), one trip across the centre of 68 cities (weekday 08:00 local time) and the departures within 600 m of the centre at about 18:30 local time.

These are samples. "No live data" may also mean the feed was down at that moment; check again before telling users.

## Warnings in the app (build 63)

Publit says **where timetable data is missing and what is missing**, instead of showing an incomplete result as if it were complete. The card reads "Not reliable here", then the area and what is missing ("Missing: local and regional buses", "No timetable data", "Very little timetable data"), and links to the [coverage map](https://publit.eu/abdeckung/) of the website.

| Where | What the user sees |
|---|---|
| Plan | Orange card above the routes when the start or the destination lies in an area ("From · Carinthia", "To · Madrid") |
| Route details | The same card for the start, the stops where you change, and the destination (not for walking, cycling and driving) |
| Nearby, stop departures | Card for where you are, and for a stop in such an area |
| Place search, saved places | Orange triangle at places in such an area, before one is picked |
| Station map | Layer "Data gaps" in Map layers (on by default) draws the areas in orange: filled solid = no data at all, dashed edge = only a part missing. A card over the map names the area in the middle of the map and what is missing; a tap opens the explanation and the link |
| Apple Watch | The same short card in Nearby and when planning a trip |

All of this works offline: the areas are bundled in the app (`Sources/Models/CoverageAtlasData.swift`, about 30 KB, 124 areas), nothing about where someone is leaves the phone.

### Where the areas come from

The atlas is **generated** from the data of the website's coverage map (repository `publit-site`, folder `abdeckung/data`, refreshed monthly) and a short hand-checked list. Do not edit the Swift file by hand:

```bash
pip install numpy shapely
python3 tools/coverage/make_atlas.py --site ../publit-site/abdeckung/data   # downloads Natural Earth places
python3 tools/coverage/make_atlas.py --site ../publit-site/abdeckung/data --report   # list what was flagged
swift test --filter CoverageTests
```

| Level | Rule (constants at the top of the script) |
|---|---|
| No timetable data | Region of the map without a single stop; a whole country with at most 5 stops |
| Very little timetable data | A whole country with fewer than 100 stops; a region with fewer than 100 stops that contains a town of 20 000 people or more; a town of 30 000 or more with at most 15 stops within 3 km of its centre, in a country where at least 20 % of such towns look like that (mostly stations only: Verona, Sicily, parts of Italy and the Balkans) |
| Part missing (hand-checked, checked against `api.transitous.org`, October 2026) | **Carinthia**: local and regional buses (Transitous skips the Carinthian feed). **Madrid**: metro and the EMT city buses (only Cercanías trains and interurban buses are loaded). **Istanbul**: metro, trams, ferries, suburban trains (only IETT buses). **Kyiv**: metro, trams, suburban trains. **Pristina**: city buses |

Run it after every monthly update of the website data, review the `--report` list, and commit the result. To add a hand-checked area (a city where one kind of service is missing), add an entry to `CURATED` in the script after checking the stops with `/api/v1/map/stops` and `/api/v1/stoptimes`.

Limits: the flag says "data is missing in this area", not "this trip does not work". Where Publit adds its own live data (Austria, Switzerland, parts of Germany, Vienna, Stockholm, London), that is not counted as missing timetable data. Border areas follow the simplified outlines of the website map (a few kilometres).

## No timetable data

| Place | Finding |
|---|---|
| Athens | **Fixed upstream (checked October 2026):** the Athens feeds now load stops and departures, so the app no longer flags Athens. Until then: feeds listed (Athens-Bus, Athens-Rail), but no stop loaded. |
| Malta | No feed. |
| Belarus (Minsk) | No feed. |
| Russia | No feed (not tested). |

## Only part of the network

| City | In the data | Missing |
|---|---|---|
| Istanbul | IETT buses | Metro, Marmaray, trams, funiculars, ferries |
| Kyiv | City buses (Kyivpastrans) | Metro, trams, suburban trains |
| Pristina | Trains (Trainkos) | City buses |
| Madrid | Cercanías trains, interurban buses (e.g. ALSA) | Metro de Madrid, EMT city buses |
| Carinthia (Villach, Klagenfurt, Spittal, Wolfsberg) | Trains, FlixBus | Local and regional buses (feed skipped by Transitous) |

## Timetable only, no live data at the centre

Vienna (Wiener Linien), Stockholm and Gothenburg (Sweden has no live feed), Copenhagen, Lisbon and Porto (only CP trains are live), Barcelona (only Rodalies), Valencia, Seville, Brussels (only SNCB trains, not STIB), Marseille, Milan (only Trenitalia), Naples (only Trenitalia), Luxembourg, Bratislava, Brno (only trains), Tallinn (only Elron trains), Manchester (only trains), Belgrade, Sarajevo, Podgorica, Tirana, Thessaloniki, Lviv, Istanbul, Ankara, Nicosia, Monaco, Andorra.

Since build 47 Publit fills some of these gaps itself (Settings → Data → "Live data from more operators", on by default): **Vienna** (Wiener Linien open data), **all of Austria** (ÖBB journey planner: trains and, where the regional networks report them, buses and trams, plus construction notes), **Venice** (ACTV vaporetti and buses), **Stockholm** (SL) and **London** line status (TfL); since build 58 also **Switzerland** (search.ch) and in Germany **North Rhine-Westphalia** (VRR), **Berlin/Brandenburg** (VBB), **Hesse** (RMV), **Lower Saxony/Bremen** (VBN), **Schleswig-Holstein** (NAH.SH) and **Rhineland-Palatinate** (VRN). See [DATA-SOURCES.md](DATA-SOURCES.md#5-extra-live-sources-build-47).

Without live data the app shows "Timetable": no delays, cancellations or platform changes, and the trip guide, live bar and Live Activity follow the timetable.

## Timetable and live data

Berlin, Hamburg, Munich (and Germany as a whole through DELFI), Graz, Paris, Lyon, London, Dublin, Madrid (Cercanías trains only), Rome, Amsterdam and Rotterdam (partly), Antwerp, Oslo, Helsinki, Riga, Vilnius, Warsaw, Kraków, Prague, Budapest, Ljubljana, Zagreb, Skopje, Sofia, Bucharest, Chișinău (partly), Tbilisi (partly), Reykjavík.

## Austria, Germany, Switzerland (checked 19 October 2026)

Departures within ~700 m of the centre in the next hour, 78 places; "live" = with a live time. Script and raw results were not committed (one-off check).

| Country | Timetable | Live from Transitous | What Publit adds |
|---|---|---|---|
| Germany | Everywhere (DELFI, VBB, VBN, KVV, AVV) | Most cities 80–100 %. Weak: NRW (Essen trams 3/33, Bielefeld trams 3/68, Münster buses 45/123), Hesse (Wiesbaden buses 16/146, Kassel buses 24/49), Lower Saxony (Oldenburg 87/139, Hildesheim 16/40), Kaiserslautern 10/43, Berlin-Spandau 89/130, Flensburg 2/11; none in Berchtesgaden, Kempten 4/36 | Build 58: VRR (NRW: Essen 26 → 38 of 40, Bielefeld 6 → 38), RMV (Hesse: Wiesbaden 7 → 43 of 44), VBN (Lower Saxony/Bremen: Oldenburg 19 → 34 of 44, Bremen 31 → 40 of 42), VRN (Kaiserslautern 11 → 22 of 39), VBB (Spandau 35 → 41 of 41), NAH.SH (Schleswig-Holstein). Still weak: Kempten/Allgäu, Flensburg (no server has more live data there) |
| Switzerland | Everywhere (opentransportdata.swiss) | Almost none: Zürich HB 4/153, Bern 0/149, Basel 4/156, Lugano 0/139 (possibly because Transitous already routes on the 2027 timetable while its live feed belongs to 2026; to report upstream) | search.ch (build 58): Bern 3 → 42 of 48, Zürich Central 0 → 39 of 40, Lugano 0 → 28 of 42 |
| Austria | Everywhere except **Carinthia**: Transitous skips the Carinthian feed (`PTA-Carinthia-Flex-2026`, `"skip": true`, "Stay Seated forever during MOTIS import"). Villach, Klagenfurt, Spittal, Wolfsberg have only trains and FlixBus; no local buses at all | Only Styria (Graz 147/152, Leoben) | ÖBB (build 47): the ride is found for 100 % of rides tested in St. Pölten, Salzburg, Innsbruck, Bregenz, Feldkirch, Linz; live for 79–100 %. Wiener Linien for Vienna. Carinthia cannot be fixed in the app: ÖBB has the buses live (Klagenfurt 68/68), but Transitous has no bus rides to correct |

## Other gaps

- Fares come only from operators that publish them (`withFares`); most routes have none.
- Shared bikes and scooters (GBFS) are mainly in France, Slovenia, Greece, Finland, Hungary, Switzerland, Italy, Romania, Norway and Luxembourg.
- Platforms (tracks) are missing in many bus and tram feeds.
- Station exits are never named by the router (the guide derives them from levels and streets).

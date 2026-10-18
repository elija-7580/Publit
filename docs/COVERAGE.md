# Coverage in Europe (Transitous)

Publit plans with [Transitous](https://transitous.org), which merges open timetable (GTFS) and live (GTFS-RT, SIRI) feeds. What a city gets depends entirely on what its operators publish. Checked on 14 October 2026: the feed list of the Transitous repository (`feeds/*.json`), one trip across the centre of 68 cities (weekday 08:00 local time) and the departures within 600 m of the centre at about 18:30 local time.

These are samples. "No live data" may also mean the feed was down at that moment; check again before telling users.

## No timetable data

| Place | Finding |
|---|---|
| Athens | Feeds are listed (Athens-Bus, Athens-Rail), but no stop is loaded: no routes, no departures. Thessaloniki works. |
| Malta | No feed. |
| Belarus (Minsk) | No feed. |
| Russia | No feed (not tested). |

## Only part of the network

| City | In the data | Missing |
|---|---|---|
| Istanbul | IETT buses | Metro, Marmaray, trams, funiculars, ferries |
| Kyiv | City buses (Kyivpastrans) | Metro, trams, suburban trains |
| Pristina | Trains (Trainkos) | City buses |

## Timetable only, no live data at the centre

Vienna (Wiener Linien), Stockholm and Gothenburg (Sweden has no live feed), Copenhagen, Lisbon and Porto (only CP trains are live), Barcelona (only Rodalies), Valencia, Seville, Brussels (only SNCB trains, not STIB), Marseille, Milan (only Trenitalia), Naples (only Trenitalia), Luxembourg, Bratislava, Brno (only trains), Tallinn (only Elron trains), Manchester (only trains), Belgrade, Sarajevo, Podgorica, Tirana, Thessaloniki, Lviv, Istanbul, Ankara, Nicosia, Monaco, Andorra.

Since build 47 Publit fills some of these gaps itself (Settings → Data → "Live data from more operators", on by default): **Vienna** (Wiener Linien open data), **all of Austria** (ÖBB journey planner: trains and, where the regional networks report them, buses and trams, plus construction notes), **Venice** (ACTV vaporetti and buses), **Stockholm** (SL) and **London** line status (TfL). See [DATA-SOURCES.md](DATA-SOURCES.md#5-extra-live-sources-build-47).

Without live data the app shows "Timetable": no delays, cancellations or platform changes, and the trip guide, live bar and Live Activity follow the timetable.

## Timetable and live data

Berlin, Hamburg, Munich (and Germany as a whole through DELFI), Zürich, Geneva, Graz, Paris, Lyon, London, Dublin, Madrid (Cercanías), Rome, Amsterdam and Rotterdam (partly), Antwerp, Oslo, Helsinki, Riga, Vilnius, Warsaw, Kraków, Prague, Budapest, Ljubljana, Zagreb, Skopje, Sofia, Bucharest, Chișinău (partly), Tbilisi (partly), Reykjavík.

## Other gaps

- Fares come only from operators that publish them (`withFares`); most routes have none.
- Shared bikes and scooters (GBFS) are mainly in France, Slovenia, Greece, Finland, Hungary, Switzerland, Italy, Romania, Norway and Luxembourg.
- Platforms (tracks) are missing in many bus and tram feeds.
- Station exits are never named by the router (the guide derives them from levels and streets).

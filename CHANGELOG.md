# Changelog

## 0.3.0 (build 3)

### New
- Filter by mode: chips on Nearby (kept between launches) and at every station: All, Train, S-Bahn, Metro, Tram, Bus, Ferry, Other. Only modes that run there are offered.
- Lines at a station: every line with its next departures per direction; tap for the line, swipe to save it.
- Route options for Plan and "Where to now?": transport modes, number of changes, walk to and from stops (5–30 min), step-free (wheelchair). The active filters are shown under the button.
- Walking, cycling and driving the whole way, next to the routes ("Other ways"), with the difference to the fastest public transport route. Driving times are without traffic and parking. Can be switched off in Route options.
- Search scopes: All, Stops, Addresses, Places.

## 0.2.0 (build 2)

First update after 0.1. Install it on top of 0.1: saved places, trips and history stay.

### New
- Nearby: live departures grouped by station, alerts, rail replacement buses, "Where to now?" with Home and Work, the next saved trip.
- Plan: trips for later (depart at / arrive by), more connections, walking when it is about as fast, routes from and to the current location.
- Route screen: summary and actions first (start trip, save, calendar, leave reminder), steps, map, fares.
- Saved trips with live status, a calendar entry that links back, a leave reminder and a Live Activity on the lock screen.
- Trip screen: every stop of a vehicle with live times and an estimated position. Save a line at a stop.
- Station map, departures widget, Siri and Shortcuts ("Take me home"), offline copies of the last answers.
- 15 languages.

### Faster
- Nearby shows the last board at once and no longer restarts while GPS settles.
- Times in server answers are read several times faster; route answers with thousands of times decode sooner.
- Offline copies are written to disk in the background, after the answer is already on screen.
- Screens no longer redraw on every location fix; departure countdowns redraw together once a minute.
- Station search reuses cached answers around the same place (search bias rounded to about 1 km).

### Fixed
- A pending leave reminder now moves when live times shift the departure (delay or earlier train).
- Station map: a station split by name no longer gives two pins with the same ID (wrong sheet on tap).
- Switching a trip's reminder on or off always redraws the saved-trip rows.

### Privacy
- Coordinates in requests are rounded to about 1 m, search bias to about 1 km.

### Not in this version
- Tickets as passes are built (`Sources/Tickets`) but not switched on. See [docs/tickets.md](docs/tickets.md).

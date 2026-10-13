# Changelog

## 0.5.1 (build 6)

### Shared tickets
- Register PDF/image Open In / Copy to Publit handlers. When iOS hands Publit a local document, recognize it locally and auto-save recognizable tickets with their unchanged source. Uncertain documents go to review; a unique ticket page is selected automatically from PDFs up to 12 pages, otherwise the user chooses. Exact repeated document/page imports do not create duplicates.
- Automatic validity uses labelled date contexts only, not arbitrary dates. Unknown validity stays unknown; recognition does not verify authenticity. Reversed dates require correction rather than silently swapping them.
- Simulator fixtures and F16 cover real PDF/image recognition and multi-page/review paths. Source-app share-sheet visibility still needs device testing; this is a document handler, not a Share Extension.

### Performance review
- Periodic departures, routes and vehicles pause in background/hidden screens; Nearby polls movement every five seconds after its first fix instead of every half-second.
- Fix shared-request cancellation: each cancelled waiter leaves immediately; the last waiter cancels the download. A stale completion cannot remove a newer flight.
- Skip redundant OCR when a PDF already has embedded text; analyze pages sequentially; bound file reads at 25 MiB and PDF auto-analysis at 12 pages. Page-choice thumbnails release when offscreen.
- Do not retain responses larger than the entire 24 MiB memory cache. Updating an existing entry no longer evicts half the cache. Operator-image cache has explicit count/cost limits.
- Fix UI checks affected by the fifth tab (German Saved) and ensure the route sort control is scrolled into view before tapping.


## 0.5.0 (build 5)

### New
- Tickets tab: add a ticket from a PDF, photo, screenshot or paper scan. Publit reads it on the iPhone (nothing is uploaded), you check the details, and the code is ready for the gate at full brightness. Day, weekly and annual passes show up on every trip while they are valid; single tickets can belong to a trip ("Add ticket for this trip", "Show ticket" on route and trip screens, Live Activity button).
- Operator logos on tickets: suggested for known operators from Wikimedia Commons (via Wikidata), or chosen from several suggestions, from Photos, or none. Only the operator name is sent.
- Apple Wallet (optional, needs a Pass Type ID and the signing service): passes carry the operator logo and icon.
- Codes stay as issued: QR, Aztec, PDF417 and Data Matrix are redrawn from the scanned symbol (same version, error correction and binary content), Code 128 from its content; EAN, UPC, ITF, Code 39/93 and Codabar are shown cut out of the original with their quiet zone. Redrawn codes use whole screen pixels per module, without smoothing.
- Bus and tram stops on either side of the road are separate when you zoom in and on Nearby, each with its directions ("→ Moosach · Pasing"); departures and walking directions go to exactly that stop.
- Stop screen: "Walk there" with the walking time to that stop (opens Apple Maps on foot) and a labelled "Route here".
- Short launch animation while location and the first departures load underneath (skipped with Reduce Motion).

### Faster and more reliable
- Station pins stay where they are while zooming and panning: each station sits on its main platform instead of the average of whatever is loaded, and the area loaded is slightly larger than the screen. Station names hide instead of overlapping, and drop the city ("Karolinenplatz", not "München, Karolinenplatz").
- Identical requests that overlap share one download; a dropped connection or a busy server (502–504) is retried once.
- Live Activity: refreshed every 10 min when the trip is more than an hour away, every 3 min within the hour, every minute shortly before leaving and near the end of a ride, every 2 min on long rides. Unchanged content is not sent to the lock screen, the headline no longer holds a minute count that goes stale, and live refreshes skip the fare data.
- GPS stops while Publit is in the background. No second response cache in memory or on disk.

### CI
- `docs/ci-workflow.yml`: faster workflow (cancels outdated runs, skips doc-only commits, boots the simulator during the build, UI tests on demand with `[ui]` or `[ui F14 F15]` in the commit message and nightly). It replaces `.github/workflows/ci.yml` once copied there (see `docs/ci.md`).

## 0.4.0 (build 4)

### New
- Lines tab: the lines around you and your saved lines, searchable by line number ("U6", "bus 52") or destination, and stations by name. Filter by mode.
- Line screen: the route on a map with the vehicles on it now (estimated from live departure times), both directions, alerts, every stop with minutes from the start. Tap a stop for its timetable for any day, by hour.
- Station map: line routes in their colours and live vehicles moving along them, tap a vehicle for its trip and next stops. Shared bikes, e-scooters and their stations as a layer. Layers can be switched on and off; modes filter lines and vehicles too.
- Shared bikes and e-scooters in route planning (Route options, off by default): routes can start or end on a rented vehicle, with a link to the provider's app.
- Notifications for disruptions on saved lines: alerts and cancelled departures, checked on opening and in the background (Settings → Notifications).
- Sort routes by departure, fastest, fewest changes or least walking.
- Share arrival: send your live arrival time from a route or trip; when a followed trip runs late, Publit offers to send the new time.

### Faster
- The station map uses MapKit directly: line routes are grouped by colour into few overlays, vehicles glide between positions instead of being redrawn, and pins cluster.
- Map data loads only for the visible area and only while the map is on screen; lines and vehicles appear from street level, rentals when zoomed in further. Answers are decoded and simplified off the main thread and cached briefly.
- Line search uses one request for all departures nearby (cached 30 min); timetables for a day are cached for hours.

### Not included
- Vehicle occupancy: Transitous publishes no occupancy data, so Publit cannot show how full a vehicle is.

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

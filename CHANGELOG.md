# Changelog

## 0.6.0 (build 25)

### Map: layers, satellite and search
- The layers button opens a sheet instead of a menu. Map: Standard, Muted (paler streets, stations and lines stand out), Satellite (with names) and Satellite without names. Switches for 3D terrain and buildings (the map tilts when switched on), places of interest (shops, sights; Apple's transit icons stay off, the stations are Publit's own) and traffic. On the map: stations (new, can be hidden), lines, vehicles, bikes and scooters. Everything is kept for the next time.
- On satellite maps the map, station names and pins switch to dark, like Apple Maps; pin label outlines and vehicle arrows now follow dark mode.
- Search places and towns right on the map (field below the title): results prefer what is around the map's centre. Picking one flies there and marks it: a city or district as a whole (stations and live vehicles stay visible), a village, a stop, an address or a single place up close. Stops open their departures, places and addresses a sheet with distance, "Route here" (closes the map and plans from your position) and "Open in Apple Maps". Towns and districts leave the map free; tap the marker for the sheet.

### Fix
- Build 24 still did not compile. The real cause: the archive's "Delete archived tickets" action returned a number, which left the whole screen ambiguous for the compiler (reported at the toolbar).

## 0.6.0 (build 24)

### Navigation: a started trip guides you step by step
- "Start trip" (on the trip, or ▶ in the live bar) turns the trip screen into a guide in stages, like Moovit: walk → wait → ride → (change) → arrive. A row of stages at the top shows done, now (yellow dot) and ahead; tap one to look ahead, "Back to now" returns. The stage follows the live times and, while the screen is open, your position (at the stop early → waiting; still far from the stop → walking).
- Walk: distance and time left, the departure you are walking to (with platform, and "Walk faster to make it." when it gets tight), the next instruction ("In 35 m · Turn left onto Ludwigstraße") and the full directions with stairs and levels ("Take the stairs down (level −1)"). The router marks stairs and levels but hardly ever turns, so turns are derived from the path's shape; stairs follow the walking direction. "Open in Apple Maps" hands the walk to Apple Maps with spoken guidance. Off the path → "New route from here".
- Wait: line and direction, "Departs in 4 min", delay, platform, tight-change warnings, disruptions, stops and time to the stop to get off.
- Ride: "Get off at …", stops left and arrival with delay, "Now at …" / "Next: …", progress in the line's colour and all stops on a line with the yellow dot where you are. While the screen is open the position comes from GPS (laid onto the line, accepted within three stops of the live times), otherwise from the live stop times. Still at the stop well after departure → "Missed it?" with a new route from here.
- The map shows the stage's leg in full colour (the rest faded), you, the vehicle and the next turn, and moves to the stage.
- GPS is precise (every 5 m) only while the guide is open and the app is in front; nothing runs in the background.
- Starting a trip sets a get-off reminder for each ride when notifications are already allowed, and moves them with live delays; ending the trip removes them. Walking directions are kept with saved trips and refreshes.

### Fix
- Builds 22 and 23 did not compile ("ambiguous use of toolbar" in the ticket archive): the archive's menu is now typed toolbar content.

### Live bar
- A started trip shows like a running workout: a dark bar with a ring for the trip so far, "Live trip", what to do now, the line, and a big countdown to the next moment (leave, departure, get off). Tap opens the guide. Trips not started yet have ▶ to start them.

## 0.6.0 (build 23)

### Resource use
- Answers in memory keep their decoded form: going back to a screen, or a second screen showing the same departures, no longer decodes the same JSON again. The memory limit (24 MB) counts decoded answers at about three times their size.
- Live answers (departures, vehicles, trips; fresh for seconds) are copied to disk for offline use at most every two minutes per board instead of on every refresh. Large disk use within a session is pruned right away instead of at the next launch.
- In the background, kept answers shrink to the newest 4 MB (and map stops are dropped); on a memory warning all of them go. A smaller suspended app is less likely to be ended by iOS.
- The freeze watchdog sleeps while Publit is in the background, and the diagnostic step trail is written at most every two seconds instead of on every step.
- Live refreshes of saved trips are written once after they settle (2 s) instead of the whole trip file on every refresh; edits are still written right away, and pending refreshes when the app goes to the background.
- In Low Power Mode, or when the phone is hot, open screens (Nearby, map vehicles, Plan, trips, lines, shared routes, live bar) refresh half as often. Live Activities and reminders keep their timing.

## 0.6.0 (build 22)

### Tickets: archive
- Expired tickets stay in the list for one more day (delayed trip, late check), then move to the new archive at the end of the ticket list ("Archive", with count). The archive is sorted by month, newest first, and searchable (title, operator, stations, passenger, ticket number, notes) – e.g. for refunds or expense reports. Nothing is deleted automatically; "Delete archived tickets" removes them with their originals after a confirmation.
- Any ticket can be moved to the archive by hand (long press on the card, or the ⋯ menu of the ticket), e.g. a used-up undated ticket; "Move back to tickets" brings it back (an expired one then stays in the list). Archived tickets are no longer offered for trips.

### Tickets: better recognition
- Operators: the issuer in a UIC rail barcode wins, otherwise the operator named nearest the top (partners and sales agents further down no longer win). 30 more operators and transport associations (Italo, Trenord, Eurostar, iryo, PKP Intercity, MÁV, ZSSK, SŽ, DSB, SJ, Leo Express, BLS, ZVV, PostAuto, RATP, VOR, OÖVV, VVT, Salzburg Verkehr, Verbund Linie, Graz Linien, Linz AG, Wiener Lokalbahnen, HVV, VBB, MVG, RMV, VRR, VVS, KVB, VGN, DPP).
- Products: Standard-Ticket, Einfach-Raus-Ticket, Quer-durchs-Land, Bayern-Ticket, Niedersachsenticket, Semesterticket, Jobticket, Kurzstrecke, Streifenkarte, (Super)Sparbillett, GA, Navigo, Travelcard, Frecciarossa; BahnCard/Vorteilscard/Halbtax only when nothing else matches. Ticket types in more languages (Dutch, Spanish, Portuguese, Polish, Czech, Swedish, Hungarian, Turkish).
- Route: timetable rows as on DB/ÖBB tickets ("Berlin Hbf 14.10. ab 08:30 … München Hbf an 12:31": first departure to last arrival), "A → B → C" (B as via), "von … nach … über …", French/Italian/Dutch/Swedish "de … à …", "da … a …", "van … naar …", "från … till …", more labels (Abfahrtsbahnhof, Zielbahnhof, Einstieg, Origen/Destino, Vertrek/Aankomst …). New "Via" field in the editor and on the card.
- Validity: shared-month ranges ("14.–20.10.2025", "28.12.–03.01.2026"), dd/mm/yy, dd-mm-yyyy, "Oct 14, 2025", "14th October 2025", "14 de octubre de 2025", month names in 12 languages, French times ("08h12"); a length printed with the start ("Gültig 90 Minuten", "24-Stunden-Karte", "7 Tage gültig ab …") sets the end; return tickets cover outbound to return day; validated/activated times count as start; more purchase-date words are ignored.
- Passenger: more labels (Passager, Nome, Naam, Pasażer, Cestující …), traveller counts ("2 Erwachsene", "1 Adulto"; not "bis zu 5 Personen") and reductions (BahnCard 25/50/100, BC 50, Vorteilscard, Halbtax, Carte Avantage, Railcards) are added, e.g. "2 Erwachsene · BC 50"; advertising lines are skipped.
- Class: "Klasse: 2", "KL. 1", "2e klas", "1. třída", "Klasa 2", "Second/Standard Class", "première classe" ….
- Price: totals before other prices ("Gesamtbetrag" before "Fahrpreis"), tax lines ("MwSt 19 %") ignored, "2 x 19,90 € = 39,80 €" gives the result, thousands separators ("CHF 1'250.00"), "Fr. 12.80", "19,– €", more currencies.
- Ticket numbers: many more labels (Bestellnummer, Vorgangsnummer, Référence du dossier, Codice prenotazione, Localizador, Boekingsnummer, Numer biletu, Číslo dokladu, Bokningsnummer …).
- Patterns are compiled once, so reading a page is much faster.

## 0.6.0 (build 21)

### Diagnostics
- The diagnostics file now records more than freezes: crashes and hangs reported by iOS (MetricKit, delivered at the next launch, with the stack of the thread that crashed), unexpected exits (the app ended while it was open – crash, watchdog or out of memory), memory warnings, and failed requests (network error code, HTTP status, or the field that could not be read in an answer). The same error within 5 minutes is noted only once.
- Each entry has a header with kind, time, version and build, device and iOS version, then the last 40 steps (screens, taps, requests with status and duration).
- Settings → Diagnostics shows the counts, "Share diagnostics" (one text file with device, language, time zone, memory, power and thermal state, the current steps and all entries), "Report a problem" (opens a new GitHub issue with version, device and counts filled in) and "Delete diagnostics".
- Still no places, stops or tickets in the log; nothing leaves the device unless shared.

## 0.6.0 (build 20)

### Design "Ink & Dot", first screen: Nearby
- New design language (docs/design: principles, tokens, clickable prototype): flat opaque cards on a warm grey ground, glass only for floating controls (tab bar, live trip bar), ink instead of a brand colour, the logo's yellow dot only for "you" and "live".
- Nearby: each station heads its own card (bold name, distance; the nearest stop has the yellow dot) instead of a grey header above it; cards on the new ground; buttons and links in ink.
- Departure boards (Nearby and a station's departures): the minutes are the big figure ("4 min", orange when late), clock time, delay and Live/Timetable small underneath; a cancelled departure shows its time struck through in red. Rows are centred vertically.
- Mode chips everywhere: the selected chip is ink (black, white in dark mode) instead of blue.
- Live trip bar: progress drawn as the logo's stroke with the yellow dot at the current position; hairline border unless late or cancelled; corner radius 22 like the cards.
- Other screens are unchanged for now. Not yet seen on a device.

## 0.6.0 (build 19)

### Sharing
- Shared links now carry the route itself instead of this phone's saved-trip ID, so they work for anyone with Publit and on any device. The route (Transitous itinerary ID, compressed), start, destination and departure are in the link; the receiving iPhone fetches it again from Transitous with live times.
- "Share arrival" (before arrival) sends the arrival text plus that link; after the trip the button is "Share trip". Departure boards have "Share departures".
- Links are https (`https://elija-7580.github.io/Publit-/open/#…`), so messengers make them tappable. The small page (`docs/open/index.html`) shows the route or stop, opens Publit, or offers Apple Maps / Google Maps for people without Publit. The part after `#` stays in the browser. Needs GitHub Pages: Settings → Pages → Deploy from a branch → `main` / `/docs`.
- Opening a route link: if it is one of your saved trips, that trip opens; otherwise the route with live status (refreshed every 90 s) and "Save trip". If Transitous no longer knows the route, "Search this route" fills Plan with the same places and time.
- Calendar entries link to the route too (URL field `publit://route?…`, notes with the web link), so they also open on another device or after the trip was deleted.
- Not yet confirmed on a device. The link includes the exact start point (e.g. home), as any shared route does.

## 0.6.0 (build 18)

- Trip tickets: several tickets for one trip are all shown, oldest first. A ticket added from a trip now always belongs to that trip; before, only tickets recognised as a single ticket were linked, so one recognised (or changed on the check screen) as a day pass, return ticket or other could drop out of the trip. The ticket section on the trip lists all tickets instead of the first three.
- Tickets added in the wallet without a trip now also show on a trip when their dates cover its departure, like passes. Not yet confirmed on a device.

## 0.6.0 (build 17)

- Live trip bar: a trip that is under way now shows as a bar at the bottom of every tab, above the tab bar. It appears for a trip started with "Remind me to leave", otherwise for a saved trip from 30 minutes before departure until 5 minutes after arrival.
- The bar shows the line of the current or next vehicle (or walking/arrival), the status ("Leave in 4 min", "Change at …", "Arrived"), the delay and a progress line. A tap opens the trip; the x hides the bar for that trip. While visible it updates the times every 90 seconds.
- Not yet confirmed on a device.

## 0.6.0 (build 16)

- Freeze log from build 15: no more freezes on the trip screen. Two short ones remain: 3.2 s when opening "Where to now?" (the same SwiftUI loop asking itself for the next update), and text layout while the app went to the background.
- "Recently searched" showed its time with `Text(date, style: .relative)`, which redraws itself every second. It now shows the time to the minute from the shared minute clock ("5 minutes ago", "now"). Likely cause of the 3.2 s, not confirmed on a device.

## 0.6.0 (build 15)

- Station map: the mode filter was sometimes not drawn (an empty strip under the bar) while its chips still took taps (screenshot from build 14). It was a horizontally scrolling row; on the map it is now one fixed row of symbols (All, Train, S-Bahn, Metro, Tram, Bus, Ferry) without scrolling, on a plain background. VoiceOver reads the mode names. Not yet confirmed on a device.
- Plan: the symbol legend (walk, change, …) under the routes is gone; the start and end time of the time axis stay.

## 0.6.0 (build 14)

### Plan
- No "Quick" section. Choosing From or To lists Home and Work first, then the current location, other saved places and recent places.
- The swap button sits between From and To on the right, not in the navigation bar.
- "To the first stop" is no longer on the Plan screen (it is in Route options, also reachable from Settings); Route options is one small line.
- Routes load after "Search routes" once both ends are set. After that, changing places, time or options searches again by itself; clearing the destination starts over. A recent search or "Plan again" searches at once.

### Station map: stations and vehicles missing at times
- An area counted as loaded as soon as its stations were downloaded, before their pins were made. If that was cut off (map closed, app in the background), the area stayed empty until the map was moved far enough. It now counts only once the pins are there.
- A failed station download is tried again after 5 s (before: only when the map moved), with a short note.
- After returning to the map, the live layer (lines and vehicles) loads again at once instead of after up to 30 s.
- The first map position is used even if MapKit reports no region change for it.

## 0.6.0 (build 13)

- Build 12 fixed the freeze on the trip screen (confirmed on the device).
- Station map: the mode chips (Train, Bus, …) have their own space below the navigation bar instead of floating over the map. They could end up hidden, and then an active filter hid stations and vehicles without showing why.
- Stops have "Route here" and "Route from here": both open the Plan tab with the stop as destination or start (the other end stays). From the station map, the map closes so Plan is visible.
- Plan is for planning only: From/To, time, options, Home/Work and recent searches. Saved trips moved to Saved: upcoming trips right below Home and Work, past trips on their own screen ("Plan again" switches to Plan).

## 0.6.0 (build 12)

### Freeze on the trip screen (freeze log from build 11)
- The call stacks show no app code: the main thread is inside SwiftUI's drawing, and while drawing SwiftUI asks itself for the next update (`requestUpdate(after:)`) again and again, until about 15 s have passed: the period of the trip screen's timeline. After the trip has loaded it repeats for another ~15 s.
- All timelines (`TimelineView`) are replaced by plain clocks: departure countdowns read one shared minute clock, the trip and map-vehicle screens keep their own time and update it every 15 s, the route status every 30 s, the line map every 5 s. Nothing else changes on screen. Likely cause, not confirmed on a device.
- The fixed timeline start from build 10 is removed.

## 0.6.0 (build 11)

### Better freeze log
- The log from build 9/10 shows the freeze starting as soon as a trip opens, before its data has loaded (7.5 s), then about 15 s more after loading. It had no build number, so it is unclear which build was running.
- Each freeze entry now has the build number and device model, and the main thread's call stack (function names from the app and iOS) at 2, 5 and 8 s. That shows where the app is stuck. No stack is taken while Xcode's debugger is attached (it would stop on the signal used).

## 0.6.0 (build 10)

### Freeze on the trip screen (freeze log from build 9)
- Still about 15 s without response after tapping a departure in Nearby, even for a short trip (13 stops, 102 map points), and already about 2 s while the trip screen opens, before the map is shown. So neither the map's size nor the list refresh explains it.
- What the trip and route screens share is "Show ticket" in the navigation bar: an item that is empty when there is no ticket, with its ticket sheets inside the bar. It is now added only when there is a ticket, and the sheets hang on the screen. Likely cause, not confirmed on a device.
- Periodic timelines (trip, route, line, map vehicle) use a fixed start instead of restarting their schedule on every redraw.

## 0.6.0 (build 9)

### Freeze when opening a trip from Nearby (freeze log from build 8)
- The log showed a 14.6 s freeze one second after opening a trip from the Nearby board, right after returning to the app. Likely cause: the board first shows the last saved departures, then the fresh ones arrive with new live times. A departure's list ID contained its live time, so a new delay made it a different row, and the trip opened from that row was closed while it was still open. Not yet confirmed on the device.
- Departure IDs now use the timetable time; repeated departures in a response appear once.
- Trips open from the Nearby board by value, so they stay open when the board refreshes or the departure leaves it.
- Trip screen: stops, alerts and the map shape are worked out once per load. The map is redrawn only when the route or the vehicle moves, and has no title labels.
- Alerts with the same priority and title keep a fixed order (before, the order could change on every redraw).
- Freeze log also notes when Nearby and a trip have loaded (counts only).

## 0.6.0 (build 8)

### Freezes (reported as "scene-update" hangs on 0.1.0 and 0.6.0 build 7)
- Both device reports show the main thread busy laying out views for more than 10 s, the second while a back swipe started. The reports contain no app code, so the screen is not known yet; the changes below remove likely causes and are not confirmed on a device.
- Route actions: the button grid is no longer a `LazyVGrid` inside a list row; a fixed two-column layout measures each button once.
- Route summary and connection legend choose their layout by text size instead of `ViewThatFits`, so a row cannot switch height between layout passes. The line chain places badges exactly as it measured them.
- "Add ticket" sheet on the route screen is attached once instead of to every ticket row.
- A trip unsaved on the route screen is deleted shortly after the back animation, not during it. Closing a screen with nothing to delete no longer redraws other screens.
- New: Settings → Diagnostics. If the app does not respond for 2 s or more, the time and the screens opened just before are written to a local file that can be shared. Only fixed screen names and times; nothing leaves the device unless shared.

## 0.6.0 (build 7)

### Fixes from device testing (need confirmation on the device)
- Paper-ticket scan: add the missing camera usage description (`NSCameraUsageDescription`, 15 languages); without it iOS stops an app that opens the camera.
- Ticket import: a ticket appears only after its document and metadata are written; write errors are reported, and a failed save leaves no ticket or orphan document behind. Photo/file pickers no longer cancel the running import. No automatic logo lookup while saving.
- Live data: malformed route shapes, invalid coordinates, non-finite distances and extreme delays are rejected; MapKit only gets valid coordinates. The reported live-data crash had no crash log, so its cause is not confirmed.
- Widget: stop search asks for stops only and skips entries without a valid ID or coordinate.

### Loading
- Nearby: one load per location/mode change instead of competing loads, smaller first request, last board shown first, small GPS movements reuse the board.
- Map: panning and zooming no longer cancel loading; stations, vehicles and rentals load separately and stay visible. Loaded areas are reused; stop grouping runs off the main thread. A failed live layer shows a note and retries after 10 s.
- Lines open with the departures already shown; Plan does not repeat the same search within 45 s.
- No timings measured on a device for this build; server response time is outside the app.

### Navigation and layout
- Lines tab removed: saved lines and stops are in Saved, with "Find a line". Plan shows the next saved trips.
- Route actions: full-width divider under Start trip, even two-column grid with wrapping labels (one column with large text).
- Connections: legend and "How to read connections" explain the timeline bars (later departures start farther right; coloured = ride, grey = walk, dotted = wait). Timelines can be turned off in Settings.
- Saved trips: tapping "Saved" on an open trip unsaves it, but the trip stays on the device until that screen closes, so it can be saved again. Opening a stop or ticket from the trip does not count as closing; after a relaunch the trip is still saved.
- Settings: travel preferences (route options, timelines, map layers).
- Map: larger labels; bike and scooter pins show type, availability and provider and open details. Walking lines use crisp dashes.
- Launch animation: only the moving icon, no spinner underneath.

### Getting to the first stop
- Plan: choose Walk, Bike (Bike & Ride) or Car (Park & Ride) to the first stop. Walking variants stay in the list for comparison. Shared bikes/scooters stay in Route options. Park & Ride is slow on the Transitous server (about 20–25 s in tests) and uses a 45 s timeout.

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

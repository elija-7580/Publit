# Publit on the Apple Watch

The watch app (target `PublitWatch`, watchOS 10) carries what you need to take a connection with the watch alone: **tickets first**, the trip under way, saved trips and stops, nearby departures, and a search that makes a trip of your own. It uses the same data as the iPhone (Transitous, no account, no server of its own).

## Screens

| Screen | What it does |
|---|---|
| Home | Tickets valid now (one tap opens the code), "Tickets", the live tile of the trip under way, Where to?, Nearby, Saved |
| Tickets | Grouped as on the iPhone (valid now, upcoming, without dates, expired). A ticket shows its code on a white plate at full width, then the details (validity, route, passenger, reference) |
| Trip | Vertical pages (Digital Crown): **Overview** first, then one page for every ride and longer walk. A trip under way opens on the leg you are on and follows the clock |
| Trip, overview | "Not reliable here" card first where data is missing, then times, status, **Tickets** button, **Map** button, Start/End trip, Save trip |
| Trip, one leg | Line, direction, from and to with times, platform (and "Platform changed"), stops, alerts, and its own **Map** button that shows exactly this section (also in the top bar of every page); a button in the map switches to the whole trip |
| Map | Apple Maps in muted style: lines in their colours, walks dotted, your position |
| Where to? | From and To (current location, saved places, dictation), up to eight routes (walking joins when it is a real choice), later connections, coverage card. A route opens like a saved trip and can be saved |
| Nearby | The nearest stops with their next departures (radius steps as on the iPhone), coverage card |
| Saved | Upcoming trips, Home and Work, stops (departures, "Route here"), places, past trips |

Everything the iPhone has sent stays on the watch, so these screens work without the iPhone nearby. Times of a trip under way are loaded by the watch itself (every 1 to 5 minutes while the app is open, never for a trip far in the future or long over).

## How it is connected

`Sources/Models/WatchSync.swift` and `WatchTrip.swift` hold the data and the rules (pure Swift, tested on Linux in `Tests/WatchSyncTests.swift`). The transport is WatchConnectivity between the two devices; nothing goes to a server.

* **iPhone to watch**: one `WatchSnapshot` (JSON file via `transferFile`): up to 8 trips (the started one, then the next ones), saved places, up to 12 tickets without their documents. A new snapshot goes out at once when something that is listed changes, and with refreshed times at most every 90 seconds. Older snapshots still waiting are cancelled. The snapshot is slimmed (`forWatch()`): no walking steps, alternatives or fare data, notices cut to two headlines; of a ticket, the document, notes, logo and the content of the code stay on the iPhone (the watch gets the picture of the code).
* **Code pictures**: CoreImage does not exist on watchOS, so the iPhone draws every code (`WatchCodeImage`, same renderer as the ticket view): black on a white plate as wide as the watch screen, every module a whole number of pixels, nothing smoothed. The watch tells the iPhone its screen width once (`resend` request), so the size fits every watch. Codes that cannot be drawn again (EAN, ITF …) are cut out of the original page.
* **Watch to iPhone**: changes made on the watch (save a trip, start or end a trip, save a place) are requests (`WatchIntent`). The watch shows the change at once and keeps the request until the next snapshot lists it as confirmed (`acks`); requests older than 14 days are dropped. The iPhone carries them out with the same code as its own buttons (reminders, Live Activity, `TripSession`).
* A trip saved on the watch has no walking directions. The iPhone loads a fresh copy right after saving it, and the watch gets it back with the next snapshot.

## Tickets and privacy

* Tickets are sent to the **paired Apple Watch only**. Settings, section "Apple Watch", has the switch "Tickets on Apple Watch" (on by default). Off: no ticket and no code leaves the iPhone, the watch drops what it has, and says so on the Tickets screen.
* The code pictures sit in the app's folders on both devices (iPhone: `Application Support/Publit/watch-codes`, with file protection until first unlock; pictures of removed tickets go after a day). Documents (PDF, photos) never go to the watch.
* Coverage warnings run on the bundled atlas, offline. The watch asks Transitous directly for places and departures, like the iPhone does.

## Coverage warnings on the watch

The same atlas and the same words as on the iPhone (`Sources/Models/Coverage.swift`, see [COVERAGE.md](COVERAGE.md)): "Not reliable here", the area, what is missing. Shown in Nearby (also when nothing is found), in the planner when From or To lies in such an area, in a trip's overview, and in a stop's departures.

## Testing

* `swift test` (Linux CI): `WatchSyncTests` (snapshot, trimming, requests, acks, sync policy, trip pages, map box, route lists) and `CoverageTests`.
* `Tests/WatchCodeImageTests.swift` (iOS): the plate has the width the watch asks for and the code can be read back by the system's code detector.
* CI workflow `watch.yml` (branches `feature/watch**` and `watch/**`, or by hand): type-checks the watch and iPhone targets, builds the `PublitWatch` target for the watchOS simulator and runs the demo screens there (screenshots on the branch `watch-results`), and builds the iPhone app (which embeds the watch app) and takes screenshots of the coverage warnings on iPhone and iPad (branch `iphone-results`).
* Demo screens, debug builds only: start the watch app with `PUBLIT_WATCH_DEMO=<screen>` (`home`, `trip`, `leg`, `leg-s8`, `tripmap`, `legmap`, `tickets`, `ticket`, `saved`, `plan`, `plan-gap`, `nearby`, `gap`). They use made-up trips and a made-up ticket (`Watch/WatchDemo.swift`, `Sources/App/DesignSampleTrip.swift`); nothing is saved or sent.

## Not covered yet

* The connection itself (WatchConnectivity) cannot be tested on a simulator that is not paired to an iPhone simulator; it needs a real pair. Please check on your devices: ticket arrives, code shows, a trip saved on the watch appears on the iPhone, "Start trip" on the watch starts the Live Activity.
* Whether scanners read a code from the watch screen depends on the watch (brightness, glass). The plate and whole-pixel modules are made for it; it has to be tried at a real gate. Rotating codes (operator apps) cannot be copied, as on the iPhone.
* No complication and no Smart Stack widget yet; no notifications on the watch itself (iPhone notifications are mirrored by the system when the iPhone is locked).
* Trips saved on the watch while the iPhone is out of reach reach the iPhone when it is back (the system queues the transfer).

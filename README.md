<p align="center">
  <a href="https://publit.eu">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="docs/readme/hero-dark.webp">
      <img alt="Publit – public transport, without the noise. Live departures, every route on one timeline and your trip on the lock screen, for iPhone, Apple Watch and Android." src="docs/readme/hero-light.webp" width="100%">
    </picture>
  </a>
</p>

<p align="center">
  <a href="https://apps.apple.com/app/id6824481988"><img alt="Download on the App Store" src="https://img.shields.io/badge/App_Store-Download-000000?style=for-the-badge&logo=apple&logoColor=white"></a>
  <a href="https://github.com/elija-7580/Publit-Android/releases/tag/native-latest"><img alt="Android APK (beta)" src="https://img.shields.io/badge/Android-APK_beta-3DDC84?style=for-the-badge&logo=android&logoColor=white"></a>
  <a href="https://publit.eu"><img alt="publit.eu" src="https://img.shields.io/badge/publit.eu-Website-FFC531?style=for-the-badge&logoColor=black"></a>
</p>

<p align="center">
  <b>A free, open-source transit app for iPhone, Apple Watch and Android.</b><br>
  Built on the open <a href="https://transitous.org">Transitous</a> routing service. No ads, no account, no tracking.
</p>

<p align="center">
  <a href="https://github.com/elija-7580/Publit/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/elija-7580/Publit/actions/workflows/ci.yml/badge.svg"></a>
  <img alt="iOS 17+" src="https://img.shields.io/badge/iOS-17%2B-black">
  <img alt="watchOS 10+" src="https://img.shields.io/badge/watchOS-10%2B-black">
  <img alt="SwiftUI" src="https://img.shields.io/badge/Swift-SwiftUI-orange">
  <a href="LICENSE"><img alt="License: AGPL-3.0" src="https://img.shields.io/badge/license-AGPL--3.0-blue"></a>
</p>

<br>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/readme/screens-dark.webp">
    <img alt="Nearby, Plan, Route, Live trip and Map screens" src="docs/readme/screens-light.webp" width="100%">
  </picture>
</p>

## What Publit does

- **Departures around you.** Every stop nearby on a live map, with line, platform and real-time minutes.
- **Every route on one timeline.** Compare connections at a glance and see where you change and where it gets tight.
- **Smart routing.** Publit learns how fast you change trains from your own trips, on your phone, and warns you before a change won't work.
- **Your trip, live.** When to leave, when to get off, on the lock screen, in the Dynamic Island and on your watch.
- **Tickets in the app.** Add one from a PDF, a photo or a screenshot; Publit reads it on the device.
- **Works abroad like at home.** Timetables and live data from [Transitous](https://transitous.org), wherever there is open data. [Coverage map](https://publit.eu/abdeckung/)
- **15 languages**, light and dark, widgets, Siri and Shortcuts.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/readme/more-dark.webp">
    <img alt="Tickets, dark mode, Apple Watch and the Android app" src="docs/readme/more-light.webp" width="100%">
  </picture>
</p>

## A community project

Publit is built in the open and shaped by the people who use it.

- 💡 **Wish for a feature** and vote on others: [publit.eu/wuensche](https://publit.eu/wuensche/)
- 💬 **Talk to us** on [r/Publit](https://www.reddit.com/r/Publit/) or at [support@publit.eu](mailto:support@publit.eu)
- ❤️ **Support Publit** with a monthly or one-time donation: [publit.eu/unterstuetzen](https://publit.eu/unterstuetzen/) or [GitHub Sponsors](https://github.com/sponsors/elija-7580)
- 🌍 **Help translate** the app: [open a translation issue](https://github.com/elija-7580/Publit/issues/new?template=translation.md)

**Source code:** iOS and watchOS here · Android in [Publit-Android](https://github.com/elija-7580/Publit-Android/tree/native-android) (native Kotlin/Compose, MapLibre maps; still in testing, Google Play release pending).

---

## For developers

This part covers the code: architecture, build, tests and CI. Every feature and screen is described (in German) in [docs/FUNKTIONEN.md](docs/FUNKTIONEN.md). Features, coverage and privacy policy for users live on [publit.eu](https://publit.eu/) ([Features](https://publit.eu/features/) · [Coverage](https://publit.eu/abdeckung/) · [Privacy](https://publit.eu/privacy/)).

### Status

`v0.1.1`, build 96. `0.1.0` (build 64) was the first App Store release; earlier builds were TestFlight only. Changes per build: [CHANGELOG.md](CHANGELOG.md).

### Architecture

```mermaid
flowchart LR
  subgraph Device["iPhone / Apple Watch"]
    App["Publit (SwiftUI)"]
    W["Widgets + Live Activity"]
    Watch["Watch app"]
    Share["Share extension"]
    Store[("JSON stores<br/>on device")]
  end
  App -- "HTTPS, identifying User-Agent" --> T["Transitous API<br/>(MOTIS routing, GTFS + GTFS-RT)"]
  App -. "opt-in" .-> G["Google Places / Maps SDK"]
  App -. "optional" .-> S["pass-signer<br/>(Cloudflare Worker)"]
  App --- Store
  W --- Store
  F["feeds/amtab-gtfsrt"] -- "GTFS-RT upstream" --> T
```

| Target | Platform | What it is |
| --- | --- | --- |
| `Publit` | iOS 17+ | Main app, SwiftUI. App Intents / Siri shortcuts, Live Activities, local notifications |
| `PublitWidgets` | iOS | WidgetKit departures widget and the live-trip Live Activity |
| `PublitWatch` | watchOS 10+ | Live trip, saved trips, tickets, trip search and nearby departures on the watch ([docs/watch.md](docs/watch.md)) |
| `PublitShare` | iOS | Share extension: open a shared map link or address in Publit and plan a route to it |
| `PublitTests` / UI tests | iOS | Unit tests with recorded fixtures, UI tests that also produce the screenshots |
| `Package.swift` | Linux / macOS | The platform-independent core (API client, models, routing logic) as a SwiftPM package, so it builds and tests without Xcode |

The Xcode project is generated from [`project.yml`](project.yml) with XcodeGen; there is no checked-in `.xcodeproj`.

#### Source layout

```
Sources/
  App/            entry point, tabs, app info, privacy manifest, InfoPlist / shortcut strings
  API/            TransitousClient, response + map stop caches, trip refresh, live source adapters, Google Places
  Models/         transit models, routing (SmartRouting, TransferRisk), trip progress/trace, map layers, fares, alerts, coverage atlas (missing data), watch sync
  Stores/         favourites, plan state, search history, JSON file store, data export
  Location/       CoreLocation wrapper, walking pace
  Notifications/  leave / get-off reminders, line alerts, trip change alerts, Live Activity session
  Tickets/        ticket recognition, Apple Wallet passes
  Intents/        App Intents (Siri, Shortcuts)
  Shared/         code and String Catalog shared with widgets and watch
  Util/           polyline decoder, formatting
  Views/          SwiftUI screens
Widgets/  Watch/  Share/     extension targets (Widgets/ too)
tools/coverage/   generator of the coverage atlas (monthly)
Tests/            unit tests + Fixtures/ (recorded API responses), UI/ (UI tests)
feeds/            data converters contributed to Transitous
services/         pass-signer (Cloudflare Worker for Wallet pass signatures)
scripts/          CI signing helper
docs/             design, data sources, coverage, CI, localization notes
```

#### Data

- **Routing, timetables, real time:** [Transitous](https://transitous.org) (MOTIS API). Publit follows the [Transitous API policy](https://transitous.org/api/): open source, non-commercial, identifying User-Agent, visible attribution. Responses are cached (`ResponseCache`, `MapStopCache`) to keep load on the community servers low.
- **Map:** Apple Maps by default; Google Maps SDK only if chosen in Settings and an API key is set.
- **Place search:** Transitous geocoding by default; Google Places is opt-in (key via the `GOOGLE_API_KEY` build setting, empty otherwise).
- **Storage:** everything (favourites, trips, tickets) stays on the device as JSON files. No account, no analytics, no backend except the optional pass signer.
- **Upstream fixes:** where a city's feed is missing or broken, it is fixed upstream so every open app benefits, e.g. [`feeds/amtab-gtfsrt`](feeds/amtab-gtfsrt) converts the Bari city bus (AMTAB) real-time data into standard GTFS-Realtime.

- **Missing data:** `Sources/Models/Coverage.swift` knows where Transitous has no or only partial data (generated atlas, offline) and the app says "Not reliable here" with what is missing: Plan, route, Nearby, stops, search and a map layer.

Details: [docs/DATA-SOURCES.md](docs/DATA-SOURCES.md), [docs/COVERAGE.md](docs/COVERAGE.md), [docs/tickets.md](docs/tickets.md), [services/pass-signer](services/pass-signer).

### Build

Requirements: macOS, Xcode 15 or newer, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
xcodegen generate
open Publit.xcodeproj
```

Set your Apple team under Signing & Capabilities (or `DEVELOPMENT_TEAM` in `project.yml`). Run the tests with ⌘U.

Core only, no Xcode needed (also on Linux):

```bash
swift test
```

### Tests and CI

| Workflow | Trigger | Does |
| --- | --- | --- |
| [`ci.yml`](.github/workflows/ci.yml) | push to `main`, PRs | Core tests on Linux (Swift 6), feed converter tests (Python, Node), iOS build + unit tests + UI tests on macOS 15, uploads screenshots, publishes results to the `ci-results` branch |
| [`design.yml`](.github/workflows/design.yml) | manual, `design/**` branches | Screenshots of the trip screens, light and dark |
| [`testflight.yml`](.github/workflows/testflight.yml) | tags `v*` | Archive, cloud signing with the App Store Connect API key, upload to TestFlight (no Mac needed) |

Tips for faster runs: [docs/ci.md](docs/ci.md). Performance notes: [docs/performance.md](docs/performance.md).

### Localization

15 languages (en, de, fr, it, es, pt-PT, nl, pl, uk, ro, cs, sv, el, hu, tr) in String Catalogs (`*.xcstrings`); `LocalizationTests` checks that every catalog has all languages, keeps placeholders and uses correct plural forms. Guide: [docs/localization.md](docs/localization.md).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Publit is an independent project and does not use code, assets or data from other transit apps.

## Data and attribution

Routing and timetables: [Transitous and its data sources](https://transitous.org/sources/). Map data © [OpenStreetMap contributors](https://www.openstreetmap.org/copyright).

## License

AGPL-3.0-only, see [LICENSE](LICENSE). A commercial license is available from the author; details, earlier MIT versions and third-party terms in [LICENSING.md](LICENSING.md). The Publit name and logo are not licensed, see [TRADEMARKS.md](TRADEMARKS.md). Contributions require the [CLA](CLA.md).

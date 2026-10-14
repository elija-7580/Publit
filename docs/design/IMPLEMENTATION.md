# Ink & Dot implementation — build 32

The reference is `prototype.html` (the eight light/dark phone screens), not the earlier generic system-list layout.

## Production views
- **Nearby:** inline logo/title, search and overflow actions, text-only mode chips, one opaque rounded card per station. Departure rows put a small line badge, destination and minutes on one line; platform and live indicator are secondary. Pinned destinations, map, the next trip and settings remain in the overflow menu.
- **Plan:** inline title, one From/To panel with swap, Now/Depart/Arrive/Options chips, separate connection cards. Each connection shows its time range, total duration, line/walk chain, thin timeline and leg-minute labels. Filtering, sorting, map comparison, pagination and recent-search deletion are preserved.
- **Started trip:** arrival card and a complete time/stop/leg-duration timeline before actions and detailed guidance. Maps, walking directions, GPS progress, voice cues and replanning remain below the overview.
- **Tickets:** subscriptions/period/day passes with their actual square code, compact grouped single-ticket rows. Original files and codes are never substituted with decorative QR patterns.
- **Dock:** opaque rounded four-tab navigation and a compact matte live bar above it. Selected tab/progress use the yellow signature dot. Swipe up opens the trip. The measured combined dock height is reserved in scrollers; keyboard presentation hides the dock. Trip sheets have navigation without a redundant live bar.
- **Review:** the PDF/image field-assignment action precedes the large ticket preview. Embedded PDF text gives exact selectable boxes on unrotated pages; images/scanned/rotated PDFs use local Vision OCR. Assignments change only the draft until Save.

## Verification boundary
- Core tests run through SwiftPM on Linux; they do not type-check or render SwiftUI, UIKit, Vision or PDFKit.
- `NativeLayoutTests` covers `DurationFigure` initialization and embedded PDF hit-box normalization on iOS.
- UI test F18 uses production NearbyView, PlanView, LiveTripView and PassWalletView with isolated deterministic fixtures. It captures light/dark and large-text states using the existing CI screenshot mechanism.
- UI tests use stable dock/root/route identifiers, not obsolete native tab-bar queries.
- Build 31's confirmed iOS failure was `DurationFigure.swift:6: missing argument for parameter 'wrappedValue' in call`; build 32 gives its `@ScaledMetric` a declaration-time default as well as the custom initializer.
- New native compilation, screenshots and device behavior must still be checked after CI runs. A green core result alone is not native or visual approval.

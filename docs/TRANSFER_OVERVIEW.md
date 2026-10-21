# Transfer overview and train-division notices

## Scope

First implementation in the main (iOS) Publit repository, merged via PR #41 (60e338c). Prepared for TestFlight as version 0.6.0, build 62. No changes to the separate Android repository.

### Connection card

The shared `TransferCard` replaces the former minimal, private live-guide card. It is displayed:

- before each connecting transit leg in route details;
- while riding the incoming vehicle (next connection);
- on the connecting walk and while waiting for the outgoing vehicle.

Each endpoint shows station, line, service identity where supplied, direction, local time, platform and platform change. Unknown platforms are explicitly labelled. Station identity is checked separately from platform identity. Total connection time and the walk-adjusted buffer are distinct; a negative buffer is never rendered as positive spare time. Cancellations take precedence over missed/tight warnings.

Time provenance uses MOTIS `arrivalTimestampReason` / `departureTimestampReason` where present (`OBSERVED`, `PROPAGATED`, `PREDICTED` vs `NO_RT_DATA` / `INCONSISTENT_RT`). Existing direct live overlays supersede original router provenance. Older saved trips without these optional fields retain their leg-level realtime fallback. This card describes the last-refreshed itinerary, not a guaranteed held connection or a live countdown from the phone clock.

### Train division

`TrainDivisionNotice` highlights explicit operator alerts in route details (even with collapsed stops), the boarding/ride guide and a train's stop view. The original heading, description and safe operator URL remain visible; the UI does not extract or invent a splitting station, carriage number, destination allocation or a command to move carriages.

Initial phrase detection covers German, English, French and Italian wording. All seven new UI strings have translations in all 15 existing app languages, in `Transfers.xcstrings`. Phrase detection is conservative and not exhaustive. Active-alert filtering and deduplication reuse existing alert rules. Non-rail vehicles do not receive the train-division card.

**A missing notice does not establish that a train will not divide.** The feature depends on the operator actually publishing an explicit alert in the data received by Publit. This is not comprehensive train-composition support.

## API findings and deliberate limits

Source: MOTIS public OpenAPI, https://github.com/motis-project/motis/blob/master/openapi.yaml (inspected 2026-10-21).

- `joinInterlinedLegs` defaults to `true`; setting it to `false` returns stay-seated sections with `interlineWithPreviousLeg=true`.
- That field means remaining on board through a service change; it is **not proof of a train division** and provides no front/rear carriage allocation.
- This change deliberately preserves the existing joined-leg default. Unjoining globally needs a separate audit of guide stages, get-off alarms, widgets, notifications, ranking and transfer counts; otherwise it could create false instructions to alight.
- No structured train-section or carriage-allocation field was found in the inspected Leg schema. An operator-specific composition source and verified trip matching are still needed for reliable section selection.
- No private operator API, scraping, additional network polling or background permission was introduced.

## Validation

Local Linux Swift 6.0.3: `swift test -Xlinker --allow-shlib-undefined` — 348 tests passed, including 11 new tests for connection endpoints/times, event provenance, delays/negative buffers, platform changes and missing platforms, station changes/cancellations, invalid/first legs, explicit division wording, false positives, source preservation, active-alert filtering and non-rail suppression. Catalog language/placeholder validation now includes `Transfers.xcstrings`.

`swiftc -frontend -parse` succeeds for all four changed SwiftUI files; `git diff --check` is clean. Syntax parsing is **not** native SwiftUI typechecking or a simulator run. Native iOS compilation, UI tests, Dynamic Type/VoiceOver and visual checks are pending CI/device verification.

Suggested manual checks:

1. Route with a same-station transfer: both lines, both platform numbers and local times are visible in Steps and on the incoming ride.
2. Station-to-station change: distinct station names remain visible; equal platform numbers must not imply the same platform.
3. Incoming delay consumes walking buffer: missed/tight message, never negative spare time formatted as a duration.
4. One endpoint has no realtime data: it remains labelled Timetable even if another event on that leg is live.
5. Explicit train-division alert: notice remains visible with collapsed stops; original operator destination/section instructions and link are retained.
6. No train-division data: no inferred front/rear recommendation or invented division marker.
7. German/English, largest accessibility text, light/dark: wrapping, warning contrast and operator-link accessibility.

## Release validation update (2026-10-21)

PR CI: Linux core and feed converter checks passed. The iOS job failed with the same four UI failures present on the base main commit 640f3f9: F02 get-off reminder, F04 Cancel button, F17 ticket review, F19 map long press. These failures are not waived as test passes. The user explicitly requested merge and TestFlight publication; PR #41 was merged with those known pre-existing UI issues documented. Release archive/upload remains a separate verification step.

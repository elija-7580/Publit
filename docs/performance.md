# Performance changes and verification

## Changes

- Station grouping indexes candidates by normalised name and memoises repeated
  names. It preserves the previous grouping semantics (name + 300 m radius).
- Concurrent live refreshes from an open trip and the foreground activity loop
  share one request. A 3-second result window absorbs staggered timers. Errors
  are not cached; subsequent requests may retry.
- Persisted trip, ticket and history snapshots are encoded and atomically
  written on an ordered utility queue, not in a SwiftUI event handler. Reloads
  flush earlier snapshots; critical ticket imports await completed storage.
- Ticket file loading, decoding and import writes run off the main actor.
  Display thumbnails are capped at 2048 pixels; a 6-item / 48 MiB cache limits
  retained images. Original source bytes remain unchanged.
- Number formatters are reused by locale. Clock formatters are keyed by locale
  and timezone, with bounded caches. Locale changes do not retain old formatting.
- Loading the previous nearby board uses a non-main-actor async path.
- Existing 300 ms place-search debounce remains. Token checks prevent an old
  cancelled search from replacing newer results or clearing its loading state.
  Cancelled plan searches no longer leave a stuck loading state.
- Points of Interest signposts cover transit requests, local saves, ticket
  import and ticket image loading. They log no location, ticket contents or URLs.

## Measured scope

The regression benchmark compares the previous and indexed grouping algorithms
on the same 1,200-record fixture, five runs each. In the Linux Swift 6.0.3 debug
workspace run: previous 28.860 ms, indexed 6.561 ms (4.40× faster). This measures
that algorithm and workload, not device FPS, app launch time or all API latency.
The test prints new results on each run and checks result parity. It does not
use a brittle fixed performance threshold.

A concurrency test submits 12 identical refreshes and verifies one loader call,
then verifies expiry and retry after errors. UI regression tests cover ordinary,
dark and large accessibility text layouts.

## On-device profiling

Use Instruments Time Profiler, Hangs, Allocations and Points of Interest on a
physical iPhone. Compare cold launch, 80-row departure refresh, repeated trip
open/close, a large ticket image and 10-minute active-trip tracking. Record main
thread stalls, frame hitches, peak memory, request count and battery impact.
No physical-device FPS or energy improvement has been claimed from CI results.

// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich
import Foundation

/// Late trains in a route search. Transitous plans Austria and other regions on the timetable; the
/// delays come from other operators afterwards (`LiveOverlay`). So a train whose timetable departure
/// has passed is missing from a "now" search although it is late and still leaves, and every refresh
/// first showed the routes without their delay until the live times came in again (feedback 27 Nov 2026:
/// "the train is late, the app shows it on time, then it is gone").
enum LateTrains {
    /// How far back a search looks for trains that are late enough to still be caught.
    static let lookback: TimeInterval = 30 * 60

    /// A route whose times came from another operator's live data (not from the router).
    static func hasOverlay(_ it: Itinerary) -> Bool {
        it.legs.contains { $0.isTransit && $0.liveSource != nil }
    }

    /// The first ride leaves at least a minute after its timetable time.
    static func isLate(_ it: Itinerary) -> Bool {
        guard let first = it.firstTransitLeg else { return false }
        return first.startTime.timeIntervalSince(first.scheduledStartTime) >= 60
    }

    /// A refresh without live times yet: a route already on screen with live times from another
    /// operator keeps them until the overlay has them again, instead of jumping back to the timetable.
    /// A late route the router no longer lists (its timetable time has passed) stays while it has
    /// not left (`now`).
    static func carry(_ fresh: [Itinerary], previous: [Itinerary], now: Date) -> [Itinerary] {
        let old = Dictionary(previous.filter(hasOverlay).map { ($0.routeKey, $0) }, uniquingKeysWith: { a, _ in a })
        var out = fresh.map { f in
            guard let o = old[f.routeKey], !hasOverlay(f) else { return f }
            return o
        }
        var known = Set(out.map(\.rideKey))
        out += previous.filter { hasOverlay($0) && isLate($0) && !$0.isCancelled && $0.startTime >= now }
            .filter { known.insert($0.rideKey).inserted }
        return out
    }

    /// Out of a search from `lookback` before `base`, with live times applied: the routes whose first
    /// ride was due before `base` but is late enough that the route has not left yet. Routes already
    /// listed (`known` ride keys) are left out.
    static func stillReachable(_ found: [Itinerary], base: Date, now: Date, known: Set<String>) -> [Itinerary] {
        var seen = known
        return found.filter { it in
            guard let first = it.firstTransitLeg, first.scheduledStartTime < base,
                  isLate(it), !it.isCancelled, it.startTime >= now, it.startTime >= base.addingTimeInterval(-60) else { return false }
            return seen.insert(it.rideKey).inserted
        }
    }

    /// Routes from a search started `lookback` before `base` that may be late enough to catch: first
    /// ride due before `base`, not yet on the list.
    static func candidates(_ found: [Itinerary], base: Date, known: Set<String>) -> [Itinerary] {
        found.filter { it in
            guard let first = it.firstTransitLeg else { return false }
            return first.scheduledStartTime < base && !known.contains(it.rideKey)
        }
    }
}

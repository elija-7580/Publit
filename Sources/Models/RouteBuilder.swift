// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich
import Foundation

/// Build your own connection, leg by leg (#91): keep the first legs of a route and plan the rest
/// again from where one leg starts. Pure logic; the search and the screens come on top of it.
enum RouteBuilder {
    /// Where and when the search for the rest starts when a route is cut at one of its legs.
    struct Restart: Equatable, Sendable {
        /// Where the leg to replace starts.
        let from: Place
        /// The route's destination.
        let to: Place
        /// Not before this: when the kept legs arrive there (the route's start when nothing is kept).
        let earliest: Date
    }

    /// The rest of a built route must start where the kept legs end, within this many metres
    /// (the router may hand back the stop's other platform or the point on the street).
    static let joinRadius: Double = 400

    static func restart(_ route: Itinerary, at index: Int) -> Restart? {
        guard route.legs.indices.contains(index), let last = route.legs.last else { return nil }
        let earliest = index == 0 ? route.startTime : route.legs[index - 1].endTime
        return Restart(from: route.legs[index].from, to: last.to, earliest: earliest)
    }

    /// Whether `rest` can follow the kept legs: it starts where they end and not before they arrive.
    static func fits(_ rest: Itinerary, after kept: [Leg]) -> Bool {
        guard let first = rest.legs.first else { return false }
        guard let last = kept.last else { return true }
        return first.startTime >= last.endTime
            && last.to.coordinate.distance(to: first.from.coordinate) <= joinRadius
    }

    /// `route` up to (not including) leg `index`, continued with `rest`. Nil when `rest` does not
    /// fit: it leaves before the kept legs arrive, or starts somewhere else.
    static func splice(_ route: Itinerary, at index: Int, with rest: Itinerary) -> Itinerary? {
        guard route.legs.indices.contains(index) else { return nil }
        let kept = Array(route.legs[..<index])
        guard fits(rest, after: kept) else { return nil }
        return make(legs: kept + rest.legs, parts: prefix(parts(of: route), legs: index) + parts(of: rest))
    }

    /// The planned routes a route is made of: its own parts when it was built, else itself.
    static func parts(of route: Itinerary) -> [RoutePart] {
        route.builtFrom ?? [RoutePart(itineraryId: route.id, firstLeg: 0, legCount: route.legs.count)]
    }

    /// A built route with fresh live times: every part is taken from the refreshed copy of its
    /// planned route (`fresh`, keyed by the ID the part holds). Nil when a part is missing or no
    /// longer the same rides; the caller then keeps the times it has.
    static func refreshed(_ route: Itinerary, with fresh: [String: Itinerary]) -> Itinerary? {
        guard let parts = route.builtFrom, !parts.isEmpty else { return nil }
        var legs: [Leg] = []
        var updated: [RoutePart] = []
        for part in parts {
            guard let source = fresh[part.itineraryId], part.firstLeg >= 0, part.legCount > 0,
                  source.legs.count >= part.firstLeg + part.legCount else { return nil }
            legs += source.legs[part.firstLeg ..< part.firstLeg + part.legCount]
            // The server's ID changes with every delay update: the next refresh asks with the new one.
            updated.append(RoutePart(itineraryId: source.id, firstLeg: part.firstLeg, legCount: part.legCount))
        }
        guard legs.map(identity) == route.legs.map(identity) else { return nil }
        return make(legs: legs, parts: updated)
    }

    /// The first leg that can no longer be reached, after live times moved: it leaves before the
    /// leg in front of it arrives. Nil while the whole route holds.
    static func firstBrokenLeg(in route: Itinerary) -> Int? {
        route.legs.indices.dropFirst().first { route.legs[$0].startTime < route.legs[$0 - 1].endTime }
    }

    // MARK: Internals

    private static func identity(_ leg: Leg) -> String {
        "\(leg.mode)~\(leg.tripId ?? leg.from.name)~\(Int64(leg.scheduledStartTime.timeIntervalSince1970))"
    }

    private static func prefix(_ parts: [RoutePart], legs count: Int) -> [RoutePart] {
        var left = count
        var out: [RoutePart] = []
        for part in parts where left > 0 {
            let take = min(part.legCount, left)
            out.append(RoutePart(itineraryId: part.itineraryId, firstLeg: part.firstLeg, legCount: take))
            left -= take
        }
        return out
    }

    private static func make(legs: [Leg], parts: [RoutePart]) -> Itinerary? {
        guard let first = legs.first, let last = legs.last else { return nil }
        let rides = legs.filter(\.isTransit)
        // The same vehicle running on under another line is no change.
        let changes = rides.count - 1 - rides.dropFirst().filter { $0.interlineWithPreviousLeg == true }.count
        var route = Itinerary(id: "built|" + legs.map(identity).joined(separator: "|"),
                              duration: Int(last.endTime.timeIntervalSince(first.startTime)),
                              startTime: first.startTime, endTime: last.endTime,
                              transfers: max(0, changes), legs: legs)
        route.builtFrom = parts
        return route
    }
}

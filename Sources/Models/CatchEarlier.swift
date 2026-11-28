// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich
import Foundation

/// A change on a route no longer works (or hardly): leave earlier and still catch the same
/// connection. The router plans with the timetable; where live times only come from another
/// operator afterwards (Wiener Linien, ÖBB, … in `LiveOverlay`), a late feeder can break a change
/// on a route that has not started yet. The router never offers the earlier feeder by itself: it
/// leaves earlier and arrives at the same time, so it counts as the worse route. Example (feedback
/// 27 Nov 2026): U1 → U4 → REX to Krems, the U4 runs late and misses the REX at Heiligenstadt;
/// an earlier U1 and U4 still make it.
enum CatchEarlier {
    /// Below this chance a change is worth rescuing (as `SmartRouting.changeAtRisk`).
    static let rescueBelow = 0.5
    /// A way there counts as safe from this chance on (`SmartRouting.Change.Level.likely`).
    static let safeFrom = 0.7
    /// Arrive at the connection's platform this long before it leaves.
    static let platformMargin: TimeInterval = 120

    /// The change to rescue and where to plan to.
    struct Target: Sendable {
        /// The ride to catch (its index in the route) and what the way to it may arrive by.
        let outgoingIndex: Int
        let outgoing: Leg
        let stopName: String
        let chance: Double
        var latestArrival: Date { outgoing.startTime.addingTimeInterval(-platformMargin) }
    }

    /// The first change ahead that no longer works or is unlikely, while the route has not started
    /// yet. Nil when every change holds, the route is already under way, or the vehicle goes on.
    static func target(_ route: Itinerary, changes: [SmartRouting.Change], at now: Date) -> Target? {
        guard route.startTime > now, route.legs.count > 1 else { return nil }
        guard let c = changes.first(where: { $0.source != .throughRun && ($0.spareMinutes < 0 || $0.chance < rescueBelow) }),
              c.outgoingIndex > 0, c.outgoing.startTime.addingTimeInterval(-platformMargin) > now else { return nil }
        return Target(outgoingIndex: c.outgoingIndex, outgoing: c.outgoing, stopName: c.stopName, chance: c.chance)
    }

    /// Out of the ways found to the connection's platform: the route that takes one of them and then
    /// goes on as before. The latest way that makes every change up to the connection safely; when
    /// none does, the surest one, if it is clearly better than the route as it is. Nil when no way
    /// fits, or each leaves before `now`.
    static func pick(_ ways: [Itinerary], for route: Itinerary, target: Target, at now: Date,
                     changes: (Itinerary) -> [SmartRouting.Change]) -> Itinerary? {
        let candidates: [(route: Itinerary, worst: Double)] = ways.compactMap { way in
            guard way.startTime >= now, way.endTime <= target.outgoing.startTime,
                  let joined = RouteBuilder.lead(way, into: route, at: target.outgoingIndex),
                  joined.rideKey != route.rideKey else { return nil }
            // Up to and including the change onto the connection; what follows is as before.
            let ahead = changes(joined).filter { $0.outgoingIndex <= way.legs.count }
            guard ahead.allSatisfy({ $0.spareMinutes >= 0 }) else { return nil }
            return (joined, ahead.map(\.chance).min() ?? 1)
        }
        let safe = candidates.filter { $0.worst >= safeFrom }
        if let latest = safe.max(by: { ($0.route.startTime, $0.worst) < ($1.route.startTime, $1.worst) }) {
            return latest.route
        }
        guard let surest = candidates.max(by: { $0.worst < $1.worst }),
              surest.worst >= rescueBelow, surest.worst >= target.chance + 0.2 else { return nil }
        return surest.route
    }

    /// The route that still makes it, and the connection it catches.
    struct Rescue: Sendable {
        let route: Itinerary
        let connection: Leg
        /// How much earlier it leaves than the route it rescues, in whole minutes (0 when not earlier).
        let minutesEarlier: Int
    }

    /// Plans the way to the connection, with live times, and picks one (`pick`). Nil when the route
    /// needs no rescue or nothing earlier still works.
    static func search(_ route: Itinerary, at now: Date = Date(), options: RouteOptions = RouteOptions()) async -> Rescue? {
        guard let target = target(route, changes: SmartRouting.changes(route, at: now), at: now),
              let start = route.legs.first?.from else { return nil }
        let to = target.outgoing.from
        guard let res = try? await TransitousClient.shared.plan(
            from: start.coordinate, to: to.coordinate, time: target.latestArrival, arriveBy: true, options: options,
            stops: PlanStops(from: start.stopId, to: to.stopId)) else { return nil }
        let ways = await LiveOverlay.apply(res.itineraries, now: now, budget: 3)
        guard let rescued = pick(ways, for: route, target: target, at: now, changes: { SmartRouting.changes($0, at: now) })
        else { return nil }
        return Rescue(route: rescued, connection: target.outgoing, minutesEarlier: minutesEarlier(rescued, than: route))
    }

    /// How much earlier the rescued route leaves, in whole minutes (0 when not earlier).
    static func minutesEarlier(_ rescued: Itinerary, than route: Itinerary) -> Int {
        max(0, Int((route.startTime.timeIntervalSince(rescued.startTime) / 60).rounded()))
    }
}

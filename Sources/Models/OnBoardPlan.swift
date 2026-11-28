// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich
import Foundation

/// Plan from the vehicle you are riding: you are on a tram, bus or train and want to go somewhere
/// else. The ride so far counts, and every way on starts from the stops still ahead, with live times.
/// The idea comes from BudapestGO, the app of BKK (Budapest), which calls it "on-board journey planning".
///
/// How it works: one search starts at the next stop the vehicle reaches, at the time it gets there.
/// The router may keep you on the same vehicle (it boards it there again) or let you change at any
/// later stop. The ride up to the next stop is put in front, and the same vehicle is one ride.
/// Pure logic; the search and the screen come on top of it.
enum OnBoardPlan {
    /// Where you are on the ride.
    struct Position: Equatable, Sendable {
        /// The stop the ride counts from: the last one the vehicle left (or stands at).
        let from: Int
        /// The first stop still ahead where you can get off; the search starts there.
        let next: Int
        /// When the vehicle gets there (live), and so when the search starts.
        let at: Date
    }

    /// Prefix of the IDs of rides cut out of a vehicle's trip: `ride:<from>:<to>:<tripId>`.
    /// A route made with one carries it as a part, so its live times come from the trip (`refreshed`).
    static let ridePrefix = "ride:"

    /// Where you are on a vehicle's ride now. Nil when it has arrived at its last stop.
    static func position(stops: [Place], now: Date) -> Position? {
        guard stops.count >= 2 else { return nil }
        let index: (from: Int, next: Int)
        switch TripProgress.at(now, stops: stops) {
        case .finished: return nil
        case .notStarted: index = (0, 0)
        case .atStop(let i): index = (i, i)
        case .between(let i, _): index = (i, i + 1)
        }
        // At the last stop there is nothing to ride on: the search starts there, now.
        let stop = stops[index.next]
        let arrival = stop.arrival ?? stop.departure ?? now
        return Position(from: index.from, next: index.next, at: max(now, arrival))
    }

    /// The stops of the vehicle still ahead, from the next one on (cancelled ones left out).
    static func stopsAhead(_ stops: [Place], from position: Position) -> [Place] {
        Array(stops[position.next...]).filter { $0.cancelled != true }
    }

    /// The ride of `trip` from stop `from` to stop `to` as a leg of its own. Nil when `to` is not after `from`.
    static func ride(_ trip: Leg, from: Int, to: Int) -> Leg? {
        let stops = trip.allStops
        guard from >= 0, to < stops.count, to > from else { return nil }
        let a = stops[from], b = stops[to]
        var leg = trip
        leg.from = a
        leg.to = b
        leg.intermediateStops = Array(stops[(from + 1)..<to])
        leg.startTime = a.departure ?? a.arrival ?? trip.startTime
        leg.endTime = b.arrival ?? b.departure ?? trip.endTime
        leg.scheduledStartTime = a.scheduledDeparture ?? a.scheduledArrival ?? leg.startTime
        leg.scheduledEndTime = b.scheduledArrival ?? b.scheduledDeparture ?? leg.endTime
        leg.duration = max(0, Int(leg.endTime.timeIntervalSince(leg.startTime)))
        leg.distance = nil
        leg.legGeometry = EncodedPolyline(coordinates: cut(trip.legGeometry.coordinates, from: a.coordinate, to: b.coordinate),
                                          precision: trip.legGeometry.precision)
        leg.interlineWithPreviousLeg = nil
        leg.alternatives = nil
        leg.fareTransferIndex = nil
        leg.effectiveFareLegIndex = nil
        return leg
    }

    /// The part of `path` between the points closest to `a` and (after it) to `b`.
    static func cut(_ path: [LatLon], from a: LatLon, to b: LatLon) -> [LatLon] {
        guard path.count >= 2 else { return [a, b] }
        func nearest(_ p: LatLon, in range: Range<Int>) -> Int {
            range.min { path[$0].distance(to: p) < path[$1].distance(to: p) } ?? range.lowerBound
        }
        let i = nearest(a, in: 0..<path.count)
        let j = nearest(b, in: i..<path.count)
        guard j > i else { return [a, b] }
        return Array(path[i...j])
    }

    /// One route found from the next stop, as a route from the vehicle: the ride so far first.
    /// When the route rides on with the same vehicle that is one ride; when it gets off at the next
    /// stop the ride ends there. Nil when the route cannot follow the ride (it leaves earlier).
    static func route(_ found: Itinerary, trip: Leg, position: Position) -> Itinerary? {
        guard let tripId = trip.tripId else { return nil }
        let stops = trip.allStops
        guard stops.indices.contains(position.from), stops.indices.contains(position.next) else { return nil }
        var legs = found.legs
        // Short walks at the start stop (the router's way from a point to the platform) do not count.
        var first = 0
        while first < legs.count - 1, !legs[first].isTransit,
              legs[first].from.coordinate.distance(to: legs[first].to.coordinate) < 150 { first += 1 }

        var rideLeg: Leg?
        var offIndex = position.next
        var part = RoutePart(itineraryId: found.id, firstLeg: 0, legCount: legs.count)
        if legs.indices.contains(first), legs[first].isTransit, legs[first].tripId == tripId,
           let off = stops.indices.dropFirst(position.next).first(where: { RouteBuilder.samePlace(stops[$0], legs[first].to) }),
           off > position.from {
            // Stays on: one ride from where you are to where the route gets off.
            rideLeg = ride(trip, from: position.from, to: off)
            offIndex = off
            legs = Array(legs[(first + 1)...])
            part = RoutePart(itineraryId: found.id, firstLeg: first + 1, legCount: legs.count)
        } else {
            // Gets off at the next stop (none when the vehicle stands there: you get off now).
            if position.next > position.from { rideLeg = ride(trip, from: position.from, to: position.next) }
            guard legs.first.map({ $0.startTime >= position.at.addingTimeInterval(-60) }) ?? false else { return nil }
        }
        guard let rideLeg else {
            // Nothing ridden any more: the route as found.
            return legs.isEmpty ? nil : found
        }
        let all = [rideLeg] + legs
        let rides = all.filter(\.isTransit)
        let changes = rides.count - 1 - rides.dropFirst().filter { $0.interlineWithPreviousLeg == true }.count
        var parts = [RoutePart(itineraryId: rideId(tripId: tripId, from: position.from, to: offIndex),
                               firstLeg: 0, legCount: 1)]
        if !legs.isEmpty { parts.append(part) }
        var route = Itinerary(id: "onboard|" + found.id,
                              duration: Int((all.last?.endTime ?? found.endTime).timeIntervalSince(rideLeg.startTime)),
                              startTime: rideLeg.startTime, endTime: all.last?.endTime ?? found.endTime,
                              transfers: max(0, changes), legs: all)
        route.builtFrom = parts
        return route
    }

    /// The routes from the vehicle out of what the search from the next stop found: each once,
    /// earliest arrival first, then fewer changes. On board you have already left, so a route that
    /// arrives later with as many changes or more is no choice and is left out (the search from the
    /// next stop also lists getting off there to wait for a later vehicle that goes the same way).
    static func routes(_ found: [Itinerary], trip: Leg, position: Position) -> [Itinerary] {
        var seen = Set<String>()
        let all = found.compactMap { route($0, trip: trip, position: position) }
            .filter { seen.insert($0.rideKey).inserted }
            .sorted { ($0.endTime, $0.transfers, $0.startTime) < ($1.endTime, $1.transfers, $1.startTime) }
        var kept: [Itinerary] = []
        for r in all where !kept.contains(where: { $0.endTime <= r.endTime && $0.transfers <= r.transfers }) {
            kept.append(r)
        }
        return kept
    }

    // MARK: Live times of the ride

    static func rideId(tripId: String, from: Int, to: Int) -> String { "\(ridePrefix)\(from):\(to):\(tripId)" }

    /// The trip and stops of a ride ID; nil for any other ID.
    static func parseRide(_ id: String) -> (tripId: String, from: Int, to: Int)? {
        guard id.hasPrefix(ridePrefix) else { return nil }
        let rest = id.dropFirst(ridePrefix.count)
        let parts = rest.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3, let from = Int(parts[0]), let to = Int(parts[1]), !parts[2].isEmpty else { return nil }
        return (String(parts[2]), from, to)
    }

    /// The ride of a ride ID, cut out of the vehicle's trip as fetched now, as a route of one leg
    /// with that same ID (so a route built from it refreshes again the next time).
    static func refreshed(_ id: String, trip fresh: Itinerary) -> Itinerary? {
        guard let ride = parseRide(id), let tripLeg = fresh.legs.first(where: \.isTransit),
              let leg = Self.ride(tripLeg, from: ride.from, to: ride.to) else { return nil }
        return Itinerary(id: id, duration: leg.duration, startTime: leg.startTime, endTime: leg.endTime,
                         transfers: 0, legs: [leg])
    }
}

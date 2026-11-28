import Foundation

/// Where a vehicle is along its trip, estimated from the (real-time) stop times.
/// Used when a feed has delays but no GPS positions.
enum TripProgress: Equatable, Sendable {
    case notStarted
    case atStop(index: Int)
    /// Between stop `index` and `index + 1`; `fraction` 0…1 by time.
    case between(index: Int, fraction: Double)
    case finished

    static func at(_ now: Date, stops: [Place]) -> TripProgress {
        guard let first = stops.first, let last = stops.last else { return .notStarted }
        func dep(_ p: Place) -> Date? { p.departure ?? p.arrival }
        func arr(_ p: Place) -> Date? { p.arrival ?? p.departure }
        if let d = dep(first), now < d { return now >= (arr(first) ?? d) ? .atStop(index: 0) : .notStarted }
        if let a = arr(last), now >= a { return .finished }
        for i in stops.indices {
            let s = stops[i]
            if let a = arr(s), let d = dep(s), now >= a, now < d { return .atStop(index: i) }
            guard i + 1 < stops.count, let d = dep(s), let a = arr(stops[i + 1]), now >= d, now < a else { continue }
            let span = a.timeIntervalSince(d)
            return .between(index: i, fraction: span > 0 ? now.timeIntervalSince(d) / span : 0)
        }
        return .notStarted
    }

    /// Estimated position between stops: along the ride's shape when there is one, else in a
    /// straight line. A long-distance bus with few stops (Vienna to Venice) went straight across
    /// the country in a straight line, far away from its road (feedback on build 98).
    static func position(_ progress: TripProgress, stops: [Place], path: [LatLon] = []) -> LatLon? {
        switch progress {
        case .atStop(let i): return stops.indices.contains(i) ? stops[i].coordinate : nil
        case .between(let i, let f):
            guard i + 1 < stops.count else { return nil }
            let a = stops[i], b = stops[i + 1]
            if path.count >= 2,
               let from = PathGeometry.locate(a.coordinate, on: path),
               let to = PathGeometry.locate(b.coordinate, on: path),
               from.offset < 2_000, to.offset < 2_000, to.along > from.along,
               let p = PathGeometry.point(at: from.along + (to.along - from.along) * f, on: path) {
                return p
            }
            return LatLon(lat: a.lat + (b.lat - a.lat) * f, lon: a.lon + (b.lon - a.lon) * f)
        case .notStarted, .finished: return nil
        }
    }

    /// Index of the next stop the vehicle has not left yet.
    static func nextStopIndex(_ progress: TripProgress, count: Int) -> Int? {
        switch progress {
        case .notStarted: return 0
        case .atStop(let i): return i
        case .between(let i, _): return min(i + 1, count - 1)
        case .finished: return nil
        }
    }

    /// Stops passed, as a number (2.5 = halfway between the third and fourth stop).
    func stopValue(count: Int) -> Double {
        switch self {
        case .notStarted: return 0
        case .atStop(let i): return Double(i)
        case .between(let i, let f): return Double(i) + f
        case .finished: return Double(max(count - 1, 0))
        }
    }

    /// Where a phone on board is along the line: the fix laid onto the route's shape (or straight
    /// lines between the stops). Nil when the fix is not near the line.
    static func located(_ p: LatLon, stops: [Place], path: [LatLon], maxOffset: Double = 200) -> TripProgress? {
        guard stops.count >= 2 else { return nil }
        let line = path.count >= 2 ? path : stops.map(\.coordinate)
        guard let me = PathGeometry.locate(p, on: line), me.offset <= maxOffset else { return nil }
        var marks: [Double] = []
        var last = 0.0
        for s in stops {
            last = max(last, PathGeometry.locate(s.coordinate, on: line)?.along ?? last)
            marks.append(last)
        }
        // At a stop when within a platform's length of it.
        if let (i, m) = marks.enumerated().min(by: { abs($0.element - me.along) < abs($1.element - me.along) }),
           abs(m - me.along) < 60 {
            return .atStop(index: i)
        }
        if me.along <= marks[0] { return .atStop(index: 0) }
        for i in 0..<(marks.count - 1) where me.along < marks[i + 1] {
            let span = marks[i + 1] - marks[i]
            return .between(index: i, fraction: span > 0 ? (me.along - marks[i]) / span : 0)
        }
        return .atStop(index: stops.count - 1)
    }
}

/// Where a vehicle's position on the map comes from, said next to it. Publit has no GPS positions
/// from vehicles: Transitous does not pass them on. A "GPS" label would need a feed that reports
/// them as such, so there is none.
enum VehiclePositionSource: Equatable, Sendable {
    /// Placed between stops by the live (real-time) stop times.
    case liveTimes
    /// Placed by the timetable: the operator sends no live data for this trip.
    case timetable
    /// Not under way (not left the first stop yet, or arrived): no position to show.
    case unavailable

    static func of(_ progress: TripProgress, realTime: Bool) -> VehiclePositionSource {
        switch progress {
        case .notStarted, .finished: return .unavailable
        case .atStop, .between: return realTime ? .liveTimes : .timetable
        }
    }

    var label: String {
        switch self {
        case .liveTimes: return L10n.t("Position estimated from live stop times.")
        case .timetable: return L10n.t("No live data for this trip. Position estimated from the timetable.")
        case .unavailable: return L10n.t("Vehicle position unavailable right now.")
        }
    }

    var symbol: String {
        switch self {
        case .liveTimes: return "dot.radiowaves.left.and.right"
        case .timetable: return "calendar"
        case .unavailable: return "questionmark.circle"
        }
    }
}

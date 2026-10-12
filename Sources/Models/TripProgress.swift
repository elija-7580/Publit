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

    /// Estimated position, interpolated in a straight line between stops.
    static func position(_ progress: TripProgress, stops: [Place]) -> LatLon? {
        switch progress {
        case .atStop(let i): return stops[i].coordinate
        case .between(let i, let f):
            let a = stops[i], b = stops[i + 1]
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
}

import Foundation

/// "Learn from my trips" (Settings → Smart routing, off by default). Everything here stays on the
/// device: nothing is sent anywhere.
///
/// During a started trip the recorder follows the location only to derive, per change, how long the
/// walk really took, whether the connection was caught, how much time was really left, and how late
/// both vehicles were. The location points themselves are never stored – only these values per change.
/// From them a personal walking model is estimated (Bayesian, starting from `WalkModel.prior`) that also
/// applies to changes never made before; for changes made often the own success rate counts too.
enum TripLearning {
    static let fileName = "trip-learning.json"
    static let maxObservations = 300

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: SmartRouting.learnTripsKey) }

    /// What is kept of one change.
    struct Observation: Codable, Equatable, Sendable {
        var date: Date
        /// stationId|outgoing routeId|time window: the same change again.
        var key: String
        var walk: Walk
        /// Seconds from the feeder's arrival until reaching the departure area (nil: not measured).
        var walkSeconds: Double?
        var made: Bool
        /// Seconds left at the departure area before the connection left (negative: missed it).
        var spareSeconds: Double?
        var feederDelay: Double
        var connectionDelay: Double

        /// `TransferWalk` without its Leg-derived init, for storage.
        struct Walk: Codable, Equatable, Sendable {
            var planned: Double, levels: Double, elevators: Int, platformChanged: Bool, stationChange: Bool, bigStation: Bool
            init(_ w: TransferWalk) {
                planned = w.plannedSeconds; levels = w.levels; elevators = w.elevators
                platformChanged = w.platformChanged; stationChange = w.stationChange; bigStation = w.bigStation
            }
            var transferWalk: TransferWalk {
                TransferWalk(plannedSeconds: planned, levels: levels, elevators: elevators, platformChanged: platformChanged,
                             stationChange: stationChange, bigStation: bigStation)
            }
        }
    }

    static func key(_ c: SmartRouting.Change) -> String {
        let tz = c.incoming.to.tz.flatMap(TimeZone.init(identifier:)) ?? .current
        return "\(c.incoming.to.stationId)|\(c.outgoing.routeId ?? c.outgoing.lineName)|\(DelayHistory.window(c.outgoing.scheduledStartTime, timeZone: tz))"
    }

    // MARK: Personal walking model (Bayesian linear regression)

    /// walk = factor·planned + perLevel·levels + perElevator·lifts + platform + station + big station + overhead.
    /// Prior: `WalkModel.prior` with `WalkModel.priorSD`. Few observations move it little, many more.
    static func walkModel(from observations: [Observation], prior: WalkModel = .prior) -> WalkModel {
        let measured = observations.compactMap { o -> (x: [Double], y: Double)? in
            guard let y = o.walkSeconds, y > 0, y < 3600 else { return nil }
            return (WalkModel.features(o.walk.transferWalk), y)
        }
        guard !measured.isEmpty else { return prior }
        let n = 7
        let mu0 = prior.parameters
        // Precision = C0⁻¹ (diagonal prior) + Σ x xᵀ / v ;  b = C0⁻¹ μ0 + Σ x y / v
        var precision = [Double](repeating: 0, count: 49)
        var b = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let p = 1 / prior.covariance[i * 8]
            precision[i * 8] = p
            b[i] = p * mu0[i]
        }
        for (x, y) in measured {
            let expected = max(30, zip(mu0, x).reduce(0) { $0 + $1.0 * $1.1 })
            // Measurement noise: getting off is timed by the vehicle's arrival, the stop by GPS in a station.
            let v = pow(0.25 * expected + 30, 2)
            for i in 0..<n {
                b[i] += x[i] * y / v
                for j in 0..<n { precision[i * n + j] += x[i] * x[j] / v }
            }
        }
        guard let cov = invert(precision, n) else { return prior }
        var mu = (0..<n).map { i in (0..<n).reduce(0) { $0 + cov[i * n + $1] * b[$1] } }
        let bounds: [ClosedRange<Double>] = [0.6...2.5, 0...120, 0...300, 0...300, 0...300, 0...300, -60...240]
        for i in 0..<n { mu[i] = mu[i].clamped(to: bounds[i]) }
        // Residual spread: prior sigma weighted like five observations, then the own scatter.
        let m = WalkModel(parameters: mu, sigma: prior.sigma, covariance: cov, observations: measured.count)
        var sumSq = 0.0
        for (x, y) in measured {
            let e = max(30, zip(mu, x).reduce(0) { $0 + $1.0 * $1.1 })
            sumSq += pow(log(y / e), 2)
        }
        let k0 = 5.0
        let sigma = ((k0 * prior.sigma * prior.sigma + sumSq) / (k0 + Double(measured.count))).squareRoot().clamped(to: 0.05...0.6)
        return WalkModel(parameters: m.parameters, sigma: sigma, covariance: cov, observations: measured.count)
    }

    /// Gauss–Jordan inverse of an n × n matrix (row-major); nil if singular.
    static func invert(_ m: [Double], _ n: Int) -> [Double]? {
        var a = m, inv = (0..<(n * n)).map { $0 % (n + 1) == 0 ? 1.0 : 0.0 }
        for col in 0..<n {
            guard let pivot = (col..<n).max(by: { abs(a[$0 * n + col]) < abs(a[$1 * n + col]) }), abs(a[pivot * n + col]) > 1e-12 else { return nil }
            if pivot != col {
                for k in 0..<n { a.swapAt(pivot * n + k, col * n + k); inv.swapAt(pivot * n + k, col * n + k) }
            }
            let d = a[col * n + col]
            for k in 0..<n { a[col * n + k] /= d; inv[col * n + k] /= d }
            for r in 0..<n where r != col {
                let f = a[r * n + col]
                guard f != 0 else { continue }
                for k in 0..<n { a[r * n + k] -= f * a[col * n + k]; inv[r * n + k] -= f * inv[col * n + k] }
            }
        }
        return inv
    }

    // MARK: Changes made before

    /// For a change made at least 3 times: the model's chance moved towards the own success rate
    /// (Beta prior worth five changes, centred on the model).
    static func adjusted(_ chance: Double, key: String, observations: [Observation]) -> Double {
        let same = observations.filter { $0.key == key }
        guard same.count >= 3 else { return chance }
        let made = Double(same.filter(\.made).count), k = 5.0
        return ((k * chance + made) / (k + Double(same.count))).clamped(to: 0.01...0.99)
    }

    // MARK: Storage (Application Support, on the device only)

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [Observation]?

    private static var fileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent(fileName)
    }

    static var observations: [Observation] {
        lock.lock(); defer { lock.unlock() }
        if let cache { return cache }
        let list = fileURL.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode([Observation].self, from: $0) } ?? []
        cache = list
        return list
    }

    static func add(_ new: [Observation]) {
        guard isEnabled, !new.isEmpty else { return }
        var list = observations + new
        list = Array(list.suffix(maxObservations))
        lock.lock(); cache = list; lock.unlock()
        if let url = fileURL {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? JSONEncoder().encode(list).write(to: url, options: [.atomic, .completeFileProtection])
        }
        if let data = try? JSONEncoder().encode(walkModel(from: list)) {
            UserDefaults.standard.set(data, forKey: WalkModel.storageKey)
        }
    }

    /// "Reset learned preferences": everything learned from trips goes.
    static func reset() {
        lock.lock(); cache = []; lock.unlock()
        if let url = fileURL { try? FileManager.default.removeItem(at: url) }
        UserDefaults.standard.removeObject(forKey: WalkModel.storageKey)
    }
}

// MARK: Recorder

extension TripLearning {
    /// Follows one started trip through location fixes and yields an `Observation` per change once
    /// it is decided. Holds only a few timestamps per change in memory – no track.
    struct Recorder: Sendable {
        /// Departure area: within this many metres of the connection's stop.
        static let atStop = 40.0
        static let maxAccuracy = 35.0

        private(set) var reached: [Int: Date] = [:]      // change index → when the departure area was reached
        private(set) var done: Set<Int> = []

        init() {}

        /// Feeds one fix; returns the changes decided by it. `itinerary` is the latest refreshed one.
        mutating func observe(_ here: LatLon, accuracy: Double, at time: Date, itinerary: Itinerary) -> [Observation] {
            guard accuracy >= 0, accuracy <= Self.maxAccuracy else { return [] }
            var out: [Observation] = []
            for (i, c) in SmartRouting.changes(itinerary, at: time).enumerated() where !done.contains(i) {
                guard c.source != .throughRun else { done.insert(i); continue }
                let stop = c.outgoing.from.coordinate
                let d = here.distance(to: stop)
                // Reached the departure area after getting off.
                if reached[i] == nil, time >= c.incoming.endTime.addingTimeInterval(-60), d <= Self.atStop {
                    reached[i] = time
                }
                // Decided: on the connection (moving away along it) or still at the stop after it left.
                let left = c.outgoing.startTime
                let onBoard = time > left.addingTimeInterval(60) && d > 300 && Self.near(here, leg: c.outgoing, within: 150)
                let stuck = time > left.addingTimeInterval(5 * 60) && d <= 150
                guard onBoard || stuck else { continue }
                done.insert(i)
                let walk = reached[i].map { $0.timeIntervalSince(c.incoming.endTime) }
                out.append(Observation(date: time, key: TripLearning.key(c), walk: Observation.Walk(c.walk ?? TransferWalk(plannedSeconds: Double(c.walkSeconds))),
                                       walkSeconds: walk.flatMap { $0 > 0 ? $0 : nil }, made: onBoard,
                                       spareSeconds: reached[i].map { left.timeIntervalSince($0) },
                                       feederDelay: c.incoming.endTime.timeIntervalSince(c.incoming.scheduledEndTime),
                                       connectionDelay: c.outgoing.startTime.timeIntervalSince(c.outgoing.scheduledStartTime)))
            }
            return out
        }

        /// Within `metres` of the leg's path (distance to each segment, flat-earth approximation).
        static func near(_ p: LatLon, leg: Leg, within metres: Double) -> Bool {
            let path = leg.mapPath
            guard let first = path.first else { return true }
            if path.count == 1 { return first.distance(to: p) <= metres }
            let k = cos(p.lat * .pi / 180) * 111_320.0
            func xy(_ q: LatLon) -> (Double, Double) { ((q.lon - p.lon) * k, (q.lat - p.lat) * 110_540) }
            for (a, b) in zip(path, path.dropFirst()) {
                let (ax, ay) = xy(a), (bx, by) = xy(b)
                let dx = bx - ax, dy = by - ay, len = dx * dx + dy * dy
                let t = len > 0 ? max(0, min(1, -(ax * dx + ay * dy) / len)) : 0
                let cx = ax + t * dx, cy = ay + t * dy
                if (cx * cx + cy * cy).squareRoot() <= metres { return true }
            }
            return false
        }
    }
}

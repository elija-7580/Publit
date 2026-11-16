import Foundation

/// The walk of a change, described so it can be predicted, also for changes never made before:
/// the planner's walk, floors on stairs or escalators, lifts, a new platform, another station,
/// a station with many levels.
struct TransferWalk: Equatable, Sendable {
    var plannedSeconds: Double = 0
    var levels: Double = 0
    var elevators = 0
    var platformChanged = false
    var stationChange = false
    var bigStation = false

    static let featureCount = 7

    /// Inputs of the walk model; the last one is the fixed overhead of every change.
    var features: [Double] {
        [plannedSeconds, levels, Double(elevators), platformChanged ? 1 : 0, stationChange ? 1 : 0, bigStation ? 1 : 0, 1]
    }

    static func of(incoming: Leg, outgoing: Leg, walks: [Leg]) -> TransferWalk {
        var w = TransferWalk()
        w.plannedSeconds = Double(walks.reduce(0) { $0 + $1.duration })
        var seen: Set<Double> = []
        for step in walks.flatMap({ $0.steps ?? [] }) {
            let dir = step.relativeDirection?.uppercased() ?? ""
            if dir == "ELEVATOR" { w.elevators += 1 }
            if let a = step.fromLevel, let b = step.toLevel {
                seen.insert(a); seen.insert(b)
                if dir != "ELEVATOR" { w.levels += abs(b - a) }
            } else if dir == "STAIRS" || dir == "ESCALATOR" {
                w.levels += 1
            }
        }
        w.bigStation = seen.count >= 3
        func moved(_ p: Place) -> Bool {
            guard let now = p.track, let was = p.scheduledTrack, !now.isEmpty, !was.isEmpty else { return false }
            return now != was
        }
        w.platformChanged = moved(incoming.to) || moved(outgoing.from)
        w.stationChange = incoming.to.stationId != outgoing.from.stationId
        return w
    }
}

/// What Publit learns from the trips you start, only on this iPhone: how long your changes take
/// (your pace, stairs, lifts, platforms), and how often a change you make again and again works.
/// Kept: a few sums for the walk model and a count per recurring change. No positions, no routes.
enum TransferLearning {
    static let enabledKey = "smartLearnTrips"
    static let warnKey = "smartWarnChanges"
    private static let modelKey = "smartTransferModel"
    private static let historyKey = "smartTransferHistory"

    static var isEnabled: Bool { SmartRouting.isEnabled && UserDefaults.standard.bool(forKey: enabledKey) }
    static var warns: Bool { UserDefaults.standard.object(forKey: warnKey) as? Bool ?? true }

    // MARK: Walk model (Bayesian linear regression, seconds)

    /// Starting values: the planner's walk plus 10 %, 10 s per floor, 45 s per lift, 1 min to find a
    /// changed platform, 30 s for another station or a big one. Wide on purpose: a few own changes move them.
    static let priorMean: [Double] = [1.1, 10, 45, 60, 30, 30, 0]
    static let priorSD: [Double] = [0.25, 10, 30, 45, 30, 30, 30]

    /// How much one change scatters around the prediction.
    static func noiseSD(_ w: TransferWalk) -> Double { 30 + 0.15 * w.plannedSeconds }

    struct Model: Codable, Equatable, Sendable {
        var count = 0
        /// Sums of x·xᵀ/σ² (row by row) and x·y/σ² over the own changes.
        var xx = [Double](repeating: 0, count: TransferWalk.featureCount * TransferWalk.featureCount)
        var xy = [Double](repeating: 0, count: TransferWalk.featureCount)

        mutating func add(_ walk: TransferWalk, seconds y: Double) {
            let x = walk.features, n = x.count, s2 = pow(noiseSD(walk), 2)
            for i in 0..<n {
                xy[i] += x[i] * y / s2
                for j in 0..<n { xx[i * n + j] += x[i] * x[j] / s2 }
            }
            count += 1
        }

        /// Posterior precision and the right-hand side; the prior is part of both.
        private var system: (a: [Double], b: [Double]) {
            let n = TransferWalk.featureCount
            var a = xx, b = xy
            for i in 0..<n {
                let p = 1 / pow(priorSD[i], 2)
                a[i * n + i] += p
                b[i] += p * priorMean[i]
            }
            return (a, b)
        }

        var coefficients: [Double] { TransferLearning.solve(system.a, system.b) ?? priorMean }

        /// Expected seconds for the walk and how unsure that is (standard deviation).
        func predict(_ walk: TransferWalk) -> (mean: Double, sd: Double) {
            let x = walk.features
            let c = coefficients
            let mean = zip(x, c).reduce(0) { $0 + $1.0 * $1.1 }
            let spread = TransferLearning.solve(system.a, x).map { zip(x, $0).reduce(0) { $0 + $1.0 * $1.1 } } ?? 0
            return (max(0, mean), (max(0, spread) + pow(noiseSD(walk), 2)).squareRoot())
        }
    }

    /// Read on every change of every route: decoded once, until the next write or reset.
    private static let lock = NSLock()
    private static var cachedModel: Model?
    private static var cachedHistory: [String: Record]?

    private static func cached<T>(_ get: () -> T?, _ load: () -> T, _ store: (T) -> Void) -> T {
        lock.lock(); defer { lock.unlock() }
        if let v = get() { return v }
        let v = load()
        store(v)
        return v
    }

    static var model: Model {
        get {
            guard isEnabled else { return Model() }
            return cached({ cachedModel }, {
                UserDefaults.standard.data(forKey: modelKey).flatMap { try? JSONDecoder().decode(Model.self, from: $0) } ?? Model()
            }, { cachedModel = $0 })
        }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: modelKey)
            lock.lock(); cachedModel = newValue; lock.unlock()
        }
    }

    /// Gaussian elimination for the small symmetric system a·x = b.
    static func solve(_ a: [Double], _ b: [Double]) -> [Double]? {
        let n = b.count
        guard a.count == n * n else { return nil }
        var m = a, v = b
        for col in 0..<n {
            guard let p = (col..<n).max(by: { abs(m[$0 * n + col]) < abs(m[$1 * n + col]) }), abs(m[p * n + col]) > 1e-12 else { return nil }
            if p != col {
                for k in 0..<n { m.swapAt(p * n + k, col * n + k) }
                v.swapAt(p, col)
            }
            for r in (col + 1)..<n {
                let f = m[r * n + col] / m[col * n + col]
                guard f != 0 else { continue }
                for k in col..<n { m[r * n + k] -= f * m[col * n + k] }
                v[r] -= f * v[col]
            }
        }
        var x = [Double](repeating: 0, count: n)
        for r in stride(from: n - 1, through: 0, by: -1) {
            var s = v[r]
            for k in (r + 1)..<n { s -= m[r * n + k] * x[k] }
            x[r] = s / m[r * n + r]
        }
        return x
    }

    // MARK: Recurring changes

    /// Weekday peak, weekday other, weekend, night: a change at 8:00 is not one at 23:00.
    static func timeWindow(_ date: Date, tz: String?) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz.flatMap(TimeZone.init(identifier:)) ?? .current
        let hour = cal.component(.hour, from: date), weekday = cal.component(.weekday, from: date)
        if hour < 5 || hour >= 22 { return "night" }
        if weekday == 1 || weekday == 7 { return "weekend" }
        return (6..<9).contains(hour) || (16..<19).contains(hour) ? "peak" : "day"
    }

    static func key(incoming: Leg, outgoing: Leg) -> String {
        let a = incoming.routeId ?? incoming.lineName, b = outgoing.routeId ?? outgoing.lineName
        return "\(incoming.to.stationId)|\(a)|\(b)|\(timeWindow(outgoing.scheduledStartTime, tz: outgoing.from.tz))"
    }

    struct Record: Codable, Equatable, Sendable {
        var made = 0
        var missed = 0
        var last: Double = 0
        var total: Int { made + missed }
    }

    static var history: [String: Record] {
        get {
            guard isEnabled else { return [:] }
            return cached({ cachedHistory }, {
                UserDefaults.standard.data(forKey: historyKey).flatMap { try? JSONDecoder().decode([String: Record].self, from: $0) } ?? [:]
            }, { cachedHistory = $0 })
        }
        set {
            // The 300 most recent changes are plenty and keep the store small.
            let kept = newValue.count > 300 ? Dictionary(uniqueKeysWithValues: newValue.sorted { $0.value.last > $1.value.last }.prefix(300).map { ($0.key, $0.value) }) : newValue
            UserDefaults.standard.set(try? JSONEncoder().encode(kept), forKey: historyKey)
            lock.lock(); cachedHistory = kept; lock.unlock()
        }
    }

    /// Own outcomes pull the model's chance towards what happened; they count like `priorWeight`
    /// changes against it, so two or three of your own barely move it.
    static let priorWeight = 8.0

    static func adjusted(_ chance: Double, by record: Record?) -> Double {
        guard let r = record, r.total > 0 else { return chance }
        return (priorWeight * chance + Double(r.made)) / (priorWeight + Double(r.total))
    }

    // MARK: Recording

    struct Outcome: Equatable, Sendable {
        let key: String
        let walk: TransferWalk
        /// Seconds from the arrival of the incoming ride to reaching the next stop; nil when not seen.
        let walkSeconds: Double?
        let made: Bool
    }

    static func record(_ o: Outcome, at date: Date = .now) {
        guard isEnabled else { return }
        if let s = o.walkSeconds {
            var m = model
            m.add(o.walk, seconds: s)
            model = m
        }
        var h = history
        var r = h[o.key] ?? Record()
        if o.made { r.made += 1 } else { r.missed += 1 }
        r.last = date.timeIntervalSince1970
        h[o.key] = r
        history = h
    }

    static var learnedSomething: Bool {
        let d = UserDefaults.standard
        return d.data(forKey: modelKey) != nil || d.data(forKey: historyKey) != nil
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: modelKey)
        UserDefaults.standard.removeObject(forKey: historyKey)
        lock.lock(); cachedModel = nil; cachedHistory = nil; lock.unlock()
    }

    /// A warning about a change: the first one, then only when the chance fell by another 20 points
    /// or the ride got cancelled. `lastWarned` is the chance last warned about (nil: never).
    static func warningDue(chance: Double, cancelled: Bool, lastWarned: Double?) -> Bool {
        guard let last = lastWarned else { return true }
        return cancelled ? last > 0.02 : chance <= last - 0.2
    }

    /// Near enough to count as being at a stop.
    static let atStopMeters = 40.0
}

import Foundation

/// The walk of a change: what makes it longer than the router's plain walking time, and how long
/// it takes this user. The router (MOTIS) already walks at the user's speed when "Use my walking
/// speed" is on; this adds what it does not know – waiting for lifts, a platform that changed after
/// planning, finding the way in a big station – and the user's own extra time.
struct TransferWalk: Equatable, Sendable {
    /// Planned walking seconds (sum of the walk legs between the two vehicles).
    var plannedSeconds: Double
    /// Floors climbed or descended (from the walk steps' levels).
    var levels: Double = 0
    var elevators = 0
    /// The live platform differs from the planned one (the router's walk was for the old platform).
    var platformChanged = false
    /// Arriving and leaving at different stations.
    var stationChange = false
    /// Three or more levels in the walk: a big multi-level station.
    var bigStation = false

    init(plannedSeconds: Double, levels: Double = 0, elevators: Int = 0, platformChanged: Bool = false,
         stationChange: Bool = false, bigStation: Bool = false) {
        self.plannedSeconds = plannedSeconds
        self.levels = levels
        self.elevators = elevators
        self.platformChanged = platformChanged
        self.stationChange = stationChange
        self.bigStation = bigStation
    }

    init(incoming: Leg, walks: [Leg], outgoing: Leg) {
        plannedSeconds = Double(walks.reduce(0) { $0 + $1.duration })
        var floors = 0.0, lifts = 0
        var seen = Set<Double>()
        for step in walks.flatMap({ $0.steps ?? [] }) {
            if let a = step.fromLevel, let b = step.toLevel { floors += abs(b - a); seen.insert(a); seen.insert(b) }
            if step.relativeDirection == "ELEVATOR" { lifts += 1 }
        }
        levels = floors
        elevators = lifts
        bigStation = seen.count >= 3
        func moved(_ p: Place) -> Bool { p.track != nil && p.scheduledTrack != nil && p.track != p.scheduledTrack }
        platformChanged = moved(incoming.to) || moved(outgoing.from)
        stationChange = incoming.to.stationId != outgoing.from.stationId
    }
}

/// How long changes take this user. Starts from general values; "Learn from my trips" moves them
/// (`TripLearning`, a Bayesian update). All in seconds except the factor and the spreads.
struct WalkModel: Equatable, Sendable, Codable {
    /// Multiplier on the router's walking time (median). 1.05: walks take a little longer than planned.
    var factor = 1.05
    var perLevel = 10.0
    var perElevator = 30.0
    var platformChange = 60.0
    var stationChange = 30.0
    var bigStation = 30.0
    /// Getting off, finding the way: the user's own overhead per change.
    var overhead = 0.0
    /// Spread of the walk time around the model (log-normal sigma).
    var sigma = 0.10
    /// Uncertainty of the seven values above (covariance, row-major 7 × 7). Learning shrinks it.
    var covariance: [Double] = WalkModel.priorCovariance
    /// Changes the model has learned from.
    var observations = 0

    static let priorSD: [Double] = [0.20, 10, 30, 45, 45, 30, 15]
    static let priorCovariance: [Double] = (0..<49).map { $0 % 8 == 0 ? pow(priorSD[$0 / 7], 2) : 0 }
    static let prior = WalkModel()
    static let storageKey = "smartWalkModel"

    var parameters: [Double] { [factor, perLevel, perElevator, platformChange, stationChange, bigStation, overhead] }

    init() {}

    init(parameters p: [Double], sigma: Double, covariance: [Double], observations: Int) {
        factor = p[0]; perLevel = p[1]; perElevator = p[2]; platformChange = p[3]
        stationChange = p[4]; bigStation = p[5]; overhead = p[6]
        self.sigma = sigma; self.covariance = covariance; self.observations = observations
    }

    /// The learned model when "Learn from my trips" is on and has learned one, else the general values.
    static var current: WalkModel {
        guard UserDefaults.standard.bool(forKey: SmartRouting.learnTripsKey),
              let data = UserDefaults.standard.data(forKey: storageKey),
              let m = try? JSONDecoder().decode(WalkModel.self, from: data), m.covariance.count == 49 else { return .prior }
        return m
    }

    static func features(_ w: TransferWalk) -> [Double] {
        [w.plannedSeconds, w.levels, Double(w.elevators), w.platformChanged ? 1 : 0, w.stationChange ? 1 : 0, w.bigStation ? 1 : 0, 1]
    }

    /// Expected walk in seconds for a change (without the user's "Extra time for changes").
    func expectedSeconds(_ w: TransferWalk) -> Double {
        zip(parameters, Self.features(w)).reduce(0) { $0 + $1.0 * $1.1 }
    }

    /// Spread for this walk: the model's own plus how unsure the model still is (x' C x).
    func spread(_ w: TransferWalk) -> Double {
        let x = Self.features(w), mid = expectedSeconds(w)
        guard mid > 0 else { return sigma }
        var v = 0.0
        for i in 0..<7 { for j in 0..<7 { v += x[i] * covariance[i * 7 + j] * x[j] } }
        return (sigma * sigma + max(0, v) / (mid * mid)).squareRoot()
    }

    /// Seven equally likely walk times around the expected one.
    func samples(_ w: TransferWalk, extraSeconds: Double = 0) -> [Double] {
        let mid = max(0, expectedSeconds(w)), s = spread(w)
        return Self.z.map { mid * exp(s * $0) + extraSeconds }
    }

    static let z: [Double] = [-1.465, -0.792, -0.366, 0, 0.366, 0.792, 1.465]
}

import Foundation

/// Smart routing (Settings → Smart routing): routes ranked by how long they feel, changes rated
/// by how likely they work, a backup for each change, and the user's own walking speed.
///
/// The weights come from transport research: waiting feels about 1.7 times and walking about
/// 1.65 times as long as riding (UK meta-analysis, Abrantes & Wardman 2011), and a change on its
/// own costs about 15 minutes of riding (Garcia-Martinez et al. 2018). Everything is computed on
/// the iPhone; what you pick only tunes these weights on the device.
enum SmartRouting {
    static let enabledKey = "smartRouting"
    /// Minutes a change is worth (the "Fewer changes ↔ Faster" slider; learning moves it).
    static let transferMinutesKey = "smartTransferMinutes"
    /// Learned weight of walking.
    static let walkWeightKey = "smartWalkWeight"
    /// Minutes added to every change (luggage, children, slower walking).
    static let extraTransferKey = "smartExtraTransfer"
    static let ownSpeedKey = "smartOwnWalkingSpeed"
    /// Measured walking speed in m/s (`WalkingPace`).
    static let measuredSpeedKey = "smartMeasuredSpeed"
    static let flatWalksKey = "smartFlatWalks"
    static let learnKey = "smartLearn"
    /// "Learn from my trips": walking times and changes from the user's own trips, on the device only (off by default).
    static let learnTripsKey = "smartLearnTrips"

    static let defaultTransferMinutes = 15.0
    static let transferMinutesRange = 3.0...30.0
    static let defaultWalkWeight = 1.65
    static let walkWeightRange = 1.1...2.5
    static let extraTransferChoices = [0, 2, 5, 10]

    private static var defaults: UserDefaults { .standard }

    static var isEnabled: Bool { defaults.object(forKey: enabledKey) as? Bool ?? true }
    static var learns: Bool { defaults.object(forKey: learnKey) as? Bool ?? true }

    // MARK: Weights

    struct Weights: Equatable, Sendable {
        var transferMinutes = SmartRouting.defaultTransferMinutes
        var wait = 1.7
        var walk = SmartRouting.defaultWalkWeight
        /// Arriving later than the earliest route (or leaving earlier, when arriving by a time).
        var lateness = 0.5
        /// What a broken change costs on average: the wait for the next vehicle and the uncertainty.
        var missedChangeMinutes = 20.0
    }

    static var weights: Weights {
        var w = Weights()
        if let t = defaults.object(forKey: transferMinutesKey) as? Double { w.transferMinutes = t.clamped(to: transferMinutesRange) }
        if let k = defaults.object(forKey: walkWeightKey) as? Double { w.walk = k.clamped(to: walkWeightRange) }
        return w
    }

    /// How long a route feels, in minutes, without its place in the time window.
    static func feltMinutes(_ it: Itinerary, weights w: Weights = weights) -> Double {
        var ride = 0.0, walk = 0.0, other = 0.0, wait = 0.0
        for (i, leg) in it.legs.enumerated() {
            let minutes = Double(leg.duration) / 60
            if leg.isTransit { ride += minutes } else if leg.mode == "WALK" { walk += minutes } else { other += minutes }
            if i > 0 {
                let gap = leg.startTime.timeIntervalSince(it.legs[i - 1].endTime) / 60
                if gap > 0 { wait += gap }
            }
        }
        let changes = Double(transitChanges(it))
        let risk = (1 - reliability(it)) * w.missedChangeMinutes
        return ride + other + w.walk * walk + w.wait * wait + w.transferMinutes * changes + risk
    }

    /// Changes between vehicles (the planner's `transfers` can count a stay-seated through-run).
    static func transitChanges(_ it: Itinerary) -> Int { max(0, it.transitLegs.count - 1) }

    /// Cost within a list: felt time plus arriving later than the best (leaving earlier, for arrive-by).
    static func costs(_ list: [Itinerary], arriveBy: Bool, weights w: Weights = weights) -> [Double] {
        guard !list.isEmpty else { return [] }
        let earliestEnd = list.map(\.endTime).min()!
        let latestStart = list.map(\.startTime).max()!
        return list.map { it in
            let shift = arriveBy ? latestStart.timeIntervalSince(it.startTime) : it.endTime.timeIntervalSince(earliestEnd)
            return feltMinutes(it, weights: w) + w.lateness * max(0, shift) / 60 + (it.isCancelled ? 10_000 : 0)
        }
    }

    /// Best first; ties keep the planner's order.
    static func ranked(_ list: [Itinerary], arriveBy: Bool = false, weights w: Weights = weights) -> [Itinerary] {
        let c = costs(list, arriveBy: arriveBy, weights: w)
        return list.indices.sorted { c[$0] != c[$1] ? c[$0] < c[$1] : $0 < $1 }.map { list[$0] }
    }

    /// The route to suggest: lowest cost among more than one that still run.
    static func recommended(_ list: [Itinerary], arriveBy: Bool = false, weights w: Weights = weights) -> Itinerary? {
        guard list.filter({ !$0.isCancelled }).count > 1 else { return nil }
        return ranked(list, arriveBy: arriveBy, weights: w).first { !$0.isCancelled }
    }

    // MARK: Fewer, more different routes

    /// Drops routes that another one beats on everything: leaves no earlier, arrives no later,
    /// with no more changes and not more walking. Walking the whole way is never dropped.
    /// A few more minutes on foot don't save a route that arrives clearly later for it: when the
    /// other one gets there at least 10 min earlier and walks no longer than it saves, it wins
    /// (Krems, 2026-11-28: the same two buses at 19:41 twice, once walking 23 min to arrive 22:06,
    /// once changing again to arrive 22:32).
    static func pruned(_ list: [Itinerary]) -> [Itinerary] {
        let walks = list.map { Double(RouteSort.walkSeconds($0)) }
        return list.enumerated().filter { i, a in
            guard !a.isDirect else { return true }
            return !list.enumerated().contains { j, b in
                guard j != i, !b.isDirect, !b.isCancelled else { return false }
                let saved = a.endTime.timeIntervalSince(b.endTime)
                let walkOK = walks[j] <= walks[i] + 60
                    || (saved >= Reach.longWalkMustSave && walks[j] - walks[i] <= saved)
                let noWorse = b.startTime >= a.startTime && b.endTime <= a.endTime
                    && transitChanges(b) <= transitChanges(a) && walkOK
                let better = b.startTime > a.startTime || b.endTime < a.endTime || transitChanges(b) < transitChanges(a)
                return noWorse && better
            }
        }.map(\.element)
    }

    /// Labels on the routes of a list: the suggested one and the best in each respect.
    enum Badge: String, CaseIterable, Sendable {
        case recommended, fastest, fewestChanges, leastWalking
        /// The route that leaves last and still arrives tonight ("Last connection").
        case lastConnection

        var title: String {
            switch self {
            case .recommended: return L10n.t("Recommended")
            case .fastest: return L10n.t("Fastest")
            case .fewestChanges: return L10n.t("Fewest changes")
            case .leastWalking: return L10n.t("Least walking")
            case .lastConnection: return L10n.t("Last connection")
            }
        }

        var symbol: String {
            switch self {
            case .recommended: return "sparkles"
            case .fastest: return "hare"
            case .fewestChanges: return "arrow.triangle.swap"
            case .leastWalking: return "figure.walk"
            case .lastConnection: return "moon.stars"
            }
        }
    }

    /// Badges by `routeKey`. A badge goes to one route only, and only where the routes differ.
    static func badges(_ list: [Itinerary], arriveBy: Bool = false, weights w: Weights = weights) -> [String: [Badge]] {
        let live = list.filter { !$0.isCancelled && !$0.isDirect }
        guard live.count > 1 else { return [:] }
        var out: [String: [Badge]] = [:]
        func give(_ b: Badge, _ it: Itinerary?) { if let it { out[it.routeKey, default: []].append(b) } }
        give(.recommended, recommended(live, arriveBy: arriveBy, weights: w))
        func best(_ value: (Itinerary) -> Double, minGap: Double) -> Itinerary? {
            let values = live.map(value)
            guard let lo = values.min(), let hi = values.max(), hi - lo >= minGap,
                  values.filter({ $0 == lo }).count == 1 else { return nil }
            return live[values.firstIndex(of: lo)!]
        }
        give(.fastest, best({ Double($0.duration) }, minGap: 120))
        give(.fewestChanges, best({ Double(transitChanges($0)) }, minGap: 1))
        give(.leastWalking, best({ Double(RouteSort.walkSeconds($0)) }, minGap: 180))
        return out
    }

    /// Why the suggested route beats the fastest one, in a few words.
    static func reason(for rec: Itinerary, in list: [Itinerary]) -> String? {
        guard let fastest = list.filter({ !$0.isCancelled && !$0.isDirect }).min(by: { $0.duration < $1.duration }),
              fastest.routeKey != rec.routeKey else { return nil }
        let fewer = transitChanges(fastest) - transitChanges(rec)
        if fewer > 0 { return fewer == 1 ? L10n.t("One change fewer") : L10n.f("%lld changes fewer", fewer) }
        if reliability(rec) - reliability(fastest) >= 0.1 { return L10n.t("Safer change") }
        let walkSaved = (RouteSort.walkSeconds(fastest) - RouteSort.walkSeconds(rec)) / 60
        if walkSaved >= 3 { return L10n.f("%lld min less walking", walkSaved) }
        return nil
    }

    // MARK: Changes: chance and backup

    struct Change: Sendable {
        let stopName: String
        let incoming: Leg
        let outgoing: Leg
        /// Index of the outgoing leg in the itinerary.
        let outgoingIndex: Int
        let walkSeconds: Int
        /// Minutes left after the walk (negative: already broken).
        let spareMinutes: Double
        let chance: Double
        var source: Source = .estimate
        var walk: TransferWalk? = nil

        enum Level: Sendable { case safe, likely, risky }
        /// Where the number comes from: measured delays (with how many observations), the old rule of
        /// thumb, or a through-run (the vehicle continues: nothing to miss).
        enum Source: Equatable, Sendable {
            case history(observations: Int)
            case estimate
            case throughRun
        }
        var level: Level { chance >= 0.9 ? .safe : chance >= 0.7 ? .likely : .risky }
        /// Whole percent, never 100 (nothing is certain) and at least 1.
        var percent: Int { min(99, max(1, Int((chance * 100).rounded()))) }
        /// Only measured chances are shown as a percentage; estimates show their level only.
        var isEstimate: Bool { source == .estimate }
    }

    static func changes(_ it: Itinerary, at now: Date = .now, history: (String?) -> DelayHistory.Table? = { DelayHistoryStore.shared.table(country: $0) },
                        walkModel: WalkModel = .current, extraSeconds: Double = Double(Request.current.extraTransferMinutes) * 60,
                        learned: [TripLearning.Observation]? = TripLearning.isEnabled ? TripLearning.observations : nil) -> [Change] {
        var out: [Change] = []
        let legs = it.legs
        var i = 0
        while i < legs.count {
            guard legs[i].isTransit else { i += 1; continue }
            var j = i + 1
            var walk = 0
            while j < legs.count, !legs[j].isTransit { walk += legs[j].duration; j += 1 }
            guard j < legs.count else { break }
            let spare = (legs[j].startTime.timeIntervalSince(legs[i].endTime) - Double(walk)) / 60
            let tw = TransferWalk(incoming: legs[i], walks: Array(legs[(i + 1)..<j]), outgoing: legs[j])
            let est = chance(incoming: legs[i], outgoing: legs[j], walk: tw, at: now, history: history,
                             walkModel: walkModel, extraSeconds: extraSeconds)
            var c = Change(stopName: legs[i].to.name, incoming: legs[i], outgoing: legs[j], outgoingIndex: j, walkSeconds: walk,
                           spareMinutes: spare, chance: est.chance, source: est.source, walk: tw)
            // Made this change several times before: the own success rate counts too.
            if let learned, est.source != .throughRun {
                c = Change(stopName: c.stopName, incoming: c.incoming, outgoing: c.outgoing, outgoingIndex: j, walkSeconds: walk, spareMinutes: spare,
                           chance: TripLearning.adjusted(est.chance, key: TripLearning.key(c), observations: learned), source: est.source, walk: tw)
            }
            out.append(c)
            i = j
        }
        return out
    }

    /// The vehicle goes on as the next leg: same trip, or the planner marks a stay-seated through-run.
    static func isThroughRun(_ incoming: Leg, _ outgoing: Leg) -> Bool {
        if outgoing.interlineWithPreviousLeg == true { return true }
        guard let a = incoming.tripId, let b = outgoing.tripId else { return false }
        return a == b
    }

    /// Chance a change works: P(feeder arrival + walk ≤ connection departure), with both delays from
    /// measured history (or the live forecast and how far such forecasts are usually off), the walk
    /// from `WalkModel`, and cancellations. Without history: the old rule of thumb, marked as estimate.
    static func chance(incoming: Leg, outgoing: Leg, walk: TransferWalk, at now: Date,
                       history: (String?) -> DelayHistory.Table?, walkModel: WalkModel = .prior,
                       extraSeconds: Double = 0) -> (chance: Double, source: Change.Source) {
        if isThroughRun(incoming, outgoing) { return (1, .throughRun) }
        if incoming.cancelled == true || outgoing.cancelled == true || outgoing.from.cancelled == true { return (0.01, .estimate) }
        let table = history(DelayHistory.country(ofId: incoming.routeId ?? outgoing.routeId))
        let tz = incoming.to.tz.flatMap(TimeZone.init(identifier:)) ?? .current
        func side(_ leg: Leg, arrival: Bool) -> (dist: DelayHistory.Dist, cancel: Double, n: Int)? {
            delay(leg, arrival: arrival, at: now, table: table, timeZone: tz)
        }
        let gap = outgoing.scheduledStartTime.timeIntervalSince(incoming.scheduledEndTime)
        guard let a = side(incoming, arrival: true) else {
            // What the model adds beyond the router's walk (lifts, platform change, …) and the user's extra time.
            let extras = walkModel.expectedSeconds(walk) - walkModel.factor * walk.plannedSeconds
            let spare = (outgoing.startTime.timeIntervalSince(incoming.endTime) - walk.plannedSeconds - extras - extraSeconds) / 60
            return (chance(spareMinutes: spare, walkSeconds: Int(walk.plannedSeconds), incoming: incoming), .estimate)
        }
        let d = side(outgoing, arrival: false)
        let p = onTime(gap: gap, arrival: a.dist, departure: d?.dist ?? .punctual,
                       walk: walkModel.samples(walk, extraSeconds: extraSeconds))
        let n = min(a.n, d?.n ?? a.n)
        let value = cap((1 - a.cancel) * (1 - (d?.cancel ?? 0)) * p, observations: n)
        return (value, d == nil ? .estimate : .history(observations: n))
    }

    /// The delay of a leg at its end (arrival) or start (departure): with live data the current forecast
    /// plus how far such forecasts are usually off at that distance; else the measured history.
    static func delay(_ leg: Leg, arrival: Bool, at now: Date, table: DelayHistory.Table?, timeZone tz: TimeZone)
        -> (dist: DelayHistory.Dist, cancel: Double, n: Int)? {
        let time = arrival ? leg.endTime : leg.startTime
        let sched = arrival ? leg.scheduledEndTime : leg.scheduledStartTime
        let minutesAhead = time.timeIntervalSince(now) / 60
        let row = table?.row(routeId: leg.routeId, stopId: arrival ? leg.to.stopId : leg.from.stopId,
                             agency: leg.agencyName, mode: leg.mode, window: DelayHistory.window(sched, timeZone: tz))
        // Live forecasts rarely miss a cancellation close to departure.
        let cancel = (row?.cancelled ?? 0) * (leg.realTime ? min(1, max(0, minutesAhead) / 60) : 1)
        if leg.realTime, let (err, n) = table?.forecastError(mode: leg.mode, minutesAhead: minutesAhead) {
            return (err.shifted(by: time.timeIntervalSince(sched)), cancel, n)
        }
        guard let row, let d = arrival ? row.arrival : row.departure else { return nil }
        return (d, cancel, row.observations)
    }

    /// P(a + w ≤ gap + d) over equally likely samples of feeder delay, walk and connection delay.
    static func onTime(gap: Double, arrival: DelayHistory.Dist, departure: DelayHistory.Dist, walk: [Double]) -> Double {
        let a = arrival.samples(), d = departure.samples().sorted()
        var hit = 0
        for x in a {
            for w in walk {
                let need = x + w - gap
                var lo = 0, hi = d.count
                while lo < hi { let mid = (lo + hi) / 2; if d[mid] < need { lo = mid + 1 } else { hi = mid } }
                hit += d.count - lo
            }
        }
        return Double(hit) / Double(a.count * walk.count * d.count)
    }

    /// No near-certainty from few observations: between 1/(n+2) and 1 − 1/(n+2).
    static func cap(_ p: Double, observations n: Int) -> Double {
        let lo = 1 / Double(n + 2)
        return min(1 - lo, max(lo, p))
    }

    /// How spread out arrivals of this kind of vehicle are, in minutes (rule of thumb, used without history).
    static func spread(_ mode: String) -> Double {
        switch mode {
        case "HIGHSPEED_RAIL", "LONG_DISTANCE", "NIGHT_RAIL", "AIRPLANE": return 4
        case "RAIL", "REGIONAL_RAIL", "REGIONAL_FAST_RAIL", "SUBURBAN", "COACH": return 2.5
        case "BUS", "FERRY", "FLEX", "ODM": return 2
        case "TRAM", "CABLE_CAR", "FUNICULAR", "AERIAL_LIFT", "AREAL_LIFT": return 1.5
        case "SUBWAY", "METRO": return 1
        default: return 2
        }
    }

    /// The rule of thumb used before measured delays (and still without them): a logistic curve over
    /// the minutes left, wider for vehicles that run late more often, narrower with live times.
    static func chance(spareMinutes: Double, walkSeconds: Int, incoming: Leg) -> Double {
        var s = spread(incoming.mode)
        if incoming.realTime { s *= 0.6 }
        // Walks take a little longer than planned now and then.
        let margin = spareMinutes - Double(walkSeconds) / 60 * 0.1
        let x = (margin + 0.5 - s / 2) / (s * 0.6)
        return (1 / (1 + exp(-x))).clamped(to: 0.01...0.995)
    }

    /// Chance the whole route works as planned.
    static func reliability(_ it: Itinerary) -> Double { changes(it).reduce(1) { $0 * $1.chance } }

    /// The next vehicle that can replace a leg if its change is missed (from `numLegAlternatives`).
    struct Backup: Sendable {
        let leg: Leg
        /// Arrival at the end of the replaced leg (with its walk).
        let arrival: Date
    }

    static func backup(for leg: Leg) -> Backup? {
        let options = (leg.alternatives ?? []).compactMap { alt -> Backup? in
            guard let ride = alt.first(where: \.isTransit), ride.startTime > leg.startTime.addingTimeInterval(59),
                  ride.cancelled != true else { return nil }
            return Backup(leg: ride, arrival: alt.last?.endTime ?? ride.endTime)
        }
        return options.min { $0.leg.startTime < $1.leg.startTime }
    }

    // MARK: Live trip

    /// A change still ahead that has become unlikely (or broken): time to look for another way.
    static func changeAtRisk(_ it: Itinerary, at now: Date) -> Change? {
        changes(it, at: now).first { $0.outgoing.startTime > now && $0.incoming.endTime > now.addingTimeInterval(-120) && $0.chance < 0.5 }
    }

    // MARK: Request

    /// What smart routing adds to the search.
    struct Request: Equatable, Sendable {
        var enabled = false
        var pedestrianSpeed: Double? = nil
        var extraTransferMinutes = 0
        var flatWalks = false

        static var current: Request {
            guard SmartRouting.isEnabled else { return Request() }
            let d = UserDefaults.standard
            var r = Request(enabled: true)
            if d.bool(forKey: ownSpeedKey), let v = d.object(forKey: measuredSpeedKey) as? Double, (0.6...2.2).contains(v) {
                r.pedestrianSpeed = (v * 100).rounded() / 100
            }
            r.extraTransferMinutes = max(0, d.integer(forKey: extraTransferKey))
            r.flatWalks = d.bool(forKey: flatWalksKey)
            return r
        }

        var queryItems: [URLQueryItem] {
            guard enabled else { return [] }
            var q = [URLQueryItem(name: "numLegAlternatives", value: "2"),
                     // Direct rides that a faster route with changes overtakes; `pruned` drops the useless ones.
                     URLQueryItem(name: "slowDirect", value: "true"),
                     URLQueryItem(name: "fastestSlowDirectFactor", value: "1.5")]
            if let pedestrianSpeed { q.append(URLQueryItem(name: "pedestrianSpeed", value: String(pedestrianSpeed))) }
            if extraTransferMinutes > 0 { q.append(URLQueryItem(name: "additionalTransferTime", value: String(extraTransferMinutes))) }
            if flatWalks { q.append(URLQueryItem(name: "elevationCosts", value: "LOW")) }
            return q
        }

        var key: String { enabled ? "s\(pedestrianSpeed.map { String($0) } ?? "-")|\(extraTransferMinutes)|\(flatWalks)" : "off" }
    }

    // MARK: Learning

    /// Routes last offered in the planner, to learn from the one that is saved.
    @MainActor static var offered: [Itinerary] = []
    @MainActor static var offeredArriveBy = false

    /// Picking a route other than the suggested one moves the weights a little towards it.
    @MainActor static func learn(chosen: Itinerary) {
        guard isEnabled, learns, offered.contains(where: { $0.routeKey == chosen.routeKey }) else { return }
        let w = learned(chosen: chosen, offered: offered, arriveBy: offeredArriveBy, weights: weights)
        defaults.set(w.transferMinutes, forKey: transferMinutesKey)
        defaults.set(w.walk, forKey: walkWeightKey)
    }

    static func learned(chosen: Itinerary, offered: [Itinerary], arriveBy: Bool, weights: Weights) -> Weights {
        var w = weights
        guard let rec = recommended(offered, arriveBy: arriveBy, weights: weights), rec.routeKey != chosen.routeKey else { return w }
        let changeDiff = transitChanges(chosen) - transitChanges(rec)
        if changeDiff < 0 { w.transferMinutes += 2 } else if changeDiff > 0 { w.transferMinutes -= 2 }
        let walkDiff = Double(RouteSort.walkSeconds(chosen) - RouteSort.walkSeconds(rec)) / 60
        if walkDiff <= -2 { w.walk += 0.1 } else if walkDiff >= 2 { w.walk -= 0.1 }
        w.transferMinutes = w.transferMinutes.clamped(to: transferMinutesRange)
        w.walk = (w.walk * 100).rounded() / 100
        w.walk = w.walk.clamped(to: walkWeightRange)
        return w
    }

    static func resetLearning() {
        defaults.removeObject(forKey: transferMinutesKey)
        defaults.removeObject(forKey: walkWeightKey)
        TripLearning.reset()
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}

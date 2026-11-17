import Foundation

/// Watches the changes of a started or remembered trip and decides when to warn (notification in
/// `ChangeRiskNotifier`). Recomputed on the device whenever live data or the user's position moves;
/// no server push. At most one warning per change, a second one only if it gets clearly worse
/// (or the connection is cancelled). None for through-runs.
enum ChangeWatch {
    static let enabledKey = "smartChangeAlerts"
    static var isEnabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
    /// Below "likely": risky.
    static let threshold = 0.7
    /// A second warning only after the chance fell this much more.
    static let worse = 0.15
    private static let warnedKey = "changeWatchWarned"

    static func key(_ c: SmartRouting.Change) -> String {
        // Time first: sorting the keys sorts by time (old ones are dropped first).
        "\(Int64(c.outgoing.scheduledStartTime.timeIntervalSince1970))|\(c.incoming.to.stationId)|\(c.outgoing.tripId ?? c.outgoing.lineName)"
    }

    static func isCancelled(_ c: SmartRouting.Change) -> Bool {
        c.outgoing.cancelled == true || c.outgoing.from.cancelled == true || c.incoming.cancelled == true
    }

    /// The changes still ahead that need a warning now. `warned`: chance at the last warning, by key.
    static func due(_ changes: [SmartRouting.Change], warned: [String: Double], now: Date) -> [SmartRouting.Change] {
        changes.filter { c in
            guard c.source != .throughRun, c.outgoing.startTime > now else { return false }
            let cancelled = isCancelled(c)
            guard cancelled || c.chance < threshold else { return false }
            guard let last = warned[key(c)] else { return true }
            return c.chance <= last - worse
        }
    }

    /// On foot between the two vehicles: the chance from where the user is now, at their pace
    /// (metres per second), with the connection's live or measured departure delay. nil outside the walk.
    static func onFoot(_ c: SmartRouting.Change, here: LatLon, now: Date, speed: Double,
                       table: DelayHistory.Table?, model: WalkModel = .current) -> Double? {
        guard now >= c.incoming.endTime.addingTimeInterval(-60), now < c.outgoing.startTime.addingTimeInterval(120), speed > 0.2 else { return nil }
        // Straight line to the stop × 1.3 for the real path.
        let seconds = here.distance(to: c.outgoing.from.coordinate) * 1.3 / speed
        let tz = c.outgoing.from.tz.flatMap(TimeZone.init(identifier:)) ?? .current
        let dep = SmartRouting.delay(c.outgoing, arrival: false, at: now, table: table, timeZone: tz)?.dist
            ?? DelayHistory.Dist.punctual.shifted(by: c.outgoing.startTime.timeIntervalSince(c.outgoing.scheduledStartTime))
        let walk = WalkModel.z.map { seconds * exp(model.sigma * $0) }
        let gap = c.outgoing.scheduledStartTime.timeIntervalSince(now)
        return SmartRouting.onTime(gap: gap, arrival: .punctual, departure: dep, walk: walk)
    }

    /// Later vehicles the router offered for the connection (`numLegAlternatives`).
    static func alternatives(_ c: SmartRouting.Change) -> Int {
        (c.outgoing.alternatives ?? []).filter { alt in
            alt.first(where: \.isTransit).map { $0.startTime > c.outgoing.startTime.addingTimeInterval(59) && $0.cancelled != true } ?? false
        }.count
    }

    static func message(_ c: SmartRouting.Change) -> String {
        if isCancelled(c) { return L10n.f("Your connection at %@ is cancelled – tap for other routes", c.stopName) }
        let n = alternatives(c)
        return n > 0 ? L10n.f("Your connection at %@ is unlikely – %lld alternatives", c.stopName, n)
            : L10n.f("Your connection at %@ is unlikely – tap for other routes", c.stopName)
    }

    // MARK: State

    static var warned: [String: Double] {
        (UserDefaults.standard.dictionary(forKey: warnedKey) as? [String: Double]) ?? [:]
    }

    static func markWarned(_ c: SmartRouting.Change) {
        var w = warned
        w[key(c)] = isCancelled(c) ? 0 : c.chance
        if w.count > 100 { w = Dictionary(uniqueKeysWithValues: w.sorted { $0.key < $1.key }.suffix(100).map { ($0.key, $0.value) }) }
        UserDefaults.standard.set(w, forKey: warnedKey)
    }
}

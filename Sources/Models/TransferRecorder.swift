import Foundation

/// Watches a started trip's changes from the phone's position, in memory only: were you at the
/// stop when the ride arrived, when did you reach the next one, did you catch it. Each finished
/// change becomes one `TransferLearning.Outcome`; the positions are dropped right away.
@MainActor
final class TransferRecorder {
    static let shared = TransferRecorder()

    private struct Watch {
        var present = false
        var reached: Date?
        var done = false
    }

    private var watches: [String: Watch] = [:]

    func handle(_ fix: LatLon, accuracy: Double, at now: Date, trip: SavedTrip) {
        guard TransferLearning.isEnabled, accuracy >= 0, accuracy <= 60 else { return }
        let it = trip.itinerary
        for change in SmartRouting.changes(it) where !change.isThroughRun && change.walk.plannedSeconds >= 30 {
            let id = "\(trip.id)|\(change.outgoingIndex)"
            var w = watches[id] ?? Watch()
            guard !w.done else { continue }
            let arrival = change.incoming.endTime, departure = change.outgoing.startTime
            if !w.present, now >= arrival.addingTimeInterval(-300), now <= arrival.addingTimeInterval(180),
               fix.distance(to: change.incoming.to.coordinate) <= 150 { w.present = true }
            if w.present, w.reached == nil, now >= arrival.addingTimeInterval(-60),
               fix.distance(to: change.outgoing.from.coordinate) <= max(TransferLearning.atStopMeters, accuracy) { w.reached = now }
            // Decided once the next ride has left: on it (seen on its way) or not.
            if now > departure.addingTimeInterval(120) {
                w.done = true
                if w.present, let outcome = Self.outcome(change, reached: w.reached, fix: fix, now: now) {
                    TransferLearning.record(outcome, at: now)
                }
            }
            watches[id] = w
        }
        watches = watches.filter { $0.key.hasPrefix(trip.id) }
    }

    /// Made it: you reached the stop before the ride left. Missed: you got there later, or you are
    /// still near the stop well after it left. Anything else (no fix in between) is not counted.
    nonisolated static func outcome(_ change: SmartRouting.Change, reached: Date?, fix: LatLon, now: Date) -> TransferLearning.Outcome? {
        let key = TransferLearning.key(incoming: change.incoming, outgoing: change.outgoing)
        let departure = change.outgoing.startTime
        let seconds = reached.map { $0.timeIntervalSince(change.incoming.endTime) }
        // A walk that took more than three times the plan plus 5 min was a coffee, not a change.
        let plausible = seconds.flatMap { $0 > 0 && $0 < 3 * change.walk.plannedSeconds + 300 ? $0 : nil }
        if let reached {
            return .init(key: key, walk: change.walk, walkSeconds: plausible, made: reached <= departure.addingTimeInterval(20))
        }
        if fix.distance(to: change.outgoing.from.coordinate) <= 150 {
            return .init(key: key, walk: change.walk, walkSeconds: nil, made: false)
        }
        return nil
    }
}

import Foundation

/// Where the traveller is in a trip at a given moment: drives the leave reminder,
/// the Live Activity and the status line of a saved trip.
struct TripStatus: Equatable, Sendable {
    enum Phase: String, Codable, Sendable { case beforeLeaving, walking, riding, transfer, arrived, cancelled }

    let phase: Phase
    /// The next moment that matters (leave, departure, arrival).
    let nextEvent: Date
    /// Short line for lock screen and notifications, e.g. "Leave in 6 min".
    let headline: String
    /// e.g. "U6 to Garching from Marienplatz, Pl. 2 at 16:12".
    let detail: String
    let delayMinutes: Int

    /// Minutes before leaving at which the leave reminder fires.
    static let leaveLead: TimeInterval = 5 * 60

    static func leaveTime(_ it: Itinerary) -> Date { it.startTime }
    static func reminderTime(_ it: Itinerary) -> Date { leaveTime(it).addingTimeInterval(-leaveLead) }

    static func at(_ now: Date, _ it: Itinerary) -> TripStatus {
        let tz = it.legs.first?.from.tz
        let transit = it.transitLegs
        func describe(_ leg: Leg) -> String {
            var s = leg.lineName
            if let h = leg.headsign, !h.isEmpty { s += " to \(h)" }
            s += " from \(leg.from.name)"
            if let t = leg.from.track, !t.isEmpty { s += ", Pl. \(t)" }
            return s + " at \(Fmt.time(leg.startTime, tz: leg.from.tz))"
        }
        if it.isCancelled {
            let leg = it.legs.first { $0.cancelled == true }
            return TripStatus(phase: .cancelled, nextEvent: it.startTime, headline: "Connection cancelled",
                              detail: leg.map { "\($0.lineName) from \($0.from.name) does not run." } ?? "Plan again.",
                              delayMinutes: 0)
        }
        let delay = transit.first?.delayMinutes ?? 0
        if now >= it.endTime {
            return TripStatus(phase: .arrived, nextEvent: it.endTime, headline: "Arrived",
                              detail: "at \(it.legs.last?.to.name ?? "destination") \(Fmt.time(it.endTime, tz: it.legs.last?.to.tz))",
                              delayMinutes: 0)
        }
        if now < it.startTime {
            let mins = Int(ceil(it.startTime.timeIntervalSince(now) / 60))
            let head = mins <= 0 ? "Leave now" : mins < 60 ? "Leave in \(mins) min" : "Leave at \(Fmt.time(it.startTime, tz: tz))"
            let det = transit.first.map(describe) ?? "Walk \(Fmt.duration(seconds: it.duration))"
            return TripStatus(phase: .beforeLeaving, nextEvent: it.startTime, headline: head, detail: det, delayMinutes: delay)
        }
        // Underway: find the leg we are in.
        guard let i = it.legs.firstIndex(where: { now < $0.endTime }) else {
            return TripStatus(phase: .arrived, nextEvent: it.endTime, headline: "Arrived", detail: "", delayMinutes: 0)
        }
        let leg = it.legs[i]
        if leg.isTransit {
            if now < leg.startTime {
                return TripStatus(phase: .transfer, nextEvent: leg.startTime,
                                  headline: "\(leg.lineName) departs \(Fmt.time(leg.startTime, tz: leg.from.tz))",
                                  detail: describe(leg), delayMinutes: leg.delayMinutes)
            }
            return TripStatus(phase: .riding, nextEvent: leg.endTime,
                              headline: "Get off at \(leg.to.name)",
                              detail: "\(leg.lineName) arrives \(Fmt.time(leg.endTime, tz: leg.to.tz))",
                              delayMinutes: Int((leg.endTime.timeIntervalSince(leg.scheduledEndTime) / 60).rounded()))
        }
        if let next = it.legs[(i + 1)...].first(where: \.isTransit) {
            return TripStatus(phase: i == 0 ? .walking : .transfer, nextEvent: next.startTime,
                              headline: "Walk to \(next.from.name)", detail: describe(next), delayMinutes: next.delayMinutes)
        }
        return TripStatus(phase: .walking, nextEvent: it.endTime, headline: "Walk to \(it.legs.last?.to.name ?? "destination")",
                          detail: "Arrive \(Fmt.time(it.endTime, tz: it.legs.last?.to.tz))", delayMinutes: 0)
    }
}

/// Text for the calendar event of a saved trip. The URL opens the trip with its live status.
enum CalendarText {
    static func title(_ trip: SavedTrip) -> String {
        let lines = trip.itinerary.transitLegs.map(\.lineName)
        return lines.isEmpty ? "Walk to \(trip.toName)" : "\(trip.toName) (\(lines.joined(separator: ", ")))"
    }

    static func notes(_ trip: SavedTrip) -> String {
        var out: [String] = []
        for leg in trip.itinerary.legs where leg.isTransit {
            var s = "\(Fmt.time(leg.startTime, tz: leg.from.tz)) \(leg.lineName)"
            if let h = leg.headsign, !h.isEmpty { s += " → \(h)" }
            s += ", \(leg.from.name)"
            if let t = leg.from.track, !t.isEmpty { s += " (Pl. \(t))" }
            s += " – \(leg.to.name) \(Fmt.time(leg.endTime, tz: leg.to.tz))"
            out.append(s)
        }
        out.append("")
        out.append("Live status and tickets: \(trip.deepLink.absoluteString)")
        return out.joined(separator: "\n")
    }

    static func location(_ trip: SavedTrip) -> String {
        trip.itinerary.firstTransitLeg?.from.name ?? trip.fromName
    }
}

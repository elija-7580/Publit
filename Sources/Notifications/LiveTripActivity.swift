import Foundation
import ActivityKit

/// Starts, updates and ends the Live Activity of a saved trip.
/// Updates happen whenever the app refreshes the trip (on open and every minute while visible);
/// the countdown itself runs on the lock screen without updates.
@MainActor
enum LiveTripActivity {
    /// iOS keeps a Live Activity for up to 8 hours.
    static let maxLead: TimeInterval = 8 * 3600

    static var isAvailable: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    static func current(_ tripId: String) -> Activity<TripActivityAttributes>? {
        Activity<TripActivityAttributes>.activities.first { $0.attributes.tripId == tripId }
    }

    static func isRunning(_ tripId: String) -> Bool { current(tripId) != nil }

    static func state(for trip: SavedTrip, now: Date = .now) -> TripActivityAttributes.ContentState {
        let s = TripStatus.at(now, trip.itinerary)
        let leg = trip.itinerary.legs.first { $0.isTransit && $0.endTime > now } ?? trip.itinerary.firstTransitLeg
        return .init(phase: s.phase.rawValue, headline: s.headline, detail: s.detail, nextEvent: s.nextEvent,
                     delayMinutes: s.delayMinutes, arrival: trip.endTime, lineName: leg?.lineName,
                     lineColor: leg?.lineColors.background, lineTextColor: leg?.lineColors.text, updatedAt: now)
    }

    enum StartResult { case started, tooEarly, unavailable, failed(String) }

    @discardableResult
    static func start(_ trip: SavedTrip, hasTicket: Bool, now: Date = .now) -> StartResult {
        guard isAvailable else { return .unavailable }
        guard trip.startTime.timeIntervalSince(now) < maxLead else { return .tooEarly }
        if let running = current(trip.id) {
            Task { await running.update(content(trip, now: now)) }
            return .started
        }
        let attrs = TripActivityAttributes(tripId: trip.id, title: trip.title, hasTicket: hasTicket)
        do {
            _ = try Activity.request(attributes: attrs, content: content(trip, now: now), pushType: nil)
            return .started
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    static func update(_ trip: SavedTrip, now: Date = .now) async {
        guard let a = current(trip.id) else { return }
        if now > trip.endTime.addingTimeInterval(10 * 60) {
            await a.end(content(trip, now: now), dismissalPolicy: .default)
        } else {
            await a.update(content(trip, now: now))
        }
    }

    static func end(_ tripId: String) async {
        guard let a = current(tripId) else { return }
        await a.end(nil, dismissalPolicy: .immediate)
    }

    private static func content(_ trip: SavedTrip, now: Date) -> ActivityContent<TripActivityAttributes.ContentState> {
        ActivityContent(state: state(for: trip, now: now), staleDate: trip.endTime.addingTimeInterval(15 * 60))
    }
}

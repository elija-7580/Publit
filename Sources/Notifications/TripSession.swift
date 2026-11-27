import Foundation

/// Starting and ending a trip by hand: the live bar and trip screen switch to the guide,
/// the Live Activity starts and a get-off reminder is set for each ride.
@MainActor
enum TripSession {
    /// Returns a note for the user about the lock screen.
    @discardableResult
    static func start(_ trip: SavedTrip, in trips: TripStore, hasTicket: Bool) async -> String {
        let previous = trips.start(trip.id)
        if let previous, previous != trip.id {
            LeaveReminder.cancel(previous)
            if let old = trips.trip(previous) { GetOffReminder.cancelAll(old.itinerary) }
            await LiveTripActivity.end(previous)
        }
        let note: String
        switch LiveTripActivity.start(trip, hasTicket: hasTicket) {
        case .started: note = L10n.t("Follow it on the lock screen.")
        case .tooEarly: note = L10n.t("Live updates on the lock screen start 8 hours before.")
        case .unavailable, .failed: note = L10n.t("Live tracking is active in the app. Lock screen updates may be unavailable.")
        }
        await GetOffReminder.scheduleAll(trip.itinerary)
        return note
    }

    /// New live times were stored for a trip outside its own screen (background refresh, on board with
    /// the screen locked): the leave and get-off reminders move with them, and a new platform, a
    /// cancellation or a later arrival is announced. Without this the stored times were already the new
    /// ones when the app came back, nothing differed any more, and a get-off reminder rang at the old time.
    static func follow(_ old: SavedTrip, to updated: SavedTrip) async {
        await LiveTripActivity.update(updated)
        await LeaveReminder.follow(old, to: updated)
        await GetOffReminder.follow(from: old.itinerary, to: updated.itinerary)
        await TripChangeAlert.follow(old.id, from: old.itinerary, to: updated.itinerary)
        await ArrivalUpdates.follow(updated)
    }

    private static var lastRefresh: [String: Date] = [:]
    private static var lastActivityUpdate: [String: Date] = [:]

    /// While the location follows a started trip with the screen locked, nothing else refreshes it:
    /// live times at most every two minutes, with everything that depends on them (`follow`), and the
    /// Live Activity moved on at most twice a minute (boarding, riding, arrived). Returns the trip as stored.
    @discardableResult
    static func refreshIfDue(_ trip: SavedTrip, in trips: TripStore, now: Date = .now) async -> SavedTrip {
        if lastRefresh[trip.id].map({ now.timeIntervalSince($0) > 120 }) ?? true {
            lastRefresh[trip.id] = now
            if let fresh = try? await TripRefreshCoordinator.shared.refresh(route: trip.itinerary),
               trips.update(trip.id, with: fresh, replacing: trip.itinerary), let updated = trips.trip(trip.id) {
                lastActivityUpdate[trip.id] = now
                await follow(trip, to: updated)
                return updated
            }
        }
        let current = trips.trip(trip.id) ?? trip
        if lastActivityUpdate[trip.id].map({ now.timeIntervalSince($0) > 30 }) ?? true {
            lastActivityUpdate[trip.id] = now
            await LiveTripActivity.update(current, now: now)
        }
        return current
    }

    static func forgetRefresh(_ tripId: String) {
        lastRefresh[tripId] = nil; lastActivityUpdate[tripId] = nil
    }

    /// Switches a running trip to a new connection: reminders and the Live Activity follow.
    static func reroute(_ trip: SavedTrip, to itinerary: Itinerary, in trips: TripStore) async {
        LeaveReminder.cancel(trip.id)
        GetOffReminder.cancelAll(trip.itinerary)
        trips.reroute(trip.id, with: itinerary, from: L10n.t("Current location"))
        guard let updated = trips.trip(trip.id) else { return }
        await LiveTripActivity.update(updated)
        await GetOffReminder.scheduleAll(updated.itinerary)
    }

    static func stop(_ trip: SavedTrip, in trips: TripStore) async {
        trips.stop(trip.id)
        GetOffAlerts.forget(trip.id)
        LeaveReminder.cancel(trip.id)
        GetOffReminder.cancelAll(trip.itinerary)
        await LiveTripActivity.end(trip.id)
    }
}

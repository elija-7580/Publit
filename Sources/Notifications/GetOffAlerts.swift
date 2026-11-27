import Foundation
import CoreLocation
import UserNotifications

/// The get-off alert from where the phone is on board (#69): while a started trip rides a vehicle,
/// each location fix is laid onto the line; at the chosen milestone ("one stop before" …) a
/// notification goes out at once and replaces the time-based reminder of that ride. Each ride gets
/// one alert, whichever comes first. Everything happens on the phone; nothing about the position leaves it.
@MainActor
enum GetOffAlerts {
    /// Fixes less accurate than this are ignored (inside a station, in a tunnel).
    static let maxAccuracy: CLLocationAccuracy = 100
    private static let deliveredKey = "getOffDelivered"

    /// How long before the first ride the location starts to follow a started trip.
    static let trackingLead: TimeInterval = 20 * 60

    /// Location follows a started trip from shortly before its first ride until after its last one,
    /// without a gap, and only when the alert uses location at all. It used to follow each ride from
    /// two minutes before it: with the phone locked earlier than that, or during a longer change,
    /// tracking was off, iOS suspended the app, and nothing woke it for the ride: no alert.
    static func wantsTracking(_ trip: SavedTrip?, now: Date = .now) -> Bool {
        guard let trip, GetOffAlert.current.usesLocation else { return false }
        return TripStatus.isBetweenRides(trip.itinerary, at: now, lead: trackingLead, after: 10 * 60)
    }

    /// A ride whose alert has gone out (by location or by the clock): no second one.
    static func wasDelivered(_ leg: Leg) -> Bool {
        (UserDefaults.standard.stringArray(forKey: deliveredKey) ?? []).contains(GetOffReminder.identifier(for: leg))
    }

    private static func markDelivered(_ leg: Leg) {
        var list = UserDefaults.standard.stringArray(forKey: deliveredKey) ?? []
        list.append(GetOffReminder.identifier(for: leg))
        UserDefaults.standard.set(Array(list.suffix(50)), forKey: deliveredKey)
    }

    /// The last "next stop" told to the Live Activity, so it is updated only when that changes.
    private static var lastRideNote: [String: String] = [:]
    /// "Next stop: Odeonsplatz · 2 stops to go", per running trip, for the Live Activity.
    static func rideNote(_ tripId: String) -> String? { lastRideNote[tripId] }

    static func handle(_ fix: CLLocation, trip: SavedTrip, now: Date = .now) async {
        guard fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= maxAccuracy,
              now.timeIntervalSince(fix.timestamp) < 30 else { return }
        let here = LatLon(lat: fix.coordinate.latitude, lon: fix.coordinate.longitude)
        guard let leg = trip.itinerary.transitLegs.first(where: { $0.startTime.addingTimeInterval(-60) <= now && $0.endTime.addingTimeInterval(10 * 60) >= now }) else { return }
        let ride = TripGuide.ridePosition(leg, at: now, location: here)
        guard ride.fromGPS else { return }
        let stops = leg.allStops

        // The Live Activity: next stop and stops still to go, from where you really are.
        if let next = TripProgress.nextStopIndex(ride.progress, count: stops.count) {
            let left = TripGuide.stopsLeft(ride.progress, count: stops.count)
            let note = left <= 1 ? L10n.f("Next stop: %@. Get off there.", stops[next].name)
                : L10n.f("Next stop: %@ · %lld stops to go", stops[next].name, left)
            if lastRideNote[trip.id] != note {
                lastRideNote[trip.id] = note
                await LiveTripActivity.update(trip, now: now)
            }
        }

        let alert = GetOffAlert.current
        guard !wasDelivered(leg),
              GetOffWatch.isDue(alert, progress: ride.progress, stopCount: stops.count,
                                metresToExit: here.distance(to: leg.to.coordinate)) else { return }
        // The clock-based reminder may already have fired: then this would be a second one.
        let id = GetOffReminder.identifier(for: leg)
        // Marked before waiting: the next fix arrives a second later and must not post the alert again.
        markDelivered(leg)
        let delivered = await UNUserNotificationCenter.current().deliveredNotifications()
        if delivered.contains(where: { $0.request.identifier == id }) { return }
        await post(leg, stopsLeft: TripGuide.stopsLeft(ride.progress, count: stops.count))
    }

    /// Goes out now, under the same identifier as the time-based reminder: that one is replaced.
    private static func post(_ leg: Leg, stopsLeft: Int) async {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = L10n.t("Get off soon")
        content.body = GetOffWatch.message(exit: leg.to.name, stopsLeft: stopsLeft)
        content.sound = .default
        content.interruptionLevel = .active
        center.removePendingNotificationRequests(withIdentifiers: [GetOffReminder.identifier(for: leg)])
        try? await center.add(UNNotificationRequest(identifier: GetOffReminder.identifier(for: leg), content: content, trigger: nil))
    }

    static func forget(_ tripId: String) { lastRideNote[tripId] = nil }
}

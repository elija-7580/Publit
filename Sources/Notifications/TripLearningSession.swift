import Foundation
import CoreLocation

/// Glue between location fixes during a started trip and the on-device learning and change alerts.
/// Fixes are used at once and dropped; only the derived values per change are kept (`TripLearning`).
@MainActor
enum TripLearningSession {
    private static var recorders: [String: TripLearning.Recorder] = [:]
    private static var lastFollow: [String: Date] = [:]

    /// Location is wanted from shortly before the first ride until shortly after the last one,
    /// when learning is on (the walks between rides are what it learns from).
    static func wantsTracking(_ trip: SavedTrip?, now: Date = .now) -> Bool {
        guard let trip, TripLearning.isEnabled, SmartRouting.isEnabled,
              let first = trip.itinerary.transitLegs.first, let last = trip.itinerary.transitLegs.last,
              trip.itinerary.transitLegs.count > 1 else { return false }
        return first.startTime.addingTimeInterval(-120) <= now && last.endTime.addingTimeInterval(10 * 60) >= now
    }

    static func handle(_ fix: CLLocation, trip: SavedTrip, trips: TripStore, now: Date = .now) async {
        guard fix.horizontalAccuracy >= 0, now.timeIntervalSince(fix.timestamp) < 30 else { return }
        let here = LatLon(lat: fix.coordinate.latitude, lon: fix.coordinate.longitude)
        var current = trip
        // In the background nothing else refreshes the trip: at most every 2 minutes here.
        // (Reminders, change alerts and the Live Activity follow the new times, see `TripSession.refreshIfDue`.)
        current = await TripSession.refreshIfDue(trip, in: trips, now: now)
        if TripLearning.isEnabled {
            var rec = recorders[trip.id] ?? TripLearning.Recorder()
            let found = rec.observe(here, accuracy: fix.horizontalAccuracy, at: now, itinerary: current.itinerary)
            recorders[trip.id] = rec
            TripLearning.add(found)
        }
        // Change alerts follow the position too (slower or faster than planned), at most twice a minute.
        if lastFollow[trip.id].map({ now.timeIntervalSince($0) > 30 }) ?? true {
            lastFollow[trip.id] = now
            let speed = fix.speed >= 0.3 && fix.speedAccuracy >= 0 && fix.speedAccuracy < 1 ? fix.speed : nil
            await ChangeRiskNotifier.follow(current, here: here, speed: speed, now: now)
        }
    }

    static func forget(_ tripId: String) {
        recorders[tripId] = nil; lastFollow[tripId] = nil; TripSession.forgetRefresh(tripId)
    }
}

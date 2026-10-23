import Foundation

/// A connection the user saved (e.g. "Friday 18:12 to Bari airport"). Stored on the device only.
struct SavedTrip: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var itinerary: Itinerary
    var fromName: String
    var toName: String
    let savedAt: Date
    var refreshedAt: Date?
    /// "Remind me to leave" is on: notification plus Live Activity.
    var followLive: Bool? = nil

    var startTime: Date { itinerary.startTime }
    var endTime: Date { itinerary.endTime }
    var title: String { "\(fromName) → \(toName)" }
    /// This phone only: opens the saved trip (Live Activity, reminders).
    var deepLink: URL { DeepLink.trip(id).url }
    /// The route itself, for other people and other devices.
    var shared: SharedRoute { SharedRoute(itinerary, fromName: fromName, toName: toName) }

    static func == (a: SavedTrip, b: SavedTrip) -> Bool {
        // followLive too: otherwise SwiftUI may skip redrawing a trip whose reminder was switched.
        a.id == b.id && a.itinerary.id == b.itinerary.id && a.refreshedAt == b.refreshedAt && a.followLive == b.followLive
    }
    func hash(into h: inout Hasher) { h.combine(id) }
}

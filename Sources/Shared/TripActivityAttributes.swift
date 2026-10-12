import Foundation
#if canImport(ActivityKit)
import ActivityKit

/// Live Activity for a saved trip: "Leave in 6 min", then the ride, on the lock screen and
/// in the Dynamic Island. Shared by the app (starts/updates it) and the widget extension (draws it).
struct TripActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// TripStatus.Phase raw value.
        var phase: String
        var headline: String
        var detail: String
        /// Countdown target (leave, departure or arrival).
        var nextEvent: Date
        var delayMinutes: Int
        var arrival: Date
        var lineName: String?
        var lineColor: String?
        var lineTextColor: String?
        var updatedAt: Date
    }

    var tripId: String
    var title: String
    var hasTicket: Bool

    var tripURL: URL { URL(string: "publit://trip/\(tripId)")! }
    var ticketsURL: URL { URL(string: "publit://tickets/\(tripId)")! }
}
#endif

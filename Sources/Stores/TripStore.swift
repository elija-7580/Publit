import Foundation
import Observation

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
    var deepLink: URL { DeepLink.trip(id).url }

    static func == (a: SavedTrip, b: SavedTrip) -> Bool {
        a.id == b.id && a.itinerary.id == b.itinerary.id && a.refreshedAt == b.refreshedAt
    }
    func hash(into h: inout Hasher) { h.combine(id) }
}

@MainActor
@Observable
final class TripStore {
    private(set) var trips: [SavedTrip] = []
    @ObservationIgnored private let file: JSONFile<[SavedTrip]>

    init(directory: URL? = nil) {
        file = JSONFile(name: "trips.json", directory: directory)
        trips = file.load() ?? []
    }

    /// Not yet arrived, soonest first.
    func upcoming(now: Date = .now) -> [SavedTrip] {
        trips.filter { $0.endTime >= now }.sorted { $0.startTime < $1.startTime }
    }

    /// Already arrived, most recent first.
    func past(now: Date = .now) -> [SavedTrip] {
        trips.filter { $0.endTime < now }.sorted { $0.startTime > $1.startTime }
    }

    func trip(_ id: String) -> SavedTrip? { trips.first { $0.id == id } }

    /// The saved trip for a route shown in the planner, matched by its vehicles and times.
    func saved(_ itinerary: Itinerary) -> SavedTrip? {
        let key = Self.matchKey(itinerary)
        return trips.first { $0.itinerary.id == itinerary.id || Self.matchKey($0.itinerary) == key }
    }

    @discardableResult
    func save(_ itinerary: Itinerary, from: String, to: String, now: Date = .now) -> SavedTrip {
        if let existing = saved(itinerary) { return existing }
        let t = SavedTrip(id: UUID().uuidString, itinerary: itinerary, fromName: from, toName: to, savedAt: now)
        trips.append(t)
        persist()
        return t
    }

    func wantsLiveActivity(_ id: String) -> Bool { trip(id)?.followLive == true }

    func setFollowLive(_ id: String, _ on: Bool) {
        guard let i = trips.firstIndex(where: { $0.id == id }) else { return }
        trips[i].followLive = on
        persist()
    }

    func remove(_ id: String) {
        trips.removeAll { $0.id == id }
        persist()
    }

    /// Replace the stored route with a fresh real-time version.
    func update(_ id: String, with itinerary: Itinerary, at date: Date = .now) {
        guard let i = trips.firstIndex(where: { $0.id == id }) else { return }
        trips[i].itinerary = itinerary
        trips[i].refreshedAt = date
        persist()
    }

    /// Same vehicles from the same stops on the same scheduled times.
    nonisolated static func matchKey(_ it: Itinerary) -> String {
        let legs = it.transitLegs.map { "\($0.tripId ?? $0.lineName)@\($0.from.name)@\(Int($0.scheduledStartTime.timeIntervalSince1970))" }
        return legs.isEmpty ? "walk@\(Int(it.startTime.timeIntervalSince1970))@\(it.legs.last?.to.name ?? "")" : legs.joined(separator: ">")
    }

    private func persist() { file.save(trips) }
}

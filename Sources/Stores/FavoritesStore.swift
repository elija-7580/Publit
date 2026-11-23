import Foundation
import Observation

/// A saved line at one stop, e.g. "U6 at Marienplatz". Shows that line's next departures there.
struct SavedLine: Codable, Hashable, Identifiable, RouteStyled {
    var id: String { "\(routeKey)@\(stopId)" }
    var routeKey: String
    var mode: String
    var routeShortName: String?
    var displayName: String?
    var routeColor: String?
    var routeTextColor: String?
    var stopId: String
    var stopName: String
    var lat: Double
    var lon: Double

    var coordinate: LatLon { LatLon(lat: lat, lon: lon) }
    /// The key is the route ID when the feed has one.
    var routeId: String? { routeKey }

    init(stopTime st: StopTime, stopId: String, stopName: String, at coordinate: LatLon) {
        routeKey = SavedLine.key(st)
        mode = st.mode
        routeShortName = st.routeShortName
        displayName = st.displayName
        routeColor = st.routeColor
        routeTextColor = st.routeTextColor
        self.stopId = stopId
        self.stopName = stopName
        lat = coordinate.lat
        lon = coordinate.lon
    }

    init(line: LineRef) {
        routeKey = line.key
        mode = line.mode
        routeShortName = line.routeShortName
        displayName = line.displayName
        routeColor = line.routeColor
        routeTextColor = line.routeTextColor
        stopId = line.stopId
        stopName = line.stopName
        lat = line.lat
        lon = line.lon
    }

    /// Route identity: the feed's route ID when present, else agency and line name.
    static func key(_ st: StopTime) -> String {
        st.routeId ?? "\(st.agencyName ?? "")|\(st.lineName)"
    }

    func matches(_ st: StopTime) -> Bool { SavedLine.key(st) == routeKey }
}

@MainActor
@Observable
final class FavoritesStore {
    private(set) var items: [SavedPlace] = []
    private(set) var lines: [SavedLine] = []
    private let key = "publit.favorites.v1"
    private let linesKey = "publit.lines.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode([SavedPlace].self, from: data) {
            items = decoded
        }
        if let data = defaults.data(forKey: linesKey),
           let decoded = try? JSONDecoder().decode([SavedLine].self, from: data) {
            lines = decoded
        }
    }

    func containsLine(_ id: String) -> Bool { lines.contains { $0.id == id } }

    func toggle(_ line: SavedLine) {
        if containsLine(line.id) { lines.removeAll { $0.id == line.id } } else { lines.append(line) }
        if let data = try? JSONEncoder().encode(lines) { defaults.set(data, forKey: linesKey) }
    }

    func removeLines(_ ids: [String]) {
        lines.removeAll { ids.contains($0.id) }
        if let data = try? JSONEncoder().encode(lines) { defaults.set(data, forKey: linesKey) }
    }

    var stops: [SavedPlace] { items.filter { $0.isStop && $0.role == nil } }
    var places: [SavedPlace] { items.filter { !$0.isStop && $0.role == nil } }
    var pinned: [SavedPlace] { PlaceRole.allCases.compactMap(place(for:)) }

    func place(for role: PlaceRole) -> SavedPlace? { items.first { $0.role == role } }

    /// Sets `place` as Home or Work, replacing any earlier one for that role.
    func set(_ place: SavedPlace, as role: PlaceRole) {
        for i in items.indices where items[i].role == role { items[i].role = nil }
        var p = place
        p.role = role
        if let i = items.firstIndex(where: { $0.id == place.id && $0.isSame(as: place) }), items[i].role == nil {
            // The same saved place becomes Home or Work.
            items[i] = p
        } else if items.contains(where: { $0.id == place.id }) {
            // The ID is taken: by the other role (same place, or an address ID the geocoder reuses
            // in another country) or by another saved address. Keep that entry and store this role
            // separately, so setting Work never removes Home or a saved place.
            p.id = Self.slotID(role, for: place)
            items.removeAll { $0.id == p.id }
            items.append(p)
        } else {
            items.append(p)
        }
        persist()
    }

    /// A stable ID of its own for a place whose ID already holds the other role.
    static func slotID(_ role: PlaceRole, for place: SavedPlace) -> String {
        "\(role.rawValue)|\(place.id)|\(String(format: "%.5f,%.5f", place.lat, place.lon))"
    }

    func clear(_ role: PlaceRole) {
        items.removeAll { $0.role == role }
        persist()
    }

    func contains(_ id: String) -> Bool { items.contains { $0.id == id } }
    func contains(_ place: SavedPlace) -> Bool { items.contains { place.isSaved(as: $0) } }

    func toggle(_ place: SavedPlace) {
        if contains(place) {
            items.removeAll { place.isSaved(as: $0) }
        } else {
            var p = place
            // Another address with this ID is saved already: both stay, each under its own ID.
            if items.contains(where: { $0.id == p.id }) { p.id = place.ownID }
            items.append(p)
        }
        persist()
    }

    func remove(_ ids: [String]) {
        items.removeAll { ids.contains($0.id) }
        persist()
    }

    // MARK: Own order (#124)

    /// Moves saved stops as a list's drag does (`offsets` and `destination` count within `stops`).
    func moveStops(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        items = Self.moved(items, fromOffsets: offsets, toOffset: destination) { $0.isStop && $0.role == nil }
        persist()
    }

    /// Moves saved places as a list's drag does (`offsets` and `destination` count within `places`).
    func movePlaces(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        items = Self.moved(items, fromOffsets: offsets, toOffset: destination) { !$0.isStop && $0.role == nil }
        persist()
    }

    /// Moves saved lines as a list's drag does.
    func moveLines(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        lines = Self.moved(lines, fromOffsets: offsets, toOffset: destination) { _ in true }
        if let data = try? JSONEncoder().encode(lines) { defaults.set(data, forKey: linesKey) }
    }

    /// `all` with the entries of one kind (`isKind`) put in a new order among themselves: those at
    /// `offsets` (counted within the kind) go before the entry at `destination`, like SwiftUI's
    /// `move(fromOffsets:toOffset:)`. Entries of other kinds keep their places, so stops, places,
    /// Home and Work stay one stored list.
    static func moved<T>(_ all: [T], fromOffsets offsets: IndexSet, toOffset destination: Int, where isKind: (T) -> Bool) -> [T] {
        let slots = all.indices.filter { isKind(all[$0]) }
        let valid = offsets.filter { $0 >= 0 && $0 < slots.count }
        guard !valid.isEmpty, destination >= 0, destination <= slots.count else { return all }
        var order = slots.indices.filter { !valid.contains($0) }
        order.insert(contentsOf: valid, at: destination - valid.filter { $0 < destination }.count)
        var result = all
        for (slot, source) in zip(slots, order) { result[slot] = all[slots[source]] }
        return result
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) { defaults.set(data, forKey: key) }
    }
}

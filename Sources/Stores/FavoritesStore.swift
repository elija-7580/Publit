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
        if let i = items.firstIndex(where: { $0.id == place.id }) { items[i] = p } else { items.append(p) }
        persist()
    }

    func clear(_ role: PlaceRole) {
        items.removeAll { $0.role == role }
        persist()
    }

    func contains(_ id: String) -> Bool { items.contains { $0.id == id } }
    func contains(_ place: SavedPlace) -> Bool { items.contains { $0.isSame(as: place) } }

    func toggle(_ place: SavedPlace) {
        if contains(place) { items.removeAll { $0.isSame(as: place) } } else { items.append(place) }
        persist()
    }

    func remove(_ ids: [String]) {
        items.removeAll { ids.contains($0.id) }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(items) { defaults.set(data, forKey: key) }
    }
}

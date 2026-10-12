import Foundation

/// Platforms with the same name close together shown as one station.
struct MapStation: Identifiable, Hashable {
    let id: String
    let name: String
    let coordinate: LatLon
    let modes: [String]
    let importance: Double

    var mainMode: String {
        let order = ["HIGHSPEED_RAIL", "LONG_DISTANCE", "NIGHT_RAIL", "REGIONAL_FAST_RAIL", "REGIONAL_RAIL", "RAIL", "SUBURBAN",
                     "SUBWAY", "METRO", "TRAM", "FERRY", "AIRPLANE", "FUNICULAR", "AERIAL_LIFT", "COACH", "BUS"]
        return order.first(where: modes.contains) ?? modes.first ?? "BUS"
    }
    var isMajor: Bool { modes.contains { $0 != "BUS" && $0 != "COACH" } }

    static func group(_ stops: [MapStop]) -> [MapStation] {
        var out: [MapStation] = []
        var buckets: [String: [MapStop]] = [:]
        for s in stops { buckets[s.stationId, default: []].append(s) }
        for (_, group) in buckets {
            // Within one parent station, or same name within 300 m.
            var remaining = group
            while let first = remaining.first {
                let key = StopGrouping.normalizedName(first.name)
                let same = remaining.filter {
                    StopGrouping.normalizedName($0.name) == key && $0.coordinate.distance(to: first.coordinate) < StopGrouping.mergeRadius
                }
                remaining.removeAll { s in same.contains(s) }
                let lat = same.map(\.lat).reduce(0, +) / Double(same.count)
                let lon = same.map(\.lon).reduce(0, +) / Double(same.count)
                out.append(MapStation(id: first.stationId, name: first.name, coordinate: LatLon(lat: lat, lon: lon),
                                      modes: Array(Set(same.flatMap { $0.modes ?? [] })).sorted(),
                                      importance: same.compactMap(\.importance).max() ?? 0))
            }
        }
        // Merge same-name stations from different parents that sit together (e.g. bus + rail feed).
        var merged: [MapStation] = []
        for s in out.sorted(by: { $0.importance > $1.importance }) {
            if let i = merged.firstIndex(where: {
                StopGrouping.normalizedName($0.name) == StopGrouping.normalizedName(s.name)
                    && $0.coordinate.distance(to: s.coordinate) < StopGrouping.mergeRadius
            }) {
                let m = merged[i]
                merged[i] = MapStation(id: m.id, name: m.name, coordinate: m.coordinate,
                                       modes: Array(Set(m.modes + s.modes)).sorted(), importance: m.importance)
            } else {
                merged.append(s)
            }
        }
        return Array(merged.prefix(300))
    }
}

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

    /// At most this many pins; MapKit annotations get slow beyond a few hundred.
    static let maxStations = 250

    static func group(_ stops: [MapStop]) -> [MapStation] {
        // Name folding is the expensive part: do it once per distinct name.
        var keys: [String: String] = [:]
        for s in stops where keys[s.name] == nil { keys[s.name] = StopGrouping.normalizedName(s.name) }
        func key(_ name: String) -> String { keys[name] ?? StopGrouping.normalizedName(name) }

        var out: [MapStation] = []
        var buckets: [String: [MapStop]] = [:]
        for s in stops { buckets[s.stationId, default: []].append(s) }
        for (_, group) in buckets {
            // Within one parent station, or same name within 300 m.
            var remaining = group
            var firstInStation = true
            while let first = remaining.first {
                let k = key(first.name)
                var same: [MapStop] = [], rest: [MapStop] = []
                for s in remaining {
                    if key(s.name) == k && s.coordinate.distance(to: first.coordinate) < StopGrouping.mergeRadius {
                        same.append(s)
                    } else {
                        rest.append(s)
                    }
                }
                remaining = rest
                let lat = same.map(\.lat).reduce(0, +) / Double(same.count)
                let lon = same.map(\.lon).reduce(0, +) / Double(same.count)
                // A parent station split by name gives several pins; each needs its own ID
                // (duplicate IDs confuse the map selection and SwiftUI's diffing).
                let id = firstInStation ? first.stationId : first.stopId
                firstInStation = false
                out.append(MapStation(id: id, name: first.name, coordinate: LatLon(lat: lat, lon: lon),
                                      modes: Array(Set(same.flatMap { $0.modes ?? [] })).sorted(),
                                      importance: same.compactMap(\.importance).max() ?? 0))
            }
        }
        // Merge same-name stations from different parents that sit together (e.g. bus + rail feed).
        var merged: [MapStation] = []
        var byName: [String: [Int]] = [:]
        for s in out.sorted(by: { $0.importance > $1.importance }) {
            let k = key(s.name)
            if let i = byName[k]?.first(where: { merged[$0].coordinate.distance(to: s.coordinate) < StopGrouping.mergeRadius }) {
                let m = merged[i]
                merged[i] = MapStation(id: m.id, name: m.name, coordinate: m.coordinate,
                                       modes: Array(Set(m.modes + s.modes)).sorted(), importance: m.importance)
            } else {
                byName[k, default: []].append(merged.count)
                merged.append(s)
            }
        }
        return Array(merged.prefix(maxStations))
    }
}

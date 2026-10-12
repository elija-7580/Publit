import Foundation

/// Departures of one station. Platforms of the same station often come with different
/// parent IDs (or none) in the feeds, so grouping is by name and distance, not by ID alone.
struct StopGroup: Identifiable, Sendable {
    let id: String
    let name: String
    let coordinate: LatLon
    var stopIds: [String]
    var departures: [StopTime]
    var distance: Double?
}

enum StopGrouping {
    /// Two stops with the same name closer than this are treated as one station.
    static let mergeRadius = 300.0

    static func normalizedName(_ name: String) -> String {
        // Turkish dotless/dotted i do not fold to "i" on their own.
        name.replacingOccurrences(of: "ı", with: "i").replacingOccurrences(of: "İ", with: "I")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func group(_ stopTimes: [StopTime], around here: LatLon?) -> [StopGroup] {
        var groups: [StopGroup] = []
        var candidates: [String: [Int]] = [:]
        var names: [String: String] = [:]
        for st in stopTimes.sorted(by: { $0.departureTime < $1.departureTime }) {
            let name = names[st.place.name] ?? normalizedName(st.place.name)
            names[st.place.name] = name
            let c = st.place.coordinate
            if let i = candidates[name]?.first(where: { groups[$0].coordinate.distance(to: c) <= mergeRadius }) {
                groups[i].departures.append(st)
                if let sid = st.place.stopId, !groups[i].stopIds.contains(sid) { groups[i].stopIds.append(sid) }
            } else {
                candidates[name, default: []].append(groups.count)
                groups.append(StopGroup(id: st.place.stationId, name: st.place.name, coordinate: c,
                                        stopIds: st.place.stopId.map { [$0] } ?? [],
                                        departures: [st], distance: here?.distance(to: c)))
            }
        }
        return groups.sorted { ($0.distance ?? .infinity) < ($1.distance ?? .infinity) }
    }
}

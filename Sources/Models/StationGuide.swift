import Foundation

/// The three station views, each switched in Settings → Stations:
/// a map of the station's platforms, the departures grouped by platform ("Which side?"),
/// and a guide from platform to platform when changing during a live trip.
enum StationViews {
    static let platformMapKey = "stationPlatformMap"
    static let byPlatformKey = "stationBoardByPlatform"
    static let changeGuideKey = "stationChangeGuide"

    /// On by default: they only add to what is there.
    static var platformMap: Bool { flag(platformMapKey, default: true) }
    static var changeGuide: Bool { flag(changeGuideKey, default: true) }
    /// Off by default: it changes how the board is ordered.
    static var byPlatform: Bool { flag(byPlatformKey, default: false) }

    static func flag(_ key: String, default value: Bool, _ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: key) as? Bool ?? value
    }
}

/// One platform (or street stop) of a station and what leaves from it.
struct PlatformGroup: Identifiable, Sendable {
    let id: String
    /// "A", "3", "3a"; nil where the feed has no platform names.
    let label: String?
    let name: String
    let coordinate: LatLon
    /// Soonest first.
    let departures: [StopTime]
    /// One departure per line, in line order (train first, "2" before "10").
    let lines: [StopTime]
    /// Where vehicles from here go next, busiest way first, at most two: ["Karlovy lázně", "Národní divadlo", …].
    let ways: [[String]]

    var title: String { label.map { L10n.f("Platform %@", $0) } ?? name }
}

enum PlatformGrouping {
    static let maxWays = 2

    /// The departures of a station by platform. Platforms with the same name but different stop IDs
    /// (one per track side) are one platform; stops without a platform name are one per stop.
    static func groups(_ stopTimes: [StopTime]) -> [PlatformGroup] {
        var order: [String] = []
        var buckets: [String: [StopTime]] = [:]
        for st in stopTimes {
            let k = key(st)
            if buckets[k] == nil { order.append(k) }
            buckets[k, default: []].append(st)
        }
        let groups = order.compactMap { k -> PlatformGroup? in
            guard let list = buckets[k]?.sorted(by: { $0.departureTime < $1.departureTime }), let first = list.first else { return nil }
            let coords = list.map(\.place.coordinate)
            let center = LatLon(lat: coords.map(\.lat).reduce(0, +) / Double(coords.count),
                                lon: coords.map(\.lon).reduce(0, +) / Double(coords.count))
            return PlatformGroup(id: k, label: TransitLabels.clean(first.place.track), name: first.place.name,
                                 coordinate: center, departures: list, lines: lines(list), ways: ways(list))
        }
        return groups.sorted { a, b in
            switch (a.label, b.label) {
            case let (x?, y?):
                let c = x.compare(y, options: [.numeric, .caseInsensitive])
                if c != .orderedSame { return c == .orderedAscending }
            case (_?, nil): return true
            case (nil, _?): return false
            default: break
            }
            let c = a.name.compare(b.name, options: [.numeric, .caseInsensitive])
            return c != .orderedSame ? c == .orderedAscending : a.id < b.id
        }
    }

    static func key(_ st: StopTime) -> String {
        if let track = TransitLabels.clean(st.place.track) {
            return "\(StopGrouping.normalizedName(st.place.name))|track|\(track)"
        }
        return st.place.stopId ?? "\(st.place.name)@\(LatLon.format(st.place.lat, 5)),\(LatLon.format(st.place.lon, 5))"
    }

    static func lines(_ list: [StopTime]) -> [StopTime] {
        var seen = Set<String>()
        let unique = list.filter { seen.insert(SavedLine.key($0)).inserted }
        let groups = ModeGroup.allCases
        return unique.sorted { a, b in
            let ga = groups.firstIndex(of: ModeGroup.of(a.mode)) ?? 0, gb = groups.firstIndex(of: ModeGroup.of(b.mode)) ?? 0
            if ga != gb { return ga < gb }
            return a.lineName.compare(b.lineName, options: [.numeric, .caseInsensitive]) == .orderedAscending
        }
    }

    /// The next stops of the busiest ways out of this platform, without the platform's own name.
    static func ways(_ list: [StopTime]) -> [[String]] {
        var counts: [String: Int] = [:]
        var chains: [String: [String]] = [:]
        var order: [String] = []
        for st in list {
            let own = TransitLabels.identity(st.place.name)
            let chain = (st.nextStops?.names ?? []).filter { TransitLabels.identity($0) != own }
            guard let first = chain.first else { continue }
            let k = TransitLabels.identity(first)
            if counts[k] == nil { order.append(k); chains[k] = chain }
            counts[k, default: 0] += 1
        }
        return order.enumerated()
            .sorted { a, b in counts[a.element]! != counts[b.element]! ? counts[a.element]! > counts[b.element]! : a.offset < b.offset }
            .prefix(maxWays).compactMap { chains[$0.element] }
    }
}

/// The change between two vehicles, for the live trip: where you get off, the way through the
/// station, where you get on, and what is on the way (stairs, lifts, levels, exits).
struct ChangeGuide: Sendable {
    let arriving: Leg
    let departing: Leg
    /// The walk from platform to platform; a straight line when the router has none.
    let path: [LatLon]
    let walkSeconds: Int
    /// Only what matters inside a station: stairs, lifts, level changes and exits, in walking order.
    let steps: [WalkManeuver]

    var stairs: Int { steps.filter { [.stairs, .stairsUp, .stairsDown].contains($0.kind) }.count }
    var elevators: Int { steps.filter { $0.kind == .elevator }.count }
    var isStepFree: Bool { stairs == 0 }
    /// The two vehicles stop at the same place: nothing to walk.
    var isSamePlatform: Bool {
        walkSeconds < 30 && arriving.to.coordinate.distance(to: departing.from.coordinate) < 25
    }

    /// The change before the ride at `legIndex`; nil without a ride before it.
    init?(before legIndex: Int, in it: Itinerary) {
        guard it.legs.indices.contains(legIndex), it.legs[legIndex].isTransit,
              let p = it.legs[..<legIndex].lastIndex(where: \.isTransit) else { return nil }
        arriving = it.legs[p]
        departing = it.legs[legIndex]
        let walks = it.legs[(p + 1)..<legIndex].filter { !$0.isTransit }
        walkSeconds = walks.reduce(0) { $0 + $1.duration }
        var path: [LatLon] = []
        var steps: [WalkManeuver] = []
        for walk in walks {
            let route = WalkRoute(leg: walk)
            path += route.path
            steps += route.maneuvers.filter { m in
                [.stairs, .stairsUp, .stairsDown, .elevator, .levelUp, .levelDown].contains(m.kind) || m.exitNote != nil
            }
        }
        if path.count < 2 { path = [arriving.to.coordinate, departing.from.coordinate] }
        self.path = path
        self.steps = steps
    }

    /// "Platform 3 → Platform 7" (or the stop names where there are no platforms).
    var headline: String {
        let from = TransitLabels.clean(arriving.to.track).map { L10n.f("Platform %@", $0) } ?? arriving.to.name
        let to = TransitLabels.clean(departing.from.track).map { L10n.f("Platform %@", $0) } ?? departing.from.name
        return "\(from) → \(to)"
    }
}

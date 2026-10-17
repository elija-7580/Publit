import Foundation

/// How far Publit looks for stops and how far it lets people walk to them, and what it says when
/// the nearest service is far away. Nothing is dropped silently: a far stop is shown with its
/// distance and walking time instead of an empty board or "no connections".
enum Reach {
    /// Radii (metres) for the Nearby board, tried in order until one has departures.
    /// 5 km covers campsites, beaches and villages at the edge of a network (Punta Sabbioni, Cavallino).
    static let nearbyRadii = [500, 1500, 5000]
    /// From this distance on, the board says that the nearest departures are far.
    static let farDistance = 1500.0
    /// Below this the header shows only the distance; above it also the walking time.
    static let walkHintDistance = 400.0

    /// Walking limits (seconds) to the first and from the last stop for route search, tried in order
    /// while nothing is found. The last step is "show it anyway": routes behind a long walk, marked as such.
    /// The server accepts up to two hours (checked 2026-10-17 against api.transitous.org).
    static let walkSteps = [1800, 2700, 7200]
    /// Walks to or from a stop longer than this are pointed out above the routes.
    static let longWalkSeconds = 1800

    /// Rough walking time from a straight-line distance: streets add about 30 %, people walk about 80 m a minute.
    static func walkMinutes(meters: Double) -> Int {
        guard meters.isFinite, meters > 0 else { return 1 }
        return max(1, Int((meters * 1.3 / 80).rounded(.up)))
    }

    /// The next walk limit after `current`, or nil when the longest one was tried.
    static func nextWalkStep(after current: Int) -> Int? {
        walkSteps.first { $0 > current }
    }

    /// Longest walk to the first or from the last stop over all routes with transit (seconds).
    static func longestAccessWalk(_ itineraries: [Itinerary]) -> Int {
        itineraries.filter { !$0.isDirect }.map { it -> Int in
            // Bike, scooter or car to the stop is not walking.
            let first = it.legs.prefix { !$0.isTransit }.filter { $0.mode == "WALK" }.reduce(0) { $0 + $1.duration }
            let last = it.legs.reversed().prefix { !$0.isTransit }.filter { $0.mode == "WALK" }.reduce(0) { $0 + $1.duration }
            return max(first, last)
        }.max() ?? 0
    }

    /// "The nearest departures are 2.9 km away, about 48 min on foot."
    static func farNote(meters: Double) -> String {
        L10n.f("The nearest departures are %@ away, about %lld min on foot.", Fmt.distance(meters: meters), walkMinutes(meters: meters))
    }

    /// Above routes that were only found with a longer walk than usual; nil when no walk is long.
    static func longWalkNote(_ itineraries: [Itinerary]) -> String? {
        let longest = longestAccessWalk(itineraries)
        guard longest > longWalkSeconds else { return nil }
        return L10n.f("These routes include a long walk: up to %lld min to or from the stop.", Int((Double(longest) / 60).rounded()))
    }

    /// No route because the user's own walking limit is short: say so instead of a plain "none".
    static func ownLimitNote(minutes: Int) -> String {
        L10n.f("No connections within your walking limit of %lld min. A longer walk in Route options may find more.", minutes)
    }
}

extension GeocodeMatch {
    /// Type of a place picked on the map (an Apple Maps point of interest or a dropped pin).
    static let pickedType = "PLACE"

    /// A place picked on the map, in the same shape as a search hit, so it opens the same sheet and routes the same way.
    /// The ID depends only on the position: naming it later (reverse geocoding) keeps the open sheet.
    static func picked(name: String, at point: LatLon, street: String? = nil, houseNumber: String? = nil,
                       locality: String? = nil, country: String? = nil, category: String? = nil) -> GeocodeMatch {
        GeocodeMatch(type: pickedType, name: name, id: pickedId(point), lat: point.lat, lon: point.lon,
                     street: street, houseNumber: houseNumber, country: country,
                     areas: locality.map { [GeocodeArea(name: $0, adminLevel: 8, default: true)] } ?? [],
                     category: category)
    }

    static func pickedId(_ point: LatLon) -> String {
        "pick|" + String(format: "%.5f,%.5f", point.lat, point.lon)
    }

    /// Search hits from two sources in one list: the transit geocoder first (it knows the stops),
    /// then other places that are not the same place under the same name (within 150 m).
    static func merged(_ primary: [GeocodeMatch], _ extra: [GeocodeMatch], limit: Int = 15) -> [GeocodeMatch] {
        var out = primary
        for m in extra {
            let name = StopGrouping.normalizedName(m.name)
            let here = LatLon(lat: m.lat, lon: m.lon)
            let duplicate = out.contains {
                StopGrouping.normalizedName($0.name) == name && LatLon(lat: $0.lat, lon: $0.lon).distance(to: here) < 150
            }
            if !duplicate { out.append(m) }
        }
        return Array(out.prefix(limit))
    }
}

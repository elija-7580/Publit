import Foundation

// What the Apple Watch needs of a trip, and how a trip is split into screens.
// Pure logic, so it is tested with the rest of the core (Tests/WatchSyncTests.swift).

extension Place {
    /// Without notices: a leg keeps its own, the places along it only add size.
    func forWatch() -> Place {
        var p = self
        p.alerts = nil
        return p
    }
}

extension Leg {
    /// The leg as the watch needs it: line, times, stops and the shape for the map. No walking
    /// directions, no alternatives, notices cut to two headlines.
    func forWatch() -> Leg {
        var l = self
        l.from = from.forWatch()
        l.to = to.forWatch()
        l.intermediateStops = intermediateStops?.map { $0.forWatch() }
        l.steps = nil
        l.alternatives = nil
        l.alerts = alerts.flatMap { list -> [Alert]? in
            let short = list.prefix(2).map {
                Alert(headerText: $0.headerText, descriptionText: "", url: nil, effect: $0.effect, severityLevel: $0.severityLevel)
            }
            return short.isEmpty ? nil : short
        }
        return l
    }
}

extension Itinerary {
    func forWatch() -> Itinerary {
        var it = self
        it.legs = legs.map { $0.forWatch() }
        it.fareTransfers = nil
        return it
    }
}

extension SavedTrip {
    func forWatch() -> SavedTrip {
        var t = self
        t.itinerary = itinerary.forWatch()
        return t
    }
}

extension TicketPass {
    /// The pass as the watch shows it. The original document, notes, logo and the content of the code stay
    /// on the iPhone: the watch gets a picture of the code instead (drawn there).
    func forWatch() -> TicketPass {
        var p = self
        p.document = nil
        p.notes = nil
        p.logo = nil
        p.legacyId = nil
        if let b = barcode {
            p.barcode = TicketPass.Barcode(format: b.format, altText: b.altText)
        }
        return p
    }
}

/// One screen of a trip on the watch.
enum WatchTripPage: Hashable, Sendable {
    /// Times, duration, changes, the lines as badges, the status and the buttons.
    case overview
    /// One leg: a ride or a longer walk, with its own map.
    case leg(Int)

    var id: String {
        switch self {
        case .overview: return "overview"
        case .leg(let i): return "leg-\(i)"
        }
    }
}

enum WatchTripPages {
    /// The overview, then every leg that deserves its own screen: all rides, and walks of two minutes or
    /// 150 m and more. Shorter walks (a change inside a station) stay in the overview.
    static func pages(for it: Itinerary) -> [WatchTripPage] {
        var out: [WatchTripPage] = [.overview]
        for (i, leg) in it.legs.enumerated() where worthAPage(leg) { out.append(.leg(i)) }
        return out
    }

    static func worthAPage(_ leg: Leg) -> Bool {
        leg.isTransit || leg.duration >= 120 || (leg.distance ?? 0) >= 150
    }

    /// The screen to open first: the overview before the trip and after it, else the leg under way (or the next one).
    static func current(in it: Itinerary, now: Date) -> WatchTripPage {
        guard now >= it.startTime, now < it.endTime else { return .overview }
        let pages = pages(for: it)
        for page in pages {
            if case .leg(let i) = page, it.legs[i].endTime > now { return page }
        }
        return .overview
    }

    /// The leg a page shows.
    static func leg(_ page: WatchTripPage, in it: Itinerary) -> Leg? {
        if case .leg(let i) = page, it.legs.indices.contains(i) { return it.legs[i] }
        return nil
    }
}

/// The part of the map a leg shows: its line and its end points, in a box of at least 400 m.
enum WatchMapFit {
    struct Box: Equatable, Sendable {
        let center: LatLon
        let latitudeDelta: Double
        let longitudeDelta: Double
    }

    static let metersPerDegree = 111_320.0

    /// A box around `points` with a margin, as wide as it is high in meters (the watch screen is nearly square).
    static func box(_ points: [LatLon], padding: Double = 0.2, minimumMeters: Double = 400) -> Box? {
        let valid = points.filter(\.isValidCoordinate)
        guard let first = valid.first else { return nil }
        var minLat = first.lat, maxLat = first.lat, minLon = first.lon, maxLon = first.lon
        for p in valid {
            minLat = min(minLat, p.lat); maxLat = max(maxLat, p.lat)
            minLon = min(minLon, p.lon); maxLon = max(maxLon, p.lon)
        }
        let center = LatLon(lat: (minLat + maxLat) / 2, lon: (minLon + maxLon) / 2)
        let cosLat = max(0.01, cos(center.lat * .pi / 180))
        let heightMeters = (maxLat - minLat) * metersPerDegree
        let widthMeters = (maxLon - minLon) * metersPerDegree * cosLat
        let side = max(max(heightMeters, widthMeters) * (1 + 2 * padding), minimumMeters)
        return Box(center: center, latitudeDelta: min(side / metersPerDegree, 170),
                   longitudeDelta: min(side / (metersPerDegree * cosLat), 350))
    }

    /// The points that decide what the map of a leg shows.
    static func points(of leg: Leg) -> [LatLon] {
        let path = leg.mapPath
        return path.isEmpty ? [leg.from.coordinate, leg.to.coordinate] : path
    }

    /// The map of a whole trip: every leg.
    static func points(of it: Itinerary) -> [LatLon] {
        it.legs.flatMap { points(of: $0) }
    }
}

/// The routes the watch lists after a search: walking joins the list when it is a real choice
/// (the same rule as the planner on the iPhone), without cycling and driving.
enum WatchRoutes {
    static func merge(transit: [Itinerary], direct: [Itinerary]) -> [Itinerary] {
        let walking = direct.filter { let m = StreetComparison.streetMode($0); return m != "BIKE" && m != "CAR" }
        guard let walk = walking.min(by: { $0.duration < $1.duration }) else { return transit }
        guard let best = transit.map(\.duration).min() else { return [walk] }
        let worthIt = Double(walk.duration) <= Double(best) * 1.25 || walk.duration <= 10 * 60
        return worthIt ? [walk] + transit : transit
    }

    /// Up to `limit` routes for a small screen: no detours, one row per route, walking first when it is a choice.
    static func list(transit: [Itinerary], direct: [Itinerary], limit: Int = 8) -> [Itinerary] {
        Array(merge(transit: transit.withoutDetours.uniqueRoutes, direct: direct).prefix(limit))
    }
}

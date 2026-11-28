import Foundation

/// Plain coordinate type, independent of CoreLocation so the model layer stays portable and testable.
struct LatLon: Hashable, Codable, Sendable {
    let lat: Double
    let lon: Double

    var isValidCoordinate: Bool { lat.isFinite && lon.isFinite && abs(lat) <= 90 && abs(lon) <= 180 }

    /// `lat,lon` as expected by the MOTIS API, to about 1 m. Full GPS precision only makes
    /// every request URL unique (no cache hits) and says more about where someone is than needed.
    var apiValue: String { Self.format(lat, 5) + "," + Self.format(lon, 5) }

    /// The same point to about 1 km, for search bias: nearby results stay first and repeated
    /// searches from around the same place reuse the cached answer.
    var coarseAPIValue: String { Self.format(lat, 2) + "," + Self.format(lon, 2) }

    /// Locale-independent fixed decimals without trailing zeros ("48.13715", "11.5").
    static func format(_ value: Double, _ decimals: Int) -> String {
        var s = String(format: "%.\(decimals)f", value)
        if s.contains(".") {
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
        }
        return s == "-0" ? "0" : s
    }

    init(lat: Double, lon: Double) { self.lat = lat; self.lon = lon }

    init?(apiValue: String) {
        let parts = apiValue.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 2 else { return nil }
        let point = LatLon(lat: parts[0], lon: parts[1])
        guard point.isValidCoordinate else { return nil }
        self = point
    }
}

/// Google-encoded polyline as returned by MOTIS (`precision` 6 for /v2+).
struct EncodedPolyline: Codable, Sendable {
    let points: String
    let precision: Int
    let length: Int
    let coordinates: [LatLon]
    /// Simplified copy for maps, computed once while decoding (off the main thread).
    let mapPoints: [LatLon]

    private enum CodingKeys: String, CodingKey { case points, precision, length }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        points = try c.decode(String.self, forKey: .points)
        precision = try c.decode(Int.self, forKey: .precision)
        length = try c.decodeIfPresent(Int.self, forKey: .length) ?? 0
        coordinates = Polyline.decode(points, precision: precision)
        mapPoints = Polyline.simplify(coordinates)
    }

    /// A shape worked out on the phone, e.g. part of a vehicle's ride (`OnBoardPlan`).
    init(coordinates: [LatLon], precision: Int = 6) {
        self.precision = precision
        self.coordinates = coordinates
        points = Polyline.encode(coordinates, precision: precision)
        length = coordinates.count
        mapPoints = Polyline.simplify(coordinates)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(points, forKey: .points)
        try c.encode(precision, forKey: .precision)
        try c.encode(length, forKey: .length)
    }
}

/// Booking links per platform, when the feed provides them.
struct TicketUrls: Codable, Hashable, Sendable {
    let web: String?
    let ios: String?
    let android: String?
}

struct Place: Codable, Hashable, Sendable {
    let name: String
    let stopId: String?
    let parentId: String?
    let lat: Double
    let lon: Double
    let tz: String?
    var arrival: Date?
    var departure: Date?
    let scheduledArrival: Date?
    let scheduledDeparture: Date?
    var track: String?
    let scheduledTrack: String?
    var cancelled: Bool?
    var alerts: [Alert]?
    /// MOTIS event-level time source. Optional for older feeds and saved trips.
    var arrivalTimestampReason: String? = nil
    var departureTimestampReason: String? = nil

    var coordinate: LatLon { LatLon(lat: lat, lon: lon) }
    var alertsList: [Alert] { alerts ?? [] }
    /// Stop identifier to group platforms of one station.
    var stationId: String { parentId ?? stopId ?? "\(name)@\(lat),\(lon)" }
}

struct Alert: Codable, Hashable, Sendable {
    let headerText: String
    let descriptionText: String
    let url: String?
    var effect: String? = nil
    var severityLevel: String? = nil
    var communicationPeriod: [AlertPeriod]? = nil
    var impactPeriod: [AlertPeriod]? = nil
}

struct Leg: Codable, Sendable, RouteStyled {
    let mode: String
    var from: Place
    var to: Place
    var duration: Int
    var startTime: Date
    var endTime: Date
    var scheduledStartTime: Date
    var scheduledEndTime: Date
    var realTime: Bool
    var distance: Double?
    let headsign: String?
    let routeColor: String?
    let routeTextColor: String?
    let routeShortName: String?
    let displayName: String?
    let agencyName: String?
    let agencyUrl: String?
    let agencyFareUrl: String?
    let routeUrl: String?
    let ticketUrls: TicketUrls?
    let routeId: String?
    let tripId: String?
    var cancelled: Bool?
    var intermediateStops: [Place]?
    var alerts: [Alert]?
    var legGeometry: EncodedPolyline
    /// Bike or scooter sharing for `RENTAL` legs.
    var rental: LegRental? = nil
    var fareTransferIndex: Int? = nil
    var effectiveFareLegIndex: Int? = nil
    /// Walking (and cycling) directions: streets, stairs and levels, each with its piece of the path.
    var steps: [StepInstruction]? = nil
    /// The planner says the vehicle continues from the previous leg (stay seated).
    var interlineWithPreviousLeg: Bool? = nil
    /// Other vehicles that can replace this ride and still keep the trip (smart routing asks for
    /// them with `numLegAlternatives`); each is walk, ride, walk.
    var alternatives: [[Leg]]? = nil
    /// Extra real-time source that corrected this ride ("ÖBB"), see `LiveOverlay`.
    var liveSource: String? = nil
    /// Train number with its category ("RJX 161", "REX 9563") where the feed has one.
    var tripShortName: String? = nil
    var routeLongName: String? = nil
    /// Whether the vehicle itself takes a wheelchair (GTFS `wheelchair_accessible`):
    /// "ACCESSIBLE", "NOT_ACCESSIBLE" or "UNKNOWN".
    var wheelchairAccessible: String? = nil
    /// Last stop of the vehicle's trip.
    var tripTo: SegmentStop? = nil
    /// First stop of the vehicle's trip.
    var tripFrom: SegmentStop? = nil
    /// Where to ride and which way out, worked out on the iPhone for the watch (nil elsewhere).
    var exitAdvice: ExitAdvice? = nil

    var directionName: String? { TransitLabels.direction(headsign: headsign, tripEnd: tripTo?.name) }
    var isTransit: Bool { ModeStyle.isTransit(mode) }
    var delayMinutes: Int { Int((startTime.timeIntervalSince(scheduledStartTime) / 60).rounded()) }
    /// Boarding stop, every stop in between, and the alighting stop.
    var allStops: [Place] { [from] + (intermediateStops ?? []) + [to] }
    /// The line to draw. A walk without a shape (some refreshed routes, very short walks)
    /// is a straight line from start to end instead of nothing.
    var mapPath: [LatLon] {
        let points = legGeometry.mapPoints
        if points.count > 1 { return points }
        let ends = [from.coordinate, to.coordinate]
        return ends[0] == ends[1] ? [] : ends
    }
    /// `mapPath` thinned out for small overview maps (see `OverviewPaths`).
    var overviewPath: [LatLon] {
        let g = legGeometry.points
        // utf8.count, not count: counting characters walks the whole (long) string on every draw.
        let u = g.utf8
        return OverviewPaths.path(mapPath, key: "\(u.count)|\(String(decoding: u.prefix(32), as: UTF8.self))|\(String(decoding: u.suffix(32), as: UTF8.self))")
    }
}

/// One piece of a walk as the router describes it. Turns are mostly "CONTINUE": `WalkGuide`
/// derives left/right from the geometry.
struct StepInstruction: Codable, Sendable {
    let relativeDirection: String?
    let distance: Double
    var fromLevel: Double? = nil
    var toLevel: Double? = nil
    var polyline: EncodedPolyline? = nil
    var streetName: String? = nil
    var exit: String? = nil
    var area: Bool? = nil
    /// OpenStreetMap nodes at the ends of this piece: a station entrance the walk passes through is one of them.
    var fromOsmNode: Int64? = nil
    var toOsmNode: Int64? = nil
}

/// One planned route's share of a route built leg by leg (#91): the server's ID of that route
/// (live times are refreshed through it) and which of its legs are used.
struct RoutePart: Codable, Hashable, Sendable {
    var itineraryId: String
    var firstLeg: Int
    var legCount: Int
}

struct Itinerary: Codable, Identifiable, Sendable {
    let id: String
    var duration: Int
    var startTime: Date
    var endTime: Date
    let transfers: Int
    var legs: [Leg]
    var fareTransfers: [FareTransfer]? = nil
    /// Only for a route built leg by leg (#91, `RouteBuilder`): the planned routes it is made of,
    /// in order. Routes from the server, saved trips and older versions have none.
    var builtFrom: [RoutePart]? = nil

    var transitLegs: [Leg] { legs.filter(\.isTransit) }
    var firstTransitLeg: Leg? { legs.first(where: \.isTransit) }
    var hasRealtime: Bool { legs.contains { $0.isTransit && $0.realTime } }
    /// A cancelled ride; walks have no service to cancel (a "cancelled" walk to a cancelled stop
    /// read "Walk from  does not run").
    var isCancelled: Bool { legs.contains { $0.isTransit && $0.cancelled == true } }
    /// Walking (or cycling) only, no public transport.
    var isDirect: Bool { transitLegs.isEmpty }
    /// Departure of the first vehicle (the moment that cannot be missed).
    var firstDeparture: Date? { firstTransitLeg?.startTime }

    /// Same route across live refreshes. The server's `id` encodes current times and changes
    /// with every delay update, so lists, selection and navigation must not depend on it.
    var routeKey: String {
        legs.map { leg in
            "\(leg.mode)~\(leg.tripId ?? leg.from.name)~\(Int64(leg.scheduledStartTime.timeIntervalSince1970))"
        }.joined(separator: "|")
    }
}

extension Itinerary {
    /// A route that gets to the destination (or back to where it was) and then rides on, e.g.
    /// 81 min on foot to Treporti, the ferry to Burano and the ferry back to Treporti. Such a
    /// route is never the way to go: the walk on its own already arrives.
    var isDetour: Bool {
        guard legs.count > 1, let last = legs.last, let first = legs.first else { return false }
        func point(_ p: Place) -> LatLon { LatLon(lat: p.lat, lon: p.lon) }
        let destination = point(last.to)
        // Start and destination next to each other: nothing to judge.
        guard point(first.from).distance(to: destination) >= 400 else { return false }
        for (i, leg) in legs.enumerated() {
            let ridesOn = legs[(i + 1)...].contains { $0.isTransit }
            if ridesOn, point(leg.to).distance(to: destination) < 250 { return true }
            if leg.isTransit, legs[..<i].contains(where: { point($0.from).distance(to: point(leg.to)) < 150 }) { return true }
        }
        return false
    }
}

/// A ride's line without the server's detours. Transitous draws a ride along the tracks of
/// OpenStreetMap; around large stations that line can leave the route between two stops in a row,
/// run along other tracks and come back (#114, Paris, checked on 2026-11-27: RER A from Châtelet
/// to Auber, 1.7 km apart, came with 14 km of line reaching 5 km away; métro 5 and 7 around Gare
/// de l'Est likewise). The map then drew branches the ride never takes.
enum LegShape {
    /// Stops closer than this prove nothing (platforms of one station, a loop back to its start).
    static let minStopGap = 150.0
    /// The line between two stops in a row counts as wrong when it is this many times as long as
    /// the straight way and at least `minExtra` metres longer. Real tracks stay below: the spirals
    /// of the Albula line between Bergün and Preda are 12.6 km for 4 km (3.1).
    static let maxRatio = 3.5
    static let minExtra = 1_000.0
    /// Rail only: a road with hairpins or a ferry around a headland can be several times the
    /// straight way, and nothing wrong has been seen there.
    static let railBound: Set<String> = VehicleKind.railModes.union(["SUBWAY", "METRO", "TRAM"])

    /// `path` with each such detour replaced by the straight way between its two stops; nil when
    /// there is none (the usual case, decided by adding up the path once).
    static func withoutDetours(_ path: [LatLon], stops: [LatLon]) -> [LatLon]? {
        guard path.count > 2, stops.count > 1 else { return nil }
        // No detour of `minExtra` fits into a line about as long as the way from stop to stop.
        guard PathGeometry.length(path) - PathGeometry.length(stops) >= minExtra else { return nil }
        // Where each stop lies on the line: the closest point at or after the stop before it.
        var at: [Int] = []
        var start = 0
        for stop in stops {
            let kx = cos(stop.lat * .pi / 180)
            var best = start, bestDistance = Double.infinity
            for i in start..<path.count {
                let dx = (path[i].lon - stop.lon) * kx, dy = path[i].lat - stop.lat
                let d = dx * dx + dy * dy
                if d < bestDistance { best = i; bestDistance = d }
            }
            at.append(best)
            start = best
        }
        var out = Array(path[...at[0]])
        var changed = false
        for k in 0..<(stops.count - 1) {
            let i = at[k], j = at[k + 1]
            guard j > i else { continue }
            let straight = stops[k].distance(to: stops[k + 1])
            let length = PathGeometry.length(Array(path[i...j]))
            if straight >= minStopGap, length >= maxRatio * straight, length - straight >= minExtra {
                out.append(path[j])
                changed = true
            } else {
                out.append(contentsOf: path[(i + 1)...j])
            }
        }
        out.append(contentsOf: path[(at[at.count - 1] + 1)...])
        return changed ? out : nil
    }
}

extension Leg {
    /// This ride with its line tidied (`LegShape`), also in the rides that can replace it.
    func tidyingShape() -> Leg {
        var leg = self
        if LegShape.railBound.contains(mode),
           let path = LegShape.withoutDetours(legGeometry.coordinates, stops: allStops.map(\.coordinate)) {
            leg.legGeometry = EncodedPolyline(coordinates: path, precision: legGeometry.precision)
        }
        if let alternatives { leg.alternatives = alternatives.map { $0.map { $0.tidyingShape() } } }
        return leg
    }
}

extension Itinerary {
    /// This route with the line of every ride tidied (`LegShape`).
    func tidyingShapes() -> Itinerary {
        var route = self
        route.legs = legs.map { $0.tidyingShape() }
        return route
    }

    /// A route the server planned the wrong way round: it starts at the destination and ends at the
    /// start. Transitous answers "Arrive by" searches that also ask for slower direct rides
    /// (`slowDirect`, smart routing) that way (#188, Saarbrücken, 2026-11-26: 4 of 9 routes rode from
    /// the university back into town, their last leg ending at "END" on the start's coordinates).
    /// Start and destination next to each other: nothing to judge.
    func runsBackwards(from: LatLon, to: LatLon) -> Bool {
        guard from.distance(to: to) >= 200, let first = legs.first, let last = legs.last else { return false }
        let start = first.from.coordinate, end = last.to.coordinate
        return start.distance(to: to) < start.distance(to: from) && end.distance(to: from) < end.distance(to: to)
    }
}

extension Array where Element == Itinerary {
    /// Without routes that pass the destination and ride on, or ride out and back (`isDetour`).
    var withoutDetours: [Itinerary] { filter { !$0.isDetour } }

    /// Without routes that run from the destination to the start (`runsBackwards`).
    func facing(from: LatLon, to: LatLon) -> [Itinerary] { filter { !$0.runsBackwards(from: from, to: to) } }

    /// One row per route: a page loaded twice or a refresh must not repeat an identity in a list.
    var uniqueRoutes: [Itinerary] {
        var seen = Set<String>()
        return filter { seen.insert($0.routeKey).inserted }
    }

    /// One row per ride: the same vehicles at the same times are one connection, however the walk
    /// to the first stop goes. The short- and long-walk searches both find the train you can
    /// see from here, and once "board here" drops the walk the two copies are identical (Brig → Visp,
    /// 2026-11-19: every connection twice). Of the copies the one arriving first stays, then the
    /// one leaving last (less walking); the list keeps its order otherwise.
    var uniqueRides: [Itinerary] {
        var best: [String: Int] = [:]
        for (i, it) in enumerated() {
            guard let j = best[it.rideKey] else { best[it.rideKey] = i; continue }
            let kept = self[j]
            if (it.endTime, kept.startTime) < (kept.endTime, it.startTime) { best[it.rideKey] = i }
        }
        let keep = Set(best.values)
        return enumerated().filter { keep.contains($0.offset) }.map(\.element)
    }
}

extension Itinerary {
    /// The vehicles ridden, where you get on and off and when (scheduled, so a delay update keeps
    /// the key); walks don't count. Getting off earlier and walking on is another connection.
    /// Walking only: the route itself, so a walk is never merged with another walk of other length.
    var rideKey: String {
        let rides = transitLegs
        guard !rides.isEmpty else { return "direct~" + routeKey }
        return rides.map { leg in
            "\(leg.mode)~\(leg.tripId ?? "\(leg.routeShortName ?? "")>\(leg.headsign ?? "")")~\(leg.from.name)~\(Int64(leg.scheduledStartTime.timeIntervalSince1970))~\(leg.to.name)~\(Int64(leg.scheduledEndTime.timeIntervalSince1970))"
        }.joined(separator: "|")
    }
}

/// A route opened from a list. Holds its own copy: a live refresh of the list underneath
/// neither closes the detail nor swallows the tap that opens it.
struct OpenedRoute: Hashable, Identifiable {
    let itinerary: Itinerary
    var id: String { itinerary.routeKey }
    static func == (a: OpenedRoute, b: OpenedRoute) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

struct PlanResponse: Decodable, Sendable {
    let direct: [Itinerary]
    let itineraries: [Itinerary]
    let previousPageCursor: String?
    let nextPageCursor: String?

    /// The same answer with another list of routes (paging cursors stay those of this search).
    func replacingItineraries(_ list: [Itinerary]) -> PlanResponse {
        PlanResponse(direct: direct, itineraries: list, previousPageCursor: previousPageCursor, nextPageCursor: nextPageCursor)
    }
}

/// A list read entry by entry: one the app cannot read (a feed leaves out a field the API promises)
/// is skipped instead of failing the whole answer. One odd ride must not turn a list of routes or a
/// departure board into "Unexpected response".
struct LossyList<Element: Decodable>: Decodable {
    private(set) var items: [Element] = []
    private(set) var skipped = 0

    private struct Anything: Decodable { init(from decoder: Decoder) throws {} }

    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        while !c.isAtEnd {
            let index = c.currentIndex
            if let item = try? c.decode(Element.self) {
                items.append(item)
            } else {
                skipped += 1
                if (try? c.decodeNil()) != true { _ = try? c.decode(Anything.self) }
            }
            // Never spin on an entry that cannot even be stepped over.
            if c.currentIndex == index { break }
        }
    }
}

extension PlanResponse {
    private enum CodingKeys: String, CodingKey { case direct, itineraries, previousPageCursor, nextPageCursor }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let routes = try c.decode(LossyList<Itinerary>.self, forKey: .itineraries)
        let street = try c.decodeIfPresent(LossyList<Itinerary>.self, forKey: .direct)
        itineraries = routes.items
        direct = street?.items ?? []
        previousPageCursor = try? c.decodeIfPresent(String.self, forKey: .previousPageCursor)
        nextPageCursor = try? c.decodeIfPresent(String.self, forKey: .nextPageCursor)
        let skipped = routes.skipped + (street?.skipped ?? 0)
        if skipped > 0 { HangLog.shared.note("plan: \(skipped) unreadable route(s) skipped") }
    }
}

extension StopTimesResponse {
    private enum CodingKeys: String, CodingKey { case stopTimes, place, nextPageCursor }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let list = try c.decode(LossyList<StopTime>.self, forKey: .stopTimes)
        stopTimes = list.items
        place = try? c.decodeIfPresent(Place.self, forKey: .place)
        nextPageCursor = try? c.decodeIfPresent(String.self, forKey: .nextPageCursor)
        if list.skipped > 0 { HangLog.shared.note("stoptimes: \(list.skipped) unreadable departure(s) skipped") }
    }
}

struct StopTime: Decodable, Identifiable, Sendable, RouteStyled {
    var place: Place
    let mode: String
    var realTime: Bool
    let headsign: String
    let agencyName: String?
    let routeId: String?
    let tripId: String
    let routeShortName: String?
    let displayName: String?
    let routeColor: String?
    let routeTextColor: String?
    var cancelled: Bool?
    let tripCancelled: Bool?
    /// Feed direction ("0"/"1"), when given; groups the two directions of a line.
    var directionId: String? = nil
    /// Last stop of the trip.
    var tripTo: SegmentStop? = nil
    /// First stop of the trip.
    var tripFrom: SegmentStop? = nil
    /// The train's own number in many rail feeds ("RE_6 - 2625"), see `tripNumberDetail`.
    var tripShortName: String? = nil
    /// Some feeds keep the train category only here ("rjx 66"), see `TransitLabels.trainName`.
    var routeLongName: String? = nil
    /// The stops after this one (`fetchStops=true`), first few only.
    var nextStops: UpcomingStops? = nil
    /// Extra real-time source that corrected this departure ("Wiener Linien"), see `LiveOverlay`.
    var liveSource: String? = nil

    /// By the timetable time where known: a new delay must not turn a row into a different row
    /// (in a list that would close a screen opened from it).
    var id: String {
        "\(tripId)|\(place.stopId ?? place.name)|\((scheduledDepartureTime ?? departureTime).timeIntervalSince1970)"
    }
    var directionName: String? { TransitLabels.direction(headsign: headsign, tripEnd: tripTo?.name) }
    /// Where the vehicle stops next. A destination you have never heard of says little; the next stop
    /// tells which way it goes (Prague: platform A or B, both "Staroměstská"). Nil when it is the
    /// destination anyway, or unknown.
    var nextStopName: String? {
        guard let next = nextStops?.names.first(where: {
            TransitLabels.identity($0) != TransitLabels.identity(place.name)
        }) else { return nil }
        if let d = directionName, TransitLabels.identity(d) == TransitLabels.identity(next) { return nil }
        return next
    }
    var departureTime: Date { place.departure ?? place.arrival ?? .distantPast }
    var scheduledDepartureTime: Date? { place.scheduledDeparture ?? place.scheduledArrival }
    var isCancelled: Bool { cancelled == true || tripCancelled == true || place.cancelled == true }
    var delayMinutes: Int {
        guard let s = scheduledDepartureTime else { return 0 }
        return Int((departureTime.timeIntervalSince(s) / 60).rounded())
    }
}

extension StopTime {
    /// Drops departures that have already left (saved boards shown offline can be minutes old).
    /// Also drops repeated entries, so list IDs stay unique.
    static func upcoming(_ list: [StopTime], now: Date = Date()) -> [StopTime] {
        var seen = Set<String>()
        return list.filter { $0.departureTime > now.addingTimeInterval(-60) && seen.insert($0.id).inserted }
    }
}

/// The first stops of a departure's remaining route. The server sends all of them to the end of the
/// trip; only the first few are kept, so a busy board stays small in memory and in the offline copy.
struct UpcomingStops: Codable, Hashable, Sendable {
    static let kept = 3
    let names: [String]

    init(names: [String]) { self.names = Array(names.prefix(Self.kept)) }

    private struct Stop: Codable { let name: String }

    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        var names: [String] = []
        while !c.isAtEnd {
            let stop = try c.decode(Stop.self)
            if names.count < Self.kept, let n = TransitLabels.clean(stop.name) { names.append(n) }
        }
        self.names = names
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        for n in names { try c.encode(Stop(name: n)) }
    }
}

struct StopTimesResponse: Decodable, Sendable {
    var stopTimes: [StopTime]
    let place: Place?
    let nextPageCursor: String?
}

struct GeocodeArea: Decodable, Hashable, Sendable {
    let name: String
    let adminLevel: Double?
    let `default`: Bool?
}

struct GeocodeMatch: Decodable, Identifiable, Hashable, Sendable {
    let type: String
    let name: String
    let id: String
    let lat: Double
    let lon: Double
    let street: String?
    let houseNumber: String?
    let country: String?
    let areas: [GeocodeArea]
    /// What kind of place (OSM based, e.g. "place_6", "suburb", "village", "restaurant_14"). Not for stops.
    let category: String?

    var isStop: Bool { type == "STOP" }
    var subtitle: String {
        var parts: [String] = []
        if !isStop, let street, street != name {
            parts.append([street, houseNumber].compactMap { $0 }.joined(separator: " "))
        }
        if let area = areas.first(where: { $0.default == true }) ?? areas.last { parts.append(area.name) }
        if let country { parts.append(country) }
        return parts.joined(separator: ", ")
    }
}

/// Where to ride in the train and which way out, for a ride that ends in a station (see `ExitAdvice.swift`).
/// Kept on the ride when the trip goes to the watch, which gets no walking directions to work it out.
struct ExitAdvice: Codable, Equatable, Sendable {
    /// Part of the train nearest the way out.
    enum Part: String, Codable, Sendable { case front, middle, back }

    var part: Part?
    /// The station door to take (its sign: "B2", "Nord"), when the walk after the ride leaves the station.
    var door: String? = nil
    /// The user chose this door (remembered for the station and destination).
    var doorSaved: Bool = false
    /// The part aims at the next train (a change in the station) rather than the way out.
    var forChange: Bool = false

    var isEmpty: Bool { part == nil && door == nil }
}

/// A stop on the station map (`/api/v6/map/stops`).
struct MapStop: Decodable, Identifiable, Hashable, Sendable {
    let name: String
    let stopId: String
    let parentId: String?
    let lat: Double
    let lon: Double
    let importance: Double?
    let modes: [String]?

    var id: String { stopId }
    var coordinate: LatLon { LatLon(lat: lat, lon: lon) }
    var stationId: String { parentId ?? stopId }
}

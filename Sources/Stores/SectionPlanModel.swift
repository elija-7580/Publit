// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich
import Foundation
import Observation

/// How one section of a journey planned section by section (#144) is travelled.
enum SectionMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case transit, walk, bike, car

    var id: String { rawValue }

    /// The street mode asked of the router; nil for public transport.
    var streetMode: String? {
        switch self {
        case .transit: return nil
        case .walk: return "WALK"
        case .bike: return "BIKE"
        case .car: return "CAR"
        }
    }

    var symbol: String {
        switch self {
        case .transit: return "tram.fill"
        case .walk: return "figure.walk"
        case .bike: return "bicycle"
        case .car: return "car.fill"
        }
    }

    var title: String {
        switch self {
        case .transit: return L10n.t("Public transport")
        case .walk: return L10n.t("On foot")
        case .bike: return L10n.t("By bike")
        case .car: return L10n.t("By car")
        }
    }
}

/// A journey laid out section by section (#144): places in order, a way to travel between each
/// two, and a stay at the places in between. Sections are searched one after the other, each not
/// before the one in front of it arrives plus the stay; together they are one route (`RouteBuilder.chain`).
@MainActor
@Observable
final class SectionPlanModel {
    /// One search for one section: the routes from A to B leaving at `time` or later.
    typealias Search = @Sendable (_ from: LatLon, _ to: LatLon, _ stops: PlanStops, _ time: Date, _ mode: SectionMode) async throws -> [Itinerary]

    enum SectionState: Equatable {
        case idle, loading, failed
        /// Nothing found that leaves after the section in front arrives.
        case empty
        case found
    }

    struct Section: Identifiable {
        let id = UUID()
        var mode: SectionMode = .transit
        var state: SectionState = .idle
        /// The ways to travel this section, earliest arrival first.
        var options: [Itinerary] = []
        var chosen = 0
        var route: Itinerary? { options.indices.contains(chosen) ? options[chosen] : nil }
    }

    struct Stop: Identifiable {
        let id = UUID()
        var place: Endpoint?
        /// Minutes spent here before going on (a place in between; unused at the start and the end).
        var stay = SectionPlanModel.defaultStay
    }

    /// A ride the user already has a ticket for (#24): section `index` leaves at `time` (the train on
    /// the ticket), and the section in front of it is the latest way that still arrives in time.
    struct Anchor: Equatable {
        var index: Int
        var time: Date
    }

    nonisolated static let defaultStay = 5
    nonisolated static let stays = [0, 5, 10, 15, 30, 60, 120]
    /// Start, destination and up to this many places in between.
    nonisolated static let maxStops = 6

    private(set) var stops: [Stop]
    /// `sections[i]` leads from `stops[i]` to `stops[i + 1]`.
    private(set) var sections: [Section]
    var date: Date
    /// The start time follows the clock until it is set by hand.
    var leavesNow = true
    /// Counts up whenever something changed that needs a new search.
    private(set) var revision = 0
    /// The ride fixed by a ticket, if the plan was started from one.
    private(set) var anchor: Anchor?

    @ObservationIgnored private let search: Search
    @ObservationIgnored private var token = UUID()

    init(from: Endpoint? = .currentLocation, to: Endpoint? = nil, date: Date = .now, search: @escaping Search = SectionPlanModel.liveSearch) {
        stops = [Stop(place: from), Stop(place: to)]
        sections = [Section()]
        self.date = date
        self.search = search
    }

    /// A plan with these places in order (at least two), optionally around a ride fixed by a ticket.
    init(places: [Endpoint?], anchor: Anchor? = nil, date: Date = .now, search: @escaping Search = SectionPlanModel.liveSearch) {
        let list = places.count >= 2 ? Array(places.prefix(Self.maxStops)) : [.currentLocation, nil]
        stops = list.enumerated().map { i, p in
            var stop = Stop(place: p)
            // Changing onto the ticket's train: no stay planned there, the arrival is planned around it.
            if let anchor, i == anchor.index { stop.stay = 0 }
            return stop
        }
        sections = (0..<(list.count - 1)).map { _ in Section() }
        self.date = date
        self.search = search
        if let anchor, sections.indices.contains(anchor.index) {
            self.anchor = anchor
            // The ticket's train is a ride, whatever was chosen before.
            sections[anchor.index].mode = .transit
        }
    }

    /// A plan around a ticket (#24): from `start` to where the ticket starts, the ticket's ride, then on
    /// to `destination` (nil: chosen next). `departure` is when the ride on the ticket leaves, if known.
    static func aroundTicket(start: Endpoint?, origin: Endpoint, destinationOfTicket: Endpoint, destination: Endpoint?,
                             departure: Date?, now: Date = .now, search: @escaping Search = SectionPlanModel.liveSearch) -> SectionPlanModel {
        let anchor = departure.flatMap { $0 > now ? Anchor(index: 1, time: $0) : nil }
        let model = SectionPlanModel(places: [start, origin, destinationOfTicket, destination], anchor: anchor,
                                     date: anchor.map { max(now, $0.time.addingTimeInterval(-Self.leadForTicket)) } ?? now, search: search)
        if anchor != nil { model.leavesNow = false }
        return model
    }

    /// How long before the ticket's ride the way there is searched from.
    nonisolated static let leadForTicket: TimeInterval = 3 * 3600

    // MARK: Layout

    var canAddStop: Bool { stops.count < Self.maxStops }

    /// A new place in between, before the destination; the last section is split in two.
    func addStop() {
        guard canAddStop else { return }
        stops.insert(Stop(), at: stops.count - 1)
        sections.insert(Section(mode: sections.last?.mode ?? .transit), at: sections.count - 1)
        invalidate(from: max(0, sections.count - 2))
    }

    /// Takes a place in between out; its two sections become one.
    func removeStop(at index: Int) {
        guard index > 0, index < stops.count - 1 else { return }
        stops.remove(at: index)
        sections.remove(at: index)
        anchor = nil
        invalidate(from: index - 1)
    }

    /// Moves places to another position, the start and the destination too (feedback on build 98:
    /// "you must be able to move the single parts"). Each place keeps its stay; each section keeps
    /// its way to travel by position; every section from the first one touched is searched again.
    func moveStops(from offsets: IndexSet, to destination: Int) {
        let moving = offsets.filter { stops.indices.contains($0) }.sorted()
        guard !moving.isEmpty, (0...stops.count).contains(destination) else { return }
        let picked = moving.map { stops[$0] }
        var rest = stops.enumerated().filter { !moving.contains($0.offset) }.map(\.element)
        let insertAt = destination - moving.filter { $0 < destination }.count
        rest.insert(contentsOf: picked, at: min(max(0, insertAt), rest.count))
        guard rest.map(\.id) != stops.map(\.id) else { return }
        let first = zip(rest, stops).enumerated().first { $0.element.0.id != $0.element.1.id }?.offset ?? 0
        stops = rest
        anchor = nil
        invalidate(from: max(0, first - 1))
    }

    func setPlace(_ place: Endpoint?, at index: Int) {
        guard stops.indices.contains(index) else { return }
        stops[index].place = place
        invalidate(from: max(0, index - 1))
    }

    func setStay(_ minutes: Int, at index: Int) {
        guard index > 0, index < stops.count - 1 else { return }
        stops[index].stay = max(0, minutes)
        invalidate(from: index)
    }

    func setMode(_ mode: SectionMode, at index: Int) {
        guard sections.indices.contains(index), sections[index].mode != mode else { return }
        sections[index].mode = mode
        invalidate(from: index)
    }

    /// Another way for one section; the sections after it are searched again from its arrival.
    func choose(_ option: Int, at index: Int) {
        guard sections.indices.contains(index), sections[index].options.indices.contains(option) else { return }
        sections[index].chosen = option
        invalidate(from: index + 1)
    }

    /// A change point of the route found for a section (#10): the section is split there, so the
    /// part after it can go another way (another mode, another departure, a stay).
    func split(_ index: Int, at place: Place) {
        guard sections.indices.contains(index), canAddStop else { return }
        let sid = place.parentId ?? place.stopId
        var stop = Stop(place: .place(SavedPlace(id: "change|\(sid ?? "\(place.lat),\(place.lon)")", name: place.name, subtitle: nil,
                                                 lat: place.lat, lon: place.lon, stopId: sid)))
        stop.stay = 0
        stops.insert(stop, at: index + 1)
        sections.insert(Section(mode: sections[index].mode), at: index + 1)
        if let a = anchor, a.index > index { anchor = Anchor(index: a.index + 1, time: a.time) }
        invalidate(from: index)
    }

    /// Where the chosen way of a section stops on the way: where it changes and every stop of its
    /// rides, in order, the same station once. Section ends are left out.
    func changePoints(of index: Int) -> [Place] {
        guard sections.indices.contains(index), let route = sections[index].route else { return [] }
        return Self.changePoints(route)
    }

    nonisolated static func changePoints(_ route: Itinerary) -> [Place] {
        var result: [Place] = []
        var seen = Set<String>()
        let rides = route.legs.filter(\.isTransit)
        for (i, leg) in rides.enumerated() {
            var stops = leg.intermediateStops ?? []
            if i < rides.count - 1 { stops.append(leg.to) }
            if i > 0 { stops.insert(leg.from, at: 0) }
            for p in stops where seen.insert(StopGrouping.normalizedName(p.name)).inserted { result.append(p) }
        }
        return result
    }

    func setDate(_ new: Date, now: Date = .now) {
        date = new
        leavesNow = abs(new.timeIntervalSince(now)) < 90
        invalidate(from: 0)
    }

    private func invalidate(from index: Int) {
        token = UUID()
        revision += 1
        for i in sections.indices where i >= index {
            sections[i].options = []
            sections[i].chosen = 0
            sections[i].state = .idle
        }
    }

    // MARK: Result

    /// Every place is set.
    var isComplete: Bool { stops.allSatisfy { $0.place != nil } }
    var isLoading: Bool { sections.contains { $0.state == .loading } }

    /// The whole journey as one route, once every section has a way.
    var route: Itinerary? {
        let chosen = sections.compactMap(\.route)
        guard chosen.count == sections.count else { return nil }
        return RouteBuilder.chain(chosen)
    }

    /// When section `index` may start at the earliest: the start time for the first, else the
    /// arrival of the section in front plus the stay at the place between them.
    func earliest(for index: Int) -> Date? {
        if let anchor, anchor.index == index { return anchor.time.addingTimeInterval(-60) }
        guard index > 0 else { return date }
        guard let arrival = sections[index - 1].route?.endTime else { return nil }
        return arrival.addingTimeInterval(Double(stops[index].stay) * 60)
    }

    /// Searches every section that has no way yet, in order. `current` stands in for "Current location".
    func plan(current: LatLon?, now: Date = .now) async {
        if leavesNow { date = now }
        let mine = UUID()
        token = mine
        for i in sections.indices {
            if sections[i].state == .found { continue }
            guard let from = stops[i].place, let to = stops[i + 1].place,
                  let a = from.coordinate(current: current), let b = to.coordinate(current: current),
                  let time = earliest(for: i) else { return }
            sections[i].state = .loading
            let mode = sections[i].mode
            // The way to the ticket's ride: searched from a while before it, the latest that arrives in time.
            let deadline = anchor.flatMap { $0.index == i + 1 ? $0.time.addingTimeInterval(-Double(stops[i + 1].stay) * 60) : nil }
            let searchTime = deadline.map { max(time, $0.addingTimeInterval(-Self.leadForTicket)) } ?? time
            let result = try? await search(a, b, PlanStops(from: from.stopId, to: to.stopId), searchTime, mode)
            guard token == mine else { return }
            // The screen went away mid-search: not a failure, the next search starts over here.
            if Task.isCancelled { sections[i].state = .idle; return }
            guard let found = result else { sections[i].state = .failed; return }
            var usable = Self.usable(found, notBefore: searchTime, mode: mode)
            var chosen = 0
            if let deadline {
                usable = usable.filter { $0.endTime <= deadline }
                // The latest that is still in time: no long wait at the station.
                chosen = max(0, usable.count - 1)
            }
            sections[i].options = usable
            sections[i].chosen = chosen
            sections[i].state = usable.isEmpty ? .empty : .found
            if usable.isEmpty { return }
        }
    }

    /// What can be taken: it leaves at `time` or later; earliest arrival first, the same rides once.
    /// Public transport sections list rides only (the walk is its own mode).
    nonisolated static func usable(_ found: [Itinerary], notBefore time: Date, mode: SectionMode) -> [Itinerary] {
        var seen = Set<String>()
        return found
            .filter { !$0.legs.isEmpty && $0.startTime >= time.addingTimeInterval(-30) && !$0.isCancelled }
            .filter { mode != .transit || !$0.isDirect }
            .filter { seen.insert($0.routeKey).inserted }
            .sorted { ($0.endTime, $0.startTime) < ($1.endTime, $1.startTime) }
    }

    nonisolated static let liveSearch: Search = { from, to, stops, time, mode in
        if let street = mode.streetMode {
            return try await TransitousClient.shared.streetRoutes(from: from, to: to, time: time, arriveBy: false, mode: street)
        }
        return try await TransitousClient.shared.plan(from: from, to: to, time: time, arriveBy: false,
                                                      options: RouteOptions.load(), stops: stops).itineraries
    }
}

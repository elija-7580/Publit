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

    @ObservationIgnored private let search: Search
    @ObservationIgnored private var token = UUID()

    init(from: Endpoint? = .currentLocation, to: Endpoint? = nil, date: Date = .now, search: @escaping Search = SectionPlanModel.liveSearch) {
        stops = [Stop(place: from), Stop(place: to)]
        sections = [Section()]
        self.date = date
        self.search = search
    }

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
        invalidate(from: index - 1)
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
            let result = try? await search(a, b, PlanStops(from: from.stopId, to: to.stopId), time, mode)
            guard token == mine else { return }
            // The screen went away mid-search: not a failure, the next search starts over here.
            if Task.isCancelled { sections[i].state = .idle; return }
            guard let found = result else { sections[i].state = .failed; return }
            let usable = Self.usable(found, notBefore: time, mode: mode)
            sections[i].options = usable
            sections[i].chosen = 0
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

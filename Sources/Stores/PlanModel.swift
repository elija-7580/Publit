import Foundation
import Observation

enum Endpoint: Hashable, Codable, Sendable {
    case currentLocation
    case place(SavedPlace)

    var title: String {
        switch self {
        case .currentLocation: return L10n.t("Current location")
        case .place(let p): return p.name
        }
    }

    var key: String {
        switch self {
        case .currentLocation: return "here"
        case .place(let p): return p.id
        }
    }

    func coordinate(current: LatLon?) -> LatLon? {
        switch self {
        case .currentLocation: return current
        case .place(let p): return p.coordinate
        }
    }
}

enum TimeMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case now = "Now"
    case departAt = "Depart"
    case arriveBy = "Arrive"
    var id: String { rawValue }
}

@MainActor
@Observable
final class PlanModel {
    var from: Endpoint = .currentLocation
    var to: Endpoint?
    var timeMode: TimeMode = .now
    var date = Date()

    /// Filters and comparison, shared by Plan and Nearby → "Where to now?" (set through AppState).
    var options = RouteOptions.load()

    private(set) var itineraries: [Itinerary] = []
    /// Walking, cycling and driving the whole way, when asked for (`options.compareStreetModes`).
    private(set) var comparisons: [StreetComparison] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var errorMessage: String?

    private var nextCursor: String?
    @ObservationIgnored private var lastRequest: (from: LatLon, to: LatLon, time: Date?, arriveBy: Bool, maxWalk: Int)?
    @ObservationIgnored private var lastOptions = RouteOptions()
    @ObservationIgnored private var token = UUID()
    @ObservationIgnored private var resultsKey: String?
    @ObservationIgnored var history: SearchHistoryStore = .shared

    /// The routes in the order chosen in the options (fastest, fewest changes, …).
    var sortedItineraries: [Itinerary] { options.sort.apply(itineraries) }

    var canLoadMore: Bool { nextCursor != nil && !itineraries.isEmpty }

    /// Changes whenever a new search is needed.
    var queryKey: String {
        let t = timeMode == .now ? "now" : String(Int(date.timeIntervalSince1970 / 60))
        return "\(from.key)|\(to?.key ?? "-")|\(timeMode.rawValue)|\(t)|\(options.key)"
    }

    func swap() {
        guard let t = to else { return }
        to = from
        from = t
    }

    /// - Parameter silent: refresh in place without a spinner (periodic live update).
    func search(current: LatLon?, locationDenied: Bool = false, silent: Bool = false) async {
        guard let to else {
            itineraries = []; comparisons = []; errorMessage = nil; return
        }
        guard let f = from.coordinate(current: current), let t = to.coordinate(current: current) else {
            itineraries = []; comparisons = []
            errorMessage = locationDenied
                ? L10n.t("Location is off. Choose a start point, or allow location access in Settings.")
                : L10n.t("Waiting for your location…")
            return
        }
        // Results of another query (new destination or time) must not stay on screen without a spinner.
        if !silent, resultsKey != queryKey { itineraries = []; comparisons = []; nextCursor = nil }
        let searchedFrom = from
        let searchedMode = timeMode
        let searchedDate = date
        let myToken = UUID()
        token = myToken
        if !silent { isLoading = true }
        defer { if token == myToken { isLoading = false } }
        errorMessage = nil
        let time: Date? = timeMode == .now ? nil : date
        let arriveBy = timeMode == .arriveBy
        let options = options
        do {
            var maxWalk = options.maxWalkMinutes * 60
            var res = try await TransitousClient.shared.plan(from: f, to: t, time: time, arriveBy: arriveBy,
                                                             maxWalk: maxWalk, options: options)
            if res.itineraries.isEmpty, options.maxWalkMinutes == RouteOptions.defaultWalkMinutes {
                // Nothing within 30 min walk of a stop: try once more with a longer walk.
                // Not when the user chose a shorter walk: that limit is theirs.
                maxWalk = TransitousClient.widerWalkLimit
                res = try await TransitousClient.shared.plan(from: f, to: t, time: time, arriveBy: arriveBy,
                                                             maxWalk: maxWalk, options: options)
            }
            guard token == myToken else { return }
            itineraries = Self.merge(transit: res.itineraries, direct: res.direct)
            comparisons = Self.comparisons(direct: res.direct, listed: itineraries, enabled: options.compareStreetModes)
            resultsKey = queryKey
            nextCursor = arriveBy ? res.previousPageCursor : res.nextPageCursor
            lastRequest = (f, t, time, arriveBy, maxWalk)
            lastOptions = options
            if !silent { history.record(from: searchedFrom, to: to, mode: searchedMode, date: searchedDate) }
            if itineraries.isEmpty {
                errorMessage = options.isDefault ? L10n.t("No connections found.")
                    : L10n.t("No connections found with these filters.")
            }
        } catch {
            guard token == myToken, !Self.isCancellation(error) else { return }
            // A failed background refresh keeps the routes already on screen.
            if !silent || itineraries.isEmpty {
                itineraries = []
                comparisons = []
                errorMessage = error.localizedDescription
            }
        }
    }

    func loadMore() async {
        guard let req = lastRequest, let cursor = nextCursor, !isLoadingMore else { return }
        let myToken = token
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let res = try await TransitousClient.shared.plan(from: req.from, to: req.to, time: req.time,
                                                             arriveBy: req.arriveBy, pageCursor: cursor, maxWalk: req.maxWalk,
                                                             options: lastOptions)
            // A new search started meanwhile: these results belong to the old query.
            guard token == myToken else { return }
            let known = Set(itineraries.map(\.id))
            let fresh = res.itineraries.filter { !known.contains($0.id) }
            itineraries = (itineraries + fresh).sorted { $0.startTime < $1.startTime }
            nextCursor = req.arriveBy ? res.previousPageCursor : res.nextPageCursor
        } catch {
            if !Self.isCancellation(error) { errorMessage = error.localizedDescription }
        }
    }

    /// Walking there is listed first when it is about as fast as the best ride, or the only way.
    nonisolated static func merge(transit: [Itinerary], direct: [Itinerary]) -> [Itinerary] {
        // Only walking joins the list; cycling and driving are shown as a comparison.
        let walking = direct.filter { let m = StreetComparison.streetMode($0); return m != "BIKE" && m != "CAR" }
        guard let walk = walking.min(by: { $0.duration < $1.duration }) else { return transit }
        guard let best = transit.map(\.duration).min() else { return [walk] }
        let worthIt = Double(walk.duration) <= Double(best) * 1.25 || walk.duration <= 10 * 60
        return worthIt ? [walk] + transit : transit
    }

    /// Street modes to compare. Walking is left out when it is already in the list of routes.
    nonisolated static func comparisons(direct: [Itinerary], listed: [Itinerary], enabled: Bool) -> [StreetComparison] {
        guard enabled else { return [] }
        let listedIds = Set(listed.map(\.id))
        return StreetComparison.from(direct).filter { !($0.mode == "WALK" && listedIds.contains($0.itinerary.id)) }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let e = error as? URLError, e.code == .cancelled { return true }
        return false
    }
}

enum AppTab: Hashable { case nearby, plan, lines, tickets, favorites }

@MainActor
@Observable
final class AppState {
    var tab: AppTab = .nearby
    /// Plan tab: trips for later (tonight, next week).
    let plan: PlanModel = {
        let m = PlanModel()
        m.timeMode = .departAt
        return m
    }()
    /// Nearby tab: "from here, now".
    let goNow = PlanModel()
    /// Set by publit:// links (calendar events, Live Activity buttons).
    var deepLink: DeepLink?
    /// Nearby shows "Where to now?" results (also opened by Siri: "Take me home").
    var showGoNow = false
    /// The first departure board is on screen (or could not load): the launch animation may end.
    var firstBoardReady = false

    func open(_ url: URL) {
        guard let link = DeepLink(url: url) else { return }
        if !Features.passes, case .ticket = link { return }
        if !Features.passes, case .tripTickets = link { return }
        // The default ticket link opens the Tickets tab.
        if case .ticket(nil) = link { tab = .tickets; deepLink = nil; return }
        switch link {
        case .trip: tab = .plan
        case .stop: tab = .nearby
        case .ticket, .tripTickets, .go: break
        }
        deepLink = link
    }

    /// Routes from the current location to `place`, leaving now (Nearby → "Where to now?").
    func goNow(to place: SavedPlace) {
        goNow.from = .currentLocation
        goNow.to = .place(place)
        goNow.timeMode = .now
        tab = .nearby
        showGoNow = true
    }

    /// Route filters apply to Plan and to "Where to now?" alike, and are kept for the next launch.
    var routeOptions: RouteOptions { plan.options }

    func setRouteOptions(_ options: RouteOptions) {
        plan.options = options
        goNow.options = options
        options.save()
    }

    func route(to place: SavedPlace) {
        plan.to = .place(place)
        tab = .plan
    }

    /// Preset state for UI tests and store screenshots (`PUBLIT_DEMO=munich`).
    func applyDemo(_ name: String?) {
        guard name == "munich" else { return }
        plan.from = .place(SavedPlace(id: "demo-marienplatz", name: "Marienplatz", subtitle: "München",
                                      lat: 48.1372, lon: 11.5755, stopId: nil))
        plan.to = .place(SavedPlace(id: "demo-muc", name: "Flughafen München", subtitle: nil,
                                    lat: 48.3537, lon: 11.7861, stopId: nil))
    }
}

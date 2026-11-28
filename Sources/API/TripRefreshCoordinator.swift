import Foundation

/// The foreground activity refresher and an open trip screen share one request.
/// A very short completed-result window also absorbs slightly staggered refresh timers.
actor TripRefreshCoordinator {
    static let shared = TripRefreshCoordinator()
    private var inFlight: [String: Task<Itinerary, Error>] = [:]
    private var recent: [String: (Itinerary, Date)] = [:]
    private let load: @Sendable (String) async throws -> Itinerary

    init(load: @escaping @Sendable (String) async throws -> Itinerary = { try await TripRefreshCoordinator.fetch($0) }) { self.load = load }

    /// A planned route by its server ID; a ride from the vehicle you are on (`OnBoardPlan`) from
    /// that vehicle's trip.
    static func fetch(_ id: String) async throws -> Itinerary {
        if let ride = OnBoardPlan.parseRide(id) {
            let trip = try await TransitousClient.shared.trip(id: ride.tripId)
            guard let cut = OnBoardPlan.refreshed(id, trip: trip) else { throw RouteBuilder.NoLongerTheSame() }
            return cut
        }
        return try await TransitousClient.shared.refresh(itineraryId: id)
    }

    func refresh(_ id: String, now: Date = .now) async throws -> Itinerary {
        if let task = inFlight[id] { return try await task.value }
        if let hit = recent[id], now.timeIntervalSince(hit.1) >= 0, now.timeIntervalSince(hit.1) < 3 { return hit.0 }
        let loader = load
        let task = Task { try await loader(id) }
        inFlight[id] = task
        defer { inFlight[id] = nil }
        let value = try await task.value
        recent = recent.filter { now.timeIntervalSince($0.value.1) < 3 }
        recent[id] = (value, now)
        return value
    }

    /// Fresh live times for a route. One built leg by leg (#91) is made of several planned routes:
    /// each is refreshed on its own and the route is put together again from them.
    func refresh(route: Itinerary, now: Date = .now) async throws -> Itinerary {
        guard route.builtFrom != nil else { return try await refresh(route.id, now: now) }
        var fresh: [String: Itinerary] = [:]
        for id in RouteBuilder.refreshIds(of: route) { fresh[id] = try await refresh(id, now: now) }
        guard let built = RouteBuilder.refreshed(route, with: fresh) else { throw RouteBuilder.NoLongerTheSame() }
        return built
    }

    /// A built route from a link (#145): every part's planned route is fetched and the route put together.
    func load(parts: [RoutePart], now: Date = .now) async throws -> Itinerary {
        var fetched: [String: Itinerary] = [:]
        for id in Set(parts.map(\.itineraryId)) { fetched[id] = try await refresh(id, now: now) }
        guard let built = RouteBuilder.assemble(parts, from: fetched) else { throw RouteBuilder.NoLongerTheSame() }
        return built
    }
}

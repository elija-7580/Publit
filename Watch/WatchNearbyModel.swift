import Foundation
import Observation

/// Departures around the watch, with the phone's radius steps (500 m, 1.5 km, 5 km): a ferry
/// 3 km away is listed with its distance instead of an empty screen.
@MainActor
@Observable
final class WatchNearbyModel {
    enum Status: Equatable { case idle, locating, loading, loaded, noLocation, denied, failed }

    private(set) var status: Status = .idle
    private(set) var groups: [StopGroup] = []
    private(set) var farDistance: Double?
    private(set) var updated: Date?

    /// Where the list is for: Nearby shows a note when this place has little or no timetable data.
    private(set) var position: LatLon?

    @ObservationIgnored private var loading = false

    /// Stops shown at once; the watch screen is small.
    static let maxStops = 6
    static let perStop = 4

    func refresh() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        if groups.isEmpty { status = .locating }
        guard let here = await WatchLocator.shared.locate() else {
            status = WatchLocator.shared.isDenied ? .denied : (groups.isEmpty ? .noLocation : .loaded)
            return
        }
        position = here
        if groups.isEmpty { status = .loading }
        do {
            var res = StopTimesResponse(stopTimes: [], place: nil, nextPageCursor: nil)
            for r in Reach.nearbyRadii where res.stopTimes.isEmpty {
                res = try await TransitousClient.shared.departures(near: here, radius: r, count: 40)
            }
            let found = StopGrouping.group(StopTime.upcoming(res.stopTimes), around: here)
            groups = Array(found.sorted { ($0.distance ?? 0) < ($1.distance ?? 0) }.prefix(Self.maxStops))
            farDistance = groups.compactMap(\.distance).min().flatMap { $0 >= Reach.farDistance ? $0 : nil }
            updated = Date()
            status = .loaded
        } catch {
            status = groups.isEmpty ? .failed : .loaded
        }
    }
}

// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich

import Foundation

/// One departure as widgets and complications show it (iPhone widgets, Apple Watch complications).
struct WidgetDeparture: Identifiable, Hashable, RouteStyled {
    let id: String
    let lineName: String
    let mode: String
    let background: String
    let foreground: String
    let service: String?
    var routeShortName: String? { lineName }
    var displayName: String? { service }
    var routeColor: String? { background }
    var routeTextColor: String? { foreground }
    let headsign: String
    let circular: Bool
    let time: Date
    let delayMinutes: Int
    let realTime: Bool
    let cancelled: Bool
    let tz: String?

    init(_ st: StopTime) {
        id = st.id
        lineName = st.lineName
        mode = st.mode
        background = st.lineColors.background
        foreground = st.lineColors.text
        service = st.serviceDetail
        headsign = st.shownDirection ?? ""
        circular = st.isCircular
        time = st.departureTime
        delayMinutes = st.delayMinutes
        realTime = st.realTime
        cancelled = st.isCancelled
        tz = st.place.tz
    }
}

/// One stop of the nearby widget and complication (#18, #19): its name, how far, its next departures.
struct NearbyBoardStop: Identifiable, Hashable {
    let id: String
    let name: String
    let lat: Double
    let lon: Double
    /// Metres from where the phone or watch is.
    let distance: Double?
    /// A saved stop the user picked for the widget.
    let favorite: Bool
    let departures: [WidgetDeparture]

    var deepLink: URL { DeepLink.stop(id: id, name: name, lat: lat, lon: lon).url }
}

/// A saved stop that goes first when it is close (`NearbyBoard.favoriteRadius`).
struct NearbyFavorite: Hashable, Sendable {
    let stopId: String
    let name: String
    let coordinate: LatLon
}

/// Departures around a place for widgets: saved stops close by first, then the nearest stations.
enum NearbyBoard {
    /// A favourite stop within this many metres comes first (a few minutes on foot).
    static let favoriteRadius = 600.0
    static let perStop = 4

    /// Which favourites are close enough to go first, nearest first.
    static func closeFavorites(_ favorites: [NearbyFavorite], at here: LatLon) -> [NearbyFavorite] {
        favorites.filter { $0.coordinate.distance(to: here) <= favoriteRadius }
            .sorted { $0.coordinate.distance(to: here) < $1.coordinate.distance(to: here) }
    }

    /// Stops to show: close favourites (in that order), then the nearest groups not already shown.
    static func merge(favorites: [NearbyBoardStop], nearby: [StopGroup], here: LatLon, limit: Int,
                      now: Date = .now) -> [NearbyBoardStop] {
        var result = favorites.filter { !$0.departures.isEmpty }
        for g in nearby where result.count < limit {
            let taken = result.contains { f in
                StopGrouping.normalizedName(f.name) == StopGrouping.normalizedName(g.name)
                    && LatLon(lat: f.lat, lon: f.lon).distance(to: g.coordinate) < StopGrouping.mergeRadius
            }
            if taken { continue }
            let list = StopTime.upcoming(g.departures, now: now).prefix(perStop).map(WidgetDeparture.init)
            guard !list.isEmpty else { continue }
            result.append(NearbyBoardStop(id: g.stopIds.first ?? g.id, name: g.name, lat: g.coordinate.lat,
                                          lon: g.coordinate.lon, distance: g.distance ?? g.coordinate.distance(to: here),
                                          favorite: false, departures: Array(list)))
        }
        return Array(result.prefix(limit))
    }

    /// Loads the board at `here`: one request per close favourite (at most two) and one for the area.
    static func load(at here: LatLon, favorites: [NearbyFavorite], limit: Int, now: Date = .now) async throws -> [NearbyBoardStop] {
        var fav: [NearbyBoardStop] = []
        for f in closeFavorites(favorites, at: here).prefix(2) {
            guard let res = try? await TransitousClient.shared.departures(stopId: f.stopId, count: 20, radius: 150) else { continue }
            let list = StopTime.upcoming(res.stopTimes, now: now).prefix(perStop).map(WidgetDeparture.init)
            fav.append(NearbyBoardStop(id: f.stopId, name: f.name, lat: f.coordinate.lat, lon: f.coordinate.lon,
                                       distance: f.coordinate.distance(to: here), favorite: true, departures: Array(list)))
        }
        var res = StopTimesResponse(stopTimes: [], place: nil, nextPageCursor: nil)
        for r in Reach.nearbyRadii.prefix(2) where res.stopTimes.isEmpty && fav.count < limit {
            res = try await TransitousClient.shared.departures(near: here, radius: r, count: 40)
        }
        let groups = StopGrouping.group(StopTime.upcoming(res.stopTimes, now: now), around: here)
        return merge(favorites: fav, nearby: groups, here: here, limit: limit, now: now)
    }
}

// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich
import XCTest
@testable import Publit

/// The remaining community wishes: saved connections (#28), lines in one direction (#21),
/// own shortcuts (#22) and the nearby board of widgets and complications (#18, #19).
@MainActor
final class CommunityWishesTests: XCTestCase {
    private func store() -> FavoritesStore {
        FavoritesStore(defaults: UserDefaults(suiteName: "publit-wishes-\(UUID().uuidString)")!)
    }

    private func place(_ id: String, lat: Double = 48.2, stop: Bool = false) -> SavedPlace {
        SavedPlace(id: id, name: "Place \(id)", subtitle: nil, lat: lat, lon: 16.37, stopId: stop ? id : nil)
    }

    private func departures() throws -> [StopTime] {
        try TransitousClient.makeDecoder().decode(StopTimesResponse.self, from: Fixtures.data("stoptimes_marienplatz")).stopTimes
    }

    // MARK: #28

    func testConnectionIsSavedOnceAndKeptAcrossLaunches() async {
        let defaults = UserDefaults(suiteName: "publit-wishes-\(UUID().uuidString)")!
        var home = place("h")
        home.role = .home
        let s = FavoritesStore(defaults: defaults)
        s.toggleConnection(from: home, to: place("w", lat: 48.3, stop: true))
        XCTAssertTrue(s.containsConnection(from: home, to: place("w", lat: 48.3, stop: true)))
        XCTAssertFalse(s.containsConnection(from: place("w", lat: 48.3, stop: true), to: home), "the way back is another connection")
        // Stored without Home's role: it only says where to plan from.
        XCTAssertNil(s.connections[0].from.role)
        XCTAssertEqual(FavoritesStore(defaults: defaults).connections.count, 1)
        s.toggleConnection(from: home, to: place("w", lat: 48.3, stop: true))
        XCTAssertTrue(s.connections.isEmpty)
    }

    func testConnectionWayBackSwapsTheEnds() async {
        let c = SavedConnection(from: place("a"), to: place("b", lat: 48.4))
        XCTAssertEqual(c.reversed.from.id, "b")
        XCTAssertEqual(c.reversed.to.id, "a")
        XCTAssertNotEqual(c.id, c.reversed.id)
    }

    func testRouteForAConnectionPlansFromStartToEndNow() async {
        let app = AppState()
        app.tab = .favorites
        let c = SavedConnection(from: place("a"), to: place("b", lat: 48.4))
        app.route(c)
        XCTAssertEqual(app.tab, .plan)
        XCTAssertEqual(app.plan.from, .place(c.from))
        XCTAssertEqual(app.plan.to, .place(c.to))
        XCTAssertTrue(app.plan.searchStarted)
    }

    // MARK: #21

    func testLineSavedFromADepartureKeepsItsDirection() async throws {
        let list = try departures()
        let st = try XCTUnwrap(list.first)
        let line = SavedLine(stopTime: st, stopId: "x", stopName: "Marienplatz", at: LatLon(lat: 48.137, lon: 11.575))
        XCTAssertEqual(line.directionId, LineDirection.groupId(st))
        XCTAssertNotNil(line.headsign)
        XCTAssertTrue(line.matches(st))
        // Same line the other way is not this saved line.
        if let other = list.first(where: { SavedLine.key($0) == SavedLine.key(st) && LineDirection.groupId($0) != line.directionId }) {
            XCTAssertFalse(line.matches(other))
        }
        let all = SavedLine(stopTime: st, stopId: "x", stopName: "Marienplatz", at: LatLon(lat: 48.137, lon: 11.575), direction: false)
        XCTAssertNil(all.directionId)
        XCTAssertNotEqual(all.id, line.id, "both can be saved")
        XCTAssertEqual(all.lineAtStop, line.lineAtStop)
    }

    func testOldSavedLinesStillDecodeForEveryDirection() async throws {
        let json = #"[{"routeKey":"r1","mode":"BUS","stopId":"s","stopName":"S","lat":48,"lon":16}]"#
        let lines = try JSONDecoder().decode([SavedLine].self, from: Data(json.utf8))
        XCTAssertNil(lines[0].directionId)
        XCTAssertEqual(lines[0].id, "r1@s")
    }

    func testLineRefFromADirectionSavedLinePreselectsIt() async throws {
        let st = try XCTUnwrap(try departures().first)
        let line = SavedLine(stopTime: st, stopId: "x", stopName: "M", at: LatLon(lat: 48, lon: 11))
        XCTAssertEqual(LineRef(saved: line).headsigns, [line.headsign!])
    }

    // MARK: #22

    func testShortcutsGoNextToHomeAndWork() async {
        let s = store()
        var home = place("h")
        home.role = .home
        s.set(home, as: .home)
        s.toggle(place("gym", lat: 48.25))
        XCTAssertEqual(s.places.map(\.id), ["gym"])
        s.addShortcut(place("gym", lat: 48.25), symbol: "dumbbell.fill")
        XCTAssertEqual(s.shortcuts.map(\.id), ["gym"])
        XCTAssertTrue(s.places.isEmpty, "a shortcut is not listed twice")
        XCTAssertEqual(s.pinned.map(\.id), ["h", "gym"])
        XCTAssertEqual(s.shortcuts[0].shownSymbol, "dumbbell.fill")
        s.addShortcut(place("school", lat: 48.26))
        XCTAssertEqual(s.shortcuts.map(\.id), ["gym", "school"])
        s.moveShortcuts(fromOffsets: IndexSet([1]), toOffset: 0)
        XCTAssertEqual(s.shortcuts.map(\.id), ["school", "gym"])
        s.removeShortcut("gym")
        XCTAssertEqual(s.shortcuts.map(\.id), ["school"])
        XCTAssertEqual(s.places.map(\.id), ["gym"], "removing the shortcut keeps the saved place")
    }

    #if canImport(AppIntents) && !SWIFT_PACKAGE
    func testShortcutEntityKeepsItsDataInTheIdentifier() async throws {
        let e = ShortcutEntity(name: "Gym | West", lat: 48.2, lon: 16.3, symbol: "dumbbell.fill")
        let back = try XCTUnwrap(ShortcutEntity(id: e.id))
        XCTAssertEqual(back.title, "Gym | West")
        XCTAssertEqual(back.symbol, "dumbbell.fill")
        XCTAssertEqual(DeepLink(url: back.deepLink), .place(name: "Gym | West", lat: 48.2, lon: 16.3))
        XCTAssertEqual(DeepLink(url: try XCTUnwrap(ShortcutEntity(id: "home")).deepLink), .go(.home))
        XCTAssertNil(ShortcutEntity(id: "p|x|y|z"))
    }
    #endif

    // MARK: #18, #19

    func testNearbyBoardPutsCloseFavouritesFirst() async throws {
        let here = LatLon(lat: 48.137, lon: 11.575)
        let near = NearbyFavorite(stopId: "a", name: "A", coordinate: LatLon(lat: 48.138, lon: 11.575))
        let far = NearbyFavorite(stopId: "b", name: "B", coordinate: LatLon(lat: 48.2, lon: 11.6))
        XCTAssertEqual(NearbyBoard.closeFavorites([far, near], at: here).map(\.stopId), ["a"])

        let list = try departures()
        let now = list.map(\.departureTime).min()!.addingTimeInterval(-60)
        let groups = StopGrouping.group(StopTime.upcoming(list, now: now), around: here)
        let fav = NearbyBoardStop(id: "a", name: "Favourite", lat: 48.138, lon: 11.575, distance: 100, favorite: true,
                                  departures: Array(list.prefix(1).map(WidgetDeparture.init)))
        let board = NearbyBoard.merge(favorites: [fav], nearby: groups, here: here, limit: 2, now: now)
        XCTAssertEqual(board.first?.name, "Favourite")
        XCTAssertLessThanOrEqual(board.count, 2)
        // A favourite that is the same station as a nearby group is not shown twice.
        let same = NearbyBoardStop(id: "m", name: groups[0].name, lat: groups[0].coordinate.lat, lon: groups[0].coordinate.lon,
                                   distance: 0, favorite: true, departures: Array(list.prefix(1).map(WidgetDeparture.init)))
        let deduped = NearbyBoard.merge(favorites: [same], nearby: groups, here: here, limit: 5, now: now)
        XCTAssertEqual(deduped.filter { StopGrouping.normalizedName($0.name) == StopGrouping.normalizedName(groups[0].name) }.count, 1)
        XCTAssertTrue(deduped.allSatisfy { $0.departures.count <= NearbyBoard.perStop })
    }
}

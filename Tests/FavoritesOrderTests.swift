// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich
import XCTest
@testable import Publit

/// Saved stops, places and lines in an order of your own (#124).
@MainActor
final class FavoritesOrderTests: XCTestCase {
    private func suite() -> String { "publit-order-tests-\(UUID().uuidString)" }

    private func stop(_ id: String) -> SavedPlace {
        SavedPlace(id: id, name: "Stop \(id)", subtitle: nil, lat: 48, lon: 16, stopId: id)
    }

    private func place(_ id: String, lat: Double) -> SavedPlace {
        SavedPlace(id: id, name: "Place \(id)", subtitle: nil, lat: lat, lon: 16, stopId: nil)
    }

    func testMovedWorksLikeAListDrag() async {
        let all = ["a", "b", "c", "d"]
        func moved(_ from: [Int], _ to: Int) -> [String] {
            FavoritesStore.moved(all, fromOffsets: IndexSet(from), toOffset: to) { _ in true }
        }
        XCTAssertEqual(moved([0], 4), ["b", "c", "d", "a"])   // first to the end
        XCTAssertEqual(moved([3], 0), ["d", "a", "b", "c"])   // last to the top
        XCTAssertEqual(moved([1], 3), ["a", "c", "b", "d"])   // one down
        XCTAssertEqual(moved([2], 1), ["a", "c", "b", "d"])   // one up
        XCTAssertEqual(moved([0, 2], 4), ["b", "d", "a", "c"])
        XCTAssertEqual(moved([1], 1), all)                    // dropped where it was
        XCTAssertEqual(moved([1], 2), all)
        XCTAssertEqual(moved([9], 0), all)                    // nothing there
        XCTAssertEqual(moved([0], 9), all)
    }

    func testOnlyTheMovedKindChangesItsOrder() async {
        // Stops (upper case) and places share one stored list.
        let all = ["A", "x", "B", "y", "C"]
        let stops = FavoritesStore.moved(all, fromOffsets: IndexSet([2]), toOffset: 0) { $0 == $0.uppercased() }
        XCTAssertEqual(stops, ["C", "x", "A", "y", "B"])
        let places = FavoritesStore.moved(all, fromOffsets: IndexSet([0]), toOffset: 2) { $0 != $0.uppercased() }
        XCTAssertEqual(places, ["A", "y", "B", "x", "C"])
    }

    func testTheOrderOfStopsSurvivesSavingAndLoading() async {
        let name = suite()
        let s = FavoritesStore(defaults: UserDefaults(suiteName: name)!)
        s.set(place("home", lat: 48.1), as: .home)
        for id in ["1", "2", "3"] { s.toggle(stop(id)) }
        s.toggle(place("p", lat: 48.5))
        s.moveStops(fromOffsets: IndexSet([2]), toOffset: 0)   // the newest stop to the top
        XCTAssertEqual(s.stops.map(\.id), ["3", "1", "2"])
        XCTAssertEqual(s.places.map(\.id), ["p"])
        XCTAssertEqual(s.place(for: .home)?.id, "home")
        let again = FavoritesStore(defaults: UserDefaults(suiteName: name)!)
        XCTAssertEqual(again.stops.map(\.id), ["3", "1", "2"])
        XCTAssertEqual(again.items.count, 5)
        // A stop saved later still goes to the end.
        again.toggle(stop("4"))
        XCTAssertEqual(again.stops.map(\.id), ["3", "1", "2", "4"])
    }

    func testPlacesMoveWithoutTouchingStops() async {
        let s = FavoritesStore(defaults: UserDefaults(suiteName: suite())!)
        s.toggle(stop("1"))
        s.toggle(place("a", lat: 48.1))
        s.toggle(stop("2"))
        s.toggle(place("b", lat: 48.2))
        s.movePlaces(fromOffsets: IndexSet([1]), toOffset: 0)
        XCTAssertEqual(s.places.map(\.id), ["b", "a"])
        XCTAssertEqual(s.stops.map(\.id), ["1", "2"])
    }
}

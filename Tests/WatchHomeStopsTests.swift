// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich
import XCTest
@testable import Publit

/// Saved stops on the watch's first screen, one tap from their departures (#123).
final class WatchHomeStopsTests: XCTestCase {
    private func stop(_ id: String) -> SavedPlace {
        SavedPlace(id: id, name: "Stop \(id)", subtitle: nil, lat: 48, lon: 16, stopId: id)
    }

    private func place(_ id: String, role: PlaceRole? = nil) -> SavedPlace {
        var p = SavedPlace(id: id, name: "Place \(id)", subtitle: nil, lat: 48.5, lon: 16, stopId: nil)
        p.role = role
        return p
    }

    func testOnlyStopsInTheSavedOrder() {
        // Home, a place and stops share one list; the order is the one set on the iPhone.
        let snap = WatchSnapshot(sentAt: .now, places: [place("h", role: .home), stop("3"), place("p"), stop("1"), stop("2")])
        XCTAssertEqual(snap.homeStops.map(\.id), ["3", "1", "2"])
    }

    func testAStopSetAsHomeOrWorkIsNotListedTwice() {
        var station = stop("hbf")
        station.role = .work
        let snap = WatchSnapshot(sentAt: .now, places: [station, stop("1")])
        XCTAssertEqual(snap.homeStops.map(\.id), ["1"], "Work is under Saved and in Where to?, not among the stops")
    }

    func testTheFirstScreenStaysShort() {
        let snap = WatchSnapshot(sentAt: .now, places: (1...9).map { stop("\($0)") })
        XCTAssertEqual(snap.homeStops.map(\.id), ["1", "2", "3", "4"])
        XCTAssertEqual(snap.homeStops.count, WatchSnapshot.homeStopLimit)
        XCTAssertEqual(snap.stops.count, 9, "all of them stay under Saved")
    }

    func testNoStopsNoRows() {
        XCTAssertTrue(WatchSnapshot(sentAt: .now, places: [place("p")]).homeStops.isEmpty)
        XCTAssertTrue(WatchSnapshot.empty.homeStops.isEmpty)
    }
}

// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich

import XCTest
@testable import Publit

/// Wish #4 "Real time transit for Lisbon Area": live times from Carris Metropolitana.
final class LisbonLiveTests: XCTestCase {
    private let t0 = 1_795_863_600.0   // 2026-11-28 11:00 Lisbon (UTC)

    private func date(_ m: Double) -> Date { Date(timeIntervalSince1970: t0 + m * 60) }

    private func ride(stop: String?, trip: String? = nil, line: String = "4701", headsign: String? = "Lisboa (Oriente)",
                      at m: Double = 0) -> LiveRide {
        LiveRide(point: LatLon(lat: 38.768, lon: -9.1), stopId: stop, stopName: "Gare do Oriente", lines: [line],
                 headsign: headsign, scheduled: date(m), mode: "BUS", tripId: trip)
    }

    private let board = """
    [{"line_id":"[A2L1N]4701","headsign":"Vale da Amoreira","scheduled_arrival_unix":1795863600,
      "estimated_arrival_unix":1795863221,"trip_id":"[FBZQZ][A2L1N]4701_0_1|2800|1100"},
     {"line_id":"[A2L1N]4701","headsign":"Lisboa (Oriente)","scheduled_arrival_unix":1795863600,
      "estimated_arrival_unix":1795863576,"trip_id":"[FBZQZ][A2L1N]4701_0_2|2800|1010"},
     {"line_id":"[A2L1N]4701","headsign":"Lisboa (Oriente)","scheduled_arrival_unix":1795864800,
      "estimated_arrival_unix":null,"trip_id":null},
     {"headsign":"no line"}]
    """

    func testCoversOnlyCarrisMetropolitanaStops() {
        let source = CarrisMetropolitanaSource()
        XCTAssertTrue(source.covers(ride(stop: "pt-Carris-Metropolitana_060001")))
        XCTAssertFalse(source.covers(ride(stop: "pt-Carris_7817")))
        XCTAssertFalse(source.covers(ride(stop: nil)))
        XCTAssertTrue(source.onlyWithoutLive)
    }

    func testStopIdsTryTheLeadingZeroSpelling() {
        XCTAssertEqual(CarrisMetropolitanaSource.stopIds("pt-Carris-Metropolitana_160061"), ["160061"])
        XCTAssertEqual(CarrisMetropolitanaSource.stopIds("pt-Carris-Metropolitana_360322"), ["360322", "060322"])
        XCTAssertEqual(CarrisMetropolitanaSource.stopIds("pt-Carris-Metropolitana_abc"), [])
        XCTAssertEqual(CarrisMetropolitanaSource.stopIds("pt-Carris_7817"), [])
    }

    func testTripKeyIsTheOperatorsTripId() {
        XCTAssertEqual(CarrisMetropolitanaSource.tripKey("20261128_11:00_pt-Carris-Metropolitana_[FBZQZ][A2L1N]4701_0_1|2800|1100"),
                       "[FBZQZ][A2L1N]4701_0_1|2800|1100")
        XCTAssertNil(CarrisMetropolitanaSource.tripKey("20261128_11:00_pt-CP_123"))
        XCTAssertNil(CarrisMetropolitanaSource.tripKey(nil))
    }

    func testParsesArrivals() throws {
        let list = CarrisMetropolitanaSource.parseArrivals(try JSONSerialization.jsonObject(with: Data(board.utf8)))
        XCTAssertEqual(list.count, 3)
        XCTAssertEqual(list[0].departure.lines, ["4701"])
        XCTAssertEqual(list[0].departure.destination, "Vale da Amoreira")
        XCTAssertEqual(list[0].departure.scheduled, date(0))
        XCTAssertEqual(list[0].departure.expected, Date(timeIntervalSince1970: 1_795_863_221))
        XCTAssertNil(list[2].departure.expected)
        XCTAssertNil(list[2].trip)
        XCTAssertEqual(CarrisMetropolitanaSource.line("[A2L1N]4701"), "4701")
        XCTAssertEqual(CarrisMetropolitanaSource.line("4701"), "4701")
    }

    /// Both directions are due at 11:00: the headsign picks the one going the ride's way.
    func testLineAndDirectionMatchWithoutTrip() throws {
        let deps = CarrisMetropolitanaSource.parseArrivals(try JSONSerialization.jsonObject(with: Data(board.utf8))).map(\.departure)
        let hit = LiveMatch.best(for: ride(stop: "pt-Carris-Metropolitana_060001"), in: deps)
        XCTAssertEqual(hit?.destination, "Lisboa (Oriente)")
        XCTAssertEqual(hit?.expected, Date(timeIntervalSince1970: 1_795_863_576))
    }

    func testRideCarriesTheTripId() throws {
        let json = """
        {"mode":"BUS","from":{"name":"A","lat":38.768,"lon":-9.1,"stopId":"pt-Carris-Metropolitana_060001"},
         "to":{"name":"B","lat":38.7,"lon":-9.0},"duration":600,"startTime":"2026-11-28T11:00:00Z","endTime":"2026-11-28T11:10:00Z",
         "scheduledStartTime":"2026-11-28T11:00:00Z","scheduledEndTime":"2026-11-28T11:10:00Z","realTime":false,
         "routeShortName":"4701","tripId":"20261128_11:00_pt-Carris-Metropolitana_X","legGeometry":{"points":"","precision":6,"length":0}}
        """
        let leg = try TransitousClient.makeDecoder().decode(Leg.self, from: Data(json.utf8))
        XCTAssertEqual(LiveOverlay.ride(leg).tripId, "20261128_11:00_pt-Carris-Metropolitana_X")
        XCTAssertTrue(LiveOverlay.sourceNames.contains("Carris Metropolitana"))
    }
}

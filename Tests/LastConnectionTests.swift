// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich

import XCTest
@testable import Publit

/// "Last connection": tonight's last route there, asked as "arrive by 4 a.m.".
final class LastConnectionTests: XCTestCase {
    private var vienna: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Vienna")!
        return c
    }

    private func local(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        vienna.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func ride(_ id: String, start: Date, end: Date, cancelled: Bool = false) throws -> Itinerary {
        let json = """
        {"mode":"BUS","from":{"name":"A","lat":48,"lon":16},"to":{"name":"B","lat":48,"lon":16},
         "duration":\(Int(end.timeIntervalSince(start))),"startTime":"\(DateParsing.format(start))","endTime":"\(DateParsing.format(end))",
         "scheduledStartTime":"\(DateParsing.format(start))","scheduledEndTime":"\(DateParsing.format(end))",
         "realTime":false,"cancelled":\(cancelled),"tripId":"t-\(id)","legGeometry":{"points":"","precision":6,"length":0}}
        """
        let leg = try TransitousClient.makeDecoder().decode(Leg.self, from: Data(json.utf8))
        return Itinerary(id: id, duration: leg.duration, startTime: start, endTime: end, transfers: 0, legs: [leg])
    }

    func testDeadlineIsFourInTheMorningAfterTheDay() {
        // Evening: the night that follows.
        XCTAssertEqual(LastConnection.deadline(for: local(23, 18), calendar: vienna), local(24, 4))
        XCTAssertEqual(LastConnection.deadline(for: local(23, 4), calendar: vienna), local(24, 4))
        // After midnight it is still last night's service.
        XCTAssertEqual(LastConnection.deadline(for: local(24, 1, 30), calendar: vienna), local(24, 4))
    }

    func testSameServiceDaySearchesOnce() {
        XCTAssertEqual(LastConnection.dayKey(for: local(23, 9), calendar: vienna),
                       LastConnection.dayKey(for: local(24, 2), calendar: vienna))
        XCTAssertNotEqual(LastConnection.dayKey(for: local(23, 9), calendar: vienna),
                          LastConnection.dayKey(for: local(24, 9), calendar: vienna))
    }

    func testLastIsTheRouteThatLeavesLatest() throws {
        let early = try ride("early", start: local(23, 22, 30), end: local(23, 23, 40))
        let night = try ride("night", start: local(24, 0, 5), end: local(24, 2, 57))
        let gone = try ride("gone", start: local(24, 0, 40), end: local(24, 3, 10), cancelled: true)
        XCTAssertEqual(LastConnection.last([night, gone, early])?.id, "night")
    }

    func testDepartedRoutesAreDroppedAndTheRestInDepartureOrder() throws {
        let a = try ride("a", start: local(23, 22, 0), end: local(23, 23, 0))
        let b = try ride("b", start: local(23, 23, 30), end: local(24, 0, 30))
        let c = try ride("c", start: local(23, 23, 0), end: local(24, 1, 0))
        XCTAssertEqual(LastConnection.upcoming([b, a, c], now: local(23, 22, 30)).map(\.id), ["c", "b"])
        XCTAssertTrue(LastConnection.upcoming([a], now: local(23, 22, 30)).isEmpty)
    }

    func testLastModeSearchesBackwards() {
        XCTAssertTrue(TimeMode.lastConnection.searchesBackwards)
        XCTAssertTrue(TimeMode.arriveBy.searchesBackwards)
        XCTAssertFalse(TimeMode.departAt.searchesBackwards)
    }

    func testBadgeIsTranslated() {
        XCTAssertEqual(SmartRouting.Badge.lastConnection.symbol, "moon.stars")
        XCTAssertFalse(SmartRouting.Badge.lastConnection.title.isEmpty)
    }
}

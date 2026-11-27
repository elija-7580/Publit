// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich
import XCTest
@testable import Publit

/// Late trains stay in a "now" search (feedback 27 Nov 2026: shown on time, then gone).
final class LateTrainsTests: XCTestCase {
    private let t0 = 1_791_360_000.0   // Wednesday 7 Oct 2026, 10:00 in Vienna

    private func time(_ minutes: Int) -> Date { Date(timeIntervalSince1970: t0 + Double(minutes) * 60) }

    private func leg(_ mode: String, _ from: Int, _ to: Int, start: Int, end: Int, delay: Int = 0, source: String? = nil) throws -> Leg {
        func iso(_ m: Int) -> String { DateParsing.format(time(m)) }
        func place(_ n: Int) -> String { "{\"name\":\"S\(n)\",\"stopId\":\"s\(n)\",\"lat\":\(48 + Double(n) * 0.01),\"lon\":16}" }
        let ride = mode == "WALK" ? "" : ",\"tripId\":\"\(mode)-\(from)-\(start)\""
        let json = """
        {"mode":"\(mode)","from":\(place(from)),"to":\(place(to)),"duration":\((end - start) * 60),
         "startTime":"\(iso(start + delay))","endTime":"\(iso(end + delay))",
         "scheduledStartTime":"\(iso(start))","scheduledEndTime":"\(iso(end))","realTime":\(delay != 0)\(ride),
         "legGeometry":{"points":"","precision":6,"length":0}}
        """
        var l = try TransitousClient.makeDecoder().decode(Leg.self, from: Data(json.utf8))
        l.liveSource = source
        return l
    }

    private func route(_ id: String, _ legs: [Leg]) -> Itinerary {
        Itinerary(id: id, duration: Int(legs[legs.count - 1].endTime.timeIntervalSince(legs[0].startTime)),
                  startTime: legs[0].startTime, endTime: legs[legs.count - 1].endTime, transfers: 0, legs: legs)
    }

    /// Train due at 0, 8 min late (ÖBB).
    private func late(id: String = "L") throws -> Itinerary {
        route(id, [try leg("REGIONAL_RAIL", 1, 2, start: 0, end: 30, delay: 8, source: "ÖBB")])
    }

    func testARefreshKeepsTheDelayUntilLiveTimesComeAgain() throws {
        let onScreen = try late()
        let fresh = route("F", [try leg("REGIONAL_RAIL", 1, 2, start: 0, end: 30)])
        let kept = LateTrains.carry([fresh], previous: [onScreen], now: time(-2))
        XCTAssertEqual(kept.count, 1)
        XCTAssertEqual(kept[0].startTime, time(8))
    }

    func testALateTrainTheServerDropsStaysUntilItLeaves() throws {
        let onScreen = try late()
        let next = route("N", [try leg("REGIONAL_RAIL", 1, 2, start: 30, end: 60)])
        let kept = LateTrains.carry([next], previous: [onScreen], now: time(3))
        XCTAssertEqual(kept.map(\.id), ["N", "L"])
        XCTAssertEqual(LateTrains.carry([next], previous: [onScreen], now: time(9)).map(\.id), ["N"])
        // On time, it is not kept once the server drops it.
        let onTime = route("O", [try leg("REGIONAL_RAIL", 1, 2, start: 0, end: 30, source: "ÖBB")])
        XCTAssertEqual(LateTrains.carry([next], previous: [onTime], now: time(3)).map(\.id), ["N"])
    }

    func testAnEarlierSearchFindsTheLateTrainsStillToCatch() throws {
        let base = time(3)
        let found = [try late(id: "late"),
                     route("gone", [try leg("REGIONAL_RAIL", 1, 2, start: -10, end: 20, delay: 2, source: "ÖBB")]),
                     route("listed", [try leg("REGIONAL_RAIL", 1, 2, start: 5, end: 35)])]
        let candidates = LateTrains.candidates(found, base: base, known: [])
        XCTAssertEqual(candidates.map(\.id), ["late", "gone"])
        let reachable = LateTrains.stillReachable(found, base: base, now: base, known: [])
        XCTAssertEqual(reachable.map(\.id), ["late"])
        XCTAssertTrue(LateTrains.stillReachable(found, base: base, now: base, known: [found[0].rideKey]).isEmpty)
    }

    /// "Earlier connections" loaded by hand stay above the routes when the list refreshes live.
    func testEarlierConnectionsStayOnARefresh() throws {
        func train(_ id: String, _ start: Int) throws -> Itinerary { route(id, [try leg("REGIONAL_RAIL", 1, 2, start: start, end: start + 30)]) }
        let earlier = [try train("E1", -20), try train("E2", -10)]
        let fresh = [try train("A", 0), try train("B", 10)]
        let kept = PlanModel.keepingEarlier(fresh, previous: earlier + fresh)
        XCTAssertEqual(kept.map(\.id), ["E1", "E2", "A", "B"])
        // Nothing earlier on screen: the refresh is as it was.
        XCTAssertEqual(PlanModel.keepingEarlier(fresh, previous: fresh).map(\.id), ["A", "B"])
    }
}

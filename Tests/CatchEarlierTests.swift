// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich
import XCTest
@testable import Publit

/// A late feeder breaks a change before the trip starts: an earlier way still catches the same
/// connection (feedback 27 Nov 2026: U1 → U4 → REX to Krems, the U4 late at Heiligenstadt).
final class CatchEarlierTests: XCTestCase {
    private let t0 = 1_791_360_000.0   // Wednesday 7 Oct 2026, 10:00 in Vienna

    private func time(_ minutes: Int) -> Date { Date(timeIntervalSince1970: t0 + Double(minutes) * 60) }

    /// Stops lie on a line, 0.01° of latitude (about 1.1 km) apart, by the number in their name.
    private func leg(_ mode: String, _ from: Int, _ to: Int, start: Int, end: Int, delay: Int = 0) throws -> Leg {
        func iso(_ m: Int) -> String { DateParsing.format(time(m)) }
        func place(_ n: Int) -> String { "{\"name\":\"S\(n)\",\"stopId\":\"s\(n)\",\"lat\":\(48 + Double(n) * 0.01),\"lon\":16}" }
        let ride = mode == "WALK" ? "" : ",\"tripId\":\"\(mode)-\(from)-\(start)\""
        let json = """
        {"mode":"\(mode)","from":\(place(from)),"to":\(place(to)),"duration":\((end - start) * 60),
         "startTime":"\(iso(start + delay))","endTime":"\(iso(end + delay))",
         "scheduledStartTime":"\(iso(start))","scheduledEndTime":"\(iso(end))","realTime":\(delay != 0)\(ride),
         "legGeometry":{"points":"","precision":6,"length":0}}
        """
        return try TransitousClient.makeDecoder().decode(Leg.self, from: Data(json.utf8))
    }

    private func route(_ id: String, _ legs: [Leg]) -> Itinerary {
        let rides = legs.filter(\.isTransit).count
        return Itinerary(id: id, duration: Int(legs[legs.count - 1].endTime.timeIntervalSince(legs[0].startTime)),
                         startTime: legs[0].startTime, endTime: legs[legs.count - 1].endTime,
                         transfers: max(0, rides - 1), legs: legs)
    }

    private func changes(_ it: Itinerary, at now: Date) -> [SmartRouting.Change] {
        SmartRouting.changes(it, at: now, history: { _ in nil }, walkModel: .prior, extraSeconds: 0, learned: nil)
    }

    /// Walk to S1, subway to S2 (6 min late), train from S2 at 18 to S3.
    private func broken() throws -> Itinerary {
        route("A", [try leg("WALK", 0, 1, start: 0, end: 4), try leg("SUBWAY", 1, 2, start: 5, end: 15, delay: 6),
                    try leg("REGIONAL_RAIL", 2, 3, start: 18, end: 50)])
    }

    /// A way from S0 to S2: walk, then subway.
    private func way(_ id: String, leaving start: Int, arriving end: Int) throws -> Itinerary {
        route(id, [try leg("WALK", 0, 1, start: start, end: start + 4), try leg("SUBWAY", 1, 2, start: start + 5, end: end)])
    }

    func testABrokenChangeAheadIsTheTarget() throws {
        let a = try broken()
        let now = time(-20)
        let target = try XCTUnwrap(CatchEarlier.target(a, changes: changes(a, at: now), at: now))
        XCTAssertEqual(target.outgoingIndex, 2)
        XCTAssertEqual(target.stopName, "S2")
        XCTAssertEqual(target.latestArrival, time(16))
        // Already under way: too late to leave earlier.
        XCTAssertNil(CatchEarlier.target(a, changes: changes(a, at: time(1)), at: time(1)))
    }

    func testNoTargetWhileEveryChangeHolds() throws {
        let fine = route("B", [try leg("WALK", 0, 1, start: 0, end: 4), try leg("SUBWAY", 1, 2, start: 5, end: 10),
                               try leg("REGIONAL_RAIL", 2, 3, start: 18, end: 50)])
        XCTAssertNil(CatchEarlier.target(fine, changes: changes(fine, at: time(-20)), at: time(-20)))
    }

    func testAWayThereLeadsIntoTheSameConnection() throws {
        let a = try broken()
        let w = try way("W", leaving: -2, arriving: 13)
        let joined = try XCTUnwrap(RouteBuilder.lead(w, into: a, at: 2))
        XCTAssertEqual(joined.legs.map(\.mode), ["WALK", "SUBWAY", "REGIONAL_RAIL"])
        XCTAssertEqual(joined.startTime, time(-2))
        XCTAssertEqual(joined.endTime, a.endTime)
        XCTAssertEqual(joined.builtFrom, [RoutePart(itineraryId: "W", firstLeg: 0, legCount: 2),
                                          RoutePart(itineraryId: "A", firstLeg: 2, legCount: 1)])
        // Arriving after the train leaves does not fit.
        XCTAssertNil(RouteBuilder.lead(try way("L", leaving: 5, arriving: 19), into: a, at: 2))
        XCTAssertNil(RouteBuilder.lead(w, into: a, at: 0))
    }

    func testTheLatestSafeWayIsPicked() throws {
        let a = try broken()
        let now = time(-20)
        let target = try XCTUnwrap(CatchEarlier.target(a, changes: changes(a, at: now), at: now))
        let ways = [try way("gone", leaving: -25, arriving: -10),   // left already
                    try way("early", leaving: -10, arriving: 5),
                    try way("good", leaving: -2, arriving: 13),
                    try way("tight", leaving: 3, arriving: 18)]     // no time to change
        let picked = try XCTUnwrap(CatchEarlier.pick(ways, for: a, target: target, at: now) { self.changes($0, at: now) })
        XCTAssertEqual(picked.builtFrom?.first?.itineraryId, "good")
        XCTAssertEqual(CatchEarlier.minutesEarlier(picked, than: a), 2)
        XCTAssertNil(CatchEarlier.pick([ways[0]], for: a, target: target, at: now) { self.changes($0, at: now) })
    }
}

// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich
import XCTest
@testable import Publit

/// Build your own connection (#91, part 1 #141): cut a route at a leg and plan the rest again.
final class RouteBuilderTests: XCTestCase {
    private let t0 = 1_791_360_000.0   // Wednesday 7 Oct 2026, 10:00 in Vienna

    private func time(_ minutes: Int) -> Date { Date(timeIntervalSince1970: t0 + Double(minutes) * 60) }

    /// Stops lie on a line, 0.01° of latitude (about 1.1 km) apart, by the number in their name.
    private func leg(_ mode: String, _ from: Int, _ to: Int, start: Int, end: Int, delay: Int = 0,
                     trip: String? = nil, interlined: Bool = false) throws -> Leg {
        func iso(_ m: Int) -> String { DateParsing.format(time(m)) }
        func place(_ n: Int) -> String { "{\"name\":\"S\(n)\",\"stopId\":\"s\(n)\",\"lat\":\(48 + Double(n) * 0.01),\"lon\":16}" }
        let ride = mode == "WALK" ? "" : ",\"tripId\":\"\(trip ?? "\(mode)-\(from)-\(start)")\""
        let json = """
        {"mode":"\(mode)","from":\(place(from)),"to":\(place(to)),"duration":\((end - start) * 60),
         "startTime":"\(iso(start + delay))","endTime":"\(iso(end + delay))",
         "scheduledStartTime":"\(iso(start))","scheduledEndTime":"\(iso(end))","realTime":\(delay != 0),
         "interlineWithPreviousLeg":\(interlined)\(ride),"legGeometry":{"points":"","precision":6,"length":0}}
        """
        return try TransitousClient.makeDecoder().decode(Leg.self, from: Data(json.utf8))
    }

    private func route(_ id: String, _ legs: [Leg]) -> Itinerary {
        let rides = legs.filter(\.isTransit).count
        return Itinerary(id: id, duration: Int(legs[legs.count - 1].endTime.timeIntervalSince(legs[0].startTime)),
                         startTime: legs[0].startTime, endTime: legs[legs.count - 1].endTime,
                         transfers: max(0, rides - 1), legs: legs)
    }

    /// Walk to S1, bus to S2, tram to S3, walk to S4.
    private func planned() throws -> Itinerary {
        route("A", [try leg("WALK", 0, 1, start: 0, end: 5), try leg("BUS", 1, 2, start: 6, end: 16),
                    try leg("TRAM", 2, 3, start: 20, end: 30), try leg("WALK", 3, 4, start: 30, end: 34)])
    }

    func testRestartIsWhereTheLegStartsAndNotBeforeTheKeptLegsArrive() throws {
        let a = try planned()
        let cut = try XCTUnwrap(RouteBuilder.restart(a, at: 2))
        XCTAssertEqual(cut.from.name, "S2")
        XCTAssertEqual(cut.to.name, "S4")
        XCTAssertEqual(cut.earliest, time(16))
        let whole = try XCTUnwrap(RouteBuilder.restart(a, at: 0))
        XCTAssertEqual(whole.from.name, "S0")
        XCTAssertEqual(whole.earliest, a.startTime)
        XCTAssertNil(RouteBuilder.restart(a, at: 4))
        XCTAssertNil(RouteBuilder.restart(a, at: -1))
    }

    func testKeptLegsAndANewRestBecomeOneRoute() throws {
        let a = try planned()
        // From S2 a later subway straight to S4.
        let b = route("B", [try leg("SUBWAY", 2, 4, start: 25, end: 33)])
        let built = try XCTUnwrap(RouteBuilder.splice(a, at: 2, with: b))
        XCTAssertEqual(built.legs.map(\.mode), ["WALK", "BUS", "SUBWAY"])
        XCTAssertEqual(built.startTime, time(0))
        XCTAssertEqual(built.endTime, time(33))
        XCTAssertEqual(built.duration, 33 * 60)
        XCTAssertEqual(built.transfers, 1)
        XCTAssertEqual(built.builtFrom, [RoutePart(itineraryId: "A", firstLeg: 0, legCount: 2),
                                         RoutePart(itineraryId: "B", firstLeg: 0, legCount: 1)])
        XCTAssertNotEqual(built.id, a.id)
        XCTAssertNil(RouteBuilder.firstBrokenLeg(in: built))
        XCTAssertNil(a.builtFrom, "a planned route is not marked as built")
    }

    func testARestThatLeavesTooEarlyOrStartsElsewhereIsRefused() throws {
        let a = try planned()
        let early = route("B", [try leg("SUBWAY", 2, 4, start: 15, end: 23)])   // the bus arrives at :16
        XCTAssertNil(RouteBuilder.splice(a, at: 2, with: early))
        let elsewhere = route("C", [try leg("SUBWAY", 3, 4, start: 25, end: 30)])   // starts 1.1 km away
        XCTAssertNil(RouteBuilder.splice(a, at: 2, with: elsewhere))
        XCTAssertNil(RouteBuilder.splice(a, at: 9, with: early))
        // Leaving the moment the kept legs arrive is fine (the search already adds the change time).
        let tight = route("D", [try leg("SUBWAY", 2, 4, start: 16, end: 24)])
        XCTAssertNotNil(RouteBuilder.splice(a, at: 2, with: tight))
    }

    func testCuttingAtTheFirstLegTakesTheWholeNewRoute() throws {
        let a = try planned()
        let b = route("B", [try leg("WALK", 0, 1, start: 10, end: 15), try leg("BUS", 1, 4, start: 16, end: 40)])
        let built = try XCTUnwrap(RouteBuilder.splice(a, at: 0, with: b))
        XCTAssertEqual(built.legs.count, 2)
        XCTAssertEqual(built.startTime, time(10))
        XCTAssertEqual(built.transfers, 0)
        XCTAssertEqual(built.builtFrom, [RoutePart(itineraryId: "B", firstLeg: 0, legCount: 2)])
    }

    func testABuiltRouteCanBeCutAgain() throws {
        let a = try planned()
        let b = route("B", [try leg("SUBWAY", 2, 3, start: 25, end: 29), try leg("BUS", 3, 4, start: 32, end: 36)])
        let once = try XCTUnwrap(RouteBuilder.splice(a, at: 2, with: b))
        let c = route("C", [try leg("WALK", 3, 4, start: 29, end: 40)])
        let twice = try XCTUnwrap(RouteBuilder.splice(once, at: 3, with: c))
        XCTAssertEqual(twice.legs.map(\.mode), ["WALK", "BUS", "SUBWAY", "WALK"])
        XCTAssertEqual(twice.transfers, 1)
        XCTAssertEqual(twice.builtFrom, [RoutePart(itineraryId: "A", firstLeg: 0, legCount: 2),
                                         RoutePart(itineraryId: "B", firstLeg: 0, legCount: 1),
                                         RoutePart(itineraryId: "C", firstLeg: 0, legCount: 1)])
    }

    func testTheSameVehicleRunningOnIsNoChange() throws {
        let a = route("A", [try leg("BUS", 0, 1, start: 0, end: 10)])
        let b = route("B", [try leg("RAIL", 1, 2, start: 15, end: 30), try leg("RAIL", 2, 3, start: 30, end: 50, interlined: true)])
        let built = try XCTUnwrap(RouteBuilder.splice(route("X", a.legs + [try leg("TRAM", 1, 3, start: 12, end: 40)]), at: 1, with: b))
        XCTAssertEqual(built.transfers, 1)
    }

    func testLiveTimesAreRefreshedPartByPart() throws {
        let a = try planned()
        let b = route("B", [try leg("SUBWAY", 2, 4, start: 25, end: 33)])
        let built = try XCTUnwrap(RouteBuilder.splice(a, at: 2, with: b))
        // The bus now runs 4 minutes late; the server hands out new IDs with the new times.
        let lateA = route("A2", [try leg("WALK", 0, 1, start: 0, end: 5), try leg("BUS", 1, 2, start: 6, end: 16, delay: 4),
                                 try leg("TRAM", 2, 3, start: 20, end: 30), try leg("WALK", 3, 4, start: 30, end: 34)])
        let sameB = route("B2", b.legs)
        let fresh = try XCTUnwrap(RouteBuilder.refreshed(built, with: ["A": lateA, "B": sameB]))
        XCTAssertEqual(fresh.legs[1].endTime, time(20))
        XCTAssertEqual(fresh.endTime, time(33))
        XCTAssertEqual(fresh.builtFrom?.map(\.itineraryId), ["A2", "B2"])
        XCTAssertEqual(fresh.id, built.id, "the same rides keep their identity across refreshes")
        XCTAssertNil(RouteBuilder.firstBrokenLeg(in: fresh))
        // 10 minutes late: the subway at :25 is gone.
        let veryLate = route("A3", [lateA.legs[0], try leg("BUS", 1, 2, start: 6, end: 16, delay: 10), lateA.legs[2], lateA.legs[3]])
        let broken = try XCTUnwrap(RouteBuilder.refreshed(built, with: ["A": veryLate, "B": sameB]))
        XCTAssertEqual(RouteBuilder.firstBrokenLeg(in: broken), 2)
    }

    func testARefreshWithAMissingOrDifferentPartKeepsWhatThereIs() throws {
        let a = try planned()
        let b = route("B", [try leg("SUBWAY", 2, 4, start: 25, end: 33)])
        let built = try XCTUnwrap(RouteBuilder.splice(a, at: 2, with: b))
        XCTAssertNil(RouteBuilder.refreshed(built, with: ["A": a]))
        let other = route("B9", [try leg("SUBWAY", 2, 4, start: 35, end: 43)])   // another train
        XCTAssertNil(RouteBuilder.refreshed(built, with: ["A": a, "B": other]))
        let short = route("A9", [a.legs[0]])
        XCTAssertNil(RouteBuilder.refreshed(built, with: ["A": short, "B": b]))
        XCTAssertNil(RouteBuilder.refreshed(a, with: ["A": a]), "a planned route is refreshed by its own ID")
    }

    func testABuiltRouteSurvivesSavingAndOldRoutesLoadWithoutParts() throws {
        let a = try planned()
        let b = route("B", [try leg("SUBWAY", 2, 4, start: 25, end: 33)])
        let built = try XCTUnwrap(RouteBuilder.splice(a, at: 2, with: b))
        let data = try JSONEncoder().encode(built)
        let back = try JSONDecoder().decode(Itinerary.self, from: data)
        XCTAssertEqual(back.builtFrom, built.builtFrom)
        XCTAssertEqual(back.legs.count, 3)
        // A route as saved before this field existed.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(a)) as? [String: Any])
        json.removeValue(forKey: "builtFrom")
        let old = try JSONDecoder().decode(Itinerary.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(old.builtFrom)
        XCTAssertEqual(old.legs.count, 4)
    }

    // MARK: Part 2 (#142): change one leg

    func testChoicesKeepTheLegsBeforeAndLeaveOutWhatCannotBeReached() throws {
        let a = try planned()
        let same = route("A2", [try leg("TRAM", 2, 3, start: 20, end: 30), try leg("WALK", 3, 4, start: 30, end: 34)])
        let later = route("B", [try leg("SUBWAY", 2, 4, start: 25, end: 33)])
        let again = route("B2", [try leg("SUBWAY", 2, 4, start: 25, end: 33)])   // the same ride, found twice
        let tooEarly = route("C", [try leg("SUBWAY", 2, 4, start: 15, end: 23)])
        let choices = RouteBuilder.choices(for: a, at: 2, from: [same, later, again, tooEarly])
        XCTAssertEqual(choices.map { $0.legs.map(\.mode) }, [["WALK", "BUS", "SUBWAY"], ["WALK", "BUS", "TRAM", "WALK"]])
        XCTAssertEqual(choices.map(\.endTime), [time(33), time(34)])
        XCTAssertTrue(choices.allSatisfy { $0.legs.prefix(2).map(\.tripId) == a.legs.prefix(2).map(\.tripId) })
        XCTAssertEqual(choices[1].routeKey, a.routeKey, "the route as it is stays recognisable")
    }

    func testABuiltRouteIsRefreshedThroughEachOfItsParts() async throws {
        let a = try planned()
        let b = route("B", [try leg("SUBWAY", 2, 4, start: 25, end: 33)])
        let built = try XCTUnwrap(RouteBuilder.splice(a, at: 2, with: b))
        XCTAssertEqual(RouteBuilder.refreshIds(of: built), ["A", "B"])
        XCTAssertEqual(RouteBuilder.refreshIds(of: a), ["A"])

        let lateBus = route("A'", [try leg("WALK", 0, 1, start: 0, end: 5), try leg("BUS", 1, 2, start: 6, end: 16, delay: 2),
                                   try leg("TRAM", 2, 3, start: 20, end: 30), try leg("WALK", 3, 4, start: 30, end: 34)])
        let coordinator = TripRefreshCoordinator { id in
            switch id {
            case "A": return lateBus
            case "B": return b
            default: throw URLError(.badURL)
            }
        }
        let fresh = try await coordinator.refresh(route: built)
        XCTAssertEqual(fresh.legs[1].endTime, time(18))
        XCTAssertEqual(fresh.legs.map(\.mode), ["WALK", "BUS", "SUBWAY"])
        XCTAssertEqual(fresh.builtFrom?.map(\.itineraryId), ["A'", "B"])
        // A planned route goes the usual way.
        let plain = try await coordinator.refresh(route: a)
        XCTAssertEqual(plain.id, "A'")
    }
}

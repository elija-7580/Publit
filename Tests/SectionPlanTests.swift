// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich
import XCTest
@testable import Publit

/// Build your own connection, part 5 (#144): a journey laid out section by section.
final class SectionPlanTests: XCTestCase {
    private static let t0 = 1_791_360_000.0   // Wednesday 7 Oct 2026, 10:00 in Vienna

    private static func time(_ minutes: Int) -> Date { Date(timeIntervalSince1970: t0 + Double(minutes) * 60) }
    private func time(_ minutes: Int) -> Date { Self.time(minutes) }

    /// Stops lie on a line, 0.01° of latitude apart, by their number.
    private static func coordinate(_ n: Int) -> LatLon { LatLon(lat: 48 + Double(n) * 0.01, lon: 16) }

    private static func leg(_ mode: String, _ from: Int, _ to: Int, start: Int, end: Int) throws -> Leg {
        func iso(_ m: Int) -> String { DateParsing.format(time(m)) }
        func place(_ n: Int) -> String { "{\"name\":\"S\(n)\",\"stopId\":\"s\(n)\",\"lat\":\(48 + Double(n) * 0.01),\"lon\":16}" }
        let street = ["WALK", "BIKE", "CAR"].contains(mode)
        let ride = street ? "" : ",\"tripId\":\"\(mode)-\(from)-\(start)\""
        let json = """
        {"mode":"\(mode)","from":\(place(from)),"to":\(place(to)),"duration":\((end - start) * 60),
         "startTime":"\(iso(start))","endTime":"\(iso(end))",
         "scheduledStartTime":"\(iso(start))","scheduledEndTime":"\(iso(end))","realTime":false\(ride),
         "legGeometry":{"points":"","precision":6,"length":0}}
        """
        return try TransitousClient.makeDecoder().decode(Leg.self, from: Data(json.utf8))
    }

    private static func route(_ id: String, _ legs: [Leg]) -> Itinerary {
        Itinerary(id: id, duration: Int(legs[legs.count - 1].endTime.timeIntervalSince(legs[0].startTime)),
                  startTime: legs[0].startTime, endTime: legs[legs.count - 1].endTime,
                  transfers: 0, legs: legs)
    }

    private func place(_ n: Int) -> Endpoint {
        .place(SavedPlace(id: "p\(n)", name: "S\(n)", subtitle: nil, lat: 48 + Double(n) * 0.01, lon: 16, stopId: nil))
    }

    /// A timetable on the line: by car 10 minutes per stop whenever asked; a train from every stop
    /// every 20 minutes (:00, :20, :40), 5 minutes per stop.
    private static let timetable: SectionPlanModel.Search = { from, to, _, time, mode in
        let a = Int(((from.lat - 48) / 0.01).rounded()), b = Int(((to.lat - 48) / 0.01).rounded())
        let asked = Int((time.timeIntervalSince1970 - t0) / 60)
        if let street = mode.streetMode {
            return [route("", [try leg(street, a, b, start: asked, end: asked + 10 * abs(b - a))])]
        }
        let first = ((asked + 19) / 20) * 20
        // One that left before the time asked for, as routers sometimes hand back.
        return try [first - 20, first, first + 20].map { start in
            route("T\(a)-\(start)", [try leg("RAIL", a, b, start: start, end: start + 5 * abs(b - a))])
        }
    }

    @MainActor
    func testSectionsChainWithTheStayAtThePlaceBetween() async throws {
        let model = SectionPlanModel(from: place(0), to: place(4), date: time(3), search: Self.timetable)
        model.leavesNow = false
        model.addStop()
        model.setPlace(place(1), at: 1)
        model.setMode(.car, at: 0)
        model.setStay(10, at: 1)
        XCTAssertNil(model.route)
        await model.plan(current: nil, now: time(0))

        // By car 10:03 – 10:13, 10 minutes to park, then the 10:40 train (10:20 has gone at 10:23).
        XCTAssertEqual(model.sections.map(\.state), [.found, .found])
        XCTAssertEqual(model.sections[0].route?.endTime, time(13))
        XCTAssertEqual(model.earliest(for: 1), time(23))
        XCTAssertEqual(model.sections[1].options.map(\.startTime), [time(40), time(60)])
        let route = try XCTUnwrap(model.route)
        XCTAssertEqual(route.legs.map(\.mode), ["CAR", "RAIL"])
        XCTAssertEqual(route.startTime, time(3))
        XCTAssertEqual(route.endTime, time(55))
        XCTAssertEqual(RouteBuilder.refreshIds(of: route), ["T1-40"], "the drive has no live times to ask for")
    }

    @MainActor
    func testAnotherChoiceOrModeSearchesWhatFollowsAgain() async throws {
        let model = SectionPlanModel(from: place(0), to: place(4), date: time(0), search: Self.timetable)
        model.leavesNow = false
        model.addStop()
        model.setPlace(place(2), at: 1)
        model.setStay(0, at: 1)
        await model.plan(current: nil, now: time(0))
        XCTAssertEqual(model.route?.endTime, time(30))   // 10:00 – 10:10, then 10:20 – 10:30

        // A later first train: the second section is searched again from its arrival.
        model.choose(1, at: 0)
        XCTAssertEqual(model.sections.map(\.state), [.found, .idle])
        XCTAssertNil(model.route)
        await model.plan(current: nil, now: time(0))
        XCTAssertEqual(model.sections[0].route?.startTime, time(20))
        XCTAssertEqual(model.route?.endTime, time(50))   // 10:20 – 10:30, then 10:40 – 10:50

        // Without the place between, it is one section again.
        model.removeStop(at: 1)
        XCTAssertEqual(model.stops.count, 2)
        XCTAssertEqual(model.sections.count, 1)
        await model.plan(current: nil, now: time(0))
        XCTAssertEqual(model.route?.legs.count, 1)
        XCTAssertEqual(model.route?.endTime, time(20))
    }

    @MainActor
    func testAMissingPlaceOrAFailedSearchLeavesNoRoute() async {
        let model = SectionPlanModel(from: place(0), to: place(4), date: time(0)) { _, _, _, _, _ in throw URLError(.timedOut) }
        model.addStop()
        XCTAssertFalse(model.isComplete)
        await model.plan(current: nil, now: time(0))
        XCTAssertEqual(model.sections.map(\.state), [.idle, .idle], "nothing is searched towards a place not chosen yet")
        model.setPlace(place(2), at: 1)
        XCTAssertTrue(model.isComplete)
        await model.plan(current: nil, now: time(0))
        XCTAssertEqual(model.sections.map(\.state), [.failed, .idle])
        XCTAssertNil(model.route)
    }

    func testOnlyWhatLeavesInTimeIsUsableAndRidesOnlyForPublicTransport() throws {
        let walk = Self.route("", [try Self.leg("WALK", 0, 1, start: 5, end: 20)])
        let early = Self.route("E", [try Self.leg("BUS", 0, 1, start: 0, end: 8)])
        let late = Self.route("L", [try Self.leg("BUS", 0, 1, start: 10, end: 18)])
        let later = Self.route("M", [try Self.leg("BUS", 0, 1, start: 6, end: 19)])
        let usable = SectionPlanModel.usable([walk, later, early, late, late], notBefore: time(5), mode: .transit)
        XCTAssertEqual(usable.map(\.id), ["L", "M"])
        XCTAssertEqual(SectionPlanModel.usable([walk], notBefore: time(5), mode: .walk).count, 1)
    }

    func testAChainThatDoesNotMeetIsRefused() throws {
        let a = Self.route("A", [try Self.leg("BUS", 0, 1, start: 0, end: 10)])
        let tooEarly = Self.route("B", [try Self.leg("BUS", 1, 2, start: 5, end: 15)])
        let elsewhere = Self.route("C", [try Self.leg("BUS", 3, 4, start: 20, end: 30)])
        XCTAssertNil(RouteBuilder.chain([a, tooEarly]))
        XCTAssertNil(RouteBuilder.chain([a, elsewhere]))
        XCTAssertNil(RouteBuilder.chain([]))
    }

    /// Places can be dragged into another order; each keeps its stay, and the route is searched again.
    @MainActor
    func testPlacesMoveIntoAnotherOrder() async throws {
        let model = SectionPlanModel(from: place(0), to: place(4), date: time(3), search: Self.timetable)
        model.leavesNow = false
        model.addStop()
        model.setPlace(place(1), at: 1)
        model.setStay(30, at: 1)
        model.addStop()
        model.setPlace(place(2), at: 2)
        await model.plan(current: nil, now: time(0))
        XCTAssertNotNil(model.route)
        let revision = model.revision

        // S2 before S1 (drag the third place up to the second position).
        model.moveStops(from: IndexSet(integer: 2), to: 1)
        XCTAssertEqual(model.stops.map { $0.place?.title }, ["S0", "S2", "S1", "S4"])
        XCTAssertEqual(model.stops[2].stay, 30, "a place keeps its stay")
        XCTAssertGreaterThan(model.revision, revision)
        XCTAssertEqual(model.sections.map(\.state), [.idle, .idle, .idle])
        XCTAssertNil(model.route)
        await model.plan(current: nil, now: time(0))
        XCTAssertNotNil(model.route)

        // Dropped where it already is: nothing changes.
        let still = model.revision
        model.moveStops(from: IndexSet(integer: 1), to: 2)
        XCTAssertEqual(model.revision, still)

        // The destination to the front.
        model.moveStops(from: IndexSet(integer: 3), to: 0)
        XCTAssertEqual(model.stops.map { $0.place?.title }, ["S4", "S0", "S2", "S1"])
        XCTAssertEqual(model.sections.count, 3)
    }

    // MARK: Around a ticket (#24) and change points (#10)

    @MainActor
    func testAroundATicketTheWayThereArrivesInTimeForItsRide() async throws {
        // Ticket S1 → S3 for the train at 10:40; from S0, on to S4.
        let model = SectionPlanModel.aroundTicket(start: place(0), origin: place(1), destinationOfTicket: place(3),
                                                  destination: place(4), departure: time(40), now: time(0), search: Self.timetable)
        XCTAssertEqual(model.anchor, SectionPlanModel.Anchor(index: 1, time: time(40)))
        XCTAssertEqual(model.stops.count, 4)
        XCTAssertEqual(model.stops[1].stay, 0)
        await model.plan(current: nil, now: time(0))
        let there = try XCTUnwrap(model.sections[0].route)
        // Trains from S0 leave at :00, :20, :40 and take 5 min to S1: the 10:20 is the latest in time.
        XCTAssertEqual(there.startTime, time(20))
        XCTAssertLessThanOrEqual(there.endTime, time(40))
        let ride = try XCTUnwrap(model.sections[1].route)
        XCTAssertEqual(ride.startTime, time(40))
        XCTAssertNotNil(model.route)
    }

    @MainActor
    func testATicketWithoutATimeIsPlannedFromNow() async {
        let model = SectionPlanModel.aroundTicket(start: place(0), origin: place(1), destinationOfTicket: place(3),
                                                  destination: nil, departure: nil, now: time(0), search: Self.timetable)
        XCTAssertNil(model.anchor)
        XCTAssertFalse(model.isComplete, "the destination after the ticket is still to be chosen")
    }

    @MainActor
    func testSplittingASectionAtAChangePoint() async throws {
        let model = SectionPlanModel(from: place(0), to: place(4), date: time(0), search: Self.timetable)
        model.leavesNow = false
        await model.plan(current: nil, now: time(0))
        let route = try XCTUnwrap(model.sections[0].route)
        let s2 = try XCTUnwrap(route.legs.first?.from)
        model.split(0, at: s2)
        XCTAssertEqual(model.stops.count, 3)
        XCTAssertEqual(model.stops[1].place?.title, s2.name)
        XCTAssertEqual(model.stops[1].stay, 0)
        XCTAssertEqual(model.sections.count, 2)
        XCTAssertEqual(model.sections.map(\.state), [.idle, .idle])
    }

    func testChangePointsAreTheStopsOnTheWay() throws {
        let a = try Self.leg("RAIL", 0, 2, start: 0, end: 10)
        let b = try Self.leg("RAIL", 2, 4, start: 15, end: 25)
        let names = SectionPlanModel.changePoints(Self.route("x", [a, b])).map(\.name)
        XCTAssertEqual(names, ["S2"], "the change, not the ends")
        XCTAssertTrue(SectionPlanModel.changePoints(Self.route("y", [try Self.leg("WALK", 0, 1, start: 0, end: 5)])).isEmpty)
    }
}

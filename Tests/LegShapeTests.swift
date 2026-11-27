// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich
import XCTest
@testable import Publit

/// The line of a ride must not run over tracks the ride never takes (#114).
final class LegShapeTests: XCTestCase {
    /// Paris, real answers of 27.11.2026, shortened (no walking steps, no fares): Porte de Pantin to
    /// Trocadéro with métro 5 and 9, and Gare du Nord to Charles de Gaulle – Étoile with RER B and A.
    private func answer() throws -> PlanResponse {
        try TransitousClient.makeDecoder().decode(PlanResponse.self, from: Fixtures.data("plan_paris_shape_detours"))
    }

    private func ride(_ res: PlanResponse, line: String) throws -> Leg {
        try XCTUnwrap(res.itineraries.flatMap(\.legs).first { $0.routeShortName == line })
    }

    private func length(_ leg: Leg) -> Double { PathGeometry.length(leg.legGeometry.coordinates) }
    private func stopsLength(_ leg: Leg) -> Double { PathGeometry.length(leg.allStops.map(\.coordinate)) }

    func testServerAnswerDrawsDetours() throws {
        let res = try answer()
        // RER A, Châtelet – Auber – Étoile: 4.3 km from stop to stop, 17 km of line.
        let rerA = try ride(res, line: "A")
        XCTAssertLessThan(stopsLength(rerA), 4_500)
        XCTAssertGreaterThan(length(rerA), 16_000)
        // Métro 5, Porte de Pantin – République: 4.3 km from stop to stop, 8.3 km of line.
        let m5 = try ride(res, line: "5")
        XCTAssertLessThan(stopsLength(m5), 4_500)
        XCTAssertGreaterThan(length(m5), 8_000)
    }

    func testDetoursBecomeTheStraightWayBetweenTheirStops() throws {
        let res = try answer()
        let from = LatLon(lat: 48.888847, lon: 2.394028), to = LatLon(lat: 48.863445, lon: 2.287224)
        let usable = TransitousClient.usable(res, from: from, to: to)
        XCTAssertEqual(usable.itineraries.count, res.itineraries.count)
        for line in ["A", "5"] {
            let before = try ride(res, line: line), after = try ride(usable, line: line)
            // About as long as the way from stop to stop, and never far from it (the real curve of
            // the RER A between Auber and Étoile is up to 290 m off the straight way).
            XCTAssertLessThan(length(after), stopsLength(after) * 1.25, line)
            let stops = after.allStops.map(\.coordinate)
            for point in after.legGeometry.coordinates {
                XCTAssertLessThan(try XCTUnwrap(PathGeometry.locate(point, on: stops)).offset, 400, line)
            }
            // It still starts and ends where the server's line did, and the ride itself is the same.
            XCTAssertEqual(after.legGeometry.coordinates.first, before.legGeometry.coordinates.first)
            XCTAssertEqual(after.legGeometry.coordinates.last, before.legGeometry.coordinates.last)
            XCTAssertEqual(after.allStops.map(\.name), before.allStops.map(\.name))
            XCTAssertEqual(after.startTime, before.startTime)
            // The map draws the tidied line.
            XCTAssertLessThan(PathGeometry.length(after.mapPath), stopsLength(after) * 1.25, line)
        }
    }

    func testOnlyThePartBetweenTheTwoStopsChanges() throws {
        let res = try answer()
        let m5 = try ride(res, line: "5")
        let tidy = m5.tidyingShape()
        let stops = m5.allStops
        // Porte de Pantin – Stalingrad was right: the first four stops keep their curves.
        let stalingrad = try XCTUnwrap(stops.firstIndex { $0.name == "Stalingrad" })
        let upTo = try XCTUnwrap(PathGeometry.locate(stops[stalingrad].coordinate, on: tidy.legGeometry.coordinates)).along
        let before = try XCTUnwrap(PathGeometry.locate(stops[stalingrad].coordinate, on: m5.legGeometry.coordinates)).along
        XCTAssertEqual(upTo, before, accuracy: 30)
        XCTAssertGreaterThan(upTo, PathGeometry.length(stops[...stalingrad].map(\.coordinate)))
    }

    func testRightLinesStayAsTheyAre() throws {
        let res = try answer()
        let from = LatLon(lat: 48.888847, lon: 2.394028), to = LatLon(lat: 48.863445, lon: 2.287224)
        let usable = TransitousClient.usable(res, from: from, to: to)
        // Métro 9 and RER B were drawn right; walks are never touched.
        for line in ["9", "B"] {
            XCTAssertEqual(try ride(usable, line: line).legGeometry.points, try ride(res, line: line).legGeometry.points, line)
        }
        for (a, b) in zip(res.itineraries.flatMap(\.legs), usable.itineraries.flatMap(\.legs)) where !a.isTransit {
            XCTAssertEqual(a.legGeometry.points, b.legGeometry.points)
        }
        XCTAssertEqual(usable.nextPageCursor, res.nextPageCursor)
        XCTAssertEqual(usable.previousPageCursor, res.previousPageCursor)
    }

    // MARK: Rules, on made-up lines

    /// Two stops 1 km apart on a west–east line; `detour` metres out to the north and back in between.
    private func line(detour: Double) -> (path: [LatLon], stops: [LatLon]) {
        let a = LatLon(lat: 47.0, lon: 9.0), b = LatLon(lat: 47.0, lon: 9.0 + 1_000 / (111_320 * cos(47.0 * .pi / 180)))
        let mid = LatLon(lat: 47.0, lon: (a.lon + b.lon) / 2)
        let out = LatLon(lat: 47.0 + detour / 110_540, lon: mid.lon)
        return ([a, mid, out, mid, b], [a, b])
    }

    func testAShortWayRoundStays() {
        // 400 m out and back: 1.8 km for 1 km. A curve, not a mistake.
        let short = line(detour: 400)
        XCTAssertNil(LegShape.withoutDetours(short.path, stops: short.stops))
        // The Albula spirals: three times the straight way stays too.
        let spiral = line(detour: 1_000)
        XCTAssertNil(LegShape.withoutDetours(spiral.path, stops: spiral.stops))
    }

    func testALongWayOutAndBackGoes() throws {
        let wrong = line(detour: 2_000)
        let tidy = try XCTUnwrap(LegShape.withoutDetours(wrong.path, stops: wrong.stops))
        XCTAssertEqual(tidy, wrong.stops)
    }

    func testStopsNextToEachOtherProveNothing() {
        // A loop line back to where it started: the two stops are the same place.
        let a = LatLon(lat: 47.0, lon: 9.0), far = LatLon(lat: 47.02, lon: 9.0)
        XCTAssertNil(LegShape.withoutDetours([a, far, a], stops: [a, LatLon(lat: 47.0005, lon: 9.0)]))
    }

    func testBusesAndFerriesKeepTheirLine() throws {
        let res = try answer()
        let rerA = try ride(res, line: "A")
        XCTAssertTrue(LegShape.railBound.contains(rerA.mode))
        for mode in ["BUS", "COACH", "FERRY", "WALK", "BIKE"] { XCTAssertFalse(LegShape.railBound.contains(mode), mode) }
        for mode in ["SUBWAY", "TRAM", "REGIONAL_RAIL", "SUBURBAN", "HIGHSPEED_RAIL"] { XCTAssertTrue(LegShape.railBound.contains(mode), mode) }
    }

    func testAWholeRouteIsTidied() throws {
        let res = try answer()
        let route = try XCTUnwrap(res.itineraries.first { $0.legs.contains { $0.routeShortName == "A" } })
        let tidy = route.tidyingShapes()
        XCTAssertEqual(tidy.id, route.id)
        XCTAssertEqual(tidy.legs.count, route.legs.count)
        XCTAssertLessThan(length(try XCTUnwrap(tidy.legs.first { $0.routeShortName == "A" })), 5_500)
    }
}

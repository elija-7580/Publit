// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich
import XCTest
@testable import Publit

/// Plan from the vehicle you are riding (idea from BudapestGO, BKK Budapest).
final class OnBoardPlanTests: XCTestCase {
    private let t0 = 1_791_360_000.0   // Wednesday 7 Oct 2026, 10:00 in Vienna

    private func time(_ minutes: Int) -> Date { Date(timeIntervalSince1970: t0 + Double(minutes) * 60) }
    private func iso(_ m: Int) -> String { DateParsing.format(time(m)) }

    /// Stops lie on a line, 0.01° of latitude (about 1.1 km) apart, by the number in their name.
    private func place(_ n: Int, arr: Int? = nil, dep: Int? = nil) -> String {
        var s = "{\"name\":\"S\(n)\",\"stopId\":\"s\(n)\",\"lat\":\(48 + Double(n) * 0.01),\"lon\":16"
        if let arr { s += ",\"arrival\":\"\(iso(arr))\",\"scheduledArrival\":\"\(iso(arr))\"" }
        if let dep { s += ",\"departure\":\"\(iso(dep))\",\"scheduledDeparture\":\"\(iso(dep))\"" }
        return s + "}"
    }

    private func decodeLeg(_ json: String) throws -> Leg {
        try TransitousClient.makeDecoder().decode(Leg.self, from: Data(json.utf8))
    }

    /// Tram T1 from S0 to S5, two minutes between stops (S0 at 0, S1 at 2, … S5 at 10).
    private func tram() throws -> Leg {
        let shape = EncodedPolyline(coordinates: (0...50).map { LatLon(lat: 48 + Double($0) * 0.001, lon: 16) })
        let middle = (1...4).map { place($0, arr: $0 * 2, dep: $0 * 2) }.joined(separator: ",")
        return try decodeLeg("""
        {"mode":"TRAM","from":\(place(0, dep: 0)),"to":\(place(5, arr: 10)),"duration":600,
         "startTime":"\(iso(0))","endTime":"\(iso(10))","scheduledStartTime":"\(iso(0))","scheduledEndTime":"\(iso(10))",
         "realTime":true,"tripId":"T1","routeShortName":"1","intermediateStops":[\(middle)],
         "legGeometry":{"points":"\(shape.points.replacingOccurrences(of: "\\", with: "\\\\"))","precision":6,"length":51}}
        """)
    }

    private func leg(_ mode: String, _ from: Int, _ to: Int, start: Int, end: Int, trip: String? = nil) throws -> Leg {
        let ride = mode == "WALK" ? "" : ",\"tripId\":\"\(trip ?? "\(mode)-\(from)")\""
        return try decodeLeg("""
        {"mode":"\(mode)","from":\(place(from)),"to":\(place(to)),"duration":\((end - start) * 60),
         "startTime":"\(iso(start))","endTime":"\(iso(end))","scheduledStartTime":"\(iso(start))","scheduledEndTime":"\(iso(end))",
         "realTime":false\(ride),"legGeometry":{"points":"","precision":6,"length":0}}
        """)
    }

    private func route(_ id: String, _ legs: [Leg]) -> Itinerary {
        Itinerary(id: id, duration: Int(legs[legs.count - 1].endTime.timeIntervalSince(legs[0].startTime)),
                  startTime: legs[0].startTime, endTime: legs[legs.count - 1].endTime,
                  transfers: max(0, legs.filter(\.isTransit).count - 1), legs: legs)
    }

    func testPolylineEncodesBackToTheSamePoints() {
        let points = [LatLon(lat: 47.49791, lon: 19.04023), LatLon(lat: 47.5, lon: 19.05), LatLon(lat: -33.1, lon: -70.6)]
        let decoded = Polyline.decode(Polyline.encode(points, precision: 6), precision: 6)
        XCTAssertEqual(decoded.count, 3)
        for (a, b) in zip(points, decoded) {
            XCTAssertEqual(a.lat, b.lat, accuracy: 1e-6)
            XCTAssertEqual(a.lon, b.lon, accuracy: 1e-6)
        }
        XCTAssertEqual(Polyline.encode([LatLon(lat: 38.5, lon: -120.2)], precision: 5), "_p~iF~ps|U")
    }

    func testPositionBetweenStopsStartsAtTheNextStop() throws {
        let stops = try tram().allStops
        let pos = try XCTUnwrap(OnBoardPlan.position(stops: stops, now: time(3)))
        XCTAssertEqual(pos.from, 1)
        XCTAssertEqual(pos.next, 2)
        XCTAssertEqual(pos.at, time(4))
        XCTAssertEqual(OnBoardPlan.stopsAhead(stops, from: pos).map(\.name), ["S2", "S3", "S4", "S5"])
        XCTAssertNil(OnBoardPlan.position(stops: stops, now: time(11)), "ride over")
    }

    func testRideIsCutOutOfTheTrip() throws {
        let ride = try XCTUnwrap(OnBoardPlan.ride(try tram(), from: 1, to: 4))
        XCTAssertEqual(ride.from.name, "S1")
        XCTAssertEqual(ride.to.name, "S4")
        XCTAssertEqual(ride.intermediateStops?.map(\.name), ["S2", "S3"])
        XCTAssertEqual(ride.startTime, time(2))
        XCTAssertEqual(ride.endTime, time(8))
        XCTAssertEqual(ride.scheduledStartTime, time(2))
        XCTAssertEqual(ride.duration, 360)
        XCTAssertEqual(ride.tripId, "T1")
        // The shape from S1 (point 10) to S4 (point 40).
        XCTAssertEqual(ride.legGeometry.coordinates.count, 31)
        XCTAssertNil(OnBoardPlan.ride(try tram(), from: 3, to: 3))
    }

    func testStayingOnIsOneRideFromWhereYouAre() throws {
        let trip = try tram()
        let pos = try XCTUnwrap(OnBoardPlan.position(stops: trip.allStops, now: time(3)))
        // Found from S2: the same tram on to S4, then a bus to S7.
        let found = route("X", [try leg("TRAM", 2, 4, start: 4, end: 8, trip: "T1"), try leg("BUS", 4, 7, start: 10, end: 16)])
        let r = try XCTUnwrap(OnBoardPlan.route(found, trip: trip, position: pos))
        XCTAssertEqual(r.legs.map(\.mode), ["TRAM", "BUS"])
        XCTAssertEqual(r.legs[0].from.name, "S1")
        XCTAssertEqual(r.legs[0].to.name, "S4")
        XCTAssertEqual(r.transfers, 1)
        XCTAssertEqual(r.endTime, time(16))
        // Live times: the ride from the trip, the rest from the planned route.
        XCTAssertEqual(r.builtFrom, [RoutePart(itineraryId: "ride:1:4:T1", firstLeg: 0, legCount: 1),
                                     RoutePart(itineraryId: "X", firstLeg: 1, legCount: 1)])
        XCTAssertEqual(RouteBuilder.refreshIds(of: r), ["ride:1:4:T1", "X"])
    }

    func testGettingOffAtTheNextStopEndsTheRideThere() throws {
        let trip = try tram()
        let pos = try XCTUnwrap(OnBoardPlan.position(stops: trip.allStops, now: time(3)))
        let found = route("Y", [try leg("WALK", 2, 9, start: 4, end: 6), try leg("SUBWAY", 9, 12, start: 7, end: 12)])
        let r = try XCTUnwrap(OnBoardPlan.route(found, trip: trip, position: pos))
        XCTAssertEqual(r.legs.map(\.mode), ["TRAM", "WALK", "SUBWAY"])
        XCTAssertEqual(r.legs[0].to.name, "S2")
        XCTAssertEqual(r.transfers, 1)
        XCTAssertEqual(r.builtFrom?.first?.itineraryId, "ride:1:2:T1")
        XCTAssertEqual(r.builtFrom?.last, RoutePart(itineraryId: "Y", firstLeg: 0, legCount: 2))
    }

    func testRoutesAreSortedByArrivalThenChanges() throws {
        let trip = try tram()
        let pos = try XCTUnwrap(OnBoardPlan.position(stops: trip.allStops, now: time(3)))
        let stay = route("A", [try leg("TRAM", 2, 5, start: 4, end: 10, trip: "T1"), try leg("WALK", 5, 6, start: 10, end: 20)])
        let change = route("B", [try leg("BUS", 2, 6, start: 5, end: 15)])
        // Getting off at S2 to wait for a later tram the same way: arrives later with a change more.
        let wait = route("C", [try leg("TRAM", 2, 5, start: 9, end: 15, trip: "T2"), try leg("WALK", 5, 6, start: 15, end: 25)])
        let routes = OnBoardPlan.routes([stay, change, stay, wait], trip: trip, position: pos)
        XCTAssertEqual(routes.map(\.endTime), [time(15), time(20)])
        XCTAssertEqual(routes.map(\.transfers), [1, 0])
    }

    func testRideIdsRoundTripAndRefreshFromTheTrip() throws {
        let id = OnBoardPlan.rideId(tripId: "20261007_10:00_de:vvo:1", from: 1, to: 4)
        let parsed = try XCTUnwrap(OnBoardPlan.parseRide(id))
        XCTAssertEqual(parsed.tripId, "20261007_10:00_de:vvo:1")
        XCTAssertEqual(parsed.from, 1)
        XCTAssertEqual(parsed.to, 4)
        XCTAssertNil(OnBoardPlan.parseRide("abc"))
        let trip = try tram()
        let whole = route("T", [trip])
        let fresh = try XCTUnwrap(OnBoardPlan.refreshed("ride:1:4:T1", trip: whole))
        XCTAssertEqual(fresh.id, "ride:1:4:T1")
        XCTAssertEqual(fresh.legs.count, 1)
        XCTAssertEqual(fresh.legs[0].to.name, "S4")
    }
}

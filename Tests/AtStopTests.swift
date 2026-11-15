import XCTest
@testable import Publit

/// Standing at the stop: no "walk 1 min" before boarding, no walking time to where you already are.
final class AtStopTests: XCTestCase {
    private let t0 = 1_791_360_000.0
    private let stop = (48.20000, 16.37000)

    private func date(_ m: Double) -> Date { Date(timeIntervalSince1970: t0 + m * 60) }

    private func leg(_ mode: String, start: Double, end: Double, from: (Double, Double), to: (Double, Double),
                     distance: Double? = nil) throws -> Leg {
        func iso(_ m: Double) -> String { DateParsing.format(date(m)) }
        let line = mode == "WALK" ? "" : ",\"routeShortName\":\"13A\""
        let dist = distance.map { ",\"distance\":\($0)" } ?? ""
        let json = """
        {"mode":"\(mode)","from":{"name":"A","lat":\(from.0),"lon":\(from.1)},"to":{"name":"B","lat":\(to.0),"lon":\(to.1)},
         "duration":\(Int((end - start) * 60)),"startTime":"\(iso(start))","endTime":"\(iso(end))",
         "scheduledStartTime":"\(iso(start))","scheduledEndTime":"\(iso(end))",
         "realTime":false\(line)\(dist),"legGeometry":{"points":"","precision":6,"length":0}}
        """
        return try TransitousClient.makeDecoder().decode(Leg.self, from: Data(json.utf8))
    }

    private func route(walkMeters: Double, here: (Double, Double)) throws -> Itinerary {
        let legs = [try leg("WALK", start: 0, end: 1, from: here, to: stop, distance: walkMeters),
                    try leg("BUS", start: 4, end: 20, from: stop, to: (48.21, 16.38))]
        return Itinerary(id: "x", duration: 20 * 60, startTime: date(0), endTime: date(20), transfers: 0, legs: legs)
    }

    func testAtTheStopTheRouteStartsWithTheRide() throws {
        let here = (48.20015, 16.37010) // about 18 m away
        let out = Reach.boardingHere([try route(walkMeters: 20, here: here)], here: LatLon(lat: here.0, lon: here.1))[0]
        XCTAssertEqual(out.legs.first?.mode, "BUS")
        XCTAssertEqual(out.startTime, date(4))
        XCTAssertEqual(out.duration, 16 * 60)
        XCTAssertEqual(Reach.leaveText(out, minutes: 3), L10n.f("Departs in %lld min", 3))
        XCTAssertEqual(Reach.leaveText(out, minutes: 0), L10n.t("Board here"))
    }

    func testAcrossTheRoadOrFurtherTheWalkStays() throws {
        let here = (48.20015, 16.37010)
        // Close in a straight line, but the path crosses the road: keep the walk.
        let across = Reach.boardingHere([try route(walkMeters: 90, here: here)], here: LatLon(lat: here.0, lon: here.1))[0]
        XCTAssertEqual(across.legs.first?.mode, "WALK")
        XCTAssertEqual(Reach.leaveText(across, minutes: 3), L10n.f("Leave in %lld min", 3))
        // 150 m away.
        let far = (48.20135, 16.37000)
        let away = Reach.boardingHere([try route(walkMeters: 40, here: far)], here: LatLon(lat: far.0, lon: far.1))[0]
        XCTAssertEqual(away.legs.count, 2)
    }

    func testRadius() {
        XCTAssertTrue(Reach.isAtStop(meters: 0))
        XCTAssertTrue(Reach.isAtStop(meters: Reach.atStopMeters))
        XCTAssertFalse(Reach.isAtStop(meters: Reach.atStopMeters + 1))
        XCTAssertFalse(Reach.isAtStop(meters: .nan))
    }
}

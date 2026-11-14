import XCTest
@testable import Publit

/// Exit numbers of underground stations from OpenStreetMap ("Take exit B2").
final class StationExitsTests: XCTestCase {
    private func munich() throws -> Itinerary {
        let res = try TransitousClient.makeDecoder().decode(PlanResponse.self, from: Fixtures.data("plan_walk_steps"))
        return try XCTUnwrap(res.itineraries.first)
    }

    func testOnlyWalksOutOfAnUndergroundStation() throws {
        let it = try munich()
        XCTAssertFalse(StationExits.leavesUnderground(it.legs, at: 0), "first walk starts at the origin")
        XCTAssertFalse(StationExits.leavesUnderground(it.legs, at: 2), "change between two underground platforms")
        XCTAssertTrue(StationExits.leavesUnderground(it.legs, at: 4))
    }

    func testExitNumberNearWhereTheWalkReachesTheStreet() throws {
        let it = try munich()
        let leg = it.legs[4]
        let plain = WalkRoute(leg: leg, exits: StationExits())
        let i = try XCTUnwrap(plain.exitIndex)
        XCTAssertNil(plain.maneuvers[i].exitRef)
        let at = plain.maneuvers[i].coordinate
        let exits = StationExits()
        exits.store([StationEntrance(id: 1, ref: "A1", coordinate: LatLon(lat: at.lat + 0.003, lon: at.lon)),
                     StationEntrance(id: 2, ref: "B2", coordinate: LatLon(lat: at.lat + 0.0001, lon: at.lon))], for: leg)
        let up = WalkRoute(leg: leg, exits: exits)
        XCTAssertEqual(up.exitIndex, i)
        XCTAssertEqual(up.maneuvers[i].exitRef, "B2")
        XCTAssertTrue(try XCTUnwrap(up.maneuvers[i].exitNote).hasPrefix("Take exit B2"))
        // Other walks of the trip get no number.
        XCTAssertNil(WalkRoute(leg: it.legs[2], exits: exits).exitIndex)
    }

    func testEntranceTheRoutePassesThroughWins() {
        let path = [LatLon(lat: 48.0, lon: 11.0), LatLon(lat: 48.001, lon: 11.0)]
        let near = StationEntrance(id: 1, ref: "A", coordinate: LatLon(lat: 48.0005, lon: 11.0))
        let through = StationEntrance(id: 2, ref: "C", coordinate: LatLon(lat: 48.0, lon: 11.002))
        let exit = (point: LatLon(lat: 48.0005, lon: 11.0), along: 55.0)
        XCTAssertEqual(StationExits.pick([near, through], path: path, exit: exit, nodes: [2])?.ref, "C")
        XCTAssertEqual(StationExits.pick([near, through], path: path, exit: exit, nodes: [])?.ref, "A")
        // No level change known: the first entrance next to the path.
        let later = StationEntrance(id: 3, ref: "D", coordinate: LatLon(lat: 48.0009, lon: 11.0))
        XCTAssertEqual(StationExits.pick([later, near], path: path, exit: nil, nodes: [])?.ref, "A")
        XCTAssertNil(StationExits.pick([through], path: path, exit: nil, nodes: []))
    }

    func testOverpassAnswer() throws {
        let json = """
        {"elements":[{"type":"node","id":11,"lat":22.28,"lon":114.15,"tags":{"railway":"subway_entrance","ref":"B2"}},
        {"type":"node","id":12,"lat":22.281,"lon":114.151,"tags":{"railway":"subway_entrance","ref":"Ausgang Nord-West"}},
        {"type":"node","id":13,"lat":22.282,"lon":114.152,"tags":{"railway":"subway_entrance","ref":"A;B"}}]}
        """
        let e = try StationExits.parse(Data(json.utf8))
        XCTAssertEqual(e.map(\.ref), ["B2"])
        XCTAssertTrue(StationExits.query(around: LatLon(lat: 22.28, lon: 114.15)).contains("subway_entrance"))
    }
}

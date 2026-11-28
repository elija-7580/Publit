import XCTest
@testable import Publit

/// Station exits from OpenStreetMap ("Take exit B2"), for metro and railway stations.
final class StationExitsTests: XCTestCase {
    private func munich() throws -> Itinerary {
        let res = try TransitousClient.makeDecoder().decode(PlanResponse.self, from: Fixtures.data("plan_walk_steps"))
        return try XCTUnwrap(res.itineraries.first)
    }

    func testOnlyWalksOutOfAnUndergroundStation() throws {
        let it = try munich()
        XCTAssertFalse(StationExits.leavesStation(it.legs, at: 0), "first walk starts at the origin")
        XCTAssertFalse(StationExits.leavesStation(it.legs, at: 2), "change between two underground platforms")
        XCTAssertTrue(StationExits.leavesStation(it.legs, at: 4))
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
        XCTAssertEqual(e.compactMap(\.ref), ["B2"], "long refs and lists are not signs")
        XCTAssertEqual(e.count, 3, "a door without a usable sign still shows where to go out")
        XCTAssertTrue(StationExits.query(around: LatLon(lat: 22.28, lon: 114.15)).contains("subway_entrance"))
    }

    /// The fixture's trip with the rides changed to `mode`, walks without levels (as at a station at street level).
    private func trip(rides mode: String) throws -> Itinerary {
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: Fixtures.data("plan_walk_steps")) as? [String: Any])
        var its = try XCTUnwrap(root["itineraries"] as? [[String: Any]])
        var legs = try XCTUnwrap(its[0]["legs"] as? [[String: Any]])
        for i in legs.indices {
            if legs[i]["mode"] as? String == "SUBWAY" { legs[i]["mode"] = mode } else { legs[i]["steps"] = [] as [Any] }
        }
        its[0]["legs"] = legs
        root["itineraries"] = its
        let data = try JSONSerialization.data(withJSONObject: root)
        return try XCTUnwrap(TransitousClient.makeDecoder().decode(PlanResponse.self, from: data).itineraries.first)
    }

    /// Railway stations above ground get their exits too; trams and buses stop in the street.
    func testTrainStationsCountTramsDoNot() throws {
        let train = try trip(rides: "REGIONAL_RAIL")
        XCTAssertTrue(StationExits.leavesStation(train.legs, at: 4))
        XCTAssertFalse(StationExits.leavesStation(train.legs, at: 2), "short walk to the next train is a change")
        let tram = try trip(rides: "TRAM")
        XCTAssertFalse(StationExits.leavesStation(tram.legs, at: 4))
    }

    /// Above ground there is no level change: the door the walk passes through is the exit, shown at the start.
    func testExitOfAStationAtStreetLevel() throws {
        let leg = try trip(rides: "RAIL").legs[4]
        let route = WalkRoute(leg: leg, exits: StationExits())
        let p = try XCTUnwrap(route.path.dropFirst(2).first)
        let exits = StationExits()
        exits.store([StationEntrance(id: 7, ref: nil, name: "Nord", coordinate: LatLon(lat: p.lat + 0.00005, lon: p.lon))], for: leg)
        let out = WalkRoute(leg: leg, exits: exits)
        XCTAssertEqual(out.exitDoor?.label, "Nord")
        XCTAssertTrue(try XCTUnwrap(out.maneuvers[0].exitNote).hasPrefix("Take exit Nord"))
    }

    func testNamesReadAsSigns() {
        XCTAssertEqual(StationExits.cleanName("Ausgang Nord"), "Nord")
        XCTAssertEqual(StationExits.cleanName("Bahnhofplatz"), "Bahnhofplatz")
        XCTAssertEqual(StationExits.cleanName("Exit"), "Exit")
        XCTAssertNil(StationExits.cleanName("Zugang zur Unterführung und zum Busbahnhof Süd"))
    }

    func testSignedDoorWinsOverAnUnsignedOne() {
        let path = [LatLon(lat: 48.0, lon: 11.0), LatLon(lat: 48.001, lon: 11.0)]
        let plain = StationEntrance(id: 1, ref: nil, coordinate: LatLon(lat: 48.0005, lon: 11.0))
        let signed = StationEntrance(id: 2, ref: "A", coordinate: LatLon(lat: 48.0005, lon: 11.0))
        XCTAssertEqual(StationExits.pick([plain, signed], path: path, exit: nil, nodes: [])?.ref, "A")
    }

    /// The exit number showed nowhere when the walk's path passed no door (wish: "show the optimal exit").
    func testSignedDoorTowardsTheWalkWhenNoneIsOnTheWay() {
        // The walk heads 300 m north; doors 40 m beside the platform, one north-east, one south.
        let path = [LatLon(lat: 48.0, lon: 11.0), LatLon(lat: 48.0027, lon: 11.0)]
        let north = StationEntrance(id: 1, ref: "3", coordinate: LatLon(lat: 48.0003, lon: 11.0005))
        let south = StationEntrance(id: 2, ref: "1", coordinate: LatLon(lat: 47.9997, lon: 11.0005))
        let unsigned = StationEntrance(id: 3, ref: nil, coordinate: LatLon(lat: 48.0004, lon: 11.0004))
        XCTAssertEqual(StationExits.pick([south, unsigned, north], path: path, exit: nil, nodes: [])?.ref, "3")
        // Far off to the side: not a door of this walk.
        let far = StationEntrance(id: 4, ref: "9", coordinate: LatLon(lat: 48.0, lon: 11.003))
        XCTAssertNil(StationExits.pick([far], path: path, exit: nil, nodes: []))
    }

    func testExitNamesWithTheStationInFront() throws {
        XCTAssertEqual(StationExits.cleanName("Stephansplatz, Ausgang Graben"), "Graben")
        XCTAssertEqual(StationExits.cleanName("Karlsplatz - Ausgang 3"), "3")
        XCTAssertEqual(StationExits.cleanName("Ausgang Nord"), "Nord")
        let json = """
        {"elements":[{"type":"node","id":21,"lat":48.2,"lon":16.37,"tags":{"railway":"subway_entrance","local_ref":"4"}}]}
        """
        XCTAssertEqual(try StationExits.parse(Data(json.utf8)).first?.ref, "4")
    }
}

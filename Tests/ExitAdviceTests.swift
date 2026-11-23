// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich

import XCTest
@testable import Publit

/// Where to ride in the train and which way out, per trip ("Board at the front · Take exit B2").
final class ExitAdviceTests: XCTestCase {
    private func munich() throws -> Itinerary {
        let res = try TransitousClient.makeDecoder().decode(PlanResponse.self, from: Fixtures.data("plan_walk_steps"))
        return try XCTUnwrap(res.itineraries.first)
    }

    private func defaults() -> UserDefaults {
        let name = "ExitAdviceTests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    /// `metres` from `p` towards `bearing` (flat earth, fine at station scale).
    private func offset(_ p: LatLon, metres: Double, bearing: Double) -> LatLon {
        let r = bearing * .pi / 180
        return LatLon(lat: p.lat + metres * cos(r) / 110_540,
                      lon: p.lon + metres * sin(r) / (111_320 * cos(p.lat * .pi / 180)))
    }

    private func heading(_ ride: Leg) throws -> Double {
        let path = ride.legGeometry.coordinates
        let length = PathGeometry.length(path)
        let before = try XCTUnwrap(PathGeometry.point(at: max(0, length - 120), on: path))
        return PathGeometry.bearing(before, try XCTUnwrap(path.last))
    }

    func testAChangeAimsAtTheNextTrainTheLastRideAtTheWayOut() throws {
        let it = try munich()
        let advice = ExitAdvice.all(it.legs, exits: StationExits(defaults: defaults()))
        XCTAssertEqual(Set(advice.keys), [1, 3], "only the rides")
        let change = try XCTUnwrap(advice[1])
        XCTAssertTrue(change.forChange)
        XCTAssertNotNil(change.part, "the walk to the next platform says which end of the train")
        XCTAssertEqual(change.reason, "Closest to your next train")
        let out = try XCTUnwrap(advice[3])
        XCTAssertFalse(out.forChange)
        XCTAssertNil(out.door, "no exit numbers loaded")
        XCTAssertEqual(out.reason, "Closest to the way out")
        XCTAssertNotNil(out.boardText)
    }

    func testTheExitNumberJoinsTheAdvice() throws {
        let it = try munich()
        let walk = it.legs[4]
        let exitAt = try XCTUnwrap(WalkRoute(leg: walk, exits: StationExits()).maneuvers.first { $0.level == 0 }?.coordinate)
        let exits = StationExits(defaults: defaults())
        exits.store([StationEntrance(id: 1, ref: "A1", coordinate: LatLon(lat: exitAt.lat + 0.003, lon: exitAt.lon)),
                     StationEntrance(id: 2, ref: "B2", coordinate: LatLon(lat: exitAt.lat + 0.0001, lon: exitAt.lon))], for: walk)
        let a = try XCTUnwrap(ExitAdvice.forRide(3, in: it.legs, exits: exits))
        XCTAssertEqual(a.door, "B2")
        XCTAssertFalse(a.doorSaved)
        XCTAssertEqual(a.reason, "Closest to exit B2")
        XCTAssertTrue(try XCTUnwrap(a.short).hasSuffix("Exit B2"))
    }

    func testAnExitPickedByTheUserIsRememberedForStationAndDestination() throws {
        let it = try munich()
        let walk = it.legs[4]
        let exitAt = try XCTUnwrap(WalkRoute(leg: walk, exits: StationExits()).maneuvers.first { $0.level == 0 }?.coordinate)
        let store = defaults()
        let exits = StationExits(defaults: store)
        let far = StationEntrance(id: 1, ref: "A1", coordinate: LatLon(lat: exitAt.lat + 0.002, lon: exitAt.lon))
        exits.store([far, StationEntrance(id: 2, ref: "B2", coordinate: LatLon(lat: exitAt.lat + 0.0001, lon: exitAt.lon)),
                     StationEntrance(id: 3, ref: "B2", coordinate: exitAt),
                     StationEntrance(id: 4, ref: nil, coordinate: exitAt)], for: walk)
        XCTAssertEqual(exits.choices(for: walk).compactMap(\.label), ["A1", "B2"], "one per sign, unsigned doors left out")
        exits.setPreferred(far, for: walk)
        let a = try XCTUnwrap(ExitAdvice.forRide(3, in: it.legs, exits: exits))
        XCTAssertEqual(a.door, "A1")
        XCTAssertTrue(a.doorSaved)
        XCTAssertEqual(WalkRoute(leg: walk, exits: exits).exitDoor?.label, "A1", "the walking directions use it too")
        // Kept across launches (another instance, same defaults), and found again by its sign if the node changed.
        let later = StationExits(defaults: store)
        later.store([StationEntrance(id: 99, ref: "A1", coordinate: far.coordinate)], for: walk)
        XCTAssertEqual(later.preferred(for: walk)?.id, 99)
        // Another destination from the same station: not this choice.
        XCTAssertNotEqual(StationExits.preferenceKey(walk), StationExits.preferenceKey(it.legs[2]))
        exits.setPreferred(nil, for: walk)
        XCTAssertEqual(ExitAdvice.forRide(3, in: it.legs, exits: exits)?.door, "B2", "back to the automatic choice")
    }

    func testPartOfTheTrainAlongTheDirectionOfTravel() throws {
        let ride = try munich().legs[3]
        let h = try heading(ride)
        let stop = ride.to.coordinate
        XCTAssertEqual(ExitAdvice.part(arriving: ride, towards: offset(stop, metres: 60, bearing: h)), .front)
        XCTAssertEqual(ExitAdvice.part(arriving: ride, towards: offset(stop, metres: 60, bearing: h + 180)), .back)
        XCTAssertEqual(ExitAdvice.part(arriving: ride, towards: offset(stop, metres: 40, bearing: h + 90)), .middle, "stairs beside the middle")
        XCTAssertNil(ExitAdvice.part(arriving: ride, towards: offset(stop, metres: 5, bearing: h)), "right where it stops")
        XCTAssertNil(ExitAdvice.part(arriving: ride, towards: offset(stop, metres: 30, bearing: h + 45)), "neither end nor middle")
        XCTAssertNil(ExitAdvice.part(arriving: ride, towards: offset(stop, metres: 900, bearing: h)), "another station")
    }

    func testTheWatchGetsTheAdviceWithoutTheDirections() throws {
        let it = try munich()
        let exits = StationExits(defaults: defaults())
        let phone = ExitAdvice.all(it.legs, exits: exits)
        let slim = it.forWatch()
        XCTAssertNil(slim.legs[4].steps)
        XCTAssertEqual(slim.legs[1].exitAdvice, phone[1])
        XCTAssertEqual(ExitAdvice.forRide(3, in: slim.legs, exits: exits), phone[3])
        XCTAssertNil(slim.legs[0].exitAdvice, "walks carry none")
        // Through the watch's codec and back.
        let data = try JSONFile<Leg>.encoder.encode(slim.legs[3])
        XCTAssertEqual(try TransitousClient.makeDecoder().decode(Leg.self, from: data).exitAdvice, phone[3])
    }

    func testBusesAndTramsGetNone() throws {
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: Fixtures.data("plan_walk_steps")) as? [String: Any])
        var its = try XCTUnwrap(root["itineraries"] as? [[String: Any]])
        var legs = try XCTUnwrap(its[0]["legs"] as? [[String: Any]])
        for i in legs.indices where legs[i]["mode"] as? String == "SUBWAY" { legs[i]["mode"] = "TRAM" }
        its[0]["legs"] = legs
        root["itineraries"] = its
        let it = try XCTUnwrap(TransitousClient.makeDecoder().decode(PlanResponse.self, from: JSONSerialization.data(withJSONObject: root)).itineraries.first)
        XCTAssertTrue(ExitAdvice.all(it.legs, exits: StationExits(defaults: defaults())).isEmpty)
    }
}

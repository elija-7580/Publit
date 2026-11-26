// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich
import XCTest
@testable import Publit

/// "Arrive by" must never list a route that runs from the destination to the start (#188).
final class ArriveByDirectionTests: XCTestCase {
    /// Saarbrücken, a point in the centre to "Universität Busterminal", arrive by 27.11.2026 09:30,
    /// asked with `slowDirect=true` (smart routing) on 26.11.2026. Real answer, shortened (no shapes,
    /// no stops in between): 9 routes, 4 of them start at the university and end at "END" in the centre.
    private let from = LatLon(lat: 49.2311, lon: 6.9990)
    private let to = LatLon(lat: 49.25746, lon: 7.047351)

    private func answer() throws -> PlanResponse {
        try TransitousClient.makeDecoder().decode(PlanResponse.self, from: Fixtures.data("plan_arrive_by_slow_direct"))
    }

    func testServerAnswerContainsRoutesTheWrongWayRound() throws {
        let res = try answer()
        XCTAssertEqual(res.itineraries.count, 9)
        let backwards = res.itineraries.filter { $0.runsBackwards(from: from, to: to) }
        XCTAssertEqual(backwards.count, 4)
        // All of them: board at or next to the destination, end on the start's coordinates.
        for route in backwards {
            XCTAssertEqual(route.legs.last?.to.name, "END")
            XCTAssertLessThan(try XCTUnwrap(route.legs.first).from.coordinate.distance(to: to), 600)
            XCTAssertLessThan(try XCTUnwrap(route.legs.last).to.coordinate.distance(to: from), 50)
        }
    }

    func testOnlyRoutesInTheAskedDirectionStay() throws {
        let res = try answer()
        let usable = TransitousClient.usable(res, from: from, to: to)
        XCTAssertEqual(usable.itineraries.count, 5)
        for route in usable.itineraries {
            XCTAssertEqual(route.legs.first?.from.name, "START")
            XCTAssertTrue(try XCTUnwrap(route.legs.last).to.name.hasPrefix("Universität Busterminal"), route.legs.last?.to.name ?? "")
            XCTAssertLessThan(try XCTUnwrap(route.legs.last).to.coordinate.distance(to: to), 150)
        }
        // The order of what stays is the server's, and paging goes on from the same cursors.
        XCTAssertEqual(usable.itineraries.map(\.id), ["slow-direct-0", "slow-direct-1", "slow-direct-2", "slow-direct-3", "slow-direct-5"])
        XCTAssertEqual(usable.previousPageCursor, res.previousPageCursor)
        XCTAssertEqual(usable.nextPageCursor, res.nextPageCursor)
        XCTAssertEqual(res.itineraries.facing(from: from, to: to).count, 5)
    }

    /// The way back asked on purpose (start and destination swapped) keeps exactly the other four.
    func testTheWayBackIsNotBackwardsWhenAskedFor() throws {
        let res = try answer()
        let back = res.itineraries.facing(from: to, to: from)
        XCTAssertEqual(back.count, 4)
        XCTAssertTrue(back.allSatisfy { $0.legs.last?.to.name == "END" })
    }

    func testRightAnswersAreLeftAlone() throws {
        let decoder = TransitousClient.makeDecoder()
        for name in ["plan", "plan_muc", "plan_roma", "plan_long_walk", "plan_park_ride", "plan_rental", "plan_walk_steps"] {
            let res = try decoder.decode(PlanResponse.self, from: Fixtures.data(name))
            guard let first = res.itineraries.first, let start = first.legs.first?.from.coordinate,
                  let end = first.legs.last?.to.coordinate else { continue }
            let usable = TransitousClient.usable(res, from: start, to: end)
            XCTAssertEqual(usable.itineraries.count, res.itineraries.count, name)
        }
    }

    /// Start and destination next to each other (two platforms of one station): nothing is judged,
    /// a route that starts at the platform nearer to the destination is still a route.
    func testNothingIsDroppedWhenStartAndDestinationAreClose() throws {
        let res = try answer()
        let near = LatLon(lat: from.lat + 0.001, lon: from.lon)
        XCTAssertLessThan(from.distance(to: near), 200)
        XCTAssertEqual(res.itineraries.facing(from: from, to: near).count, 9)
        XCTAssertFalse(try XCTUnwrap(res.itineraries.last).runsBackwards(from: from, to: from))
    }
}

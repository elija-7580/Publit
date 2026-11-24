// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich
import XCTest
@testable import Publit

/// A better stop while walking to a ride (#110): when to look, and what counts as clearly faster.
final class FasterWayTests: XCTestCase {
    /// Munich, three routes: S-Bahn 06:17 (arrives 06:57), S-Bahn 06:18 (arrives 07:08),
    /// U-Bahn 06:21 and bus (arrives 06:58).
    private func routes() throws -> [Itinerary] {
        try TransitousClient.makeDecoder().decode(PlanResponse.self, from: Fixtures.data("plan_muc")).itineraries
    }

    func testOnlyClearlyEarlierArrivalsEarliestFirst() throws {
        let all = try routes()
        let (first, slow, viaBus) = (all[0], all[1], all[2])
        let now = slow.startTime.addingTimeInterval(-360)
        // On the slow S-Bahn: both others arrive ten minutes earlier; the trip itself is no other way.
        XCTAssertEqual(TripAlternative.faster(all, than: slow, at: now).map(\.id), [first.id, viaBus.id])
        // One minute earlier is not worth turning round for.
        XCTAssertEqual(viaBus.endTime.timeIntervalSince(first.endTime), 60)
        XCTAssertTrue(TripAlternative.faster(all, than: viaBus, at: now).isEmpty)
        XCTAssertTrue(TripAlternative.faster(all, than: first, at: now).isEmpty)
        XCTAssertTrue(TripAlternative.faster([], than: slow, at: now).isEmpty)
    }

    func testOnlyWhatYouCanStillCatch() throws {
        let all = try routes()
        let slow = all[1]
        // The 06:17 S-Bahn leaves in a few seconds: only the way via the bus is left.
        let now = try XCTUnwrap(all[0].firstTransitLeg).startTime.addingTimeInterval(-10)
        XCTAssertEqual(TripAlternative.faster(all, than: slow, at: now).map(\.id), [all[2].id])
    }

    func testSameVehiclesAreNotAnotherWay() throws {
        let all = try routes()
        let slow = all[1]
        // The trip's own vehicles with a fresher, earlier live arrival: still the same way.
        var fresher = slow
        fresher.endTime = slow.endTime.addingTimeInterval(-600)
        XCTAssertTrue(TripAlternative.faster([fresher], than: slow, at: slow.startTime.addingTimeInterval(-360)).isEmpty)
    }

    func testLooksOnlyOnAWalkToARideWithTimeLeft() throws {
        // Munich: walk 13:57 (4 min), U-Bahn 14:01, walk 14:03 (3 min), U-Bahn 14:07, walk 14:14 to the door.
        let it = try TransitousClient.makeDecoder().decode(PlanResponse.self, from: Fixtures.data("plan_walk_steps")).itineraries[0]
        let steps = TripGuide.steps(it)
        let first = try XCTUnwrap(steps.first { $0.kind == .walk })
        let departs = it.legs[1].startTime
        XCTAssertTrue(TripAlternative.worthLooking(first, it, at: it.startTime))
        XCTAssertTrue(TripAlternative.worthLooking(first, it, at: departs.addingTimeInterval(-180)))
        // Two minutes before it leaves you are at the stop.
        XCTAssertFalse(TripAlternative.worthLooking(first, it, at: departs.addingTimeInterval(-120)))
        // A trip opened long before it starts is not slow because one could leave now.
        XCTAssertFalse(TripAlternative.worthLooking(first, it, at: it.startTime.addingTimeInterval(-600)))
        // Waiting and riding are not walking.
        for step in steps where step.kind != .walk {
            XCTAssertFalse(TripAlternative.worthLooking(step, it, at: it.startTime), step.id)
        }
        // The walk between two rides counts, the walk at the end leads to no ride.
        let between = try XCTUnwrap(steps.first { $0.kind == .walk && $0.legIndex == 2 })
        XCTAssertTrue(TripAlternative.worthLooking(between, it, at: it.legs[3].startTime.addingTimeInterval(-200)))
        let last = try XCTUnwrap(steps.last { $0.kind == .walk })
        XCTAssertEqual(last.legIndex, it.legs.count - 1)
        XCTAssertFalse(TripAlternative.worthLooking(last, it, at: it.legs[4].startTime))
    }
}

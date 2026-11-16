import XCTest
@testable import Publit

/// Feedback, November 2026: home 10 km from two stations on different lines, both towards Milan.
/// Park & Ride should let both compete, without driving past the local station to the next town.
final class Build82Tests: XCTestCase {
    private func plan(_ name: String) throws -> PlanResponse {
        try TransitousClient.makeDecoder().decode(PlanResponse.self, from: Fixtures.data(name))
    }

    /// Drives of 12, 16 and 25 min: the stations at 12 and 16 min stay, the one at 25 min goes.
    func testSecondStationCompetesFarTownDoesNot() throws {
        let list = try plan("plan_park_ride_two_stations").itineraries
        XCTAssertEqual(list.map(ParkAndRide.driveSeconds), [720, 960, 1500])
        let kept = ParkAndRide.nearStations(ParkAndRide.sensible(list), nearest: 720)
        XCTAssertEqual(kept.map(ParkAndRide.driveSeconds), [720, 960])
    }

    /// Nearest station 12 min away: search once more up to 22 min.
    func testWiderSearchAfterNearestStation() throws {
        let list = try plan("plan_park_ride_two_stations").itineraries
        let first = Array(list.prefix(1))
        XCTAssertEqual(ParkAndRide.widerLimit(firstSearch: first, kept: first), 720 + 600)
    }

    /// Nearest station 8 min away (Gföhl → Krems): up to 18 min, so St. Pölten (25 min) stays out.
    func testNearStationNeedsNoWiderSearchBeyondLimit() throws {
        let list = try plan("plan_park_ride").itineraries
        XCTAssertEqual(ParkAndRide.widerLimit(firstSearch: list, kept: list), 480 + 600)
    }

    /// No car route in the first search (every station over 15 min): try up to 25 min.
    /// Car routes that were all dropped (the destination is a short drive): no wider search.
    func testWiderSearchWithoutAnyStationInReach() throws {
        XCTAssertEqual(ParkAndRide.widerLimit(firstSearch: [], kept: []), ParkAndRide.maxWiderDriveSeconds)
        let mostly = try plan("plan_park_ride_drive_most").itineraries
        XCTAssertNil(ParkAndRide.widerLimit(firstSearch: mostly, kept: []))
    }
}

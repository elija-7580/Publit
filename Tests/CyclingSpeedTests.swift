// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich

import XCTest
@testable import Publit

/// Wish #30 "Import bike speed": the cycling speed from Apple Health goes to the router.
final class CyclingSpeedTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "CyclingSpeedTests"

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() { defaults.removePersistentDomain(forName: suite) }

    func testAverageIsDistanceOverTime() throws {
        let v = try XCTUnwrap(SmartRouting.cyclingSpeed(fromRides: [(6_000, 1_200), (4_000, 1_000)]))
        XCTAssertEqual(v, 10_000 / 2_200, accuracy: 0.001)
    }

    func testTooLittleOrImplausibleRidingIsIgnored() {
        XCTAssertNil(SmartRouting.cyclingSpeed(fromRides: []))
        XCTAssertNil(SmartRouting.cyclingSpeed(fromRides: [(2_000, 500)]))
        // A car trip logged as a ride (90 km/h) and a 100 m test ride do not count.
        XCTAssertNil(SmartRouting.cyclingSpeed(fromRides: [(25_000, 1_000), (100, 120), (2_500, 600)]))
    }

    func testOwnSpeedOnlyWhenTurnedOnAndPlausible() {
        defaults.set(5.123, forKey: SmartRouting.measuredCyclingSpeedKey)
        XCTAssertNil(SmartRouting.ownCyclingSpeed(defaults))
        defaults.set(true, forKey: SmartRouting.ownCyclingSpeedKey)
        XCTAssertEqual(SmartRouting.ownCyclingSpeed(defaults), 5.12)
        defaults.set(false, forKey: SmartRouting.enabledKey)
        XCTAssertNil(SmartRouting.ownCyclingSpeed(defaults))
        defaults.set(true, forKey: SmartRouting.enabledKey)
        defaults.set(30.0, forKey: SmartRouting.measuredCyclingSpeedKey)
        XCTAssertNil(SmartRouting.ownCyclingSpeed(defaults))
    }

    func testQueriesCarryTheSpeed() {
        let a = LatLon(lat: 48.2, lon: 16.37), b = LatLon(lat: 48.18, lon: 16.31)
        let bike = TransitousClient.streetQuery(from: a, to: b, time: nil, arriveBy: false, mode: "BIKE", cyclingSpeed: 6.5)
        XCTAssertEqual(bike.first { $0.name == "cyclingSpeed" }?.value, "6.5")
        let car = TransitousClient.streetQuery(from: a, to: b, time: nil, arriveBy: false, mode: "CAR", cyclingSpeed: 6.5)
        XCTAssertNil(car.first { $0.name == "cyclingSpeed" })
        let plain = TransitousClient.streetQuery(from: a, to: b, time: nil, arriveBy: false, mode: "BIKE", cyclingSpeed: nil)
        XCTAssertNil(plain.first { $0.name == "cyclingSpeed" })

        var smart = SmartRouting.Request(enabled: true)
        XCTAssertNil(smart.queryItems.first { $0.name == "cyclingSpeed" })
        let before = smart.key
        smart.cyclingSpeed = 5.5
        XCTAssertEqual(smart.queryItems.first { $0.name == "cyclingSpeed" }?.value, "5.5")
        XCTAssertNotEqual(smart.key, before)
    }
}

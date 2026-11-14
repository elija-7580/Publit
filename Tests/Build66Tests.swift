import XCTest
@testable import Publit

/// Tester feedback, November 2026: Park & Ride to the nearest station, the kind of train for wheelchair
/// users, Paris metro and RER names.
final class Build66Tests: XCTestCase {
    private func plan(_ name: String) throws -> PlanResponse {
        try TransitousClient.makeDecoder().decode(PlanResponse.self, from: Fixtures.data(name))
    }

    // MARK: Park & Ride

    /// Gföhl → Krems Bahnhof with Park & Ride: the server drives 8 min into town and adds a 2-min bus.
    /// That is driving there, not a connection.
    func testDrivingMostOfTheWayIsNotParkAndRide() throws {
        let res = try plan("plan_park_ride_drive_most")
        XCTAssertFalse(res.itineraries.isEmpty)
        XCTAssertTrue(res.itineraries.allSatisfy { ParkAndRide.driveSeconds($0) > 0 })
        XCTAssertTrue(ParkAndRide.sensible(res.itineraries).isEmpty)
    }

    /// Gföhl → Wien Hbf with a 15-min drive: to Krems station, then the train. Kept.
    func testDriveToTheNearStationThenTrainIsKept() throws {
        let res = try plan("plan_park_ride")
        let kept = ParkAndRide.sensible(res.itineraries)
        XCTAssertEqual(kept.count, res.itineraries.count)
        for it in kept {
            XCTAssertLessThanOrEqual(ParkAndRide.driveSeconds(it), ParkAndRide.maxDriveSeconds)
            XCTAssertTrue(it.transitLegs.contains { VehicleKind.railModes.contains($0.mode) })
        }
    }

    func testDriveLimitStaysNearHome() {
        XCTAssertEqual(ParkAndRide.maxDriveSeconds, 900)
        XCTAssertLessThan(ParkAndRide.maxDriveSeconds, RouteOptions.defaultWalkMinutes * 60)
        XCTAssertFalse(ParkAndRide.fallbackNote.isEmpty)
    }

    // MARK: Train type and step-free vehicles

    func testRidesDecodeVehicleAccessAndTripEnd() throws {
        let res = try plan("plan_park_ride")
        let rides = res.itineraries.flatMap(\.transitLegs)
        XCTAssertTrue(rides.contains { $0.wheelchairAccessible != nil })
        XCTAssertTrue(rides.allSatisfy { $0.tripTo != nil })
        // Saved trips keep the new fields.
        let leg = try XCTUnwrap(rides.first)
        let again = try TransitousClient.makeDecoder().decode(Leg.self, from: JSONEncoder.withISODates.encode(leg))
        XCTAssertEqual(again.wheelchairAccessible, leg.wheelchairAccessible)
        XCTAssertEqual(again.tripTo, leg.tripTo)
    }

    func testTrainCategories() {
        XCTAssertEqual(VehicleKind.categoryName("RJX 161"), "Railjet Xpress")
        XCTAssertEqual(VehicleKind.categoryName("RJ 540"), "Railjet")
        XCTAssertEqual(VehicleKind.categoryName("IC 535"), "Intercity")
        XCTAssertEqual(VehicleKind.categoryName("ICE615"), "ICE")
        XCTAssertEqual(VehicleKind.categoryName("REX 9563"), "Regionalexpress")
        XCTAssertEqual(VehicleKind.categoryName("CJX 1923"), "Cityjet Xpress")
        XCTAssertNil(VehicleKind.categoryName("S7"))
        XCTAssertNil(VehicleKind.categoryName("12"))
        XCTAssertNil(VehicleKind.categoryName(""))
        XCTAssertNil(VehicleKind.categoryName(nil))
    }

    func testVehicleKindOfRealLegs() throws {
        let res = try plan("plan_park_ride")
        let regional = try XCTUnwrap(res.itineraries.flatMap(\.transitLegs).first { $0.mode == "REGIONAL_RAIL" })
        let kind = VehicleKind.of(regional)
        XCTAssertEqual(kind.modeLabel, L10n.t("Regional train"))
        switch regional.wheelchairAccessible {
        case "ACCESSIBLE": XCTAssertEqual(kind.access, .accessible); XCTAssertNotNil(kind.accessText)
        case "NOT_ACCESSIBLE": XCTAssertEqual(kind.access, .notAccessible); XCTAssertNotNil(kind.accessText)
        default: XCTAssertEqual(kind.access, .unknown); XCTAssertNil(kind.accessText)
        }
        // A bus gets no train category, even with a letter code in its name.
        let bus = try XCTUnwrap(res.itineraries.flatMap(\.transitLegs).first { $0.mode == "BUS" })
        XCTAssertNil(VehicleKind.of(bus).category)
    }

    // MARK: Paris

    func testParisBisLines() {
        XCTAssertEqual(TransitLabels.lineName("3B", mode: "SUBWAY"), "3bis")
        XCTAssertEqual(TransitLabels.lineName("7B", mode: "SUBWAY"), "7bis")
        XCTAssertEqual(TransitLabels.lineName("14", mode: "SUBWAY"), "14")
        XCTAssertEqual(TransitLabels.lineName("U1", mode: "SUBWAY"), "U1")
        XCTAssertEqual(TransitLabels.lineName("B", mode: "SUBWAY"), "B")
        XCTAssertEqual(TransitLabels.lineName("3B", mode: "BUS"), "3B")
    }

    func testRERMissionCodesGiveWayToTheTripEnd() {
        XCTAssertEqual(TransitLabels.direction(headsign: "NEGE", tripEnd: "Boissy-Saint-Léger"), "Boissy-Saint-Léger")
        XCTAssertEqual(TransitLabels.direction(headsign: "ZEMA", tripEnd: "Marne-la-Vallée Chessy"), "Marne-la-Vallée Chessy")
        XCTAssertEqual(TransitLabels.direction(headsign: "Nation", tripEnd: "Nation"), "Nation")
        XCTAssertEqual(TransitLabels.direction(headsign: "Porte Dauphine", tripEnd: "Somewhere"), "Porte Dauphine")
        // A real place in capitals that is the trip's end stays as it is.
        XCTAssertEqual(TransitLabels.direction(headsign: "BRIG", tripEnd: "Brig"), "BRIG")
        XCTAssertEqual(TransitLabels.direction(headsign: "NEGE", tripEnd: nil), "NEGE")
        XCTAssertNil(TransitLabels.direction(headsign: nil, tripEnd: "Nation"))
    }
}

private extension JSONEncoder {
    static var withISODates: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

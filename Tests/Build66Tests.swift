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

    // MARK: Train names (real field combinations from Transitous, 2026-11-14)

    private func name(_ short: String?, _ display: String?, _ long: String? = nil) -> String? {
        TransitLabels.trainName(short: short, display: display, longName: long)
    }

    func testTrainNamesFromEachFeedsHabits() {
        // DB: internal line number in the short name; the badge shows the category, as for other feeds.
        XCTAssertEqual(name("29", "ICE 1006"), "ICE")
        // Trenitalia: the category is the badge, the train beside it (unchanged).
        XCTAssertNil(name("FR", "FR 6649", "Frecciarossa"))
        // MÁV: empty short name, category only in the long name.
        XCTAssertEqual(name("", "xpress 66", "rjx 66"), "RJX 66")
        XCTAssertEqual(name("", "xpress 63", "rjx 63/64/65"), "RJX 63")
        XCTAssertEqual(name("", "InterCity 854", "IC TÓPART"), "InterCity 854")
        XCTAssertEqual(name("", "TGV INOUI 6615"), "TGV INOUI 6615")
        // Already right: left alone.
        XCTAssertNil(name("RJX 161", "RJX 161", "Lindau - Bregenz - Wien"))
        XCTAssertNil(name("RE1", "RE1 (4016)"))
        XCTAssertNil(name("IR16", "IR16"))
        XCTAssertNil(name("R19", "R19 (R 869)", "Praha – Česká Třebová – Brno"))
        XCTAssertNil(name("A", "A"))
        let ice = TestTrain(routeShortName: "29", displayName: "ICE 1006")
        XCTAssertEqual(ice.lineName, "ICE")
        XCTAssertEqual(ice.serviceDetail, "ICE 1006")
    }

    func testRailLegUsesTheTrainName() throws {
        var data = try XCTUnwrap(JSONSerialization.jsonObject(with: Fixtures.data("plan_park_ride")) as? [String: Any])
        var trips = try XCTUnwrap(data["itineraries"] as? [[String: Any]])
        var legs = try XCTUnwrap(trips[0]["legs"] as? [[String: Any]])
        let i = try XCTUnwrap(legs.firstIndex { ($0["mode"] as? String) == "LONG_DISTANCE" })
        legs[i]["routeShortName"] = ""
        legs[i]["displayName"] = "xpress 66"
        legs[i]["routeLongName"] = "rjx 66"
        trips[0]["legs"] = legs; data["itineraries"] = trips
        let res = try TransitousClient.makeDecoder().decode(PlanResponse.self, from: JSONSerialization.data(withJSONObject: data))
        let leg = try XCTUnwrap(res.itineraries[0].legs.first { $0.mode == "LONG_DISTANCE" })
        XCTAssertEqual(leg.lineName, "RJX 66")
        XCTAssertNil(leg.serviceDetail)
        XCTAssertEqual(VehicleKind.of(leg).category, "Railjet Xpress")
        // Buses keep their names untouched.
        let bus = try XCTUnwrap(res.itineraries[0].legs.first { $0.mode == "BUS" })
        XCTAssertEqual(bus.lineName, TransitLabels.clean(bus.routeShortName) ?? bus.lineName)
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

private struct TestTrain: RouteStyled {
    var mode = "HIGHSPEED_RAIL"
    var routeColor: String? = nil
    var routeTextColor: String? = nil
    var routeShortName: String?
    var displayName: String?
}

private extension JSONEncoder {
    static var withISODates: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

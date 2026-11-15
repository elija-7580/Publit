import XCTest
@testable import Publit

/// Deutschlandticket routes: local and regional transport only.
final class LocalTicketTests: XCTestCase {
    private func leg(_ mode: String, _ name: String? = nil, agency: String? = nil) -> Leg {
        let json = """
        {"mode":"\(mode)","from":{"name":"A","lat":48.1,"lon":11.5},"to":{"name":"B","lat":48.2,"lon":11.6},
         "duration":600,"startTime":"2026-11-15T10:00:00Z","endTime":"2026-11-15T10:10:00Z","scheduledStartTime":"2026-11-15T10:00:00Z","scheduledEndTime":"2026-11-15T10:10:00Z","realTime":false,"legGeometry":{"points":"","precision":6,"length":0},
         "routeShortName":\(name.map { "\"\($0)\"" } ?? "null"),"agencyName":\(agency.map { "\"\($0)\"" } ?? "null")}
        """
        return try! TransitousClient.makeDecoder().decode(Leg.self, from: Data(json.utf8))
    }

    func testCoversLocalAndRegionalOnly() {
        XCTAssertTrue(LocalTicket.covers(leg("WALK")))
        XCTAssertTrue(LocalTicket.covers(leg("BUS", "54")))
        XCTAssertTrue(LocalTicket.covers(leg("SUBURBAN", "S1")))
        XCTAssertTrue(LocalTicket.covers(leg("REGIONAL_RAIL", "RE 1")))
        XCTAssertTrue(LocalTicket.covers(leg("RAIL", "RB 33")))
        XCTAssertFalse(LocalTicket.covers(leg("HIGHSPEED_RAIL", "ICE 615")))
        XCTAssertFalse(LocalTicket.covers(leg("COACH", "N850")))
        XCTAssertFalse(LocalTicket.covers(leg("RAIL", "IC 2013")))
        XCTAssertFalse(LocalTicket.covers(leg("RAIL", "FLX 1240")))
        XCTAssertFalse(LocalTicket.covers(leg("RAIL", "1240", agency: "FlixTrain")))
    }

    func testSearchLeavesOutLongDistanceModes() {
        var o = RouteOptions()
        XCTAssertNil(o.transitModesValue)
        o.localTicket = true
        let modes = Set(o.transitModesValue!.split(separator: ",").map(String.init))
        XCTAssertTrue(modes.isSuperset(of: ["REGIONAL_RAIL", "SUBURBAN", "BUS", "TRAM", "SUBWAY"]))
        XCTAssertTrue(modes.isDisjoint(with: LocalTicket.excludedModes))
        o.modes.set(.bus, on: false)
        XCTAssertFalse(o.transitModesValue!.contains("BUS"))
        XCTAssertEqual(o.activeCount, 2)
        XCTAssertTrue(o.summary!.contains("Deutschlandticket"))
        // Old saved options have no flag.
        let old = try! JSONDecoder().decode(RouteOptions.self, from: Data(#"{"wheelchair":true}"#.utf8))
        XCTAssertFalse(old.localTicket)
    }

    func testRecognisesASavedDeutschlandticket() {
        XCTAssertTrue(LocalTicket.isDeutschlandticket("Deutschland-Ticket Job"))
        XCTAssertTrue(LocalTicket.isDeutschlandticket("D-Ticket"))
        XCTAssertFalse(LocalTicket.isDeutschlandticket("KlimaTicket Ö"))
    }
}

import XCTest
@testable import Publit

/// Own tickets (Deutschlandticket, KlimaTicket, GA …): routes only use rides the tickets cover.
final class OwnTicketTests: XCTestCase {
    private func leg(_ mode: String, _ name: String? = nil, agency: String? = nil,
                     from: String? = nil, to: String? = nil) -> Leg {
        func q(_ s: String?) -> String { s.map { "\"\($0)\"" } ?? "null" }
        let json = """
        {"mode":"\(mode)","from":{"name":"A","lat":48.1,"lon":11.5,"stopId":\(q(from))},"to":{"name":"B","lat":48.2,"lon":11.6,"stopId":\(q(to))},
         "duration":600,"startTime":"2026-11-15T10:00:00Z","endTime":"2026-11-15T10:10:00Z","scheduledStartTime":"2026-11-15T10:00:00Z","scheduledEndTime":"2026-11-15T10:10:00Z","realTime":false,"legGeometry":{"points":"","precision":6,"length":0},
         "routeShortName":\(q(name)),"agencyName":\(q(agency))}
        """
        return try! TransitousClient.makeDecoder().decode(Leg.self, from: Data(json.utf8))
    }

    private func trip(_ legs: [Leg]) -> Itinerary {
        Itinerary(id: "t", duration: 600, startTime: legs[0].startTime, endTime: legs[0].endTime, transfers: legs.count - 1, legs: legs)
    }

    // Real stop IDs from Transitous.
    let munich = "de-DELFI_de:09162:100:11:12", berlin = "de-DELFI_de:11000:900003200:3:54"
    let salzburg = "de-DELFI_at:45:50002", salzburgAT = "at-Railway-Current-Reference-Data-2026_at:45:50002:0:8"
    let wienHbf = "at-Railway-Current-Reference-Data-2026_at:49:1349:0:28", krems = "at-Railway-Current-Reference-Data-2026_at:43:3993:0:11"
    let wienU = "at-PTA-Eastern-Region-Flex-2026_at:49:491:0:5", airport = "at-Railway-Current-Reference-Data-2026_at:43:5764:0:3"
    let zurich = "ch-opentransportdataswiss26_ch:1:sloid:3000:8:15", bern = "ch-opentransportdataswiss26_ch:1:sloid:7000:6:12"
    let basel = "de-DELFI_ch:1:sloid:10", freiburg = "de-DELFI_de:08311:6508:3:1"

    func testStopArea() {
        XCTAssertEqual(StopArea(stopId: salzburg), StopArea(country: "at", state: 45))
        XCTAssertEqual(StopArea(stopId: krems), StopArea(country: "at", state: 43))
        XCTAssertEqual(StopArea(stopId: munich), StopArea(country: "de"))
        XCTAssertEqual(StopArea(stopId: zurich), StopArea(country: "ch"))
        XCTAssertEqual(StopArea(stopId: "de-DELFI_de:05113:9289_G"), StopArea(country: "de"))
        XCTAssertEqual(StopArea(stopId: "de-VBN_000000100063"), StopArea(country: "de"))
        XCTAssertNil(StopArea(stopId: nil))
        XCTAssertNil(StopArea(stopId: "12345"))
    }

    func testDeutschlandticketCoversLocalAndRegionalOnly() {
        let dt = OwnTicket.deutschlandticket
        XCTAssertTrue(dt.covers(leg("WALK")))
        XCTAssertTrue(dt.covers(leg("BUS", "54")))
        XCTAssertTrue(dt.covers(leg("SUBURBAN", "S1")))
        XCTAssertTrue(dt.covers(leg("REGIONAL_RAIL", "RE 1")))
        XCTAssertTrue(dt.covers(leg("RAIL", "RB 33")))
        XCTAssertFalse(dt.covers(leg("HIGHSPEED_RAIL", "ICE 615")))
        XCTAssertFalse(dt.covers(leg("COACH", "N850")))
        XCTAssertFalse(dt.covers(leg("RAIL", "IC 2013")))
        XCTAssertFalse(dt.covers(leg("RAIL", "FLX 1240")))
        XCTAssertFalse(dt.covers(leg("RAIL", "1240", agency: "FlixTrain")))
        // Across the border to Salzburg yes, within Austria no.
        XCTAssertTrue(dt.covers(leg("REGIONAL_RAIL", "RE5", from: munich, to: salzburg)))
        XCTAssertFalse(dt.covers(leg("REGIONAL_RAIL", "REX 2817", from: krems, to: wienHbf)))
    }

    func testBahnCard100AddsDBLongDistanceInGermany() {
        let bc = OwnTicket.bahncard100
        XCTAssertTrue(bc.covers(leg("HIGHSPEED_RAIL", "29", agency: "DB Fernverkehr AG", from: munich, to: berlin)))
        XCTAssertTrue(bc.covers(leg("BUS", "100", from: berlin, to: berlin)))
        XCTAssertFalse(bc.covers(leg("RAIL", "FLX 1240", agency: "FlixTrain", from: berlin, to: munich)))
        XCTAssertFalse(bc.covers(leg("HIGHSPEED_RAIL", "ICE 1211", from: munich, to: salzburg)))
        XCTAssertFalse(bc.covers(leg("HIGHSPEED_RAIL", "ICE 374", from: basel, to: freiburg)))
    }

    func testKlimaTicketCoversAllOfAustria() {
        let kt = OwnTicket.klimaticket
        XCTAssertTrue(kt.covers(leg("LONG_DISTANCE", "RJX 265", from: salzburgAT, to: wienHbf)))
        XCTAssertTrue(kt.covers(leg("SUBWAY", "U4", from: wienU, to: wienU)))
        XCTAssertFalse(kt.covers(leg("HIGHSPEED_RAIL", "ICE 1211", from: munich, to: salzburg)))
        XCTAssertFalse(kt.covers(leg("BUS", "CAT", agency: "City Air Terminal Betriebsgesellschaft m.b.H.", from: wienHbf, to: airport)))
        XCTAssertFalse(kt.covers(leg("BUS", "VAB 4", agency: "Österreichische Postbus AG", from: wienU, to: airport)))
        XCTAssertFalse(kt.covers(leg("NIGHT_RAIL", "NJ 466", from: wienHbf, to: salzburgAT)))
    }

    func testRegionalTicketsKeepToTheirStates() {
        let ride = leg("REGIONAL_RAIL", "REX 2817", from: krems, to: wienHbf)
        XCTAssertFalse(OwnTicket.vorRegion.covers(ride))
        XCTAssertTrue(OwnTicket.vorMetropolregion.covers(ride))
        XCTAssertFalse(OwnTicket.wienJahreskarte.covers(ride))
        XCTAssertTrue(OwnTicket.wienJahreskarte.covers(leg("SUBWAY", "U4", from: wienU, to: wienU)))
        XCTAssertTrue(OwnTicket.klimaticketSalzburg.covers(leg("BUS", "25", from: salzburgAT, to: salzburgAT)))
        XCTAssertFalse(OwnTicket.klimaticketSalzburg.covers(leg("LONG_DISTANCE", "RJX 265", from: salzburgAT, to: wienHbf)))
        // No stop IDs: a regional ticket cannot tell.
        XCTAssertFalse(OwnTicket.klimaticketTirol.covers(leg("BUS", "R")))
    }

    func testGACoversSwitzerland() {
        XCTAssertTrue(OwnTicket.generalabonnement.covers(leg("LONG_DISTANCE", "IC1", from: zurich, to: bern)))
        XCTAssertFalse(OwnTicket.generalabonnement.covers(leg("HIGHSPEED_RAIL", "ICE 374", from: basel, to: freiburg)))
    }

    func testAnyTicketMayCoverARide() {
        let it = trip([leg("HIGHSPEED_RAIL", "ICE 1211", from: munich, to: salzburg)])
        XCTAssertFalse(OwnTicket.covers(it, with: [.deutschlandticket, .klimaticket]))
        let it2 = trip([leg("REGIONAL_RAIL", "RE5", from: munich, to: salzburg),
                                          leg("LONG_DISTANCE", "RJX 265", from: salzburgAT, to: wienHbf)])
        XCTAssertTrue(OwnTicket.covers(it2, with: [.deutschlandticket, .klimaticket]))
        XCTAssertFalse(OwnTicket.covers(it2, with: [.deutschlandticket]))
        XCTAssertTrue(OwnTicket.covers(it2, with: []))
    }

    func testSearchLeavesOutModesNoTicketCovers() {
        var o = RouteOptions()
        XCTAssertNil(o.transitModesValue)
        o.tickets = [.deutschlandticket]
        var modes = Set(o.transitModesValue!.split(separator: ",").map(String.init))
        XCTAssertTrue(modes.isSuperset(of: ["REGIONAL_RAIL", "SUBURBAN", "BUS", "TRAM", "SUBWAY"]))
        XCTAssertTrue(modes.isDisjoint(with: ["HIGHSPEED_RAIL", "LONG_DISTANCE", "NIGHT_RAIL", "COACH", "AIRPLANE"]))
        o.tickets.insert(.klimaticket)
        modes = Set(o.transitModesValue!.split(separator: ",").map(String.init))
        XCTAssertTrue(modes.contains("HIGHSPEED_RAIL"))
        XCTAssertFalse(modes.contains("COACH"))
        o.tickets = [.deutschlandticket]
        o.modes.set(.bus, on: false)
        XCTAssertFalse(o.transitModesValue!.contains("BUS"))
        XCTAssertEqual(o.activeCount, 2)
        XCTAssertTrue(o.summary!.contains("Deutschlandticket"))
        XCTAssertNotEqual(o.key, RouteOptions().key)
    }

    func testStoredOptions() throws {
        // Builds 72–81: one Deutschlandticket switch.
        let old = try JSONDecoder().decode(RouteOptions.self, from: Data(#"{"wheelchair":true,"localTicket":true}"#.utf8))
        XCTAssertEqual(old.tickets, [.deutschlandticket])
        let none = try JSONDecoder().decode(RouteOptions.self, from: Data(#"{"wheelchair":true}"#.utf8))
        XCTAssertTrue(none.tickets.isEmpty)
        var o = RouteOptions(); o.tickets = [.klimaticket, .generalabonnement]
        let back = try JSONDecoder().decode(RouteOptions.self, from: JSONEncoder().encode(o))
        XCTAssertEqual(back.tickets, o.tickets)
    }

    func testRecognisesSavedTickets() {
        XCTAssertEqual(OwnTicket.recognise("Deutschland-Ticket Job"), .deutschlandticket)
        XCTAssertEqual(OwnTicket.recognise("D-Ticket"), .deutschlandticket)
        XCTAssertEqual(OwnTicket.recognise("KlimaTicket Ö Classic"), .klimaticket)
        XCTAssertEqual(OwnTicket.recognise("VOR KlimaTicket MetropolRegion"), .vorMetropolregion)
        XCTAssertEqual(OwnTicket.recognise("KlimaTicket Region"), .vorRegion)
        XCTAssertEqual(OwnTicket.recognise("KlimaTicket OÖ"), .klimaticketOOE)
        XCTAssertEqual(OwnTicket.recognise("BahnCard 100"), .bahncard100)
        XCTAssertEqual(OwnTicket.recognise("GA 2. Klasse"), .generalabonnement)
        XCTAssertNil(OwnTicket.recognise("Sparschiene Wien–Graz"))
        XCTAssertNil(OwnTicket.recognise("Gate 4"))
    }
}

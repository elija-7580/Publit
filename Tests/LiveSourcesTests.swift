import XCTest
@testable import Publit

final class LiveSourcesTests: XCTestCase {
    private let t0 = 1_791_360_000.0   // 2026-10-07 08:00 UTC

    private func date(_ m: Double) -> Date { Date(timeIntervalSince1970: t0 + m * 60) }

    private func leg(_ mode: String, start: Double, end: Double, name: String? = nil, realTime: Bool = false,
                     cancelled: Bool? = nil) throws -> Leg {
        func iso(_ m: Double) -> String { DateParsing.format(date(m)) }
        let line = name.map { ",\"routeShortName\":\"\($0)\"" } ?? ""
        let cancel = cancelled.map { ",\"cancelled\":\($0)" } ?? ""
        let json = """
        {"mode":"\(mode)","from":{"name":"A","lat":48.2,"lon":16.37},"to":{"name":"B","lat":48.21,"lon":16.38},
         "duration":\(Int((end - start) * 60)),"startTime":"\(iso(start))","endTime":"\(iso(end))",
         "scheduledStartTime":"\(iso(start))","scheduledEndTime":"\(iso(end))",
         "realTime":\(realTime)\(line)\(cancel),"legGeometry":{"points":"","precision":6,"length":0}}
        """
        return try TransitousClient.makeDecoder().decode(Leg.self, from: Data(json.utf8))
    }

    private func itinerary(_ legs: [Leg]) -> Itinerary {
        Itinerary(id: "x", duration: Int(legs.last!.endTime.timeIntervalSince(legs.first!.startTime)),
                  startTime: legs.first!.startTime, endTime: legs.last!.endTime, transfers: 0, legs: legs)
    }

    private func json(_ s: String) throws -> Any { try JSONSerialization.jsonObject(with: Data(s.utf8)) }

    func testLineNamesMatchAcrossOperators() {
        XCTAssertEqual(LiveMatch.key("Bus 404"), "404")
        XCTAssertEqual(LiveMatch.key("S 4 (Zug-Nr. 5197)"), "s4")
        XCTAssertEqual(LiveMatch.key("13_UN"), "13")
        XCTAssertEqual(LiveMatch.key("Elizabeth line"), "elizabeth")
        XCTAssertEqual(LiveMatch.key("Tram 1"), "1")
        XCTAssertTrue(LiveMatch.sameLine(["S4"], ["S 4", "4", "5197"]))
        XCTAssertTrue(LiveMatch.sameLine(["REX 7 2345"], ["REX 7", "2345"]))
        XCTAssertFalse(LiveMatch.sameLine(["U4"], ["U1"]))
        XCTAssertFalse(LiveMatch.sameLine(["13A"], ["13"]))
    }

    func testBestMatchNeedsLineAndTime() {
        let ride = LiveRide(point: LatLon(lat: 48.2, lon: 16.37), stopId: nil, stopName: "A", lines: ["U1"],
                            headsign: nil, scheduled: date(10), mode: "SUBWAY")
        let deps = [LiveDeparture(lines: ["U1"], scheduled: date(5), expected: date(6)),
                    LiveDeparture(lines: ["U1"], scheduled: date(10), expected: date(13)),
                    LiveDeparture(lines: ["U4"], scheduled: date(10), expected: date(10))]
        XCTAssertEqual(LiveMatch.best(for: ride, in: deps)?.expected, date(13))
        XCTAssertNil(LiveMatch.best(for: ride, in: [LiveDeparture(lines: ["U1"], scheduled: date(20))]))
        // Countdown-only boards: the nearest live time not long before the timetable time.
        let counted = [LiveDeparture(lines: ["1"], expected: date(12)), LiveDeparture(lines: ["1"], expected: date(25))]
        let tram = LiveRide(point: ride.point, stopId: nil, stopName: "A", lines: ["1"], headsign: nil, scheduled: date(10), mode: "TRAM")
        XCTAssertEqual(LiveMatch.best(for: tram, in: counted)?.expected, date(12))
    }

    func testMergeMovesRideAndFollowingWalk() throws {
        let it = itinerary([try leg("WALK", start: 0, end: 5), try leg("BUS", start: 5, end: 20, name: "404"),
                            try leg("WALK", start: 20, end: 25)])
        let fix = LiveFix(departure: date(9), alerts: [Alert(headerText: "Umleitung", descriptionText: "Wegen Bauarbeiten", url: nil)],
                          source: "ÖBB")
        let out = LiveMerge.merge(it, fixes: [1: fix])
        XCTAssertEqual(out.legs[1].startTime, date(9))
        XCTAssertEqual(out.legs[1].endTime, date(24))
        XCTAssertTrue(out.legs[1].realTime)
        XCTAssertEqual(out.legs[1].liveSource, "ÖBB")
        XCTAssertEqual(out.legs[1].alerts?.count, 1)
        XCTAssertEqual(out.legs[0].endTime, date(9))
        XCTAssertEqual(out.legs[2].endTime, date(29))
        XCTAssertEqual(out.endTime, date(29))
        XCTAssertEqual(out.duration, 29 * 60)
        XCTAssertEqual(LiveOverlay.sourceNames(out), ["ÖBB"])
        // The same alert twice is listed once.
        XCTAssertEqual(LiveMerge.merge(out.legs[1], fix).alerts?.count, 1)
    }

    func testLiveTimesFromTransitousWin() throws {
        let live = try leg("BUS", start: 5, end: 20, name: "404", realTime: true)
        let out = LiveMerge.merge(live, LiveFix(departure: date(15), cancelled: true, source: "ÖBB"))
        XCTAssertEqual(out.startTime, date(5))
        XCTAssertNotEqual(out.cancelled, true)
        XCTAssertNil(out.liveSource)
    }

    func testCancelledWalkDoesNotCancelTheTrip() throws {
        let it = itinerary([try leg("WALK", start: 0, end: 5, cancelled: true), try leg("BUS", start: 5, end: 20, name: "404")])
        XCTAssertFalse(it.isCancelled)
        let bus = itinerary([try leg("WALK", start: 0, end: 5), try leg("BUS", start: 5, end: 20, name: "404", cancelled: true)])
        XCTAssertTrue(bus.isCancelled)
        XCTAssertEqual(TripStatus.at(date(-10), bus).phase, .cancelled)
    }

    func testHafasBoard() throws {
        let res = try XCTUnwrap(json("""
        {"common":{"prodL":[{"name":"Bus N1","number":"N1","cls":64,"prodCtx":{"line":"N1","num":"910582"}},
                            {"name":"U1","number":"U1","cls":256}],
                   "himL":[{"head":"Bauarbeiten - Zugausfall","text":"Wegen Bauarbeiten <br>zwischen <b>Wien Hbf</b>","prio":100,"prod":560,
                            "sDate":"20260907","sTime":"000000","eDate":"20271031","eTime":"235900"},
                           {"head":"Umleitung","text":"Linie N1 f&auml;hrt um","prio":10,"prod":64}]},
         "jnyL":[{"prodX":0,"date":"20261018","dirTxt":"Sieglanger","stbStop":{"dTimeS":"233000","dTimeR":"233200","dTZOffset":120,
                   "dPltfS":{"type":"ST","txt":"D"}},"msgL":[{"type":"HIM","himX":1}]},
                 {"prodX":1,"date":"20261018","dirTxt":"Oberlaa","stbStop":{"dTimeS":"01001500","dTZOffset":120,"dCncl":true},
                   "msgL":[{"type":"HIM","himX":0,"tagL":["SUM_GLB_HDR_H3"]},{"type":"HIM","himX":0}]}]}
        """) as? [String: Any])
        let deps = HafasSource.parseBoard(res)
        XCTAssertEqual(deps.count, 2)
        XCTAssertEqual(deps[0].scheduled, ISO8601DateFormatter().date(from: "2026-10-18T21:30:00Z"))
        XCTAssertEqual(deps[0].expected, ISO8601DateFormatter().date(from: "2026-10-18T21:32:00Z"))
        XCTAssertEqual(deps[0].track, "D")
        XCTAssertEqual(deps[0].alerts.first?.headerText, "Umleitung")
        XCTAssertEqual(deps[0].alerts.first?.severityLevel, "SEVERE")
        XCTAssertTrue(deps[0].lines.contains("N1"))
        // Next day, cancelled, no live time; the rail works note is not about the U-Bahn (product mask).
        XCTAssertEqual(deps[1].scheduled, ISO8601DateFormatter().date(from: "2026-10-18T22:15:00Z"))
        XCTAssertNil(deps[1].expected)
        XCTAssertTrue(deps[1].cancelled)
        XCTAssertTrue(deps[1].alerts.isEmpty)
        let him = try XCTUnwrap(HafasSource.alert(["head": "Bauarbeiten", "text": "Wegen <b>Bauarbeiten</b><br>zwischen A &#60;=&#62; B"]))
        XCTAssertEqual(him.descriptionText, "Wegen Bauarbeiten\nzwischen A <=> B")
        XCTAssertEqual(HafasSource.parseNearest(["locL": [["lid": "far", "dist": 200], ["lid": "near", "dist": 40]]]), "near")
    }

    func testWienerLinienMonitor() throws {
        XCTAssertEqual(WienerLinienSource.diva("at-PTA-Eastern-Region-Flex-2026_Pat:49:1198"), "60201198")
        XCTAssertNil(WienerLinienSource.diva("de-DELFI_de:09162:2"))
        let root = try XCTUnwrap(json("""
        {"data":{"monitors":[{"lines":[{"name":"U4","towards":"Hütteldorf","departures":{"departure":[
            {"departureTime":{"timePlanned":"2026-10-18T23:40:00.000+0200","timeReal":"2026-10-18T23:41:28.000+0200","countdown":4}},
            {"departureTime":{"timePlanned":"2026-10-18T23:50:00.000+0200","countdown":14}}]}}]}],
         "trafficInfos":[{"refTrafficInfoCategoryId":2,"title":"U4 Störung","description":"Unregelmäßige Intervalle","relatedLines":["U4"]},
                         {"refTrafficInfoCategoryId":1,"title":"Aufzug","description":"außer Betrieb","relatedLines":["U4"]}]}}
        """) as? [String: Any])
        let deps = WienerLinienSource.parseMonitor(root)
        XCTAssertEqual(deps.count, 2)
        XCTAssertEqual(deps[0].expected, ISO8601DateFormatter().date(from: "2026-10-18T21:41:28Z"))
        XCTAssertNil(deps[1].expected)
        XCTAssertEqual(deps[0].alerts.map(\.headerText), ["U4 Störung"])
    }

    func testACTVPassages() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-18T21:38:00Z"))   // 23:38 in Venice
        let list = try json("""
        [{"line":"13_UN","destination":"F.TE NOVE","time":"2'","real":true,"timingPoints":[{"time":"23:40","stop":"Treporti"}]},
         {"line":"12_UN","destination":"BURANO","time":"00:10","real":false,"timingPoints":[{"time":"00:10","stop":"Treporti"}]}]
        """)
        let deps = ACTVSource.parsePassages(list, now: now)
        XCTAssertEqual(deps.count, 2)
        XCTAssertEqual(deps[0].scheduled, now.addingTimeInterval(120))
        XCTAssertEqual(deps[0].expected, now.addingTimeInterval(120))
        XCTAssertNil(deps[1].expected)
        XCTAssertEqual(deps[1].scheduled, now.addingTimeInterval(32 * 60))   // after midnight
        XCTAssertEqual(ACTVSource.parseStops(try json("""
        [{"name":"5069-Treporti-nav-web","latitude":45.46,"longitude":12.45}]
        """)).first?.id, "5069-Treporti-nav-web")
    }

    func testSLDepartures() throws {
        let root = try XCTUnwrap(json("""
        {"departures":[{"destination":"Uppsala C","state":"EXPECTED","scheduled":"2026-10-18T23:38:00","expected":"2026-10-18T23:41:00",
                        "stop_point":{"designation":"2"},"line":{"designation":"40","transport_mode":"TRAIN"},
                        "deviations":[{"importance_level":5,"message":"Signalfel"}]},
                       {"destination":"Hjulsta","state":"CANCELLED","scheduled":"2026-10-18T23:45:00","expected":"2026-10-18T23:45:00",
                        "line":{"designation":"10","transport_mode":"METRO"},"deviations":[]}],
         "stop_deviations":[{"importance_level":3,"message":"Hissen ur funktion","scope":{"lines":[{"designation":"40"}]}}]}
        """) as? [String: Any])
        let deps = SLSource.parseDepartures(root)
        XCTAssertEqual(deps[0].expected, ISO8601DateFormatter().date(from: "2026-10-18T21:41:00Z"))
        XCTAssertEqual(deps[0].track, "2")
        XCTAssertEqual(deps[0].alerts.map(\.headerText), ["Signalfel", "Hissen ur funktion"])
        XCTAssertTrue(deps[1].cancelled)
        XCTAssertTrue(deps[1].alerts.isEmpty)
    }

    func testTfLStatus() throws {
        let lines = TfLStatusSource.parseStatus(try json("""
        [{"id":"bakerloo","name":"Bakerloo","lineStatuses":[{"statusSeverity":9,"statusSeverityDescription":"Minor Delays",
           "reason":"Bakerloo Line: Minor delays due to train cancellations. ",
           "validityPeriods":[{"fromDate":"2026-10-18T20:48:42Z","toDate":"2026-10-19T00:29:00Z"}]}]},
         {"id":"victoria","name":"Victoria","lineStatuses":[{"statusSeverity":10,"statusSeverityDescription":"Good Service"}]}]
        """))
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0].alerts.first?.headerText, "Bakerloo: Minor Delays")
        XCTAssertEqual(lines[0].alerts.first?.impactPeriod?.count, 1)
        XCTAssertTrue(lines[1].alerts.isEmpty)
        XCTAssertTrue(LiveMatch.sameLine(["Bakerloo"], lines[0].names))
    }

    func testOverlayStaysOutsideCoveredAreas() async throws {
        // Munich: no extra source, nothing is asked and the routes come back unchanged.
        let json = """
        {"mode":"BUS","from":{"name":"A","lat":48.13,"lon":11.57},"to":{"name":"B","lat":48.14,"lon":11.58},
         "duration":600,"startTime":"\(DateParsing.format(Date()))","endTime":"\(DateParsing.format(Date().addingTimeInterval(600)))",
         "scheduledStartTime":"\(DateParsing.format(Date()))","scheduledEndTime":"\(DateParsing.format(Date().addingTimeInterval(600)))",
         "realTime":false,"routeShortName":"52","legGeometry":{"points":"","precision":6,"length":0}}
        """
        let bus = try TransitousClient.makeDecoder().decode(Leg.self, from: Data(json.utf8))
        XCTAssertFalse(LiveOverlay.wanted(LiveOverlay.ride(bus), now: Date()))
        let it = itinerary([bus])
        let started = Date()
        let out = await LiveOverlay.apply([it])
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.5)
        XCTAssertEqual(out.first?.startTime, it.startTime)
    }
}

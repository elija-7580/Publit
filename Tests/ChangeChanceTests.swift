import XCTest
@testable import Publit

/// Measured change chances (SmartRouting.chance with DelayHistory).
final class ChangeChanceTests: XCTestCase {
    private let t0 = 1_791_360_000.0   // Wednesday 7 Oct 2026, 10:00 in Vienna (stops carry that zone)

    private func leg(_ mode: String, from: String, to: String, start: Int, end: Int, delay: Int = 0, realTime: Bool = false,
                     route: String? = "de-T_R1", trip: String? = nil, fromTrack: String? = nil, toTrack: String? = nil,
                     toScheduledTrack: String? = nil, cancelled: Bool = false) throws -> Leg {
        func iso(_ m: Int, _ d: Int = 0) -> String { DateParsing.format(Date(timeIntervalSince1970: t0 + Double(m) * 60 + Double(d))) }
        func opt(_ k: String, _ v: String?) -> String { v.map { ",\"\(k)\":\"\($0)\"" } ?? "" }
        let json = """
        {"mode":"\(mode)","from":{"name":"\(from)","stopId":"de-T_\(from)","lat":48,"lon":11,"tz":"Europe/Vienna"\(opt("track", fromTrack))\(opt("scheduledTrack", fromTrack))},
         "to":{"name":"\(to)","stopId":"de-T_\(to)","lat":48,"lon":11,"tz":"Europe/Vienna"\(opt("track", toTrack))\(opt("scheduledTrack", toScheduledTrack ?? toTrack))},
         "duration":\((end - start) * 60),"startTime":"\(iso(start, delay))","endTime":"\(iso(end, delay))",
         "scheduledStartTime":"\(iso(start))","scheduledEndTime":"\(iso(end))","cancelled":\(cancelled),
         "realTime":\(realTime)\(opt("routeId", route)),"tripId":"\(trip ?? "\(mode)-\(from)-\(start)")","legGeometry":{"points":"","precision":6,"length":0}}
        """
        return try TransitousClient.makeDecoder().decode(Leg.self, from: Data(json.utf8))
    }

    private let table = DelayHistory.Table(text: """
    D|2026-11-17|30|2026-10-19
    R|de-T_R1|w|-60,0,90,240,480|-60,0,60,180,420|10|500
    S|de-T_R1|de-T_B|w|0,60,180,360,600|0,60,180,360,600|10|120
    R|de-T_R2|w|-30,0,0,30,60|-30,0,0,30,60|0|300
    R|de-T_R3|w|0,60,180,300,600|0,60,180,300,600|0|200
    O|de-T|Bahn A|w|0,0,30,60,120|0,0,30,60,120|0|900
    M|BUS|w|-30,0,60,120,240|-30,0,30,90,180|20|5000
    H|REGIONAL_RAIL|5|-30,-10,0,10,30|800
    H|REGIONAL_RAIL|60|-120,-60,0,120,300|800
    """)

    private func history(_ c: String?) -> DelayHistory.Table? { c == "de" ? table : nil }

    func testSharedVectorsMatchThePythonReference() throws {
        struct Case: Decodable { let name: String; let gap, walk, cin, cout: Double; let arr, dep: [Double]; let n: Int?; let expected: Double }
        struct File: Decodable { let cases: [Case] }
        let file = try JSONDecoder().decode(File.self, from: Fixtures.data("change-chance-vectors"))
        XCTAssertFalse(file.cases.isEmpty)
        for c in file.cases {
            let p = SmartRouting.onTime(gap: c.gap, arrival: DelayHistory.Dist(c.arr)!, departure: DelayHistory.Dist(c.dep)!,
                                        walk: WalkModel.prior.samples(TransferWalk(plannedSeconds: c.walk)))
            var v = (1 - c.cin) * (1 - c.cout) * p
            if let n = c.n { v = SmartRouting.cap(v, observations: n) }
            XCTAssertEqual(v, c.expected, accuracy: 0.0001, c.name)
        }
    }

    func testTableFallsBackFromStopToRouteToOperatorToMode() {
        XCTAssertEqual(table.date, "2026-11-17")
        XCTAssertEqual(table.row(routeId: "de-T_R1", stopId: "de-T_B", agency: nil, mode: "BUS", window: "w")?.observations, 120)
        XCTAssertEqual(table.row(routeId: "de-T_R1", stopId: "de-T_X", agency: nil, mode: "BUS", window: "w")?.observations, 500)
        XCTAssertEqual(table.row(routeId: "de-T_R9", stopId: nil, agency: "Bahn A", mode: "BUS", window: "w")?.observations, 900)
        XCTAssertEqual(table.row(routeId: "de-T_R9", stopId: nil, agency: "Other", mode: "BUS", window: "w")?.observations, 5000)
        XCTAssertNil(table.row(routeId: "de-T_R9", stopId: nil, agency: nil, mode: "TRAM", window: "w"))
        XCTAssertNil(table.row(routeId: "de-T_R1", stopId: nil, agency: nil, mode: "TRAM", window: "p"))
        XCTAssertEqual(DelayHistory.country(ofId: "de-DELFI_de:09162:1"), "de")
        XCTAssertNil(DelayHistory.country(ofId: nil))
    }

    func testWindows() {
        let utc = TimeZone(identifier: "UTC")!
        func d(_ day: Int, _ h: Int) -> Date { Date(timeIntervalSince1970: 1_794_787_200 + Double(day * 86400 + h * 3600)) } // Mon 16 Nov 2026 00:00 UTC
        XCTAssertEqual(DelayHistory.window(d(0, 7), timeZone: utc), "p")
        XCTAssertEqual(DelayHistory.window(d(0, 12), timeZone: utc), "w")
        XCTAssertEqual(DelayHistory.window(d(5, 12), timeZone: utc), "e")
        XCTAssertEqual(DelayHistory.window(d(5, 23), timeZone: utc), "n")
    }

    private func change(_ a: Leg, _ b: Leg, now: Date? = nil, walk: TransferWalk = TransferWalk(plannedSeconds: 120)) -> (chance: Double, source: SmartRouting.Change.Source) {
        SmartRouting.chance(incoming: a, outgoing: b, walk: walk, at: now ?? Date(timeIntervalSince1970: t0 - 7200), history: history)
    }

    func testUsesHistoryOfBothVehicles() throws {
        let feeder = try leg("REGIONAL_RAIL", from: "A", to: "B", start: 0, end: 30)
        let punctual = try leg("BUS", from: "B", to: "C", start: 35, end: 50, route: "de-T_R2")
        let late = try leg("BUS", from: "B", to: "C", start: 35, end: 50, route: "de-T_R3")
        let p = change(feeder, punctual), l = change(feeder, late)
        // Feeder from the stop row (120 observations), connection from its route.
        XCTAssertEqual(p.source, .history(observations: 120))
        XCTAssertLessThan(p.chance, l.chance, "a connection that often leaves late helps")
        XCTAssertGreaterThan(p.chance, 0.3)
        XCTAssertLessThan(p.chance, 0.95)
    }

    func testLiveForecastIsSurerShortlyBefore() throws {
        // 3 min late now; 4 min scheduled gap minus 2 min walk: tight but likely.
        let feeder = try leg("REGIONAL_RAIL", from: "A", to: "B", start: 0, end: 30, delay: 60, realTime: true)
        let next = try leg("BUS", from: "B", to: "C", start: 34, end: 50, route: "de-T_R2")
        let arrival = Date(timeIntervalSince1970: t0 + 30 * 60 + 60)
        let soon = change(feeder, next, now: arrival.addingTimeInterval(-5 * 60))
        let later = change(feeder, next, now: arrival.addingTimeInterval(-60 * 60))
        XCTAssertGreaterThan(soon.chance, later.chance)
        XCTAssertGreaterThan(soon.chance, 0.8)
    }

    func testPlatformChangeAndLiftsMakeItHarder() throws {
        let feeder = try leg("REGIONAL_RAIL", from: "A", to: "B", start: 0, end: 30, toTrack: "5", toScheduledTrack: "2")
        let same = try leg("REGIONAL_RAIL", from: "A", to: "B", start: 0, end: 30, toTrack: "2")
        let next = try leg("BUS", from: "B", to: "C", start: 34, end: 50, route: "de-T_R2")
        let moved = TransferWalk(incoming: feeder, walks: [], outgoing: next)
        XCTAssertTrue(moved.platformChanged)
        XCTAssertFalse(moved.stationChange)
        XCTAssertLessThan(change(feeder, next, walk: moved).chance, change(same, next, walk: TransferWalk(incoming: same, walks: [], outgoing: next)).chance)
        let plain = TransferWalk(plannedSeconds: 120)
        var lifts = plain; lifts.elevators = 2; lifts.levels = 3; lifts.bigStation = true
        XCTAssertGreaterThan(WalkModel.prior.expectedSeconds(lifts), WalkModel.prior.expectedSeconds(plain) + 60)
    }

    func testThroughRunCancellationAndFallback() throws {
        let a = try leg("REGIONAL_RAIL", from: "A", to: "B", start: 0, end: 30, trip: "T1")
        let b = try leg("REGIONAL_RAIL", from: "B", to: "C", start: 31, end: 50, trip: "T1")
        XCTAssertEqual(change(a, b).source, .throughRun)
        XCTAssertEqual(change(a, b).chance, 1)
        let gone = try leg("BUS", from: "B", to: "C", start: 40, end: 50, route: "de-T_R2", cancelled: true)
        XCTAssertLessThan(change(a, gone).chance, 0.05)
        // No table for this country: the old rule of thumb, marked as estimate.
        let x = try leg("TRAM", from: "A", to: "B", start: 0, end: 10, route: "at-X_1")
        let y = try leg("TRAM", from: "B", to: "C", start: 14, end: 20, route: "at-X_2")
        let est = change(x, y)
        XCTAssertEqual(est.source, .estimate)
        XCTAssertEqual(est.chance, SmartRouting.chance(spareMinutes: 2, walkSeconds: 120, incoming: x), accuracy: 0.0001)
    }

    func testFewObservationsAreNeverNearlyCertain() {
        XCTAssertEqual(SmartRouting.cap(1, observations: 30), 1 - 1.0 / 32, accuracy: 1e-9)
        XCTAssertEqual(SmartRouting.cap(0.5, observations: 30), 0.5)
    }

    func testStoreKeepsNewerTable() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = DelayHistoryStore(cacheDirectory: dir)
        XCTAssertTrue(store.install(text: "D|2026-11-17|30|x\nM|BUS|w|0,0,0,0,0|0,0,0,0,0|0|100", country: "de"))
        XCTAssertFalse(store.install(text: "D|2026-11-10|30|x\nM|BUS|w|0,0,0,0,0|0,0,0,0,0|0|100", country: "de"))
        XCTAssertFalse(store.install(text: "garbage", country: "de"))
        XCTAssertEqual(DelayHistoryStore(cacheDirectory: dir).table(country: "de")?.date, "2026-11-17")
    }
}

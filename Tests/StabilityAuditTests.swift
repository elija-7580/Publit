// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich
import XCTest
@testable import Publit

/// Stability review, 27 Nov 2026: wrong live times from the other direction, "Later connections"
/// lost on a refresh, one unreadable entry failing a whole answer.
final class StabilityAuditTests: XCTestCase {
    private let t0 = 1_791_360_000.0   // 2026-10-07 08:00 UTC
    private func date(_ m: Double) -> Date { Date(timeIntervalSince1970: t0 + m * 60) }
    private func iso(_ m: Double) -> String { DateParsing.format(date(m)) }

    private func legJSON(_ mode: String, start: Double, end: Double, trip: String? = nil) -> String {
        let id = trip.map { ",\"tripId\":\"\($0)\",\"routeShortName\":\"\($0)\"" } ?? ""
        return """
        {"mode":"\(mode)","from":{"name":"A","lat":48.2,"lon":16.37},"to":{"name":"B","lat":48.3,"lon":16.5},
         "duration":\(Int((end - start) * 60)),"startTime":"\(iso(start))","endTime":"\(iso(end))",
         "scheduledStartTime":"\(iso(start))","scheduledEndTime":"\(iso(end))",
         "realTime":false\(id),"legGeometry":{"points":"","precision":6,"length":0}}
        """
    }

    private func routeJSON(_ id: String, mode: String = "SUBWAY", start: Double, end: Double) -> String {
        """
        {"id":"\(id)","duration":\(Int((end - start) * 60)),"startTime":"\(iso(start))","endTime":"\(iso(end))",
         "transfers":0,"legs":[\(legJSON(mode, start: start, end: end, trip: mode == "WALK" ? nil : id))]}
        """
    }

    private func route(_ id: String, mode: String = "SUBWAY", start: Double, end: Double) throws -> Itinerary {
        try TransitousClient.makeDecoder().decode(Itinerary.self, from: Data(routeJSON(id, mode: mode, start: start, end: end).utf8))
    }

    // MARK: Live times of the right direction

    private func ride(_ headsign: String?, lines: [String] = ["U4"]) -> LiveRide {
        LiveRide(point: LatLon(lat: 48.2, lon: 16.37), stopId: nil, stopName: "Schwedenplatz", lines: lines,
                 headsign: headsign, scheduled: date(10), mode: "SUBWAY")
    }

    /// Both directions of a line leave a station in the same minute: the ride gets its own train's delay.
    func testLiveTimeComesFromTheRidesDirection() {
        let board = [LiveDeparture(lines: ["U4"], destination: "HEILIGENSTADT", scheduled: date(10), expected: date(17)),
                     LiveDeparture(lines: ["U4"], destination: "HÜTTELDORF", scheduled: date(10), expected: date(10))]
        XCTAssertEqual(LiveMatch.best(for: ride("Hütteldorf"), in: board)?.expected, date(10))
        XCTAssertEqual(LiveMatch.best(for: ride("Wien Heiligenstadt"), in: board)?.expected, date(17))
        XCTAssertEqual(LiveMatch.best(for: ride("Hütteldorf"), in: board.reversed())?.expected, date(10))
    }

    /// The other direction's cancellation is not this ride's.
    func testOtherDirectionsCancellationDoesNotCancelTheRide() {
        let board = [LiveDeparture(lines: ["U4"], destination: "Heiligenstadt", scheduled: date(10), cancelled: true),
                     LiveDeparture(lines: ["U4"], destination: "Hütteldorf", scheduled: date(11), expected: date(12))]
        let hit = LiveMatch.best(for: ride("Hütteldorf"), in: board)
        XCTAssertEqual(hit?.cancelled, false)
        XCTAssertEqual(hit?.expected, date(12))
        // Only the other direction is on the board: no live time rather than the wrong one.
        XCTAssertNil(LiveMatch.best(for: ride("Hütteldorf"), in: [board[0], LiveDeparture(lines: ["U4"], destination: "Hütteldorf", scheduled: date(30))]))
    }

    /// Unknown or unrecognisable directions change nothing: the nearest timetable time wins as before.
    func testUnknownDirectionKeepsTheNearestDeparture() {
        let board = [LiveDeparture(lines: ["U4"], destination: "Depot", scheduled: date(10.5), expected: date(12)),
                     LiveDeparture(lines: ["U4"], destination: "Betriebsbahnhof", scheduled: date(10), expected: date(11))]
        XCTAssertEqual(LiveMatch.best(for: ride("Hütteldorf"), in: board)?.expected, date(11))
        XCTAssertEqual(LiveMatch.best(for: ride(nil), in: board)?.expected, date(11))
        let unnamed = [LiveDeparture(lines: ["U4"], scheduled: date(10), expected: date(13))]
        XCTAssertEqual(LiveMatch.best(for: ride("Hütteldorf"), in: unnamed)?.expected, date(13))
    }

    func testDirectionAgreement() {
        XCTAssertEqual(LiveMatch.direction("Hütteldorf", "HÜTTELDORF "), 3)
        XCTAssertEqual(LiveMatch.direction("Wien Hütteldorf", "Hütteldorf"), 2)
        XCTAssertEqual(LiveMatch.direction("Karlsplatz U", "Oper, Karlsplatz U"), 2)
        XCTAssertEqual(LiveMatch.direction("Bahnhof Meidling", "Wien Meidling"), 1)
        // A shared city name or "Bahnhof" says nothing about the direction.
        XCTAssertEqual(LiveMatch.direction("Wien Oberlaa", "Wien Leopoldau"), 0)
        XCTAssertEqual(LiveMatch.direction("Floridsdorf Bahnhof", "Hauptbahnhof Bahnhof Süd"), 0)
        XCTAssertEqual(LiveMatch.direction("Hütteldorf", nil), 0)
        XCTAssertEqual(LiveMatch.direction("Weißgerberlände", "Weissgerberlaende"), 0)
        XCTAssertEqual(LiveMatch.direction("Weißgerberlände", "WEISSGERBERLÄNDE"), 3)
    }

    // MARK: "Later connections" through a refresh

    func testLaterPagesStayThroughARefresh() throws {
        let walk = try route("walk", mode: "WALK", start: 0, end: 50)
        let first = [try route("a", start: 5, end: 25), try route("b", start: 15, end: 35)]
        let later = [try route("c", start: 25, end: 45), try route("d", start: 35, end: 55)]
        // The refreshed first page has moved on by one route.
        let fresh = [try route("b", start: 15, end: 35), try route("c", start: 25, end: 45)]
        let kept = PlanModel.laterPages(of: [walk] + first + later, after: fresh, arriveBy: false)
        XCTAssertEqual(kept.map(\.id), ["d"])
        // Nothing fresh to compare with: nothing is kept (the list must not show stale routes alone).
        XCTAssertTrue(PlanModel.laterPages(of: first + later, after: [], arriveBy: false).isEmpty)
        XCTAssertTrue(PlanModel.laterPages(of: first + later, after: [walk], arriveBy: false).isEmpty)
    }

    func testEarlierPagesStayForArriveBy() throws {
        let fresh = [try route("c", start: 25, end: 45), try route("d", start: 35, end: 55)]
        let previous = [try route("a", start: 5, end: 25), try route("b", start: 15, end: 35)] + fresh
        XCTAssertEqual(PlanModel.laterPages(of: previous, after: fresh, arriveBy: true).map(\.id), ["a", "b"])
        XCTAssertTrue(PlanModel.laterPages(of: fresh, after: fresh, arriveBy: true).isEmpty)
    }

    // MARK: One unreadable entry does not fail the answer

    func testPlanSkipsARouteItCannotRead() throws {
        // The second route lacks its legs' times; `direct` holds a number where a route belongs.
        let json = """
        {"itineraries":[\(routeJSON("a", start: 5, end: 25)),
                        {"id":"broken","duration":60,"transfers":0,"legs":[{"mode":"BUS"}]},
                        null,
                        \(routeJSON("b", start: 15, end: 35))],
         "direct":[7, \(routeJSON("walk", mode: "WALK", start: 0, end: 50))],
         "nextPageCursor":"LATER|1"}
        """
        let res = try TransitousClient.makeDecoder().decode(PlanResponse.self, from: Data(json.utf8))
        XCTAssertEqual(res.itineraries.map(\.id), ["a", "b"])
        XCTAssertEqual(res.direct.map(\.id), ["walk"])
        XCTAssertEqual(res.nextPageCursor, "LATER|1")
        XCTAssertNil(res.previousPageCursor)
    }

    func testPlanWithoutRoutesIsStillAnError() {
        XCTAssertThrowsError(try TransitousClient.makeDecoder().decode(PlanResponse.self, from: Data(#"{"error":"busy"}"#.utf8)))
        XCTAssertThrowsError(try TransitousClient.makeDecoder().decode(StopTimesResponse.self, from: Data(#"{"stopTimes":{}}"#.utf8)))
    }

    func testPlanFixtureStillDecodesCompletely() throws {
        let res = try TransitousClient.makeDecoder().decode(PlanResponse.self, from: Fixtures.data("plan"))
        XCTAssertEqual(res.itineraries.count, 2)
    }

    func testBoardSkipsADepartureItCannotRead() throws {
        func departure(_ trip: String?, headsign: String?) -> String {
            let t = trip.map { "\"tripId\":\"\($0)\"," } ?? ""
            let h = headsign.map { "\"headsign\":\"\($0)\"," } ?? ""
            return """
            {"place":{"name":"A","lat":48.2,"lon":16.37,"departure":"\(iso(5))"},\(t)\(h)"mode":"TRAM","realTime":false}
            """
        }
        let json = """
        {"stopTimes":[\(departure("t1", headsign: "Prater")), \(departure(nil, headsign: "Depot")), "x",
                      \(departure("t3", headsign: "Ring"))], "place": 5}
        """
        let res = try TransitousClient.makeDecoder().decode(StopTimesResponse.self, from: Data(json.utf8))
        XCTAssertEqual(res.stopTimes.map(\.tripId), ["t1", "t3"])
        XCTAssertNil(res.place)
    }

    func testLossyListReadsEveryKindOfEntry() throws {
        let list = try JSONDecoder().decode(LossyList<Int>.self, from: Data(#"[1, "two", null, {"a":[1,2]}, [3], 4.5, 6]"#.utf8))
        XCTAssertEqual(list.items, [1, 6])
        XCTAssertEqual(list.skipped, 5)
        XCTAssertTrue(try JSONDecoder().decode(LossyList<Int>.self, from: Data("[]".utf8)).items.isEmpty)
    }

    // MARK: Numbers no clock shows

    func testAbsurdCountdownsAndDelaysAreIgnored() throws {
        let now = date(0)
        XCTAssertEqual(ACTVSource.countdown("6'", now: now), date(6))
        XCTAssertNil(ACTVSource.countdown("999999999999999999'", now: now))
        XCTAssertNil(ACTVSource.countdown("-3'", now: now))
        let board = try JSONSerialization.jsonObject(with: Data("""
        {"connections":[{"time":"2026-10-07 10:10:00","line":"S2","dep_delay":"+9223372036854775807"},
                        {"time":"2026-10-07 10:20:00","line":"S2","dep_delay":"+3"}]}
        """.utf8)) as? [String: Any] ?? [:]
        let deps = SearchChSource.parseBoard(board)
        XCTAssertEqual(deps.count, 2)
        XCTAssertNil(deps[0].expected)
        XCTAssertEqual(deps[1].expected, deps[1].scheduled?.addingTimeInterval(180))
    }

    // MARK: Saved data survives an entry the app cannot read

    private func tempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("publit-audit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testOneUnreadableTripDoesNotEmptyTheStore() async throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let good = """
        {"id":"t1","itinerary":\(routeJSON("a", start: 5, end: 25)),"fromName":"A","toName":"B","savedAt":"\(iso(0))"}
        """
        let url = dir.appendingPathComponent("trips.json")
        try Data("[\(good), {\"id\":\"t2\",\"itinerary\":{\"id\":\"from a newer version\"}}]".utf8).write(to: url)
        let ids = await MainActor.run { TripStore(directory: dir).trips.map(\.id) }
        XCTAssertEqual(ids, ["t1"])
        // The file as it was stays next to it.
        XCTAssertTrue(FileManager.default.fileExists(atPath: JSONFileRescue.copyURL(for: url).path))
    }

    func testAFileThatIsNoListIsKeptBeforeTheStoreWritesAgain() throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = JSONFile<[String]>(name: "list.json", directory: dir)
        try Data("not json at all".utf8).write(to: file.url)
        XCTAssertNil(file.loadList())
        file.save(["new"])
        XCTAssertEqual(try String(contentsOf: JSONFileRescue.copyURL(for: file.url), encoding: .utf8), "not json at all")
        XCTAssertEqual(file.loadList(), ["new"])
        // A file that is simply not there is no reason for a copy.
        let fresh = JSONFile<[String]>(name: "fresh.json", directory: dir)
        XCTAssertNil(fresh.loadList())
        XCTAssertFalse(FileManager.default.fileExists(atPath: JSONFileRescue.copyURL(for: fresh.url).path))
    }

    // MARK: A late answer does not undo a switch to another connection

    func testRefreshOfTheOldRouteDoesNotReplaceTheNewOne() async throws {
        let dir = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let old = try route("old", start: 5, end: 25), new = try route("new", start: 15, end: 35)
        let lateAnswer = try route("old", start: 6, end: 26)
        let stored: (Bool, String?, Bool) = await MainActor.run {
            let trips = TripStore(directory: dir)
            let trip = trips.save(old, from: "A", to: "B")
            trips.reroute(trip.id, with: new, from: "A")
            let wrote = trips.update(trip.id, with: lateAnswer, replacing: old)
            let after = trips.trip(trip.id)?.itinerary.id
            // The same route's refresh still lands.
            let again = trips.update(trip.id, with: new, replacing: new)
            return (wrote, after, again)
        }
        XCTAssertFalse(stored.0)
        XCTAssertEqual(stored.1, "new")
        XCTAssertTrue(stored.2)
    }

    // MARK: Links with numbers no clock shows

    func testSharedRouteLinkWithAnAbsurdTimeIsNoRoute() {
        XCTAssertNotNil(SharedRoute(query: "fl=48.2,16.3&tl=48.1,16.2&d=1795000000"))
        XCTAssertNil(SharedRoute(query: "fl=48.2,16.3&tl=48.1,16.2&d=1e30"))
        XCTAssertNil(SharedRoute(query: "fl=48.2,16.3&tl=48.1,16.2&d=-1e30"))
    }
}

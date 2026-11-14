import XCTest
@testable import Publit

/// "Which way does it go?" A destination you have never heard of says little; the next stop does.
/// Prague, Staroměstská: tram 17 leaves from platform A towards Libuš and from B towards Kobylisy.
final class NextStopTests: XCTestCase {
    private func board() throws -> StopTimesResponse {
        try TransitousClient.makeDecoder().decode(StopTimesResponse.self, from: Fixtures.data("stoptimes_prague_next_stops"))
    }

    func testEachDirectionNamesItsNextStop() throws {
        let sts = try board().stopTimes
        let south = try XCTUnwrap(sts.first { $0.routeShortName == "17" && $0.headsign == "Libuš" })
        let north = try XCTUnwrap(sts.first { $0.routeShortName == "17" && $0.headsign == "Vozovna Kobylisy" })
        XCTAssertEqual(south.nextStopName, "Karlovy lázně")
        XCTAssertEqual(north.nextStopName, "Právnická fakulta")
        XCTAssertEqual(south.place.track, "A")
        XCTAssertEqual(north.place.track, "B")
    }

    func testOnlyTheFirstStopsAreKept() throws {
        for st in try board().stopTimes {
            XCTAssertLessThanOrEqual(st.nextStops?.names.count ?? 0, UpcomingStops.kept)
            XCTAssertNotNil(st.nextStopName)
        }
    }

    func testRoundTripAndOlderAnswersWithoutStops() throws {
        let stops = UpcomingStops(names: ["A", "B", "C", "D"])
        XCTAssertEqual(stops.names, ["A", "B", "C"])
        let again = try JSONDecoder().decode(UpcomingStops.self, from: JSONEncoder().encode(stops))
        XCTAssertEqual(again, stops)
        // Saved boards from before have no next stops: nothing shown, nothing broken.
        let old = try TransitousClient.makeDecoder().decode(StopTimesResponse.self, from: Fixtures.data("stoptimes"))
        XCTAssertTrue(old.stopTimes.allSatisfy { $0.nextStopName == nil })
    }

    func testNextStopThatIsTheDestinationOrThisStopIsNotRepeated() throws {
        var st = try XCTUnwrap(board().stopTimes.first)
        st.nextStops = UpcomingStops(names: [st.place.name, st.headsign])
        XCTAssertNil(st.nextStopName)
        st.nextStops = UpcomingStops(names: [st.place.name, "Somewhere", st.headsign])
        XCTAssertEqual(st.nextStopName, "Somewhere")
    }

    func testBoardsAskForTheStops() {
        // Both board requests carry fetchStops; checked on the query the client builds.
        let source = try? String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/API/TransitousClient.swift"), encoding: .utf8)
        XCTAssertEqual(source?.components(separatedBy: "\"fetchStops\"").count, 3)
    }
}

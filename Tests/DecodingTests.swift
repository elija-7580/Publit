import XCTest
@testable import Publit

final class DecodingTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data { try Fixtures.data(name) }

    func testPolylineGoogleReferenceExample() {
        let coords = Polyline.decode("_p~iF~ps|U_ulLnnqC_mqNvxq`@", precision: 5)
        XCTAssertEqual(coords.count, 3)
        XCTAssertEqual(coords[0].lat, 38.5, accuracy: 1e-9)
        XCTAssertEqual(coords[2].lon, -126.453, accuracy: 1e-9)
    }

    func testDecodesPlanResponse() throws {
        let plan = try TransitousClient.makeDecoder().decode(PlanResponse.self, from: fixture("plan"))
        XCTAssertFalse(plan.itineraries.isEmpty)
        let it = plan.itineraries[0]
        XCTAssertGreaterThan(it.transitLegs.count, 0)
        for leg in it.legs {
            XCTAssertEqual(leg.legGeometry.coordinates.count, leg.legGeometry.length)
        }
        XCTAssertNotNil(it.firstTransitLeg?.displayName)
    }

    func testDecodesStopTimes() throws {
        let res = try TransitousClient.makeDecoder().decode(StopTimesResponse.self, from: fixture("stoptimes"))
        XCTAssertFalse(res.stopTimes.isEmpty)
        XCTAssertNotEqual(res.stopTimes[0].departureTime, .distantPast)
    }

    func testDecodesGeocode() throws {
        let matches = try TransitousClient.makeDecoder().decode([GeocodeMatch].self, from: fixture("geocode"))
        XCTAssertFalse(matches.isEmpty)
        XCTAssertFalse(matches[0].subtitle.isEmpty)
    }

    func testDateParsingWithAndWithoutFraction() {
        XCTAssertNotNil(DateParsing.parse("2026-10-06T20:18:00Z"))
        XCTAssertNotNil(DateParsing.parse("2026-10-06T20:18:00.123Z"))
    }

    /// `.distantPast`/`.distantFuture` are saved (e.g. "never synced" on the watch) and read back at launch.
    /// They are computed without Int overflow, so 32-bit watches (arm64_32) no longer crash on them (#80).
    func testDateParsingFarDatesRoundTrip() throws {
        // Exact within the Gregorian era; for year 1 the formatter counts Julian days (2 days apart), which is fine.
        for (date, slack) in [(Date.distantPast, 3 * 86400.0), (.distantFuture, 1), (Date(timeIntervalSince1970: 0), 1),
                              (Date(timeIntervalSince1970: 4_200_000_000), 1)] {
            let text = DateParsing.format(date)
            let parsed = try XCTUnwrap(DateParsing.parse(text), text)
            XCTAssertEqual(parsed.timeIntervalSince1970, date.timeIntervalSince1970.rounded(.down), accuracy: slack, text)
        }
    }
}

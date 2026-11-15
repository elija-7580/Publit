import XCTest
@testable import Publit

/// The arrow on the Nearby map: which way the walk to the nearest station starts.
final class NearbyWalkTests: XCTestCase {
    func testArrowPointsAlongTheStartOfTheWalk() throws {
        // 200 m east, then north.
        let path = [LatLon(lat: 48.2, lon: 16.37), LatLon(lat: 48.2, lon: 16.3727), LatLon(lat: 48.202, lon: 16.3727)]
        let arrow = try XCTUnwrap(PathGeometry.arrow(on: path))
        XCTAssertEqual(arrow.bearing, 90, accuracy: 2, "east first")
        let away = path[0].distance(to: arrow.point)
        XCTAssertGreaterThanOrEqual(away, 25, "clear of your position dot")
        XCTAssertLessThanOrEqual(away, 91)
    }

    func testNoArrowForAFewSteps() {
        XCTAssertNil(PathGeometry.arrow(on: [LatLon(lat: 48.2, lon: 16.37), LatLon(lat: 48.2001, lon: 16.37)]))
        XCTAssertNil(PathGeometry.arrow(on: []))
    }
}

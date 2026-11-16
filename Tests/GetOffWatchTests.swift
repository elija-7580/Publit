import XCTest
@testable import Publit

final class GetOffWatchTests: XCTestCase {
    // A ride with 6 stops: 0 … 5, getting off at 5.
    private let n = 6

    func testOneStopBeforeFiresAtTheStopBeforeNotEarlier() {
        XCTAssertFalse(GetOffWatch.isDue(.oneStopBefore, progress: .between(index: 3, fraction: 0.9), stopCount: n, metresToExit: 900))
        XCTAssertTrue(GetOffWatch.isDue(.oneStopBefore, progress: .atStop(index: 4), stopCount: n, metresToExit: 600))
        XCTAssertTrue(GetOffWatch.isDue(.oneStopBefore, progress: .between(index: 4, fraction: 0.2), stopCount: n, metresToExit: 500))
        XCTAssertFalse(GetOffWatch.isDue(.oneStopBefore, progress: .finished, stopCount: n, metresToExit: 0))
    }

    func testTwoStopsBefore() {
        XCTAssertFalse(GetOffWatch.isDue(.twoStopsBefore, progress: .between(index: 2, fraction: 0.5), stopCount: n, metresToExit: 2000))
        XCTAssertTrue(GetOffWatch.isDue(.twoStopsBefore, progress: .atStop(index: 3), stopCount: n, metresToExit: 1500))
    }

    func testApproachingUsesDistanceOnlyOnTheLastStretch() {
        // Close to the exit stop as the crow flies, but three stops away along the line: not due.
        XCTAssertFalse(GetOffWatch.isDue(.approaching, progress: .between(index: 2, fraction: 0.5), stopCount: n, metresToExit: 300))
        XCTAssertFalse(GetOffWatch.isDue(.approaching, progress: .between(index: 4, fraction: 0.1), stopCount: n, metresToExit: 900))
        XCTAssertTrue(GetOffWatch.isDue(.approaching, progress: .between(index: 4, fraction: 0.7), stopCount: n, metresToExit: 350))
        XCTAssertTrue(GetOffWatch.isDue(.approaching, progress: .atStop(index: 5), stopCount: n, metresToExit: 0))
    }

    func testClockOnlyNeverUsesLocation() {
        XCTAssertFalse(GetOffWatch.isDue(.timeOnly, progress: .atStop(index: 4), stopCount: n, metresToExit: 100))
    }

    func testShortRideMilestoneIsTheFirstStopLeft() {
        XCTAssertFalse(GetOffWatch.isDue(.twoStopsBefore, progress: .atStop(index: 0), stopCount: 2, metresToExit: 800))
        XCTAssertTrue(GetOffWatch.isDue(.twoStopsBefore, progress: .between(index: 0, fraction: 0.3), stopCount: 2, metresToExit: 600))
    }
}

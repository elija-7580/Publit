import XCTest
@testable import Publit

final class HangLogTests: XCTestCase {
    private func makeLog() -> HangLog {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return HangLog(directory: dir)
    }

    func testShortWaitsAreNotRecorded() {
        let log = makeLog()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(log.tick(now: t0))
        XCTAssertFalse(log.tick(now: t0.addingTimeInterval(0.5)))
        log.answered(now: t0.addingTimeInterval(1.2))
        XCTAssertFalse(log.hasEntries)
    }

    func testFreezeIsRecordedWithLastScreensAndRecovery() throws {
        let log = makeLog()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        log.note("open Plan", at: t0.addingTimeInterval(-3))
        log.note("open Route", at: t0.addingTimeInterval(-1))
        XCTAssertTrue(log.tick(now: t0))
        for half in 1...11 { log.tick(now: t0.addingTimeInterval(Double(half) * 0.5)) }
        log.answered(now: t0.addingTimeInterval(5.6))
        let text = try String(contentsOf: log.fileURL, encoding: .utf8)
        XCTAssertTrue(text.contains("No response for 2 s"))
        XCTAssertTrue(text.contains("open Plan") && text.contains("open Route"))
        XCTAssertTrue(text.contains("Still no response after 5 s"))
        XCTAssertFalse(text.contains("after 8 s"))
        XCTAssertTrue(text.contains("Responding again after 5.6 s"))
        log.clear()
        XCTAssertFalse(log.hasEntries)
    }

    func testSuspensionIsNotAFreeze() {
        let log = makeLog()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(log.tick(now: t0))
        // The app was suspended for a minute with the question still queued.
        XCTAssertFalse(log.tick(now: t0.addingTimeInterval(60)))
        XCTAssertFalse(log.tick(now: t0.addingTimeInterval(60.5)))
        log.answered(now: t0.addingTimeInterval(60.6))
        XCTAssertFalse(log.hasEntries)
    }

    func testTrailKeepsOnlyTheLatestSteps() throws {
        let log = makeLog()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        for i in 0..<40 { log.note("open Screen\(i)", at: t0) }
        log.tick(now: t0)
        log.tick(now: t0.addingTimeInterval(2.1))
        let text = try String(contentsOf: log.fileURL, encoding: .utf8)
        XCTAssertFalse(text.contains("Screen14\n"))
        XCTAssertTrue(text.contains("Screen15\n") && text.contains("Screen39\n"))
    }
}

/// A board refresh must not turn a departure into a different list row (that closed the trip opened from it).
final class StableDepartureIdentityTests: XCTestCase {
    private func stopTimes(delayingFirstBy minutes: Int = 0, duplicateFirst: Bool = false) throws -> [StopTime] {
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: Fixtures.data("stoptimes")) as? [String: Any])
        var list = try XCTUnwrap(root["stopTimes"] as? [[String: Any]])
        if minutes != 0 {
            var place = try XCTUnwrap(list[0]["place"] as? [String: Any])
            let departure = try XCTUnwrap(DateParsing.parse(try XCTUnwrap(place["departure"] as? String)))
            place["departure"] = ISO8601DateFormatter().string(from: departure.addingTimeInterval(Double(minutes) * 60))
            list[0]["place"] = place
        }
        if duplicateFirst { list.insert(list[0], at: 1) }
        root["stopTimes"] = list
        let data = try JSONSerialization.data(withJSONObject: root)
        return try TransitousClient.makeDecoder().decode(StopTimesResponse.self, from: data).stopTimes
    }

    func testANewDelayKeepsTheRowIdentity() throws {
        let before = try stopTimes()[0]
        let after = try stopTimes(delayingFirstBy: 4)[0]
        XCTAssertNotEqual(before.departureTime, after.departureTime)
        XCTAssertEqual(before.id, after.id)
    }

    func testRepeatedDeparturesAppearOnce() throws {
        let list = try stopTimes(duplicateFirst: true)
        let now = list.map(\.departureTime).min()!.addingTimeInterval(-120)
        let shown = StopTime.upcoming(list, now: now)
        XCTAssertEqual(Set(shown.map(\.id)).count, shown.count)
        XCTAssertEqual(shown.count, list.count - 1)
    }
}

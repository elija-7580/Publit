import XCTest
@testable import Publit

/// The short note after an update.
final class WhatsNewTests: XCTestCase {
    func testShowsItemsOfNewerBuildsOnly() {
        let latest = WhatsNew.entries.map(\.build).max() ?? 0
        XCTAssertFalse(WhatsNew.items(seen: latest - 1, current: latest).isEmpty)
        XCTAssertTrue(WhatsNew.items(seen: latest, current: latest).isEmpty, "same build: nothing new")
        XCTAssertTrue(WhatsNew.items(seen: latest + 1, current: latest).isEmpty, "downgrade: nothing")
    }

    func testStaysShort() {
        for entry in WhatsNew.entries {
            XCTAssertLessThanOrEqual(entry.items.count, 3, "build \(entry.build): at most three items")
        }
        XCTAssertLessThanOrEqual(WhatsNew.items(seen: 0, current: Int.max).count, 4)
    }

    func testEntriesAreNewestFirstAndUnique() {
        let builds = WhatsNew.entries.map(\.build)
        XCTAssertEqual(builds, builds.sorted(by: >))
        XCTAssertEqual(Set(builds).count, builds.count)
    }
}

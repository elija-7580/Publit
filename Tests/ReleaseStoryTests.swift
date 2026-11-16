import XCTest
@testable import Publit

/// The interactive "What's new" story after a bigger update.
final class ReleaseStoryTests: XCTestCase {
    func testShownWhenItsBuildsWereNotSeen() {
        XCTAssertEqual(ReleaseStory.story(seen: 65, current: 85)?.version, "0.1.1", "from the App Store version 0.1.0")
        XCTAssertEqual(ReleaseStory.story(seen: 84, current: 85)?.version, "0.1.1", "testers on the build before")
    }

    func testNotShownWhenSeenOrDowngraded() {
        let latest = ReleaseStory.all.map(\.lastBuild).max() ?? 0
        XCTAssertNil(ReleaseStory.story(seen: latest, current: latest), "same build")
        XCTAssertNil(ReleaseStory.story(seen: latest + 1, current: latest), "downgrade")
    }

    func testNotShownForBuildsBeforeTheStory() {
        XCTAssertNil(ReleaseStory.story(seen: 10, current: 60), "an old build never gets a later story")
    }

    func testStaysShortAndConsistent() {
        for story in ReleaseStory.all {
            XCTAssertLessThanOrEqual(story.firstBuild, story.lastBuild)
            XCTAssertTrue((3...6).contains(story.cards.count), "\(story.version): 3 to 6 feature cards")
            XCTAssertLessThanOrEqual(story.fixes.count, 12, "\(story.version): the fixes page stays short")
            XCTAssertGreaterThanOrEqual(story.fixCount, story.fixes.count)
            XCTAssertEqual(Set(story.cards.map(\.id)).count, story.cards.count, "card ids are unique")
            for card in story.cards {
                XCTAssertLessThanOrEqual(card.title.split(separator: " ").count, 6, "\(card.id): short title")
            }
        }
    }

    func testNewestFirst() {
        let builds = ReleaseStory.all.map(\.lastBuild)
        XCTAssertEqual(builds, builds.sorted(by: >))
    }
}

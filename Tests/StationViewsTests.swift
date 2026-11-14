import XCTest
@testable import Publit

/// Settings → Stations: platform map, departures by platform, change guide.
final class StationViewsTests: XCTestCase {
    private func prague() throws -> [StopTime] {
        try TransitousClient.makeDecoder().decode(StopTimesResponse.self, from: Fixtures.data("stoptimes_prague_next_stops")).stopTimes
    }

    func testStaromestskaSplitsIntoItsPlatforms() throws {
        let groups = PlatformGrouping.groups(try prague())
        let tramA = try XCTUnwrap(groups.first { $0.label == "A" && $0.name == "Staroměstská" })
        let tramB = try XCTUnwrap(groups.first { $0.label == "B" && $0.name == "Staroměstská" })
        XCTAssertEqual(Set(tramA.lines.map(\.lineName)), ["17", "18"])
        XCTAssertEqual(tramB.lines.map(\.lineName), ["17"])
        // Platform A goes towards Karlovy lázně, B towards Právnická fakulta.
        XCTAssertEqual(tramA.ways.first?.first, "Karlovy lázně")
        XCTAssertEqual(tramB.ways.first?.first, "Právnická fakulta")
        XCTAssertLessThanOrEqual(tramA.ways.count, PlatformGrouping.maxWays)
        XCTAssertEqual(tramA.title, L10n.f("Platform %@", "A"))
        // Every departure is in exactly one platform.
        XCTAssertEqual(groups.map(\.departures.count).reduce(0, +), try prague().count)
    }

    func testPlatformsInNaturalOrder() throws {
        let labels = PlatformGrouping.groups(try prague()).compactMap(\.label)
        XCTAssertEqual(labels, labels.sorted { $0.compare($1, options: [.numeric, .caseInsensitive]) == .orderedAscending })
    }

    func testBoardWithoutNextStopsStillGroups() throws {
        let old = try TransitousClient.makeDecoder().decode(StopTimesResponse.self, from: Fixtures.data("stoptimes")).stopTimes
        let groups = PlatformGrouping.groups(old)
        XCTAssertFalse(groups.isEmpty)
        XCTAssertTrue(groups.allSatisfy { $0.ways.isEmpty })
    }

    func testChangeGuideForEveryChange() throws {
        for name in ["plan", "plan_muc", "plan_park_ride"] {
            let res = try TransitousClient.makeDecoder().decode(PlanResponse.self, from: Fixtures.data(name))
            for it in res.itineraries {
                let rides = it.legs.indices.filter { it.legs[$0].isTransit }
                // No change before the first ride.
                if let first = rides.first { XCTAssertNil(ChangeGuide(before: first, in: it)) }
                for i in rides.dropFirst() {
                    let g = try XCTUnwrap(ChangeGuide(before: i, in: it), name)
                    XCTAssertGreaterThanOrEqual(g.path.count, 2)
                    XCTAssertTrue(g.headline.contains("→"))
                    XCTAssertEqual(g.stairs == 0, g.isStepFree)
                    XCTAssertTrue(g.steps.allSatisfy {
                        [.stairs, .stairsUp, .stairsDown, .elevator, .levelUp, .levelDown].contains($0.kind) || $0.exitNote != nil
                    })
                }
            }
        }
    }

    func testSettingsDefaults() {
        let d = UserDefaults(suiteName: "StationViewsTests")!
        d.removePersistentDomain(forName: "StationViewsTests")
        XCTAssertTrue(StationViews.flag(StationViews.platformMapKey, default: true, d))
        XCTAssertTrue(StationViews.flag(StationViews.changeGuideKey, default: true, d))
        XCTAssertFalse(StationViews.flag(StationViews.byPlatformKey, default: false, d))
        d.set(false, forKey: StationViews.platformMapKey)
        XCTAssertFalse(StationViews.flag(StationViews.platformMapKey, default: true, d))
    }
}

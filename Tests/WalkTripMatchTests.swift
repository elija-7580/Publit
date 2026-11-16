import XCTest
@testable import Publit

/// Walking-only routes come with an empty server ID. Starting a new walk opened the first walk
/// ever saved (feedback 2026-11-16: "Start walking navigation" showed an old walk in Annenheim).
final class WalkTripMatchTests: XCTestCase {
    private func walk() throws -> Itinerary {
        let res = try TransitousClient.makeDecoder().decode(PlanResponse.self, from: Fixtures.data("plan_direct_modes"))
        return try XCTUnwrap(res.direct.first { StreetComparison.streetMode($0) == "WALK" })
    }

    /// The same walk a day later (another walk with the same empty ID).
    private func later(_ it: Itinerary) -> Itinerary {
        let day: TimeInterval = 86400
        return Itinerary(id: it.id, duration: it.duration, startTime: it.startTime + day, endTime: it.endTime + day,
                         transfers: it.transfers, legs: it.legs)
    }

    @MainActor
    func testANewWalkIsNotAnOldSavedWalk() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { JSONPersistence.flush(); try? FileManager.default.removeItem(at: dir) }
        let store = TripStore(directory: dir)
        let old = try walk()
        XCTAssertEqual(old.id, "", "the router gives walks no ID")
        let saved = store.save(old, from: "Annenheim", to: "Somewhere")
        let fresh = later(old)
        XCTAssertNil(store.saved(fresh))
        XCTAssertNotEqual(store.save(fresh, from: "Here", to: "There").id, saved.id)
        XCTAssertEqual(store.saved(old)?.id, saved.id, "the same walk still finds its saved trip")
    }
}

import XCTest
@testable import Publit

/// Reddit report: a big street in central Milan could not be found from home.
final class SearchBiasTests: XCTestCase {
    private func match(_ id: String, _ name: String, street: String? = nil) throws -> GeocodeMatch {
        var o: [String: Any] = ["type": "ADDRESS", "name": name, "id": id, "lat": 45.46, "lon": 9.19, "areas": [] as [Any]]
        if let street { o["street"] = street }
        return try JSONDecoder().decode(GeocodeMatch.self, from: JSONSerialization.data(withJSONObject: o))
    }

    func testNamedTownDropsThePositionBias() {
        let here = LatLon(lat: 48.2, lon: 16.37)
        XCTAssertNil(SearchBias.position(for: "Corso Buenos Aires, Milano", location: here))
        XCTAssertEqual(SearchBias.position(for: "Corso Buenos Aires", location: here), here)
    }

    func testWiderSearchWhenNoResultCarriesAllWords() throws {
        let nearby = [try match("a", "Buenos-Aires-Gasse"), try match("b", "Corso Italia")]
        XCTAssertTrue(SearchBias.needsWiderSearch("Corso Buenos Aires", results: nearby))
        let hit = [try match("c", "Corso Buenos Aires 12", street: "Corso Buenos Aires")]
        XCTAssertFalse(SearchBias.needsWiderSearch("corso buenos aires", results: hit))
        XCTAssertFalse(SearchBias.needsWiderSearch("U6", results: []), "too short to judge")
    }

    func testMergePutsWideHitsFirstWithoutDuplicates() throws {
        let near = [try match("a", "Buenos-Aires-Gasse"), try match("c", "Corso Buenos Aires")]
        let wide = [try match("c", "Corso Buenos Aires"), try match("d", "Corso Buenos Aires 5")]
        XCTAssertEqual(SearchBias.merge(near, wide).map(\.id), ["d", "a", "c"])
    }
}

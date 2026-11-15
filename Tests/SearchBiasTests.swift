import XCTest
@testable import Publit

/// Reddit report: a big street in central Milan could not be found from home.
final class SearchBiasTests: XCTestCase {
    private func match(_ id: String, _ name: String, street: String? = nil, number: String? = nil,
                       type: String = "ADDRESS", lat: Double = 45.46) throws -> GeocodeMatch {
        var o: [String: Any] = ["type": type, "name": name, "id": id, "lat": lat, "lon": 9.19, "areas": [] as [Any]]
        if let street { o["street"] = street }
        if let number { o["houseNumber"] = number }
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

    /// Reddit report: the own street and house number could not be found, so a nearby stop had to
    /// stand in as Home. Apple's address with that number goes to the top.
    func testHouseNumber() {
        XCTAssertEqual(SearchBias.houseNumber(in: "Hauptstraße 12"), "12")
        XCTAssertEqual(SearchBias.houseNumber(in: "12a Main Street"), "12a")
        XCTAssertEqual(SearchBias.houseNumber(in: "Via Roma 7/2, Milano"), "7/2")
        XCTAssertNil(SearchBias.houseNumber(in: "Hauptbahnhof"))
    }

    func testAddressWithNumberComesFirst() throws {
        let transit = [try match("t1", "Hauptstraße", street: "Hauptstraße"),
                       try match("t2", "Hauptstraße", type: "STOP", lat: 45.47)]
        let apple = [try match("a1", "Hauptstraße 12", street: "Hauptstraße", number: "12", lat: 45.461),
                     try match("a2", "Hauptstraße 14", street: "Hauptstraße", number: "14", lat: 45.462)]
        let list = SearchBias.combine(transit, apple, query: "Hauptstraße 12")
        XCTAssertEqual(list.first?.id, "a1")
        XCTAssertEqual(list.map(\.id), ["a1", "t1", "t2", "a2"])
    }

    func testStopsStayFirstWithoutHouseNumber() throws {
        let transit = [try match("s", "Marienplatz", type: "STOP")]
        let apple = [try match("p", "Marienplatz Café", type: "PLACE", lat: 45.5)]
        XCTAssertEqual(SearchBias.combine(transit, apple, query: "Marienplatz").map(\.id), ["s", "p"])
    }

    func testAppleOnlyWhenTransitHasNothing() throws {
        let apple = [try match("a", "Rue de Rivoli 5", street: "Rue de Rivoli", number: "5")]
        XCTAssertEqual(SearchBias.combine([], apple, query: "rue de rivoli 5").map(\.id), ["a"])
    }
}

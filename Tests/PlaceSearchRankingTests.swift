import XCTest
@testable import Publit

/// The place search orders stops and Apple's suggestions like Apple Maps.
final class PlaceSearchRankingTests: XCTestCase {
    private func match(_ id: String, _ name: String, type: String = "STOP", street: String? = nil) throws -> GeocodeMatch {
        var o: [String: Any] = ["type": type, "name": name, "id": id, "lat": 48.2, "lon": 16.37, "areas": [] as [Any]]
        if let street { o["street"] = street }
        return try JSONDecoder().decode(GeocodeMatch.self, from: JSONSerialization.data(withJSONObject: o))
    }

    private func suggestion(_ title: String, _ subtitle: String = "Wien", address: Bool = false) -> PlaceSuggestion {
        PlaceSuggestion(id: title + "|" + subtitle, title: title, subtitle: subtitle, source: .apple, isAddress: address)
    }

    func testStopsThatMatchComeFirstThenApple() throws {
        let transit = [try match("s1", "Wien Westbahnhof"), try match("s2", "Westbahnstraße")]
        let apple = [suggestion("Westbahnhof Shopping", "Europaplatz"), suggestion("Westbahnstraße 7", address: true)]
        let hits = PlaceSearchRanking.order(transit: transit, suggestions: apple, query: "Westbahnhof", scope: .all)
        XCTAssertEqual(hits.first?.id, "m|s1")
        XCTAssertTrue(hits.contains { $0.id == "s|Westbahnstraße 7|Wien" })
        XCTAssertEqual(hits.last?.id, "m|s2", "a stop without every word comes last")
    }

    func testHouseNumberPutsAddressesFirst() throws {
        let transit = [try match("s1", "Hauptstraße")]
        let apple = [suggestion("Hauptstraße 12", address: true)]
        let hits = PlaceSearchRanking.order(transit: transit, suggestions: apple, query: "Hauptstraße 12", scope: .all)
        XCTAssertEqual(hits.first?.id, "s|Hauptstraße 12|Wien")
    }

    func testSuggestionNamedLikeAStopIsDropped() throws {
        let transit = [try match("s1", "Karlsplatz")]
        let apple = [suggestion("Karlsplatz", "1010 Wien")]
        let hits = PlaceSearchRanking.order(transit: transit, suggestions: apple, query: "Karlsplatz", scope: .all)
        XCTAssertEqual(hits.map(\.id), ["m|s1"])
    }

    func testStopsScopeHasOnlyStops() throws {
        let transit = [try match("s1", "Karlsplatz"), try match("a1", "Karlsplatz 1", type: "ADDRESS")]
        let hits = PlaceSearchRanking.order(transit: transit, suggestions: [suggestion("Karlskirche")], query: "Karlsplatz", scope: .stops)
        XCTAssertEqual(hits.map(\.id), ["m|s1"])
    }

    func testWithoutSuggestionsTransitousAddressesStay() throws {
        let transit = [try match("a1", "Mariahilfer Straße 1", type: "ADDRESS", street: "Mariahilfer Straße")]
        let hits = PlaceSearchRanking.order(transit: transit, suggestions: [], query: "Mariahilfer Straße", scope: .addresses)
        XCTAssertEqual(hits.map(\.id), ["m|a1"])
        let all = PlaceSearchRanking.order(transit: transit, suggestions: [], query: "Mariahilfer Straße", scope: .all)
        XCTAssertEqual(all.map(\.id), ["m|a1"])
    }

    func testNoDuplicatesAndLimit() throws {
        let transit = try (0..<40).map { try match("s\($0)", "Stop \($0) Ring") }
        let hits = PlaceSearchRanking.order(transit: transit, suggestions: [], query: "Ring", scope: .all)
        XCTAssertEqual(hits.count, PlaceSearchRanking.limit)
        XCTAssertEqual(Set(hits.map(\.id)).count, hits.count)
    }
}

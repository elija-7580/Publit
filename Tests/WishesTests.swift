import XCTest
@testable import Publit

/// Feature requests and voting in the app (the wish list on publit.eu/wuensche).
final class WishesTests: XCTestCase {
    func testDecodesTheServerList() throws {
        let json = """
        {"wishes":[{"id":2,"title":"Show the optimal exit","body":"OSM has ref","lang":"en","status":"planned","created":1794592760,"votes":2,"mine":true},
                   {"id":1,"title":"Wear OS app","body":"","lang":"en","status":"something-new","created":1793441034,"votes":1,"mine":false}]}
        """
        struct R: Decodable { let wishes: [Wish] }
        let list = try JSONDecoder().decode(R.self, from: Data(json.utf8)).wishes
        XCTAssertEqual(list.map(\.id), [2, 1])
        XCTAssertEqual(list[0].status, .planned)
        XCTAssertTrue(list[0].mine)
        XCTAssertEqual(list[1].status, .open, "unknown states read as open")
    }

    func testVoterIdMatchesTheServerRule() {
        let v = WishesClient.newVoter()
        XCTAssertTrue(WishesClient.isValidVoter(v))
        XCTAssertNotEqual(v, WishesClient.newVoter())
        XCTAssertFalse(WishesClient.isValidVoter("short"))
        XCTAssertFalse(WishesClient.isValidVoter(String(repeating: "a", count: 20) + "!"))
        let d = UserDefaults(suiteName: "publit-tests-\(UUID().uuidString)")!
        XCTAssertEqual(WishesClient.storedVoter(d), WishesClient.storedVoter(d), "kept once made")
    }

    func testServerAnswersBecomeMessages() {
        XCTAssertEqual(WishesClient.failure(409, Data()), .exists)
        XCTAssertEqual(WishesClient.failure(429, Data()), .slowDown)
        XCTAssertEqual(WishesClient.failure(422, Data(#"{"error":"links"}"#.utf8)), .links)
        XCTAssertEqual(WishesClient.failure(422, Data(#"{"error":"title"}"#.utf8)), .tooShort)
        XCTAssertEqual(WishesClient.failure(500, Data()), .unavailable)
    }

    func testLanguage() {
        XCTAssertEqual(WishesClient.language(["de-AT"]), "de")
        XCTAssertEqual(WishesClient.language(["it-IT"]), "en")
    }

    func testShortTitleIsRejectedBeforeSending() async {
        do {
            try await WishesClient(voter: WishesClient.newVoter()).suggest(title: "  hi ", body: "")
            XCTFail("should throw")
        } catch {
            XCTAssertEqual(error as? WishesClient.Failure, .tooShort)
        }
    }
}

import XCTest
@testable import Publit

/// Product IDs for supporting Publit (shared with Android).
final class SupportTests: XCTestCase {
    func testMonthlyAmounts() {
        XCTAssertEqual(Support.monthlyCents, [150, 300, 500, 1000, 2000, 5000])
        XCTAssertEqual(Support.monthlyID(150), "io.github.elija7580.publit.support.monthly.150")
        XCTAssertEqual(Support.oneTimeID(500), "io.github.elija7580.publit.support.tip.500")
    }

    func testParse() {
        XCTAssertEqual(Support.parse(Support.monthlyID(2000))?.kind, .monthly)
        XCTAssertEqual(Support.parse(Support.oneTimeID(1000))?.cents, 1000)
        XCTAssertNil(Support.parse("io.github.elija7580.publit.support.monthly.123"), "unknown amount")
        XCTAssertNil(Support.parse("com.example.tip.500"))
    }

    func testSortsByAmountAndKind() {
        let ids = [Support.monthlyID(5000), Support.oneTimeID(300), Support.monthlyID(150), Support.monthlyID(500)]
        XCTAssertEqual(Support.sorted(ids, id: { $0 }, kind: .monthly),
                       [Support.monthlyID(150), Support.monthlyID(500), Support.monthlyID(5000)])
        XCTAssertEqual(Support.sorted(ids, id: { $0 }, kind: .oneTime), [Support.oneTimeID(300)])
    }

    func testIDsAreUnique() {
        XCTAssertEqual(Set(Support.allIDs).count, Support.allIDs.count)
        XCTAssertTrue(Support.monthlyCents.contains(Support.suggestedMonthlyCents))
    }
}

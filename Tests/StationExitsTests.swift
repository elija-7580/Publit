import XCTest
@testable import Publit

/// Feature request: show the number of the station exit to use (OSM `ref` on subway entrances).
final class StationExitsTests: XCTestCase {
    private let sample = """
    {"elements":[
      {"type":"node","id":1,"lat":48.13720,"lon":11.57560,"tags":{"railway":"subway_entrance","ref":"3"}},
      {"type":"node","id":2,"lat":48.13780,"lon":11.57560,"tags":{"railway":"subway_entrance","ref":"7"}},
      {"type":"node","id":3,"lat":48.13721,"lon":11.57561,"tags":{"railway":"subway_entrance","ref":" "}}
    ]}
    """

    func testParsesEntrancesWithRef() throws {
        let list = try StationExits.parse(Data(sample.utf8))
        XCTAssertEqual(list.map(\.ref), ["3", "7"], "blank refs are dropped")
    }

    func testPicksTheEntranceAtTheExitPoint() throws {
        let list = try StationExits.parse(Data(sample.utf8))
        XCTAssertEqual(StationExits.nearest(list, to: LatLon(lat: 48.13725, lon: 11.57562)), "3")
        XCTAssertEqual(StationExits.nearest(list, to: LatLon(lat: 48.13775, lon: 11.57562)), "7")
        XCTAssertNil(StationExits.nearest(list, to: LatLon(lat: 48.1390, lon: 11.5790)), "no entrance close enough")
    }

    func testQueryOnlyCarriesTheExitPoint() {
        let q = StationExits.query(around: LatLon(lat: 45.464211, lon: 9.190336))
        XCTAssertTrue(q.contains("45.464211,9.190336"))
        XCTAssertTrue(q.contains("subway_entrance"))
    }
}

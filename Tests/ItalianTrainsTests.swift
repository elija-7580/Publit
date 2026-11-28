// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich

import XCTest
@testable import Publit

/// Feedback from a rider near Milan (Nov 2026): Frecciarossa and Italo were missing on the live map,
/// Trenord trains showed only "RE6" without the train number riders look for on the board.
final class ItalianTrainsTests: XCTestCase {
    private let decoder = TransitousClient.makeDecoder()

    /// `distance` is the whole trip's (927 km for a Frecciarossa Milan–Naples), not the hop's.
    private func segment(mode: String, name: String, tripId: String, polyline: String, distance: Double,
                         from: (String, Double, Double), to: (String, Double, Double)) -> String {
        """
        {"trips":[{"tripId":"\(tripId)","displayName":"\(name)"}],"mode":"\(mode)","distance":\(distance),
         "from":{"name":"\(from.0)","stopId":"\(from.0)","lat":\(from.1),"lon":\(from.2)},
         "to":{"name":"\(to.0)","stopId":"\(to.0)","lat":\(to.1),"lon":\(to.2)},
         "departure":"2026-11-28T11:00:00Z","arrival":"2026-11-28T11:40:00Z",
         "scheduledDeparture":"2026-11-28T11:00:00Z","scheduledArrival":"2026-11-28T11:40:00Z",
         "realTime":false,"polyline":"\(polyline)"}
        """
    }

    private func segments() throws -> [TripSegment] {
        let list = [
            segment(mode: "HIGHSPEED_RAIL", name: "FR 8809", tripId: "fr8809", polyline: "kvhtGwnkw@jrl@g`yAfd|AguzD",
                    distance: 927_000, from: ("MILANO ROGOREDO", 45.4335, 9.2390), to: ("REGGIO EMILIA AV", 44.7230, 10.6610)),
            segment(mode: "HIGHSPEED_RAIL", name: "FR 9617", tripId: "fr9617", polyline: "w_stG_tdw@nf{Tg}bS",
                    distance: 479_000, from: ("MILANO CENTRALE", 45.4862, 9.2040), to: ("ROMA TERMINI", 41.9010, 12.5010)),
            segment(mode: "REGIONAL_RAIL", name: "RE6", tripId: "re6", polyline: "gxrtGgbkw@oKgjIkCsyF",
                    distance: 139_000, from: ("Milano Lambrate", 45.4850, 9.2370), to: ("Pioltello Limito", 45.4877, 9.3301)),
            segment(mode: "BUS", name: "923", tripId: "bus923", polyline: "gxrtGgbkw@oKgjIkCsyF",
                    distance: 9_000, from: ("A", 45.4850, 9.2370), to: ("B", 45.4877, 9.3301)),
        ]
        return try decoder.decode([TripSegment].self, from: Data("[\(list.joined(separator: ","))]".utf8))
    }

    func testHighSpeedTrainsStayOnTheMap() throws {
        let snap = LiveMap.build(try segments(), filter: .all, precision: 5, tolerance: 2)
        let ids = Set(snap.tracks.map(\.id))
        XCTAssertTrue(ids.contains("fr8809"), "a long trip with a real shape is drawn")
        XCTAssertFalse(ids.contains("fr9617"), "a 400 km hop without a shape would be a straight line across Italy")
        XCTAssertTrue(ids.contains("re6"))
        XCTAssertTrue(ids.contains("bus923"))
    }

    func testOverviewKeepsOnlyTrainsAsDots() throws {
        let snap = LiveMap.build(try segments(), filter: .all, precision: 5, tolerance: 300, overview: true)
        XCTAssertEqual(Set(snap.tracks.map(\.id)), ["fr8809", "re6"])
        XCTAssertTrue(snap.tracks.allSatisfy(\.compact))
        let at = ISO8601DateFormatter().date(from: "2026-11-28T11:20:00Z")!
        let v = try XCTUnwrap(snap.tracks.first { $0.id == "re6" }?.vehicle(at: at))
        XCTAssertTrue(v.compact)
        XCTAssertGreaterThan(LiveMap.tolerance(spanMeters: 300_000), 40, "zoomed out, shapes are simplified more")
        XCTAssertEqual(LiveMap.tolerance(spanMeters: 2_000), 2.5)
    }

    func testTrenordTrainNumberBesideTheLine() throws {
        let re6 = Train(mode: "REGIONAL_RAIL", routeShortName: "RE6", displayName: "RE6", tripShortName: "RE_6 - 2625")
        XCTAssertEqual(re6.lineName, "RE6")
        XCTAssertEqual(re6.tripNumber, "2625")
        XCTAssertEqual(re6.serviceDetail, "RE 2625")
        let s5 = Train(mode: "REGIONAL_RAIL", routeShortName: "S5", displayName: "S5", tripShortName: "S5 - 24539")
        XCTAssertEqual(s5.serviceDetail, "24539")
        // Already in the badge: nothing twice.
        let fr = Train(mode: "HIGHSPEED_RAIL", routeShortName: nil, displayName: "FR 9304", tripShortName: "9304")
        XCTAssertNil(fr.tripNumber)
        XCTAssertNil(fr.serviceDetail)
        // DB keeps its train in the display name, as before.
        let ice = Train(mode: "HIGHSPEED_RAIL", routeShortName: "29", displayName: "ICE 1006", tripShortName: "1006")
        XCTAssertEqual(ice.serviceDetail, "ICE 1006")
        // Buses: trip numbers there are internal.
        let bus = Train(mode: "BUS", routeShortName: "923", displayName: "923", tripShortName: "923 - 4711")
        XCTAssertNil(bus.serviceDetail)
    }

    func testStopTimeDecodesTrainNumberAndFirstStop() throws {
        let json = """
        {"stopTimes":[{"place":{"name":"Pioltello Limito","lat":45.4877,"lon":9.3301,"departure":"2026-11-28T11:39:00Z",
          "scheduledDeparture":"2026-11-28T11:39:00Z"},"mode":"REGIONAL_RAIL","realTime":false,"headsign":"Verona Porta Nuova",
          "agencyName":"Trenord","routeId":"it-Lombardia-Trenord_RE_6","tripId":"t1","routeShortName":"RE6","displayName":"RE6",
          "routeColor":"e40314","routeTextColor":"ffffff","tripShortName":"RE_6 - 2625",
          "tripFrom":{"name":"Milano Centrale","lat":45.487,"lon":9.203},"tripTo":{"name":"Verona Porta Nuova","lat":45.429,"lon":10.982}}],
         "nextPageCursor":null}
        """
        let st = try XCTUnwrap(decoder.decode(StopTimesResponse.self, from: Data(json.utf8)).stopTimes.first)
        XCTAssertEqual(st.tripShortName, "RE_6 - 2625")
        XCTAssertEqual(st.tripFrom?.name, "Milano Centrale")
        XCTAssertEqual(st.serviceDetail, "RE 2625")
    }
}

private struct Train: RouteStyled {
    var mode: String
    var routeColor: String? = nil
    var routeTextColor: String? = nil
    var routeShortName: String?
    var displayName: String?
    var tripShortName: String?
}

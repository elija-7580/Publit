import XCTest
@testable import Publit

final class CoverageTests: XCTestCase {
    private let atlas = CoverageAtlas.shared

    private func area(_ lat: Double, _ lon: Double) -> CoverageArea? { atlas.area(at: LatLon(lat: lat, lon: lon)) }

    func testAtlasIsDecoded() {
        XCTAssertGreaterThan(atlas.areas.count, 50)
        XCTAssertFalse(atlas.date.isEmpty)
        XCTAssertEqual(Set(atlas.areas.map(\.id)).count, atlas.areas.count, "ids are unique")
        // The hand-checked areas come first, so they win over a coarse region around them.
        XCTAssertEqual(atlas.areas.prefix(5).map(\.level), Array(repeating: .partial, count: 5))
    }

    func testCarinthiaHasNoLocalBuses() throws {
        // The example that started it: Transitous skips the Carinthian bus feed.
        for (name, lat, lon) in [("Klagenfurt", 46.623, 14.308), ("Villach", 46.61, 13.845), ("Spittal", 46.80, 13.49), ("Wolfsberg", 46.84, 14.84)] {
            let a = try XCTUnwrap(area(lat, lon), name)
            XCTAssertEqual(a.id, "at-carinthia", name)
            XCTAssertEqual(a.level, .partial)
            XCTAssertEqual(a.gaps, [.localBuses])
            XCTAssertEqual(a.name(german: true), "Kärnten")
            XCTAssertEqual(a.name(german: false), "Carinthia")
            XCTAssertEqual(a.mapURL(german: false).absoluteString, "https://publit.eu/abdeckung/?lang=en#at/K%C3%A4rnten")
        }
    }

    func testPlacesWithDataAreNotFlagged() {
        for (name, lat, lon) in [("Vienna", 48.2082, 16.3738), ("Graz", 47.0707, 15.4395), ("Salzburg", 47.8095, 13.0550),
                                 ("Innsbruck", 47.2692, 11.4041), ("Munich", 48.1374, 11.5755), ("Berlin", 52.52, 13.405),
                                 ("Zürich", 47.3769, 8.5417), ("Paris", 48.8566, 2.3522), ("London", 51.5072, -0.1276),
                                 ("Prague", 50.0755, 14.4378), ("Oslo", 59.9139, 10.7522), ("Barcelona", 41.3874, 2.1686),
                                 ("Rome", 41.9028, 12.4964), ("Athens", 37.9838, 23.7275), ("Lisbon", 38.7223, -9.1393),
                                 ("Warsaw", 52.2297, 21.0122), ("Bucharest", 44.4268, 26.1025), ("Sofia", 42.6977, 23.3219)] {
            XCTAssertNil(area(lat, lon), "\(name) has timetable data")
        }
    }

    func testBigCitiesWithMissingServices() throws {
        let madrid = try XCTUnwrap(area(40.4168, -3.7038))
        XCTAssertEqual(madrid.level, .partial)
        XCTAssertTrue(madrid.gaps.contains(.metro) && madrid.gaps.contains(.cityBuses))
        let istanbul = try XCTUnwrap(area(41.0082, 28.9784))
        XCTAssertEqual(istanbul.gaps, [.metro, .trams, .ferries, .suburbanTrains])
        let kyiv = try XCTUnwrap(area(50.4501, 30.5234))
        XCTAssertEqual(kyiv.gaps, [.metro, .trams, .suburbanTrains])
        // Pristina has trains; the city buses are missing.
        let pristina = try XCTUnwrap(area(42.6629, 21.1655))
        XCTAssertEqual(pristina.gaps, [.cityBuses])
    }

    func testNoDataAtAll() throws {
        XCTAssertEqual(try XCTUnwrap(area(35.8989, 14.5146)).level, .none, "Valletta (Malta has no feed)")
        XCTAssertEqual(try XCTUnwrap(area(55.7558, 37.6173)).level, .none, "Moscow")
        XCTAssertEqual(try XCTUnwrap(area(43.9424, 12.4578)).level, .none, "San Marino")
        XCTAssertNotNil(area(53.9006, 27.5590), "Minsk")
    }

    func testThinTownsAreSparse() throws {
        // Verona: the data holds a FlixBus stop, nothing else.
        let verona = try XCTUnwrap(area(45.4384, 10.9916))
        XCTAssertEqual(verona.level, .sparse)
        XCTAssertEqual(verona.name(german: false), "Verona")
        XCTAssertEqual(verona.summary, L10n.t("Very little timetable data"))
    }

    func testPolygonsHonourHoles() {
        let outer = (0..<4).map { LatLon(lat: [0, 0, 10, 10][$0], lon: [0, 10, 10, 0][$0]) }
        let hole = (0..<4).map { LatLon(lat: [4, 4, 6, 6][$0], lon: [4, 6, 6, 4][$0]) }
        let a = CoverageArea(id: "t", level: .sparse, gaps: [], nameEN: "T", nameDE: "T", shape: .polygon(rings: [outer, hole]))
        XCTAssertTrue(a.contains(LatLon(lat: 2, lon: 2)))
        XCTAssertFalse(a.contains(LatLon(lat: 5, lon: 5)))
        XCTAssertFalse(a.contains(LatLon(lat: 11, lon: 5)))
        // For drawing: one piece with the hole cut out; two separate outlines are two pieces without holes.
        XCTAssertEqual(a.pieces.count, 1)
        XCTAssertEqual(a.pieces[0].outer, outer)
        XCTAssertEqual(a.pieces[0].holes, [hole])
        let island = (0..<4).map { LatLon(lat: [20, 20, 22, 22][$0], lon: [20, 22, 22, 20][$0]) }
        let two = CoverageArea(id: "t2", level: .none, gaps: [], nameEN: "T", nameDE: "T", shape: .polygon(rings: [outer, hole, island]))
        XCTAssertEqual(two.pieces.map(\.outer), [outer, island])
        XCTAssertEqual(two.pieces.map { $0.holes.count }, [1, 0])
        XCTAssertTrue(CoverageArea(id: "c", level: .partial, gaps: [], nameEN: "C", nameDE: "C",
                                   shape: .circle(center: LatLon(lat: 1, lon: 1), radius: 500)).pieces.isEmpty)
    }

    func testDecoderRoundTrip() throws {
        // Delta/zigzag varints: 46.623,14.308 then +0.001,-0.002 then +0.002,+0.003.
        func enc(_ v: Int) -> String {
            let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
            var z = v >= 0 ? v << 1 : ((-v) << 1) - 1
            var out = ""
            while true {
                let g = z & 31; z >>= 5
                if z > 0 { out.append(alphabet[g | 32]) } else { out.append(alphabet[g]); break }
            }
            return out
        }
        let ring = [(46_623, 14_308), (1, -2), (2, 3), (-4, 1)].map { enc($0.0) + enc($0.1) }.joined()
        let atlas = CoverageAtlas(payload: "A|x|n||Xland|Xland|xx|p\(ring)\nA|c|p|MT|Circle|Kreis|yy/Ä|c10000,20000,5000\nbroken line\nA|y|z||a|b|zz|p", date: "d")
        XCTAssertEqual(atlas.areas.map(\.id), ["x", "c"])
        guard case .polygon(let rings) = atlas.areas[0].shape else { return XCTFail("polygon") }
        XCTAssertEqual(rings[0].count, 4)
        XCTAssertEqual(rings[0][0], LatLon(lat: 46.623, lon: 14.308))
        XCTAssertEqual(rings[0][1], LatLon(lat: 46.624, lon: 14.306))
        XCTAssertEqual(atlas.areas[1].gaps, [.metro, .trams])
        XCTAssertEqual(atlas.areas[1].mapURL(german: true).absoluteString, "https://publit.eu/abdeckung/?lang=de#yy/%C3%84")
        XCTAssertTrue(atlas.areas[1].contains(LatLon(lat: 10.02, lon: 20.0)))
        XCTAssertFalse(atlas.areas[1].contains(LatLon(lat: 10.06, lon: 20.0)))
    }

    func testNoticesMergeAndSort() throws {
        let klagenfurt = LatLon(lat: 46.623, lon: 14.308)
        let villach = LatLon(lat: 46.61, lon: 13.845)
        let valletta = LatLon(lat: 35.8989, lon: 14.5146)
        // Start and destination in the same area: one notice.
        let both = CoverageGuide.notices(start: klagenfurt, destination: villach)
        XCTAssertEqual(both.count, 1)
        XCTAssertEqual(both[0].roles, [.start, .destination])
        XCTAssertEqual(both[0].heading, both[0].area.name)
        // Only the destination: the heading says so; the worse gap comes first.
        let mixed = CoverageGuide.notices(start: klagenfurt, destination: valletta)
        XCTAssertEqual(mixed.map(\.area.level), [.none, .partial])
        XCTAssertEqual(mixed[0].roles, [.destination])
        XCTAssertTrue(mixed[0].heading.hasPrefix(L10n.t("To")))
        XCTAssertTrue(CoverageGuide.notices(start: LatLon(lat: 48.2, lon: 16.37), destination: nil).isEmpty)
        XCTAssertNil(CoverageGuide.notice(at: nil))
        XCTAssertEqual(CoverageGuide.notice(at: klagenfurt)?.roles, [.here])
    }

    func testEveryGapHasAWordAndEveryAreaASummary() {
        for gap in CoverageGap.allCases { XCTAssertFalse(gap.title.isEmpty) }
        for a in atlas.areas { XCTAssertFalse(a.summary.isEmpty, a.id); XCTAssertFalse(a.nameEN.isEmpty, a.id); XCTAssertFalse(a.nameDE.isEmpty, a.id) }
        XCTAssertEqual(CoverageGuide.mapURL.host, "publit.eu")
    }

    func testLookupIsFast() {
        let points = (0..<2000).map { LatLon(lat: 35 + Double($0 % 40), lon: -10 + Double($0 % 55)) }
        measure { for p in points { _ = atlas.area(at: p) } }
    }

    // MARK: Along a trip

    private func leg(_ mode: String, from: (Double, Double), to: (Double, Double), start: Double) throws -> Leg {
        let t0 = 1_791_360_000.0
        func iso(_ m: Double) -> String { DateParsing.format(Date(timeIntervalSince1970: t0 + m * 60)) }
        let json = """
        {"mode":"\(mode)","from":{"name":"A","lat":\(from.0),"lon":\(from.1)},"to":{"name":"B","lat":\(to.0),"lon":\(to.1)},
         "duration":600,"startTime":"\(iso(start))","endTime":"\(iso(start + 10))",
         "scheduledStartTime":"\(iso(start))","scheduledEndTime":"\(iso(start + 10))",
         "realTime":false,"legGeometry":{"points":"","precision":6,"length":0}}
        """
        return try TransitousClient.makeDecoder().decode(Leg.self, from: Data(json.utf8))
    }

    private func trip(_ legs: [Leg]) -> Itinerary {
        Itinerary(id: "x", duration: 600 * legs.count, startTime: legs.first!.startTime, endTime: legs.last!.endTime, transfers: 0, legs: legs)
    }

    func testTripNoticesStartChangeAndDestination() throws {
        let vienna = (48.2082, 16.3738), klagenfurt = (46.623, 14.308), graz = (47.0707, 15.4395)
        // Vienna -> Graz -> Klagenfurt: only the end lies in the flagged area.
        let it = trip([try leg("WALK", from: vienna, to: vienna, start: 0),
                       try leg("RAIL", from: vienna, to: graz, start: 5),
                       try leg("RAIL", from: graz, to: klagenfurt, start: 40)])
        let notices = CoverageGuide.notices(for: it)
        XCTAssertEqual(notices.count, 1)
        XCTAssertEqual(notices[0].roles, [.destination])
        // Changing in Klagenfurt on the way to Vienna: the stop in the area counts as "here".
        let through = trip([try leg("RAIL", from: graz, to: klagenfurt, start: 0), try leg("RAIL", from: klagenfurt, to: vienna, start: 20)])
        XCTAssertEqual(CoverageGuide.notices(for: through).first?.roles, [.here])
        // Everything else (Vienna to Graz) gets none.
        XCTAssertTrue(CoverageGuide.notices(for: trip([try leg("RAIL", from: vienna, to: graz, start: 0)])).isEmpty)
        // A walk in the area does not depend on timetable data.
        XCTAssertTrue(CoverageGuide.notices(for: trip([try leg("WALK", from: klagenfurt, to: klagenfurt, start: 0)])).isEmpty)
    }
}

import XCTest
@testable import Publit

final class LineColorTests: XCTestCase {
    func testKeepsLegibleOperatorTextColour() {
        let p = LineColors.resolve(routeColor: "E3000F", routeTextColor: "ffffff", fallback: "000000")
        XCTAssertEqual(p, .init(background: "E3000F", text: "FFFFFF"))
    }

    func testReplacesIllegibleDefaultWhiteOnLightLine() {
        // Munich S1 (light blue) comes without a text colour; white on it is about 2.3:1.
        let p = LineColors.resolve(routeColor: "16c0e9", routeTextColor: nil, fallback: "000000")
        XCTAssertEqual(p.text, "000000")
        let ratio = LineColors.contrast(LineColors.RGB(hex: p.text)!, LineColors.RGB(hex: p.background)!)
        XCTAssertGreaterThanOrEqual(ratio, 4.5)
    }

    func testReplacesOperatorPairBelowThreshold() {
        let p = LineColors.resolve(routeColor: "FFD800", routeTextColor: "FFFFFF", fallback: "000000")
        XCTAssertEqual(p.text, "000000")
    }

    func testFallsBackToModeColourWhenFeedHasNone() {
        let p = LineColors.resolve(routeColor: nil, routeTextColor: "000000", fallback: ModeStyle.defaultHex("BUS"))
        XCTAssertEqual(p.background, "2973CC")
        XCTAssertEqual(p.text, "FFFFFF")
    }

    func testRejectsMalformedHex() {
        XCTAssertNil(LineColors.RGB(hex: "12345"))
        XCTAssertNil(LineColors.RGB(hex: "zzzzzz"))
        XCTAssertNotNil(LineColors.RGB(hex: "#0065ae"))
    }

    func testWhiteBlackContrastIs21() {
        XCTAssertEqual(LineColors.contrast(LineColors.white, LineColors.black), 21, accuracy: 0.01)
    }
}

final class GroupingTests: XCTestCase {
    func testMergesPlatformsOfOneStationWithDifferentParentIds() throws {
        // Live sample: Marienplatz arrives as three IDs (no parent, "_G" parent, bus stop).
        let res = try TransitousClient.makeDecoder()
            .decode(StopTimesResponse.self, from: Fixtures.data("stoptimes_marienplatz"))
        let rawKeys = Set(res.stopTimes.filter { $0.place.name == "Marienplatz" }.map(\.place.stationId))
        XCTAssertGreaterThan(rawKeys.count, 1, "fixture should reproduce the duplicate-station bug")

        let groups = StopGrouping.group(res.stopTimes, around: LatLon(lat: 48.1372, lon: 11.5755))
        XCTAssertEqual(groups.filter { $0.name == "Marienplatz" }.count, 1)
        XCTAssertEqual(Set(groups.map(\.name)).count, groups.count, "every station name appears once")
        XCTAssertEqual(groups.first?.name, "Marienplatz", "nearest station first")
        XCTAssertEqual(groups.reduce(0) { $0 + $1.departures.count }, res.stopTimes.count, "no departure lost")
    }

    func testDeparturesInsideGroupAreChronological() throws {
        let res = try TransitousClient.makeDecoder()
            .decode(StopTimesResponse.self, from: Fixtures.data("stoptimes_marienplatz"))
        for g in StopGrouping.group(res.stopTimes, around: nil) {
            XCTAssertEqual(g.departures.map(\.departureTime), g.departures.map(\.departureTime).sorted())
        }
    }

    func testNameNormalisationIgnoresCaseAndAccents() {
        XCTAssertEqual(StopGrouping.normalizedName(" Bari Centrale "), StopGrouping.normalizedName("bari centrale"))
        XCTAssertEqual(StopGrouping.normalizedName("Kadıköy"), StopGrouping.normalizedName("Kadiköy"))
    }

    func testHaversineDistance() {
        let marienplatz = LatLon(lat: 48.137, lon: 11.5754)
        let hbf = LatLon(lat: 48.1402, lon: 11.5586)
        XCTAssertEqual(marienplatz.distance(to: hbf), 1300, accuracy: 60)
        XCTAssertEqual(hbf.distance(to: hbf), 0, accuracy: 0.001)
    }
}

final class TransferRiskTests: XCTestCase {
    private func leg(_ mode: String, _ from: String, _ to: String, start: Int, end: Int,
                     scheduledEnd: Int? = nil, realTime: Bool = true) throws -> Leg {
        let t0 = 1_791_360_000.0
        func iso(_ m: Int) -> String { DateParsing.format(Date(timeIntervalSince1970: t0 + Double(m) * 60)) }
        let json = """
        {"mode":"\(mode)","from":{"name":"\(from)","lat":48,"lon":11},"to":{"name":"\(to)","lat":48,"lon":11},
         "duration":\((end - start) * 60),"startTime":"\(iso(start))","endTime":"\(iso(end))",
         "scheduledStartTime":"\(iso(start))","scheduledEndTime":"\(iso(scheduledEnd ?? end))",
         "realTime":\(realTime),"legGeometry":{"points":"","precision":6,"length":0}}
        """
        return try TransitousClient.makeDecoder().decode(Leg.self, from: Data(json.utf8))
    }

    private func itinerary(_ legs: [Leg]) -> Itinerary {
        Itinerary(id: "t", duration: 0, startTime: legs.first!.startTime, endTime: legs.last!.endTime,
                  transfers: legs.filter(\.isTransit).count - 1, legs: legs)
    }

    func testNoWarningForComfortableChange() throws {
        let it = itinerary([try leg("SUBWAY", "A", "B", start: 0, end: 8),
                            try leg("WALK", "B", "B", start: 8, end: 10),
                            try leg("BUS", "B", "C", start: 14, end: 30)])
        XCTAssertTrue(TransferRisk.warnings(for: it).isEmpty)
    }

    func testTightWhenIncomingIsLateAndBufferSmall() throws {
        let it = itinerary([try leg("SUBWAY", "A", "Nordfriedhof", start: 0, end: 10, scheduledEnd: 8),
                            try leg("WALK", "Nordfriedhof", "Nordfriedhof", start: 10, end: 12),
                            try leg("BUS", "Nordfriedhof", "C", start: 13, end: 30)])
        let w = TransferRisk.warnings(for: it)
        XCTAssertEqual(w.count, 1)
        XCTAssertEqual(w.first?.level, .tight)
        XCTAssertEqual(w.first?.bufferMinutes, 1)
        XCTAssertEqual(w.first?.message, "Tight change at Nordfriedhof (1 min)")
    }

    func testMissedWhenWalkLongerThanGap() throws {
        let it = itinerary([try leg("SUBWAY", "A", "B", start: 0, end: 10, scheduledEnd: 6),
                            try leg("WALK", "B", "B", start: 10, end: 14),
                            try leg("BUS", "B", "C", start: 12, end: 30)])
        XCTAssertEqual(TransferRisk.warnings(for: it).first?.level, .missed)
    }

    func testDirectTripHasNoWarnings() throws {
        let it = itinerary([try leg("WALK", "Home", "A", start: 0, end: 3),
                            try leg("SUBURBAN", "A", "Airport", start: 5, end: 45)])
        XCTAssertTrue(TransferRisk.warnings(for: it).isEmpty)
    }

    func testLiveFixtureHasNoFalseAlarms() throws {
        let plan = try TransitousClient.makeDecoder().decode(PlanResponse.self, from: Fixtures.data("plan_muc"))
        XCTAssertEqual(plan.itineraries.count, 3)
        for it in plan.itineraries { XCTAssertTrue(TransferRisk.warnings(for: it).isEmpty) }
    }
}

final class FormattingTests: XCTestCase {
    func testChangesAndStopsPluralisation() {
        XCTAssertEqual(Fmt.changes(0), "Direct")
        XCTAssertEqual(Fmt.changes(1), "1 change")
        XCTAssertEqual(Fmt.changes(3), "3 changes")
        XCTAssertEqual(Fmt.stops(1), "1 stop")
    }

    func testDuration() {
        XCTAssertEqual(Fmt.duration(seconds: 20), "1 min")
        XCTAssertEqual(Fmt.duration(seconds: 2520), "42 min")
        XCTAssertEqual(Fmt.duration(seconds: 3600), "1 h")
        XCTAssertEqual(Fmt.duration(seconds: 5400), "1 h 30 min")
    }

    func testTimeUsesStopTimeZone() throws {
        let d = try XCTUnwrap(DateParsing.parse("2026-10-07T06:15:00Z"))
        XCTAssertTrue(Fmt.time(d, tz: "Europe/Istanbul").contains("9:15"), Fmt.time(d, tz: "Europe/Istanbul"))
        XCTAssertTrue(Fmt.time(d, tz: "Europe/Vienna").contains("8:15"), Fmt.time(d, tz: "Europe/Vienna"))
    }

    func testForeignZoneNote() throws {
        let d = try XCTUnwrap(DateParsing.parse("2026-10-07T06:15:00Z"))
        let vienna = try XCTUnwrap(TimeZone(identifier: "Europe/Vienna"))
        XCTAssertEqual(Fmt.foreignZoneNote(tz: "Europe/Istanbul", at: d, device: vienna), "Local time Istanbul (GMT+3)")
        XCTAssertNil(Fmt.foreignZoneNote(tz: "Europe/Rome", at: d, device: vienna))
        XCTAssertNil(Fmt.foreignZoneNote(tz: nil, at: d, device: vienna))
    }
}

@MainActor
final class FavoritesTests: XCTestCase {
    private func store() -> FavoritesStore {
        let d = UserDefaults(suiteName: "publit-tests-\(UUID().uuidString)")!
        return FavoritesStore(defaults: d)
    }

    private let a = SavedPlace(id: "a", name: "Flat", subtitle: nil, lat: 48.2, lon: 16.3, stopId: nil)
    private let b = SavedPlace(id: "b", name: "Office", subtitle: nil, lat: 48.4, lon: 15.6, stopId: nil)

    func testHomeAndWorkAreExclusiveSlots() async {
        let s = store()
        s.set(a, as: .home)
        s.set(b, as: .home)
        XCTAssertEqual(s.place(for: .home)?.id, "b")
        XCTAssertEqual(s.items.filter { $0.role == .home }.count, 1)
        XCTAssertTrue(s.places.contains { $0.id == "a" }, "previous Home stays as a normal saved place")
    }

    func testPinnedPlacesAreNotListedTwice() async {
        let s = store()
        s.set(a, as: .work)
        XCTAssertTrue(s.places.isEmpty)
        XCTAssertEqual(s.pinned.map(\.id), ["a"])
    }

    func testPersistsAcrossInstancesAndReadsOldFormat() async throws {
        let suite = "publit-tests-\(UUID().uuidString)"
        let old = #"[{"id":"x","name":"Old","lat":1,"lon":2}]"#
        UserDefaults(suiteName: suite)!.set(Data(old.utf8), forKey: "publit.favorites.v1")
        let s = FavoritesStore(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertEqual(s.items.first?.name, "Old")
        s.set(a, as: .home)
        let again = FavoritesStore(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertEqual(again.place(for: .home)?.id, "a")
    }
}

@MainActor
final class PlanModelTests: XCTestCase {
    func testMissingLocationExplainsWhatToDo() async {
        let m = PlanModel()
        m.to = .place(SavedPlace(id: "t", name: "T", subtitle: nil, lat: 1, lon: 1, stopId: nil))
        await m.search(current: nil, locationDenied: true)
        XCTAssertEqual(m.errorMessage?.hasPrefix("Location is off"), true)
        await m.search(current: nil, locationDenied: false)
        XCTAssertEqual(m.errorMessage, "Waiting for your location…")
    }

    func testQueryKeyChangesWithInputs() async {
        let m = PlanModel()
        let k0 = m.queryKey
        m.timeMode = .arriveBy
        XCTAssertNotEqual(m.queryKey, k0)
    }

    func testDemoPreset() async {
        let app = AppState()
        app.applyDemo("munich")
        XCTAssertEqual(app.plan.to?.title, "Flughafen München")
        app.applyDemo(nil)
        XCTAssertEqual(app.plan.from.title, "Marienplatz")
    }
}

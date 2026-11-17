import XCTest
@testable import Publit

final class SmartRoutingTests: XCTestCase {
    private func leg(_ mode: String, _ from: String, _ to: String, start: Int, end: Int, realTime: Bool = false) throws -> Leg {
        let t0 = 1_791_360_000.0
        func iso(_ m: Int) -> String { DateParsing.format(Date(timeIntervalSince1970: t0 + Double(m) * 60)) }
        let json = """
        {"mode":"\(mode)","from":{"name":"\(from)","lat":48,"lon":11},"to":{"name":"\(to)","lat":48,"lon":11},
         "duration":\((end - start) * 60),"startTime":"\(iso(start))","endTime":"\(iso(end))",
         "scheduledStartTime":"\(iso(start))","scheduledEndTime":"\(iso(end))",
         "realTime":\(realTime),"tripId":"\(mode)-\(from)-\(start)","legGeometry":{"points":"","precision":6,"length":0}}
        """
        return try TransitousClient.makeDecoder().decode(Leg.self, from: Data(json.utf8))
    }

    private func itinerary(_ legs: [Leg]) -> Itinerary {
        Itinerary(id: UUID().uuidString, duration: Int(legs.last!.endTime.timeIntervalSince(legs.first!.startTime)),
                  startTime: legs.first!.startTime, endTime: legs.last!.endTime,
                  transfers: max(0, legs.filter(\.isTransit).count - 1), legs: legs)
    }

    private let w = SmartRouting.Weights()

    func testChanceGrowsWithSpareTimeAndDependsOnTheVehicle() throws {
        let subway = try leg("SUBWAY", "A", "B", start: 0, end: 10)
        let train = try leg("REGIONAL_RAIL", "A", "B", start: 0, end: 10)
        let tight = SmartRouting.chance(spareMinutes: 0, walkSeconds: 120, incoming: subway)
        let roomy = SmartRouting.chance(spareMinutes: 5, walkSeconds: 120, incoming: subway)
        XCTAssertLessThan(tight, roomy)
        XCTAssertGreaterThan(roomy, 0.95)
        // Trains run late more often than the underground: the same 2 minutes are less sure.
        XCTAssertLessThan(SmartRouting.chance(spareMinutes: 2, walkSeconds: 60, incoming: train),
                          SmartRouting.chance(spareMinutes: 2, walkSeconds: 60, incoming: subway))
        XCTAssertLessThan(SmartRouting.chance(spareMinutes: -3, walkSeconds: 60, incoming: train), 0.1)
    }

    func testChangesAndReliability() throws {
        let it = itinerary([try leg("WALK", "Home", "A", start: 0, end: 5),
                            try leg("SUBWAY", "A", "B", start: 5, end: 15),
                            try leg("WALK", "B", "B", start: 15, end: 17),
                            try leg("BUS", "B", "C", start: 19, end: 30)])
        let changes = SmartRouting.changes(it)
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes[0].stopName, "B")
        XCTAssertEqual(changes[0].spareMinutes, 2, accuracy: 0.01)
        XCTAssertEqual(changes[0].outgoingIndex, 3)
        XCTAssertEqual(SmartRouting.reliability(it), changes[0].chance, accuracy: 0.0001)
        XCTAssertLessThan(changes[0].percent, 100)
    }

    func testRecommendsTheDirectRideOverASlightlyFasterOneWithAChange() throws {
        let direct = itinerary([try leg("BUS", "A", "C", start: 0, end: 34)])
        let change = itinerary([try leg("SUBWAY", "A", "B", start: 0, end: 12),
                                try leg("SUBWAY", "B", "C", start: 14, end: 30)])
        XCTAssertEqual(SmartRouting.recommended([change, direct], weights: w)?.routeKey, direct.routeKey)
        // Much faster with the change: then the change is worth it.
        let quick = itinerary([try leg("SUBWAY", "A", "B", start: 0, end: 6),
                               try leg("SUBWAY", "B", "C", start: 10, end: 14)])
        XCTAssertEqual(SmartRouting.recommended([quick, direct], weights: w)?.routeKey, quick.routeKey)
        XCTAssertEqual(SmartRouting.reason(for: direct, in: [change, direct]), L10n.t("One change fewer"))
        let badges = SmartRouting.badges([change, direct], weights: w)
        XCTAssertEqual(badges[direct.routeKey], [.recommended, .fewestChanges])
        XCTAssertEqual(badges[change.routeKey], [.fastest])
    }

    func testPrunedDropsRoutesBeatenOnEverything() throws {
        let early = itinerary([try leg("SUBWAY", "A", "C", start: 0, end: 42)])
        let later = itinerary([try leg("SUBWAY", "A", "C", start: 12, end: 42)])
        let walk = itinerary([try leg("WALK", "A", "C", start: 0, end: 50)])
        let kept = SmartRouting.pruned([early, later, walk])
        XCTAssertEqual(kept.map(\.routeKey), [later.routeKey, walk.routeKey])
    }

    func testBackupIsTheNextVehicleThatStillWorks() throws {
        var ride = try leg("BUS", "B", "C", start: 20, end: 30)
        let earlier = [try leg("WALK", "B", "B", start: 14, end: 15), try leg("BUS", "B", "C", start: 15, end: 25), try leg("WALK", "C", "C", start: 25, end: 26)]
        let later = [try leg("WALK", "B", "B", start: 25, end: 27), try leg("TRAM", "B", "C", start: 27, end: 38), try leg("WALK", "C", "C", start: 38, end: 40)]
        ride.alternatives = [earlier, later]
        let backup = try XCTUnwrap(SmartRouting.backup(for: ride))
        XCTAssertEqual(backup.leg.mode, "TRAM")
        XCTAssertEqual(backup.arrival, later[2].endTime)
        ride.alternatives = [earlier]
        XCTAssertNil(SmartRouting.backup(for: ride))
    }

    func testPickingFewerChangesRaisesTheirWeight() throws {
        let change = itinerary([try leg("SUBWAY", "A", "B", start: 0, end: 6),
                                try leg("SUBWAY", "B", "C", start: 10, end: 14)])
        let direct = itinerary([try leg("BUS", "A", "C", start: 0, end: 34)])
        let learned = SmartRouting.learned(chosen: direct, offered: [change, direct], arriveBy: false, weights: w)
        XCTAssertEqual(learned.transferMinutes, w.transferMinutes + 2)
        let same = SmartRouting.learned(chosen: change, offered: [change, direct], arriveBy: false, weights: w)
        XCTAssertEqual(same, w)
    }

    func testRequestAddsItsParametersOnlyWhenOn() {
        XCTAssertTrue(SmartRouting.Request().queryItems.isEmpty)
        let on = SmartRouting.Request(enabled: true, pedestrianSpeed: 1.25, extraTransferMinutes: 5, flatWalks: true)
        let d = Dictionary(uniqueKeysWithValues: on.queryItems.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(d["numLegAlternatives"], "2")
        XCTAssertEqual(d["pedestrianSpeed"], "1.25")
        XCTAssertEqual(d["additionalTransferTime"], "5")
        XCTAssertEqual(d["elevationCosts"], "LOW")
        XCTAssertNotEqual(on.key, SmartRouting.Request().key)
    }

    func testOldSavedTripsDecodeWithoutAlternatives() throws {
        let plan = try TransitousClient.makeDecoder().decode(PlanResponse.self, from: Fixtures.data("plan"))
        XCTAssertTrue(plan.itineraries.allSatisfy { $0.legs.allSatisfy { ($0.alternatives ?? []).isEmpty } })
    }

    // MARK: Change chance, own trips, warnings

    private func ride(_ mode: String, _ from: String, _ to: String, start: Int, end: Int, realTime: Bool = false,
                      tripId: String? = nil, cancelled: Bool = false, track: String? = nil, scheduledTrack: String? = nil,
                      stationOf stop: String? = nil) throws -> Leg {
        let t0 = 1_791_360_000.0
        func iso(_ m: Int) -> String { DateParsing.format(Date(timeIntervalSince1970: t0 + Double(m) * 60)) }
        let tracks = track.map { ",\"track\":\"\($0)\",\"scheduledTrack\":\"\(scheduledTrack ?? $0)\"" } ?? ""
        let json = """
        {"mode":"\(mode)","from":{"name":"\(from)","stopId":"\(from)","lat":48,"lon":11\(tracks)},
         "to":{"name":"\(to)","stopId":"\(stop ?? to)","lat":48,"lon":11},
         "duration":\((end - start) * 60),"startTime":"\(iso(start))","endTime":"\(iso(end))",
         "scheduledStartTime":"\(iso(start))","scheduledEndTime":"\(iso(end))","cancelled":\(cancelled),
         "realTime":\(realTime),"tripId":"\(tripId ?? "\(mode)-\(from)-\(start)")","legGeometry":{"points":"","precision":6,"length":0}}
        """
        return try TransitousClient.makeDecoder().decode(Leg.self, from: Data(json.utf8))
    }

    private var t0: Date { Date(timeIntervalSince1970: 1_791_360_000) }

    func testOutgoingLiveDelayAndShortForecastsMakeAChangeSurer() throws {
        let walk = TransferWalk(plannedSeconds: 120)
        let incoming = try ride("REGIONAL_RAIL", "A", "B", start: 0, end: 10, realTime: true)
        let outgoing = try ride("BUS", "B", "C", start: 14, end: 30, realTime: true)
        // Arrival forecast an hour ahead is less sure than five minutes ahead.
        let far = SmartRouting.assess(spareMinutes: 2, walk: walk, incoming: incoming, outgoing: outgoing, at: t0.addingTimeInterval(-3600)).chance
        let near = SmartRouting.assess(spareMinutes: 2, walk: walk, incoming: incoming, outgoing: outgoing, at: t0.addingTimeInterval(300)).chance
        XCTAssertLessThan(far, near)
        // An estimate never says 99 %.
        let roomy = SmartRouting.assess(spareMinutes: 30, walk: walk, incoming: incoming, outgoing: outgoing, at: t0)
        XCTAssertEqual(roomy.basis, .estimate)
        XCTAssertLessThanOrEqual(roomy.chance, SmartRouting.estimateCap)
    }

    func testThroughRunIsSafeAndCancellationBreaksTheChange() throws {
        let a = try ride("REGIONAL_RAIL", "A", "B", start: 0, end: 10, tripId: "same")
        let b = try ride("REGIONAL_RAIL", "B", "C", start: 10, end: 30, tripId: "same")
        let through = SmartRouting.assess(spareMinutes: -1, walk: TransferWalk(), incoming: a, outgoing: b, at: t0)
        XCTAssertEqual(through.basis, .throughRun)
        XCTAssertGreaterThan(through.chance, 0.99)
        let gone = try ride("BUS", "B", "C", start: 20, end: 30, cancelled: true)
        XCTAssertLessThan(SmartRouting.assess(spareMinutes: 8, walk: TransferWalk(), incoming: a, outgoing: gone, at: t0).chance, 0.05)
    }

    func testWalkShapeCountsPlatformAndStationChanges() throws {
        let incoming = try ride("SUBURBAN", "A", "B", start: 0, end: 10, stationOf: "B1")
        let moved = try ride("REGIONAL_RAIL", "B2", "C", start: 15, end: 30, track: "7", scheduledTrack: "3")
        let shape = TransferWalk.of(incoming: incoming, outgoing: moved, walks: [])
        XCTAssertTrue(shape.platformChanged)
        XCTAssertTrue(shape.stationChange)
        // A changed platform needs more time than the plan says: lower chance, same spare minutes.
        let plain = TransferWalk(plannedSeconds: 120)
        var harder = plain
        harder.platformChanged = true
        XCTAssertLessThan(SmartRouting.assess(spareMinutes: 2, walk: harder, incoming: incoming, outgoing: moved, at: t0).chance,
                          SmartRouting.assess(spareMinutes: 2, walk: plain, incoming: incoming, outgoing: moved, at: t0).chance)
    }

    func testWalkModelStartsAtThePlanAndLearnsAPersonalPaceThatCarriesOver() {
        var m = TransferLearning.Model()
        let known = TransferWalk(plannedSeconds: 180)
        XCTAssertEqual(m.predict(known).mean, 198, accuracy: 1, "prior: the planned walk plus 10 %")
        // A slow walker: 1.5 times the plan on a few changes.
        for s in [120.0, 180, 240, 300] { m.add(TransferWalk(plannedSeconds: s), seconds: s * 1.5) }
        let few = m.predict(known).mean
        XCTAssertGreaterThan(few, 198)
        for _ in 0..<5 { for s in [120.0, 180, 240, 300] { m.add(TransferWalk(plannedSeconds: s), seconds: s * 1.5) } }
        let many = m.predict(known).mean
        XCTAssertGreaterThan(many, few, "more own changes count more")
        XCTAssertEqual(many, 270, accuracy: 25)
        // Carries over to a change never made: a longer walk, also slower than planned.
        XCTAssertGreaterThan(m.predict(TransferWalk(plannedSeconds: 600)).mean, 600 * 1.3)
        // Stairs: learned extra time per floor.
        var stairs = TransferLearning.Model()
        for s in [120.0, 200, 300] {
            stairs.add(TransferWalk(plannedSeconds: s, levels: 2), seconds: s * 1.1 + 2 * 40)
            stairs.add(TransferWalk(plannedSeconds: s), seconds: s * 1.1)
        }
        for _ in 0..<4 { for s in [120.0, 200, 300] {
            stairs.add(TransferWalk(plannedSeconds: s, levels: 2), seconds: s * 1.1 + 2 * 40)
            stairs.add(TransferWalk(plannedSeconds: s), seconds: s * 1.1)
        } }
        XCTAssertGreaterThan(stairs.coefficients[1], 20, "seconds per floor move from 10 towards 40")
    }

    func testOwnOutcomesMoveTheChanceSlowly() {
        XCTAssertEqual(TransferLearning.adjusted(0.8, by: nil), 0.8)
        let two = TransferLearning.adjusted(0.8, by: .init(made: 0, missed: 2))
        XCTAssertGreaterThan(two, 0.6, "two misses barely move it")
        let many = TransferLearning.adjusted(0.8, by: .init(made: 2, missed: 30))
        XCTAssertLessThan(many, 0.3)
    }

    func testSolveSmallSystem() throws {
        let x = try XCTUnwrap(TransferLearning.solve([2, 1, 1, 3], [3, 5]))
        XCTAssertEqual(x[0], 0.8, accuracy: 1e-9)
        XCTAssertEqual(x[1], 1.4, accuracy: 1e-9)
    }

    func testTimeWindows() {
        // 1_791_360_000 = Wed 2026-10-07 08:00 UTC.
        XCTAssertEqual(TransferLearning.timeWindow(t0, tz: "UTC"), "peak")
        XCTAssertEqual(TransferLearning.timeWindow(t0.addingTimeInterval(3 * 3600), tz: "UTC"), "day")
        XCTAssertEqual(TransferLearning.timeWindow(t0.addingTimeInterval(-4 * 3600), tz: "UTC"), "night")
        XCTAssertEqual(TransferLearning.timeWindow(t0.addingTimeInterval(3 * 86_400), tz: "UTC"), "weekend")
    }

    func testRecorderOutcomeMadeMissedOrUnknown() throws {
        let it = itinerary([try ride("SUBWAY", "A", "B", start: 0, end: 10),
                            try leg("WALK", "B", "B2", start: 10, end: 13),
                            try ride("BUS", "B2", "C", start: 15, end: 30)])
        let c = try XCTUnwrap(SmartRouting.changes(it, at: t0).first)
        let stop = c.outgoing.from.coordinate
        let made = try XCTUnwrap(TransferRecorder.outcome(c, reached: t0.addingTimeInterval(13 * 60), fix: stop, now: t0.addingTimeInterval(18 * 60)))
        XCTAssertTrue(made.made)
        XCTAssertEqual(made.walkSeconds ?? 0, 180, accuracy: 0.1)
        let late = try XCTUnwrap(TransferRecorder.outcome(c, reached: t0.addingTimeInterval(16 * 60), fix: stop, now: t0.addingTimeInterval(18 * 60)))
        XCTAssertFalse(late.made)
        let far = LatLon(lat: 48.1, lon: 11.1)
        XCTAssertNil(TransferRecorder.outcome(c, reached: nil, fix: far, now: t0.addingTimeInterval(18 * 60)))
    }

    func testWarningsAreNotRepeated() {
        XCTAssertTrue(TransferLearning.warningDue(chance: 0.4, cancelled: false, lastWarned: nil))
        XCTAssertFalse(TransferLearning.warningDue(chance: 0.35, cancelled: false, lastWarned: 0.4))
        XCTAssertTrue(TransferLearning.warningDue(chance: 0.15, cancelled: false, lastWarned: 0.4))
        XCTAssertTrue(TransferLearning.warningDue(chance: 0.01, cancelled: true, lastWarned: 0.4))
        XCTAssertFalse(TransferLearning.warningDue(chance: 0.01, cancelled: true, lastWarned: 0.01))
    }

    func testNoWarningForAThroughRun() throws {
        let it = itinerary([try ride("REGIONAL_RAIL", "A", "B", start: 0, end: 10, tripId: "x"),
                            try ride("REGIONAL_RAIL", "B", "C", start: 10, end: 30, tripId: "x")])
        XCTAssertNil(SmartRouting.changeAtRisk(it, at: t0))
    }
}

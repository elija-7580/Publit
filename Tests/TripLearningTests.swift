import XCTest
@testable import Publit

/// "Learn from my trips" (walking model, own success rates, recorder) and the change alerts.
final class TripLearningTests: XCTestCase {
    private let t0 = 1_791_360_000.0

    private func obs(planned: Double, actual: Double?, levels: Double = 0, elevators: Int = 0, made: Bool = true, key: String = "k") -> TripLearning.Observation {
        TripLearning.Observation(date: Date(timeIntervalSince1970: t0), key: key,
                                 walk: .init(TransferWalk(plannedSeconds: planned, levels: levels, elevators: elevators)),
                                 walkSeconds: actual, made: made, spareSeconds: 60, feederDelay: 0, connectionDelay: 0)
    }

    // MARK: Walking model

    func testStartsFromTheGeneralModel() {
        XCTAssertEqual(TripLearning.walkModel(from: []), .prior)
        XCTAssertEqual(TripLearning.walkModel(from: [obs(planned: 120, actual: nil)]), .prior)
    }

    func testFewTripsMoveItLittleManyMore() {
        // This user needs twice the planned time.
        let few = TripLearning.walkModel(from: (0..<2).map { _ in obs(planned: 180, actual: 360) })
        let many = TripLearning.walkModel(from: (0..<60).map { (i: Int) -> TripLearning.Observation in
            let planned = Double(120 + (i % 5) * 60)
            return obs(planned: planned, actual: planned * 2)
        })
        let walk = TransferWalk(plannedSeconds: 180)
        let prior = WalkModel.prior.expectedSeconds(walk)
        XCTAssertGreaterThan(few.expectedSeconds(walk), prior)
        XCTAssertLessThan(few.expectedSeconds(walk), 280, "two trips must not move it all the way")
        XCTAssertEqual(many.expectedSeconds(walk), 360, accuracy: 25)
        XCTAssertEqual(many.observations, 60)
        // Consistent data: the model is surer of itself than the general one.
        XCTAssertLessThan(many.spread(walk), WalkModel.prior.spread(walk))
    }

    func testStairsAndLiftsCarryOverToChangesNeverMade() {
        // Planned walks the same, but each level costs this user 40 s and each lift 90 s.
        var list: [TripLearning.Observation] = []
        for i in 0..<40 {
            let levels = Double(i % 4), lifts = i % 3 == 0 ? 1 : 0
            list.append(obs(planned: 150, actual: 150 * 1.05 + levels * 40 + Double(lifts) * 90, levels: levels, elevators: lifts))
        }
        let m = TripLearning.walkModel(from: list)
        XCTAssertGreaterThan(m.perLevel, 25)
        XCTAssertGreaterThan(m.perElevator, 60)
        // A change with 5 levels and 2 lifts – never made – is expected to take longer than the general model says.
        let unknown = TransferWalk(plannedSeconds: 200, levels: 5, elevators: 2)
        XCTAssertGreaterThan(m.expectedSeconds(unknown), WalkModel.prior.expectedSeconds(unknown) + 120)
    }

    func testOwnSuccessRateForChangesMadeOften() {
        let missed = (0..<5).map { _ in obs(planned: 120, actual: 150, made: false, key: "A") }
        XCTAssertLessThan(TripLearning.adjusted(0.9, key: "A", observations: missed), 0.5)
        XCTAssertEqual(TripLearning.adjusted(0.9, key: "B", observations: missed), 0.9)
        XCTAssertEqual(TripLearning.adjusted(0.9, key: "A", observations: Array(missed.prefix(2))), 0.9, "fewer than 3: not used")
    }

    func testInvert() throws {
        let inv = try XCTUnwrap(TripLearning.invert([4, 7, 2, 6], 2))
        XCTAssertEqual(inv[0], 0.6, accuracy: 1e-9); XCTAssertEqual(inv[1], -0.7, accuracy: 1e-9)
        XCTAssertNil(TripLearning.invert([1, 2, 2, 4], 2))
    }

    // MARK: Recorder

    private func leg(_ mode: String, from: (String, Double), to: (String, Double), start: Int, end: Int, trip: String, cancelled: Bool = false) throws -> Leg {
        func iso(_ m: Int) -> String { DateParsing.format(Date(timeIntervalSince1970: t0 + Double(m) * 60)) }
        let json = """
        {"mode":"\(mode)","from":{"name":"\(from.0)","stopId":"x_\(from.0)","lat":\(from.1),"lon":11},"to":{"name":"\(to.0)","stopId":"x_\(to.0)","lat":\(to.1),"lon":11},
         "duration":\((end - start) * 60),"startTime":"\(iso(start))","endTime":"\(iso(end))","scheduledStartTime":"\(iso(start))","scheduledEndTime":"\(iso(end))",
         "realTime":false,"tripId":"\(trip)","cancelled":\(cancelled),"legGeometry":{"points":"","precision":6,"length":0}}
        """
        return try TransitousClient.makeDecoder().decode(Leg.self, from: Data(json.utf8))
    }

    private func trip(cancelled: Bool = false) throws -> Itinerary {
        let legs = [try leg("BUS", from: ("A", 48.00), to: ("B", 48.05), start: 0, end: 10, trip: "t1"),
                    try leg("WALK", from: ("B", 48.05), to: ("B2", 48.0505), start: 10, end: 12, trip: "w"),
                    try leg("BUS", from: ("B2", 48.0505), to: ("C", 48.15), start: 15, end: 30, trip: "t2", cancelled: cancelled)]
        return Itinerary(id: "i", duration: 1800, startTime: legs[0].startTime, endTime: legs[2].endTime, transfers: 1, legs: legs)
    }

    private func at(_ minutes: Double) -> Date { Date(timeIntervalSince1970: t0 + minutes * 60) }

    func testRecorderMeasuresTheWalkAndSeesTheConnectionCaught() throws {
        let it = try trip()
        var rec = TripLearning.Recorder()
        XCTAssertTrue(rec.observe(LatLon(lat: 48.05, lon: 11), accuracy: 10, at: at(10), itinerary: it).isEmpty)
        XCTAssertTrue(rec.observe(LatLon(lat: 48.0505, lon: 11), accuracy: 10, at: at(13.5), itinerary: it).isEmpty)  // at the stop
        let found = rec.observe(LatLon(lat: 48.08, lon: 11), accuracy: 10, at: at(20), itinerary: it)                   // riding on
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found[0].walkSeconds ?? 0, 210, accuracy: 1)
        XCTAssertTrue(found[0].made)
        XCTAssertEqual(found[0].spareSeconds ?? 0, 90, accuracy: 1)
        XCTAssertTrue(rec.observe(LatLon(lat: 48.1, lon: 11), accuracy: 10, at: at(25), itinerary: it).isEmpty, "decided once")
    }

    func testRecorderSeesAMissedConnectionAndIgnoresBadFixes() throws {
        let it = try trip()
        var rec = TripLearning.Recorder()
        XCTAssertTrue(rec.observe(LatLon(lat: 48.0505, lon: 11), accuracy: 200, at: at(13), itinerary: it).isEmpty)
        XCTAssertNil(rec.reached[0])
        let found = rec.observe(LatLon(lat: 48.0505, lon: 11), accuracy: 10, at: at(21), itinerary: it)
        XCTAssertEqual(found.count, 1)
        XCTAssertFalse(found[0].made)
    }

    // MARK: Change alerts

    private func change(_ chance: Double, source: SmartRouting.Change.Source = .history(observations: 100), cancelled: Bool = false) throws -> SmartRouting.Change {
        let it = try trip(cancelled: cancelled)
        return SmartRouting.Change(stopName: "B", incoming: it.legs[0], outgoing: it.legs[2], outgoingIndex: 2, walkSeconds: 120,
                                   spareMinutes: 3, chance: chance, source: source)
    }

    func testAlertThresholdCancellationAndThroughRun() throws {
        let now = at(5)
        XCTAssertTrue(ChangeWatch.due([try change(0.8)], warned: [:], now: now).isEmpty)
        XCTAssertEqual(ChangeWatch.due([try change(0.6)], warned: [:], now: now).count, 1)
        XCTAssertEqual(ChangeWatch.due([try change(0.01, cancelled: true)], warned: [:], now: now).count, 1)
        XCTAssertTrue(ChangeWatch.due([try change(0.2, source: .throughRun)], warned: [:], now: now).isEmpty)
        XCTAssertTrue(ChangeWatch.due([try change(0.6)], warned: [:], now: at(16)).isEmpty, "connection already gone")
    }

    func testNoDoubleAlertsUnlessClearlyWorse() throws {
        let c = try change(0.6)
        let warned = [ChangeWatch.key(c): 0.6]
        XCTAssertTrue(ChangeWatch.due([try change(0.55)], warned: warned, now: at(5)).isEmpty)
        XCTAssertEqual(ChangeWatch.due([try change(0.4)], warned: warned, now: at(5)).count, 1)
        XCTAssertEqual(ChangeWatch.due([try change(0.01, cancelled: true)], warned: warned, now: at(5)).count, 1)
        XCTAssertTrue(ChangeWatch.due([try change(0.01, cancelled: true)], warned: [ChangeWatch.key(c): 0], now: at(5)).isEmpty)
    }

    func testOnFootSlowerThanPlanned() throws {
        let c = try change(0.9)
        // 1 min before the connection, still 500 m away at walking pace: unlikely. At the stop: fine.
        let far = try XCTUnwrap(ChangeWatch.onFoot(c, here: LatLon(lat: 48.046, lon: 11), now: at(14), speed: 1.3, table: nil, model: .prior))
        let there = try XCTUnwrap(ChangeWatch.onFoot(c, here: LatLon(lat: 48.0505, lon: 11), now: at(14), speed: 1.3, table: nil, model: .prior))
        XCTAssertLessThan(far, 0.1)
        XCTAssertGreaterThan(there, 0.9)
        XCTAssertNil(ChangeWatch.onFoot(c, here: LatLon(lat: 48.0505, lon: 11), now: at(2), speed: 1.3, table: nil), "still on the bus")
    }

    func testAlternativesLinkRoundTrip() throws {
        let to = DeepLink.Spot(name: "Home", lat: 48.2, lon: 16.3, stopId: nil)
        let from = DeepLink.Spot(name: "Krems", lat: 48.4, lon: 15.6, stopId: "at-X_1")
        guard case .alternatives(let f, let t) = try XCTUnwrap(DeepLink(url: DeepLink.alternatives(from: from, to: to).url)) else { return XCTFail() }
        XCTAssertEqual(f?.name, "Krems"); XCTAssertEqual(f?.stopId, "at-X_1"); XCTAssertEqual(t.name, "Home")
        guard case .alternatives(nil, _) = try XCTUnwrap(DeepLink(url: DeepLink.alternatives(from: nil, to: to).url)) else { return XCTFail() }
    }
}

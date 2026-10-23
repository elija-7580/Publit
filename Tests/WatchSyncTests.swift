import Foundation
import XCTest
@testable import Publit

/// What the iPhone and the Apple Watch exchange: snapshot, requests, trimming, screens of a trip.
final class WatchSyncTests: XCTestCase {
    private func plan(_ name: String) throws -> PlanResponse {
        try TransitousClient.makeDecoder().decode(PlanResponse.self, from: Fixtures.data(name))
    }

    private func trip(_ id: String, _ it: Itinerary, saved: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> SavedTrip {
        SavedTrip(id: id, itinerary: it, fromName: "Home", toName: "Airport", savedAt: saved)
    }

    private func pass(_ id: String, valid: ClosedRange<Double>? = nil, code: Bool = true, tripId: String? = nil,
                      category: TicketPass.Category = .single, created: Double = 1_700_000_000) -> TicketPass {
        TicketPass(id: id, title: "Ticket \(id)", operatorName: "MVV", category: category, origin: "A", destination: "B",
                   validFrom: valid.map { Date(timeIntervalSince1970: $0.lowerBound) },
                   validUntil: valid.map { Date(timeIntervalSince1970: $0.upperBound) },
                   barcode: code ? TicketPass.Barcode(format: .qr, message: "SECRET-CONTENT", payload: Data([1, 2, 3]),
                                                      descriptor: Data([9, 9]), altText: "No. 123",
                                                      region: .init(x: 0, y: 0, width: 1, height: 1)) : nil,
                   document: TicketPass.Document(file: "x.pdf", kind: .pdf, page: 0), notes: "private note", tripId: tripId,
                   legacyId: "old", createdAt: Date(timeIntervalSince1970: created))
    }

    // MARK: Trimming

    func testTripForWatchKeepsWhatIsShownAndDropsDirectionsAndAlternatives() throws {
        let it = try XCTUnwrap(plan("plan_walk_steps").itineraries.first)
        XCTAssertTrue(it.legs.contains { $0.steps?.isEmpty == false }, "the fixture has walking directions")
        let slim = it.forWatch()
        XCTAssertEqual(slim.id, it.id)
        XCTAssertEqual(slim.legs.count, it.legs.count)
        XCTAssertEqual(slim.routeKey, it.routeKey, "the same route, so a refresh matches it")
        XCTAssertTrue(slim.legs.allSatisfy { $0.steps == nil && $0.alternatives == nil })
        XCTAssertEqual(slim.legs.map(\.lineName), it.legs.map(\.lineName))
        XCTAssertEqual(slim.legs.map(\.startTime), it.legs.map(\.startTime))
        XCTAssertEqual(slim.legs.map(\.legGeometry.points), it.legs.map(\.legGeometry.points), "the map needs the shape")
        let full = try WatchCodec.encode(WatchSnapshot(sentAt: .now, trips: [trip("a", it)]))
        let small = try WatchCodec.encode(WatchSnapshot(sentAt: .now, trips: [trip("a", it).forWatch()]))
        XCTAssertLessThan(small.count, full.count)
    }

    func testLegAlertsAreCutToTwoHeadlines() throws {
        var it = try XCTUnwrap(plan("plan_walk_steps").itineraries.first)
        let alert = Alert(headerText: "Signal fault", descriptionText: String(repeating: "long text ", count: 50), url: "https://x.y")
        it.legs[1].alerts = [alert, alert, alert]
        it.legs[1].from.alerts = [alert]
        let slim = it.forWatch()
        XCTAssertEqual(slim.legs[1].alerts?.count, 2)
        XCTAssertEqual(slim.legs[1].alerts?.first?.headerText, "Signal fault")
        XCTAssertEqual(slim.legs[1].alerts?.first?.descriptionText, "")
        XCTAssertNil(slim.legs[1].from.alerts)
    }

    func testPassForWatchKeepsNothingPrivateThatTheWatchDoesNotNeed() {
        let p = pass("p1").forWatch()
        XCTAssertNil(p.document)
        XCTAssertNil(p.notes)
        XCTAssertNil(p.legacyId)
        XCTAssertEqual(p.barcode?.format, .qr)
        XCTAssertEqual(p.barcode?.altText, "No. 123")
        XCTAssertNil(p.barcode?.message)
        XCTAssertNil(p.barcode?.payload)
        XCTAssertNil(p.barcode?.descriptor)
        XCTAssertNil(p.barcode?.region)
        XCTAssertEqual(p.title, "Ticket p1")
        XCTAssertEqual(p.origin, "A")
    }

    // MARK: Snapshot

    func testSnapshotRoundTripsThroughTheTransferFormat() throws {
        let it = try XCTUnwrap(plan("plan_muc").itineraries.first)
        let now = it.startTime.addingTimeInterval(-600)
        let place = SavedPlace(id: "s1", name: "Marienplatz", subtitle: "München", lat: 48.137, lon: 11.575, stopId: "s1")
        let snap = WatchSnapshot.make(now: now, trips: [trip("t1", it)], activeTripId: "t1", places: [place],
                                      passes: [pass("p1", valid: (now.timeIntervalSince1970 - 100)...(now.timeIntervalSince1970 + 3600))],
                                      ticketsOn: true, codes: ["p1": "p1-1-352.png"], acks: ["a", "b"])
        let back = try WatchCodec.snapshot(from: WatchCodec.encode(snap))
        XCTAssertEqual(back.trips.map(\.id), ["t1"])
        XCTAssertEqual(back.activeTripId, "t1")
        XCTAssertEqual(back.places, [place])
        XCTAssertEqual(back.tickets.map(\.id), ["p1"])
        XCTAssertEqual(back.tickets.first?.code, "p1-1-352.png")
        XCTAssertEqual(back.tickets.first?.pass.barcode?.altText, "No. 123")
        XCTAssertEqual(back.acks, ["a", "b"])
        XCTAssertEqual(back.trips.first?.itinerary.legs.count, it.legs.count)
        XCTAssertEqual(back.sentAt.timeIntervalSince1970, now.timeIntervalSince1970, accuracy: 1)
    }

    func testNoTicketLeavesThePhoneWhenTheyAreOff() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let snap = WatchSnapshot.make(now: now, trips: [], activeTripId: nil, places: [],
                                      passes: [pass("p1", valid: (now.timeIntervalSince1970 - 10)...(now.timeIntervalSince1970 + 10))],
                                      ticketsOn: false, codes: ["p1": "x.png"])
        XCTAssertTrue(snap.tickets.isEmpty)
        XCTAssertFalse(snap.ticketsOn)
        let data = try WatchCodec.encode(snap)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("Ticket p1"))
    }

    func testSnapshotDecodesWhenFieldsAreMissing() throws {
        let json = #"{"sentAt":"2026-10-07T06:00:00Z"}"#
        let snap = try WatchCodec.snapshot(from: Data(json.utf8))
        XCTAssertTrue(snap.trips.isEmpty)
        XCTAssertTrue(snap.tickets.isEmpty)
        XCTAssertTrue(snap.ticketsOn)
        XCTAssertEqual(snap.version, WatchSnapshot.currentVersion)
    }

    func testTicketsAreLimitedAndOrderedLikeTheListOnThePhone() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let n = now.timeIntervalSince1970
        var passes = [pass("later", valid: (n + 1000)...(n + 2000)),
                      pass("ends-late", valid: (n - 100)...(n + 9000)),
                      pass("ends-soon", valid: (n - 100)...(n + 500)),
                      pass("undated", valid: nil),
                      pass("old", valid: (n - 400_000)...(n - 300_000))]   // archived: gone for more than a day
        XCTAssertEqual(WatchTickets.shared(from: passes, at: now).map(\.id), ["ends-soon", "ends-late", "later", "undated"])
        passes = (0..<30).map { pass("p\($0)", valid: (n - 10)...(n + 100 + Double($0))) }
        XCTAssertEqual(WatchTickets.shared(from: passes, at: now).count, WatchTickets.limit)
    }

    func testTicketsOfATripComeFirst() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let n = now.timeIntervalSince1970
        let tickets = [pass("day", valid: (n - 10)...(n + 5000), category: .dayPass, created: 1),
                       pass("mine", valid: (n - 10)...(n + 5000), tripId: "t1", created: 2),
                       pass("other", valid: (n - 10)...(n + 5000), tripId: "t2", created: 3)]
            .map { WatchTicket(pass: $0.forWatch(), code: "\($0.id).png") }
        XCTAssertEqual(WatchTickets.forTrip("t1", in: tickets, at: now).map(\.id), ["mine", "day"])
        XCTAssertEqual(WatchTickets.forTrip(nil, in: tickets, at: now).map(\.id), ["day"])
        XCTAssertEqual(WatchTickets.validNow(tickets, at: now).count, 3)
    }

    func testTripSelectionKeepsTheStartedTripAndAtMostEight() throws {
        let base = try XCTUnwrap(plan("plan_muc").itineraries.first)
        func at(_ hours: Double) -> Itinerary {
            var it = base
            let shift = hours * 3600
            it.startTime = base.startTime.addingTimeInterval(shift)
            it.endTime = base.endTime.addingTimeInterval(shift)
            return it
        }
        let now = base.startTime
        var trips = (0..<12).map { trip("t\($0)", at(Double($0) * 5)) }
        trips.append(trip("old", at(-40)))         // over for more than six hours: not carried
        trips.append(trip("far", at(500)))         // far ahead and not started: only if it fits
        let chosen = WatchSnapshot.chooseTrips(trips, active: "far", now: now)
        XCTAssertEqual(chosen.count, WatchSnapshot.tripLimit)
        XCTAssertTrue(chosen.contains { $0.id == "far" }, "the started trip is always there")
        XCTAssertFalse(chosen.contains { $0.id == "old" })
        XCTAssertEqual(chosen.map(\.startTime), chosen.map(\.startTime).sorted())
        let snap = WatchSnapshot.make(now: now, trips: trips, activeTripId: "gone", places: [], passes: [], ticketsOn: true)
        XCTAssertNil(snap.activeTripId, "an unknown started trip is not announced")
    }

    func testCurrentTripFollowsTheLiveBarRule() throws {
        let it = try XCTUnwrap(plan("plan_muc").itineraries.first)
        let a = trip("a", it)
        var later = try XCTUnwrap(plan("plan_muc").itineraries.dropFirst().first)
        later.startTime = it.startTime.addingTimeInterval(2 * 3600)
        later.endTime = later.startTime.addingTimeInterval(1800)
        let b = trip("b", later)
        var snap = WatchSnapshot(sentAt: .now, trips: [b, a])
        XCTAssertNil(snap.current(now: it.startTime.addingTimeInterval(-3600)), "more than half an hour before")
        XCTAssertEqual(snap.current(now: it.startTime.addingTimeInterval(-25 * 60))?.id, "a")
        XCTAssertEqual(snap.current(now: it.endTime.addingTimeInterval(4 * 60))?.id, "a", "Arrived stays for five minutes")
        XCTAssertNil(snap.current(now: it.endTime.addingTimeInterval(6 * 60)))
        snap.activeTripId = "b"
        XCTAssertEqual(snap.current(now: it.startTime)?.id, "b", "a trip started by hand wins within three hours of its start")
        XCTAssertEqual(snap.upcoming(now: it.startTime).map(\.id), ["a", "b"])
        XCTAssertEqual(snap.past(now: it.endTime.addingTimeInterval(60)).map(\.id), ["a"])
        // Same trip of the planner: found again after a refresh changed the server ID.
        var refreshed = it
        refreshed.startTime = it.startTime.addingTimeInterval(60)
        XCTAssertEqual(snap.trip(for: refreshed)?.id, "a")
    }

    // MARK: Requests from the watch

    func testRequestsShowAtOnceOnTheWatch() throws {
        let it = try XCTUnwrap(plan("plan_muc").itineraries.first)
        let phone = WatchSnapshot(sentAt: Date(timeIntervalSince1970: 100), trips: [trip("a", it)])
        var state = WatchState(received: phone)
        let place = SavedPlace(id: "p", name: "Cafe", subtitle: nil, lat: 48.1, lon: 11.5, stopId: nil)
        var newTrip = trip("n", try XCTUnwrap(plan("plan").itineraries.first))
        newTrip.followLive = nil
        state.add(.saveTrip(newTrip))
        state.add(.startTrip("n"))
        state.add(.savePlace(place))
        state.add(.removeTrip("a"))
        let s = state.snapshot
        XCTAssertEqual(s.trips.map(\.id), ["n"])
        XCTAssertEqual(s.activeTripId, "n")
        XCTAssertEqual(s.places, [place])
        // The same route twice stays one trip.
        state.add(.saveTrip(trip("n2", newTrip.itinerary)))
        XCTAssertEqual(state.snapshot.trips.count, 1)
        state.add(.stopTrip("n"))
        XCTAssertNil(state.snapshot.activeTripId)
        state.add(.removePlace("p"))
        XCTAssertTrue(state.snapshot.places.isEmpty)
        XCTAssertEqual(state.received.trips.map(\.id), ["a"], "what the iPhone sent is not touched")
    }

    func testConfirmedRequestsLeaveTheListAndOldSnapshotsAreIgnored() throws {
        let it = try XCTUnwrap(plan("plan_muc").itineraries.first)
        var state = WatchState(received: WatchSnapshot(sentAt: Date(timeIntervalSince1970: 100)))
        let save = WatchIntent.saveTrip(trip("a", it))
        let other = WatchIntent.startTrip("a")
        state.add(save)
        state.add(other)
        let newer = WatchSnapshot(sentAt: Date(timeIntervalSince1970: 200), trips: [trip("a", it)], acks: [save.id])
        XCTAssertTrue(state.receive(newer))
        XCTAssertEqual(state.pending.map(\.id), [other.id])
        XCTAssertFalse(state.receive(WatchSnapshot(sentAt: Date(timeIntervalSince1970: 150))), "an older transfer arrived late")
        XCTAssertEqual(state.received.sentAt, Date(timeIntervalSince1970: 200))
        XCTAssertFalse(state.isEmpty)
        XCTAssertTrue(WatchState().isEmpty)
    }

    func testRequestsNobodyConfirmsAreDroppedAfterTwoWeeksAndLimited() {
        var state = WatchState()
        let old = WatchIntent.stopTrip("x", now: Date(timeIntervalSince1970: 0))
        state.add(old, now: Date(timeIntervalSince1970: 0))
        state.add(.stopTrip("y", now: Date(timeIntervalSince1970: 15 * 24 * 3600)), now: Date(timeIntervalSince1970: 15 * 24 * 3600))
        XCTAssertEqual(state.pending.count, 1)
        for i in 0..<80 { state.add(.removePlace("p\(i)", now: Date(timeIntervalSince1970: 15 * 24 * 3600)), now: Date(timeIntervalSince1970: 15 * 24 * 3600)) }
        XCTAssertEqual(state.pending.count, WatchState.pendingLimit)
        XCTAssertEqual(state.pending.last?.placeId, "p79")
    }

    func testTimesTheWatchRefreshedSurviveAnOlderSnapshotButNotANewerOne() throws {
        let it = try XCTUnwrap(plan("plan_muc").itineraries.first)
        var delayed = it
        delayed.endTime = it.endTime.addingTimeInterval(600)
        let t0 = Date(timeIntervalSince1970: 1_000)
        var state = WatchState(received: WatchSnapshot(sentAt: t0, trips: [trip("a", it, saved: t0)]))
        state.update(tripId: "a", itinerary: delayed, at: t0.addingTimeInterval(300))
        XCTAssertEqual(state.snapshot.trips.first?.endTime, delayed.endTime)
        // The iPhone's snapshot is older than the watch's refresh: the watch keeps its times.
        XCTAssertTrue(state.receive(WatchSnapshot(sentAt: t0.addingTimeInterval(100), trips: [trip("a", it, saved: t0)])))
        XCTAssertEqual(state.snapshot.trips.first?.endTime, delayed.endTime)
        // The iPhone refreshed later: its times win.
        var fresh = trip("a", it, saved: t0)
        fresh.refreshedAt = t0.addingTimeInterval(900)
        XCTAssertTrue(state.receive(WatchSnapshot(sentAt: t0.addingTimeInterval(1000), trips: [fresh])))
        XCTAssertEqual(state.snapshot.trips.first?.endTime, it.endTime)
    }

    func testRefreshOfATripSavedOnTheWatchUpdatesTheRequest() throws {
        let it = try XCTUnwrap(plan("plan_muc").itineraries.first)
        var delayed = it
        delayed.endTime = it.endTime.addingTimeInterval(120)
        var state = WatchState()
        state.add(.saveTrip(trip("w", it)))
        state.update(tripId: "w", itinerary: delayed, at: .now)
        XCTAssertEqual(state.pending.first?.trip?.itinerary.endTime, delayed.endTime)
        XCTAssertEqual(state.snapshot.trips.first?.endTime, delayed.endTime)
    }

    func testStateSurvivesTheFile() throws {
        let it = try XCTUnwrap(plan("plan_muc").itineraries.first)
        var state = WatchState(received: WatchSnapshot(sentAt: Date(timeIntervalSince1970: 500), trips: [trip("a", it)]))
        state.add(.resend(screen: 396))
        state.add(.saveTrip(trip("b", try XCTUnwrap(plan("plan").itineraries.first))))
        let back = try WatchCodec.state(from: WatchCodec.encode(state))
        XCTAssertEqual(back.received.trips.map(\.id), ["a"])
        XCTAssertEqual(back.pending.map(\.kind), [.resend, .saveTrip])
        XCTAssertEqual(back.pending.first?.screen, 396)
        let intent = try WatchCodec.intent(from: WatchCodec.encode(WatchIntent.removePlace("z")))
        XCTAssertEqual(intent.placeId, "z")
    }

    // MARK: Screens of a trip

    func testATripHasAnOverviewAndOnePagePerLegWorthIt() throws {
        let all = try XCTUnwrap(plan("plan_walk_steps").itineraries.first)
        XCTAssertEqual(WatchTripPages.pages(for: all), [.overview, .leg(0), .leg(1), .leg(2), .leg(3), .leg(4)])
        // The first walk of the other trip is one minute and 0 m: it stays in the overview.
        let short = try XCTUnwrap(plan("plan_direct_modes").itineraries.first)
        XCTAssertEqual(WatchTripPages.pages(for: short), [.overview, .leg(1), .leg(2)])
        XCTAssertEqual(WatchTripPages.leg(.leg(1), in: short)?.lineName, short.legs[1].lineName)
        XCTAssertNil(WatchTripPages.leg(.overview, in: short))
        XCTAssertNil(WatchTripPages.leg(.leg(9), in: short))
        XCTAssertEqual(Set(WatchTripPages.pages(for: all).map(\.id)).count, 6)
    }

    func testTheOpenPageFollowsTheJourney() throws {
        let it = try XCTUnwrap(plan("plan_walk_steps").itineraries.first)
        XCTAssertEqual(WatchTripPages.current(in: it, now: it.startTime.addingTimeInterval(-60)), .overview)
        XCTAssertEqual(WatchTripPages.current(in: it, now: it.legs[0].startTime.addingTimeInterval(30)), .leg(0))
        XCTAssertEqual(WatchTripPages.current(in: it, now: it.legs[1].startTime.addingTimeInterval(30)), .leg(1))
        XCTAssertEqual(WatchTripPages.current(in: it, now: it.legs[3].startTime.addingTimeInterval(1)), .leg(3))
        XCTAssertEqual(WatchTripPages.current(in: it, now: it.endTime.addingTimeInterval(1)), .overview)
    }

    func testMapBoxShowsTheLegAndNeverLessThanFourHundredMeters() throws {
        let it = try XCTUnwrap(plan("plan_walk_steps").itineraries.first)
        let leg = it.legs[1]
        let points = WatchMapFit.points(of: leg)
        XCTAssertGreaterThan(points.count, 1)
        let box = try XCTUnwrap(WatchMapFit.box(points))
        let lats = points.map(\.lat), lons = points.map(\.lon)
        XCTAssertTrue((lats.min()!)...(lats.max()!) ~= box.center.lat)
        XCTAssertTrue((lons.min()!)...(lons.max()!) ~= box.center.lon)
        XCTAssertGreaterThanOrEqual(box.latitudeDelta * WatchMapFit.metersPerDegree, 399)
        // Every point lies inside the box.
        for p in points {
            XCTAssertLessThanOrEqual(abs(p.lat - box.center.lat), box.latitudeDelta / 2 + 1e-9)
            XCTAssertLessThanOrEqual(abs(p.lon - box.center.lon), box.longitudeDelta / 2 + 1e-9)
        }
        // One point: the minimum box, centred on it.
        let one = try XCTUnwrap(WatchMapFit.box([LatLon(lat: 48.0, lon: 11.0)]))
        XCTAssertEqual(one.center, LatLon(lat: 48.0, lon: 11.0))
        XCTAssertEqual(one.latitudeDelta * WatchMapFit.metersPerDegree, 400, accuracy: 1)
        XCTAssertNil(WatchMapFit.box([]))
        XCTAssertNil(WatchMapFit.box([LatLon(lat: .nan, lon: 1)]))
        // A long leg is as wide as high in meters.
        let long = try XCTUnwrap(WatchMapFit.box([LatLon(lat: 48.0, lon: 11.0), LatLon(lat: 48.5, lon: 11.2)]))
        let h = long.latitudeDelta * WatchMapFit.metersPerDegree
        let w = long.longitudeDelta * WatchMapFit.metersPerDegree * cos(long.center.lat * .pi / 180)
        XCTAssertEqual(h, w, accuracy: 1)
        XCTAssertFalse(WatchMapFit.points(of: it).isEmpty)
    }

    // MARK: Routes, policy, files

    func testWatchRoutesAgreeWithThePlannerOnWalking() throws {
        let res = try plan("plan_direct_modes")
        XCTAssertEqual(WatchRoutes.merge(transit: res.itineraries, direct: res.direct).map(\.id),
                       PlanModel.merge(transit: res.itineraries, direct: res.direct).map(\.id))
        XCTAssertEqual(WatchRoutes.merge(transit: [], direct: res.direct).map(\.id),
                       PlanModel.merge(transit: [], direct: res.direct).map(\.id))
        XCTAssertEqual(WatchRoutes.list(transit: res.itineraries, direct: res.direct, limit: 1).count, 1)
        let long = try plan("plan_long_walk")
        XCTAssertEqual(WatchRoutes.merge(transit: long.itineraries, direct: long.direct).map(\.id),
                       PlanModel.merge(transit: long.itineraries, direct: long.direct).map(\.id))
    }

    func testSyncPolicySendsChangesAtOnceAndTimesRarely() throws {
        let it = try XCTUnwrap(plan("plan_muc").itineraries.first)
        let t0 = Date(timeIntervalSince1970: 10_000)
        var snap = WatchSnapshot(sentAt: t0, trips: [trip("a", it, saved: t0)])
        XCTAssertEqual(WatchSyncPolicy.decide(last: nil, new: snap, now: t0), .send)
        let last = (structure: WatchSyncPolicy.structure(snap), content: WatchSyncPolicy.content(snap), sentAt: t0)
        XCTAssertEqual(WatchSyncPolicy.decide(last: last, new: snap, now: t0.addingTimeInterval(5)), .skip)
        // Only a refreshed time: not more often than every 90 seconds.
        snap.trips[0].refreshedAt = t0.addingTimeInterval(20)
        XCTAssertEqual(WatchSyncPolicy.decide(last: last, new: snap, now: t0.addingTimeInterval(30)), .wait(60))
        XCTAssertEqual(WatchSyncPolicy.decide(last: last, new: snap, now: t0.addingTimeInterval(95)), .send)
        // A trip added, a ticket changed or the setting switched: at once.
        var added = snap
        added.trips.append(trip("b", it))
        XCTAssertEqual(WatchSyncPolicy.decide(last: last, new: added, now: t0.addingTimeInterval(1)), .send)
        var off = snap
        off.ticketsOn = false
        XCTAssertEqual(WatchSyncPolicy.decide(last: last, new: off, now: t0.addingTimeInterval(1)), .send)
        var ticket = snap
        ticket.tickets = [WatchTicket(pass: pass("p"), code: "p.png")]
        XCTAssertEqual(WatchSyncPolicy.decide(last: last, new: ticket, now: t0.addingTimeInterval(1)), .send)
        var started = snap
        started.activeTripId = "a"
        XCTAssertEqual(WatchSyncPolicy.decide(last: last, new: started, now: t0.addingTimeInterval(1)), .send)
    }

    func testCodeFileNamesAreSafeAndChangeWithTheTicketAndTheScreen() {
        let d = Date(timeIntervalSince1970: 1_700_000_123)
        XCTAssertEqual(WatchCodeFile.name(passId: "AB-12", updatedAt: d, pixels: 396), "AB-12-1700000123-396.png")
        XCTAssertEqual(WatchCodeFile.name(passId: "../etc/x y", updatedAt: d, pixels: 396), "___etc_x_y-1700000123-396.png")
        XCTAssertNotEqual(WatchCodeFile.name(passId: "a", updatedAt: d, pixels: 396),
                          WatchCodeFile.name(passId: "a", updatedAt: d.addingTimeInterval(1), pixels: 396))
        XCTAssertEqual(WatchCodeFile.clamped(nil), WatchCodeFile.defaultPixels)
        XCTAssertEqual(WatchCodeFile.clamped(50), 200)
        XCTAssertEqual(WatchCodeFile.clamped(5000), 560)
    }

    func testOfferedTicketsAreOneRuleForPhoneAndWatch() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let n = now.timeIntervalSince1970
        let list = [pass("a", valid: (n - 10)...(n + 100), tripId: "t"), pass("b", valid: (n - 10)...(n + 100)),
                    pass("c", valid: nil), pass("d", valid: (n + 500)...(n + 900))]
        XCTAssertEqual(TicketPass.offered(list, forTrip: "t", at: now).map(\.id), ["a", "b", "c"])
        XCTAssertEqual(TicketPass.offered(list, forTrip: nil, at: now).map(\.id), ["b", "c"])
    }
}

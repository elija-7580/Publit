// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich
import XCTest
@testable import Publit

/// Calendar events as destinations: which events are offered, and when to leave for them.
final class CalendarTripsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_795_449_600)   // 2026-11-23 14:00 UTC

    private func event(_ id: String, inMinutes m: Double, location: String = "Herrengasse 14, Wien",
                       allDay: Bool = false, lat: Double? = nil, lon: Double? = nil) -> CalendarAppointment {
        CalendarAppointment(id: id, title: "Meeting \(id)", start: now.addingTimeInterval(m * 60),
                            end: now.addingTimeInterval((m + 60) * 60), location: location,
                            lat: lat, lon: lon, isAllDay: allDay)
    }

    func testOffersUpcomingEventsWithAPlaceSoonestFirst() {
        let list = CalendarTrips.suggestions([event("b", inMinutes: 300), event("a", inMinutes: 60), event("c", inMinutes: 600)], now: now)
        XCTAssertEqual(list.map(\.id), ["a", "b", "c"])
        XCTAssertEqual(CalendarTrips.suggestions((0..<6).map { event("\($0)", inMinutes: Double(60 + $0)) }, now: now).count, 3)
    }

    func testLeavesOutWhatNobodyTravelsTo() {
        let list = CalendarTrips.suggestions([
            event("allday", inMinutes: 60, allDay: true),
            event("empty", inMinutes: 60, location: "  "),
            event("zoom", inMinutes: 60, location: "https://zoom.us/j/123456"),
            event("teams", inMinutes: 60, location: "Microsoft Teams Meeting"),
            event("started", inMinutes: -10),
            event("tooSoon", inMinutes: 3),
            event("nextWeek", inMinutes: 7 * 24 * 60),
            event("ok", inMinutes: 90),
        ], now: now)
        XCTAssertEqual(list.map(\.id), ["ok"])
    }

    func testAnEventWhereYouAreIsNotOffered() {
        let here = LatLon(lat: 48.2090, lon: 16.3660)
        let there = event("here", inMinutes: 60, lat: 48.2091, lon: 16.3661)
        let away = event("away", inMinutes: 90, lat: 48.1850, lon: 16.3780)
        XCTAssertEqual(CalendarTrips.suggestions([there, away], now: now, here: here).map(\.id), ["away"])
    }

    func testNearbyShowsOnlyTheNextEventWithinAFewHours() {
        let later = event("later", inMinutes: 6 * 60)
        XCTAssertNil(CalendarTrips.next([later], now: now))
        let soon = event("soon", inMinutes: 45)
        XCTAssertEqual(CalendarTrips.next([soon, later], now: now)?.id, "soon")
    }

    func testPlaceNameAndLookupText() {
        let a = event("x", inMinutes: 60, location: "Café Central\nHerrengasse 14\n1010 Wien")
        XCTAssertEqual(a.placeName, "Café Central")
        XCTAssertEqual(a.searchText, "Café Central, Herrengasse 14, 1010 Wien")
        XCTAssertNil(a.coordinate)
        let pinned = event("y", inMinutes: 60, lat: 48.21, lon: 16.37)
        let place = pinned.place(at: pinned.coordinate!)
        XCTAssertEqual(place.id, "calendar|y")
        XCTAssertEqual(place.subtitle, "Meeting y")
        XCTAssertNil(place.stopId)
    }

    func testArriveAFewMinutesEarly() {
        let a = event("x", inMinutes: 120)
        XCTAssertEqual(a.arriveBy, a.start.addingTimeInterval(-5 * 60))
    }

    /// "Leave by": the route that leaves last and still arrives on time.
    func testLatestRouteThatStillArrivesOnTime() {
        func it(_ id: String, start: Double, end: Double) -> Itinerary {
            Itinerary(id: id, duration: Int((end - start) * 60), startTime: now.addingTimeInterval(start * 60),
                      endTime: now.addingTimeInterval(end * 60), transfers: 0, legs: [])
        }
        let target = now.addingTimeInterval(115 * 60)
        let routes = [it("early", start: 40, end: 80), it("best", start: 70, end: 112), it("late", start: 90, end: 125)]
        XCTAssertEqual(CalendarTrips.latestOnTime(routes, arriveBy: target)?.id, "best")
        XCTAssertNil(CalendarTrips.latestOnTime([it("late", start: 90, end: 125)], arriveBy: target))
    }

    @MainActor
    func testAnotherDestinationDropsTheEvent() async {
        let plan = PlanModel()
        let a = event("x", inMinutes: 60, lat: 48.21, lon: 16.37)
        let place = a.place(at: a.coordinate!)
        plan.to = .place(place)
        plan.appointment = a
        plan.to = .place(place)
        XCTAssertEqual(plan.appointment, a)
        plan.to = .place(SavedPlace(id: "other", name: "Other", subtitle: nil, lat: 48.2, lon: 16.3, stopId: nil))
        XCTAssertNil(plan.appointment)
    }
}

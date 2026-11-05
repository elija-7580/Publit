import XCTest
@testable import Publit

/// Route list order and the day marker (feedback 2026-11-03: later trips further down, next day marked).
final class TripOrderTests: XCTestCase {
    private let t0 = 1_793_739_600.0   // 2026-11-03 21:00 UTC (22:00 in Vienna)

    private func date(_ m: Double) -> Date { Date(timeIntervalSince1970: t0 + m * 60) }

    private func itinerary(_ id: String, start: Double, end: Double) -> Itinerary {
        Itinerary(id: id, duration: Int((end - start) * 60), startTime: date(start), endTime: date(end),
                  transfers: 0, legs: [])
    }

    func testDepartureSearchListsByDepartureThenArrival() {
        let a = itinerary("a", start: 30, end: 90)
        let b = itinerary("b", start: 10, end: 100)
        let c = itinerary("c", start: 10, end: 60)
        XCTAssertEqual(PlanModel.timetableOrder([a, b, c], arriveBy: false).map(\.id), ["c", "b", "a"])
    }

    func testArriveBySearchListsByArrival() {
        // Leaves earlier but arrives later: in an "Arrive by" search it belongs further down.
        let slow = itinerary("slow", start: 0, end: 120)
        let fast = itinerary("fast", start: 40, end: 100)
        let late = itinerary("late", start: 60, end: 130)
        XCTAssertEqual(PlanModel.timetableOrder([late, slow, fast], arriveBy: true).map(\.id), ["fast", "slow", "late"])
        XCTAssertEqual(PlanModel.timetableOrder([late, slow, fast], arriveBy: false).map(\.id), ["slow", "fast", "late"])
    }

    func testTiesKeepServerOrder() {
        let x = itinerary("x", start: 10, end: 50)
        let y = itinerary("y", start: 10, end: 50)
        XCTAssertEqual(PlanModel.timetableOrder([y, x], arriveBy: false).map(\.id), ["y", "x"])
    }

    func testDayOffsetAndNoteAcrossMidnight() {
        let tz = "Europe/Vienna"
        // 22:00 → 23:50 same day; 22:00 → 00:10 next day.
        XCTAssertEqual(Fmt.dayOffset(from: date(0), to: date(110), tz: tz), 0)
        XCTAssertEqual(Fmt.dayOffset(from: date(0), to: date(130), tz: tz), 1)
        XCTAssertEqual(Fmt.dayOffset(from: date(0), to: date(60 * 50), tz: tz), 3)
        XCTAssertNil(Fmt.dayNote(date(110), reference: date(0), tz: tz))
        XCTAssertNotNil(Fmt.dayNote(date(130), reference: date(0), tz: tz))
        XCTAssertNotNil(Fmt.dayNote(date(60 * 50), reference: date(0), tz: tz))
        // The same instant is still "today" in UTC (23:10) but already tomorrow in Vienna (00:10).
        XCTAssertEqual(Fmt.dayOffset(from: date(0), to: date(130), tz: "UTC"), 0)
    }
}

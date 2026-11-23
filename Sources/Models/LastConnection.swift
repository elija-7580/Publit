// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich

import Foundation

/// "Last connection": the latest you can still leave and get there tonight.
///
/// Asked as "arrive by" the end of the service day (4 a.m. the next morning), so the routes found are
/// the last ones that still arrive in the night, night buses included. A route that only arrives the
/// next morning (sitting at a station overnight) is not a last connection and is not counted.
enum LastConnection {
    /// The service day ends at 4 a.m.: after midnight, "tonight" is still the day before.
    static let dayEndHour = 4

    /// Arrive-by time for the last connection of the service day `date` falls in.
    static func deadline(for date: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: date)
        let hour = calendar.component(.hour, from: date)
        let day = hour < dayEndHour ? start : calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return calendar.date(bySettingHour: dayEndHour, minute: 0, second: 0, of: day) ?? day
    }

    /// The service day as a key (searching again for another time on the same day changes nothing).
    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let d = deadline(for: date, calendar: calendar)
        let c = calendar.dateComponents([.year, .month, .day], from: d)
        return "last-\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    /// Routes that have not left yet (a minute's grace), in departure order.
    static func upcoming(_ list: [Itinerary], now: Date = .now) -> [Itinerary] {
        list.filter { $0.startTime >= now.addingTimeInterval(-60) }
            .sorted { $0.startTime == $1.startTime ? $0.endTime < $1.endTime : $0.startTime < $1.startTime }
    }

    /// The route that leaves last; a cancelled one or walking the whole way never counts.
    static func last(_ list: [Itinerary]) -> Itinerary? {
        list.filter { !$0.isCancelled && !$0.isDirect }
            .max { $0.startTime == $1.startTime ? $0.endTime > $1.endTime : $0.startTime < $1.startTime }
    }
}

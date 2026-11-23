// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich
import EventKit
import Foundation
import Observation

/// Upcoming calendar events with a place, read with EventKit on the iPhone.
/// Off until the person turns it on; calendar access is asked for only then. The events stay on the
/// device: a place is looked up (and so sent to a search) only when its route is opened.
@MainActor
@Observable
final class CalendarSuggestions {
    static let shared = CalendarSuggestions()

    private(set) var appointments: [CalendarAppointment] = []
    private(set) var status: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    private(set) var enabled = UserDefaults.standard.bool(forKey: CalendarTrips.enabledKey)
    /// A place of an event is being looked up (one at a time).
    private(set) var resolving: String?

    @ObservationIgnored private var store: EKEventStore?
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var lastHere: LatLon?
    @ObservationIgnored private var lastRead: Date?

    /// Allowed and on: events are read.
    var isActive: Bool { enabled && status == .fullAccess }
    /// Turned off in iOS Settings (or by a profile): only the Settings app can turn it on again.
    var isBlocked: Bool { status == .denied || status == .restricted }

    /// Turns the suggestions on and asks for calendar access once (iOS shows its own question).
    /// - Returns: whether events can be read now.
    @discardableResult
    func enable() async -> Bool {
        let store = eventStore()
        if status != .fullAccess {
            _ = try? await store.requestFullAccessToEvents()
            status = EKEventStore.authorizationStatus(for: .event)
            // A store made before the access was granted reads nothing until it is reset.
            if status == .fullAccess { store.reset() }
        }
        setEnabled(status == .fullAccess)
        refresh(here: lastHere, force: true)
        return enabled
    }

    func disable() {
        setEnabled(false)
        lastRead = nil
        appointments = []
    }

    private func setEnabled(_ on: Bool) {
        enabled = on
        UserDefaults.standard.set(on, forKey: CalendarTrips.enabledKey)
    }

    /// Reads the events of the next hours again (on appearing, after a calendar change).
    /// Screens call it on every appearance: within a minute the last reading is kept, unless `force`.
    func refresh(here: LatLon?, now: Date = .now, force: Bool = false) {
        lastHere = here ?? lastHere
        let current = EKEventStore.authorizationStatus(for: .event)
        if current != status { status = current }
        guard isActive else { if !appointments.isEmpty { appointments = [] }; return }
        if !force, let lastRead, now.timeIntervalSince(lastRead) < 60, now >= lastRead { return }
        lastRead = now
        let store = eventStore()
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-3600),
                                                 end: now.addingTimeInterval(CalendarTrips.lookahead), calendars: nil)
        let events = store.events(matching: predicate).compactMap { e -> CalendarAppointment? in
            guard e.status != .canceled else { return nil }
            // Declined invitations are not your appointments.
            if let me = e.attendees?.first(where: \.isCurrentUser), me.participantStatus == .declined { return nil }
            let geo = e.structuredLocation?.geoLocation?.coordinate
            let text = [e.structuredLocation?.title, e.location]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty } ?? ""
            // The full address from the event when the pin's title is only a name.
            let location = (e.location?.count ?? 0) > text.count ? (e.location ?? text) : text
            return CalendarAppointment(id: "\(e.calendarItemIdentifier)|\(Int(e.startDate.timeIntervalSince1970))",
                                       title: e.title ?? "", start: e.startDate, end: e.endDate,
                                       location: location, lat: geo?.latitude, lon: geo?.longitude,
                                       isAllDay: e.isAllDay)
        }
        let next = CalendarTrips.suggestions(events, now: now, here: lastHere)
        if next != appointments { appointments = next }
    }

    private func eventStore() -> EKEventStore {
        if let store { return store }
        let s = EKEventStore()
        store = s
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: s, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh(here: nil, force: true) }
        }
        return s
    }

    /// Coordinates for the event's place: the calendar's own pin, else an address lookup
    /// (Apple's place search first, then the open geocoder). Only called when its route is opened.
    func resolve(_ a: CalendarAppointment, near: LatLon?) async -> SavedPlace? {
        if let c = a.coordinate { return a.place(at: c) }
        guard resolving == nil else { return nil }
        resolving = a.id
        defer { resolving = nil }
        if let m = await AppleSearch.places(a.searchText, near: near).first {
            return a.place(at: LatLon(lat: m.lat, lon: m.lon))
        }
        if let m = try? await TransitousClient.shared.geocode(a.searchText, near: near).first {
            return a.place(at: LatLon(lat: m.lat, lon: m.lon))
        }
        return nil
    }
}

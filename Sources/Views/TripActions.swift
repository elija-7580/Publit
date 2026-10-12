import SwiftUI
import EventKit
import EventKitUI

/// Save, calendar, leave reminder and tickets for one route. Used in route details and saved trips.
struct TripActionsSection: View {
    let itinerary: Itinerary
    let fromName: String
    let toName: String

    @Environment(TripStore.self) private var trips
    @Environment(TicketStore.self) private var tickets
    @Environment(AppState.self) private var app
    @State private var calendarTrip: SavedTrip?
    @State private var reminderOn = false
    @State private var note: String?
    @State private var addingTicket = false
    @State private var showingTickets = false

    private var saved: SavedTrip? { trips.saved(itinerary) }

    var body: some View {
        Section {
            if let saved, trips.activeTripId == saved.id {
                Button { Task { await stopTrip(saved) } } label: {
                    Label("End trip", systemImage: "stop.circle")
                }
                .accessibilityIdentifier("endTrip")
            } else {
                Button { Task { await startTrip() } } label: {
                    Label("Start trip", systemImage: "location.north.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(itinerary.isCancelled || itinerary.endTime < .now)
                .accessibilityIdentifier("startTrip")
            }
            Button {
                if let saved { trips.remove(saved.id); LeaveReminder.cancel(saved.id); Task { await LiveTripActivity.end(saved.id) }; reminderOn = false }
                else { trips.save(itinerary, from: fromName, to: toName) }
            } label: {
                Label(saved == nil ? L10n.t("Save trip") : L10n.t("Saved"), systemImage: saved == nil ? "bookmark" : "bookmark.fill")
            }
            Button {
                calendarTrip = ensureSaved()
            } label: {
                Label("Add to Calendar", systemImage: "calendar.badge.plus")
            }
            if itinerary.startTime > .now {
                Button {
                    Task { await toggleReminder() }
                } label: {
                    Label(reminderOn ? L10n.t("Leave reminder on") : L10n.t("Remind me to leave in time"),
                          systemImage: reminderOn ? "bell.fill" : "bell")
                }
            }
            if let note {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("Trip")
        } footer: {
            Text("The calendar entry links back to this trip with its live status.")
        }
        .task(id: saved?.id) {
            if let id = saved?.id { reminderOn = await LeaveReminder.isScheduled(id) }
        }
        .sheet(item: $calendarTrip) { trip in
            CalendarEventSheet(trip: trip).ignoresSafeArea()
        }

        FareSection(itinerary: itinerary)
        TicketSection(itinerary: itinerary, tripId: saved?.id, onAddTicket: {
            _ = ensureSaved()
            addingTicket = true
        })
        .sheet(isPresented: $addingTicket) { AddTicketView(tripId: saved?.id) }
    }

    private func startTrip() async {
        let trip = ensureSaved()
        if let previous = trips.start(trip.id), previous != trip.id {
            LeaveReminder.cancel(previous)
            await LiveTripActivity.end(previous)
        }
        switch LiveTripActivity.start(trip, hasTicket: !tickets.tickets(forTrip: trip.id).isEmpty) {
        case .started: note = L10n.t("Follow it on the lock screen.")
        case .tooEarly: note = L10n.t("Live updates on the lock screen start 8 hours before.")
        case .unavailable, .failed: note = L10n.t("Live tracking is active in the app. Lock screen updates may be unavailable.")
        }
        app.open(trip.deepLink)
    }

    private func stopTrip(_ trip: SavedTrip) async {
        trips.stop(trip.id)
        LeaveReminder.cancel(trip.id)
        await LiveTripActivity.end(trip.id)
        reminderOn = false
        note = L10n.t("Trip ended")
    }

    private func ensureSaved() -> SavedTrip {
        saved ?? trips.save(itinerary, from: fromName, to: toName)
    }

    private func toggleReminder() async {
        let trip = ensureSaved()
        if reminderOn {
            LeaveReminder.cancel(trip.id)
            if trips.activeTripId != trip.id {
                trips.setFollowLive(trip.id, false)
                await LiveTripActivity.end(trip.id)
            }
            reminderOn = false
            note = nil
            return
        }
        switch await LeaveReminder.schedule(trip) {
        case .denied:
            note = L10n.t("Allow notifications for Publit in Settings.")
            return
        case .tooLate:
            note = L10n.t("This trip starts now.")
        case .scheduled(let date):
            note = L10n.f("We'll remind you at %@.", Fmt.time(date, tz: trip.itinerary.legs.first?.from.tz))
        }
        trips.setFollowLive(trip.id, true)
        reminderOn = true
        switch LiveTripActivity.start(trip, hasTicket: !tickets.tickets(forTrip: trip.id).isEmpty) {
        case .started: note = [note, L10n.t("Follow it on the lock screen.")].compactMap { $0 }.joined(separator: " ")
        case .tooEarly: note = [note, L10n.t("Live updates on the lock screen start 8 hours before.")].compactMap { $0 }.joined(separator: " ")
        case .unavailable: note = [note, L10n.t("Turn on Live Activities for Publit in Settings to follow it on the lock screen.")].compactMap { $0 }.joined(separator: " ")
        case .failed: break
        }
    }
}

/// "Buy ticket" per operator and the user's own tickets.
struct TicketSection: View {
    let itinerary: Itinerary
    let tripId: String?
    let onAddTicket: () -> Void

    @Environment(TicketStore.self) private var tickets

    var body: some View {
        let links = TicketLinks.links(for: itinerary, userLinked: tickets.linkedApps)
        let mine = tickets.tickets(forTrip: tripId)
        if !itinerary.isDirect {
            Section {
                ForEach(mine.prefix(2)) { ticket in
                    TicketCardButton(ticket: ticket)
                }
                ForEach(links) { l in
                    Link(destination: l.url) {
                        Label(l.title, systemImage: l.source == .userLinked ? "arrow.up.forward.app" : "cart")
                    }
                }
                Button(action: onAddTicket) {
                    Label("Add ticket for this trip", systemImage: "plus.rectangle.on.rectangle")
                }
            } header: {
                Text("Tickets")
            } footer: {
                if links.isEmpty {
                    Text("The operator publishes no ticket link. Link your ticket app in Settings → Ticket apps.")
                }
            }
        }
    }
}

/// One ticket row that owns its own full-screen presentation.
/// A presentation modifier on a `Group`/`Section` inside a `List` is copied onto every row,
/// so several covers competed for one binding and the ticket never opened reliably.
struct TicketCardButton: View {
    let ticket: Ticket
    @State private var showing = false
    /// fullScreenCover does not inherit the presenter's Dynamic Type; re-apply so UI samples (and a11y sizes) reach the ticket.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button { showing = true } label: { TicketSummaryCard(ticket: ticket) }
            .buttonStyle(.plain)
            .fullScreenCover(isPresented: $showing) {
                TicketDisplayView(tickets: [ticket])
                    .dynamicTypeSize(dynamicTypeSize)
            }
    }
}

/// System "New Event" sheet, prefilled. Needs no calendar permission (iOS 17 write-only via EventKitUI).
struct CalendarEventSheet: UIViewControllerRepresentable {
    let trip: SavedTrip
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(dismiss: { dismiss() }) }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.title = CalendarText.title(trip)
        event.startDate = trip.startTime
        event.endDate = trip.endTime
        event.location = CalendarText.location(trip)
        event.notes = CalendarText.notes(trip)
        event.url = trip.deepLink
        event.addAlarm(EKAlarm(absoluteDate: TripStatus.reminderTime(trip.itinerary)))
        let vc = EKEventEditViewController()
        vc.eventStore = store
        vc.event = event
        vc.editViewDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: EKEventEditViewController, context: Context) {}

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let dismiss: () -> Void
        init(dismiss: @escaping () -> Void) { self.dismiss = dismiss }
        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            dismiss()
        }
    }
}

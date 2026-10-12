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
    @State private var calendarTrip: SavedTrip?
    @State private var reminderOn = false
    @State private var note: String?
    @State private var addingTicket = false
    @State private var showingTickets = false

    private var saved: SavedTrip? { trips.saved(itinerary) }

    var body: some View {
        Section {
            Button {
                if let saved { trips.remove(saved.id); LeaveReminder.cancel(saved.id); reminderOn = false }
                else { trips.save(itinerary, from: fromName, to: toName) }
            } label: {
                Label(saved == nil ? "Save trip" : "Saved", systemImage: saved == nil ? "bookmark" : "bookmark.fill")
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
                    Label(reminderOn ? "Leave reminder on" : "Remind me to leave in time",
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
            if let id = saved?.id { reminderOn = await LeaveReminder.isScheduled(id) || LiveTripActivity.isRunning(id) }
        }
        .sheet(item: $calendarTrip) { trip in
            CalendarEventSheet(trip: trip).ignoresSafeArea()
        }

        TicketSection(itinerary: itinerary, tripId: saved?.id, onAddTicket: {
            _ = ensureSaved()
            addingTicket = true
        })
        .sheet(isPresented: $addingTicket) { AddTicketView(tripId: saved?.id) }
    }

    private func ensureSaved() -> SavedTrip {
        saved ?? trips.save(itinerary, from: fromName, to: toName)
    }

    private func toggleReminder() async {
        let trip = ensureSaved()
        if reminderOn {
            LeaveReminder.cancel(trip.id)
            trips.setFollowLive(trip.id, false)
            await LiveTripActivity.end(trip.id)
            reminderOn = false
            note = nil
            return
        }
        switch await LeaveReminder.schedule(trip) {
        case .denied:
            note = "Allow notifications for Publit in Settings."
            return
        case .tooLate:
            note = "This trip starts now."
        case .scheduled(let date):
            note = "We'll remind you at \(Fmt.time(date, tz: trip.itinerary.legs.first?.from.tz))."
        }
        trips.setFollowLive(trip.id, true)
        reminderOn = true
        switch LiveTripActivity.start(trip, hasTicket: !tickets.tickets(forTrip: trip.id).isEmpty) {
        case .started: note = (note ?? "") + " Follow it on the lock screen."
        case .tooEarly: note = (note ?? "") + " Live updates on the lock screen start 8 hours before."
        case .unavailable: note = (note ?? "") + " Turn on Live Activities for Publit in Settings to follow it on the lock screen."
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
    @State private var showing = false

    var body: some View {
        let links = TicketLinks.links(for: itinerary, userLinked: tickets.linkedApps)
        let mine = tickets.tickets(forTrip: tripId)
        if !itinerary.isDirect {
            Section {
                if !mine.isEmpty {
                    Button { showing = true } label: {
                        Label(mine.count == 1 ? "Show ticket: \(mine[0].name)" : "Show my tickets (\(mine.count))",
                              systemImage: "ticket.fill")
                    }
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
            .fullScreenCover(isPresented: $showing) { TicketDisplayView(tickets: mine) }
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

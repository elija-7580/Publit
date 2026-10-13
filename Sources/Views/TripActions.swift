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
    @Environment(PassStore.self) private var passes
    @Environment(AppState.self) private var app
    @State private var calendarTrip: SavedTrip?
    @State private var reminderOn = false
    @State private var note: String?
    @State private var addingTicket = false
    @State private var showingTickets = false

    private var saved: SavedTrip? { trips.saved(itinerary) }

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Section {
            VStack(spacing: 16) {
            if let saved, trips.activeTripId == saved.id {
                Button { Task { await stopTrip(saved) } } label: {
                    Label("End trip", systemImage: "stop.circle")
                }
                .accessibilityIdentifier("endTrip")
            } else {
                Button { Task { await startTrip() } } label: {
                    Text("Start trip")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(itinerary.isCancelled || itinerary.endTime < .now)
                .accessibilityIdentifier("startTrip")
            }
            Divider().frame(maxWidth: .infinity)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
                secondaryButtons
            }
            .labelStyle(ActionLabelStyle())
            .buttonStyle(ActionButtonStyle())
            if let note {
                Text(note).font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
            }
            .padding(.vertical, 4)
            .listRowSeparator(.hidden)
            .sheet(item: $calendarTrip) { trip in CalendarEventSheet(trip: trip).ignoresSafeArea() }
        } footer: {
            Text("The calendar entry links back to this trip with its live status.")
        }
        .task(id: saved?.id) {
            if let id = saved?.id { reminderOn = await LeaveReminder.isScheduled(id) }
        }

        if Features.tickets {
            TicketSection(itinerary: itinerary, tripId: saved?.id, onAddTicket: {
                _ = ensureSaved()
                addingTicket = true
            })
            .sheet(isPresented: $addingTicket) { AddTicketView(tripId: saved?.id) }
        }
        if Features.passes, !itinerary.isDirect {
            TripPassSection(tripId: saved?.id, at: itinerary.startTime, ensureTrip: { ensureSaved().id })
        }
    }

    @ViewBuilder
    private var secondaryButtons: some View {
        Button {
            if saved == nil { trips.save(itinerary, from: fromName, to: toName) }
        } label: {
            Label(saved == nil ? L10n.t("Save trip") : L10n.t("Saved"), systemImage: saved == nil ? "bookmark" : "bookmark.fill")
        }
        .buttonStyle(ActionButtonStyle())
        .disabled(saved != nil)
        Button {
            calendarTrip = ensureSaved()
        } label: {
            Label("Add to Calendar", systemImage: "calendar.badge.plus")
        }
        .buttonStyle(ActionButtonStyle())
        if itinerary.endTime > .now {
            // "I'm arriving at … at 18:42": live time; a notification follows if it moves later.
            ShareLink(item: ArrivalShare.message(for: itinerary, to: toName)) {
                Label("Share arrival", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(ActionButtonStyle())
            .simultaneousGesture(TapGesture().onEnded {
                let trip = ensureSaved()
                ArrivalUpdates.recordShare(tripKey: trip.id, arrival: itinerary.endTime)
            })
            .accessibilityIdentifier("shareArrival")
        }
        if itinerary.startTime > .now {
            Button {
                Task { await toggleReminder() }
            } label: {
                Label(reminderOn ? L10n.t("Reminder on") : L10n.t("Leave reminder"),
                      systemImage: reminderOn ? "bell.fill" : "bell")
            }
            .buttonStyle(ActionButtonStyle())
        }
    }

    private func startTrip() async {
        let trip = ensureSaved()
        let previous = trips.start(trip.id)
        app.open(trip.deepLink)
        if let previous, previous != trip.id {
            LeaveReminder.cancel(previous)
            await LiveTripActivity.end(previous)
        }
        switch LiveTripActivity.start(trip, hasTicket: !passes.passes(forTrip: trip.id, at: trip.startTime).isEmpty) {
        case .started: note = L10n.t("Follow it on the lock screen.")
        case .tooEarly: note = L10n.t("Live updates on the lock screen start 8 hours before.")
        case .unavailable, .failed: note = L10n.t("Live tracking is active in the app. Lock screen updates may be unavailable.")
        }
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
        switch LiveTripActivity.start(trip, hasTicket: !passes.passes(forTrip: trip.id, at: trip.startTime).isEmpty) {
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

/// Icon above a short title, filling an equal share of the row.
struct TileLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 6) {
            configuration.icon.font(.title3)
            configuration.title.font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2).minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 58)
    }
}

/// Fixed padding and unlimited wrapping, independent of iOS's automatic capsule button shapes.
struct ActionLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 8) {
            configuration.icon.font(.title3.weight(.semibold))
            configuration.title.font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .center)
    }
}

struct ActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(12).frame(maxWidth: .infinity)
            .foregroundStyle(Color.appAccent)
            .background(Color.appAccent.opacity(configuration.isPressed ? 0.2 : 0.1), in: RoundedRectangle(cornerRadius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14))
    }
}

import SwiftUI
import EventKit
import EventKitUI

/// Start, save, calendar, share and leave reminder for one route, as a list section (samples and other
/// screens). The route screen shows the same `TripActionBar` pinned to the bottom instead, and the tickets
/// at the end (`TripTicketSections`).
struct TripActionsSection: View {
    let itinerary: Itinerary
    let fromName: String
    let toName: String

    @Environment(TripStore.self) private var trips
    @State private var addingTicket = false

    var body: some View {
        Section {
            TripActionBar(itinerary: itinerary, fromName: fromName, toName: toName, pinned: false)
                .listRowSeparator(.hidden)
                // On the one row, not on a Section: there it is copied onto every row.
                .sheet(isPresented: $addingTicket) { AddTicketView(tripId: trips.saved(itinerary)?.id) }
        }
        TripTicketSections(itinerary: itinerary, fromName: fromName, toName: toName) { addingTicket = true }
    }
}

/// The route's actions in one row: save, calendar, share, leave reminder as small square buttons and
/// "Start trip" as the wide ink button; while the trip runs, "End trip". On the route screen it stays
/// pinned to the bottom, so starting is always one tap away while scrolling through the steps.
struct TripActionBar: View {
    let itinerary: Itinerary
    let fromName: String
    let toName: String
    /// Pinned under the list (own background and edge); false inside a list row.
    var pinned = true

    @Environment(TripStore.self) private var trips
    @Environment(PassStore.self) private var passes
    @Environment(AppState.self) private var app
    @State private var calendarTrip: SavedTrip?
    @State private var reminderOn = false
    @State private var note: String?

    private var saved: SavedTrip? { trips.saved(itinerary) }
    /// Unsaved here, but kept until this screen closes.
    private var pending: Bool { saved.map { trips.isPendingRemoval($0.id) } ?? false }

    var body: some View {
        let running = saved.map { trips.activeTripId == $0.id } ?? false
        let blocked = running ? nil : TripStatus.startBlocked(itinerary, now: .now)
        VStack(spacing: 8) {
            // A grey button with no reason looked broken.
            if let line = blocked ?? note {
                Text(line).font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: pinned ? .center : .leading)
                    .multilineTextAlignment(pinned ? .center : .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(blocked != nil ? "startTripReason" : "tripActionNote")
            }
            HStack(spacing: 8) {
                if let saved, running {
                    shareButton
                    Button { Task { await stopTrip(saved) } } label: {
                        Label("End trip", systemImage: "stop.circle.fill")
                            .labelStyle(.titleAndIcon)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(EndTripButtonStyle())
                    .accessibilityIdentifier("endTrip")
                } else {
                    saveButton
                    calendarButton
                    shareButton
                    if itinerary.startTime > .now { reminderButton }
                    startButton(disabled: blocked != nil)
                }
            }
            .labelStyle(.iconOnly)
        }
        .padding(.horizontal, pinned ? 16 : 0)
        .padding(.top, pinned ? 10 : 4)
        .padding(.bottom, pinned ? 8 : 4)
        .background {
            if pinned {
                Color.surface.ignoresSafeArea(edges: .bottom)
                    .overlay(alignment: .top) { Divider() }
            }
        }
        .sheet(item: $calendarTrip) { trip in CalendarEventSheet(trip: trip).ignoresSafeArea() }
        .task(id: saved?.id) {
            if let id = saved?.id { reminderOn = await LeaveReminder.isScheduled(id) }
        }
    }

    private func startButton(disabled: Bool) -> some View {
        Button { Task { await startTrip() } } label: {
            // The longest label that fits next to the small buttons; the icon alone at the largest text sizes.
            ViewThatFits(in: .horizontal) {
                startLabel(short: false).labelStyle(.titleOnly)
                startLabel(short: true).labelStyle(.titleAndIcon)
                startLabel(short: true).labelStyle(.iconOnly)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.ink)
        .disabled(disabled)
        .accessibilityLabel(Text(L10n.t(TripStatus.startsOnFoot(itinerary, now: .now) ? "Start walking navigation" : "Start trip")))
        .accessibilityIdentifier("startTrip")
    }

    /// Starting on foot: the button says so and opens the walk turn by turn.
    private func startLabel(short: Bool) -> some View {
        let walking = TripStatus.startsOnFoot(itinerary, now: .now)
        let title: LocalizedStringKey = walking ? (short ? "Walk" : "Start walking navigation") : (short ? "Start" : "Start trip")
        return Label(title, systemImage: walking ? "figure.walk" : "play.fill")
    }

    private var saveButton: some View {
        let isSaved = saved != nil && !pending
        return Button {
            if let saved {
                if pending { trips.keep(saved.id) } else { trips.markForRemoval(saved.id) }
            } else {
                trips.save(itinerary, from: fromName, to: toName)
                SmartRouting.learn(chosen: itinerary)
            }
        } label: {
            Label(isSaved ? L10n.t("Saved") : L10n.t("Save trip"), systemImage: isSaved ? "bookmark.fill" : "bookmark")
        }
        .buttonStyle(BarIconButtonStyle())
        .accessibilityIdentifier("saveTrip")
    }

    private var calendarButton: some View {
        Button {
            calendarTrip = ensureSaved()
        } label: {
            Label("Add to Calendar", systemImage: "calendar.badge.plus")
        }
        .buttonStyle(BarIconButtonStyle())
        .accessibilityHint(Text("The calendar entry links back to this trip with its live status."))
        .accessibilityIdentifier("addToCalendar")
    }

    /// A link anyone can open (web page → Publit, or maps), with the route fetched live on their phone.
    /// Before arrival with "I'm arriving at … at 18:42"; a notification follows if that moves later.
    private var shareButton: some View {
        let upcoming = itinerary.endTime > .now
        return ShareLink(item: ShareLinks.web(.route(SharedRoute(itinerary, fromName: fromName, toName: toName))),
                         subject: Text(verbatim: "\(fromName) → \(toName)"),
                         message: Text(verbatim: upcoming ? ArrivalShare.message(for: itinerary, to: toName) : "\(fromName) → \(toName)")) {
            Label(upcoming ? L10n.t("Share arrival") : L10n.t("Share trip"), systemImage: "square.and.arrow.up")
        }
        .buttonStyle(BarIconButtonStyle())
        .simultaneousGesture(TapGesture().onEnded {
            guard upcoming else { return }
            let trip = ensureSaved()
            ArrivalUpdates.recordShare(tripKey: trip.id, arrival: itinerary.endTime)
        })
        .accessibilityIdentifier("shareArrival")
    }

    private var reminderButton: some View {
        Button {
            Task { await toggleReminder() }
        } label: {
            Label(reminderOn ? L10n.t("Reminder on") : L10n.t("Leave reminder"),
                  systemImage: reminderOn ? "bell.fill" : "bell")
        }
        .buttonStyle(BarIconButtonStyle())
        .accessibilityIdentifier("leaveReminder")
    }

    private func startTrip() async {
        let trip = ensureSaved()
        app.open(trip.deepLink)
        note = await TripSession.start(trip, in: trips,
                                       hasTicket: !passes.passes(forTrip: trip.id, at: trip.startTime).isEmpty)
    }

    private func stopTrip(_ trip: SavedTrip) async {
        await TripSession.stop(trip, in: trips)
        reminderOn = false
        note = L10n.t("Trip ended")
    }

    private func ensureSaved() -> SavedTrip {
        trips.ensureSaved(itinerary, from: fromName, to: toName)
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

/// Everything about tickets for a route in one place at the end of the route screen: how tickets work in
/// each network along the way, operator fares, the user's tickets and where to buy.
struct TripTicketSections: View {
    let itinerary: Itinerary
    let fromName: String
    let toName: String
    /// "Add ticket for this trip" (after saving it); the caller shows the sheet, on a single row or the list,
    /// because a presentation on a list section is copied onto every row.
    let onAddTicket: () -> Void

    @Environment(TripStore.self) private var trips

    private var saved: SavedTrip? { trips.saved(itinerary) }

    var body: some View {
        let regions = TransitRegion.along(itinerary)
        if !regions.isEmpty {
            Section {
                ForEach(regions, id: \.network) { RegionTicketRow(region: $0) }
            } header: {
                Text("Tickets")
            }
        }
        FareSection(itinerary: itinerary)
        if Features.tickets {
            TicketSection(itinerary: itinerary, tripId: saved?.id, onAddTicket: {
                trips.ensureSaved(itinerary, from: fromName, to: toName)
                onAddTicket()
            })
        }
        // Looking at a route shows no tickets; a saved or started trip does.
        if Features.passes, !itinerary.isDirect, saved != nil {
            TripPassSection(tripId: saved?.id, at: itinerary.startTime,
                            ensureTrip: { trips.ensureSaved(itinerary, from: fromName, to: toName).id })
        }
        TicketShopSection(itinerary: itinerary, tripId: { trips.ensureSaved(itinerary, from: fromName, to: toName).id })
    }
}

/// A square, icon-only action next to the start button.
struct BarIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title3.weight(.semibold))
            .foregroundStyle(Color.ink)
            .frame(width: 46, height: 46)
            .background(Color.inkFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.35)
    }
}

/// "End trip": the ink button's shape in the danger colour, so a running trip reads differently at a glance.
struct EndTripButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(minHeight: 46)
            .background(Color.danger, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(configuration.isPressed ? 0.75 : 1)
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
        event.url = CalendarText.url(trip)
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

extension TripStore {
    /// Deletes trips unsaved on a screen that has closed, with their reminder and Live Activity.
    func discardPendingRemovals() {
        for id in removePending() {
            LeaveReminder.cancel(id)
            Task { await LiveTripActivity.end(id) }
        }
    }

    /// The same once the back animation has finished: removing a trip mid-transition changes
    /// the list being revealed (Saved, Plan) while UIKit is laying it out.
    func discardPendingRemovalsLater() {
        guard !pendingRemoval.isEmpty else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            discardPendingRemovals()
        }
    }
}

extension TripStore {
    /// The saved trip for this route, kept if it was just unsaved here, else saved now.
    @discardableResult
    func ensureSaved(_ itinerary: Itinerary, from: String, to: String) -> SavedTrip {
        if let saved = saved(itinerary) {
            keep(saved.id)
            return saved
        }
        return save(itinerary, from: from, to: to)
    }
}

import SwiftUI

/// The first screen: tickets above all, then the trip under way, then the ways in (where to, nearby, saved).
struct WatchHomeView: View {
    @Environment(WatchLibrary.self) private var library

    var body: some View {
        TimelineView(.everyMinute) { context in
            let snap = library.snapshot
            let now = context.date
            List {
                ticketRows(snap, now: now)
                if let trip = snap.current(now: now) {
                    NavigationLink(value: WatchRoute.trip(trip.id)) {
                        WatchLiveTile(trip: trip, started: snap.activeTripId == trip.id, now: now)
                    }
                    .listRowBackground(Color.live.opacity(0.18).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous)))
                }
                NavigationLink(value: WatchRoute.plan) {
                    Label("Where to?", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                }
                NavigationLink(value: WatchRoute.nearby) {
                    Label("Nearby", systemImage: "location.fill")
                }
                NavigationLink(value: WatchRoute.saved) {
                    Label("Saved", systemImage: "star.fill")
                }
            }
        }
        .navigationTitle(Text(verbatim: "Publit"))
    }

    /// Tickets that are valid now open their code with one tap; the row below lists all of them.
    @ViewBuilder
    private func ticketRows(_ snap: WatchSnapshot, now: Date) -> some View {
        let valid = WatchTickets.validNow(snap.tickets, at: now)
        ForEach(valid.prefix(2)) { ticket in
            NavigationLink(value: WatchRoute.ticket(ticket.id)) {
                WatchTicketRow(pass: ticket.pass, now: now)
            }
            .listRowBackground(Color.appAccent.opacity(0.22).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous)))
        }
        NavigationLink(value: WatchRoute.tickets) {
            HStack {
                Label("Tickets", systemImage: "ticket.fill")
                Spacer(minLength: 4)
                if !snap.tickets.isEmpty {
                    Text(verbatim: "\(snap.tickets.count)").foregroundStyle(.secondary).monospacedDigit()
                }
            }
        }
    }
}

/// The trip under way (or about to start): where, and what to do next.
struct WatchLiveTile: View {
    let trip: SavedTrip
    let started: Bool
    let now: Date

    var body: some View {
        let status = TripStatus.at(now, trip.itinerary)
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: "dot.radiowaves.left.and.right").font(.caption2).foregroundStyle(Color.live)
                Text("Live").font(.caption2.weight(.bold)).foregroundStyle(Color.live)
            }
            Text(verbatim: trip.toName).font(.headline).lineLimit(1)
            Text(verbatim: status.headline)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(status.delayMinutes > 0 ? Color.delay : Color.primary)
                .lineLimit(2)
            Text(verbatim: status.detail).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
        }
        .accessibilityElement(children: .combine)
    }
}

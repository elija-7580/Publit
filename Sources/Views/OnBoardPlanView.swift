// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich
import SwiftUI

/// "I'm on board": plan from the vehicle you are riding. Pick where to go; the routes start with
/// this ride (stay on, or change at a stop still ahead), with live times. Idea from BudapestGO (BKK).
struct OnBoardPlanView: View {
    /// The vehicle's whole ride, as loaded by the trip screen.
    let trip: Leg
    let lineName: String

    @Environment(\.dismiss) private var dismiss
    @State private var destination: SavedPlace?
    @State private var picking = false
    @State private var routes: [Itinerary] = []
    @State private var position: OnBoardPlan.Position?
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var opened: OpenedRoute?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    header
                    Button { picking = true } label: {
                        HStack {
                            Label(destination?.name ?? L10n.t("Where to?"), systemImage: "mappin.and.ellipse")
                                .foregroundStyle(destination == nil ? Color.secondary : Color.primary)
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("onBoardDestination")
                } footer: {
                    Text("Routes start with this ride: stay on, or change at a stop still ahead. Idea: BudapestGO (BKK Budapest).")
                }
                if destination != nil {
                    Section {
                        if loading && routes.isEmpty {
                            LogoLoader()
                        } else if let errorMessage, routes.isEmpty {
                            Text(errorMessage).foregroundStyle(.secondary)
                        }
                        ForEach(routes, id: \.routeKey) { it in
                            Button { opened = OpenedRoute(itinerary: it) } label: {
                                ItineraryRow(itinerary: it, windowStart: it.startTime,
                                             windowEnd: it.startTime.addingTimeInterval(span), showLeave: false)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(.isLink)
                            .accessibilityIdentifier("onBoardRoute")
                        }
                    }
                }
            }
            .navigationTitle("Plan from this vehicle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .navigationDestination(item: $opened) { route in
                ItineraryDetailView(itinerary: route.itinerary, fromName: L10n.f("On board %@", lineName),
                                    toName: destination?.name ?? "")
            }
            .sheet(isPresented: $picking) {
                PlaceSearchView(title: "Where to?", allowCurrentLocation: false) { endpoint in
                    if case .place(let place) = endpoint { destination = place }
                    picking = false
                }
            }
            .task(id: destination?.id) { await search() }
            .refreshable { await search() }
            .onAppear { if destination == nil { picking = true } }
            .screenTrail("OnBoardPlan")
        }
    }

    /// "Next stop: Deák Ferenc tér, in 2 min".
    @ViewBuilder private var header: some View {
        let now = Date()
        if let pos = OnBoardPlan.position(stops: trip.allStops, now: now) {
            let next = trip.allStops[pos.next]
            let minutes = max(0, Int((pos.at.timeIntervalSince(now) / 60).rounded()))
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: L10n.f("On board %@", lineName)).font(.headline)
                    Text(verbatim: minutes == 0 ? L10n.f("Now at %@", next.name)
                                                : L10n.f("Next stop: %@, in %lld min", next.name, minutes))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "tram.fill").foregroundStyle(trip.lineStroke)
            }
            .accessibilityElement(children: .combine)
        } else {
            Text("This ride has ended.").foregroundStyle(.secondary)
        }
    }

    private var span: TimeInterval {
        guard let first = routes.map(\.startTime).min(), let last = routes.map(\.endTime).max() else { return 3600 }
        return max(1800, last.timeIntervalSince(first))
    }

    private func search() async {
        guard let destination else { return }
        guard let pos = OnBoardPlan.position(stops: trip.allStops, now: .now) else {
            errorMessage = L10n.t("This ride has ended.")
            return
        }
        position = pos
        loading = true
        defer { loading = false }
        let start = trip.allStops[pos.next]
        do {
            let res = try await TransitousClient.shared.plan(
                from: start.coordinate, to: destination.coordinate, time: pos.at, arriveBy: false,
                stops: PlanStops(from: start.stopId, to: destination.stopId))
            routes = OnBoardPlan.routes(res.itineraries + res.direct, trip: trip, position: pos)
            errorMessage = routes.isEmpty ? L10n.t("No connections found.") : nil
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
            errorMessage = error.localizedDescription
        }
    }
}

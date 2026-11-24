// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich
import SwiftUI

/// Build your own connection, part 3 (#143): the place to change is only a suggestion. It can be
/// moved to another stop of the ride (earlier or later than planned) or to a place found by search
/// or on the map. The legs before the ride stay; the way there and the way on are planned again
/// to meet at the new point.
struct ChangePointView: View {
    let route: Itinerary
    /// The ride whose change is moved.
    let index: Int
    var onChoose: (Itinerary) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var stops: [Place] = []
    @State private var loading = true
    @State private var picking = false
    @State private var target: ChangeTarget?

    private var leg: Leg? { route.legs[safe: index] }

    var body: some View {
        List {
            if let leg {
                Section {
                    if loading && stops.isEmpty {
                        HStack { Spacer(); ProgressView(); Spacer() }
                    }
                    ForEach(Array(stops.enumerated()), id: \.offset) { _, stop in
                        let planned = RouteBuilder.samePlace(stop, leg.to)
                        Button {
                            target = ChangeTarget(name: stop.name, coordinate: stop.coordinate, stopId: stop.stopId,
                                                  tripId: leg.tripId, tz: stop.tz)
                        } label: {
                            HStack(spacing: 10) {
                                Text(verbatim: (stop.arrival ?? stop.departure).map { Fmt.time($0, tz: stop.tz ?? leg.to.tz) } ?? "")
                                    .font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                                    .frame(minWidth: 44, alignment: .leading)
                                Text(verbatim: stop.name).font(.subheadline.weight(planned ? .semibold : .regular))
                                    .foregroundStyle(Color.ink).lineLimit(2)
                                Spacer(minLength: 4)
                                if planned {
                                    Text("Planned").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(planned)
                        .accessibilityIdentifier("changePointStop")
                    }
                } header: {
                    Text(L10n.f("%@: get off at", leg.lineName))
                } footer: {
                    Text("The way up to the ride stays as it is. From the new stop, Publit looks for the way on.")
                }
                .inkCard()

                Section {
                    Button { picking = true } label: {
                        Label("Another place, by search or on the map", systemImage: "magnifyingglass")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("changePointSearch")
                }
                .inkCard()
            }
        }
        .inkList()
        .navigationTitle("Change somewhere else")
        .navigationBarTitleDisplayMode(.inline)
        .screenTrail("Change point")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        }
        .task { await loadStops() }
        .sheet(isPresented: $picking) {
            PlaceSearchView(title: "Change at", allowCurrentLocation: false, chooseOnMap: true) { endpoint in
                guard case .place(let p) = endpoint else { return }
                target = ChangeTarget(name: p.name, coordinate: p.coordinate, stopId: p.stopId, tripId: nil, tz: nil)
            }
        }
        .navigationDestination(item: $target) { t in
            ChangePointChoicesView(route: route, index: index, target: t) { onChoose($0); dismiss() }
        }
    }

    /// The vehicle's whole trip, so stops after the planned one can be chosen too.
    private func loadStops() async {
        guard let leg else { loading = false; return }
        stops = RouteBuilder.exitStops(of: leg, trip: nil)
        defer { loading = false }
        guard let id = leg.tripId,
              let trip = try? await TransitousClient.shared.trip(id: id).legs.first(where: \.isTransit),
              !Task.isCancelled else { return }
        stops = RouteBuilder.exitStops(of: leg, trip: trip)
    }
}

/// The new change point: a stop of the ride (with its vehicle) or any place.
struct ChangeTarget: Hashable, Identifiable {
    let name: String
    let coordinate: LatLon
    let stopId: String?
    /// The ride's vehicle, when the point is one of its stops.
    let tripId: String?
    let tz: String?
    var id: String { "\(stopId ?? name)@\(coordinate.lat),\(coordinate.lon)" }
}

/// The ways on from the new change point, each as the whole route.
private struct ChangePointChoicesView: View {
    let route: Itinerary
    let index: Int
    let target: ChangeTarget
    var onChoose: (Itinerary) -> Void
    @State private var way: Itinerary?
    @State private var choices: [Itinerary] = []
    @State private var loading = true
    @State private var failure: LocalizedStringKey?

    var body: some View {
        List {
            Section {
                ForEach(choices) { choice in
                    Button { onChoose(choice) } label: {
                        LegChoiceRow(choice: choice, from: index + (way?.legs.count ?? 0), current: false)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("changePointChoice")
                }
                if loading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if let failure {
                    Text(failure).font(.footnote).foregroundStyle(.secondary)
                        .accessibilityIdentifier("changePointFailure")
                    Button("Try again") { Task { await load() } }
                }
            } header: {
                if let way {
                    Text(L10n.f("From %@, after %@", target.name, Fmt.time(way.endTime, tz: target.tz ?? way.legs.last?.to.tz)))
                } else {
                    Text(verbatim: target.name)
                }
            } footer: {
                if way != nil, target.tripId != nil, way?.legs.filter(\.isTransit).first?.tripId != target.tripId {
                    Text("The ride does not stop there in time, so another way there is shown.")
                }
            }
            .inkCard()
        }
        .inkList()
        .navigationTitle(Text(verbatim: target.name))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        guard let restart = RouteBuilder.restart(route, at: index), let leg = route.legs[safe: index] else {
            loading = false; return
        }
        loading = true
        failure = nil
        defer { loading = false }
        let options = RouteOptions.load()
        do {
            // 1. To the new point, leaving where the ride starts, not before the kept legs arrive.
            let there = try await TransitousClient.shared.plan(
                from: restart.from.coordinate, to: target.coordinate, time: min(restart.earliest, leg.startTime),
                arriveBy: false, options: options, stops: PlanStops(from: restart.from.stopId, to: target.stopId))
            guard !Task.isCancelled else { return }
            guard let found = RouteBuilder.wayToChange(route, at: index, tripId: target.tripId, from: there.itineraries) else {
                failure = "No way found to this place in time. Choose another stop."
                return
            }
            way = found
            // 2. On from there to the destination, after arriving.
            let on = try await TransitousClient.shared.plan(
                from: target.coordinate, to: restart.to.coordinate, time: found.endTime, arriveBy: false,
                options: options, stops: PlanStops(from: target.stopId, to: restart.to.stopId))
            guard !Task.isCancelled else { return }
            choices = RouteBuilder.choices(for: route, at: index, way: found, from: on.itineraries)
            if choices.isEmpty { failure = "No way on from this place to your destination. Choose another stop." }
        } catch {
            if !HangLog.isCancellation(error) {
                failure = "The ways to go on could not be loaded. Check your connection and try again."
            }
        }
    }
}

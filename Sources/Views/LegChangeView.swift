// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich
import SwiftUI

/// A route built leg by leg, as a navigation value (an `Itinerary` is not hashable).
struct BuiltRoute: Identifiable, Hashable {
    let itinerary: Itinerary
    var id: String { itinerary.id }
    static func == (a: BuiltRoute, b: BuiltRoute) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Build your own connection, part 2 (#142): the ways to go on from one leg of a route. The legs
/// before it stay as they are; choosing a way replaces that leg and what follows.
struct LegChangeView: View {
    let route: Itinerary
    /// The leg to replace.
    let index: Int
    var onChoose: (Itinerary) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var choices: [Itinerary] = []
    @State private var nextPage: String?
    @State private var loading = true
    @State private var loadingMore = false
    @State private var failed = false

    private var restart: RouteBuilder.Restart? { RouteBuilder.restart(route, at: index) }
    private var stopName: String { ItineraryDetailView.placeName(restart?.from) }

    var body: some View {
        List {
            if let restart {
                Section {
                    ForEach(choices) { choice in
                        Button { onChoose(choice); dismiss() } label: {
                            LegChoiceRow(choice: choice, from: index, current: choice.routeKey == route.routeKey)
                        }
                        .buttonStyle(.plain)
                        .disabled(choice.routeKey == route.routeKey)
                        .accessibilityIdentifier("legChoice")
                    }
                    if loading {
                        HStack { Spacer(); ProgressView(); Spacer() }
                    } else if failed {
                        Text("The ways to go on could not be loaded. Check your connection and try again.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button("Try again") { Task { await load(restart) } }
                    } else if choices.allSatisfy({ $0.routeKey == route.routeKey }) {
                        Text("No other way to go on from here.")
                            .font(.footnote).foregroundStyle(.secondary)
                            .accessibilityIdentifier("noLegChoice")
                    }
                    if nextPage != nil, !loading {
                        Button { Task { await more(restart) } } label: {
                            HStack {
                                Text("Later")
                                if loadingMore { Spacer(); ProgressView() }
                            }
                        }
                        .disabled(loadingMore)
                        .accessibilityIdentifier("laterLegChoices")
                    }
                } header: {
                    Text(L10n.f("From %@, after %@", stopName, Fmt.time(restart.earliest, tz: restart.from.tz)))
                } footer: {
                    if index > 0 {
                        Text("The way up to here stays as it is. Only ways you can still reach are listed.")
                    }
                }
                .inkCard()
            }
        }
        .inkList()
        .navigationTitle("Go on another way")
        .navigationBarTitleDisplayMode(.inline)
        .screenTrail("Change leg")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        }
        .task {
            if let restart { await load(restart) } else { loading = false }
        }
    }

    private func search(_ restart: RouteBuilder.Restart, page: String?) async throws -> PlanResponse {
        try await TransitousClient.shared.plan(from: restart.from.coordinate, to: restart.to.coordinate, time: restart.earliest,
                                               arriveBy: false, pageCursor: page, options: RouteOptions.load(),
                                               stops: PlanStops(from: restart.from.stopId, to: restart.to.stopId))
    }

    private func load(_ restart: RouteBuilder.Restart) async {
        loading = true
        failed = false
        defer { loading = false }
        do {
            let res = try await search(restart, page: nil)
            guard !Task.isCancelled else { return }
            choices = RouteBuilder.choices(for: route, at: index, from: res.itineraries)
            nextPage = res.nextPageCursor
        } catch {
            failed = !HangLog.isCancellation(error)
        }
    }

    private func more(_ restart: RouteBuilder.Restart) async {
        guard let page = nextPage else { return }
        loadingMore = true
        defer { loadingMore = false }
        guard let res = try? await search(restart, page: page) else { return }
        let known = Set(choices.map(\.routeKey))
        choices += RouteBuilder.choices(for: route, at: index, from: res.itineraries).filter { !known.contains($0.routeKey) }
        nextPage = res.nextPageCursor
    }
}

/// One way to go on: its lines, when it leaves the stop and when the whole route arrives.
private struct LegChoiceRow: View {
    let choice: Itinerary
    /// Index of the first leg that is new.
    let from: Int
    let current: Bool

    private var rest: [Leg] { Array(choice.legs.dropFirst(from)) }
    private var rides: [Leg] { rest.filter(\.isTransit) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Fmt.time(rides.first?.startTime ?? rest.first?.startTime ?? choice.startTime, tz: rest.first?.from.tz)) – \(Fmt.time(choice.endTime, tz: choice.legs.last?.to.tz))")
                    .font(.headline.monospacedDigit())
                    .lineLimit(1).minimumScaleFactor(0.8)
                if rest.contains(where: \.realTime) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.caption).foregroundStyle(Color.live)
                        .accessibilityLabel("Live data")
                }
                Spacer(minLength: 8)
                if current {
                    Text("Your route").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            if rides.isEmpty {
                Label(L10n.t("On foot"), systemImage: "figure.walk").font(.subheadline)
            } else {
                HStack(spacing: 4) {
                    ForEach(Array(rides.prefix(5).enumerated()), id: \.offset) { i, leg in
                        if i > 0 {
                            Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
                        }
                        LineBadge(leg)
                    }
                }
                if let direction = rides.first?.directionName, !direction.isEmpty {
                    Text(verbatim: "→ \(direction)").font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .opacity(current ? 0.6 : 1)
    }
}

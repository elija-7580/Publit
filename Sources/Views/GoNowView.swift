import SwiftUI

/// Nearby → "Where to now?": best ways from here, leaving now, kept live.
struct GoNowView: View {
    @Environment(AppState.self) private var app
    @Environment(LocationManager.self) private var location
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false
    @State private var selectedId: String?
    /// Picking another start than the current location.
    @State private var pickingStart = false
    /// iPad layout: the routes are on the big map, not in a small one at the top.
    @Environment(WideMapState.self) private var wideMap: WideMapState?

    var body: some View {
        let plan = app.goNow
        let its = plan.sortedItineraries
        let span = TimeInterval(its.map(\.duration).max() ?? 0)
        let badges = SmartRouting.isEnabled ? SmartRouting.badges(its, arriveBy: false) : [:]
        List {
            if !its.isEmpty && wideMap == nil {
                // Redrawn only when the routes change, not on every refresh of this list (long routes
                // with many points made opening one wait for the map).
                CompareMapView(itineraries: its, selectedId: selectedId ?? its.first?.routeKey)
                    .equatable()
                    .frame(height: 220)
                    .listRowInsets(EdgeInsets())
            }
            Section {
                // Not always from here: a friend's place, the hotel, the station you will be at.
                Button { pickingStart = true } label: {
                    HStack(spacing: 8) {
                        Text("From").font(.subheadline).foregroundStyle(.secondary)
                            .frame(minWidth: 44, alignment: .leading)
                        if case .currentLocation = plan.from { SignatureDot(size: 9) }
                        Text(verbatim: plan.from.title).font(.body.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                        Spacer(minLength: 0)
                        Text("Change").font(.subheadline.weight(.semibold)).foregroundStyle(Color.inkAction)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("goNowFrom")
                RouteOptionsButton()
            }
            Section {
                OfflineNote()
                if plan.isLoading && its.isEmpty {
                    LogoLoader()
                } else if let msg = plan.errorMessage, its.isEmpty {
                    Text(msg).foregroundStyle(.secondary)
                }
                if let note = plan.walkNote, !its.isEmpty {
                    // Found only with a longer walk: say so, the walk is part of the decision.
                    Label(note, systemImage: "figure.walk")
                        .font(.footnote).foregroundStyle(Color.delay)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("longWalkNote")
                }
                ForEach(its) { it in
                    NavigationLink {
                        ItineraryDetailView(itinerary: it, fromName: plan.from.title, toName: plan.to?.title ?? "")
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            if let dep = it.firstDeparture {
                                Text(leaveText(it, firstDeparture: dep))
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(it.startTime < .now.addingTimeInterval(120) ? Color.delay : .secondary)
                            } else {
                                Text("Walk all the way").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                            }
                            ItineraryRow(itinerary: it, windowStart: it.startTime, windowEnd: it.startTime.addingTimeInterval(span),
                                         badges: badges[it.routeKey] ?? [], showLeave: false)
                        }
                    }
                    .linkIndicatorHidden()
                }
                if plan.canLoadMore {
                    Button("Later connections") { Task { await plan.loadMore() } }
                }
            } header: {
                if case .currentLocation = plan.from {
                    Text("From your location")
                } else {
                    Text(verbatim: L10n.f("from %@", plan.from.title))
                }
            } footer: {
                if let note = its.first.flatMap({ Fmt.foreignZoneNote(tz: $0.legs.first?.from.tz, at: $0.startTime) }) {
                    Label(note, systemImage: "clock")
                }
            }
            StreetComparisonSection(comparisons: plan.comparisons,
                                    bestTransit: its.filter { !$0.isDirect }.map(\.duration).min(),
                                    fromName: plan.from.title, toName: plan.to?.title ?? "")
        }
        .readableWidth()
        .inkList()
        .navigationTitle(plan.to?.title ?? L10n.t("Route"))
        .wideMapScene(its.isEmpty ? .explore : .routes(its, selected: selectedId ?? its.first?.routeKey))
        .screenTrail("Go now")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $pickingStart) {
            PlaceSearchView(title: "From", allowCurrentLocation: true) { endpoint in
                if endpoint == plan.to { plan.to = plan.from }
                plan.from = endpoint
            }
        }
        .refreshable { await plan.search(current: location.coordinate, locationDenied: location.isDenied, silent: true) }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        .task(id: "\(plan.queryKey)|\(scenePhase)|\(isVisible)") {
            guard isVisible, scenePhase == .active else { return }
            await plan.search(current: location.coordinate, locationDenied: location.isDenied)
            while !Task.isCancelled {
                try? await Task.sleep(for: PlanView.refreshInterval)
                guard !Task.isCancelled else { break }
                await plan.search(current: location.coordinate, locationDenied: location.isDenied, silent: true)
            }
        }
        .onChange(of: location.hasFix) { _, hasFix in
            if hasFix, plan.itineraries.isEmpty { Task { await plan.search(current: location.coordinate) } }
        }
    }

    private func leaveText(_ it: Itinerary, firstDeparture: Date) -> String {
        let mins = Int(ceil(it.startTime.timeIntervalSinceNow / 60))
        return Reach.leaveText(it, minutes: mins)
    }
}

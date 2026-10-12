import SwiftUI

/// Nearby → "Where to now?": best ways from here, leaving now, kept live.
struct GoNowView: View {
    @Environment(AppState.self) private var app
    @Environment(LocationManager.self) private var location
    @State private var selectedId: String?

    var body: some View {
        let plan = app.goNow
        let its = plan.itineraries
        let windowStart = its.map(\.startTime).min() ?? .now
        let windowEnd = its.map(\.endTime).max() ?? .now
        List {
            if !its.isEmpty {
                CompareMapView(itineraries: its, selectedId: selectedId ?? its.first?.id)
                    .frame(height: 220)
                    .listRowInsets(EdgeInsets())
            }
            Section {
                OfflineNote()
                if plan.isLoading && its.isEmpty {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if let msg = plan.errorMessage, its.isEmpty {
                    Text(msg).foregroundStyle(.secondary)
                }
                ForEach(its) { it in
                    NavigationLink {
                        ItineraryDetailView(itinerary: it, fromName: L10n.t("Current location"), toName: plan.to?.title ?? "")
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            if let dep = it.firstDeparture {
                                Text(leaveText(it, firstDeparture: dep))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(it.startTime < .now.addingTimeInterval(120) ? Color.delay : .secondary)
                            } else {
                                Text("Walk all the way").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            }
                            ItineraryRow(itinerary: it, windowStart: windowStart, windowEnd: windowEnd)
                        }
                    }
                    .simultaneousGesture(TapGesture().onEnded { selectedId = it.id })
                }
                if plan.canLoadMore {
                    Button("Later connections") { Task { await plan.loadMore() } }
                }
            } header: {
                Text("From your location")
            } footer: {
                if let note = its.first.flatMap({ Fmt.foreignZoneNote(tz: $0.legs.first?.from.tz, at: $0.startTime) }) {
                    Label(note, systemImage: "clock")
                }
            }
        }
        .navigationTitle(plan.to?.title ?? L10n.t("Route"))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await plan.search(current: location.coordinate, locationDenied: location.isDenied, silent: true) }
        .task(id: plan.queryKey) {
            await plan.search(current: location.coordinate, locationDenied: location.isDenied)
            while !Task.isCancelled {
                try? await Task.sleep(for: PlanView.refreshInterval)
                guard !Task.isCancelled else { break }
                await plan.search(current: location.coordinate, locationDenied: location.isDenied, silent: true)
            }
        }
        .onChange(of: location.coordinate == nil) { _, isNil in
            if !isNil, plan.itineraries.isEmpty { Task { await plan.search(current: location.coordinate) } }
        }
    }

    private func leaveText(_ it: Itinerary, firstDeparture: Date) -> String {
        let mins = Int(ceil(it.startTime.timeIntervalSinceNow / 60))
        return mins <= 0 ? L10n.t("Leave now") : L10n.f("Leave in %lld min", mins)
    }
}

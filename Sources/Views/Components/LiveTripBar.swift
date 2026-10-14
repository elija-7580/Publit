import SwiftUI

/// A bar above the tab bar while a saved trip is on: what to do next ("Leave in 6 min",
/// "Get off at …"), the line, delay and how far along the trip is. Tap for the trip with live status.
/// Shown 30 min before leaving until 5 min after arrival, or for the trip started by hand.
struct LiveTripBar: View {
    @Environment(TripStore.self) private var trips
    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    /// Hidden by hand for this trip only; the next trip shows again.
    @AppStorage("liveBarHiddenTrip") private var hiddenId = ""

    var body: some View {
        // Minute clock: countdowns are in whole minutes, so one redraw a minute is enough.
        let now = Ticker.minute.now
        if let trip = trips.current(now: now), trip.id != hiddenId {
            bar(trip, now: now)
                .task(id: "\(trip.id)|\(scenePhase)") { await follow(trip.id) }
        }
    }

    private func bar(_ trip: SavedTrip, now: Date) -> some View {
        let it = trip.itinerary
        let status = TripStatus.at(now, it)
        let leg = it.transitLegs.first { $0.endTime > now }
        let total = max(it.endTime.timeIntervalSince(it.startTime), 60)
        let progress = min(max(now.timeIntervalSince(it.startTime) / total, 0), 1)
        let alert = status.phase == .cancelled || status.delayMinutes > 0
        let color: Color = status.phase == .cancelled ? .danger : status.delayMinutes > 0 ? .delay : .ink
        return HStack(spacing: 10) {
            Button { app.deepLink = .trip(trip.id) } label: {
                HStack(spacing: 10) {
                    if let leg { LineBadge(leg) } else {
                        Image(systemName: status.phase == .arrived ? "flag.checkered" : "figure.walk")
                            .font(.body.weight(.semibold)).frame(width: 28)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(verbatim: status.headline).font(.subheadline.weight(.semibold)).lineLimit(1)
                            if status.delayMinutes > 0 {
                                Text(verbatim: "+\(status.delayMinutes)").font(.caption.weight(.bold).monospacedDigit())
                                    .foregroundStyle(Color.delay)
                            }
                        }
                        Text(verbatim: status.detail.isEmpty ? trip.title : status.detail)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        InkProgress(value: progress, tint: color).padding(.top, 2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("liveTripBar")
            Button { hiddenId = trip.id } label: {
                Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    .frame(width: 32, height: 32).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Hide"))
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(alert ? color.opacity(0.35) : Color.primary.opacity(0.08)))
        .padding(.horizontal, 10).padding(.bottom, 6)
    }

    /// Live times every 90 s while the app is open and the trip is not over.
    private func follow(_ id: String) async {
        guard scenePhase == .active else { return }
        while !Task.isCancelled {
            guard let t = trips.trip(id), t.endTime > .now else { return }
            await SavedTripView.refresh(t, in: trips)
            try? await Task.sleep(for: Energy.duration(90))
        }
    }
}

extension View {
    /// The live trip bar above the tab bar, on every screen of a tab.
    func liveTripBar() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) { LiveTripBar() }
    }
}

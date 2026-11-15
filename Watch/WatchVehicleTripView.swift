import SwiftUI

/// The whole trip of the vehicle behind one ride (TripView on the iPhone): every stop with its time, also those
/// before boarding; where you get on and off in bold, stops already passed grey, where the vehicle is now.
struct WatchVehicleTripView: View {
    /// The ride, as it is in the trip.
    let leg: Leg

    @Environment(\.scenePhase) private var scenePhase
    @State private var trip: Itinerary?
    @State private var failed = false

    private var full: Leg? { trip?.legs.first(where: \.isTransit) }
    private var stops: [Place] { full?.allStops ?? leg.allStops }

    var body: some View {
        TimelineView(.everyMinute) { context in
            let stops = stops
            let progress = TripProgress.at(context.date, stops: stops)
            let board = StopGrouping.normalizedName(leg.from.name)
            let exit = StopGrouping.normalizedName(leg.to.name)
            List {
                VStack(alignment: .leading, spacing: 3) {
                    LineBadge(leg, compact: true)
                    DirectionLabel(direction: leg.shownDirection, circular: leg.isCircular, font: .footnote).lineLimit(2)
                    Label(status(progress, stops: stops), systemImage: (full?.realTime ?? leg.realTime) ? "dot.radiowaves.left.and.right" : "calendar")
                        .font(.caption2)
                        .foregroundStyle((full?.realTime ?? leg.realTime) ? Color.live : Color.secondary)
                }
                .listRowBackground(Color.clear)
                if trip == nil && !failed {
                    HStack { Spacer(); ProgressView(); Spacer() }.listRowBackground(Color.clear)
                } else if failed && trip == nil {
                    Button("Try again") { Task { await load() } }
                }
                Section("Stops") {
                    ForEach(Array(stops.enumerated()), id: \.offset) { i, stop in
                        let name = StopGrouping.normalizedName(stop.name)
                        row(stop, focus: name == board || name == exit, past: isPast(i, progress))
                    }
                }
                if let trip {
                    NavigationLink(value: WatchRoute.map(OpenedRoute(itinerary: trip),
                                                         .leg(trip.legs.firstIndex(where: \.isTransit) ?? 0))) {
                        Label("Map", systemImage: "map.fill")
                    }
                }
            }
        }
        .navigationTitle(Text(verbatim: leg.lineName))
        .task(id: scenePhase == .active) {
            guard scenePhase == .active, leg.tripId != nil else { return }
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    private func row(_ stop: Place, focus: Bool, past: Bool) -> some View {
        let time = stop.departure ?? stop.arrival
        let scheduled = stop.scheduledDeparture ?? stop.scheduledArrival
        let delay = time.flatMap { t in scheduled.map { Int((t.timeIntervalSince($0) / 60).rounded()) } } ?? 0
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(verbatim: time.map { Fmt.time($0, tz: stop.tz) } ?? "–")
                    .font(.footnote.monospacedDigit().weight(focus ? .bold : .regular))
                if delay > 0 {
                    Text(verbatim: "+\(delay)").font(.caption2.monospacedDigit()).foregroundStyle(Color.delay)
                }
                if let track = TransitLabels.clean(stop.track) {
                    Spacer(minLength: 2)
                    Text(L10n.f("Pl. %@", track)).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Text(verbatim: stop.name)
                .font(.footnote.weight(focus ? .bold : .regular))
                .lineLimit(2)
                .strikethrough(stop.cancelled == true)
        }
        .foregroundStyle(past ? Color.secondary : Color.primary)
        .accessibilityElement(children: .combine)
    }

    private func isPast(_ i: Int, _ progress: TripProgress) -> Bool {
        switch progress {
        case .finished: return true
        case .notStarted: return false
        case .atStop(let k): return i < k
        case .between(let k, _): return i <= k
        }
    }

    private func status(_ progress: TripProgress, stops: [Place]) -> String {
        switch progress {
        case .notStarted: return L10n.t("Not departed yet")
        case .finished: return L10n.f("Arrived at %@", stops.last?.name ?? "")
        case .atStop(let i): return L10n.f("At %@", stops[i].name)
        case .between(let i, _): return L10n.f("Between %@ and %@", stops[i].name, stops[i + 1].name)
        }
    }

    private func load() async {
        guard let id = leg.tripId else { return }
        do {
            trip = try await TransitousClient.shared.trip(id: id)
            failed = false
        } catch {
            if !(error is CancellationError) { failed = true }
        }
    }
}

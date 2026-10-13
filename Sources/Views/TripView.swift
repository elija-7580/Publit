import SwiftUI
import MapKit

/// A departure to open as a trip, for value-based navigation.
struct TripTarget: Hashable {
    let stopTime: StopTime
    let stationId: String
    let stationName: String
    let coordinate: LatLon

    static func == (a: TripTarget, b: TripTarget) -> Bool { a.stopTime.id == b.stopTime.id && a.stationId == b.stationId }
    func hash(into h: inout Hasher) { h.combine(stopTime.id); h.combine(stationId) }
}

/// One vehicle's whole trip: every stop with live times, an estimated position, and "save this line".
struct TripView: View {
    let stopTime: StopTime
    /// Station the user came from (used to save the line there).
    let stationId: String
    let stationName: String
    let stationCoordinate: LatLon

    @Environment(FavoritesStore.self) private var favorites
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false
    @State private var trip: Itinerary?
    @State private var errorMessage: String?
    /// Stops at the station the user came from, worked out once per load instead of on every 15 s redraw.
    @State private var focusStops: Set<Int> = []
    /// Worked out once per load, not on every redraw: stops, alerts and the map's shape.
    @State private var stops: [Place] = []
    @State private var alerts: [Alert] = []
    @State private var shape: [LatLon] = []
    @State private var generation = 0

    private var leg: Leg? { trip?.legs.first(where: \.isTransit) }
    private var savedLine: SavedLine {
        SavedLine(stopTime: stopTime, stopId: stationId, stopName: stationName, at: stationCoordinate)
    }

    var body: some View {
        TimelineView(.periodic(from: .timelineAnchor, by: 15)) { ctx in
            List {
                Section {
                    DepartureRow(stopTime: stopTime)
                    ServiceAlertsView(alerts: trip == nil ? stopTime.serviceAlerts : alerts)
                }
                if let leg {
                    let progress = TripProgress.at(ctx.date, stops: stops)
                    Section {
                        OfflineNote()
                        TripMap(generation: generation, shape: shape, stops: stops.map(\.coordinate),
                                color: leg.lineColor, textColor: leg.lineTextColor, mode: leg.mode,
                                vehicle: TripProgress.position(progress, stops: stops))
                            .equatable()
                            .frame(height: 240)
                            .listRowInsets(EdgeInsets())
                        statusLine(progress: progress, stops: stops, leg: leg)
                    }
                    Section("Stops") {
                        ForEach(Array(stops.enumerated()), id: \.offset) { i, stop in
                            StopTimeRow(stop: stop, isFocus: focusStops.contains(i),
                                        isPast: isPast(i, progress: progress), realTime: leg.realTime)
                        }
                    }
                } else if let errorMessage {
                    Text(errorMessage).foregroundStyle(.secondary)
                } else {
                    HStack { Spacer(); ProgressView(); Spacer() }
                }
            }
        }
        .navigationTitle(stopTime.lineName)
        .screenTrail("Trip")
        .navigationBarTitleDisplayMode(.inline)
        .showPassToolbar(at: stopTime.departureTime, enabled: Features.passes)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { favorites.toggle(savedLine) } label: {
                    Label(favorites.containsLine(savedLine.id) ? L10n.t("Saved line") : L10n.t("Save line"),
                          systemImage: favorites.containsLine(savedLine.id) ? "star.fill" : "star")
                }
            }
        }
        .refreshable { await load() }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        .task(id: isVisible && scenePhase == .active) {
            guard isVisible, scenePhase == .active else { return }
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    private func isPast(_ i: Int, progress: TripProgress) -> Bool {
        switch progress {
        case .finished: return true
        case .notStarted: return false
        case .atStop(let k): return i < k
        case .between(let k, _): return i <= k
        }
    }

    @ViewBuilder
    private func statusLine(progress: TripProgress, stops: [Place], leg: Leg) -> some View {
        let text: String = {
            switch progress {
            case .notStarted: return L10n.t("Not departed yet")
            case .finished: return L10n.f("Arrived at %@", stops.last?.name ?? "")
            case .atStop(let i): return L10n.f("At %@", stops[i].name)
            case .between(let i, _): return L10n.f("Between %@ and %@", stops[i].name, stops[i + 1].name)
            }
        }()
        Label(text, systemImage: leg.realTime ? "dot.radiowaves.left.and.right" : "calendar")
            .font(.subheadline)
            .foregroundStyle(leg.realTime ? Color.live : Color.secondary)
        if !leg.realTime {
            Text("No live data for this trip. Position estimated from the timetable.")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            Text("Position estimated from live stop times.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func load() async {
        do {
            let fresh = try await TransitousClient.shared.trip(id: stopTime.tripId)
            let station = StopGrouping.normalizedName(stationName)
            let freshLeg = fresh.legs.first(where: \.isTransit)
            let all = freshLeg?.allStops ?? []
            focusStops = Set(all.indices.filter { StopGrouping.normalizedName(all[$0].name) == station })
            alerts = Alert.relevant(stopTime.serviceAlerts + (freshLeg?.serviceAlerts ?? []))
            let freshShape = freshLeg?.legGeometry.mapPoints ?? []
            // The map is rebuilt only when the route or its stops moved, not for new times.
            if freshShape != shape || all.map(\.coordinate) != stops.map(\.coordinate) {
                shape = freshShape
                generation += 1
                HangLog.shared.note("trip loaded: \(all.count) stops, \(freshShape.count) map points, \(alerts.count) alerts")
            }
            stops = all
            trip = fresh
            errorMessage = nil
        } catch {
            if !(error is CancellationError) && (error as? URLError)?.code != .cancelled {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// The trip on a map. Redrawn only for a new load or a moved vehicle, not on every list update.
/// Stop dots and the vehicle have no titles, so MapKit lays out no labels for them.
private struct TripMap: View, Equatable {
    let generation: Int
    let shape: [LatLon]
    let stops: [LatLon]
    let color: Color
    let textColor: Color
    let mode: String
    let vehicle: LatLon?

    static func == (a: TripMap, b: TripMap) -> Bool {
        a.generation == b.generation && a.vehicle?.lat == b.vehicle?.lat && a.vehicle?.lon == b.vehicle?.lon
    }

    var body: some View {
        Map(initialPosition: .automatic) {
            MapPolyline(coordinates: shape.map(\.clCoordinate))
                .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            ForEach(Array(stops.enumerated()), id: \.offset) { _, s in
                Annotation("", coordinate: s.clCoordinate, anchor: .center) {
                    Circle().fill(.white).stroke(color, lineWidth: 2).frame(width: 8, height: 8)
                }
                .annotationTitles(.hidden)
            }
            if let vehicle {
                Annotation("", coordinate: vehicle.clCoordinate, anchor: .center) {
                    Image(systemName: ModeStyle.symbol(mode))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(textColor)
                        .padding(6)
                        .background(color, in: Circle())
                        .accessibilityLabel("Estimated vehicle position")
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
    }
}

private struct StopTimeRow: View {
    let stop: Place
    let isFocus: Bool
    let isPast: Bool
    let realTime: Bool

    var body: some View {
        let time = stop.departure ?? stop.arrival
        let scheduled = stop.scheduledDeparture ?? stop.scheduledArrival
        let delay = time.flatMap { t in scheduled.map { Int((t.timeIntervalSince($0) / 60).rounded()) } } ?? 0
        HStack(spacing: 10) {
            Text(time.map { Fmt.time($0, tz: stop.tz) } ?? "–")
                .font(.subheadline.weight(isFocus ? .bold : .regular).monospacedDigit())
                .lineLimit(1).fixedSize()
                .frame(minWidth: 52, alignment: .leading)
            if realTime && delay > 0 {
                Text("+\(delay)").font(.caption.monospacedDigit()).foregroundStyle(Color.delay)
            }
            Text(stop.name)
                .font(.subheadline.weight(isFocus ? .bold : .regular))
                .lineLimit(1)
                .strikethrough(stop.cancelled == true)
            Spacer()
            if let track = stop.track, !track.isEmpty {
                Text("Pl. \(track)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(isPast ? Color.secondary : Color.primary)
    }
}

/// Next departures of one saved line at its saved stop.
struct LineDeparturesView: View {
    let line: SavedLine
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false
    @State private var departures: [StopTime] = []
    @State private var errorMessage: String?
    @State private var loaded = false

    var body: some View {
        List {
            Section {
                if let errorMessage, departures.isEmpty {
                    Text(errorMessage).foregroundStyle(.secondary)
                } else if !loaded {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if departures.isEmpty {
                    Text("No departures of \(line.lineName) in the next hours.").foregroundStyle(.secondary)
                }
                ForEach(departures) { st in
                    NavigationLink {
                        TripView(stopTime: st, stationId: line.stopId, stationName: line.stopName,
                                 stationCoordinate: line.coordinate)
                    } label: { DepartureRow(stopTime: st) }
                }
            } header: {
                HStack { LineBadge(line); Text(L10n.f("At %@", line.stopName)).textCase(nil) }
            }
        }
        .navigationTitle(line.lineName)
        .screenTrail("Line trip")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        .task(id: isVisible && scenePhase == .active) {
            guard isVisible, scenePhase == .active else { return }
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    private func load() async {
        do {
            let res = try await TransitousClient.shared.departures(stopId: line.stopId, count: 100,
                                                                  radius: StopDeparturesView.stationRadius)
            departures = StopTime.upcoming(res.stopTimes).filter(line.matches)
            errorMessage = nil
        } catch {
            if !(error is CancellationError) && (error as? URLError)?.code != .cancelled {
                errorMessage = error.localizedDescription
            }
        }
        loaded = true
    }
}

import SwiftUI
import MapKit

/// One vehicle's whole trip: every stop with live times, an estimated position, and "save this line".
struct TripView: View {
    let stopTime: StopTime
    /// Station the user came from (used to save the line there).
    let stationId: String
    let stationName: String
    let stationCoordinate: LatLon

    @Environment(FavoritesStore.self) private var favorites
    @State private var trip: Itinerary?
    @State private var errorMessage: String?

    private var leg: Leg? { trip?.legs.first(where: \.isTransit) }
    private var savedLine: SavedLine {
        SavedLine(stopTime: stopTime, stopId: stationId, stopName: stationName, at: stationCoordinate)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { ctx in
            List {
                if let leg {
                    let stops = leg.allStops
                    let progress = TripProgress.at(ctx.date, stops: stops)
                    Section {
                        tripMap(leg: leg, stops: stops, progress: progress)
                            .frame(height: 240)
                            .listRowInsets(EdgeInsets())
                        statusLine(progress: progress, stops: stops, leg: leg)
                    }
                    Section("Stops") {
                        ForEach(Array(stops.enumerated()), id: \.offset) { i, stop in
                            StopTimeRow(stop: stop, isFocus: StopGrouping.normalizedName(stop.name) == StopGrouping.normalizedName(stationName),
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
        .navigationTitle(stopTime.headsign.isEmpty ? stopTime.lineName : "\(stopTime.lineName) → \(stopTime.headsign)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { ShowTicketButton() }
            ToolbarItem(placement: .topBarTrailing) {
                Button { favorites.toggle(savedLine) } label: {
                    Label(favorites.containsLine(savedLine.id) ? "Saved line" : "Save line",
                          systemImage: favorites.containsLine(savedLine.id) ? "star.fill" : "star")
                }
            }
        }
        .refreshable { await load() }
        .task {
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
            case .notStarted: return "Not departed yet"
            case .finished: return "Arrived at \(stops.last?.name ?? "")"
            case .atStop(let i): return "At \(stops[i].name)"
            case .between(let i, _): return "Between \(stops[i].name) and \(stops[i + 1].name)"
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

    private func tripMap(leg: Leg, stops: [Place], progress: TripProgress) -> some View {
        Map(initialPosition: .automatic) {
            MapPolyline(coordinates: leg.legGeometry.clCoordinates)
                .stroke(leg.lineColor, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            ForEach(Array(stops.enumerated()), id: \.offset) { _, s in
                Annotation("", coordinate: s.coordinate.clCoordinate) {
                    Circle().fill(.white).stroke(leg.lineColor, lineWidth: 2).frame(width: 8, height: 8)
                }
            }
            if let pos = TripProgress.position(progress, stops: stops) {
                Annotation(leg.lineName, coordinate: pos.clCoordinate) {
                    Image(systemName: ModeStyle.symbol(leg.mode))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(leg.lineTextColor)
                        .padding(6)
                        .background(leg.lineColor, in: Circle())
                        .accessibilityLabel("Estimated vehicle position")
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
    }

    private func load() async {
        do {
            trip = try await TransitousClient.shared.trip(id: stopTime.tripId)
            errorMessage = nil
        } catch {
            if !(error is CancellationError) && (error as? URLError)?.code != .cancelled {
                errorMessage = error.localizedDescription
            }
        }
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
                .frame(width: 52, alignment: .leading)
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
                HStack { LineBadge(line); Text("at \(line.stopName)").textCase(nil) }
            }
        }
        .navigationTitle(line.lineName)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task {
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
            departures = res.stopTimes.filter(line.matches)
            errorMessage = nil
        } catch {
            if !(error is CancellationError) && (error as? URLError)?.code != .cancelled {
                errorMessage = error.localizedDescription
            }
        }
        loaded = true
    }
}

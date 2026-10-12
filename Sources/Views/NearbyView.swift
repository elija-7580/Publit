import SwiftUI

struct NearbyView: View {
    @Environment(LocationManager.self) private var location
    @Environment(AppState.self) private var app
    @Environment(FavoritesStore.self) private var favorites
    @Environment(TripStore.self) private var trips
    @State private var searching = false
    @State private var goNow = false
    @State private var showMap = false
    @State private var groups: [StopGroup] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    /// Rounded position (~100 m) so small GPS jitter does not trigger reloads.
    private var locationKey: String {
        guard let c = location.coordinate else { return "none" }
        return String(format: "%.3f,%.3f", c.lat, c.lon)
    }

    var body: some View {
        List {
            goSection
            if location.isDenied {
                ContentUnavailableView("Location is off",
                                       systemImage: "location.slash",
                                       description: Text("Allow location access in Settings to see departures near you. Trip planning works without it."))
            } else if groups.isEmpty {
                if let errorMessage {
                    ContentUnavailableView("Departures unavailable", systemImage: "exclamationmark.triangle",
                                           description: Text(errorMessage))
                } else if isLoading || location.coordinate == nil {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else {
                    ContentUnavailableView("No departures nearby", systemImage: "tram",
                                           description: Text("No public transport stops within 1.5 km."))
                }
            }
            if !groups.isEmpty, errorMessage != nil {
                Label("Couldn't refresh. Times may be out of date.", systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            ForEach(groups) { group in
                Section {
                    ForEach(group.departures.prefix(5)) { st in
                        NavigationLink {
                            TripView(stopTime: st, stationId: group.id, stationName: group.name,
                                     stationCoordinate: group.coordinate)
                        } label: { DepartureRow(stopTime: st) }
                    }
                    NavigationLink {
                        StopDeparturesView(stopId: group.id, name: group.name, coordinate: group.coordinate)
                    } label: {
                        Text("All departures").font(.subheadline)
                    }
                } header: {
                    HStack {
                        Text(group.name)
                        Spacer()
                        if let d = group.distance { Text(Fmt.distance(meters: d)) }
                    }
                }
            }

        }
        .navigationTitle("Nearby")
        .withSettingsButton()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showMap = true } label: { Label("Station map", systemImage: "map") }
            }
        }
        .sheet(isPresented: $searching) {
            PlaceSearchView(title: "Where to?", allowCurrentLocation: false) { endpoint in go(endpoint) }
        }
        .navigationDestination(isPresented: $goNow) { GoNowView() }
        .fullScreenCover(isPresented: $showMap) { StationMapView() }
        .refreshable { await load() }
        .task(id: locationKey) {
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    /// "I have to get there now": route from the current location, leaving now.
    private func go(_ destination: Endpoint) {
        app.goNow.from = .currentLocation
        app.goNow.to = destination
        app.goNow.timeMode = .now
        goNow = true
    }

    @ViewBuilder
    private var goSection: some View {
        Section {
            Button { searching = true } label: {
                Label("Where to now?", systemImage: "magnifyingglass").foregroundStyle(.secondary)
            }
            .accessibilityLabel("Where to now? Route from your location")
            ForEach(favorites.pinned) { p in
                Button { go(.place(p)) } label: {
                    Label { Text(p.role?.title ?? p.name) + Text("  \(p.name)").foregroundStyle(.secondary) }
                        icon: { Image(systemName: p.role?.symbol ?? "mappin") }
                }
            }
            if let next = trips.upcoming().first, next.startTime.timeIntervalSinceNow < 3 * 3600 {
                NavigationLink { SavedTripView(tripId: next.id) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Next trip: \(next.toName)").font(.subheadline.weight(.semibold))
                        Text(TripStatus.at(.now, next.itinerary).headline).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func load() async {
        guard let here = location.coordinate else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            var res = try await TransitousClient.shared.departures(near: here, radius: 500, count: 80)
            if res.stopTimes.isEmpty {
                res = try await TransitousClient.shared.departures(near: here, radius: 1500, count: 80)
            }
            groups = StopGrouping.group(res.stopTimes, around: here)
            errorMessage = nil
        } catch {
            if !(error is CancellationError) && (error as? URLError)?.code != .cancelled {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct StopDeparturesView: View {
    /// Includes the other platforms of the station (feeds often split them across IDs).
    static let stationRadius = 150

    let stopId: String
    let name: String
    let coordinate: LatLon

    @Environment(FavoritesStore.self) private var favorites
    @Environment(AppState.self) private var app
    @State private var departures: [StopTime] = []
    @State private var alerts: [Alert] = []
    @State private var errorMessage: String?
    @State private var loaded = false
    @State private var lastUpdated: Date?

    private var saved: SavedPlace {
        SavedPlace(id: stopId, name: name, subtitle: nil, lat: coordinate.lat, lon: coordinate.lon, stopId: stopId)
    }

    var body: some View {
        List {
            if !alerts.isEmpty {
                Section("Alerts") {
                    ForEach(alerts, id: \.self) { a in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(a.headerText).font(.subheadline.weight(.semibold))
                            if !a.descriptionText.isEmpty {
                                Text(a.descriptionText).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            Section {
                if let errorMessage, departures.isEmpty {
                    Text(errorMessage).foregroundStyle(.secondary)
                } else if errorMessage != nil, let lastUpdated {
                    Label("Couldn't refresh. Showing times from \(Fmt.time(lastUpdated)).", systemImage: "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(.secondary)
                } else if !loaded {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if departures.isEmpty {
                    Text("No upcoming departures.").foregroundStyle(.secondary)
                }
                ForEach(departures) { st in
                    NavigationLink {
                        TripView(stopTime: st, stationId: stopId, stationName: name, stationCoordinate: coordinate)
                    } label: { DepartureRow(stopTime: st) }
                }
            }
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    app.route(to: saved)
                } label: {
                    Label("Route here", systemImage: "arrow.triangle.turn.up.right.diamond")
                }
                Button {
                    favorites.toggle(saved)
                } label: {
                    Label("Save", systemImage: favorites.contains(saved) ? "star.fill" : "star")
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

    private func load() async {
        do {
            let res = try await TransitousClient.shared.departures(stopId: stopId, count: 40, radius: Self.stationRadius)
            departures = res.stopTimes
            alerts = Array(Set(res.place?.alertsList ?? []))
            errorMessage = nil
            lastUpdated = Date()
        } catch {
            if !(error is CancellationError) && (error as? URLError)?.code != .cancelled {
                errorMessage = error.localizedDescription
            }
        }
        loaded = true
    }
}

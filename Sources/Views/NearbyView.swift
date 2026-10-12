import SwiftUI

struct NearbyView: View {
    @Environment(LocationManager.self) private var location
    @Environment(AppState.self) private var app
    @Environment(FavoritesStore.self) private var favorites
    @Environment(TripStore.self) private var trips
    @State private var searching = false
    @State private var showMap = false
    @State private var groups: [StopGroup] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    /// Where and when the board was last requested. A refined GPS fix does not restart a running request.
    @State private var loadedCenter: LatLon?
    @State private var loadedAt = Date.distantPast

    /// Reload after moving this far (metres) or after `refreshInterval` seconds.
    static let reloadDistance = 150.0
    static let refreshInterval: TimeInterval = 30

    var body: some View {
        List {
            goSection
            activeTripSection
            RecentSearchesSection(goNow: true)
            OfflineNote()
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
            if !groups.isEmpty, errorMessage != nil, !Connectivity.shared.isOffline {
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
        .navigationDestination(isPresented: Bindable(app).showGoNow) { GoNowView() }
        .fullScreenCover(isPresented: $showMap) { StationMapView() }
        .refreshable { await load(force: true) }
        .task {
            await showLastBoard()
            // One loop for the screen. Before, every ~100 m change of the first, still improving GPS
            // fixes cancelled the running request and started over, so the board took many seconds.
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    @ViewBuilder
    private var activeTripSection: some View {
        if let trip = trips.activeTrip {
            Section("Active trip") {
                NavigationLink { SavedTripView(tripId: trip.id) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(trip.toName, systemImage: "location.north.circle.fill").font(.headline)
                        Text(TripStatus.at(.now, trip.itinerary).headline).font(.subheadline).foregroundStyle(.secondary)
                        if let leg = trip.itinerary.firstTransitLeg { LineBadge(leg) }
                    }
                }
                .accessibilityIdentifier("activeTrip")
            }
        }
    }

    /// "I have to get there now": route from the current location, leaving now.
    private func go(_ destination: Endpoint) {
        app.goNow.from = .currentLocation
        app.goNow.to = destination
        app.goNow.timeMode = .now
        app.showGoNow = true
    }

    @ViewBuilder
    private var goSection: some View {
        Section {
            Button { searching = true } label: {
                Label("Where to now?", systemImage: "magnifyingglass").foregroundStyle(.secondary)
            }
            .accessibilityLabel("Where to now? Route from your location")
            .accessibilityIdentifier("whereToNow")
            ForEach(favorites.pinned) { p in
                Button { go(.place(p)) } label: {
                    Label { Text(p.role?.title ?? p.name) + Text(verbatim: "  \(p.name)").foregroundStyle(.secondary) }
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

    /// The last board (up to 30 min old, past departures removed) right away, so the screen is not
    /// empty while GPS and network start. It is replaced as soon as fresh times arrive.
    private func showLastBoard() async {
        guard groups.isEmpty, let last = await TransitousClient.shared.lastNearby(maxAge: 1800) else { return }
        let here = location.coordinate ?? last.center
        guard here.distance(to: last.center) < 400 else { return }
        groups = StopGrouping.group(StopTime.upcoming(last.response.stopTimes), around: here)
    }

    private func load(force: Bool = false) async {
        guard let here = location.coordinate else { return }
        if !force, let c = loadedCenter, here.distance(to: c) < Self.reloadDistance,
           Date().timeIntervalSince(loadedAt) < Self.refreshInterval { return }
        loadedCenter = here
        loadedAt = Date()
        isLoading = true
        defer { isLoading = false }
        do {
            var res = try await TransitousClient.shared.departures(near: here, radius: 500, count: 80)
            if res.stopTimes.isEmpty {
                res = try await TransitousClient.shared.departures(near: here, radius: 1500, count: 80)
            }
            let stopTimes = res.stopTimes
            groups = await Task.detached(priority: .userInitiated) {
                StopGrouping.group(StopTime.upcoming(stopTimes), around: here)
            }.value
            errorMessage = nil
        } catch {
            if !(error is CancellationError) && (error as? URLError)?.code != .cancelled {
                errorMessage = error.localizedDescription
                // Try again soon instead of waiting for the next regular refresh.
                loadedAt = Date().addingTimeInterval(10 - Self.refreshInterval)
            } else {
                loadedCenter = nil
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
                    ServiceAlertsView(alerts: alerts)
                }
            }
            Section {
                OfflineNote()
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
            departures = StopTime.upcoming(res.stopTimes)
            alerts = Alert.relevant((res.place?.alertsList ?? []) + res.stopTimes.flatMap { $0.place.alertsList })
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

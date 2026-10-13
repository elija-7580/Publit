import SwiftUI
import MapKit

/// State of the transit map: stations, line shapes and moving vehicles for what is on screen.
/// Heavy work (grouping, polyline decoding) runs off the main thread; the 2-second tick only
/// interpolates positions along already decoded shapes.
@MainActor
@Observable
final class TransitMapModel {
    var content = TransitMapContent()
    var stationsHidden = false
    var liveHidden = false
    var isLoadingLive = false

    var filter = ModeFilter() { didSet { if filter != oldValue { rebuildLive(); bumpStations() } } }
    var showLines = true { didSet { if showLines != oldValue { publishShapes() } } }
    var showVehicles = true { didSet { if showVehicles != oldValue { tick() } } }
    var showSharing = false { didSet { if showSharing != oldValue { Task { await loadRentals(force: true) } } } }

    @ObservationIgnored private var region: MKCoordinateRegion?
    @ObservationIgnored private var allStations: [MapStation] = []
    @ObservationIgnored private var segments: [TripSegment] = []
    @ObservationIgnored private var segmentPrecision = 5
    @ObservationIgnored private var tracks: [VehicleTrack] = []
    @ObservationIgnored private var shapes: [String: LineShape] = [:]
    @ObservationIgnored private var liveBox: (min: LatLon, max: LatLon, at: Date)?
    @ObservationIgnored private var rentalBox: (min: LatLon, max: LatLon, at: Date)?
    @ObservationIgnored private var regionTask: Task<Void, Never>?

    /// Spans (degrees latitude) above which a layer is not loaded: too much to show or download.
    static let maxStationSpan = 0.08
    static let maxLiveSpan = 0.06
    static let maxRentalSpan = 0.03
    /// Vehicles are asked for this far ahead; the first request also draws the lines.
    static let firstWindow: TimeInterval = 15 * 60
    static let refreshWindow: TimeInterval = 4 * 60
    static let refreshEvery: TimeInterval = 30
    static let tickSeconds: TimeInterval = 2

    func regionChanged(_ r: MKCoordinateRegion) {
        region = r
        regionTask?.cancel()
        regionTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            async let a: Void = self.loadStations(r)
            async let b: Void = self.loadLive(force: false)
            async let c: Void = self.loadRentals(force: false)
            _ = await (a, b, c)
            self.tick()
        }
    }

    /// Called every `tickSeconds` while the map is open.
    func tick(now: Date = .now) {
        guard let r = region else { return }
        let (lo, hi) = Self.box(r, grow: 0.1)
        let list = showVehicles && !liveHidden ? LiveMap.vehicles(tracks, at: now, min: lo, max: hi) : []
        if list.isEmpty && content.vehicles.isEmpty { return }
        content.vehicles = list
        content.vehiclesVersion += 1
    }

    func refreshIfDue() async {
        if let box = liveBox, Date().timeIntervalSince(box.at) >= Self.refreshEvery { await loadLive(force: true) }
        if showSharing, let box = rentalBox, Date().timeIntervalSince(box.at) >= 60 { await loadRentals(force: true) }
    }

    // MARK: Loading

    private func loadStations(_ r: MKCoordinateRegion) async {
        guard r.span.latitudeDelta <= Self.maxStationSpan else {
            stationsHidden = true
            if !content.stations.isEmpty { allStations = []; bumpStations() }
            return
        }
        stationsHidden = false
        // A margin around the screen: stations at the edge have all their platforms, so their pins stay put.
        let (lo, hi) = Self.box(r, grow: 0.15)
        let zoom = Self.zoom(r)
        let separate = r.span.latitudeDelta <= MapStation.poleSpan
        guard let stops = try? await TransitousClient.shared.mapStops(min: lo, max: hi, zoom: zoom) else { return }
        let grouped = await Task.detached(priority: .userInitiated) { MapStation.group(stops, separatePoles: separate) }.value
        guard !Task.isCancelled else { return }
        allStations = grouped
        bumpStations()
    }

    private func bumpStations() {
        let f = filter
        content.stations = f.isActive ? allStations.filter { $0.modes.contains { f.allows($0) } } : allStations
        content.stationsVersion += 1
    }

    private func loadLive(force: Bool) async {
        guard let r = region else { return }
        guard r.span.latitudeDelta <= Self.maxLiveSpan else {
            liveHidden = true
            tracks = []
            if !content.shapes.isEmpty { content.shapes = []; content.shapesVersion += 1 }
            return
        }
        liveHidden = false
        guard showLines || showVehicles else { return }
        let (vlo, vhi) = Self.box(r, grow: 0)
        // Small pans stay inside the last (larger) box: no new request.
        if !force, let b = liveBox, vlo.lat >= b.min.lat, vlo.lon >= b.min.lon, vhi.lat <= b.max.lat, vhi.lon <= b.max.lon,
           Date().timeIntervalSince(b.at) < Self.refreshEvery { return }
        let (lo, hi) = Self.box(r, grow: 0.25)
        let first = liveBox == nil || shapes.isEmpty
        let zoom = Self.zoom(r)
        let now = Date()
        liveBox = (lo, hi, now)
        isLoadingLive = true
        defer { isLoadingLive = false }
        guard let segs = try? await TransitousClient.shared.mapTrips(
            min: lo, max: hi, zoom: zoom, start: now.addingTimeInterval(-60),
            end: now.addingTimeInterval(first ? Self.firstWindow : Self.refreshWindow)) else { liveBox = nil; return }
        guard !Task.isCancelled else { return }
        segments = segs
        segmentPrecision = zoom >= 14 ? 5 : 4
        rebuildLive()
    }

    /// Shapes and tracks from the last answer (also when the filter changes).
    private func rebuildLive() {
        let segs = segments, f = filter, precision = segmentPrecision
        let tolerance = LiveMap.tolerance(spanMeters: (region?.span.latitudeDelta ?? 0.02) * 111_000)
        Task {
            let snap = await Task.detached(priority: .userInitiated) {
                LiveMap.build(segs, filter: f, precision: precision, tolerance: tolerance)
            }.value
            tracks = snap.tracks
            // Lines stay drawn after their vehicles have passed; a new filter starts over.
            if f != lastShapeFilter { shapes = [:]; lastShapeFilter = f }
            if shapes.count > LiveMap.maxShapes { shapes = [:] }
            var changed = false
            for s in snap.shapes where shapes[s.id] == nil { shapes[s.id] = s; changed = true }
            if changed || content.shapes.isEmpty != shapes.isEmpty { publishShapes() }
            tick()
        }
    }

    @ObservationIgnored private var lastShapeFilter = ModeFilter()

    private func publishShapes() {
        content.shapes = showLines && !liveHidden
            ? shapes.values.sorted { LiveMap.rank($0.mode) != LiveMap.rank($1.mode) ? LiveMap.rank($0.mode) < LiveMap.rank($1.mode) : $0.id < $1.id }
            : []
        content.shapesVersion += 1
    }

    private func loadRentals(force: Bool) async {
        guard showSharing, let r = region, r.span.latitudeDelta <= Self.maxRentalSpan else {
            if !content.rentals.stations.isEmpty || !content.rentals.vehicles.isEmpty {
                content.rentals = RentalsResponse(); content.rentalsVersion += 1
            }
            rentalBox = nil
            return
        }
        let (vlo, vhi) = Self.box(r, grow: 0)
        if !force, let b = rentalBox, vlo.lat >= b.min.lat, vlo.lon >= b.min.lon, vhi.lat <= b.max.lat, vhi.lon <= b.max.lon { return }
        let (lo, hi) = Self.box(r, grow: 0.25)
        rentalBox = (lo, hi, Date())
        guard let res = try? await TransitousClient.shared.rentals(min: lo, max: hi) else { rentalBox = nil; return }
        content.rentals = res
        content.rentalsVersion += 1
    }

    // MARK: Geometry

    static func box(_ r: MKCoordinateRegion, grow: Double) -> (LatLon, LatLon) {
        let dl = r.span.latitudeDelta * (0.5 + grow), dn = r.span.longitudeDelta * (0.5 + grow)
        return (LatLon(lat: r.center.latitude - dl, lon: r.center.longitude - dn),
                LatLon(lat: r.center.latitude + dl, lon: r.center.longitude + dn))
    }

    static func zoom(_ r: MKCoordinateRegion) -> Int {
        Int((log2(360 / max(r.span.longitudeDelta, 0.0001))).rounded())
    }
}

/// Interactive map of stations, the lines running around you and their vehicles moving live.
/// Tap a station for its departures, a vehicle for its trip, a bike or scooter for its provider.
struct StationMapView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(LocationManager.self) private var location
    @State private var model = TransitMapModel()
    @State private var selection: MapSelection?
    @State private var center: LatLon?
    @AppStorage("mapModes") private var storedModes = ""
    @AppStorage("mapLines") private var showLines = true
    @AppStorage("mapVehicles") private var showVehicles = true
    @AppStorage("mapSharing") private var showSharing = false

    var body: some View {
        NavigationStack {
            TransitMapView(content: model.content, initialCenter: center ?? location.coordinate,
                           glide: TransitMapModel.tickSeconds,
                           onRegion: { model.regionChanged($0) },
                           onSelect: { selection = $0 })
                .ignoresSafeArea(edges: .bottom)
                .overlay(alignment: .top) { header }
                .navigationTitle("Stations")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { layersMenu }
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                }
                .sheet(item: $selection) { sel in
                    NavigationStack { MapSelectionView(selection: sel) }
                        .presentationDetents([.medium, .large])
                        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                }
        }
        .onAppear {
            if center == nil { center = location.coordinate }
            model.filter = ModeFilter(storageValue: storedModes)
            model.showLines = showLines
            model.showVehicles = showVehicles
            model.showSharing = showSharing
        }
        .onChange(of: storedModes) { model.filter = ModeFilter(storageValue: storedModes) }
        .onChange(of: showLines) { model.showLines = showLines }
        .onChange(of: showVehicles) { model.showVehicles = showVehicles }
        .onChange(of: showSharing) { model.showSharing = showSharing }
        .task(id: scenePhase) {
            // Vehicles glide every 2 s and are fetched again every 30 s, only while the map is on screen.
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                model.tick()
                await model.refreshIfDue()
                try? await Task.sleep(for: .seconds(TransitMapModel.tickSeconds))
            }
        }
    }

    private var filterBinding: Binding<ModeFilter> {
        Binding(get: { ModeFilter(storageValue: storedModes) }, set: { storedModes = $0.storageValue })
    }

    private var header: some View {
        VStack(spacing: 6) {
            ModeFilterBar(available: ModeGroup.allCases.filter { $0 != .other }, filter: filterBinding)
                .background(.regularMaterial)
            if let hint {
                Text(hint).font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
            }
        }
    }

    private var hint: String? {
        if model.stationsHidden { return L10n.t("Zoom in to see stations") }
        if model.liveHidden && (showLines || showVehicles) { return L10n.t("Zoom in to see lines and vehicles") }
        return nil
    }

    private var layersMenu: some View {
        Menu {
            Toggle(isOn: $showLines) { Label("Lines", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
            Toggle(isOn: $showVehicles) { Label("Vehicles", systemImage: "bus.doubledecker") }
            Toggle(isOn: $showSharing) { Label("Bikes and scooters", systemImage: "bicycle") }
        } label: {
            Label("Map layers", systemImage: "square.3.layers.3d")
        }
        .accessibilityIdentifier("mapLayers")
    }
}

/// Sheet for whatever was tapped on the map.
struct MapSelectionView: View {
    let selection: MapSelection

    var body: some View {
        switch selection {
        case .station(let s):
            StopDeparturesView(stopId: s.id, name: s.name, coordinate: s.coordinate, exact: s.isPole)
        case .vehicle(let v):
            VehicleTripView(vehicle: v)
        case .rentalStation(let s, let provider):
            RentalDetailView(title: s.name, provider: provider, kinds: (s.formFactors ?? []).map(RentalKind.init),
                             available: s.numVehiclesAvailable, link: [s.rentalUriIOS, s.rentalUriWeb])
        case .rentalVehicle(let v, let provider):
            RentalDetailView(title: RentalKind(v.formFactor).title, provider: provider, kinds: [RentalKind(v.formFactor)],
                             available: nil, link: [v.rentalUriIOS, v.rentalUriWeb])
        }
    }
}

/// A shared bike or scooter (or a station of them): who runs it and a link to rent it.
struct RentalDetailView: View {
    let title: String
    let provider: String
    let kinds: [RentalKind]
    let available: Int?
    let link: [String?]

    private var url: URL? { link.compactMap { $0 }.first { !$0.isEmpty }.flatMap(URL.init(string:)) }

    var body: some View {
        List {
            Section {
                LabeledContent("Provider", value: provider)
                if !kinds.isEmpty {
                    LabeledContent("Vehicles", value: Array(Set(kinds.map(\.title))).sorted().joined(separator: ", "))
                }
                if let available { LabeledContent("Available now", value: "\(available)") }
            }
            if let url {
                Section {
                    Link(destination: url) { Label("Open in the provider's app", systemImage: "arrow.up.forward.app") }
                }
            }
            Section {
                EmptyView()
            } footer: {
                Text("Renting needs the provider's app and an account there.")
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The trip of a vehicle tapped on the map: next stops with live times, and the whole line.
struct VehicleTripView: View {
    let vehicle: LiveVehicle
    @State private var leg: Leg?
    @State private var errorMessage: String?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { ctx in
            List {
                Section {
                    HStack(spacing: 10) {
                        LineBadge(vehicle)
                        VStack(alignment: .leading, spacing: 2) {
                            if let to = leg?.directionName { Text(L10n.f("Towards %@", to)).font(.subheadline.weight(.semibold)) }
                            Text(vehicle.realTime ? L10n.t("Live position") : L10n.t("Position from the timetable"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if vehicle.delayMinutes >= 1 {
                        Text(L10n.f("%lld min late", vehicle.delayMinutes)).font(.footnote.weight(.semibold)).foregroundStyle(.orange)
                    }
                }
                if let leg {
                    let stops = leg.allStops
                    let progress = TripProgress.at(ctx.date, stops: stops)
                    let next = TripProgress.nextStopIndex(progress, count: stops.count) ?? stops.count
                    Section("Next stops") {
                        ForEach(Array(stops.enumerated()).filter { $0.offset >= next }, id: \.offset) { _, stop in
                            HStack {
                                Text(stop.name)
                                Spacer()
                                if let t = stop.arrival ?? stop.departure {
                                    Text(Fmt.time(t, tz: stop.tz)).monospacedDigit().foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if let line = lineRef(leg, next: next) {
                        Section {
                            NavigationLink { LineDetailView(line: line) } label: {
                                Label(L10n.f("Line %@: route and timetable", leg.lineName), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                            }
                        }
                    }
                } else if let errorMessage {
                    Text(errorMessage).foregroundStyle(.secondary)
                } else {
                    HStack { Spacer(); ProgressView(); Spacer() }
                }
            }
        }
        .navigationTitle(vehicle.lineName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                leg = try await TransitousClient.shared.trip(id: vehicle.id).legs.first(where: \.isTransit)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func lineRef(_ leg: Leg, next: Int) -> LineRef? {
        let stops = leg.allStops
        guard !stops.isEmpty else { return nil }
        let anchor = stops[min(next, stops.count - 1)]
        let key = leg.routeId ?? "\(leg.agencyName ?? "")|\(leg.lineName)"
        return LineRef(key: key, mode: leg.mode, routeShortName: leg.routeShortName, displayName: leg.displayName,
                       routeColor: leg.routeColor, routeTextColor: leg.routeTextColor, agencyName: leg.agencyName,
                       headsigns: leg.directionName.map { [$0] } ?? [], stopId: anchor.stopId ?? anchor.stationId,
                       stopName: anchor.name, lat: anchor.lat, lon: anchor.lon)
    }
}

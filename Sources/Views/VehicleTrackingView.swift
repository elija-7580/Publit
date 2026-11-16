import SwiftUI
import MapKit

/// "Track vehicle": one departure's vehicle on a full map with its route and the stops still to come.
/// Refreshes by itself while open; "Follow vehicle" keeps it in the middle. The line under the map says
/// where the position comes from (live stop times or the timetable), or that there is none right now.
struct VehicleTrackingView: View {
    let stopTime: StopTime
    /// Where the rider gets on (or the station the departure was opened from): bold in the list.
    let stationName: String

    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false
    @State private var leg: Leg?
    @State private var stops: [Place] = []
    @State private var shape: [LatLon] = []
    @State private var errorMessage: String?
    @State private var now = Date()
    @State private var camera: MapCameraPosition = .automatic
    @State private var follow = false

    var body: some View {
        let progress = TripProgress.at(now, stops: stops)
        let vehicle = TripProgress.position(progress, stops: stops)
        let source = VehiclePositionSource.of(progress, realTime: leg?.realTime ?? false)
        map(vehicle: vehicle)
            .safeAreaInset(edge: .bottom) { panel(progress: progress, source: source) }
            .overlay(alignment: .topTrailing) { followButton(enabled: vehicle != nil) }
            .navigationTitle(stopTime.lineName)
            .navigationBarTitleDisplayMode(.inline)
            .screenTrail("Track vehicle")
            .ticking(every: 5, now: $now)
            .onChange(of: vehicle) { _, v in
                guard follow, let v else { return }
                withAnimation(.easeInOut(duration: 0.6)) { camera = Self.centered(on: v) }
            }
            .onAppear { isVisible = true }
            .onDisappear { isVisible = false }
            .task(id: isVisible && scenePhase == .active) {
                guard isVisible, scenePhase == .active else { return }
                while !Task.isCancelled {
                    await load()
                    try? await Task.sleep(for: Energy.duration(15))
                }
            }
    }

    private func map(vehicle: LatLon?) -> some View {
        let color = leg?.lineStroke ?? Color.ink
        return Map(position: $camera) {
            if shape.count > 1 {
                MapPolyline(coordinates: shape.map(\.clCoordinate))
                    .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
            ForEach(Array(stops.enumerated()), id: \.offset) { _, s in
                Annotation("", coordinate: s.coordinate.clCoordinate, anchor: .center) {
                    Circle().fill(.white).stroke(color, lineWidth: 2).frame(width: 9, height: 9)
                }
                .annotationTitles(.hidden)
            }
            if let vehicle, let leg {
                Annotation("", coordinate: vehicle.clCoordinate, anchor: .center) {
                    Image(systemName: ModeStyle.symbol(leg.mode))
                        .font(.callout.weight(.bold))
                        .foregroundStyle(leg.lineTextColor)
                        .padding(8)
                        .background(leg.lineStroke, in: Circle())
                        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                        .shadow(radius: 2)
                        .accessibilityLabel(Text("Estimated vehicle position"))
                }
                .annotationTitles(.hidden)
            }
            UserAnnotation()
        }
        .publitMapStyle()
        .mapControls { MapUserLocationButton(); MapCompass() }
        // Moving the map by hand ends following.
        .onMapCameraChange(frequency: .onEnd) { _ in
            if camera.positionedByUser { follow = false }
        }
    }

    private func followButton(enabled: Bool) -> some View {
        Button {
            follow.toggle()
            if follow, let v = TripProgress.position(TripProgress.at(now, stops: stops), stops: stops) {
                withAnimation { camera = Self.centered(on: v) }
            }
        } label: {
            Label(follow ? L10n.t("Following vehicle") : L10n.t("Follow vehicle"),
                  systemImage: follow ? "scope" : "location.viewfinder")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 9)
                .matteSurface(in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
        .padding(10)
        .accessibilityIdentifier("followVehicle")
    }

    private func panel(progress: TripProgress, source: VehiclePositionSource) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let errorMessage, leg == nil {
                Text(verbatim: errorMessage).font(.subheadline).foregroundStyle(.secondary)
            } else if leg == nil {
                ProgressView().frame(maxWidth: .infinity)
            } else {
                Label(source.label, systemImage: source.symbol)
                    .font(.footnote)
                    .foregroundStyle(source == .liveTimes ? Color.live : Color.secondary)
                    .accessibilityIdentifier("vehiclePositionSource")
                let upcoming = Self.upcoming(progress, stops: stops)
                if upcoming.isEmpty {
                    if case .finished = progress { Text(L10n.f("Arrived at %@", stops.last?.name ?? "")).font(.subheadline) }
                } else {
                    Text("Next stops").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(Array(upcoming.prefix(4).enumerated()), id: \.offset) { _, stop in
                        HStack {
                            Text(verbatim: stop.name)
                                .font(.subheadline.weight(StopGrouping.normalizedName(stop.name) == StopGrouping.normalizedName(stationName) ? .bold : .regular))
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(verbatim: (stop.arrival ?? stop.departure).map { Fmt.time($0, tz: stop.tz) } ?? "–")
                                .font(.subheadline.monospacedDigit())
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    /// The stops the vehicle has not left yet.
    static func upcoming(_ progress: TripProgress, stops: [Place]) -> [Place] {
        guard let first = TripProgress.nextStopIndex(progress, count: stops.count), first < stops.count else { return [] }
        return Array(stops[first...])
    }

    static func centered(on point: LatLon) -> MapCameraPosition {
        .camera(MapCamera(centerCoordinate: point.clCoordinate, distance: 1500))
    }

    private func load() async {
        do {
            let fresh = try await TransitousClient.shared.trip(id: stopTime.tripId)
            guard let l = fresh.legs.first(where: \.isTransit) else { return }
            let first = leg == nil
            leg = l
            stops = l.allStops
            shape = l.legGeometry.mapPoints
            errorMessage = nil
            if first, !follow {
                camera = .rect(GuideMapFraming.rect(shape + stops.map(\.coordinate)))
            }
        } catch {
            if !(error is CancellationError) && (error as? URLError)?.code != .cancelled {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// A map rectangle around some points, with a margin.
enum GuideMapFraming {
    static func rect(_ points: [LatLon]) -> MKMapRect {
        let r = points.reduce(MKMapRect.null) { $0.union(MKMapRect(origin: MKMapPoint($1.clCoordinate), size: MKMapSize(width: 1, height: 1))) }
        guard !r.isNull else { return MKMapRect.world }
        let pad = max(max(r.width, r.height) * 0.12, 400)
        return r.insetBy(dx: -pad, dy: -pad)
    }
}

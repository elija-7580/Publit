import SwiftUI
import MapKit

/// Interactive map of stations around you. Tap a station for its departures.
struct StationMapView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(LocationManager.self) private var location
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var stations: [MapStation] = []
    @State private var selected: MapStation?
    @State private var region: MKCoordinateRegion?
    @State private var tooFar = false

    /// Above this span (degrees latitude) stops are not loaded: too many to show.
    static let maxSpan = 0.08

    var body: some View {
        NavigationStack {
            Map(position: $position, selection: $selected) {
                UserAnnotation()
                ForEach(stations) { s in
                    Annotation(s.name, coordinate: s.coordinate.clCoordinate, anchor: .center) {
                        Image(systemName: ModeStyle.symbol(s.mainMode))
                            .font(.system(size: s.isMajor ? 13 : 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(s.isMajor ? 6 : 4)
                            .background(ModeStyle.color(s.mainMode), in: Circle())
                            .overlay(Circle().stroke(.white, lineWidth: 1.5))
                            .accessibilityLabel(s.name)
                    }
                    .tag(s)
                    .annotationTitles(s.isMajor ? .visible : .hidden)
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
            .onMapCameraChange(frequency: .onEnd) { ctx in region = ctx.region }
            .task(id: region.map { "\(($0.center.latitude * 500).rounded()),\(($0.center.longitude * 500).rounded()),\(($0.span.latitudeDelta * 200).rounded())" }) {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, let region else { return }
                await load(region)
            }
            .overlay(alignment: .top) {
                if tooFar {
                    Text("Zoom in to see stations").font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(.regularMaterial, in: Capsule()).padding(.top, 8)
                }
            }
            .navigationTitle("Stations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(item: $selected) { s in
                NavigationStack {
                    StopDeparturesView(stopId: s.id, name: s.name, coordinate: s.coordinate)
                }
                .presentationDetents([.medium, .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            }
        }
    }

    private func load(_ r: MKCoordinateRegion) async {
        guard r.span.latitudeDelta <= Self.maxSpan else { tooFar = true; return }
        tooFar = false
        let min = LatLon(lat: r.center.latitude - r.span.latitudeDelta / 2, lon: r.center.longitude - r.span.longitudeDelta / 2)
        let max = LatLon(lat: r.center.latitude + r.span.latitudeDelta / 2, lon: r.center.longitude + r.span.longitudeDelta / 2)
        let zoom = Int((log2(360 / r.span.longitudeDelta)).rounded())
        guard let stops = try? await TransitousClient.shared.mapStops(min: min, max: max, zoom: zoom) else { return }
        guard !Task.isCancelled else { return }
        stations = MapStation.group(stops)
    }
}


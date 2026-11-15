import SwiftUI
import MapKit

/// Nearby on iPhone: the map is the screen, the departure board a panel over it (like the live trip).
/// It shows where you are and the board's stations, named, the nearest with the yellow dot. It starts
/// framed on you and those stations and can then be moved freely; the location button brings it back.
/// A tap on a station opens its departures. Settings → Nearby → "Map" turns it off (list only).
struct NearbyMap: View {
    static let defaultsKey = "nearbyMap"
    /// The panel down: the search field and a little of the board.
    static let peek: CGFloat = 132
    /// The panel up: a strip of the map stays visible above it.
    static let topGap: CGFloat = 56

    let here: LatLon?
    let groups: [StopGroup]
    var onOpenStation: (StopGroup) -> Void

    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    /// Framed on you and the stations once; after that the map is yours to move.
    @State private var framed = false

    /// The board's first stations; more only crowd the map.
    private var shown: [StopGroup] { Array(groups.prefix(8)) }

    var body: some View {
        Map(position: $camera) {
            UserAnnotation()
            ForEach(shown) { g in
                Annotation(g.name, coordinate: g.coordinate.clCoordinate, anchor: .center) {
                    Button { onOpenStation(g) } label: {
                        ZStack {
                            Circle().fill(Color.ink).frame(width: 18, height: 18)
                                .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                            if g.id == groups.first?.id { SignatureDot(size: 7) }
                        }
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: g.name))
                    .accessibilityIdentifier("nearbyMapStation")
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls { MapUserLocationButton(); MapCompass() }
        .onChange(of: groups.first?.id, initial: true) { frame() }
        .accessibilityIdentifier("nearbyMap")
    }

    private func frame() {
        guard !framed, let here, !shown.isEmpty else { return }
        framed = true
        withAnimation(.easeInOut(duration: 0.4)) {
            camera = .region(Self.region(here: here, stations: Array(shown.prefix(6)).map(\.coordinate)))
        }
    }

    /// You in the middle with the nearest stations around; never closer than about 500 m across.
    static func region(here: LatLon, stations: [LatLon]) -> MKCoordinateRegion {
        let far = stations.map { here.distance(to: $0) }.max() ?? 0
        let radius = max(250, far * 1.25)
        return MKCoordinateRegion(center: here.clCoordinate, latitudinalMeters: radius * 2, longitudinalMeters: radius * 2)
    }
}

import SwiftUI
import MapKit

/// Nearby on iPhone: the map as the picture at the top of the board (`MapHero`).
/// It shows where you are and the board's stations, named, the nearest with the yellow dot, and the
/// walk there (Apple Maps' walking route, with an arrow for the way to go). It is framed on you and
/// those stations. Settings → Nearby → "Map" turns it off (list only).
struct NearbyMap: View {
    static let defaultsKey = "nearbyMap"
    /// The panel down: the search field and a little of the board.
    static let peek: CGFloat = 132
    /// The panel up: a strip of the map stays visible above it.
    static let topGap: CGFloat = 56

    let here: LatLon?
    let groups: [StopGroup]
    var onOpenStation: (StopGroup) -> Void
    /// The picture at the top of Nearby: nothing to tap or steer, no controls.
    var preview = false

    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    /// Framed on you and the stations once; after that the map is yours to move.
    @State private var framed = false
    /// The walk to the nearest station.
    @State private var walk = WalkDetour()

    /// Closer than this the station is right here: no way to show.
    static let walkFrom = 40.0

    /// The station to walk to: the nearest, when it is not right where you stand.
    private var target: StopGroup? {
        guard let g = groups.first, let here, here.distance(to: g.coordinate) >= Self.walkFrom else { return nil }
        return g
    }

    /// Asked again when the nearest station changes or you have moved about 30 m.
    private var walkKey: String {
        guard let target, let here else { return "" }
        return "\(target.id)|\((here.lat * 3000).rounded())|\((here.lon * 3000).rounded())"
    }

    /// The board's first stations; more only crowd the map.
    private var shown: [StopGroup] { Array(groups.prefix(8)) }

    var body: some View {
        Map(position: $camera) {
            UserAnnotation()
            if let target, let route = walk.route, route.to == target.coordinate, route.points.count > 1 {
                MapPolyline(coordinates: route.points.map(\.clCoordinate))
                    .stroke(Color.routeAhead, style: .leg(false, width: 6))
                if let arrow = PathGeometry.arrow(on: route.points) {
                    Annotation("", coordinate: arrow.point.clCoordinate, anchor: .center) {
                        Image(systemName: "arrowtriangle.up.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(Color.routeAhead, in: Circle())
                            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                            // The picture does not turn (north up): the bearing is the arrow's angle.
                            .rotationEffect(.degrees(arrow.bearing))
                            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                            .accessibilityHidden(true)
                    }
                }
            }
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
        .mapControlVisibility(preview ? .hidden : .automatic)
        .onChange(of: groups.first?.id, initial: true) { frame() }
        .task(id: walkKey) {
            guard !walkKey.isEmpty else { return }
            await walk.update(from: here, to: target?.coordinate)
        }
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

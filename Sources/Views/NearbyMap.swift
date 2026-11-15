import SwiftUI
import MapKit

/// Nearby on iPhone: the map as the picture at the top of the board (`MapHero`).
/// It shows where you are, with an arrow the way you face, and the board's stations, named, the
/// nearest with the yellow dot. It is framed on you and those stations. Settings → Nearby → "Map" turns it off (list only).
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
    /// Which way the iPhone points (degrees from north), when the compass runs.
    var heading: Double? = nil

    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    /// Framed on you and the stations once; after that the map is yours to move.
    @State private var framed = false
    /// The board's first stations; more only crowd the map.
    private var shown: [StopGroup] { Array(groups.prefix(8)) }

    var body: some View {
        Map(position: $camera) {
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
            // On top of the stations. Your position with an arrow the way you hold the iPhone (the picture is north up and
            // does not turn, so the compass heading is the arrow's angle). Without a compass: the dot.
            if let here {
                Annotation("", coordinate: here.clCoordinate, anchor: .center) {
                    HeadingDot(heading: heading)
                }
            } else {
                UserAnnotation()
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls { MapUserLocationButton(); MapCompass() }
        .mapControlVisibility(preview ? .hidden : .automatic)
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

/// Your position on the Nearby map: the blue dot, with an arrow the way you face when the compass runs.
struct HeadingDot: View {
    let heading: Double?

    var body: some View {
        ZStack {
            Circle().fill(Color.blue.opacity(0.18)).frame(width: 44, height: 44)
            Circle().fill(Color.blue).frame(width: 26, height: 26)
                .overlay(Circle().strokeBorder(.white, lineWidth: 3))
            if let heading {
                Image(systemName: "location.north.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(heading))
            }
        }
        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
        .accessibilityHidden(true)
    }
}

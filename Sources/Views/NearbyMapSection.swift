import SwiftUI
import MapKit

/// Nearby: a small map above the departure board, for orientation. It shows where you are and where the
/// listed stations are (the nearest with the yellow dot), framed so all of them fit. A tap on the map opens
/// the full station map; a tap on a station opens its departures. Settings → Nearby → "Map" turns it off.
struct NearbyMapSection: View {
    static let defaultsKey = "nearbyMap"

    let here: LatLon
    let groups: [StopGroup]
    var onOpenMap: () -> Void
    var onOpenStation: (StopGroup) -> Void

    /// The board's first stations; more than that only crowds a small map.
    private var shown: [StopGroup] { Array(groups.prefix(6)) }

    var body: some View {
        Map(position: .constant(.region(Self.region(here: here, stations: shown.map(\.coordinate)))), interactionModes: []) {
            UserAnnotation()
            ForEach(shown) { g in
                Annotation(g.name, coordinate: g.coordinate.clCoordinate, anchor: .center) {
                    Button { onOpenStation(g) } label: {
                        ZStack {
                            Circle().fill(Color.ink).frame(width: 16, height: 16)
                                .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                            if g.id == groups.first?.id { SignatureDot(size: 6) }
                        }
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: g.name))
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .frame(height: 180)
        .overlay(alignment: .bottomTrailing) {
            Button(action: onOpenMap) {
                Label("Station map", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .matteSurface(in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(10)
            .accessibilityIdentifier("nearbyMapOpen")
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpenMap)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nearbyMap")
    }

    /// You and the stations, with some room around them; never closer than about 400 m across.
    static func region(here: LatLon, stations: [LatLon]) -> MKCoordinateRegion {
        let pts = [here] + stations
        let minLat = pts.map(\.lat).min()!, maxLat = pts.map(\.lat).max()!
        let minLon = pts.map(\.lon).min()!, maxLon = pts.map(\.lon).max()!
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let minSpan = 400 / 111_200.0
        let span = MKCoordinateSpan(latitudeDelta: max(minSpan, (maxLat - minLat) * 1.5),
                                    longitudeDelta: max(minSpan / max(0.2, cos(center.latitude * .pi / 180)), (maxLon - minLon) * 1.5))
        return MKCoordinateRegion(center: center, span: span)
    }
}

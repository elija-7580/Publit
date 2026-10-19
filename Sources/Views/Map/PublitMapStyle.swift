import MapKit
import SwiftUI

/// The map look chosen in Settings → Map (the same keys as the station map's layers sheet),
/// for the SwiftUI maps on routes, trips and lines.
private struct PublitMapStyle: ViewModifier {
    @AppStorage("mapBase") private var storedBase = MapBase.defaultValue
    @AppStorage("map3D") private var realistic3D = false
    @AppStorage("mapPOI") private var pointsOfInterest = true
    @AppStorage("mapTraffic") private var traffic = false

    func body(content: Content) -> some View {
        content.mapStyle(Self.style(MapLook(base: MapBase(storageValue: storedBase), realistic3D: realistic3D,
                                            pointsOfInterest: pointsOfInterest, traffic: traffic)))
    }

    /// Public transport POIs stay off: the stops on these maps are Publit's own.
    static func style(_ look: MapLook) -> MapStyle {
        let elevation: MapStyle.Elevation = look.realistic3D ? .realistic : .flat
        let poi: PointOfInterestCategories = look.showsPointsOfInterest ? .excluding([.publicTransport]) : .excludingAll
        switch look.base {
        case .standard:
            return .standard(elevation: elevation, emphasis: .automatic, pointsOfInterest: poi, showsTraffic: look.showsTraffic)
        case .muted:
            return .standard(elevation: elevation, emphasis: .muted, pointsOfInterest: poi, showsTraffic: look.showsTraffic)
        case .satellite:
            return .hybrid(elevation: elevation, pointsOfInterest: poi, showsTraffic: look.showsTraffic)
        case .imagery:
            return .imagery(elevation: elevation)
        }
    }
}

extension View {
    func publitMapStyle() -> some View { modifier(PublitMapStyle()) }
}

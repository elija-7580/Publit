import MapKit
import SwiftUI

/// The map of a trip, like in Apple Maps: rides in their line colour, walks dotted, you as the blue dot.
/// Opened from a leg it shows exactly that leg; opened from the overview it shows the whole trip.
struct WatchTripMapView: View {
    let itinerary: Itinerary
    let page: WatchTripPage
    @State private var position: MapCameraPosition
    @State private var wholeTrip: Bool

    init(itinerary: Itinerary, page: WatchTripPage) {
        self.itinerary = itinerary
        self.page = page
        _position = State(initialValue: Self.camera(itinerary, page: page))
        _wholeTrip = State(initialValue: page == .overview)
    }

    private struct Stop: Identifiable {
        let id: String
        let name: String
        let coordinate: CLLocationCoordinate2D
        let color: Color
    }

    /// The legs on the map.
    private var shown: [(index: Int, leg: Leg)] {
        if !wholeTrip, case .leg(let i) = page, itinerary.legs.indices.contains(i) { return [(i, itinerary.legs[i])] }
        return Array(itinerary.legs.enumerated()).map { (index: $0.offset, leg: $0.element) }
    }

    private var stops: [Stop] {
        var out: [Stop] = []
        func add(_ place: Place, _ color: Color, _ tag: String) {
            let c = CLLocationCoordinate2D(latitude: place.lat, longitude: place.lon)
            guard place.coordinate.isValidCoordinate,
                  !out.contains(where: { $0.coordinate.latitude == c.latitude && $0.coordinate.longitude == c.longitude }) else { return }
            out.append(Stop(id: "\(tag)-\(out.count)", name: place.name, coordinate: c, color: color))
        }
        for item in shown {
            if item.leg.isTransit || shown.count == 1 || item.index == 0 { add(item.leg.from, item.leg.isTransit ? item.leg.lineStroke : Color.appAccent, "from") }
            if item.leg.isTransit || shown.count == 1 || item.index == itinerary.legs.count - 1 { add(item.leg.to, item.leg.isTransit ? item.leg.lineStroke : Color.appAccent, "to") }
        }
        return out
    }

    var body: some View {
        Map(position: $position) {
            UserAnnotation()
            ForEach(shown, id: \.index) { item in
                let line = path(of: item.leg)
                if line.count > 1 {
                    if item.leg.isTransit {
                        MapPolyline(coordinates: line).stroke(item.leg.lineStroke, lineWidth: 5)
                    } else {
                        MapPolyline(coordinates: line).stroke(Color.appAccent, style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [1, 7]))
                    }
                }
            }
            ForEach(stops) { stop in
                Annotation(stop.name, coordinate: stop.coordinate, anchor: .center) {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().strokeBorder(stop.color, lineWidth: 3))
                }
                .annotationTitles(shown.count == 1 ? .automatic : .hidden)
            }
        }
        .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
        .navigationTitle(title)
        .overlay(alignment: .bottom) {
            if let notice = CoverageGuide.notices(for: itinerary).first {
                Label {
                    Text("Not reliable here").font(.caption2.weight(.bold))
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.delay)
                }
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(.black.opacity(0.7), in: Capsule())
                .accessibilityValue(Text(verbatim: notice.area.summary))
            }
        }
        .toolbar {
            if case .leg = page {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        wholeTrip.toggle()
                        withAnimation { position = Self.camera(itinerary, page: wholeTrip ? .overview : page) }
                    } label: {
                        Image(systemName: wholeTrip ? "scope" : "arrow.up.left.and.arrow.down.right")
                    }
                    .accessibilityLabel(Text("Trip overview"))
                }
            }
        }
    }

    private var title: Text {
        if !wholeTrip, let leg = WatchTripPages.leg(page, in: itinerary) {
            return leg.isTransit ? Text(verbatim: leg.lineName) : Text(L10n.f("Walk %@", Fmt.duration(seconds: leg.duration)))
        }
        return Text("Map")
    }

    private func path(of leg: Leg) -> [CLLocationCoordinate2D] {
        (wholeTrip || shown.count > 1 ? leg.overviewPath : leg.mapPath)
            .filter(\.isValidCoordinate)
            .map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
    }

    /// The part of the map that fits the leg (or the trip) with a little room around.
    private static func camera(_ it: Itinerary, page: WatchTripPage) -> MapCameraPosition {
        let points: [LatLon]
        if let leg = WatchTripPages.leg(page, in: it) { points = WatchMapFit.points(of: leg) } else { points = WatchMapFit.points(of: it) }
        guard let box = WatchMapFit.box(points) else { return .automatic }
        return .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: box.center.lat, longitude: box.center.lon),
            span: MKCoordinateSpan(latitudeDelta: box.latitudeDelta, longitudeDelta: box.longitudeDelta)))
    }
}

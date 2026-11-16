import SwiftUI
import MapKit

/// "Choose on map" from the From and To fields: a pin in the middle of the map. Move the map, or tap
/// a spot, to put the pin there; "Confirm location" fills the field with that point (and the street,
/// once it is known). Nothing else in the planner changes.
struct ChooseOnMapView: View {
    /// Where the map opens: where you are (else wherever MapKit starts).
    let start: LatLon?
    let onConfirm: (SavedPlace) -> Void

    @State private var camera: MapCameraPosition
    @State private var center: LatLon?
    @State private var address: String?
    @State private var lookingUp = false
    /// The visible height in metres, kept when a tap moves the pin.
    @State private var span: CLLocationDistance = 600
    @State private var regionCenter: CLLocationCoordinate2D?
    @State private var geocoder = CLGeocoder()

    init(start: LatLon?, onConfirm: @escaping (SavedPlace) -> Void) {
        self.start = start
        self.onConfirm = onConfirm
        if let start, start.isValidCoordinate {
            _camera = State(initialValue: .region(MKCoordinateRegion(center: start.clCoordinate, latitudinalMeters: 600, longitudinalMeters: 600)))
            _center = State(initialValue: start)
        } else {
            _camera = State(initialValue: .userLocation(fallback: .automatic))
        }
    }

    var body: some View {
        GeometryReader { geo in
            // The pin stands in the middle of the map's own frame; the point used is the one under its
            // tip, read through the map (not the region's centre, which safe areas can move).
            let tip = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            MapReader { proxy in
                Map(position: $camera) {
                    UserAnnotation()
                }
                .mapStyle(.standard)
                .mapControls { MapUserLocationButton(); MapCompass() }
                .onMapCameraChange(frequency: .onEnd) { context in
                    regionCenter = context.region.center
                    span = max(150, context.region.span.latitudeDelta * 111_000)
                    guard let c = proxy.convert(tip, from: .local) else { return }
                    let point = LatLon(lat: c.latitude, lon: c.longitude)
                    guard point.isValidCoordinate else { return }
                    center = point
                    lookUp(point)
                }
                // A tap puts the pin there: the map moves so the tapped spot lies under the pin.
                .onTapGesture { screenPoint in
                    guard let tapped = proxy.convert(screenPoint, from: .local),
                          let underPin = proxy.convert(tip, from: .local),
                          let regionCenter else { return }
                    let target = CLLocationCoordinate2D(latitude: regionCenter.latitude + tapped.latitude - underPin.latitude,
                                                        longitude: regionCenter.longitude + tapped.longitude - underPin.longitude)
                    withAnimation(.easeInOut(duration: 0.3)) {
                        camera = .region(MKCoordinateRegion(center: target, latitudinalMeters: span, longitudinalMeters: span))
                    }
                }
                .overlay { CenterPin().allowsHitTesting(false) }
            }
        }
        .safeAreaInset(edge: .bottom) { confirmBar }
        .navigationTitle("Choose on map")
        .navigationBarTitleDisplayMode(.inline)
        .screenTrail("Choose on map")
        .onDisappear { geocoder.cancelGeocode() }
    }

    private var confirmBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "mappin.and.ellipse").foregroundStyle(.secondary)
                if let address {
                    Text(verbatim: address).font(.subheadline.weight(.semibold)).lineLimit(2)
                } else {
                    Group {
                        if lookingUp { Text("Finding the address…") } else { Text("Move the map or tap to place the pin") }
                    }
                    .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            Button {
                guard let center else { return }
                onConfirm(Self.place(at: center, address: address))
            } label: {
                Text("Confirm location").frame(maxWidth: .infinity)
            }
            .buttonStyle(InkButtonStyle())
            .disabled(center == nil)
            .accessibilityIdentifier("confirmMapLocation")
        }
        .padding(16)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    /// The street and number under the pin, to show and to name the place.
    private func lookUp(_ point: LatLon) {
        geocoder.cancelGeocode()
        address = nil
        lookingUp = true
        geocoder.reverseGeocodeLocation(CLLocation(latitude: point.lat, longitude: point.lon)) { marks, _ in
            DispatchQueue.main.async {
                // A later move wins: only the answer for the point the pin is on now counts.
                guard center == point else { return }
                lookingUp = false
                guard let mark = marks?.first else { return }
                let street = [mark.thoroughfare, mark.subThoroughfare].compactMap { $0 }.joined(separator: " ")
                address = street.isEmpty ? (mark.name ?? mark.locality) : street
            }
        }
    }

    /// The pinned point as a place: named after its street when known, else "Dropped pin".
    static func place(at point: LatLon, address: String?) -> SavedPlace {
        SavedPlace(match: .picked(name: address ?? L10n.t("Dropped pin"), at: point))
    }
}

/// The pin in the middle of the map, its tip on the point that will be used.
private struct CenterPin: View {
    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: "mappin")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Color.danger)
                .shadow(radius: 2)
            Circle().fill(.black.opacity(0.35)).frame(width: 6, height: 3)
        }
        // The tip, not the middle of the symbol, sits on the centre of the map.
        .offset(y: -18)
        .accessibilityHidden(true)
    }
}

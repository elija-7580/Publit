import SwiftUI
import MapKit

/// "Choose on map" from the From and To fields: a pin stands in the middle of the map, like in Apple
/// Maps; move the map under it. The map behaves like any map (pinch, double-tap to zoom in, two-finger
/// tap to zoom out, rotate): no own tap gesture on it, which used to swallow double-taps and made the
/// map jump (feedback 2026-11-17). The pin lifts while the map moves and sets down where it stops;
/// "Confirm location" fills the field with that point (and the street, once it is known).
/// Nothing else in the planner changes.
struct ChooseOnMapView: View {
    /// Where the map opens: where you are (else wherever MapKit starts).
    let start: LatLon?
    let onConfirm: (SavedPlace) -> Void

    @State private var camera: MapCameraPosition
    @State private var center: LatLon?
    @State private var address: String?
    @State private var lookingUp = false
    /// The map is being moved: the pin is lifted.
    @State private var moving = false
    @State private var geocoder = CLGeocoder()

    init(start: LatLon?, onConfirm: @escaping (SavedPlace) -> Void) {
        self.start = start
        self.onConfirm = onConfirm
        if let start, start.isValidCoordinate {
            _camera = State(initialValue: .camera(MapCamera(centerCoordinate: start.clCoordinate, distance: 900)))
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
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
                .mapControls { MapUserLocationButton(); MapCompass(); MapScaleView() }
                .onMapCameraChange(frequency: .continuous) { _ in
                    guard !moving else { return }
                    address = nil
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { moving = true }
                }
                .onMapCameraChange(frequency: .onEnd) { _ in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { moving = false }
                    guard let c = proxy.convert(tip, from: .local) else { return }
                    let point = LatLon(lat: c.latitude, lon: c.longitude)
                    guard point.isValidCoordinate, point != center || address == nil else { return }
                    center = point
                    lookUp(point)
                }
                .overlay { CenterPin(lifted: moving).allowsHitTesting(false) }
                .sensoryFeedback(.impact(weight: .light), trigger: moving) { was, now in was && !now }
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
                        if lookingUp || moving { Text("Finding the address…") } else { Text("Move the map to place the pin") }
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

/// The pin in the middle of the map, in Publit's look: an ink head with the yellow dot on a short
/// stem, its tip on the point that will be used. While the map moves it lifts, and its shadow on
/// the ground grows and fades, so it is clear where it will set down.
private struct CenterPin: View {
    var lifted = false

    private static let head: CGFloat = 34
    private static let stem: CGFloat = 16

    var body: some View {
        ZStack {
            // The shadow on the ground, right under the tip.
            Ellipse()
                .fill(.black.opacity(lifted ? 0.18 : 0.32))
                .frame(width: lifted ? 18 : 10, height: lifted ? 7 : 4)
                .blur(radius: lifted ? 2 : 0.5)
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(Color.ink)
                    Circle().strokeBorder(.white, lineWidth: 3)
                    SignatureDot(size: 12)
                }
                .frame(width: Self.head, height: Self.head)
                .shadow(color: .black.opacity(0.3), radius: lifted ? 6 : 3, y: lifted ? 4 : 2)
                Capsule()
                    .fill(Color.ink)
                    .frame(width: 3, height: Self.stem)
                    .overlay(Capsule().strokeBorder(.white.opacity(0.7), lineWidth: 0.5))
            }
            // The tip, not the middle, sits on the centre of the map; lifted it floats above it.
            .offset(y: -(Self.head + Self.stem) / 2 - (lifted ? 12 : 0))
        }
        .accessibilityHidden(true)
    }
}

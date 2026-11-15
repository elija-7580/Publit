import SwiftUI
import MapKit

/// Your position on every map, the same everywhere: the blue dot with a white arrow the way you
/// hold the iPhone (from the compass), like the arrow in the live trip. Without a compass: the dot.
struct HeadingDot: View {
    /// Degrees to turn the arrow on screen (compass heading minus the map's own turn); nil hides it.
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

/// `HeadingDot` on a SwiftUI map. Put it last, so it sits on top of stations and routes.
struct YouAreHere: MapContent {
    let here: LatLon?
    let heading: Double?
    /// Which way the map itself is turned (its camera heading): the arrow keeps pointing the real way.
    var mapHeading: Double = 0

    var body: some MapContent {
        if let here {
            Annotation("", coordinate: here.clCoordinate, anchor: .center) {
                HeadingDot(heading: heading.map { $0 - mapHeading })
            }
            .annotationTitles(.hidden)
        } else {
            UserAnnotation()
        }
    }
}

/// The compass runs while this screen is on screen and the app is in front (it costs battery).
/// Each screen has its own name, so one closing does not turn it off for another.
private struct CompassWhileShown: ViewModifier {
    let user: String
    @Environment(LocationManager.self) private var location
    @Environment(\.scenePhase) private var scenePhase
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .onAppear { shown = true }
            .onDisappear { shown = false }
            .onChange(of: shown && scenePhase == .active, initial: true) { _, on in location.setHeading(on, for: user) }
    }
}

extension View {
    /// See `CompassWhileShown`.
    func compassWhileShown(_ user: String) -> some View { modifier(CompassWhileShown(user: user)) }
}

/// `HeadingDot` for the UIKit station map (`TransitMapView`): your position with the arrow, turned
/// against the map's own rotation.
final class UserHeadingView: MKAnnotationView {
    static let reuseId = "UserHeading"
    private let halo = CALayer()
    private let dot = CALayer()
    private let arrow = CAShapeLayer()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        canShowCallout = false
        displayPriority = .required
        zPriority = .max
        collisionMode = .none
        halo.frame = bounds
        halo.cornerRadius = 22
        halo.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.18).cgColor
        dot.frame = CGRect(x: 9, y: 9, width: 26, height: 26)
        dot.cornerRadius = 13
        dot.backgroundColor = UIColor.systemBlue.cgColor
        dot.borderColor = UIColor.white.cgColor
        dot.borderWidth = 3
        dot.shadowColor = UIColor.black.cgColor
        dot.shadowOpacity = 0.25
        dot.shadowRadius = 2
        dot.shadowOffset = CGSize(width: 0, height: 1)
        arrow.frame = bounds
        let p = UIBezierPath()
        // Like SF Symbols' "location.north.fill", around the centre.
        p.move(to: CGPoint(x: 22, y: 16))
        p.addLine(to: CGPoint(x: 27, y: 27.5))
        p.addLine(to: CGPoint(x: 22, y: 25))
        p.addLine(to: CGPoint(x: 17, y: 27.5))
        p.close()
        arrow.path = p.cgPath
        arrow.fillColor = UIColor.white.cgColor
        arrow.isHidden = true
        layer.addSublayer(halo)
        layer.addSublayer(dot)
        layer.addSublayer(arrow)
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(heading: Double?, mapHeading: Double) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let heading, heading.isFinite {
            arrow.isHidden = false
            arrow.setAffineTransform(CGAffineTransform(rotationAngle: (heading - mapHeading) * .pi / 180))
        } else {
            arrow.isHidden = true
        }
        CATransaction.commit()
    }
}

import SwiftUI
import MapKit

/// Your position on every map, the same everywhere: the blue dot with a beam fanning out the way
/// you face (from the compass), like Apple Maps' own position. Without a compass: the dot alone.
/// Feedback 2026-11-17: the beam of the old live trip (Apple's position, until build 79) read much
/// better than build 80's white arrow inside the dot.
struct HeadingDot: View {
    /// Degrees to turn the beam on screen (compass heading minus the map's own turn); nil hides it.
    let heading: Double?

    var body: some View {
        ZStack {
            if let heading {
                HeadingBeam()
                    .fill(RadialGradient(colors: [Color.blue.opacity(0.55), Color.blue.opacity(0)],
                                         center: .center, startRadius: 6, endRadius: 46))
                    .frame(width: 92, height: 92)
                    .rotationEffect(.degrees(heading))
                    .animation(.easeOut(duration: 0.25), value: heading)
            } else {
                Circle().fill(Color.blue.opacity(0.16)).frame(width: 44, height: 44)
            }
            Circle().fill(Color.blue).frame(width: 20, height: 20)
                .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
        }
        .frame(width: 92, height: 92)
        .accessibilityHidden(true)
    }
}

/// The beam: a wedge of about 70° from the middle upwards (north before turning).
private struct HeadingBeam: Shape {
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var p = Path()
        p.move(to: c)
        p.addArc(center: c, radius: rect.width / 2, startAngle: .degrees(-90 - 35), endAngle: .degrees(-90 + 35), clockwise: false)
        p.closeSubpath()
        return p
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

/// `HeadingDot` for the UIKit station map (`TransitMapView`): your position with the beam the way
/// you face, turned against the map's own rotation.
final class UserHeadingView: MKAnnotationView {
    static let reuseId = "UserHeading"
    private static let size: CGFloat = 92
    private let halo = CALayer()
    private let beam = CAGradientLayer()
    private let beamMask = CAShapeLayer()
    private let dot = CALayer()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        let side = Self.size
        frame = CGRect(x: 0, y: 0, width: side, height: side)
        canShowCallout = false
        displayPriority = .required
        zPriority = .max
        collisionMode = .none
        halo.frame = CGRect(x: side / 2 - 22, y: side / 2 - 22, width: 44, height: 44)
        halo.cornerRadius = 22
        halo.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.16).cgColor
        // The beam: a radial fade in a 70° wedge pointing up (north before turning).
        beam.frame = bounds
        beam.type = .radial
        beam.colors = [UIColor.systemBlue.withAlphaComponent(0.55).cgColor, UIColor.systemBlue.withAlphaComponent(0).cgColor]
        beam.startPoint = CGPoint(x: 0.5, y: 0.5)
        beam.endPoint = CGPoint(x: 1, y: 1)
        let c = CGPoint(x: side / 2, y: side / 2)
        let p = UIBezierPath()
        p.move(to: c)
        p.addArc(withCenter: c, radius: side / 2, startAngle: (-90 - 35) * .pi / 180, endAngle: (-90 + 35) * .pi / 180, clockwise: true)
        p.close()
        beamMask.path = p.cgPath
        beam.mask = beamMask
        beam.isHidden = true
        dot.frame = CGRect(x: side / 2 - 10, y: side / 2 - 10, width: 20, height: 20)
        dot.cornerRadius = 10
        dot.backgroundColor = UIColor.systemBlue.cgColor
        dot.borderColor = UIColor.white.cgColor
        dot.borderWidth = 3
        dot.shadowColor = UIColor.black.cgColor
        dot.shadowOpacity = 0.3
        dot.shadowRadius = 2
        dot.shadowOffset = CGSize(width: 0, height: 1)
        layer.addSublayer(halo)
        layer.addSublayer(beam)
        layer.addSublayer(dot)
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(heading: Double?, mapHeading: Double) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let heading, heading.isFinite {
            beam.isHidden = false
            halo.isHidden = true
            beam.setAffineTransform(CGAffineTransform(rotationAngle: (heading - mapHeading) * .pi / 180))
        } else {
            beam.isHidden = true
            halo.isHidden = false
        }
        CATransaction.commit()
    }
}

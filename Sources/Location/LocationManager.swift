import CoreLocation
import Observation

@MainActor
@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate {
    /// Every fix (about every 50 m). Read it in tasks and actions, not in a view body:
    /// a body that reads it is redrawn on every fix.
    private(set) var location: CLLocation?
    /// Changes once, when the first fix arrives. Safe to read in a view body.
    private(set) var hasFix = false
    private(set) var status: CLAuthorizationStatus

    private let manager: CLLocationManager

    override init() {
        let m = CLLocationManager()
        manager = m
        status = m.authorizationStatus
        super.init()
        m.delegate = self
        m.desiredAccuracy = kCLLocationAccuracyHundredMeters
        m.distanceFilter = 50
        useRecentFix(m.location)
    }

    /// The system's last fix, when it is recent and good enough: routes and departures can start
    /// right away instead of waiting a few seconds for GPS.
    private func useRecentFix(_ fix: CLLocation?) {
        guard location == nil, let fix, fix.horizontalAccuracy >= 0, fix.horizontalAccuracy <= 1000,
              Date().timeIntervalSince(fix.timestamp) < 5 * 60 else { return }
        location = fix
        if !hasFix { hasFix = true }
    }

    var coordinate: LatLon? {
        location.map { LatLon(lat: $0.coordinate.latitude, lon: $0.coordinate.longitude) }
    }

    var isDenied: Bool { status == .denied || status == .restricted }

    func start() {
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if !isDenied {
            useRecentFix(manager.location)
            manager.startUpdatingLocation()
        }
    }

    /// Walking directions need a fix every few metres; elsewhere every 50 m is plenty.
    func setPrecise(_ precise: Bool) {
        manager.desiredAccuracy = precise ? kCLLocationAccuracyBest : kCLLocationAccuracyHundredMeters
        manager.distanceFilter = precise ? 5 : 50
    }

    /// Metres of uncertainty of the last fix (large when unknown).
    var accuracy: Double { location.map { $0.horizontalAccuracy >= 0 ? $0.horizontalAccuracy : 1000 } ?? 1000 }

    /// In the background nothing shows the location: GPS off until the app is open again.
    func pause() {
        manager.stopUpdatingLocation()
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        Task { @MainActor in
            self.location = last
            if !self.hasFix { self.hasFix = true }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let s = manager.authorizationStatus
        Task { @MainActor in
            self.status = s
            if s == .authorizedWhenInUse || s == .authorizedAlways {
                self.useRecentFix(self.manager.location)
                self.manager.startUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}

extension LatLon {
    var clCoordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
}

extension EncodedPolyline {
    var clCoordinates: [CLLocationCoordinate2D] { mapPoints.map(\.clCoordinate) }
}

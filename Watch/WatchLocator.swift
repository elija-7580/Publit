import CoreLocation
import Foundation

/// Where the watch is, once: for Nearby and for "from my location". Asks for permission on first use.
@MainActor
final class WatchLocator: NSObject, CLLocationManagerDelegate {
    static let shared = WatchLocator()

    private let manager = CLLocationManager()
    /// The last position found, for biasing a search toward where you are (no new request).
    private(set) var last: LatLon?
    private var waiting: [CheckedContinuation<LatLon?, Never>] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// The user (or Screen Time) switched location off for Publit.
    var isDenied: Bool {
        let auth = manager.authorizationStatus
        return auth == .denied || auth == .restricted
    }

    /// nil when there is no position (location off, no signal). Several callers share one request.
    func locate() async -> LatLon? {
        await withCheckedContinuation { c in
            waiting.append(c)
            guard waiting.count == 1 else { return }
            // No answer at all (the permission question left open, no fix indoors): give up after a
            // while, or Nearby stays on "Waiting for your location…" and "Try again" does nothing.
            round += 1
            let mine = round
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(20))
                guard let self, self.round == mine, !self.waiting.isEmpty else { return }
                self.deliver(nil)
            }
            switch manager.authorizationStatus {
            case .notDetermined: manager.requestWhenInUseAuthorization()
            case .denied, .restricted: deliver(nil)
            default: manager.requestLocation()
            }
        }
    }

    /// Counts location requests, so a timeout only ends the request it was started for.
    private var round = 0

    private func deliver(_ position: LatLon?) {
        round += 1
        if let position { last = position }
        let all = waiting
        waiting = []
        for c in all { c.resume(returning: position) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let c = locations.last?.coordinate else { return }
        let p = LatLon(lat: c.latitude, lon: c.longitude)
        Task { @MainActor in self.deliver(p) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.deliver(nil) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let auth = manager.authorizationStatus
        Task { @MainActor in
            guard !self.waiting.isEmpty else { return }
            switch auth {
            case .notDetermined: break
            case .denied, .restricted: self.deliver(nil)
            default: self.manager.requestLocation()
            }
        }
    }
}

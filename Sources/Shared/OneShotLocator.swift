// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich

import CoreLocation
import Foundation

/// Where the device is, once, for a widget or complication. Never asks for permission (a widget
/// cannot): without it, or without a fix in time, the last known position or nil.
@MainActor
final class OneShotLocator: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<LatLon?, Never>?

    /// A position no older than this is used right away.
    static let freshEnough: TimeInterval = 120
    /// The last known position is still good for a widget when no newer one arrives.
    static let oldestUsable: TimeInterval = 30 * 60

    static func locate(timeout: TimeInterval = 8) async -> LatLon? {
        let locator = OneShotLocator()
        return await locator.run(timeout: timeout)
    }

    private var cached: LatLon? {
        guard let l = manager.location, -l.timestamp.timeIntervalSinceNow < Self.oldestUsable else { return nil }
        return LatLon(lat: l.coordinate.latitude, lon: l.coordinate.longitude)
    }

    private func run(timeout: TimeInterval) async -> LatLon? {
        switch manager.authorizationStatus {
        case .notDetermined, .denied, .restricted: return nil
        default: break
        }
        if let l = manager.location, -l.timestamp.timeIntervalSinceNow < Self.freshEnough {
            return LatLon(lat: l.coordinate.latitude, lon: l.coordinate.longitude)
        }
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        return await withCheckedContinuation { c in
            continuation = c
            manager.requestLocation()
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(timeout))
                self.finish(self.cached)
            }
        }
    }

    private func finish(_ position: LatLon?) {
        guard let c = continuation else { return }
        continuation = nil
        c.resume(returning: position)
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let c = locations.last?.coordinate else { return }
        let p = LatLon(lat: c.latitude, lon: c.longitude)
        Task { @MainActor in self.finish(p) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(self.cached) }
    }
}

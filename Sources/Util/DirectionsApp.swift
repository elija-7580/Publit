import MapKit
import UIKit

/// Which app "Open in …" hands a place or a walk to (Settings → Map).
enum DirectionsApp: String, CaseIterable, Identifiable {
    case apple, google, citymapper

    static let defaultsKey = "directionsApp"
    static var current: DirectionsApp {
        DirectionsApp(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .apple
    }

    var id: String { rawValue }
    var title: String {
        switch self {
        case .apple: return L10n.t("Apple Maps")
        case .google: return "Google Maps"
        case .citymapper: return "Citymapper"
        }
    }

    /// "Open in Google Maps".
    var openLabel: String { L10n.f("Open in %@", title) }

    enum Mode { case walking, transit, show }

    /// Opens the place in the chosen app: directions from where you are (or from `from`, for a later
    /// walk of a trip), or just the place.
    /// Google and Citymapper links open their app when it is installed, otherwise the website.
    @MainActor
    func open(_ point: LatLon, name: String, mode: Mode, from: (point: LatLon, name: String)? = nil) {
        switch self {
        case .apple:
            let item = MKMapItem(placemark: MKPlacemark(coordinate: point.clCoordinate))
            item.name = name
            var options: [String: Any]?
            switch mode {
            case .walking: options = [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking]
            case .transit: options = [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeTransit]
            case .show: options = nil
            }
            if let from, mode != .show {
                let start = MKMapItem(placemark: MKPlacemark(coordinate: from.point.clCoordinate))
                start.name = from.name
                MKMapItem.openMaps(with: [start, item], launchOptions: options)
            } else {
                item.openInMaps(launchOptions: options)
            }
        case .google, .citymapper:
            if let url = url(point, name: name, mode: mode, from: from) { UIApplication.shared.open(url) }
        }
    }

    func url(_ point: LatLon, name: String, mode: Mode, from: (point: LatLon, name: String)? = nil) -> URL? {
        let coord = String(format: "%.6f,%.6f", point.lat, point.lon)
        let start = from.map { String(format: "%.6f,%.6f", $0.point.lat, $0.point.lon) }
        switch self {
        case .apple:
            var c = URLComponents(string: "https://maps.apple.com/")!
            c.queryItems = mode == .show ? [URLQueryItem(name: "ll", value: coord), URLQueryItem(name: "q", value: name)]
                : (start.map { [URLQueryItem(name: "saddr", value: $0)] } ?? [])
                    + [URLQueryItem(name: "daddr", value: coord), URLQueryItem(name: "dirflg", value: mode == .walking ? "w" : "r")]
            return c.url
        case .google:
            if mode == .show {
                var c = URLComponents(string: "https://www.google.com/maps/search/")!
                c.queryItems = [URLQueryItem(name: "api", value: "1"), URLQueryItem(name: "query", value: coord)]
                return c.url
            }
            var c = URLComponents(string: "https://www.google.com/maps/dir/")!
            c.queryItems = [URLQueryItem(name: "api", value: "1")] + (start.map { [URLQueryItem(name: "origin", value: $0)] } ?? [])
                + [URLQueryItem(name: "destination", value: coord),
                   URLQueryItem(name: "travelmode", value: mode == .walking ? "walking" : "transit")]
            return c.url
        case .citymapper:
            var c = URLComponents(string: "https://citymapper.com/directions")!
            c.queryItems = (from.map { [URLQueryItem(name: "startcoord", value: start), URLQueryItem(name: "startname", value: $0.name)] } ?? [])
                + [URLQueryItem(name: "endcoord", value: coord), URLQueryItem(name: "endname", value: name)]
            return c.url
        }
    }
}

import Foundation

/// `publit://trip/<saved trip id>` opens a saved trip with its live status,
/// `publit://ticket/<ticket id>` (or `publit://ticket` for the default pass) shows a ticket.
/// Used in calendar events, on the Live Activity, by the departures widget and by Siri.
enum DeepLink: Hashable, Identifiable {
    case trip(String)
    case ticket(String?)
    /// Tickets for one saved trip (its single tickets plus valid passes): `publit://tickets/<trip id>`.
    case tripTickets(String)
    /// Departure board: `publit://stop/<stop id>?name=…&lat=…&lon=…` (from the widget).
    case stop(id: String, name: String, lat: Double, lon: Double)
    /// Routes from here to Home or Work, leaving now: `publit://go/home` (from Siri).
    case go(PlaceRole)

    static let scheme = "publit"

    var id: String { url.absoluteString }

    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme, let host = url.host?.lowercased() else { return nil }
        let arg = url.pathComponents.dropFirst().first.flatMap { $0.removingPercentEncoding }
        switch host {
        case "trip":
            guard let arg, !arg.isEmpty else { return nil }
            self = .trip(arg)
        case "ticket":
            self = .ticket(arg?.isEmpty == false ? arg : nil)
        case "tickets":
            guard let arg, !arg.isEmpty else { return nil }
            self = .tripTickets(arg)
        case "stop":
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            func value(_ n: String) -> String? { items.first { $0.name == n }?.value }
            guard let arg, !arg.isEmpty, let lat = value("lat").flatMap(Double.init),
                  let lon = value("lon").flatMap(Double.init),
                  lat.isFinite, lon.isFinite, abs(lat) <= 90, abs(lon) <= 180 else { return nil }
            self = .stop(id: arg, name: value("name") ?? arg, lat: lat, lon: lon)
        case "go":
            guard let role = arg.flatMap(PlaceRole.init(rawValue:)) else { return nil }
            self = .go(role)
        default:
            return nil
        }
    }

    var url: URL {
        var c = URLComponents()
        c.scheme = Self.scheme
        switch self {
        case .trip(let id): c.host = "trip"; c.path = "/" + id
        case .ticket(let id): c.host = "ticket"; c.path = id.map { "/" + $0 } ?? ""
        case .tripTickets(let id): c.host = "tickets"; c.path = "/" + id
        case .stop(let id, let name, let lat, let lon):
            c.host = "stop"; c.path = "/" + id
            c.queryItems = [URLQueryItem(name: "name", value: name),
                            URLQueryItem(name: "lat", value: String(lat)), URLQueryItem(name: "lon", value: String(lon))]
        case .go(let role): c.host = "go"; c.path = "/" + role.rawValue
        }
        return c.url!
    }
}

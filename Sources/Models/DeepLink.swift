import Foundation

/// `publit://trip/<saved trip id>` opens a saved trip with its live status,
/// `publit://ticket/<ticket id>` (or `publit://ticket` for the default pass) shows a ticket.
/// Used in calendar events and on the Live Activity.
enum DeepLink: Hashable, Identifiable {
    case trip(String)
    case ticket(String?)
    /// Tickets for one saved trip (its single tickets plus valid passes): `publit://tickets/<trip id>`.
    case tripTickets(String)

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
        }
        return c.url!
    }
}

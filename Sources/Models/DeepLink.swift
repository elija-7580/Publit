import Foundation

/// `publit://trip/<saved trip id>` opens a saved trip with its live status,
/// `publit://ticket/<ticket id>` (or `publit://ticket` for the default pass) shows a ticket.
/// Used in calendar events, on the Live Activity, by the departures widget and by Siri.
/// `publit://route?…` carries a whole route (see `SharedRoute`), so it also works on someone else's
/// iPhone; `ShareLinks.web` wraps any link in an https address that can be sent to anyone.
enum DeepLink: Hashable, Identifiable {
    case trip(String)
    /// A route someone shared: fetched again from Transitous with its live state.
    case route(SharedRoute)
    case ticket(String?)
    /// Tickets for one saved trip (its single tickets plus valid passes): `publit://tickets/<trip id>`.
    case tripTickets(String)
    /// Departure board: `publit://stop/<stop id>?name=…&lat=…&lon=…` (from the widget).
    case stop(id: String, name: String, lat: Double, lon: Double)
    /// Routes from here to Home or Work, leaving now: `publit://go/home` (from Siri).
    case go(PlaceRole)
    /// Routes from here to a place shared from another map app: `publit://place?name=…&lat=…&lon=…`
    /// (from the share extension, see `MapLink`). Without coordinates the name is searched.
    case place(name: String, lat: Double?, lon: Double?)
    /// Other routes when a change is at risk: `publit://alternatives?tn=…&tlat=…&tlon=…[&fn=…&flat=…&flon=…&fs=…]`,
    /// from the change stop (or from here without `fn`) to the destination, leaving now.
    case alternatives(from: Spot?, to: Spot)

    /// A place in a link (no dependency on `SavedPlace`, so the extensions that build links compile without it).
    struct Spot: Hashable, Sendable {
        var name: String
        var lat: Double
        var lon: Double
        var stopId: String?
    }

    static let scheme = "publit"

    var id: String { url.absoluteString }

    init?(url: URL) {
        if let inner = ShareLinks.appURL(fromWeb: url) { self.init(url: inner); return }
        guard url.scheme?.lowercased() == Self.scheme, let host = url.host?.lowercased() else { return nil }
        let arg = url.pathComponents.dropFirst().first.flatMap { $0.removingPercentEncoding }
        switch host {
        case "trip":
            guard let arg, !arg.isEmpty else { return nil }
            self = .trip(arg)
        case "route":
            guard let route = SharedRoute(query: url.query ?? "") else { return nil }
            self = .route(route)
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
        case "place":
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            func value(_ n: String) -> String? { items.first { $0.name == n }?.value.flatMap { $0.isEmpty ? nil : $0 } }
            let lat = value("lat").flatMap(Double.init), lon = value("lon").flatMap(Double.init)
            if let lat, let lon {
                guard lat.isFinite, lon.isFinite, abs(lat) <= 90, abs(lon) <= 180 else { return nil }
                self = .place(name: value("name") ?? String(format: "%.5f, %.5f", lat, lon), lat: lat, lon: lon)
            } else {
                guard let name = value("name") else { return nil }
                self = .place(name: name, lat: nil, lon: nil)
            }
        case "alternatives":
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            func value(_ n: String) -> String? { items.first { $0.name == n }?.value.flatMap { $0.isEmpty ? nil : $0 } }
            func coord(_ a: String, _ b: String) -> (Double, Double)? {
                guard let lat = value(a).flatMap(Double.init), let lon = value(b).flatMap(Double.init),
                      lat.isFinite, lon.isFinite, abs(lat) <= 90, abs(lon) <= 180 else { return nil }
                return (lat, lon)
            }
            guard let tn = value("tn"), let t = coord("tlat", "tlon") else { return nil }
            let to = Spot(name: tn, lat: t.0, lon: t.1, stopId: value("ts"))
            var from: Spot?
            if let fn = value("fn"), let f = coord("flat", "flon") {
                from = Spot(name: fn, lat: f.0, lon: f.1, stopId: value("fs"))
            }
            self = .alternatives(from: from, to: to)
        default:
            return nil
        }
    }

    var url: URL {
        var c = URLComponents()
        c.scheme = Self.scheme
        switch self {
        case .trip(let id): c.host = "trip"; c.path = "/" + id
        case .route(let r): c.host = "route"; c.percentEncodedQuery = r.query
        case .ticket(let id): c.host = "ticket"; c.path = id.map { "/" + $0 } ?? ""
        case .tripTickets(let id): c.host = "tickets"; c.path = "/" + id
        case .stop(let id, let name, let lat, let lon):
            c.host = "stop"; c.path = "/" + id
            c.queryItems = [URLQueryItem(name: "name", value: name),
                            URLQueryItem(name: "lat", value: String(lat)), URLQueryItem(name: "lon", value: String(lon))]
        case .go(let role): c.host = "go"; c.path = "/" + role.rawValue
        case .place(let name, let lat, let lon):
            c.host = "place"
            var items = [URLQueryItem(name: "name", value: name)]
            if let lat, let lon {
                items += [URLQueryItem(name: "lat", value: String(lat)), URLQueryItem(name: "lon", value: String(lon))]
            }
            c.queryItems = items
        case .alternatives(let from, let to):
            c.host = "alternatives"
            var items = [URLQueryItem(name: "tn", value: to.name), URLQueryItem(name: "tlat", value: String(to.lat)),
                         URLQueryItem(name: "tlon", value: String(to.lon))]
            if let s = to.stopId { items.append(URLQueryItem(name: "ts", value: s)) }
            if let from {
                items += [URLQueryItem(name: "fn", value: from.name), URLQueryItem(name: "flat", value: String(from.lat)),
                          URLQueryItem(name: "flon", value: String(from.lon))]
                if let s = from.stopId { items.append(URLQueryItem(name: "fs", value: s)) }
            }
            c.queryItems = items
        }
        return c.url!
    }
}

/// A route as a link: what is needed to fetch it again on any iPhone, nothing from this device's storage.
/// `itineraryId` is the MOTIS itinerary ID (it encodes the vehicles and stops; `refresh-itinerary` answers
/// with the live state). Places and departure are there for the label and, when the ID no longer works
/// (old timetable), for searching the same route again.
struct SharedRoute: Hashable, Sendable {
    var itineraryId: String?
    var fromName: String
    var from: LatLon
    var toName: String
    var to: LatLon
    var departure: Date
    /// A route built leg by leg (#145): the planned routes it is made of and which legs of each.
    /// Older versions ignore it and offer to search the route again.
    var parts: [RoutePart]? = nil

    init(itineraryId: String?, fromName: String, from: LatLon, toName: String, to: LatLon, departure: Date,
         parts: [RoutePart]? = nil) {
        self.parts = parts
        self.itineraryId = itineraryId
        self.fromName = fromName
        self.from = from
        self.toName = toName
        self.to = to
        self.departure = departure
    }

    init(_ it: Itinerary, fromName: String, toName: String) {
        let start = it.legs.first?.from, end = it.legs.last?.to
        // A route built leg by leg has no server ID of its own: its link carries its parts. One with
        // a part on foot, by bike or by car (no ID to fetch it by) carries the search only.
        let parts = it.builtFrom.flatMap { $0.allSatisfy { !$0.itineraryId.isEmpty } && $0.count <= Self.maxParts ? $0 : nil }
        self.init(itineraryId: it.id.isEmpty || it.builtFrom != nil ? nil : it.id,
                  fromName: fromName.isEmpty ? (start?.name ?? "") : fromName,
                  from: LatLon(lat: start?.lat ?? 0, lon: start?.lon ?? 0),
                  toName: toName.isEmpty ? (end?.name ?? "") : toName,
                  to: LatLon(lat: end?.lat ?? 0, lon: end?.lon ?? 0),
                  departure: it.legs.first?.scheduledStartTime ?? it.startTime, parts: parts)
    }

    /// More parts make the link too long to send.
    static let maxParts = 6

    /// `i=…&f=…&fl=…&t=…&tl=…&d=…`, every value percent-encoded (no `+`, safe in a URL fragment too).
    var query: String {
        var items: [(String, String)] = []
        if let itineraryId { items.append(("i", ShareLinks.pack(itineraryId))) }
        items += [("f", fromName), ("fl", from.apiValue), ("t", toName), ("tl", to.apiValue),
                  ("d", String(Int64(departure.timeIntervalSince1970)))]
        // `p0=<id>~<first leg>~<legs>`, `p1=…`: after the fields older versions read.
        for (n, part) in (parts ?? []).enumerated() {
            items.append(("p\(n)", "\(ShareLinks.pack(part.itineraryId))~\(part.firstLeg)~\(part.legCount)"))
        }
        return items.map { "\($0)=\(ShareLinks.encode($1))" }.joined(separator: "&")
    }

    init?(query: String) {
        var v: [String: String] = [:]
        for pair in query.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2, let value = kv[1].removingPercentEncoding else { continue }
            v[kv[0]] = value
        }
        guard let from = v["fl"].flatMap(LatLon.init(apiValue:)), let to = v["tl"].flatMap(LatLon.init(apiValue:)),
              let d = v["d"].flatMap(Double.init), d.isFinite else { return nil }
        var parts: [RoutePart] = []
        while parts.count < Self.maxParts, let raw = v["p\(parts.count)"] {
            let fields = raw.split(separator: "~", omittingEmptySubsequences: false)
            guard fields.count >= 3, let first = Int(fields[fields.count - 2]), let count = Int(fields[fields.count - 1]),
                  first >= 0, count > 0, count < 100,
                  let id = ShareLinks.unpack(fields.dropLast(2).joined(separator: "~")) else { parts = []; break }
            parts.append(RoutePart(itineraryId: id, firstLeg: first, legCount: count))
        }
        self.init(itineraryId: v["i"].flatMap(ShareLinks.unpack), fromName: v["f"] ?? "", from: from,
                  toName: v["t"] ?? "", to: to, departure: Date(timeIntervalSince1970: d), parts: parts.isEmpty ? nil : parts)
    }
}

/// Links for other people: `https://publit.eu/open/#route?…` opens a small page
/// (docs/open/index.html) that shows what was shared, opens Publit, or falls back to maps.
/// The part after `#` never reaches the web server.
enum ShareLinks {
    static let webHost = "publit.eu"
    static let webPath = "/open/"
    /// Existing share links on GitHub Pages keep working after the domain change.
    static let legacyWebHosts = ["elija-7580.github.io"]
    /// Paths of links sent by older builds; still read when pasted.
    static let legacyPaths = ["/publit-site/open/", "/Publit-/open/", "/Publit/open/"]

    /// The https link for sending; the app link without `publit://` goes after `#`.
    static func web(_ link: DeepLink) -> URL {
        let app = link.url.absoluteString
        let rest = app.hasPrefix(DeepLink.scheme + "://") ? String(app.dropFirst(DeepLink.scheme.count + 3)) : app
        return URL(string: "https://\(webHost)\(webPath)#\(rest)")!
    }

    /// The `publit://` link inside a web share link (pasted, or opened as a universal link later).
    static func appURL(fromWeb url: URL) -> URL? {
        let host = url.host?.lowercased()
        guard url.scheme?.lowercased() == "https",
              host == webHost || legacyWebHosts.contains(host ?? ""),
              ([webPath] + legacyPaths).contains(where: { url.path.hasPrefix(String($0.dropLast())) }),
              let fragment = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedFragment,
              !fragment.isEmpty else { return nil }
        return URL(string: "\(DeepLink.scheme)://\(fragment)")
    }

    private static let unreserved = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    static func encode(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: unreserved) ?? "" }

    /// The itinerary ID is base64 protobuf (1–2 KB). Compressed it is about half as long:
    /// `z` + base64url of raw DEFLATE; `b` + base64url when compression is not available.
    static func pack(_ id: String) -> String {
        guard let data = Data(base64Encoded: id) else { return "s" + id }
        #if canImport(Darwin)
        if let z = try? (data as NSData).compressed(using: .zlib) as Data, z.count < data.count {
            return "z" + base64url(z)
        }
        #endif
        return "b" + base64url(data)
    }

    static func unpack(_ s: String) -> String? {
        guard let kind = s.first else { return nil }
        let body = String(s.dropFirst())
        switch kind {
        case "s": return body.isEmpty ? nil : body
        case "b": return data(base64url: body)?.base64EncodedString()
        case "z":
            #if canImport(Darwin)
            guard let z = data(base64url: body),
                  let raw = try? (z as NSData).decompressed(using: .zlib) as Data else { return nil }
            return raw.base64EncodedString()
            #else
            return nil
            #endif
        default: return nil
        }
    }

    static func base64url(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func data(base64url s: String) -> Data? {
        var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        return Data(base64Encoded: b)
    }
}

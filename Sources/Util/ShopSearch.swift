// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A shop search with start, destination and departure filled in, so the shop opens on the user's connections
/// instead of its start page. Checked by hand in November 2026: bahn.de (station names are enough) and the
/// FlixBus shop (needs FlixBus city IDs, looked up when the user taps).
struct ShopSearch: Hashable, Sendable {
    enum Shop: String, Sendable { case db, flix }

    let shop: Shop
    let fromName: String
    let toName: String
    let from: LatLon
    let to: LatLon
    /// Scheduled departure of the first ride with this operator.
    let departure: Date
    /// Time zone of the departure stop (the shops expect local time).
    let timeZone: TimeZone

    /// The shop that can be searched for an operator, or nil.
    static func shop(for operatorName: String) -> Shop? {
        let key = TicketLinks.operatorKey(operatorName)
        let words = Set(key.split(separator: " ").map(String.init))
        if words.contains("db") || key.contains("deutsche bahn") { return .db }
        if words.contains(where: { $0.hasPrefix("flixbus") || $0.hasPrefix("flixtrain") }) { return .flix }
        return nil
    }

    init?(operatorName: String, from: Place, to: Place, departure: Date) {
        guard let shop = Self.shop(for: operatorName), !from.name.isEmpty, !to.name.isEmpty else { return nil }
        self.shop = shop
        fromName = from.name
        toName = to.name
        self.from = from.coordinate
        self.to = to.coordinate
        self.departure = departure
        timeZone = from.tz.flatMap(TimeZone.init(identifier:)) ?? TimeZone(identifier: "Europe/Berlin")!
    }

    /// The shop's start page, used until the search is ready (or when it cannot be built).
    var startPage: URL {
        switch shop {
        case .db: return URL(string: "https://www.bahn.de")!
        case .flix: return URL(string: "https://www.flixbus.com")!
        }
    }

    private func format(_ pattern: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = pattern
        return f.string(from: departure)
    }

    /// bahn.de connection search, one adult, 2nd class, connections from the departure time on.
    var dbURL: URL? {
        guard shop == .db else { return nil }
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: allowed) ?? "" }
        func id(_ name: String) -> String { enc("A=1@O=\(name)@") }
        let fragment = [
            "sts=true", "so=\(enc(fromName))", "zo=\(enc(toName))", "kl=2", "r=13:16:KLASSENLOS:1",
            "soid=\(id(fromName))", "zoid=\(id(toName))", "sot=ST", "zot=ST",
            "hd=\(format("yyyy-MM-dd'T'HH:mm")):00", "hza=D", "ar=false", "s=false", "d=false", "fm=false", "bp=false",
        ].joined(separator: "&")
        return URL(string: "https://www.bahn.de/buchung/fahrplan/suche#" + fragment)
    }

    /// FlixBus shop search for two FlixBus city IDs.
    func flixURL(fromCity: String, toCity: String) -> URL? {
        var c = URLComponents(string: "https://shop.flixbus.com/search")!
        c.queryItems = [
            URLQueryItem(name: "departureCity", value: fromCity),
            URLQueryItem(name: "arrivalCity", value: toCity),
            URLQueryItem(name: "rideDate", value: format("dd.MM.yyyy")),
            URLQueryItem(name: "adult", value: "1"),
        ]
        return c.url
    }

    /// The finished search link. For FlixBus this looks up the two cities (only the stop names go to FlixBus,
    /// and only when the user taps); nil when they cannot be found.
    func resolve(session: URLSession = .shared) async -> URL? {
        switch shop {
        case .db: return dbURL
        case .flix:
            async let a = FlixCities.id(near: from, name: fromName, session: session)
            async let b = FlixCities.id(near: to, name: toName, session: session)
            guard let fromCity = await a, let toCity = await b, fromCity != toCity else { return nil }
            return flixURL(fromCity: fromCity, toCity: toCity)
        }
    }
}

/// FlixBus city IDs, from the FlixBus shop's own city search (the same one its web page uses).
enum FlixCities {
    struct City: Decodable {
        struct Location: Decodable { let lat: Double; let lon: Double }
        let id: String
        let name: String
        let location: Location
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: String] = [:]

    /// The words to search for: the stop name without its details ("Wien Erdberg (VIB)" → "Wien Erdberg"),
    /// then only the first word ("Wien").
    static func queries(for name: String) -> [String] {
        let base = name.components(separatedBy: CharacterSet(charactersIn: "(,/–-")).first?
            .trimmingCharacters(in: .whitespaces) ?? name
        let first = base.split(separator: " ").first.map(String.init) ?? base
        return (base == first ? [base] : [base, first]).filter { !$0.isEmpty }
    }

    /// The nearest city within 50 km of the stop, from a city search answer.
    static func nearest(_ cities: [City], to point: LatLon) -> City? {
        cities.map { ($0, distanceKm(point, LatLon(lat: $0.location.lat, lon: $0.location.lon))) }
            .filter { $0.1 <= 50 }
            .min { $0.1 < $1.1 }?.0
    }

    static func distanceKm(_ a: LatLon, _ b: LatLon) -> Double {
        let r = 6371.0, rad = Double.pi / 180
        let dLat = (b.lat - a.lat) * rad, dLon = (b.lon - a.lon) * rad
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(a.lat * rad) * cos(b.lat * rad) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * asin(min(1, sqrt(h)))
    }

    static func id(near point: LatLon, name: String, session: URLSession = .shared) async -> String? {
        let key = "\(name)@\((point.lat * 100).rounded()),\((point.lon * 100).rounded())"
        if let hit = lock.withLock({ cache[key] }) { return hit }
        for q in queries(for: name) {
            var c = URLComponents(string: "https://global.api.flixbus.com/search/autocomplete/cities")!
            c.queryItems = [URLQueryItem(name: "q", value: q), URLQueryItem(name: "lang", value: "en"),
                            URLQueryItem(name: "flixbus_cities_only", value: "false")]
            guard let url = c.url,
                  let (data, response) = try? await session.data(for: URLRequest(url: url, timeoutInterval: 6)),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let cities = try? JSONDecoder().decode([City].self, from: data) else { continue }
            if let city = nearest(cities, to: point) {
                lock.withLock { cache[key] = city.id }
                return city.id
            }
        }
        return nil
    }
}

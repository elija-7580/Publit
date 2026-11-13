import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Numbered station exits from OpenStreetMap (`railway=subway_entrance` with `ref`), so the walk
/// guide can say "Use exit 3" where many metro systems sign their exits by number.
///
/// The router already picks the exit on the shortest way; this only looks up the number of the
/// entrance at the point where that walk comes up to the street. Asked once per exit point (cached
/// for the session), with the exit's coordinate only, never the phone's position. Off in Settings
/// (`exitNumbers`).
actor StationExits {
    static let shared = StationExits()
    static let enabledKey = "exitNumbers"
    /// An entrance further away than this from the exit point is another exit.
    static let matchRadius = 45.0

    struct Entrance: Equatable, Sendable {
        let ref: String
        let coordinate: LatLon
    }

    /// Main instance first; it is often overloaded (504), so a second one as fallback.
    private let servers = [
        "https://overpass-api.de/api/interpreter",
        "https://overpass.kumi.systems/api/interpreter",
    ]
    private var cache: [String: String] = [:]
    private var misses: Set<String> = []
    private let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    static var isEnabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }

    /// The number of the exit at `point`, nil when OpenStreetMap has none there.
    func ref(at point: LatLon) async -> String? {
        guard Self.isEnabled, point.isValidCoordinate else { return nil }
        let key = String(format: "%.4f,%.4f", point.lat, point.lon)
        if let hit = cache[key] { return hit }
        if misses.contains(key) { return nil }
        for server in servers {
            guard let list = try? await fetch(around: point, from: server) else { continue }
            let found = Self.nearest(list, to: point)
            if let found { cache[key] = found } else { misses.insert(key) }
            return found
        }
        return nil // Both servers failed: not remembered, so the next opening asks again.
    }

    private func fetch(around p: LatLon, from server: String) async throws -> [Entrance] {
        guard var c = URLComponents(string: server) else { return [] }
        c.queryItems = [URLQueryItem(name: "data", value: Self.query(around: p))]
        guard let url = c.url else { return [] }
        var r = URLRequest(url: url, timeoutInterval: 12)
        r.setValue(AppInfo.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: r)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try Self.parse(data)
    }

    nonisolated static func query(around p: LatLon) -> String {
        let r = Int(matchRadius + 25)
        let at = String(format: "%.6f,%.6f", p.lat, p.lon)
        return "[out:json][timeout:10];(node(around:\(r),\(at))[railway~\"^(subway_entrance|train_station_entrance)$\"][ref];"
            + "node(around:\(r),\(at))[entrance][\"public_transport\"][ref];);out;"
    }

    nonisolated static func parse(_ data: Data) throws -> [Entrance] {
        struct Response: Decodable {
            struct Element: Decodable {
                let lat: Double?
                let lon: Double?
                let tags: [String: String]?
            }
            let elements: [Element]
        }
        return try JSONDecoder().decode(Response.self, from: data).elements.compactMap { e in
            guard let lat = e.lat, let lon = e.lon,
                  let ref = e.tags?["ref"]?.trimmingCharacters(in: .whitespaces),
                  !ref.isEmpty, ref.count <= 8 else { return nil }
            return Entrance(ref: ref, coordinate: LatLon(lat: lat, lon: lon))
        }
    }

    /// The entrance closest to `p`, if it is close enough to be the one the walk uses.
    nonisolated static func nearest(_ list: [Entrance], to p: LatLon) -> String? {
        list.map { ($0, $0.coordinate.distance(to: p)) }
            .filter { $0.1 <= matchRadius }
            .min { $0.1 < $1.1 }?.0.ref
    }
}

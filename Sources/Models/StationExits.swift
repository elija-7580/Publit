import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A way out of a station, from OpenStreetMap: `railway=subway_entrance`, `train_station_entrance`
/// or `public_transport=entrance`. Signed with a number or letter ("A", "B2", "12") in `ref`, or with
/// a name ("Nord", "Bahnhofplatz"); some have neither and only say where the door is.
struct StationEntrance: Equatable, Sendable {
    let id: Int64
    let ref: String?
    var name: String? = nil
    let coordinate: LatLon

    /// What the sign says: the number, else the name.
    var label: String? { ref ?? name }
}

/// The best exit for walks out of a station, so you do not have to look for a station map:
/// "Take exit B2", and the door on the live map. Metro stations and railway stations alike;
/// OpenStreetMap has the entrances with their number or name. Asked from Overpass once per station,
/// kept for the session.
final class StationExits: @unchecked Sendable {
    static let shared = StationExits()
    /// Settings → Data → "Exit numbers from OpenStreetMap" (on). Off: no Overpass lookups at all.
    static let enabledKey = "stationExitNumbers"
    static var enabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }

    /// Entrances further than this from where you get off are another station's.
    static let radius = 250.0
    /// An entrance this close to where the walk reaches the street is the one it uses.
    static let nearExit = 40.0
    /// An entrance this close to the walk's path is on the way.
    static let nearPath = 20.0
    /// The main Overpass instance is often busy (504); the second one answers then.
    static let endpoints = [URL(string: "https://overpass-api.de/api/interpreter")!,
                            URL(string: "https://overpass.kumi.systems/api/interpreter")!]

    private let lock = NSLock()
    /// Entrances per station (rounded place where you get off).
    private var areas: [String: [StationEntrance]] = [:]
    /// Walks that leave an underground station, and their station.
    private var walks: [String: String] = [:]
    private var loading: Set<String> = []
    private var failed: [String: Date] = [:]
    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let cfg = URLSessionConfiguration.default
            cfg.timeoutIntervalForRequest = 15
            cfg.urlCache = nil
            self.session = URLSession(configuration: cfg)
        }
    }

    // MARK: Which walks

    /// Rides that end in a station building or underground: metro and trains (not trams and buses,
    /// which stop in the street).
    static let stationModes: Set<String> = ["SUBWAY", "METRO", "HIGHSPEED_RAIL", "LONG_DISTANCE", "REGIONAL_RAIL",
                                            "REGIONAL_FAST_RAIL", "NIGHT_RAIL", "RAIL", "SUBURBAN"]

    /// The walk after a ride that ends in a station (metro, train, or any ride whose walk starts
    /// below street level), unless it only changes to another platform of that station.
    static func leavesStation(_ legs: [Leg], at i: Int) -> Bool {
        guard legs.indices.contains(i), i > 0, !legs[i].isTransit else { return false }
        let walk = legs[i], before = legs[i - 1]
        guard before.isTransit else { return false }
        let levels = (walk.steps ?? []).flatMap { [$0.fromLevel, $0.toLevel] }.compactMap { $0 }
        let startsBelow = (levels.first ?? 0) < 0
        guard startsBelow || stationModes.contains(before.mode) else { return false }
        // Known levels: it has to come up to the street. Unknown: a short walk to another train is a change.
        if !levels.isEmpty, startsBelow { return levels.contains { $0 >= 0 } }
        if let next = legs[safe: i + 1], stationModes.contains(next.mode), (walk.distance ?? .infinity) < 250 { return false }
        return true
    }

    static func walkKey(_ leg: Leg) -> String { leg.from.coordinate.apiValue + ">" + leg.to.coordinate.apiValue }
    /// About 100 m: platforms of one station share their entrances.
    static func areaKey(_ p: LatLon) -> String { String(format: "%.3f,%.3f", p.lat, p.lon) }

    // MARK: Lookup

    /// Entrances around the station this walk leaves; nil when it does not leave one or nothing is loaded.
    func entrances(for leg: Leg) -> [StationEntrance]? {
        lock.lock(); defer { lock.unlock() }
        guard let area = walks[Self.walkKey(leg)] else { return nil }
        return areas[area]
    }

    /// Looks up the stations the itinerary leaves on foot. True when new exit numbers arrived.
    @discardableResult
    func load(_ it: Itinerary) async -> Bool {
        var wanted: [(walk: String, area: String, at: LatLon)] = []
        for i in it.legs.indices where Self.leavesStation(it.legs, at: i) {
            let leg = it.legs[i]
            wanted.append((Self.walkKey(leg), Self.areaKey(leg.from.coordinate), leg.from.coordinate))
        }
        guard Self.enabled, !wanted.isEmpty else { return false }
        let fetch = claim(wanted)
        var found = false
        for f in fetch {
            let result = try? await request(around: f.at)
            found = finish(f.area, result) || found
        }
        return found
    }

    private func claim(_ wanted: [(walk: String, area: String, at: LatLon)]) -> [(area: String, at: LatLon)] {
        lock.withLock {
            var fetch: [(area: String, at: LatLon)] = []
            for w in wanted {
                walks[w.walk] = w.area
                if areas[w.area] != nil || loading.contains(w.area) { continue }
                if let f = failed[w.area], Date().timeIntervalSince(f) < 300 { continue }
                loading.insert(w.area)
                fetch.append((w.area, w.at))
            }
            return fetch
        }
    }

    private func finish(_ area: String, _ result: [StationEntrance]?) -> Bool {
        lock.withLock {
            loading.remove(area)
            guard let result else { failed[area] = Date(); return false }
            areas[area] = result
            return !result.isEmpty
        }
    }

    /// For tests and previews.
    func store(_ entrances: [StationEntrance], for leg: Leg) {
        lock.lock(); defer { lock.unlock() }
        let area = Self.areaKey(leg.from.coordinate)
        walks[Self.walkKey(leg)] = area
        areas[area] = entrances
    }

    func removeAll() {
        lock.lock(); defer { lock.unlock() }
        areas = [:]; walks = [:]; failed = [:]
    }

    // MARK: Overpass

    static func query(around p: LatLon) -> String {
        let at = "\(Int(radius)),\(p.lat),\(p.lon)"
        return "[out:json][timeout:10];"
            + "(node(around:\(at))[\"railway\"~\"^(subway_entrance|train_station_entrance)$\"];"
            + "node(around:\(at))[\"public_transport\"=\"entrance\"];);out;"
    }

    private func request(around p: LatLon) async throws -> [StationEntrance] {
        var last: Error = URLError(.badServerResponse)
        for url in Self.endpoints {
            do { return try await request(url, around: p) } catch { last = error }
        }
        throw last
    }

    private func request(_ url: URL, around p: LatLon) async throws -> [StationEntrance] {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue(AppInfo.userAgent, forHTTPHeaderField: "User-Agent")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        req.httpBody = Data(("data=" + (Self.query(around: p).addingPercentEncoding(withAllowedCharacters: allowed) ?? "")).utf8)
        let (data, response) = try await session.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try Self.parse(data)
    }

    private struct Response: Decodable {
        struct Element: Decodable {
            let id: Int64
            let lat: Double?
            let lon: Double?
            let tags: [String: String]?
        }
        let elements: [Element]
    }

    static func parse(_ data: Data) throws -> [StationEntrance] {
        let r = try JSONDecoder().decode(Response.self, from: data)
        return r.elements.compactMap { e in
            guard let lat = e.lat, let lon = e.lon else { return nil }
            let point = LatLon(lat: lat, lon: lon)
            guard point.isValidCoordinate else { return nil }
            let tags = e.tags ?? [:]
            // A closed or staff-only door is no way out.
            if tags["access"] == "private" || tags["access"] == "no" || tags["entrance"] == "emergency" { return nil }
            return StationEntrance(id: e.id, ref: tags["ref"].flatMap(Self.clean),
                                   name: tags["name"].flatMap(Self.cleanName), coordinate: point)
        }
    }

    /// Names of exits as on the sign, without the word "exit" ("Ausgang Nord" → "Nord"), so they
    /// read in "Take exit …". Long names are descriptions, not signs.
    static func cleanName(_ name: String) -> String? {
        var s = name.trimmingCharacters(in: .whitespaces)
        for word in ["Ausgang", "Eingang", "Zugang", "Exit", "Entrance", "Uscita", "Sortie", "Salida", "Wyjście", "Výstup"] {
            if s.count > word.count + 1, s.lowercased().hasPrefix(word.lowercased() + " ") {
                s = String(s.dropFirst(word.count + 1)).trimmingCharacters(in: .whitespaces)
            }
        }
        guard !s.isEmpty, s.count <= 24, !s.contains(";") else { return nil }
        return s
    }

    /// Exit numbers are short ("A", "B2", "12", "A1-A2"); longer refs are internal codes, not signs.
    static func clean(_ ref: String) -> String? {
        let s = ref.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty, s.count <= 6, !s.contains(";") else { return nil }
        return s
    }

    // MARK: Choosing

    /// The entrance the walk goes out by: one the route passes through, else the nearest to where it
    /// reaches the street, else the first one along the way. `exit` is where the walk reaches the street.
    /// Among equally good doors a signed one (number or name) wins.
    static func pick(_ entrances: [StationEntrance], path: [LatLon], exit: (point: LatLon, along: Double)?,
                     nodes: Set<Int64>) -> StationEntrance? {
        guard !entrances.isEmpty else { return nil }
        // Signed doors first: `min` keeps the first of equals.
        let entrances = entrances.filter { $0.label != nil } + entrances.filter { $0.label == nil }
        func along(_ e: StationEntrance) -> (along: Double, offset: Double)? { PathGeometry.locate(e.coordinate, on: path) }
        let limit = exit.map { $0.along + nearExit } ?? .infinity
        let passed = entrances.filter { nodes.contains($0.id) }
        if let first = passed.min(by: { (along($0)?.along ?? 0) < (along($1)?.along ?? 0) }) { return first }
        if let exit, let near = entrances.min(by: { $0.coordinate.distance(to: exit.point) < $1.coordinate.distance(to: exit.point) }),
           near.coordinate.distance(to: exit.point) <= nearExit {
            return near
        }
        return entrances.compactMap { e in along(e).flatMap { $0.offset <= nearPath && $0.along <= limit ? (e, $0.along) : nil } }
            .min { $0.1 < $1.1 }?.0
    }
}

import Foundation

/// How badly the open timetable data falls short around a place. Ordered by severity.
enum CoverageLevel: Int, Comparable, Sendable {
    /// Some services are in the data, others are not (`CoverageArea.gaps` says which).
    case partial
    /// Next to nothing: stations only, most local and regional transport is missing.
    case sparse
    /// No timetable data at all.
    case none

    static func < (a: CoverageLevel, b: CoverageLevel) -> Bool { a.rawValue < b.rawValue }
}

/// A kind of service the open timetables do not contain in an area: the "which data is missing" part.
enum CoverageGap: Character, CaseIterable, Sendable {
    case localBuses = "L"
    case cityBuses = "C"
    case metro = "M"
    case trams = "T"
    case ferries = "F"
    case suburbanTrains = "S"

    var title: String {
        switch self {
        case .localBuses: return L10n.t("Local and regional buses")
        case .cityBuses: return L10n.t("City buses")
        case .metro: return L10n.t("Metro")
        case .trams: return L10n.t("Trams")
        case .ferries: return L10n.t("Ferries")
        case .suburbanTrains: return L10n.t("Suburban trains")
        }
    }

    /// "Metro, trams and ferries" in the reader's language.
    static func list(_ gaps: [CoverageGap]) -> String {
        let names = gaps.map { $0.title.lowercasedFirst }
        #if canImport(Darwin)
        return ListFormatter.localizedString(byJoining: names)
        #else
        return names.joined(separator: ", ")
        #endif
    }
}

private extension String {
    /// "Local buses" → "local buses" inside a sentence, but not "Metro" in German ("Metro" stays a noun there).
    var lowercasedFirst: String {
        if Bundle.main.preferredLocalizations.first == "de" { return self }
        return prefix(1).lowercased() + dropFirst()
    }
}

/// A place or region where data is known to be missing. Comes from `CoverageAtlasData`.
struct CoverageArea: Identifiable, Equatable, Sendable {
    enum Shape: Equatable, Sendable {
        case circle(center: LatLon, radius: Double)
        /// Outer rims and holes together: a point is inside when it lies within an odd number of rings.
        case polygon(rings: [[LatLon]])
    }

    let id: String
    let level: CoverageLevel
    let gaps: [CoverageGap]
    let nameEN: String
    let nameDE: String
    /// Where the website's coverage map shows this: `at/Kärnten` (country/region) or `it` (country).
    let link: String
    let shape: Shape
    let minLat: Double, maxLat: Double, minLon: Double, maxLon: Double

    init(id: String, level: CoverageLevel, gaps: [CoverageGap], nameEN: String, nameDE: String, link: String = "", shape: Shape) {
        self.id = id; self.level = level; self.gaps = gaps; self.nameEN = nameEN; self.nameDE = nameDE; self.link = link; self.shape = shape
        switch shape {
        case .circle(let c, let r):
            let dLat = r / 111_200
            let dLon = r / (111_200 * max(0.05, cos(c.lat * .pi / 180)))
            (minLat, maxLat, minLon, maxLon) = (c.lat - dLat, c.lat + dLat, c.lon - dLon, c.lon + dLon)
        case .polygon(let rings):
            let pts = rings.flatMap { $0 }
            (minLat, maxLat) = (pts.map(\.lat).min() ?? 0, pts.map(\.lat).max() ?? 0)
            (minLon, maxLon) = (pts.map(\.lon).min() ?? 0, pts.map(\.lon).max() ?? 0)
        }
    }

    static var prefersGerman: Bool { Bundle.main.preferredLocalizations.first == "de" }

    func name(german: Bool = CoverageArea.prefersGerman) -> String { german ? nameDE : nameEN }
    var name: String { name() }

    /// The coverage map, opened at this area and in the reader's language.
    func mapURL(german: Bool = CoverageArea.prefersGerman) -> URL {
        var text = CoverageGuide.mapURL.absoluteString + "?lang=" + (german ? "de" : "en")
        if let fragment = link.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed), !fragment.isEmpty { text += "#" + fragment }
        return URL(string: text) ?? CoverageGuide.mapURL
    }

    var center: LatLon { LatLon(lat: (minLat + maxLat) / 2, lon: (minLon + maxLon) / 2) }

    func intersects(minLat a: Double, maxLat b: Double, minLon c: Double, maxLon d: Double) -> Bool {
        !(maxLat < a || minLat > b || maxLon < c || minLon > d)
    }

    func contains(_ p: LatLon) -> Bool {
        guard p.lat >= minLat, p.lat <= maxLat, p.lon >= minLon, p.lon <= maxLon else { return false }
        switch shape {
        case .circle(let c, let r):
            let dy = (p.lat - c.lat) * 111_200
            let dx = (p.lon - c.lon) * 111_200 * cos(c.lat * .pi / 180)
            return dx * dx + dy * dy <= r * r
        case .polygon(let rings):
            var inside = false
            for ring in rings where Self.ring(ring, contains: p) { inside.toggle() }
            return inside
        }
    }

    /// One filled piece of an outline: its edge and the holes cut out of it (for drawing on a map).
    struct Piece: Equatable, Sendable {
        var outer: [LatLon]
        var holes: [[LatLon]] = []
    }

    /// The outline as filled pieces. The rings follow the even-odd rule: a ring inside an odd number
    /// of other rings is a hole of the ring around it.
    var pieces: [Piece] {
        guard case .polygon(let rings) = shape else { return [] }
        func inside(_ ring: [LatLon], of other: [LatLon]) -> Bool {
            // Most of the sampled points decide: a hole may touch the edge of its ring.
            let step = max(1, ring.count / 5)
            let samples = stride(from: 0, to: ring.count, by: step).map { ring[$0] }
            let hits = samples.filter { Self.ring(other, contains: $0) }.count
            return hits * 2 > samples.count
        }
        let depth = rings.indices.map { i in rings.indices.filter { $0 != i && inside(rings[i], of: rings[$0]) }.count }
        var out: [Piece] = []
        var pieceOf: [Int: Int] = [:]
        for i in rings.indices where depth[i] % 2 == 0 {
            pieceOf[i] = out.count
            out.append(Piece(outer: rings[i]))
        }
        for i in rings.indices where depth[i] % 2 == 1 {
            let parent = rings.indices.first { $0 != i && depth[$0] == depth[i] - 1 && inside(rings[i], of: rings[$0]) }
            if let parent, let k = pieceOf[parent] { out[k].holes.append(rings[i]) }
        }
        return out
    }

    /// Ray casting: is the point inside this one ring?
    static func ring(_ ring: [LatLon], contains p: LatLon) -> Bool {
        guard ring.count > 2 else { return false }
        var inside = false
        var j = ring.count - 1
        for i in ring.indices {
            let a = ring[i], b = ring[j]
            if (a.lat > p.lat) != (b.lat > p.lat),
               p.lon < (b.lon - a.lon) * (p.lat - a.lat) / (b.lat - a.lat) + a.lon { inside.toggle() }
            j = i
        }
        return inside
    }

    /// What is missing, in one short line: "Missing: metro, trams and ferries" / "No timetable data" / "Very little timetable data".
    var summary: String {
        switch level {
        case .none: return L10n.t("No timetable data")
        case .sparse: return L10n.t("Very little timetable data")
        case .partial: return gaps.isEmpty ? L10n.t("Very little timetable data") : L10n.f("Missing: %@", CoverageGap.list(gaps))
        }
    }
}

/// All known gaps, decoded once from the generated payload. Bundled in the app: lookups are
/// offline, nothing about where someone is leaves the phone.
struct CoverageAtlas: Sendable {
    let date: String
    let areas: [CoverageArea]

    static let shared = CoverageAtlas(payload: CoverageAtlasData.payload, date: CoverageAtlasData.date)

    init(areas: [CoverageArea], date: String = "") { self.areas = areas; self.date = date }

    /// One area per line: `A|id|level|gaps|name en|name de|link|shape` (see tools/coverage/make_atlas.py).
    init(payload: String, date: String) {
        var list: [CoverageArea] = []
        for line in payload.split(separator: "\n") {
            let f = line.split(separator: "|", maxSplits: 7, omittingEmptySubsequences: false)
            guard f.count == 8, f[0] == "A" else { continue }
            let level: CoverageLevel
            switch f[2] {
            case "n": level = .none
            case "s": level = .sparse
            case "p": level = .partial
            default: continue
            }
            let gaps = f[3].compactMap { CoverageGap(rawValue: $0) }
            guard let shape = Self.shape(f[7]) else { continue }
            list.append(CoverageArea(id: String(f[1]), level: level, gaps: gaps, nameEN: String(f[4]), nameDE: String(f[5]), link: String(f[6]), shape: shape))
        }
        self.init(areas: list, date: date)
    }

    /// The most specific area first: the file lists hand-checked areas before towns before regions.
    func area(at p: LatLon) -> CoverageArea? {
        guard p.isValidCoordinate else { return nil }
        return areas.first { $0.contains(p) }
    }

    /// Areas inside or touching a map rectangle (to draw them).
    func areas(minLat: Double, maxLat: Double, minLon: Double, maxLon: Double) -> [CoverageArea] {
        areas.filter { $0.intersects(minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon) }
    }

    // MARK: Decoding

    private static let digits: [UInt8] = {
        var table = [UInt8](repeating: 255, count: 128)
        for (i, c) in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_".utf8.enumerated() { table[Int(c)] = UInt8(i) }
        return table
    }()

    private static func shape(_ s: Substring) -> CoverageArea.Shape? {
        guard let kind = s.first else { return nil }
        let body = s.dropFirst()
        if kind == "c" {
            let v = body.split(separator: ",").compactMap { Double($0) }
            guard v.count == 3 else { return nil }
            return .circle(center: LatLon(lat: v[0] / 1000, lon: v[1] / 1000), radius: v[2])
        }
        guard kind == "p" else { return nil }
        let rings = body.split(separator: "/").map(ring).filter { $0.count > 2 }
        return rings.isEmpty ? nil : .polygon(rings: rings)
    }

    /// Zigzag varints, 5 bits per character (bit 5 = more follows); latitude and longitude deltas alternate.
    private static func ring(_ s: Substring) -> [LatLon] {
        var values: [Int] = []
        var acc = 0, shift = 0
        for u in s.utf8 {
            guard u < 128, digits[Int(u)] != 255 else { continue }
            let v = Int(digits[Int(u)])
            acc |= (v & 31) << shift
            if v >= 32 { shift += 5; continue }
            values.append(acc & 1 == 1 ? -((acc + 1) >> 1) : acc >> 1)
            acc = 0; shift = 0
        }
        var lat = 0, lon = 0
        var out: [LatLon] = []
        var i = 0
        while i + 1 < values.count {
            lat += values[i]; lon += values[i + 1]
            out.append(LatLon(lat: Double(lat) / 1000, lon: Double(lon) / 1000))
            i += 2
        }
        return out
    }
}

/// A warning to show: one area, and which of the searched places lie in it.
struct CoverageNotice: Identifiable, Equatable, Sendable {
    enum Role: Int, Comparable, Sendable {
        /// The place being looked at (map, nearby, a stop).
        case here
        case start
        case destination
        static func < (a: Role, b: Role) -> Bool { a.rawValue < b.rawValue }
    }

    let area: CoverageArea
    let roles: Set<Role>
    var id: String { area.id }

    /// "From · Carinthia", "To · Carinthia", "Carinthia" (when start and destination are both there, or neither is named).
    var heading: String {
        if roles == [.start] { return L10n.t("From") + " · " + area.name }
        if roles == [.destination] { return L10n.t("To") + " · " + area.name }
        return area.name
    }
}

enum CoverageGuide {
    /// The website's coverage map: what is missing where, and why.
    static let mapURL = URL(string: "https://publit.eu/abdeckung/")!

    /// Warnings for the places of a search, worst first, each area once.
    static func notices(places: [(point: LatLon?, role: CoverageNotice.Role)], atlas: CoverageAtlas = .shared) -> [CoverageNotice] {
        var byArea: [String: (area: CoverageArea, roles: Set<CoverageNotice.Role>)] = [:]
        var order: [String] = []
        for place in places {
            guard let p = place.point, let area = atlas.area(at: p) else { continue }
            if byArea[area.id] == nil { order.append(area.id); byArea[area.id] = (area, []) }
            byArea[area.id]?.roles.insert(place.role)
        }
        return order.compactMap { byArea[$0] }
            .sorted { $0.area.level > $1.area.level }
            .map { CoverageNotice(area: $0.area, roles: $0.roles) }
    }

    static func notices(start: LatLon?, destination: LatLon?, atlas: CoverageAtlas = .shared) -> [CoverageNotice] {
        notices(places: [(start, .start), (destination, .destination)], atlas: atlas)
    }

    static func notice(at point: LatLon?, atlas: CoverageAtlas = .shared) -> CoverageNotice? {
        notices(places: [(point, .here)], atlas: atlas).first
    }
}

extension CoverageGuide {
    /// Warnings for a whole trip: where it starts and ends, and the stops where it changes.
    /// A trip on foot, by bike or by car does not depend on the timetable data.
    static func notices(for itinerary: Itinerary, atlas: CoverageAtlas = .shared) -> [CoverageNotice] {
        guard itinerary.legs.contains(where: \.isTransit), let first = itinerary.legs.first, let last = itinerary.legs.last else { return [] }
        var places: [(point: LatLon?, role: CoverageNotice.Role)] = [(first.from.coordinate, .start)]
        for leg in itinerary.legs.dropFirst() where leg.isTransit { places.append((leg.from.coordinate, .here)) }
        places.append((last.to.coordinate, .destination))
        return notices(places: places, atlas: atlas)
    }
}

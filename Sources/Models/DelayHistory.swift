import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Measured delays for Smart Routing's change chances (`services/delay-history`, published on
/// publit.eu per country). Only public timetable data: the app downloads the tables of the
/// countries it plans in, like the coverage atlas; nothing about the user is sent.
enum DelayHistory {
    /// The five quantiles every distribution carries (share, 0…1).
    static let knots: [Double] = [0.05, 0.20, 0.50, 0.80, 0.95]
    static let samplesPerDistribution = 20

    /// A delay distribution in seconds, rebuilt from its 5/20/50/80/95 % quantiles.
    struct Dist: Equatable, Sendable {
        let q: [Double]

        init?(_ q: [Double]) {
            guard q.count == DelayHistory.knots.count else { return nil }
            self.q = q
        }

        /// Linear between the knots, linear outside them; the late tail twice as steep (long delays are rare but real).
        func quantile(_ p: Double) -> Double {
            let k = DelayHistory.knots
            if p <= k[0] { return q[0] - (k[0] - p) / (k[1] - k[0]) * (q[1] - q[0]) }
            if p >= k[4] { return q[4] + 2 * (p - k[4]) / (k[4] - k[3]) * (q[4] - q[3]) }
            for i in 0..<4 where p <= k[i + 1] {
                return q[i] + (p - k[i]) / (k[i + 1] - k[i]) * (q[i + 1] - q[i])
            }
            return q[4]
        }

        func samples(_ n: Int = DelayHistory.samplesPerDistribution) -> [Double] {
            (0..<n).map { quantile((Double($0) + 0.5) / Double(n)) }
        }

        func shifted(by s: Double) -> Dist { Dist(q.map { $0 + s })! }
        static let punctual = Dist([0, 0, 0, 0, 0])!
    }

    struct Row: Equatable, Sendable {
        let arrival: Dist?
        let departure: Dist?
        /// Share of cancelled or skipped stops (0…1).
        let cancelled: Double
        let observations: Int
    }

    /// p weekday peak, w weekday other, e weekend, n night – as on the server.
    static func window(_ date: Date, timeZone: TimeZone = .current) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let h = cal.component(.hour, from: date)
        let weekday = cal.component(.weekday, from: date)   // 1 Sunday … 7 Saturday
        if h >= 22 || h < 5 { return "n" }
        if weekday == 1 || weekday == 7 { return "e" }
        if (6..<9).contains(h) || (16..<19).contains(h) { return "p" }
        return "w"
    }

    /// "de" from "de-DELFI_de:09162:…".
    static func country(ofId id: String?) -> String? {
        guard let id, let tag = id.split(separator: "_", maxSplits: 1).first,
              let c = tag.split(separator: "-", maxSplits: 1).first, c.count >= 2, c.count <= 6 else { return nil }
        return c.lowercased()
    }

    // MARK: Table

    struct Table: Sendable {
        var date = ""
        var days = 0
        private(set) var stops: [String: Row] = [:]       // "route|stop|win"
        private(set) var routes: [String: Row] = [:]      // "route|win"
        private(set) var operators: [String: Row] = [:]   // "feed|agency|win"
        private(set) var modes: [String: Row] = [:]       // "mode|win"
        private(set) var horizons: [String: [(minutes: Double, error: Dist, n: Int)]] = [:]

        var isEmpty: Bool { routes.isEmpty && modes.isEmpty && stops.isEmpty }

        init() {}

        init(text: String) {
            func dist(_ s: Substring) -> Dist? {
                let v = s.split(separator: ",").compactMap { Double($0) }
                return Dist(v)
            }
            func row(_ f: [Substring], _ i: Int) -> Row? {
                guard f.count >= i + 4, let c = Double(f[i + 2]), let n = Int(f[i + 3]) else { return nil }
                return Row(arrival: dist(f[i]), departure: dist(f[i + 1]), cancelled: c / 1000, observations: n)
            }
            for line in text.split(separator: "\n") {
                let f = line.split(separator: "|", omittingEmptySubsequences: false)
                guard let kind = f.first else { continue }
                switch kind {
                case "D" where f.count >= 3: date = String(f[1]); days = Int(f[2]) ?? 0
                case "S" where f.count >= 8: if let r = row(f, 4) { stops["\(f[1])|\(f[2])|\(f[3])"] = r }
                case "R" where f.count >= 7: if let r = row(f, 3) { routes["\(f[1])|\(f[2])"] = r }
                case "O" where f.count >= 8: if let r = row(f, 4) { operators["\(f[1])|\(f[2])|\(f[3])"] = r }
                case "M" where f.count >= 7: if let r = row(f, 3) { modes["\(f[1])|\(f[2])"] = r }
                case "H" where f.count >= 5:
                    if let m = Double(f[2]), let e = dist(f[3]), let n = Int(f[4]) {
                        horizons[String(f[1]), default: []].append((m, e, n))
                        horizons[String(f[1])]!.sort { $0.minutes < $1.minutes }
                    }
                default: continue
                }
            }
        }

        /// Most specific first: route at this stop, route, operator, mode in the region.
        func row(routeId: String?, stopId: String?, agency: String?, mode: String, window: String) -> Row? {
            if let routeId {
                if let stopId, let r = stops["\(routeId)|\(stopId)|\(window)"] { return r }
                if let r = routes["\(routeId)|\(window)"] { return r }
                if let agency, let feed = routeId.split(separator: "_", maxSplits: 1).first,
                   let r = operators["\(feed)|\(agency)|\(window)"] { return r }
            }
            return modes["\(mode)|\(window)"]
        }

        /// How far a live forecast this many minutes ahead is off (interpolated between 5/15/30/60 min;
        /// shrinks to nothing at 0 min).
        func forecastError(mode: String, minutesAhead: Double) -> (Dist, Int)? {
            guard let hs = horizons[mode], let first = hs.first else { return nil }
            let m = max(0, minutesAhead)
            if m <= first.minutes {
                let f = m / first.minutes
                return (Dist(first.error.q.map { $0 * f })!, first.n)
            }
            for (a, b) in zip(hs, hs.dropFirst()) where m <= b.minutes {
                let t = (m - a.minutes) / (b.minutes - a.minutes)
                return (Dist(zip(a.error.q, b.error.q).map { $0 + t * ($1 - $0) })!, min(a.n, b.n))
            }
            return (hs.last!.error, hs.last!.n)
        }
    }

    /// Strips the gzip wrapper and inflates (Apple's ZLIB is raw DEFLATE). nil if not gzip.
    static func gunzip(_ data: Data) -> Data? {
        let b = [UInt8](data)
        guard b.count > 18, b[0] == 0x1f, b[1] == 0x8b, b[2] == 8 else { return nil }
        let flags = b[3]
        var i = 10
        if flags & 4 != 0 { guard b.count > i + 2 else { return nil }; i += 2 + Int(b[i]) + Int(b[i + 1]) << 8 }
        if flags & 8 != 0 { while i < b.count, b[i] != 0 { i += 1 }; i += 1 }
        if flags & 16 != 0 { while i < b.count, b[i] != 0 { i += 1 }; i += 1 }
        if flags & 2 != 0 { i += 2 }
        guard i < b.count - 8 else { return nil }
        let size = Int(b[b.count - 4]) | Int(b[b.count - 3]) << 8 | Int(b[b.count - 2]) << 16 | Int(b[b.count - 1]) << 24
        #if canImport(Darwin)
        let body = Data(b[i..<(b.count - 8)])
        return try? (body as NSData).decompressed(using: .zlib) as Data
        #else
        _ = size
        return nil
        #endif
    }
}

/// Keeps the delay tables of the countries the user plans in. Each country at most once a day;
/// a failed or broken download keeps the old file. Same pattern as `CoverageAtlasStore`.
final class DelayHistoryStore: @unchecked Sendable {
    static let shared = DelayHistoryStore()
    static func remoteURL(_ country: String) -> URL { URL(string: "https://publit.eu/verspaetung/data/\(country).txt.gz")! }

    private let lock = NSLock()
    private var tables: [String: DelayHistory.Table] = [:]
    private var checked: [String: Date] = [:]
    private let dir: URL?

    init(cacheDirectory: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first) {
        dir = cacheDirectory?.appendingPathComponent("delay-history", isDirectory: true)
        if let dir { try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
    }

    func table(country: String?) -> DelayHistory.Table? {
        guard let country else { return nil }
        lock.lock()
        if let t = tables[country] { lock.unlock(); return t }
        lock.unlock()
        guard let dir, let text = try? String(contentsOf: dir.appendingPathComponent("\(country).txt"), encoding: .utf8) else { return nil }
        let t = DelayHistory.Table(text: text)
        guard !t.isEmpty else { return nil }
        lock.lock(); tables[country] = t; lock.unlock()
        return t
    }

    /// For tests and previews.
    func install(_ table: DelayHistory.Table, country: String) {
        lock.lock(); tables[country] = table; lock.unlock()
    }

    /// Accepts a downloaded table only if it parses and is not older than the one we have.
    @discardableResult
    func install(text: String, country: String) -> Bool {
        let new = DelayHistory.Table(text: text)
        guard !new.date.isEmpty, !new.isEmpty else { return false }
        if let old = table(country: country), old.date > new.date { return false }
        lock.lock(); tables[country] = new; lock.unlock()
        if let dir { try? text.write(to: dir.appendingPathComponent("\(country).txt"), atomically: true, encoding: .utf8) }
        return true
    }

    /// Loads the tables for the countries of these routes (background, at most once a day each).
    func refresh(for itineraries: [Itinerary], now: Date = .now) {
        let countries = Set(itineraries.flatMap(\.legs).compactMap { DelayHistory.country(ofId: $0.routeId) })
        for c in countries {
            lock.lock()
            let due = checked[c].map { now.timeIntervalSince($0) > 20 * 3600 } ?? true
            if due { checked[c] = now }
            lock.unlock()
            guard due else { continue }
            Task.detached(priority: .utility) { [weak self] in
                var req = URLRequest(url: Self.remoteURL(c), timeoutInterval: 30)
                req.setValue("Publit", forHTTPHeaderField: "User-Agent")
                guard let (data, resp) = try? await URLSession.shared.data(for: req),
                      (resp as? HTTPURLResponse)?.statusCode == 200,
                      let raw = DelayHistory.gunzip(data) ?? (data.first == UInt8(ascii: "D") ? data : nil),
                      let text = String(data: raw, encoding: .utf8) else { return }
                self?.install(text: text, country: c)
            }
        }
    }
}

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: ÖBB (HAFAS, all of Austria)

/// ÖBB's journey planner backend (the one its app uses): live times for trains, and in many
/// regions buses and trams (VOR, VVT, …), plus construction and disruption notes. Not an
/// official open API: if it changes, rides simply keep their timetable times.
struct HafasSource: LiveSource {
    let name = "ÖBB"
    let horizon: TimeInterval = 6 * 3600
    static let area = GeoBox(minLat: 46.37, maxLat: 49.02, minLon: 9.53, maxLon: 17.17)
    static let endpoint = URL(string: "https://fahrplan.oebb.at/bin/mgate.exe")!
    static let tz = "Europe/Vienna"
    private static let stops = TTLCache<String>(limit: 400)
    private static let boards = TTLCache<[LiveDeparture]>(limit: 120)
    private static let day = J.formatter("yyyyMMdd", tz)
    private static let clock = J.formatter("HHmmss", tz)

    /// Austria's border, roughly: the rectangle alone takes in Munich, Passau, Bratislava and Bolzano.
    static let outline = GeoOutline(points: [
        (9.53, 47.27), (9.60, 47.53), (10.0, 47.58), (10.45, 47.55), (10.9, 47.48), (11.4, 47.58), (12.2, 47.72),
        (12.75, 47.66), (13.0, 47.74), (12.96, 47.86), (12.85, 48.1), (13.03, 48.27), (13.43, 48.46), (13.73, 48.52),
        (13.84, 48.77), (14.7, 48.6), (15.0, 49.02), (15.9, 48.84), (16.9, 48.62), (17.07, 48.12), (17.16, 48.0),
        (16.9, 47.7), (16.65, 47.45), (16.45, 47.0), (16.1, 46.85), (16.0, 46.67), (15.5, 46.63), (14.9, 46.6),
        (14.5, 46.42), (13.7, 46.52), (12.4, 46.65), (12.15, 47.0), (11.6, 46.98), (11.1, 46.78), (10.45, 46.86),
        (10.1, 46.85), (9.85, 47.0), (9.53, 47.06),
    ])

    func covers(_ ride: LiveRide) -> Bool {
        if let tz = ride.tz, tz != Self.tz { return false }
        return Self.area.contains(ride.point) && Self.outline.contains(ride.point)
    }

    func fix(for ride: LiveRide, now: Date) async throws -> LiveFix? {
        let point = ride.point
        let lid = try await Self.stops.value(LatLon.format(point.lat, 4) + "," + LatLon.format(point.lon, 4), ttl: 86_400) {
            try await Self.nearestStop(point)
        }
        guard !lid.isEmpty else { return nil }
        let start = Date(timeIntervalSince1970: (ride.scheduled.timeIntervalSince1970 / 1800).rounded(.down) * 1800 - 120)
        let deps = try await Self.boards.value("\(lid)|\(Int(start.timeIntervalSince1970))", ttl: 45) {
            try await Self.board(lid, from: start)
        }
        return LiveMatch.best(for: ride, in: deps).map { LiveMatch.fix($0, source: name) }
    }

    static func body(_ method: String, _ req: [String: Any]) -> Data {
        let body: [String: Any] = [
            "lang": "de", "svcReqL": [["meth": method, "req": req]],
            "client": ["id": "OEBB", "type": "IPH", "name": "oebbPROD-ADHOC", "v": "6030600"],
            "ext": "OEBB.1", "ver": "1.57", "auth": ["type": "AID", "aid": "OWDL4fE4ixNiPBBm"],
        ]
        return (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
    }

    static func call(_ body: Data) async throws -> [String: Any] {
        var r = LiveHTTP.request(endpoint)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = body
        let raw = try await LiveHTTP.json(r)
        let root = J.dict(raw)
        let first = J.dict(J.list(root["svcResL"]).first)
        guard J.str(first["err"]) == "OK" else { throw URLError(.cannotParseResponse) }
        return J.dict(first["res"])
    }

    /// "" when there is no stop within 300 m (cached like a hit: no point asking again).
    static func nearestStop(_ p: LatLon) async throws -> String {
        let res = try await call(body("LocGeoPos", [
            "ring": ["cCrd": ["x": Int(p.lon * 1e6), "y": Int(p.lat * 1e6)], "maxDist": 300],
            "getPOIs": false, "getStops": true, "maxLoc": 3,
        ]))
        return parseNearest(res) ?? ""
    }

    static func parseNearest(_ res: [String: Any]) -> String? {
        J.list(res["locL"]).map { J.dict($0) }
            .min { (J.int($0["dist"]) ?? .max) < (J.int($1["dist"]) ?? .max) }
            .flatMap { J.str($0["lid"]) }
    }

    static func board(_ lid: String, from start: Date) async throws -> [LiveDeparture] {
        let res = try await call(body("StationBoard", [
            "type": "DEP", "date": day.string(from: start), "time": clock.string(from: start),
            "stbLoc": ["lid": lid], "dur": 60, "maxJny": 80,
        ]))
        return parseBoard(res)
    }

    static func parseBoard(_ res: [String: Any]) -> [LiveDeparture] {
        let common = J.dict(res["common"])
        let prods = J.list(common["prodL"]).map { J.dict($0) }
        let hims = J.list(common["himL"]).map { J.dict($0) }
        return J.list(res["jnyL"]).map { J.dict($0) }.compactMap { j in
            let s = J.dict(j["stbStop"])
            let date = J.str(j["date"])
            let offset = J.int(s["dTZOffset"])
            guard let scheduled = Self.clockTime(date, J.str(s["dTimeS"]), offset: offset) else { return nil }
            let prodIndex = J.int(j["prodX"]) ?? J.int(s["dProdX"]) ?? -1
            let prod = prods.indices.contains(prodIndex) ? prods[prodIndex] : [:]
            let ctx = J.dict(prod["prodCtx"])
            let lines = [J.str(prod["name"]), J.str(prod["number"]), J.str(ctx["line"]), J.str(ctx["num"])]
                .compactMap { $0?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let cls = J.int(prod["cls"])
            let alerts: [Alert] = J.list(j["msgL"]).map { J.dict($0) }.compactMap { m in
                guard J.str(m["type"]) == "HIM", let x = J.int(m["himX"]), hims.indices.contains(x) else { return nil }
                // Summary headers ("SUM_GLB_…") are network-wide notes, not about this ride.
                if J.list(m["tagL"]).compactMap { J.str($0) }.contains(where: { $0.contains("GLB") }) { return nil }
                let him = hims[x]
                if let mask = J.int(him["prod"]), let cls, mask & cls == 0 { return nil }
                return alert(him)
            }
            let track = J.str(J.dict(s["dPltfR"])["txt"]) ?? J.str(s["dPlatfR"]) ?? J.str(J.dict(s["dPltfS"])["txt"]) ?? J.str(s["dPlatfS"])
            return LiveDeparture(lines: lines, destination: J.str(j["dirTxt"]), scheduled: scheduled,
                                 expected: Self.clockTime(date, J.str(s["dTimeR"]), offset: offset),
                                 cancelled: J.bool(s["dCncl"]) || J.bool(j["isCncl"]), track: track, alerts: alerts)
        }
    }

    static func alert(_ him: [String: Any]) -> Alert? {
        let head = J.plain(J.str(him["head"]) ?? "")
        let text = J.plain(J.str(him["text"]) ?? "")
        guard !head.isEmpty || !text.isEmpty else { return nil }
        let start = Self.clockTime(J.str(him["sDate"]), J.str(him["sTime"]), offset: nil)
        let end = Self.clockTime(J.str(him["eDate"]), J.str(him["eTime"]), offset: nil)
        let prio = J.int(him["prio"]) ?? 100
        return Alert(headerText: head.isEmpty ? text : head, descriptionText: head.isEmpty ? "" : text, url: nil,
                     severityLevel: prio <= 25 ? "SEVERE" : "WARNING",
                     impactPeriod: start == nil && end == nil ? nil : [AlertPeriod(start: start, end: end)])
    }

    /// HAFAS time "HHMMSS" or "DDHHMMSS" (days after `date`), local with `offset` minutes from UTC.
    static func clockTime(_ date: String?, _ value: String?, offset: Int?) -> Date? {
        guard let date, date.count == 8, let value, value.count == 6 || value.count == 8,
              let y = Int(date.prefix(4)), let mo = Int(date.dropFirst(4).prefix(2)), let d = Int(date.suffix(2)) else { return nil }
        let digits = value.count == 8 ? String(value.suffix(6)) : value
        let days = value.count == 8 ? Int(value.prefix(2)) ?? 0 : 0
        guard let h = Int(digits.prefix(2)), let mi = Int(digits.dropFirst(2).prefix(2)), let s = Int(digits.suffix(2)) else { return nil }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        guard let midnight = utc.date(from: DateComponents(year: y, month: mo, day: d)) else { return nil }
        let local = midnight.addingTimeInterval(TimeInterval(days * 86_400 + h * 3600 + mi * 60 + s))
        let seconds = offset.map { $0 * 60 } ?? (TimeZone(identifier: tz)?.secondsFromGMT(for: local) ?? 3600)
        return local.addingTimeInterval(TimeInterval(-seconds))
    }
}

// MARK: Wiener Linien (Vienna)

/// Wiener Linien open data (CC BY 4.0, Stadt Wien – data.wien.gv.at): live countdowns of
/// U-Bahn, tram and bus, and current disruptions.
struct WienerLinienSource: LiveSource {
    let name = "Wiener Linien"
    let horizon: TimeInterval = 70 * 60
    static let area = GeoBox(minLat: 48.11, maxLat: 48.33, minLon: 16.18, maxLon: 16.58)
    private static let boards = TTLCache<[LiveDeparture]>(limit: 80)
    private static let stamp = J.formatter("yyyy-MM-dd'T'HH:mm:ss.SSSZ", "Europe/Vienna")

    func covers(_ ride: LiveRide) -> Bool { Self.area.contains(ride.point) }

    func fix(for ride: LiveRide, now: Date) async throws -> LiveFix? {
        guard let diva = ride.stopId.flatMap(Self.diva) else { return nil }
        let deps = try await Self.boards.value(diva, ttl: 30) { try await Self.monitor(diva) }
        return LiveMatch.best(for: ride, in: deps).map { LiveMatch.fix($0, source: name) }
    }

    /// Transitous' Vienna stop IDs end in the operator's stop number: "…Pat:49:1198" is DIVA 60201198.
    static func diva(_ stopId: String) -> String? {
        guard let r = stopId.range(of: ":49:", options: .backwards) else { return nil }
        let digits = stopId[r.upperBound...].prefix { $0.isASCII && $0.isNumber }
        guard let n = Int(digits), n > 0, n < 100_000 else { return nil }
        return String(60_200_000 + n)
    }

    static func monitor(_ diva: String) async throws -> [LiveDeparture] {
        var c = URLComponents(string: "https://www.wienerlinien.at/ogd_realtime/monitor")!
        c.queryItems = [URLQueryItem(name: "diva", value: diva),
                        URLQueryItem(name: "activateTrafficInfo", value: "stoerungkurz"),
                        URLQueryItem(name: "activateTrafficInfo", value: "stoerunglang")]
        let raw = try await LiveHTTP.json(LiveHTTP.request(c.url!))
        return parseMonitor(J.dict(raw))
    }

    static func parseMonitor(_ root: [String: Any]) -> [LiveDeparture] {
        let data = J.dict(root["data"])
        let infos: [(lines: [String], alert: Alert)] = J.list(data["trafficInfos"]).map { J.dict($0) }.compactMap { info in
            guard J.int(info["refTrafficInfoCategoryId"]) != 1 else { return nil }   // lifts: not about rides
            let attrs = J.dict(info["attributes"])
            let lines = J.list(info["relatedLines"]).compactMap { J.str($0) } + J.list(attrs["relatedLines"]).compactMap { J.str($0) }
            let title = J.str(info["title"]) ?? ""
            let text = [J.str(info["description"]), J.str(attrs["reason"])].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
            guard !title.isEmpty || !text.isEmpty else { return nil }
            let t = J.dict(info["time"])
            let start = J.str(t["start"]).flatMap { stamp.date(from: $0) }
            let end = J.str(t["end"]).flatMap { stamp.date(from: $0) }
            return (lines, Alert(headerText: title.isEmpty ? text : title, descriptionText: title.isEmpty ? "" : text, url: nil,
                                 severityLevel: "WARNING",
                                 impactPeriod: start == nil && end == nil ? nil : [AlertPeriod(start: start, end: end)]))
        }
        var out: [LiveDeparture] = []
        for monitor in J.list(data["monitors"]).map { J.dict($0) } {
            for line in J.list(monitor["lines"]).map { J.dict($0) } {
                guard let name = J.str(line["name"]) else { continue }
                let alerts = infos.filter { $0.lines.contains(name) }.map { $0.alert }
                for dep in J.list(J.dict(line["departures"])["departure"]).map { J.dict($0) } {
                    let t = J.dict(dep["departureTime"])
                    guard let planned = J.str(t["timePlanned"]).flatMap({ stamp.date(from: $0) }) else { continue }
                    let vehicle = J.dict(dep["vehicle"])
                    out.append(LiveDeparture(lines: [J.str(vehicle["name"]) ?? name],
                                             destination: J.str(vehicle["towards"]) ?? J.str(line["towards"]),
                                             scheduled: planned, expected: J.str(t["timeReal"]).flatMap { stamp.date(from: $0) },
                                             alerts: alerts))
                }
            }
        }
        return out
    }
}

// MARK: ACTV (Venice: vaporetto and bus)

/// ACTV's live departure screens (oraritemporeale.actv.it), unofficial: vaporetti and buses
/// in Venice, Lido and Mestre.
struct ACTVSource: LiveSource {
    let name = "ACTV"
    let horizon: TimeInterval = 90 * 60
    static let area = GeoBox(minLat: 45.2, maxLat: 45.7, minLon: 12.0, maxLon: 12.7)
    static let tz = "Europe/Rome"
    static let browserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Publit"

    struct Stop: Sendable, Hashable { let id: String; let point: LatLon }
    private static let stopLists = TTLCache<[Stop]>(limit: 4)
    private static let boards = TTLCache<[LiveDeparture]>(limit: 80)

    func covers(_ ride: LiveRide) -> Bool { Self.area.contains(ride.point) }

    func fix(for ride: LiveRide, now: Date) async throws -> LiveFix? {
        let net = ride.mode == "FERRY" ? "nav" : "aut"
        let stops = try await Self.stopLists.value(net, ttl: 86_400) { try await Self.stops(net) }
        guard let stop = stops.min(by: { $0.point.distance(to: ride.point) < $1.point.distance(to: ride.point) }),
              stop.point.distance(to: ride.point) < 150 else { return nil }
        let deps = try await Self.boards.value(stop.id, ttl: 30) { try await Self.passages(net, stop.id) }
        return LiveMatch.best(for: ride, in: deps, tolerance: 150).map { LiveMatch.fix($0, source: name) }
    }

    static func get(_ url: URL) async throws -> Any {
        try await LiveHTTP.json(LiveHTTP.request(url, userAgent: browserAgent))
    }

    static func stops(_ net: String) async throws -> [Stop] {
        let raw = try await get(URL(string: "https://oraritemporeale.actv.it/\(net)/backend/page/stops")!)
        return parseStops(raw)
    }

    static func parseStops(_ root: Any) -> [Stop] {
        J.list(root).map { J.dict($0) }.compactMap { s in
            guard let id = J.str(s["name"]), let lat = J.double(s["latitude"]), let lon = J.double(s["longitude"]) else { return nil }
            let p = LatLon(lat: lat, lon: lon)
            return p.isValidCoordinate ? Stop(id: id, point: p) : nil
        }
    }

    static func passages(_ net: String, _ id: String) async throws -> [LiveDeparture] {
        let path = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let raw = try await get(URL(string: "https://oraritemporeale.actv.it/\(net)/backend/passages/\(path)")!)
        return parsePassages(raw, now: Date())
    }

    static func parsePassages(_ root: Any, now: Date) -> [LiveDeparture] {
        J.list(root).map { J.dict($0) }.compactMap { p in
            guard let line = J.str(p["line"]) else { return nil }
            let shown = J.str(p["time"]) ?? ""
            let first = J.str(J.dict(J.list(p["timingPoints"]).first)["time"])
            let scheduled = first.flatMap { clock($0, near: now) }
            let live = J.bool(p["real"]) ? (countdown(shown, now: now) ?? clock(shown, near: now)) : nil
            guard scheduled != nil || live != nil else { return nil }
            return LiveDeparture(lines: [line], destination: J.str(p["destination"]), scheduled: scheduled, expected: live)
        }
    }

    /// "6'" → in 6 minutes.
    static func countdown(_ s: String, now: Date) -> Date? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard t.hasSuffix("'"), let m = Int(t.dropLast()) else { return nil }
        return now.addingTimeInterval(TimeInterval(m * 60))
    }

    /// "23:55" → the nearest such time around `now` in Venice.
    static func clock(_ s: String, near now: Date) -> Date? {
        let parts = s.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: tz)!
        guard let today = cal.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: now) else { return nil }
        if today.timeIntervalSince(now) > 12 * 3600 { return today.addingTimeInterval(-86_400) }
        if now.timeIntervalSince(today) > 12 * 3600 { return today.addingTimeInterval(86_400) }
        return today
    }
}

// MARK: SL (Stockholm)

/// Storstockholms Lokaltrafik's open departures API (no key): metro, commuter trains,
/// trams, buses and boats, with deviations.
struct SLSource: LiveSource {
    let name = "SL"
    let horizon: TimeInterval = 60 * 60
    static let area = GeoBox(minLat: 58.7, maxLat: 60.3, minLon: 17.2, maxLon: 19.3)
    struct Site: Sendable, Hashable { let id: Int; let point: LatLon }
    private static let sites = TTLCache<[Site]>(limit: 2)
    private static let boards = TTLCache<[LiveDeparture]>(limit: 80)
    private static let stamp = J.formatter("yyyy-MM-dd'T'HH:mm:ss", "Europe/Stockholm")

    func covers(_ ride: LiveRide) -> Bool { Self.area.contains(ride.point) }

    func fix(for ride: LiveRide, now: Date) async throws -> LiveFix? {
        let all = try await Self.sites.value("sites", ttl: 7 * 86_400) {
            let raw = try await LiveHTTP.json(LiveHTTP.request(URL(string: "https://transport.integration.sl.se/v1/sites?expand=false")!))
            return Self.parseSites(raw)
        }
        guard let site = all.min(by: { $0.point.distance(to: ride.point) < $1.point.distance(to: ride.point) }),
              site.point.distance(to: ride.point) < 250 else { return nil }
        let deps = try await Self.boards.value(String(site.id), ttl: 30) {
            let raw = try await LiveHTTP.json(LiveHTTP.request(URL(string: "https://transport.integration.sl.se/v1/sites/\(site.id)/departures")!))
            return Self.parseDepartures(J.dict(raw))
        }
        return LiveMatch.best(for: ride, in: deps).map { LiveMatch.fix($0, source: name) }
    }

    static func parseSites(_ root: Any) -> [Site] {
        J.list(root).map { J.dict($0) }.compactMap { s in
            guard let id = J.int(s["id"]), let lat = J.double(s["lat"]), let lon = J.double(s["lon"]) else { return nil }
            return Site(id: id, point: LatLon(lat: lat, lon: lon))
        }
    }

    static func deviationAlerts(_ list: Any?) -> [Alert] {
        J.list(list).map { J.dict($0) }.compactMap { d in
            guard let text = J.str(d["message"]), !text.isEmpty else { return nil }
            let level = J.int(d["importance_level"]) ?? 0
            return Alert(headerText: text, descriptionText: "", url: nil, severityLevel: level >= 7 ? "SEVERE" : "WARNING")
        }
    }

    static func parseDepartures(_ root: [String: Any]) -> [LiveDeparture] {
        let stopWide: [(lines: [String], alert: Alert)] = J.list(root["stop_deviations"]).map { J.dict($0) }.compactMap { d in
            guard let alert = deviationAlerts([d]).first else { return nil }
            let lines = J.list(J.dict(d["scope"])["lines"]).map { J.dict($0) }.compactMap { J.str($0["designation"]) }
            return (lines, alert)
        }
        return J.list(root["departures"]).map { J.dict($0) }.compactMap { d in
            let line = J.dict(d["line"])
            guard let designation = J.str(line["designation"]),
                  let scheduled = J.str(d["scheduled"]).flatMap({ stamp.date(from: $0) }) else { return nil }
            let state = J.str(d["state"]) ?? ""
            let alerts = deviationAlerts(d["deviations"]) + stopWide.filter { $0.lines.isEmpty || $0.lines.contains(designation) }.map { $0.alert }
            return LiveDeparture(lines: [designation], destination: J.str(d["destination"]), scheduled: scheduled,
                                 expected: state == "NOTEXPECTED" ? nil : J.str(d["expected"]).flatMap { stamp.date(from: $0) },
                                 cancelled: state == "CANCELLED", track: J.str(J.dict(d["stop_point"])["designation"]),
                                 alerts: alerts)
        }
    }
}

// MARK: TfL (London line status)

/// Transport for London line status (Powered by TfL Open Data): delays, closures and
/// part suspensions on Underground, Overground, DLR, Elizabeth line and trams.
struct TfLStatusSource: LiveSource {
    let name = "TfL"
    let horizon: TimeInterval = 4 * 3600
    static let area = GeoBox(minLat: 51.28, maxLat: 51.70, minLon: -0.52, maxLon: 0.34)
    struct Line: Sendable, Hashable { let names: [String]; let alerts: [Alert] }
    private static let status = TTLCache<[Line]>(limit: 2)
    private static let stamp: ISO8601DateFormatter = ISO8601DateFormatter()

    func covers(_ ride: LiveRide) -> Bool { Self.area.contains(ride.point) }

    func fix(for ride: LiveRide, now: Date) async throws -> LiveFix? {
        guard ride.mode != "BUS" && ride.mode != "COACH" else { return nil }
        let lines = try await Self.status.value("status", ttl: 90) {
            let raw = try await LiveHTTP.json(LiveHTTP.request(URL(string: "https://api.tfl.gov.uk/Line/Mode/tube,overground,dlr,elizabeth-line,tram/Status")!))
            return Self.parseStatus(raw)
        }
        guard let line = lines.first(where: { LiveMatch.sameLine(ride.lines, $0.names) }), !line.alerts.isEmpty else { return nil }
        return LiveFix(alerts: line.alerts, source: name)
    }

    static func parseStatus(_ root: Any) -> [Line] {
        J.list(root).map { J.dict($0) }.compactMap { l in
            guard let name = J.str(l["name"]) else { return nil }
            let alerts: [Alert] = J.list(l["lineStatuses"]).map { J.dict($0) }.compactMap { s in
                let severity = J.int(s["statusSeverity"]) ?? 10
                guard ![10, 18, 19].contains(severity), let reason = J.str(s["reason"]), !reason.isEmpty else { return nil }
                let periods = J.list(s["validityPeriods"]).map { J.dict($0) }.map {
                    AlertPeriod(start: J.str($0["fromDate"]).flatMap { stamp.date(from: $0) },
                                end: J.str($0["toDate"]).flatMap { stamp.date(from: $0) })
                }
                let effect: String? = [1, 2, 16, 20].contains(severity) ? "NO_SERVICE" : severity == 15 ? "DETOUR"
                    : severity == 6 ? "SIGNIFICANT_DELAYS" : [3, 4, 5, 7, 11, 14].contains(severity) ? "REDUCED_SERVICE" : nil
                return Alert(headerText: "\(name): \(J.str(s["statusSeverityDescription"]) ?? "")",
                             descriptionText: reason.trimmingCharacters(in: .whitespaces), url: "https://tfl.gov.uk/tube-dlr-overground/status/",
                             effect: effect, severityLevel: severity <= 6 || severity == 20 ? "SEVERE" : "WARNING",
                             impactPeriod: periods.isEmpty ? nil : periods)
            }
            return Line(names: [name, J.str(l["id"]) ?? name], alerts: alerts)
        }
    }
}

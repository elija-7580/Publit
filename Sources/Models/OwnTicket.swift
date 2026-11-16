import Foundation

/// Where a stop is, read from its Transitous stop ID: the national stop ID after the feed name
/// ("de-DELFI_at:45:50002" → Austria, Salzburg), else the feed's country ("de-VBN_000000100063" → Germany).
struct StopArea: Equatable, Sendable {
    /// ISO country code, lower case: "de", "at", "ch".
    let country: String
    /// Austrian state by the stop ID's second part: 41 Burgenland, 42 Carinthia, 43 Lower Austria,
    /// 44 Upper Austria, 45 Salzburg, 46 Styria, 47 Tyrol, 48 Vorarlberg, 49 Vienna.
    let state: Int?

    init(country: String, state: Int? = nil) {
        self.country = country
        self.state = state
    }

    init?(stopId: String?) {
        guard let id = stopId, !id.isEmpty else { return nil }
        // National IDs (DHID, SLOID) start with the country: "at:45:50002", "ch:1:sloid:3000".
        for part in id.split(separator: "_").dropFirst() {
            let f = part.split(separator: ":", omittingEmptySubsequences: false)
            guard f.count >= 2, f[0].count == 2, f[0].allSatisfy({ $0.isASCII && $0.isLowercase }) else { continue }
            let state = f[0] == "at" ? Int(f[1]).flatMap { (41...49).contains($0) ? $0 : nil } : nil
            self.init(country: String(f[0]), state: state)
            return
        }
        // Feed names start with the country: "de-VBN", "at-Railway-Current-Reference-Data-2026".
        let feed = id.prefix { $0 != "_" }
        let cc = feed.prefix(2)
        guard feed.count > 3, feed.dropFirst(2).first == "-", cc.allSatisfy({ $0.isASCII && $0.isLowercase }) else { return nil }
        self.init(country: String(cc))
    }
}

/// Tickets that cover a whole country or region. With one chosen in Route options, routes only use
/// rides it covers: no ICE with a Deutschlandticket, no train into Vienna with the VOR Region ticket.
/// Checked per ride by mode, train type and where it starts and ends; tourist and mountain railways,
/// supplements and single exceptions are not modelled.
enum OwnTicket: String, CaseIterable, Codable, Identifiable, Sendable {
    case deutschlandticket, bahncard100
    case klimaticket, vorMetropolregion, vorRegion, wienJahreskarte
    case klimaticketOOE, klimaticketSalzburg, klimaticketTirol, klimaticketSteiermark, klimaticketKaernten, klimaticketVorarlberg
    case generalabonnement

    var id: String { rawValue }

    enum Country: String, CaseIterable, Identifiable, Sendable {
        case de, at, ch
        var id: String { rawValue }
        /// "Germany", "Österreich" … in the app language.
        var title: String {
            Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en").localizedString(forRegionCode: rawValue.uppercased()) ?? rawValue.uppercased()
        }
    }

    var country: Country {
        switch self {
        case .deutschlandticket, .bahncard100: return .de
        case .generalabonnement: return .ch
        default: return .at
        }
    }

    static func tickets(in country: Country) -> [OwnTicket] { allCases.filter { $0.country == country } }

    /// Product name, the same in every language.
    var title: String {
        switch self {
        case .deutschlandticket: return "Deutschlandticket"
        case .bahncard100: return "BahnCard 100"
        case .klimaticket: return "KlimaTicket Ö"
        case .vorMetropolregion: return "KlimaTicket MetropolRegion"
        case .vorRegion: return "KlimaTicket Region"
        case .wienJahreskarte: return "Jahreskarte Wien"
        case .klimaticketOOE: return "KlimaTicket OÖ"
        case .klimaticketSalzburg: return "KlimaTicket Salzburg"
        case .klimaticketTirol: return "KlimaTicket Tirol"
        case .klimaticketSteiermark: return "KlimaTicket Steiermark"
        case .klimaticketKaernten: return "KlimaTicket Kärnten"
        case .klimaticketVorarlberg: return "KlimaTicket VMOBIL"
        case .generalabonnement: return "GA"
        }
    }

    /// What it covers, in a few words.
    var detail: String {
        switch self {
        case .deutschlandticket: return L10n.t("Local and regional transport in Germany")
        case .bahncard100: return L10n.t("DB trains and local transport in Germany")
        case .klimaticket: return L10n.t("All public transport in Austria")
        case .vorMetropolregion: return L10n.t("Vienna, Lower Austria and Burgenland")
        case .vorRegion: return L10n.t("Lower Austria and Burgenland, without Vienna")
        case .wienJahreskarte: return L10n.t("Vienna")
        case .klimaticketOOE: return L10n.t("Upper Austria")
        case .klimaticketSalzburg: return L10n.t("Salzburg")
        case .klimaticketTirol: return L10n.t("Tyrol")
        case .klimaticketSteiermark: return L10n.t("Styria")
        case .klimaticketKaernten: return L10n.t("Carinthia")
        case .klimaticketVorarlberg: return L10n.t("Vorarlberg")
        case .generalabonnement: return L10n.t("All public transport in Switzerland")
        }
    }

    /// Austrian states a regional ticket covers (see `StopArea.state`).
    var states: Set<Int>? {
        switch self {
        case .vorMetropolregion: return [41, 43, 49]
        case .vorRegion: return [41, 43]
        case .wienJahreskarte: return [49]
        case .klimaticketOOE: return [44]
        case .klimaticketSalzburg: return [45]
        case .klimaticketTirol: return [47]
        case .klimaticketSteiermark: return [46]
        case .klimaticketKaernten: return [42]
        case .klimaticketVorarlberg: return [48]
        default: return nil
        }
    }

    // MARK: - Modes and trains

    /// MOTIS modes no ticket here covers: planes, long-distance coaches, night trains (reservation or couchette).
    static let alwaysExcludedModes: Set<String> = ["COACH", "AIRPLANE", "NIGHT_RAIL"]
    /// The Deutschlandticket leaves out long-distance trains as well.
    static let longDistanceModes: Set<String> = ["HIGHSPEED_RAIL", "LONG_DISTANCE"]
    /// Long-distance trains by line name, for feeds that file them as plain RAIL.
    static let longDistanceLines: Set<String> = ["ICE", "IC", "EC", "ECE", "FLX", "NJ", "EN", "TGV", "RJ", "RJX", "ES", "EST", "WB"]

    /// MOTIS modes the ticket never covers; left out of the search when it is the only ticket.
    var excludedModes: Set<String> {
        self == .deutschlandticket ? Self.alwaysExcludedModes.union(Self.longDistanceModes) : Self.alwaysExcludedModes
    }

    /// Modes to leave out of the search: those none of the chosen tickets covers.
    static func excludedModes(_ tickets: Set<OwnTicket>) -> Set<String> {
        tickets.reduce(into: Optional<Set<String>>.none) { acc, t in
            acc = acc.map { $0.intersection(t.excludedModes) } ?? t.excludedModes
        } ?? []
    }

    /// A long-distance train (ICE, IC, RJX, FlixTrain …) by mode, line name or operator.
    static func isLongDistance(_ leg: Leg) -> Bool {
        if longDistanceModes.contains(leg.mode) || leg.mode == "NIGHT_RAIL" { return true }
        guard ModeGroup.of(leg.mode) == .train else { return false }
        if isFlix(leg) { return true }
        for name in [leg.routeShortName, leg.displayName].compactMap({ $0?.uppercased() }) {
            if longDistanceLines.contains(String(name.prefix { $0.isLetter })) { return true }
        }
        return false
    }

    private static func isFlix(_ leg: Leg) -> Bool { leg.agencyName?.lowercased().contains("flix") == true }

    /// Rides with their own fares in Austria: City Airport Train, Vienna Airport Lines.
    private static func isAustrianExtraFare(_ leg: Leg) -> Bool {
        let agency = leg.agencyName?.lowercased() ?? ""
        if agency.contains("city air terminal") || agency.contains("city airport train") { return true }
        return (leg.routeShortName ?? "").uppercased().hasPrefix("VAB")
    }

    // MARK: - Coverage

    /// The Deutschlandticket's own check by mode and train alone (no stop IDs needed).
    static func coversByMode(_ leg: Leg) -> Bool {
        !leg.isTransit || (!alwaysExcludedModes.contains(leg.mode) && !isLongDistance(leg))
    }

    func covers(_ leg: Leg) -> Bool {
        guard leg.isTransit else { return true }
        if Self.alwaysExcludedModes.contains(leg.mode) { return false }
        let a = StopArea(stopId: leg.from.stopId), b = StopArea(stopId: leg.to.stopId)
        switch self {
        case .deutschlandticket:
            guard Self.coversByMode(leg) else { return false }
            // Unknown stops: the mode decides. Otherwise one end in Germany: regional trains to
            // Salzburg, Kufstein or Basel count, a bus in Vienna does not.
            if a == nil && b == nil { return true }
            return a?.country == "de" || b?.country == "de"
        case .bahncard100:
            if Self.deutschlandticket.covers(leg) { return true }
            // DB long-distance trains within Germany (not FlixTrain).
            return ModeGroup.of(leg.mode) == .train && !Self.isFlix(leg) && a?.country == "de" && b?.country == "de"
        case .generalabonnement:
            if Self.isFlix(leg) { return false }
            return Self.isSwiss(a) && Self.isSwiss(b)
        case .klimaticket:
            if Self.isFlix(leg) || Self.isAustrianExtraFare(leg) { return false }
            return a?.country == "at" && b?.country == "at"
        default:
            guard let states else { return false }
            if Self.isFlix(leg) || Self.isAustrianExtraFare(leg) { return false }
            return a?.state.map(states.contains) == true && b?.state.map(states.contains) == true
        }
    }

    private static func isSwiss(_ a: StopArea?) -> Bool { a?.country == "ch" || a?.country == "li" }

    /// Every ride covered by at least one of the tickets. No tickets: every route.
    static func covers(_ it: Itinerary, with tickets: Set<OwnTicket>) -> Bool {
        tickets.isEmpty || it.legs.allSatisfy { leg in tickets.contains { $0.covers(leg) } }
    }

    // MARK: - Text

    /// "Deutschlandticket" or "KlimaTicket Ö, GA" in the order of the list.
    static func summary(_ tickets: Set<OwnTicket>) -> String {
        let chosen = allCases.filter(tickets.contains)
        return chosen.count > 2 ? L10n.f("%lld tickets", chosen.count) : chosen.map(\.title).joined(separator: ", ")
    }

    /// The ticket a saved ticket or pass is, by its title ("D-Ticket", "KlimaTicket Ö Classic", "GA 2. Klasse").
    static func recognise(_ title: String) -> OwnTicket? {
        let t = title.lowercased().replacingOccurrences(of: "-", with: " ")
        let words = Set(t.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        if t.contains("deutschlandticket") || t.contains("deutschland ticket") || t.contains("d ticket") { return .deutschlandticket }
        if t.contains("bahncard 100") || words.contains("bc100") { return .bahncard100 }
        if t.contains("metropolregion") { return .vorMetropolregion }
        if t.contains("klimaticket region") { return .vorRegion }
        if t.contains("jahreskarte") && (t.contains("wien") || t.contains("wiener linien")) { return .wienJahreskarte }
        if t.contains("vmobil") || t.contains("klimaticket vorarlberg") { return .klimaticketVorarlberg }
        if t.contains("klimaticket") {
            if t.contains("oö") || t.contains("oberösterreich") { return .klimaticketOOE }
            if t.contains("salzburg") { return .klimaticketSalzburg }
            if t.contains("tirol") { return .klimaticketTirol }
            if t.contains("steiermark") { return .klimaticketSteiermark }
            if t.contains("kärnten") { return .klimaticketKaernten }
            return .klimaticket
        }
        if t.contains("generalabonnement") || t.contains("general abo") || t.contains("abonnement général")
            || t.contains("abbonamento generale") || t == "ga" || t.hasPrefix("ga ") { return .generalabonnement }
        return nil
    }
}

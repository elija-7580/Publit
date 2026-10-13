import Foundation

/// Operators the recogniser knows by name or by UIC company code. Colours are approximations of
/// the operators' own colours and only a starting point; the user picks the final look.
enum KnownOperators {
    struct Operator: Sendable {
        let name: String
        let patterns: [String]
        let color: String
        let symbol: TicketPass.Symbol
        let uicCode: String?
        /// Wikidata item, for the logo (Wikimedia Commons) and the website.
        var wikidata: String? = nil
        var domain: String? = nil
    }

    static let all: [Operator] = [
        Operator(name: "ÖBB", patterns: ["ÖBB", "OEBB", "Österreichische Bundesbahnen", "oebb.at"], color: "D70015", symbol: .train, uicCode: "1181", wikidata: "Q83822", domain: "oebb.at"),
        Operator(name: "Deutsche Bahn", patterns: ["Deutsche Bahn", "DB Fernverkehr", "DB Regio", "DB Navigator", "bahn.de"], color: "EC0016", symbol: .train, uicCode: "1080", wikidata: "Q9322", domain: "bahn.de"),
        Operator(name: "SBB", patterns: ["SBB CFF FFS", "SBB", "sbb.ch"], color: "D70015", symbol: .train, uicCode: "1185", wikidata: "Q83835", domain: "sbb.ch"),
        Operator(name: "WESTbahn", patterns: ["WESTbahn"], color: "00578A", symbol: .train, uicCode: nil, wikidata: "Q266280", domain: "westbahn.at"),
        Operator(name: "Wiener Linien", patterns: ["Wiener Linien", "wienerlinien"], color: "D70015", symbol: .metro, uicCode: nil, wikidata: "Q668849", domain: "wienerlinien.at"),
        Operator(name: "MVV", patterns: ["MVV", "Münchner Verkehrs"], color: "0065AE", symbol: .metro, uicCode: nil, wikidata: "Q259000", domain: "mvv-muenchen.de"),
        Operator(name: "BVG", patterns: ["BVG", "Berliner Verkehrsbetriebe"], color: "F0D722", symbol: .metro, uicCode: nil, wikidata: "Q99633", domain: "bvg.de"),
        Operator(name: "Trenitalia", patterns: ["Trenitalia"], color: "C8102E", symbol: .train, uicCode: "1183", wikidata: "Q286650", domain: "trenitalia.com"),
        Operator(name: "SNCF", patterns: ["SNCF", "TGV INOUI", "OUIGO"], color: "8C1D5A", symbol: .train, uicCode: "1187", wikidata: "Q13646", domain: "sncf-connect.com"),
        Operator(name: "NS", patterns: ["NS International", "Nederlandse Spoorwegen"], color: "FFC917", symbol: .train, uicCode: "1184", wikidata: "Q23076", domain: "ns.nl"),
        Operator(name: "SNCB", patterns: ["SNCB", "NMBS"], color: "0069B4", symbol: .train, uicCode: "1188", wikidata: "Q524255", domain: "belgiantrain.be"),
        Operator(name: "CFL", patterns: ["CFL", "Chemins de fer luxembourgeois"], color: "B5121B", symbol: .train, uicCode: "1182", wikidata: "Q525359", domain: "cfl.lu"),
        Operator(name: "ČD", patterns: ["České dráhy", "Ceske drahy", "ČD"], color: "0B4EA2", symbol: .train, uicCode: "1154", wikidata: "Q304944", domain: "cd.cz"),
        Operator(name: "Renfe", patterns: ["Renfe"], color: "6C2C91", symbol: .train, uicCode: "1071", wikidata: "Q2476154", domain: "renfe.com"),
        Operator(name: "RegioJet", patterns: ["RegioJet"], color: "FECB00", symbol: .train, uicCode: nil, wikidata: "Q221186", domain: "regiojet.com"),
        Operator(name: "FlixBus", patterns: ["FlixBus", "FlixTrain"], color: "73D700", symbol: .bus, uicCode: nil, wikidata: "Q1881378", domain: "flixbus.com"),
    ]

    static func find(_ name: String) -> Operator? {
        let folded = TicketTextParser.fold(name)
        return all.first { $0.name == name || TicketTextParser.fold($0.name) == folded }
            ?? all.first { op in op.patterns.contains { TicketTextParser.matches($0, in: name) } }
    }

    static func uic(_ code: String) -> Operator? { all.first { $0.uicCode == code } }
}

/// What the recogniser read from a ticket. Every field is a suggestion the user checks.
struct TicketDraft: Equatable, Sendable {
    var title: String?
    var operatorName: String?
    var category: TicketPass.Category?
    var symbol: TicketPass.Symbol?
    var origin: String?
    var destination: String?
    var passenger: String?
    var travelClass: String?
    var price: String?
    var reference: String?
    var validFrom: Date?
    var validUntil: Date?
}

extension TicketPass {
    init(draft: TicketDraft, barcode: Barcode?, now: Date = .now) {
        let category = draft.category ?? .single
        self.init(title: draft.title ?? "", operatorName: draft.operatorName, category: category,
                  symbol: draft.symbol ?? .ticket, origin: draft.origin, destination: draft.destination,
                  passenger: draft.passenger, travelClass: draft.travelClass, price: draft.price,
                  reference: draft.reference, validFrom: draft.validFrom, validUntil: draft.validUntil,
                  barcode: barcode, style: PassStyle.suggested(forOperator: draft.operatorName) ?? .standard,
                  createdAt: now)
    }
}

/// Reads ticket details from recognised text lines, entirely on the device. Rules, not guesses:
/// a field stays empty when no label or pattern supports it. Covers common German, English,
/// French and Italian ticket wording.
enum TicketTextParser {
    static func parse(lines raw: [String], barcodes: [TicketPass.Barcode] = [], calendar: Calendar = .current, strictValidity: Bool = false) -> TicketDraft {
        let lines = raw.map(clean).filter { !$0.isEmpty }
        let text = lines.joined(separator: "\n")
        var d = TicketDraft()

        let op = KnownOperators.all.first { op in op.patterns.contains { matches($0, in: text) } }
            ?? barcodes.lazy.compactMap { $0.uicIssuerCode }.compactMap(KnownOperators.uic).first
        d.operatorName = op?.name
        d.symbol = op?.symbol

        let product = products.first { p in p.patterns.contains { matches($0, in: text) } }
        d.title = product?.title
        d.category = product?.category ?? category(in: text)

        (d.origin, d.destination) = route(lines)
        d.passenger = labelled(lines, passengerLabels, accept: { v in
            v.first?.isLetter == true && v.count <= 60 && v.filter(\.isNumber).count < 3
        })
        d.travelClass = travelClass(text)
        d.price = price(lines)
        d.reference = labelled(lines, referenceLabels, accept: { v in
            (v.count >= 5 && v.count <= 40 && v.contains(where: \.isNumber))
                || (v.count >= 6 && v.count <= 40 && v.allSatisfy { $0.isUppercase || $0.isNumber || $0 == "-" })
        })

        let validity = validity(lines, calendar: calendar, strict: strictValidity)
        d.validFrom = validity.from
        d.validUntil = validity.until

        if d.category == nil || (product == nil && d.category == .single), let from = d.validFrom, let until = d.validUntil,
           until.timeIntervalSince(from) > 36 * 3600 {
            d.category = until.timeIntervalSince(from) > 40 * 24 * 3600 ? .subscription : .period
        }
        return d
    }

    // MARK: - Products and categories

    struct Product: Sendable {
        let title: String
        let patterns: [String]
        let category: TicketPass.Category
    }

    static let products: [Product] = [
        Product(title: "Deutschlandticket", patterns: ["Deutschlandticket", "Deutschland-Ticket", "D-Ticket"], category: .subscription),
        Product(title: "KlimaTicket Ö", patterns: ["KlimaTicket Ö", "Klimaticket Österreich", "KlimaTicket Österreich"], category: .subscription),
        Product(title: "KlimaTicket", patterns: ["KlimaTicket"], category: .subscription),
        Product(title: "Interrail Pass", patterns: ["Interrail"], category: .period),
        Product(title: "Eurail Pass", patterns: ["Eurail"], category: .period),
        Product(title: "Jahreskarte", patterns: ["Jahreskarte", "Jahresabo"], category: .subscription),
        Product(title: "Monatskarte", patterns: ["Monatskarte"], category: .period),
        Product(title: "Wochenkarte", patterns: ["Wochenkarte"], category: .period),
        Product(title: "Tageskarte", patterns: ["Tageskarte", "Tagesticket", "24-Stunden-Karte", "24 Stunden"], category: .dayPass),
        Product(title: "Sparschiene", patterns: ["Sparschiene"], category: .single),
        Product(title: "Super Sparpreis", patterns: ["Super Sparpreis"], category: .single),
        Product(title: "Sparpreis", patterns: ["Sparpreis"], category: .single),
        Product(title: "Flexpreis", patterns: ["Flexpreis"], category: .single),
        Product(title: "Halbtax", patterns: ["Halbtax"], category: .subscription),
    ]

    private static let categoryWords: [(TicketPass.Category, [String])] = [
        (.returnTrip, ["rückfahrt", "hin- und rückfahrt", "hin und rück", "hin-/rückfahrt", "return ticket", "aller-retour", "aller retour", "andata e ritorno"]),
        (.dayPass, ["tageskarte", "tagesticket", "day ticket", "day pass", "24h", "24 h", "24-stunden", "billet journée", "biglietto giornaliero"]),
        (.subscription, ["jahreskarte", "annual pass", "abonnement", "abo"]),
        (.period, ["wochenkarte", "monatskarte", "weekly", "monthly", "week pass", "month pass", "abbonamento mensile"]),
        (.single, ["einzelfahrt", "einzelticket", "einfache fahrt", "single ticket", "one-way", "one way", "aller simple", "corsa semplice", "hinfahrt"]),
    ]

    private static func category(in text: String) -> TicketPass.Category? {
        let f = fold(text)
        let ticketWords = ["fahrkarte", "fahrschein", "ticket", "billet", "biglietto"]
        if ["reservierung", "reservation", "réservation", "prenotazione"].contains(where: { f.contains($0) }),
           !ticketWords.contains(where: { f.contains($0) }) {
            return .reservation
        }
        return categoryWords.first { _, words in words.contains { containsWord(fold($0), in: f) } }?.0
    }

    // MARK: - Route

    private static let fromLabels = ["von", "from", "start", "abfahrt", "departure", "ab", "départ", "depart", "partenza", "da"]
    private static let toLabels = ["nach", "to", "ziel", "ankunft", "arrival", "an", "arrivée", "arrivee", "arrivo", "destination", "a"]
    private static let arrows = ["→", "->", "➔", "➜", "⇒", "►", "▶", "—>", "–>", "⟶"]

    private static func route(_ lines: [String]) -> (String?, String?) {
        for line in lines {
            if let arrow = arrows.first(where: { line.contains($0) }) {
                let parts = line.components(separatedBy: arrow)
                if parts.count == 2, let a = place(parts[0]), let b = place(parts[1]) { return (a, b) }
            }
        }
        for line in lines {
            // "Von Wien Hbf nach Salzburg Hbf" or "From Paris to Lyon".
            for (from, to) in [("von", "nach"), ("from", "to")] {
                let pattern = "^\(from)\\s+(.+?)\\s+\(to)\\s+(.+)$"
                if let m = firstMatch(pattern, in: line, caseInsensitive: true), m.count == 3,
                   let a = place(m[1]), let b = place(m[2]) { return (a, b) }
            }
            // "Strecke: Wien Hbf – Salzburg Hbf"
            if let m = firstMatch(#"^(?:strecke|route|relation|verbindung|itinéraire|tratta)\s*:?\s*(.+?)\s+[-–—]\s+(.+)$"#, in: line, caseInsensitive: true),
               m.count == 3, let a = place(m[1]), let b = place(m[2]) { return (a, b) }
        }
        let a = labelled(lines, fromLabels, requireSeparatorForShort: true, accept: { place($0) != nil }).flatMap(place)
        let b = labelled(lines, toLabels, requireSeparatorForShort: true, accept: { place($0) != nil }).flatMap(place)
        return a != nil && b != nil ? (a, b) : (nil, nil)
    }

    /// A station name without times, dates, platforms or prices.
    private static func place(_ raw: String) -> String? {
        var s = raw
        for pattern in [#"\b\d{1,2}:\d{2}\b(\s*Uhr)?"#, #"\b\d{1,2}\.\d{1,2}\.\d{2,4}\b"#, #"\b\d{4}-\d{2}-\d{2}\b"#,
                        #"(?i)\b(gleis|bahnsteig|steig|platform|track|voie|binario)\b.*$"#, #"(€|EUR|CHF)\s*\d.*$"#] {
            s = s.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-–—|()").union(.whitespaces))
        guard s.count >= 2, s.count <= 60, s.first?.isLetter == true, !s.lowercased().contains("http") else { return nil }
        return s
    }

    // MARK: - Labelled values

    private static let passengerLabels = ["name", "reisende", "reisender", "fahrgast", "passenger", "passagier", "inhaber",
                                          "karteninhaber", "ticketinhaber", "holder", "voyageur", "passeggero"]
    private static let referenceLabels = ["ticketnummer", "ticket-nr", "ticket nr", "ticket-id", "ticket id", "ticket number",
                                          "auftragsnummer", "auftrags-nr", "auftrag", "buchungsnummer", "buchungscode",
                                          "order number", "booking reference", "booking code", "reference", "referenz",
                                          "kartennummer", "fahrscheinnummer", "pnr", "numéro de dossier", "codice biglietto"]

    /// The value after `Label:` / `Label value`, or on the next line when the label stands alone.
    /// Short labels ("ab", "an", "to") need a colon so ordinary words do not match.
    private static func labelled(_ lines: [String], _ labels: [String], requireSeparatorForShort: Bool = false,
                                 accept: (String) -> Bool) -> String? {
        for (i, line) in lines.enumerated() {
            let f = fold(line)
            for label in labels.sorted(by: { $0.count > $1.count }) {
                let l = fold(label)
                guard f.hasPrefix(l) else { continue }
                let restStart = line.index(line.startIndex, offsetBy: min(label.count, line.count))
                var rest = String(line[restStart...])
                // "Name" must not match "Namensänderung".
                if let next = rest.first, next.isLetter { continue }
                let hasColon = rest.trimmingCharacters(in: .whitespaces).hasPrefix(":")
                rest = rest.trimmingCharacters(in: CharacterSet(charactersIn: " :.").union(.whitespaces))
                if rest.isEmpty {
                    if i + 1 < lines.count, accept(lines[i + 1]), !isLabel(lines[i + 1]) { return lines[i + 1] }
                    continue
                }
                if requireSeparatorForShort, label.count <= 3, !hasColon { continue }
                if accept(rest) { return rest }
            }
        }
        return nil
    }

    private static func isLabel(_ line: String) -> Bool {
        let f = fold(line).trimmingCharacters(in: CharacterSet(charactersIn: " :"))
        return (fromLabels + toLabels + passengerLabels + referenceLabels).contains(f)
    }

    // MARK: - Class and price

    private static func travelClass(_ text: String) -> String? {
        let patterns = [#"\b([12])\.\s*(?:klasse|kl\.?)(?![a-z])"#, #"\bklasse\s*:?\s*([12])\b"#, #"\b([12])(?:st|nd)\s+class\b"#,
                        #"\bclass\s*:?\s*([12])\b"#, #"\b([12])\s*(?:e|ère|ème|re)\s+classe\b"#, #"\b([12])\s*[ªa°]?\s+classe\b"#]
        for p in patterns {
            if let m = firstMatch(p, in: fold(text), caseInsensitive: true), m.count == 2 { return m[1] }
        }
        return nil
    }

    private static let priceLabels = ["preis", "summe", "gesamt", "total", "betrag", "price", "prix", "prezzo", "bezahlt", "paid", "fahrpreis"]
    private static let pricePattern = #"(?:(?:€|EUR|CHF|£|GBP|CZK|PLN|HUF|RON|SEK|DKK)\s?\d{1,5}(?:[.,]\d{2})?)|(?:\d{1,5}[.,]\d{2}\s?(?:€|EUR|CHF|Kč|CZK|zł|PLN|Ft|HUF|lei|RON|kr|SEK|DKK))"#

    private static func price(_ lines: [String]) -> String? {
        let labelled = lines.filter { l in priceLabels.contains { fold(l).contains($0) } }
        for line in labelled + lines {
            if let m = firstMatch(pricePattern, in: line, caseInsensitive: false) { return m[0].trimmingCharacters(in: .whitespaces) }
        }
        return nil
    }

    // MARK: - Validity

    private static let excludedDateWords = ["geb", "geburt", "birth", "né le", "née le", "nato", "kauf", "gekauft", "purchase",
                                            "bought", "ausgestellt", "issued", "erstellt", "created", "buchung am", "gebucht",
                                            "booked", "bestellt", "ordered", "druck", "printed", "rechnung", "invoice", "acquist", "achat"]
    private static let untilWords = ["bis", "until", "valid to", "valid till", "expires", "expiry", "ablauf", "geltungsende",
                                     "jusqu", "fino al", "fino a", "ende"]
    private static let fromWords = ["ab", "from", "valid from", "gültig von", "vom", "geltungsbeginn", "beginn", "à partir",
                                    "a partire", "dal", "start"]
    private static let validityWords = ["gültig", "gueltig", "gültigkeit", "geltungsdauer", "geltungszeitraum", "valid", "validity",
                                        "reisedatum", "reisetag", "travel date", "date of travel", "fahrtantritt", "hinfahrt", "fahrt am",
                                        "datum", "date", "data", "valable", "valido", "validità"]

    struct FoundDate {
        var components: DateComponents
        var hasTime: Bool
        var position: Int
        var length = 1
        /// Whole month ("Oktober 2025") without a day.
        var wholeMonth = false
    }

    private static func validity(_ lines: [String], calendar: Calendar, strict: Bool) -> (from: Date?, until: Date?) {
        var from: FoundDate?
        var until: FoundDate?
        var day: FoundDate?
        var loose: [FoundDate] = []
        var month: FoundDate?

        for (i, line) in lines.enumerated() {
            let f = fold(line)
            if excludedDateWords.contains(where: { f.contains($0) }) { continue }
            var dates = findDates(line)
            var context = f
            if dates.isEmpty {
                // Label alone on its line, date on the next.
                guard i + 1 < lines.count, validityWords.contains(where: { f.contains($0) }) || untilWords.contains(where: { containsWord($0, in: f) }) || fromWords.contains(where: { containsWord($0, in: f) }) else { continue }
                let next = findDates(lines[i + 1])
                guard !next.isEmpty, !excludedDateWords.contains(where: { fold(lines[i + 1]).contains($0) }) else { continue }
                dates = next.map { var d = $0; d.position += f.count + 1; return d }
                context = f + " " + fold(lines[i + 1])
            }
            if strict {
                let explicitWords = validityWords.filter { !["datum", "date", "data"].contains($0) }
                let labelled = explicitWords.contains { context.contains($0) }
                    || untilWords.contains { containsWord($0, in: context) }
                    || fromWords.contains { containsWord($0, in: context) }
                guard labelled else { continue }
            }
            if dates.count == 1, dates[0].wholeMonth {
                if month == nil { month = dates[0] }
                continue
            }
            if dates.count >= 2 {
                let sorted = dates.sorted { (date($0, end: false, calendar) ?? .distantPast) < (date($1, end: false, calendar) ?? .distantPast) }
                if from == nil { from = sorted.first }
                if until == nil { until = sorted.last }
                continue
            }
            guard let found = dates.first else { continue }
            let before = String(context.prefix(found.position))
            if untilWords.contains(where: { containsWord($0, in: before) }) {
                if until == nil { until = found }
            } else if fromWords.contains(where: { containsWord($0, in: before) }) {
                if from == nil { from = found }
            } else if validityWords.contains(where: { context.contains($0) }) {
                if day == nil { day = found }
            } else {
                loose.append(found)
            }
        }

        if from == nil, until == nil {
            if let day {
                from = day
                until = FoundDate(components: day.components, hasTime: false, position: 0)
            } else if let month {
                from = month
                until = month
            } else if loose.count >= 2 {
                let sorted = loose.sorted { (date($0, end: false, calendar) ?? .distantPast) < (date($1, end: false, calendar) ?? .distantPast) }
                from = sorted.first
                until = sorted.last
            } else if let only = loose.first {
                from = only
                until = FoundDate(components: only.components, hasTime: false, position: 0)
            }
        }
        var start = from.flatMap { date($0, end: false, calendar) }
        var end = until.flatMap { date($0, end: true, calendar) }
        if !strict, let s = start, let e = end, s > e { (start, end) = (e, s) }
        return (start, end)
    }

    /// Dates without a time start at midnight and end at 23:59:59; whole months cover the month.
    private static func date(_ found: FoundDate, end: Bool, _ calendar: Calendar) -> Date? {
        var c = found.components
        c.calendar = calendar
        c.timeZone = calendar.timeZone
        if found.wholeMonth {
            c.day = 1
            guard let first = calendar.date(from: c) else { return nil }
            guard end else { return first }
            guard let next = calendar.date(byAdding: .month, value: 1, to: first) else { return nil }
            return next.addingTimeInterval(-1)
        }
        if !found.hasTime {
            c.hour = end ? 23 : 0
            c.minute = end ? 59 : 0
            c.second = end ? 59 : 0
        }
        guard let date = calendar.date(from: c), calendar.component(.day, from: date) == c.day else { return nil }
        return date
    }

    private static let monthNames: [[String]] = [
        ["januar", "jänner", "january", "janvier", "gennaio"], ["februar", "feber", "february", "février", "fevrier", "febbraio"],
        ["märz", "march", "mars", "marzo", "mrz"], ["april", "avril", "aprile"], ["mai", "may", "maggio"],
        ["juni", "june", "juin", "giugno"], ["juli", "july", "juillet", "luglio"], ["august", "août", "aout", "agosto"],
        ["september", "septembre", "settembre", "sept"], ["oktober", "october", "octobre", "ottobre"],
        ["november", "novembre"], ["dezember", "december", "décembre", "decembre", "dicembre"],
    ]

    /// A month name or its abbreviation of three or four letters ("Okt", "Sept"), never a longer word that only starts like one.
    private static func month(_ word: String) -> Int? {
        let w = word.lowercased()
        guard w.count >= 3 else { return nil }
        for (i, names) in monthNames.enumerated() {
            if names.contains(w) { return i + 1 }
            if w.count <= 4, names.contains(where: { $0.hasPrefix(w) }) { return i + 1 }
        }
        return nil
    }

    static func findDates(_ line: String) -> [FoundDate] {
        var out: [FoundDate] = []
        let ns = line as NSString
        func year(_ s: String) -> Int? {
            guard let y = Int(s) else { return nil }
            return s.count == 2 ? 2000 + y : y
        }
        func time(after end: Int) -> (Int, Int)? {
            let rest = ns.substring(from: end)
            guard let m = firstMatch(#"^\s*(?:,|um|at|ab|à|alle|-)?\s*(\d{1,2}):(\d{2})"#, in: rest, caseInsensitive: true),
                  let h = Int(m[1]), let mi = Int(m[2]), h < 24, mi < 60 else { return nil }
            return (h, mi)
        }
        func add(_ y: Int?, _ m: Int?, _ d: Int?, _ range: NSRange, wholeMonth: Bool = false) {
            guard let y, let m, (1...12).contains(m), (2000...2100).contains(y) else { return }
            if !wholeMonth { guard let d, (1...31).contains(d) else { return } }
            guard !out.contains(where: { NSIntersectionRange(NSRange(location: $0.position, length: $0.length), range).length > 0 }) else { return }
            var c = DateComponents(year: y, month: m, day: wholeMonth ? 1 : d)
            var hasTime = false
            if !wholeMonth, let t = time(after: range.location + range.length) {
                c.hour = t.0; c.minute = t.1; c.second = 0
                hasTime = true
            }
            out.append(FoundDate(components: c, hasTime: hasTime, position: range.location, length: range.length, wholeMonth: wholeMonth))
        }
        for m in allMatches(#"(?<!\d)(\d{1,2})\.\s?(\d{1,2})\.\s?(\d{4}|\d{2})(?!\d)"#, in: line) {
            add(year(m.groups[3]), Int(m.groups[2]), Int(m.groups[1]), m.range)
        }
        for m in allMatches(#"(?<!\d)(\d{4})-(\d{2})-(\d{2})(?!\d)"#, in: line) {
            add(Int(m.groups[1]), Int(m.groups[2]), Int(m.groups[3]), m.range)
        }
        for m in allMatches(#"(?<!\d)(\d{1,2})/(\d{1,2})/(\d{4})(?!\d)"#, in: line) {
            add(Int(m.groups[3]), Int(m.groups[2]), Int(m.groups[1]), m.range)
        }
        for m in allMatches(#"(?<!\d)(\d{1,2})\.?\s+([A-Za-zÄÖÜäöüÉéÈèÛûÔô]{3,})\.?\s+(\d{4})(?!\d)"#, in: line) {
            if let mo = month(m.groups[2]) { add(Int(m.groups[3]), mo, Int(m.groups[1]), m.range) }
        }
        for m in allMatches(#"(?<![\p{L}\d.])([A-Za-zÄÖÜäöüÉéÈèÛûÔô]{3,})\.?\s+(\d{4})(?!\d)"#, in: line) {
            if let mo = month(m.groups[1]) { add(Int(m.groups[2]), mo, nil, m.range, wholeMonth: true) }
        }
        return out.sorted { $0.position < $1.position }
    }

    // MARK: - Text helpers

    static func clean(_ line: String) -> String {
        line.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Lowercased for label matching. Accents stay: "Gültig" and "à partir" are matched as written.
    static func fold(_ s: String) -> String { s.lowercased() }

    /// Case-insensitive match; short all-caps patterns ("SBB", "MVV") need whole words in capitals.
    static func matches(_ pattern: String, in text: String) -> Bool {
        if pattern.count <= 4, pattern == pattern.uppercased() {
            return firstMatch("(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: pattern) + "(?![\\p{L}\\p{N}])",
                              in: text, caseInsensitive: false) != nil
        }
        return text.range(of: pattern, options: [.caseInsensitive]) != nil
    }

    static func containsWord(_ word: String, in text: String) -> Bool {
        firstMatch("(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: word) + "(?![\\p{L}\\p{N}])",
                   in: text, caseInsensitive: true) != nil
    }

    struct Match { let range: NSRange; let groups: [String] }

    static func allMatches(_ pattern: String, in text: String) -> [Match] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { m in
            Match(range: m.range, groups: (0..<m.numberOfRanges).map { i in
                let r = m.range(at: i)
                return r.location == NSNotFound ? "" : ns.substring(with: r)
            })
        }
    }

    static func firstMatch(_ pattern: String, in text: String, caseInsensitive: Bool) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : []) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? "" : ns.substring(with: r)
        }
    }
}

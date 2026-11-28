// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich

import Foundation

/// Reads an Apple Wallet pass (`.pkpass`, #20) into a Publit ticket: the code exactly as issued, the
/// route, the validity, the operator and the colour. Everything stays on the device; the signature is
/// not checked (Publit shows the code, the operator's scanner checks it).
enum WalletPassImport {
    enum Failure: LocalizedError {
        case notAPass
        var errorDescription: String? { L10n.t("This file is not a Wallet pass Publit can read.") }
    }

    struct Result {
        var pass: TicketPass
        var codes: [TicketPass.Barcode]
        /// `RRGGBB` of the pass, for the colour suggestion.
        var color: String?
    }

    private struct PassJSON: Decodable {
        struct Field: Decodable {
            let key: String?
            let label: String?
            let value: Value?
            let dateStyle: String?
            let timeStyle: String?
        }
        /// A field value: text, number or date (as an ISO 8601 string).
        enum Value: Decodable {
            case text(String), number(Double)
            init(from decoder: Decoder) throws {
                let c = try decoder.singleValueContainer()
                if let s = try? c.decode(String.self) { self = .text(s) }
                else { self = .number(try c.decode(Double.self)) }
            }
            var text: String {
                switch self {
                case .text(let s): return s
                // `Int(exactly:)`: a 20-digit ticket number is a whole number no Int holds (the app closed on opening such a pass).
                case .number(let n): return Int(exactly: n).map { String($0) } ?? String(n)
                }
            }
        }
        struct Structure: Decodable {
            let transitType: String?
            let headerFields: [Field]?
            let primaryFields: [Field]?
            let secondaryFields: [Field]?
            let auxiliaryFields: [Field]?
            let backFields: [Field]?
            var front: [Field] { (headerFields ?? []) + (primaryFields ?? []) + (secondaryFields ?? []) + (auxiliaryFields ?? []) }
        }
        struct Barcode: Decodable {
            let format: String?
            let message: String?
            let messageEncoding: String?
            let altText: String?
        }
        let description: String?
        let organizationName: String?
        let logoText: String?
        let serialNumber: String?
        let relevantDate: String?
        let expirationDate: String?
        let backgroundColor: String?
        let barcode: Barcode?
        let barcodes: [Barcode]?
        let boardingPass: Structure?
        let eventTicket: Structure?
        let generic: Structure?
        let storeCard: Structure?
        let coupon: Structure?
        var structure: Structure? { boardingPass ?? generic ?? eventTicket ?? storeCard ?? coupon }
    }

    /// The pass inside a `.pkpass` file.
    static func read(pkpass data: Data, now: Date = .now) throws -> Result {
        guard let json = try? ZipReader.file("pass.json", in: data) else { throw Failure.notAPass }
        return try read(passJSON: json, now: now)
    }

    static func read(passJSON json: Data, now: Date = .now) throws -> Result {
        guard let p = try? JSONDecoder().decode(PassJSON.self, from: json) else { throw Failure.notAPass }
        let s = p.structure
        let front = s?.front ?? []
        let back = s?.backFields ?? []

        // Text the usual rules understand ("Deutschlandticket", "Gültig bis …", "2. Klasse").
        let lines = ([p.organizationName, p.description, p.logoText].compactMap { $0 }
            + (front + back).map { [$0.label, $0.value?.text].compactMap { $0 }.joined(separator: " ") })
            .map(TicketTextParser.clean).filter { !$0.isEmpty }
        let codes = (p.barcodes ?? p.barcode.map { [$0] } ?? []).compactMap(barcode)
        var draft = TicketTextParser.parse(lines: lines, barcodes: codes)

        draft.operatorName = p.organizationName?.nilIfEmpty ?? draft.operatorName
        draft.title = draft.title ?? p.description?.nilIfEmpty ?? p.logoText?.nilIfEmpty
        if let t = s?.transitType { draft.symbol = symbol(t) ?? draft.symbol }
        // A boarding pass names its start and end in the first two primary fields.
        if p.boardingPass != nil, let primary = s?.primaryFields, primary.count >= 2 {
            draft.origin = place(primary[0]) ?? draft.origin
            draft.destination = place(primary[1]) ?? draft.destination
        }
        func field(_ words: [String]) -> String? {
            (front + back).first { f in
                let k = ((f.key ?? "") + " " + (f.label ?? "")).lowercased()
                return words.contains { k.contains($0) }
            }?.value?.text.nilIfEmpty
        }
        draft.passenger = field(["passenger", "reisende", "fahrgast", "traveller", "traveler", "name"]) ?? draft.passenger
        draft.travelClass = draft.travelClass ?? field(["class", "klasse"]).flatMap { v in v.first(where: { $0 == "1" || $0 == "2" }).map(String.init) }
        draft.reference = field(["ticket", "booking", "buchung", "pnr", "auftrag", "order", "reference"]) ?? draft.reference ?? p.serialNumber
        if let d = p.relevantDate.flatMap(date) { draft.validFrom = draft.validFrom ?? d }
        if let d = p.expirationDate.flatMap(date) { draft.validUntil = d }
        if draft.category == nil {
            draft.category = p.boardingPass != nil ? .single : draft.validUntil != nil && draft.validFrom == nil ? .period : nil
        }

        var pass = TicketPass(draft: draft, barcode: codes.first, now: now)
        let color = p.backgroundColor.flatMap(hex)
        if PassStyle.suggested(forOperator: draft.operatorName) == nil, let color { pass.style = PassStyle(background: color) }
        let notes = back.compactMap { f -> String? in
            guard let v = f.value?.text.nilIfEmpty else { return nil }
            return f.label.map { "\($0): \(v)" } ?? v
        }
        if !notes.isEmpty { pass.notes = String(notes.joined(separator: "\n").prefix(2000)) }
        return Result(pass: pass, codes: codes, color: color)
    }

    private static func barcode(_ b: PassJSON.Barcode) -> TicketPass.Barcode? {
        let format: TicketPass.Barcode.Format
        switch b.format {
        case "PKBarcodeFormatQR": format = .qr
        case "PKBarcodeFormatAztec": format = .aztec
        case "PKBarcodeFormatPDF417": format = .pdf417
        case "PKBarcodeFormatCode128": format = .code128
        default: return nil
        }
        guard let message = b.message, !message.isEmpty else { return nil }
        // Binary codes (UIC 918.3) travel as ISO-8859-1 text: one character per byte.
        if b.messageEncoding?.lowercased() == "iso-8859-1",
           message.unicodeScalars.contains(where: { $0.value > 0x7F || $0.value < 0x20 }),
           message.unicodeScalars.allSatisfy({ $0.value <= 0xFF }) {
            return TicketPass.Barcode(format: format, payload: Data(message.unicodeScalars.map { UInt8($0.value) }), altText: b.altText)
        }
        return TicketPass.Barcode(format: format, message: message, altText: b.altText)
    }

    private static func symbol(_ transitType: String) -> TicketPass.Symbol? {
        switch transitType {
        case "PKTransitTypeTrain": return .train
        case "PKTransitTypeBus": return .bus
        case "PKTransitTypeBoat": return .ferry
        case "PKTransitTypeGeneric", "PKTransitTypeAir": return .ticket
        default: return nil
        }
    }

    /// A station's name: the label when the value is only a code ("VIE"), else the value.
    private static func place(_ f: PassJSON.Field) -> String? {
        let v = f.value?.text.trimmingCharacters(in: .whitespaces) ?? ""
        let label = f.label?.trimmingCharacters(in: .whitespaces) ?? ""
        if v.count <= 4, v == v.uppercased(), label.count > v.count { return label }
        return v.nilIfEmpty ?? label.nilIfEmpty
    }

    private static func date(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        // "2026-12-01T08:00+01:00" without seconds.
        f.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime, .withTimeZone, .withDashSeparatorInDate]
        return f.date(from: s)
    }

    /// `rgb(12, 34, 56)` or `#0c2238` → `0C2238`.
    static func hex(_ css: String) -> String? {
        let t = css.trimmingCharacters(in: .whitespaces).lowercased()
        if t.hasPrefix("#") { return LineColors.RGB(hex: String(t.dropFirst())) != nil ? LineColors.normalized(t) : nil }
        guard t.hasPrefix("rgb") else { return nil }
        let nums = t.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard nums.count >= 3, nums.prefix(3).allSatisfy({ (0...255).contains($0) }) else { return nil }
        return String(format: "%02X%02X%02X", nums[0], nums[1], nums[2])
    }
}

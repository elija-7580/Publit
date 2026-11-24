import Foundation

/// A piece of text on a ticket page that can be assigned to a field.
struct TicketTextPiece: Identifiable, Sendable {
    let id: Int
    let text: String
    /// Normalized to the upright page, origin top left (same convention as barcode regions).
    let rect: CGRect

    /// Embedded PDF text plus the text recognised in the rendered page where the PDF has none (#5):
    /// a recognised piece that mostly lies on an embedded one is the same text and is dropped.
    /// Numbered again from the top of the page.
    static func merging(embedded: [TicketTextPiece], recognized: [TicketTextPiece]) -> [TicketTextPiece] {
        let extra = recognized.filter { r in
            let area = r.rect.width * r.rect.height
            guard area > 0 else { return false }
            return !embedded.contains { e in
                let i = e.rect.intersection(r.rect)
                return !i.isNull && i.width * i.height >= area * 0.3
            }
        }
        let all = (embedded + extra).sorted { a, b in
            abs(a.rect.minY - b.rect.minY) < 0.004 ? a.rect.minX < b.rect.minX : a.rect.minY < b.rect.minY
        }
        return all.enumerated().map { TicketTextPiece(id: $0.offset, text: $0.element.text, rect: $0.element.rect) }
    }

    /// Embedded lines first, then recognised lines that say something the embedded text does not.
    static func mergedLines(embedded: [String], recognized: [String]) -> [String] {
        func key(_ s: String) -> String {
            s.lowercased().filter { $0.isLetter || $0.isNumber }
        }
        let known = embedded.map(key).joined(separator: "|")
        var seen = Set<String>()
        let extra = recognized.filter { line in
            let k = key(line)
            return k.count >= 3 && !known.contains(k) && seen.insert(k).inserted
        }
        return embedded + extra
    }
}

/// Only explicit user assignments, never inference. Kept separate from Vision for unit tests.
enum TicketField: String, CaseIterable, Identifiable, Sendable {
    case title, operatorName, origin, destination, via, passenger, price, reference, validFrom, validUntil, notes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .title: return L10n.t("Title")
        case .operatorName: return L10n.t("Operator")
        case .origin: return L10n.t("From")
        case .destination: return L10n.t("To")
        case .via: return L10n.t("Via")
        case .passenger: return L10n.t("Passenger")
        case .price: return L10n.t("Price")
        case .reference: return L10n.t("Ticket number")
        case .validFrom: return L10n.t("Valid from")
        case .validUntil: return L10n.t("Valid until")
        case .notes: return L10n.t("Notes")
        }
    }

    /// False leaves the pass unchanged, e.g. when an assigned date cannot be read.
    @discardableResult
    func apply(_ text: String, to pass: inout TicketPass, calendar: Calendar = .current) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return false }
        switch self {
        case .title: pass.title = value
        case .operatorName: pass.operatorName = value
        case .origin: pass.origin = value
        case .destination: pass.destination = value
        case .via: pass.via = value
        case .passenger: pass.passenger = value
        case .price: pass.price = value
        case .reference: pass.reference = value
        case .notes: pass.notes = value
        case .validFrom, .validUntil:
            guard let date = TicketTextParser.date(in: value, end: self == .validUntil, calendar: calendar) else { return false }
            if self == .validFrom { pass.validFrom = date } else { pass.validUntil = date }
        }
        return true
    }
}

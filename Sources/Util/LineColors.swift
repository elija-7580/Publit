import Foundation

/// GTFS line colours with a legibility check (WCAG 2 contrast).
enum LineColors {
    struct Pair: Equatable, Sendable {
        let background: String
        let text: String
    }

    struct RGB: Equatable, Sendable {
        let r: Double, g: Double, b: Double

        /// Parses `e3000f` or `#E3000F`.
        init?(hex: String?) {
            guard var s = hex?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
            if s.hasPrefix("#") { s.removeFirst() }
            guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
            r = Double((v >> 16) & 0xFF) / 255
            g = Double((v >> 8) & 0xFF) / 255
            b = Double(v & 0xFF) / 255
        }

        var luminance: Double {
            func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
            return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
        }
    }

    static func contrast(_ a: RGB, _ b: RGB) -> Double {
        let (l1, l2) = (max(a.luminance, b.luminance), min(a.luminance, b.luminance))
        return (l1 + 0.05) / (l2 + 0.05)
    }

    static let white = RGB(hex: "FFFFFF")!
    static let black = RGB(hex: "000000")!

    /// Minimum ratio we accept for an operator's own text colour on its line colour
    /// (bold badge text; WCAG large/bold text threshold).
    static let minimumOperatorContrast = 3.0

    static func normalized(_ hex: String) -> String {
        hex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "").uppercased()
    }

    /// Keeps the operator's text colour when it is legible, otherwise picks white or black,
    /// whichever contrasts more with the background.
    static func resolve(routeColor: String?, routeTextColor: String?, fallback: String) -> Pair {
        let bgHex = RGB(hex: routeColor) != nil ? normalized(routeColor!) : normalized(fallback)
        guard let bg = RGB(hex: bgHex) else { return Pair(background: "4D4D59", text: "FFFFFF") }
        if routeColor != nil, let given = RGB(hex: routeTextColor),
           contrast(given, bg) >= minimumOperatorContrast {
            return Pair(background: bgHex, text: normalized(routeTextColor!))
        }
        return Pair(background: bgHex, text: contrast(white, bg) >= contrast(black, bg) ? "FFFFFF" : "000000")
    }
}

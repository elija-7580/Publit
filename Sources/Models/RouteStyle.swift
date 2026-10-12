import SwiftUI

extension Color {
    /// Parses GTFS-style hex colours (`e3000f` or `#e3000f`).
    init?(hex: String?) {
        guard let rgb = LineColors.RGB(hex: hex) else { return nil }
        self.init(red: rgb.r, green: rgb.g, blue: rgb.b)
    }
}

extension RouteStyled {
    var lineColor: Color { Color(hex: lineColors.background) ?? .gray }
    var lineTextColor: Color { Color(hex: lineColors.text) ?? .white }
}

extension ModeStyle {
    static func color(_ mode: String) -> Color { Color(hex: defaultHex(mode)) ?? .gray }
}

#if canImport(UIKit)
import UIKit

extension Color {
    /// Light/dark adaptive colour from a `Palette.Tone`.
    init(_ tone: Palette.Tone) {
        let l = LineColors.RGB(hex: tone.light)!
        let d = LineColors.RGB(hex: tone.dark) ?? l
        self.init(uiColor: UIColor { trait in
            let c = trait.userInterfaceStyle == .dark ? d : l
            return UIColor(red: c.r, green: c.g, blue: c.b, alpha: 1)
        })
    }
    static let live = Color(Palette.live)
    static let delay = Color(Palette.delay)
    static let danger = Color(Palette.danger)
    static let appAccent = Color(Palette.accent)
}
#endif

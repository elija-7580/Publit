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

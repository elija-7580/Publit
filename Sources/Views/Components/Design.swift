import SwiftUI

/// "Ink & Dot" (docs/design/README.md): flat opaque cards, one glass layer for floating controls,
/// ink instead of a brand colour, the logo's yellow dot only for "you" and "live".
extension Color {
    static let ground = Color(Palette.ground)
    static let surface = Color(Palette.surface)
    static let inkFill = Color(Palette.fill)
    static let ink = Color(Palette.ink)
    static let onInk = Color(Palette.onInk)
    static let signature = Color(Palette.signature)
}

/// The logo's dot: where you are, what is live.
struct SignatureDot: View {
    var size: CGFloat = 8
    var body: some View {
        Circle().fill(Color.signature).frame(width: size, height: size).accessibilityHidden(true)
    }
}

/// Progress as the logo's stroke: a round-capped track, filled in ink (or a status colour),
/// with the yellow dot where you are now.
struct InkProgress: View {
    let value: Double
    var tint: Color = .ink

    var body: some View {
        let v = min(max(value, 0), 1)
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.inkFill).frame(height: 6)
                Capsule().fill(tint).frame(width: max(6, w * v), height: 6)
                Circle().fill(Color.signature)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().strokeBorder(Color.surface, lineWidth: 2.5).padding(-2.5))
                    .offset(x: min(max(w * v - 6, 0), max(w - 12, 0)))
            }
            .frame(height: 12)
        }
        .frame(height: 12)
        .accessibilityElement()
        .accessibilityValue(Text(verbatim: "\(Int((v * 100).rounded())) %"))
    }
}

extension View {
    /// A list on the flat "Ink & Dot" ground with opaque cards (apply `inkCard()` to its sections).
    func inkList() -> some View {
        scrollContentBackground(.hidden)
            .background(Color.ground)
            .listSectionSpacing(12)
    }

    /// Rows of a list section as one flat card.
    func inkCard() -> some View { listRowBackground(Color.surface) }
}

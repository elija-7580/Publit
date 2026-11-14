import SwiftUI

struct LineBadge: View {
    let name: String
    let mode: String
    let color: Color
    let textColor: Color
    let compact: Bool
    /// Raw background, for the edge check in dark and light mode.
    let hex: String
    @Environment(\.colorScheme) private var scheme

    init(_ route: some RouteStyled, compact: Bool = false, detailed: Bool = false) {
        self.compact = compact
        name = detailed ? (route.serviceDetail ?? route.lineName) : route.lineName
        mode = route.mode
        color = route.lineColor
        textColor = route.lineTextColor
        hex = route.lineColors.background
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: ModeStyle.symbol(mode))
                .font(.caption.weight(.semibold))
                .accessibilityHidden(true)
            Text(verbatim: name)
                .font(compact ? .caption.weight(.bold) : .subheadline.weight(.bold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, compact ? 2 : 4)
        .frame(minWidth: 44)
        .foregroundStyle(textColor)
        .background(color, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        // Near-black badges on dark backgrounds (and white ones on light) get a visible edge;
        // the others the usual hairline.
        .overlay {
            if LineColors.blendsIn(hex, dark: scheme == .dark) {
                RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.45), lineWidth: 1)
            } else {
                RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(ModeStyle.label(mode)) \(name)")
    }
}

/// Clock time is primary; countdown, delay and provenance are always secondary.
struct AttributionFooter: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Link("Routing and timetables: Transitous and its data sources", destination: AppInfo.sourcesURL)
            Link("Map data © OpenStreetMap contributors", destination: AppInfo.osmCopyrightURL)
        }
        .font(.footnote)
    }
}

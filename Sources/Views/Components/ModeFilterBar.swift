import SwiftUI

/// "All · Train · S-Bahn · Tram · Bus" chips. From "All", a tap shows only that mode; more taps add
/// or remove modes. Only modes that actually run here are offered.
struct ModeFilterBar: View {
    let available: [ModeGroup]
    @Binding var filter: ModeFilter
    /// Symbols only, in one fixed row without scrolling (station map). A horizontal scroll view
    /// floating over the map was sometimes not drawn on iOS 26+, while its chips still took taps.
    var iconsOnly = false
    var horizontalInset: CGFloat = 16

    var body: some View {
        if iconsOnly { iconRow } else { scrollingRow }
    }

    private var iconRow: some View {
        HStack(spacing: 6) {
            iconChip(symbol: "square.grid.2x2", title: L10n.t("All"), selected: !filter.isActive) { filter = .all }
                .accessibilityIdentifier("modeChip-all")
            ForEach(available) { group in
                iconChip(symbol: group.symbol, title: group.title,
                         selected: filter.isActive && filter.included.contains(group)) { filter.toggleOnly(group) }
                    .accessibilityIdentifier("modeChip-\(group.rawValue)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.t("Filter by mode"))
    }

    private func iconChip(symbol: String, title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 34)
                .foregroundStyle(selected ? Color.onInk : Color.primary)
                .background(selected ? Color.ink : Color.inkFill, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var scrollingRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: L10n.t("All"), symbol: nil, selected: !filter.isActive) { filter = .all }
                    .accessibilityIdentifier("modeChip-all")
                ForEach(available) { group in
                    chip(title: group.title, symbol: nil, selected: filter.isActive && filter.included.contains(group)) {
                        filter.toggleOnly(group)
                    }
                    .accessibilityIdentifier("modeChip-\(group.rawValue)")
                }
            }
            .padding(.horizontal, horizontalInset)
            .padding(.vertical, 6)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.t("Filter by mode"))
    }

    private func chip(title: String, symbol: String?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol).font(.caption.weight(.semibold)).accessibilityHidden(true) }
                Text(verbatim: title).font(.subheadline.weight(.semibold)).lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(selected ? Color.onInk : Color.primary)
            .background(selected ? Color.ink : Color.inkFill, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

extension View {
    /// A full-width list row without background, for the chip bar.
    func chipRow() -> some View {
        listRowInsets(EdgeInsets()).listRowBackground(Color.clear).listRowSeparator(.hidden)
    }
}

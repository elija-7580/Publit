import SwiftUI

/// The four main screens share a quiet heading, opaque panels and the same dock.
/// These are real app components, also used by the deterministic screenshot fixtures.
struct InkPageHeader<Actions: View>: View {
    let title: LocalizedStringKey
    let logo: Bool
    let identifier: String
    private let actions: Actions

    init(_ title: LocalizedStringKey, logo: Bool = false, identifier: String,
         @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.logo = logo
        self.identifier = identifier
        self.actions = actions()
    }

    var body: some View {
        HStack(spacing: 8) {
            if logo {
                PublitLogo(line: .ink).frame(width: 30, height: 36).accessibilityHidden(true)
            }
            Text(title).font(.system(.largeTitle, design: .default).weight(.heavy))
                .tracking(-0.7).lineLimit(1).minimumScaleFactor(0.75)
                .accessibilityAddTraits(.isHeader).accessibilityIdentifier(identifier)
            Spacer(minLength: 4)
            HStack(spacing: 4) { actions }
                .font(.body.weight(.semibold)).labelStyle(.iconOnly).buttonStyle(.plain)
        }
        .foregroundStyle(Color.ink).padding(.top, 12).padding(.bottom, 4)
    }
}

struct InkPanel<Content: View>: View {
    private let padding: CGFloat
    private let content: Content
    init(padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }
    var body: some View {
        content.padding(padding).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct InkSectionLabel: View {
    let title: String
    var body: some View {
        Text(verbatim: title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4).padding(.top, 8)
            .accessibilityAddTraits(.isHeader)
    }
}

struct InkTabBar: View {
    @Environment(AppState.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        HStack(spacing: 0) {
            tab(.nearby, title: "Nearby", symbol: "mappin.and.ellipse", id: "tab-nearby")
            tab(.plan, title: "Plan", symbol: "point.topleft.down.curvedto.point.bottomright.up", id: "tab-plan")
            tab(.tickets, title: "Tickets", symbol: "ticket", id: "tab-tickets")
            tab(.favorites, title: "Saved", symbol: "bookmark", id: "tab-favorites")
        }
        .padding(.horizontal, 6).padding(.vertical, 5)
        .matteSurface(in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .accessibilityIdentifier("publitDock")
    }
    private func tab(_ target: AppTab, title: LocalizedStringKey, symbol: String, id: String) -> some View {
        let selected = app.tab == target
        return Button {
            app.deepLink = nil
            app.tab = target
        } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 19, weight: .semibold)).frame(height: 23)
                Text(title).font(typeSize.isAccessibilitySize ? .caption2 : .system(size: 10, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.8)
                Circle().fill(selected ? Color.signature : .clear).frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity, minHeight: 48).contentShape(Rectangle())
            .foregroundStyle(selected ? Color.ink : Color.secondary)
        }
        .buttonStyle(.plain).accessibilityLabel(Text(title))
        .accessibilityAddTraits(selected ? .isSelected : []).accessibilityIdentifier(id)
    }
}

extension View {
    func inkRouteCard() -> some View {
        padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

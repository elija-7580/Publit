import SwiftUI

struct LineBadge: View {
    let name: String
    let mode: String
    let color: Color
    let textColor: Color
    let compact: Bool

    init(_ route: some RouteStyled, compact: Bool = false, detailed: Bool = false) {
        self.compact = compact
        name = detailed ? (route.serviceDetail ?? route.lineName) : route.lineName
        mode = route.mode
        color = route.lineColor
        textColor = route.lineTextColor
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
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(ModeStyle.label(mode)) \(name)")
    }
}

/// Clock time is primary; countdown, delay and provenance are always secondary.
struct DepartureTimeView: View {
    let actual: Date
    let delayMinutes: Int
    let realTime: Bool
    let cancelled: Bool
    var tz: String? = nil

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { ctx in
            let minutes = Int(ceil(actual.timeIntervalSince(ctx.date) / 60))
            VStack(alignment: .trailing, spacing: 4) {
                Text(Fmt.time(actual, tz: tz))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(cancelled ? Color.secondary : Color.primary)
                    .strikethrough(cancelled)
                    .lineLimit(1).fixedSize()
                if cancelled {
                    Text("Cancelled").font(.caption.weight(.semibold)).foregroundStyle(Color.danger)
                } else {
                    if minutes <= 0 {
                        Text("now").font(.caption.weight(.semibold))
                    } else if minutes < 60 {
                        Text(L10n.f("In %lld min", minutes)).font(.caption.monospacedDigit())
                    }
                    if delayMinutes > 0 {
                        Text(L10n.f("+%lld min", delayMinutes))
                            .font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(Color.delay)
                    }
                    Label(realTime ? L10n.t("Live") : L10n.t("Timetable"),
                          systemImage: realTime ? "dot.radiowaves.left.and.right" : "calendar")
                        .font(.caption2)
                        .fixedSize(horizontal: true, vertical: true)
                        .foregroundStyle(realTime ? Color.live : Color.secondary)
                }
            }
            .fixedSize(horizontal: true, vertical: true)
        }
        .fixedSize(horizontal: true, vertical: true)
    }
}

struct AttributionFooter: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Link("Routing and timetables: Transitous and its data sources", destination: AppInfo.sourcesURL)
            Link("Map data © OpenStreetMap contributors", destination: AppInfo.osmCopyrightURL)
        }
        .font(.footnote)
    }
}

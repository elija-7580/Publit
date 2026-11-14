import SwiftUI

struct DepartureRow: View {
    let stopTime: StopTime

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // Countdowns are in whole minutes: all rows read one shared minute clock and redraw
        // together on the minute (no timeline per row).
        row(now: Ticker.minute.now)
    }

    /// Ink & Dot board row, two lines: what comes (line and destination) and when (the minutes);
    /// platform and clock time underneath in one grey line. Notes only when there is one.
    private func row(now: Date) -> some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    identity(lines: 3)
                    details
                    serviceNote
                    minutes(now: now)
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        identity(lines: 1)
                        details
                        serviceNote
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    minutes(now: now)
                }
            }
        }
        .padding(.vertical, 4)
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier("departureRow")
    }

    /// Badge and destination on one line: the two things you look for first.
    private func identity(lines: Int) -> some View {
        HStack(alignment: .center, spacing: 8) {
            LineBadge(stopTime)
            Group {
                if let direction = TransitLabels.clean(stopTime.shownDirection) {
                    Text(verbatim: stopTime.isCircular ? direction + " · " + L10n.t("Circle line") : direction)
                        .foregroundStyle(Color.primary)
                } else if stopTime.isCircular {
                    Text("Circle line").foregroundStyle(Color.primary)
                } else {
                    Text("Direction unavailable").foregroundStyle(.secondary)
                }
            }
            .font(.body.weight(.semibold))
            .lineLimit(lines)
            .truncationMode(.tail)
            .accessibilityIdentifier("vehicleDirection")
        }
    }

    /// "Pl. 51 · 11:24 · +2 min", one grey line (footnote, never smaller).
    private var details: some View {
        let delayed = stopTime.delayMinutes > 0 && !stopTime.isCancelled
        return HStack(spacing: 0) {
            Text(verbatim: Self.detailText(stopTime))
            if stopTime.isCancelled {
                Text(verbatim: " · ")
                Text("Cancelled").fontWeight(.semibold).foregroundStyle(Color.danger)
            } else if delayed {
                Text(verbatim: " · ")
                Text(L10n.f("+%lld min", stopTime.delayMinutes)).fontWeight(.semibold).foregroundStyle(Color.delay)
            }
        }
        .font(.footnote.monospacedDigit())
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    /// Service detail ("ICE 123"), platform and clock time.
    static func detailText(_ st: StopTime) -> String {
        var parts: [String] = []
        if let detail = st.serviceDetail { parts.append(detail) }
        if let track = TransitLabels.clean(st.place.track) { parts.append(L10n.f("Pl. %@", track)) }
        parts.append(Fmt.time(st.departureTime, tz: st.place.tz))
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var serviceNote: some View {
        if stopTime.isReplacementBus { Label("Rail replacement bus", systemImage: "bus.fill").font(.footnote.weight(.semibold)).foregroundStyle(Color.delay) }
        if let alert = stopTime.serviceAlerts.first {
            Label(alert.headerText, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote).foregroundStyle(alert.priority == 0 ? Color.danger : Color.delay)
                .lineLimit(2)
        }
    }

    /// The figure: minutes (orange when late), "now", or the clock time from an hour on.
    /// Live or timetable as a small symbol in front of it, not as a word on every row.
    private func minutes(now: Date) -> some View {
        let minutes = Int(ceil(stopTime.departureTime.timeIntervalSince(now) / 60))
        let live = stopTime.realTime && !Connectivity.shared.isOffline
        let late = stopTime.delayMinutes > 0
        return HStack(alignment: .firstTextBaseline, spacing: 3) {
            if stopTime.isCancelled {
                Text(Fmt.time(stopTime.departureTime, tz: stopTime.place.tz))
                    .font(.title3.weight(.bold).monospacedDigit())
                    .strikethrough(true, color: Color.danger)
                    .foregroundStyle(Color.danger)
            } else {
                Image(systemName: live ? "dot.radiowaves.left.and.right" : "calendar")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(live ? Color.live : Color.secondary)
                    .accessibilityHidden(true)
                if minutes <= 0 {
                    Text("now").font(.title2.weight(.bold))
                        .foregroundStyle(late ? Color.delay : Color.primary)
                } else if minutes < 60 {
                    Text(verbatim: "\(minutes)").font(.title2.weight(.bold).monospacedDigit())
                        .foregroundStyle(late ? Color.delay : Color.primary)
                    Text("min").font(.footnote.weight(.medium)).foregroundStyle(.secondary)
                } else {
                    Text(Fmt.time(stopTime.departureTime, tz: stopTime.place.tz))
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(late ? Color.delay : Color.primary)
                }
            }
        }
        .lineLimit(1)
        .fixedSize()
    }

    private var accessibilityText: String {
        var parts = ["\(ModeStyle.label(stopTime.mode)) \(stopTime.lineName)"]
        if let detail = stopTime.serviceDetail { parts.append(detail) }
        if stopTime.isCircular { parts.append(L10n.t("Circle line")) }
        else if let direction = stopTime.directionName { parts.append(L10n.f("Towards %@", direction)) }
        else { parts.append(L10n.t("Direction unavailable")) }
        if stopTime.isReplacementBus { parts.append(L10n.t("Rail replacement bus")) }
        parts.append(contentsOf: stopTime.serviceAlerts.map(\.headerText))
        parts.append(L10n.f("at %@", Fmt.time(stopTime.departureTime, tz: stopTime.place.tz)))
        if stopTime.isCancelled { parts.append(L10n.t("cancelled")) }
        else if stopTime.realTime {
            parts.append(stopTime.delayMinutes > 0 ? L10n.f("live, %lld minutes late", stopTime.delayMinutes) : L10n.t("live, on time"))
        }
        else { parts.append(L10n.t("timetable time, no live data")) }
        if let track = stopTime.place.track, !track.isEmpty { parts.append(L10n.f("platform %@", track)) }
        return parts.joined(separator: ", ")
    }
}

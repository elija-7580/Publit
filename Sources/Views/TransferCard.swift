import SwiftUI

/// The same connection information before travelling, while riding and during the change.
/// Times are the itinerary's last refresh, not a promise that the connection is held.
///
/// Kept short on purpose: line, direction and stop names are already in the legs around it,
/// so the card only answers "where, which platform, how much time".
///   ⇄ Change at Krems Bahnhof          [6 min to spare]
///   5:43 · Platform E2  →  5:52 · Platform 2
///   700 → REX 2807 · 3 min walk
struct TransferCard: View {
    let info: TransferInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(L10n.f("Change at %@", info.arrivalStop.name), systemImage: "arrow.triangle.swap")
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if !info.isCancelled && !info.isMissed { spareBadge }
            }
            if info.changesStation {
                Label(L10n.transfer("Station change") + " · " + info.departureStop.name, systemImage: "figure.walk")
                    .font(.footnote.weight(.semibold)).foregroundStyle(Color.delay)
            }
            Text(verbatim: "\(endpoint(info.arrivalTime, stop: info.arrivalStop))  →  \(endpoint(info.departureTime, stop: info.departureStop))")
                .font(.subheadline.weight(.medium).monospacedDigit())
                .fixedSize(horizontal: false, vertical: true)
            platformChange(info.arrivalStop)
            platformChange(info.departureStop)
            Text(verbatim: details).font(.footnote).foregroundStyle(.secondary)
            if info.isCancelled {
                Label("Connection cancelled", systemImage: "xmark.circle.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Color.danger)
            } else if info.isMissed {
                Label(L10n.f("Change at %@ no longer works", info.arrivalStop.name), systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Color.danger)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("transferCard")
    }

    /// The one number that matters at a glance: time left after walking.
    private var spareBadge: some View {
        let text = info.spareSeconds >= 60
            ? L10n.f("%@ to spare", Fmt.duration(seconds: info.spareSeconds))
            : L10n.t("Very tight change")
        let tint = info.isTight ? Color.delay : Color.secondary
        return Text(verbatim: text)
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(tint)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(tint.opacity(0.15), in: Capsule())
            .lineLimit(1)
            .layoutPriority(1)
    }

    /// "5:43 · Platform E2"; only the time when the platform is unknown.
    private func endpoint(_ time: Date, stop: Place) -> String {
        let t = Fmt.time(time, tz: stop.tz)
        guard let track = TransitLabels.clean(stop.track) else { return t }
        return "\(t) · \(L10n.f("Platform %@", track))"
    }

    /// "700 → REX 2807 · 3 min walk · Live" (Live only when both ends are live).
    private var details: String {
        [
            "\(info.fromLine) → \(info.toLine)",
            info.walkSeconds > 0 ? L10n.f("%@ walk", Fmt.duration(seconds: max(60, info.walkSeconds))) : nil,
            info.levels,
            info.arrivalIsLive && info.departureIsLive ? L10n.t("Live") : nil,
        ].compactMap { $0 }.joined(separator: " · ")
    }

    @ViewBuilder
    private func platformChange(_ stop: Place) -> some View {
        if TransitLabels.clean(stop.track) != nil, let change = stop.platformChange {
            Label(L10n.f("Platform changed (was %@)", change.scheduled), systemImage: "exclamationmark.triangle.fill")
                .font(.footnote.weight(.semibold)).foregroundStyle(Color.delay)
        }
    }
}

/// The operator's wording is always visible: do not turn an unstructured notice into a
/// guessed splitting station, destination, carriage number or instruction to move carriages.
struct TrainDivisionNotice: View {
    let leg: Leg

    var body: some View {
        let notices = leg.trainDivisionAlerts
        if !notices.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label(L10n.transfer("Operator notice: train division"), systemImage: "arrow.triangle.branch")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Color.delay)
                ForEach(notices, id: \.self) { alert in
                    VStack(alignment: .leading, spacing: 4) {
                        if !alert.headerText.isEmpty { Text(verbatim: alert.headerText).font(.subheadline.weight(.medium)) }
                        if !alert.descriptionText.isEmpty { Text(verbatim: alert.descriptionText).font(.subheadline) }
                        if let url = TicketLinks.webURL(alert.url) { Link("Operator details", destination: url) }
                    }
                }
                Text(verbatim: L10n.transfer("Check the destination of your train section. Carriage allocation is not available in Publit."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("trainDivisionNotice")
        }
    }
}

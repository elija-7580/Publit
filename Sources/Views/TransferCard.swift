import SwiftUI

/// The same connection information before travelling, while riding and during the change.
/// Times are the itinerary's last refresh, not a promise that the connection is held.
struct TransferCard: View {
    let info: TransferInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L10n.transfer("Change: %@ → %@", info.fromLine, info.toLine), systemImage: "arrow.triangle.swap")
                .font(.subheadline.weight(.semibold))
            endpoint(stop: info.arrivalStop, time: info.arrivalTime, live: info.arrivalIsLive,
                     line: info.fromLine, service: info.fromService, direction: info.fromDirection,
                     label: L10n.t("Arrive"))
            if info.changesStation {
                Label(L10n.transfer("Station change"), systemImage: "figure.walk")
                    .font(.caption.weight(.semibold)).foregroundStyle(Color.delay)
            }
            endpoint(stop: info.departureStop, time: info.departureTime, live: info.departureIsLive,
                     line: info.toLine, service: info.toService, direction: info.toDirection,
                     label: L10n.t("Departure"))
            if let levels = info.levels { Text(verbatim: levels).font(.caption).foregroundStyle(.secondary) }
            if info.isCancelled {
                Label("Connection cancelled", systemImage: "xmark.circle.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Color.danger)
            } else if info.isMissed {
                Label(L10n.f("Change at %@ no longer works", info.arrivalStop.name), systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Color.danger)
            } else {
                Text(L10n.transfer("Connection time: %@", Fmt.duration(seconds: max(0, info.connectionSeconds))))
                    .font(.caption.weight(.semibold))
                Text(verbatim: [
                    info.walkSeconds > 0 ? L10n.f("%@ walk", Fmt.duration(seconds: max(60, info.walkSeconds))) : nil,
                    info.spareSeconds >= 60 ? L10n.f("%@ to spare", Fmt.duration(seconds: info.spareSeconds))
                        : L10n.t("Very tight change")
                ].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(info.isTight ? Color.delay : Color.secondary)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("transferCard")
    }

    private func endpoint(stop: Place, time: Date, live: Bool, line: String, service: String?,
                          direction: String?, label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            // No fixed widths: long station names and larger accessibility text can wrap.
            Text(verbatim: "\(label) · \(Fmt.time(time, tz: stop.tz)) · \(L10n.t(live ? "Live" : "Timetable"))")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            Text(verbatim: stop.name).font(.subheadline.weight(.medium))
            Text(verbatim: [line, service, direction.map { L10n.f("Towards %@", $0) }]
                .compactMap { $0 }.joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary)
            if let track = TransitLabels.clean(stop.track) {
                Text(L10n.f("Platform %@", track)).font(.subheadline.weight(.semibold))
                if let change = stop.platformChange {
                    Label(L10n.f("Platform changed (was %@)", change.scheduled), systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold)).foregroundStyle(Color.delay)
                }
            } else {
                Text(verbatim: L10n.transfer("Platform not available")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
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
                    .font(.caption).foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("trainDivisionNotice")
        }
    }
}

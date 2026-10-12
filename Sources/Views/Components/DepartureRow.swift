import SwiftUI

struct DepartureRow: View {
    let stopTime: StopTime

    var body: some View {
        HStack(spacing: 10) {
            LineBadge(stopTime)
                .frame(minWidth: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(stopTime.headsign.isEmpty ? "—" : stopTime.headsign)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let track = stopTime.place.track, !track.isEmpty {
                        Text("Platform \(track)")
                    }
                    if stopTime.isCancelled {
                        Text("Cancelled").foregroundStyle(Color.danger)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            DepartureTimeView(actual: stopTime.departureTime,
                              delayMinutes: stopTime.delayMinutes,
                              realTime: stopTime.realTime,
                              cancelled: stopTime.isCancelled,
                              tz: stopTime.place.tz)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts = ["\(ModeStyle.label(stopTime.mode)) \(stopTime.lineName)"]
        if !stopTime.headsign.isEmpty { parts.append("to \(stopTime.headsign)") }
        parts.append("at \(Fmt.time(stopTime.departureTime, tz: stopTime.place.tz))")
        if stopTime.isCancelled { parts.append("cancelled") }
        else if stopTime.realTime { parts.append(stopTime.delayMinutes > 0 ? "live, \(stopTime.delayMinutes) minutes late" : "live, on time") }
        else { parts.append("timetable time, no live data") }
        if let track = stopTime.place.track, !track.isEmpty { parts.append("platform \(track)") }
        return parts.joined(separator: ", ")
    }
}

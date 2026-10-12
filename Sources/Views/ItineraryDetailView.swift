import SwiftUI
import MapKit

struct CompareMapView: View {
    let itineraries: [Itinerary]
    let selectedId: String?

    /// Selected route is drawn last so it sits on top.
    private var ordered: [Itinerary] {
        itineraries.filter { $0.id != selectedId } + itineraries.filter { $0.id == selectedId }
    }

    var body: some View {
        Map(initialPosition: .automatic) {
            UserAnnotation()
            ForEach(ordered) { it in
                let isSelected = it.id == selectedId
                ForEach(Array(it.legs.enumerated()), id: \.offset) { _, leg in
                    MapPolyline(coordinates: leg.legGeometry.clCoordinates)
                        .stroke(isSelected ? leg.lineColor : Color.gray.opacity(0.45),
                                style: StrokeStyle(lineWidth: isSelected ? 5 : 3, lineCap: .round, lineJoin: .round,
                                                   dash: leg.isTransit ? [] : [2, 6]))
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
    }
}

struct ItineraryDetailView: View {
    let itinerary: Itinerary
    var fromName: String = ""
    var toName: String = ""
    /// Shown above the summary for saved trips ("On time", "Leave in 6 min", …).
    var status: TripStatus? = nil
    var refreshedAt: Date? = nil

    private var resolvedFrom: String { fromName.isEmpty ? Self.placeName(itinerary.legs.first?.from) : fromName }
    private var resolvedTo: String { toName.isEmpty ? Self.placeName(itinerary.legs.last?.to) : toName }

    /// MOTIS names coordinate endpoints "START"/"END".
    static func placeName(_ p: Place?) -> String {
        guard let p, p.name != "START", p.name != "END" else { return "Destination" }
        return p.name
    }

    var body: some View {
        List {
            Section {
                Map(initialPosition: .automatic) {
                    UserAnnotation()
                    ForEach(Array(itinerary.legs.enumerated()), id: \.offset) { _, leg in
                        MapPolyline(coordinates: leg.legGeometry.clCoordinates)
                            .stroke(leg.isTransit ? leg.lineColor : Color.gray,
                                    style: StrokeStyle(lineWidth: leg.isTransit ? 5 : 3, lineCap: .round, lineJoin: .round,
                                                       dash: leg.isTransit ? [] : [2, 6]))
                    }
                    if let first = itinerary.legs.first {
                        Marker("Start", systemImage: "circle.fill", coordinate: first.from.coordinate.clCoordinate)
                            .tint(.green)
                    }
                    if let last = itinerary.legs.last {
                        Marker("Destination", systemImage: "flag.fill", coordinate: last.to.coordinate.clCoordinate)
                            .tint(.red)
                    }
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
                .frame(height: 260)
                .listRowInsets(EdgeInsets())
            }

            Section {
                if let status {
                    StatusBanner(status: status, refreshedAt: refreshedAt)
                }
                HStack {
                    VStack(alignment: .leading) {
                        Text("\(Fmt.time(itinerary.startTime, tz: itinerary.legs.first?.from.tz)) – \(Fmt.time(itinerary.endTime, tz: itinerary.legs.last?.to.tz))")
                            .font(.title3.weight(.semibold).monospacedDigit())
                        Text(Fmt.changes(itinerary.transfers))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(Fmt.duration(seconds: itinerary.duration)).font(.title3.weight(.semibold))
                }
                ForEach(TransferRisk.warnings(for: itinerary), id: \.self) { w in
                    Label(w.message, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(w.level == .missed ? Color.danger : Color.delay)
                }
                if let note = Fmt.foreignZoneNote(tz: itinerary.legs.first?.from.tz, at: itinerary.startTime) {
                    Label(note, systemImage: "clock").font(.footnote).foregroundStyle(.secondary)
                }
            }

            Section("Steps") {
                ForEach(Array(itinerary.legs.enumerated()), id: \.offset) { _, leg in
                    LegRow(leg: leg)
                }
            }

            TripActionsSection(itinerary: itinerary, fromName: resolvedFrom, toName: resolvedTo)

        }
        .navigationTitle("Route")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { ShowTicketButton() }
        }
    }
}

struct LegRow: View {
    let leg: Leg

    var body: some View {
        if leg.isTransit {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    LineBadge(leg)
                    if let h = leg.headsign, !h.isEmpty {
                        Text("→ \(h)").font(.subheadline).lineLimit(1)
                    }
                    Spacer()
                    if leg.realTime {
                        Text("live").font(.caption2.weight(.bold)).foregroundStyle(Color.live)
                    }
                }
                stopLine(time: leg.startTime, delay: leg.delayMinutes, name: leg.from.name, track: leg.from.track, tz: leg.from.tz)
                let stops = leg.intermediateStops?.count ?? 0
                Text("\(Fmt.stops(stops)) · \(Fmt.duration(seconds: leg.duration))")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.leading, 52)
                stopLine(time: leg.endTime,
                         delay: Int((leg.endTime.timeIntervalSince(leg.scheduledEndTime) / 60).rounded()),
                         name: leg.to.name, track: leg.to.track, tz: leg.to.tz)
                if leg.cancelled == true {
                    Text("This trip is cancelled.").font(.caption.weight(.semibold)).foregroundStyle(Color.danger)
                }
                ForEach(leg.alerts ?? [], id: \.self) { a in
                    Label(a.headerText, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(Color.delay)
                }
                GetOffButton(leg: leg)
                    .padding(.leading, 52)
            }
            .padding(.vertical, 4)
        } else {
            HStack(spacing: 8) {
                Image(systemName: ModeStyle.symbol(leg.mode)).foregroundStyle(.secondary).frame(width: 24)
                Text("\(ModeStyle.label(leg.mode)) \(Fmt.duration(seconds: leg.duration))")
                if let d = leg.distance, d > 0 {
                    Text("· \(Fmt.distance(meters: d))").foregroundStyle(.secondary)
                }
                Spacer()
            }
            .font(.subheadline)
        }
    }

    private func stopLine(time: Date, delay: Int, name: String, track: String?, tz: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(Fmt.time(time, tz: tz)).font(.subheadline.weight(.semibold).monospacedDigit()).frame(width: 52, alignment: .leading)
            if delay > 0 {
                Text("+\(delay)").font(.caption.monospacedDigit()).foregroundStyle(Color.delay)
            }
            Text(name).font(.subheadline).lineLimit(1)
            Spacer()
            if let track, !track.isEmpty {
                Text("Pl. \(track)").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// "Remind me to get off" for one transit leg.
struct GetOffButton: View {
    let leg: Leg
    @State private var scheduled = false
    @State private var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                Task { await toggle() }
            } label: {
                Label(scheduled ? "Reminder set" : "Remind me to get off",
                      systemImage: scheduled ? "bell.fill" : "bell")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderless)
            if let note {
                Text(note).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .task { scheduled = await GetOffReminder.isScheduled(leg) }
    }

    private func toggle() async {
        if scheduled {
            GetOffReminder.cancel(for: leg)
            scheduled = false
            note = nil
            return
        }
        switch await GetOffReminder.schedule(for: leg) {
        case .scheduled(let date):
            scheduled = true
            note = "We'll notify you at \(Fmt.time(date, tz: leg.to.tz))."
        case .tooLate:
            note = "This stop is less than two minutes away."
        case .denied:
            note = "Allow notifications for Publit in Settings."
        }
    }
}

/// Live state of a saved trip.
struct StatusBanner: View {
    let status: TripStatus
    let refreshedAt: Date?

    private var color: Color {
        switch status.phase {
        case .cancelled: return .danger
        default: return status.delayMinutes > 0 ? .delay : .live
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(status.headline).font(.headline)
                Spacer()
                if status.phase != .arrived && status.phase != .cancelled {
                    Text(status.delayMinutes > 0 ? "+\(status.delayMinutes) min" : "On time")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(color)
                }
            }
            Text(status.detail).font(.subheadline).foregroundStyle(status.phase == .cancelled ? Color.danger : .secondary)
            if let refreshedAt {
                Text("Updated \(refreshedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

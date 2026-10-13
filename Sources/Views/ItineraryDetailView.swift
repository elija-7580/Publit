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
                                style: StrokeStyle(lineWidth: isSelected ? 5 : 3, lineCap: leg.isTransit ? .round : .butt, lineJoin: .round,
                                                   dash: leg.isTransit ? [] : [6, 4]))
                }
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
    }
}

struct ItineraryDetailView: View {
    @Environment(TripStore.self) private var trips
    /// False once this screen is popped or dismissed (still true while a child screen is pushed).
    @Environment(\.isPresented) private var isPresented
    let itinerary: Itinerary
    var fromName: String = ""
    var toName: String = ""
    /// Live state of a saved trip ("On time", "Leave in 6 min", …), evaluated every 30 s.
    /// Only the banner redraws on that timer, not the map and the steps.
    var statusAt: ((Date) -> TripStatus)? = nil
    var refreshedAt: Date? = nil

    private var isBikeOrCar: Bool {
        let m = StreetComparison.streetMode(itinerary)
        return m == "BIKE" || m == "CAR"
    }

    private var resolvedFrom: String { fromName.isEmpty ? Self.placeName(itinerary.legs.first?.from) : fromName }
    private var resolvedTo: String { toName.isEmpty ? Self.placeName(itinerary.legs.last?.to) : toName }

    /// MOTIS names coordinate endpoints "START"/"END".
    static func placeName(_ p: Place?) -> String {
        guard let p, p.name != "START", p.name != "END" else { return L10n.t("Destination") }
        return p.name
    }

    var body: some View {
        let warnings = TransferRisk.warnings(for: itinerary)
        List {
            // 1. What matters first: when, how long, which lines, live state and warnings.
            Section {
                if let statusAt {
                    TimelineView(.periodic(from: .now, by: 30)) { ctx in
                        StatusBanner(status: statusAt(ctx.date), refreshedAt: refreshedAt)
                    }
                }
                RouteSummary(itinerary: itinerary)
                ForEach(warnings, id: \.self) { w in
                    Label(w.message, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(w.level == .missed ? Color.danger : Color.delay)
                }
                if let note = Fmt.foreignZoneNote(tz: itinerary.legs.first?.from.tz, at: itinerary.startTime) {
                    Label(note, systemImage: "clock").font(.footnote).foregroundStyle(.secondary)
                }
                if StreetComparison.streetMode(itinerary) == "CAR" {
                    Label("Driving times are without traffic and parking.", systemImage: "info.circle")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }

            // 2. What you can do with it, right below: start, save, calendar, reminder.
            // Cycling and driving are shown for comparison only: no trip, reminder or fares.
            if !isBikeOrCar {
                TripActionsSection(itinerary: itinerary, fromName: resolvedFrom, toName: resolvedTo)
            }

            // 3. The way, step by step.
            Section("Steps") {
                ForEach(Array(itinerary.legs.enumerated()), id: \.offset) { _, leg in
                    LegRow(leg: leg)
                }
            }

            // 4. The map last: it is the most expensive row and the List only builds it when it scrolls in.
            Section {
                RouteMap(itinerary: itinerary)
                    .frame(height: 240)
                    .listRowInsets(EdgeInsets())
            }

            if !isBikeOrCar { FareSection(itinerary: itinerary) }
        }
        .navigationTitle("Route")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if Features.passes { ToolbarItem(placement: .topBarTrailing) { ShowPassButton(tripId: trips.saved(itinerary)?.id, at: itinerary.startTime) } }
        }
        // A trip unsaved here is only deleted when the screen closes, not when a detail is pushed.
        .onDisappear { if !isPresented { trips.discardPendingRemovals() } }
        .onChange(of: isPresented) { _, presented in if !presented { trips.discardPendingRemovals() } }
    }
}

/// Time, duration and the chain of lines, e.g. 🚶 › S8 › U6 › 🚶.
struct RouteSummary: View {
    let itinerary: Itinerary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(Fmt.time(itinerary.startTime, tz: itinerary.legs.first?.from.tz)) – \(Fmt.time(itinerary.endTime, tz: itinerary.legs.last?.to.tz))")
                    .font(.title2.weight(.bold).monospacedDigit())
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 8)
                Text(Fmt.duration(seconds: itinerary.duration)).font(.title3.weight(.semibold))
                    .lineLimit(1).fixedSize()
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("\(Fmt.time(itinerary.startTime, tz: itinerary.legs.first?.from.tz)) – \(Fmt.time(itinerary.endTime, tz: itinerary.legs.last?.to.tz))")
                    .font(.title2.bold().monospacedDigit())
                Text(Fmt.duration(seconds: itinerary.duration)).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            }
            }
            legChain
            HStack(spacing: 6) {
                Text(Fmt.changes(itinerary.transfers))
                if itinerary.hasRealtime && !Connectivity.shared.isOffline {
                    Text(verbatim: "·")
                    Label("Live", systemImage: "dot.radiowaves.left.and.right")
                        .foregroundStyle(Color.live)
                }
                if itinerary.isCancelled {
                    Text(verbatim: "·")
                    Text("Cancelled").foregroundStyle(Color.danger)
                }
            }
            .font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var legChain: some View {
        // Short walks between platforms are noise in the overview; the steps list keeps them.
        let legs = itinerary.legs.filter { $0.isTransit || $0.duration >= 120 }
        return FlowRow(spacing: 4) {
            ForEach(Array(legs.enumerated()), id: \.offset) { i, leg in
                HStack(spacing: 4) {
                    if i > 0 {
                        Image(systemName: "chevron.compact.right").font(.caption).foregroundStyle(.tertiary)
                    }
                    if leg.isTransit {
                        LineBadge(leg)
                    } else {
                        HStack(spacing: 2) {
                            Image(systemName: ModeStyle.symbol(leg.mode))
                            Text(verbatim: "\(max(1, leg.duration / 60))")
                        }
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

/// Wraps its children onto new lines when they do not fit (long routes with many changes).
struct FlowRow: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, width: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > maxWidth { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
            width = max(width, x - spacing)
        }
        return CGSize(width: min(width, maxWidth), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX, x + s.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}

/// The whole route on a map, with start and destination.
struct RouteMap: View {
    let itinerary: Itinerary

    var body: some View {
        Map(initialPosition: .automatic) {
            UserAnnotation()
            ForEach(Array(itinerary.legs.enumerated()), id: \.offset) { _, leg in
                MapPolyline(coordinates: leg.legGeometry.clCoordinates)
                    .stroke(leg.isTransit ? leg.lineColor : Color.gray,
                            style: StrokeStyle(lineWidth: leg.isTransit ? 5 : 4, lineCap: leg.isTransit ? .round : .butt, lineJoin: .round,
                                               dash: leg.isTransit ? [] : [6, 4]))
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
    }
}

struct LegRow: View {
    let leg: Leg

    var body: some View {
        if leg.isTransit {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    LineBadge(leg)
                    if let detail = leg.serviceDetail {
                        Text(verbatim: detail).font(.caption.weight(.semibold))
                    }
                    Spacer(minLength: 4)
                    Text(leg.realTime && !Connectivity.shared.isOffline ? L10n.t("Live") : L10n.t("Timetable"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                DirectionLabel(direction: leg.directionName)
                if leg.isReplacementBus { Label("Rail replacement bus", systemImage: "bus.fill").font(.subheadline.weight(.semibold)).foregroundStyle(Color.delay) }
                stopLine(label: "Board here", time: leg.startTime, delay: leg.delayMinutes,
                         name: leg.from.name, track: leg.from.track, tz: leg.from.tz)
                if let stops = leg.intermediateStops {
                    Text("\(Fmt.stops(stops.count)) · \(Fmt.duration(seconds: leg.duration))")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(Fmt.duration(seconds: leg.duration)).font(.caption).foregroundStyle(.secondary)
                }
                stopLine(label: "Get off here", time: leg.endTime,
                         delay: Int((leg.endTime.timeIntervalSince(leg.scheduledEndTime) / 60).rounded()),
                         name: leg.to.name, track: leg.to.track, tz: leg.to.tz)
                if leg.cancelled == true {
                    Text("This trip is cancelled.").font(.caption.weight(.semibold)).foregroundStyle(Color.danger)
                }
                ServiceAlertsView(alerts: leg.serviceAlerts)
                GetOffButton(leg: leg)
            }
            .padding(.vertical, 6)
            .padding(.leading, 12)
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(leg.lineColor).frame(width: 4).padding(.vertical, 6)
                    .accessibilityHidden(true)
            }
            .accessibilityIdentifier("transitLeg")
        } else {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: leg.rental.map { $0.kind.symbol } ?? ModeStyle.symbol(leg.mode))
                    .foregroundStyle(leg.rental == nil ? Color.secondary : Color.teal).frame(width: 24)
                VStack(alignment: .leading, spacing: 4) {
                    if let r = leg.rental {
                        // Shared bike or scooter: whose, from where, and a link to rent it.
                        Text(verbatim: "\(r.kind.title) · \(r.systemName ?? ModeStyle.label(leg.mode)) · \(Fmt.duration(seconds: leg.duration))")
                        if let from = r.fromStationName, !from.isEmpty {
                            Text(L10n.f("Pick up at %@", from)).foregroundStyle(.secondary)
                        }
                        if let to = r.toStationName, !to.isEmpty {
                            Text(L10n.f("Return at %@", to)).foregroundStyle(.secondary)
                        }
                        if let d = leg.distance, d > 0 { Text(Fmt.distance(meters: d)).foregroundStyle(.secondary) }
                        if let url = r.bookingURL {
                            Link(destination: url) { Label("Rent in the provider's app", systemImage: "arrow.up.forward.app") }
                                .font(.subheadline.weight(.semibold))
                        }
                    } else {
                        Text("\(ModeStyle.label(leg.mode)) \(Fmt.duration(seconds: leg.duration))")
                        if let d = leg.distance, d > 0 { Text(Fmt.distance(meters: d)).foregroundStyle(.secondary) }
                    }
                }
                Spacer(minLength: 0)
            }
            .font(.subheadline)
        }
    }

    private func stopLine(label: LocalizedStringKey, time: Date, delay: Int, name: String,
                          track: String?, tz: String?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Fmt.time(time, tz: tz)).font(.subheadline.weight(.semibold).monospacedDigit())
                    .lineLimit(1).fixedSize()
                if delay > 0 { Text(L10n.f("+%lld min", delay)).font(.caption).foregroundStyle(Color.delay) }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text(verbatim: name).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                if let track = TransitLabels.clean(track) {
                    Text(L10n.f("Platform %@", track)).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
                Label(scheduled ? L10n.t("Reminder set") : L10n.t("Remind me to get off"),
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
            note = L10n.f("We'll notify you at %@.", Fmt.time(date, tz: leg.to.tz))
        case .tooLate:
            note = L10n.t("This stop is less than two minutes away.")
        case .denied:
            note = L10n.t("Allow notifications for Publit in Settings.")
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
                    Text(status.delayMinutes > 0 ? L10n.f("+%lld min", status.delayMinutes) : L10n.t("On time"))
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

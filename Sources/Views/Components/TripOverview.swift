import SwiftUI

/// Arrival and the complete route come before maps and turn-by-turn instructions.
struct TripArrivalCard: View {
    let trip: SavedTrip
    let now: Date
    @ScaledMetric(relativeTo: .largeTitle) private var timeSize: CGFloat = 42

    var body: some View {
        let it = trip.itinerary
        let status = TripStatus.at(now, it)
        let remaining = max(0, Int(it.endTime.timeIntervalSince(now)))
        InkPanel {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    HStack(spacing: 5) {
                        SignatureDot()
                        Text(status.phase == .arrived ? L10n.t("Arrived") : L10n.t("Live trip"))
                    }
                    .font(.caption.weight(.semibold)).padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Color.inkFill, in: Capsule())
                    if status.phase == .cancelled {
                        Text("Cancelled").font(.caption.weight(.semibold)).foregroundStyle(Color.danger)
                    } else if it.hasRealtime {
                        Text(verbatim: status.delayMinutes > 0 ? L10n.f("+%lld min", status.delayMinutes) : L10n.t("On time"))
                            .font(.caption.weight(.semibold)).foregroundStyle(status.delayMinutes > 0 ? Color.delay : Color.live)
                    }
                }
                Text(verbatim: L10n.f("Arrive at %@", trip.toName)).font(.subheadline).foregroundStyle(.secondary)
                FlowRow(spacing: 8) {
                    Text(Fmt.time(it.endTime, tz: it.legs.last?.to.tz))
                        .font(.system(size: timeSize, weight: .bold).monospacedDigit()).tracking(-1)
                    Text(verbatim: status.phase == .arrived ? L10n.t("Arrived") : L10n.f("in %@", Fmt.duration(seconds: remaining)))
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 20)
                }
                InkProgress(value: now.timeIntervalSince(it.startTime) / max(it.endTime.timeIntervalSince(it.startTime), 60))
                HStack {
                    Text(verbatim: "\(Fmt.time(it.startTime, tz: it.legs.first?.from.tz)) \(trip.fromName)").lineLimit(1)
                    Spacer()
                    Text(Fmt.time(it.endTime, tz: it.legs.last?.to.tz))
                }
                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("tripArrivalCard")
    }
}

struct TripTimelineView: View {
    let itinerary: Itinerary
    let fromName: String
    let toName: String
    let now: Date
    var onSelectLeg: (Int) -> Void = { _ in }

    var body: some View {
        InkPanel {
            VStack(spacing: 0) {
                ForEach(Array(itinerary.legs.enumerated()), id: \.offset) { index, leg in
                    Button { onSelectLeg(index) } label: {
                        TimelineLeg(leg: leg,
                                    startName: index == 0 ? fromName : ItineraryDetailView.placeName(leg.from),
                                    endName: index == itinerary.legs.count - 1 ? toName : ItineraryDetailView.placeName(leg.to),
                                    current: now >= leg.startTime && now < leg.endTime)
                    }
                    .buttonStyle(.plain).accessibilityIdentifier("timeline-leg-\(index)")
                }
            }
        }
        .accessibilityIdentifier("tripTimeline")
    }
}

private struct TimelineLeg: View {
    let leg: Leg
    let startName: String
    let endName: String
    let current: Bool
    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 9, verticalSpacing: 0) {
            GridRow(alignment: .top) {
                clock(leg.startTime, scheduled: leg.scheduledStartTime, tz: leg.from.tz)
                Circle().fill(current ? Color.signature : Color.surface)
                    .overlay(Circle().strokeBorder(current ? Color.signature : Color.ink, lineWidth: 3))
                    .frame(width: 14, height: 14).padding(.top, 3).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    FlowRow(spacing: 6) {
                        if leg.isTransit { LineBadge(leg, compact: true) }
                        Text(verbatim: startName).font(.subheadline.weight(.semibold))
                    }
                    if let track = TransitLabels.clean(leg.from.track) {
                        Text(verbatim: L10n.f("Platform %@", track)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            GridRow {
                Color.clear.frame(width: 44, height: 38).gridCellUnsizedAxes(.vertical)
                Path { p in p.move(to: CGPoint(x: 7, y: 0)); p.addLine(to: CGPoint(x: 7, y: 38)) }
                    .stroke(leg.isTransit ? Color.ink : Color.secondary,
                            style: StrokeStyle(lineWidth: 3, dash: leg.isTransit ? [] : [4, 4]))
                    .frame(width: 14, height: 38).accessibilityHidden(true)
                HStack(spacing: 6) {
                    if !leg.isTransit { Image(systemName: ModeStyle.symbol(leg.mode)).foregroundStyle(.secondary) }
                    DurationFigure(seconds: leg.duration, size: 20)
                    if leg.isTransit, let stops = leg.intermediateStops, !stops.isEmpty {
                        Text(verbatim: "· " + Fmt.stops(stops.count)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            GridRow(alignment: .top) {
                clock(leg.endTime, scheduled: leg.scheduledEndTime, tz: leg.to.tz)
                Circle().strokeBorder(Color.ink, lineWidth: 3).frame(width: 14, height: 14)
                    .padding(.top, 3).accessibilityHidden(true)
                Text(verbatim: endName).font(.subheadline.weight(.semibold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 12)
        .contentShape(Rectangle()).accessibilityElement(children: .combine)
    }
    private func clock(_ actual: Date, scheduled: Date, tz: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Fmt.time(scheduled, tz: tz)).font(.caption.weight(.bold).monospacedDigit())
            if leg.realTime && abs(actual.timeIntervalSince(scheduled)) >= 30 {
                Text(Fmt.time(actual, tz: tz)).font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(actual > scheduled ? Color.delay : Color.live)
            }
        }
        .frame(width: 44, alignment: .leading)
    }
}

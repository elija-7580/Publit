import SwiftUI
import WidgetKit
import ActivityKit

/// Picks the bundle at launch: from iOS 18 the Live Activity is also offered to Apple Watch.
@main
enum PublitWidgetsEntry {
    static func main() {
        if #available(iOS 18.0, *) {
            PublitWidgetsWithWatch.main()
        } else {
            PublitWidgets.main()
        }
    }
}

struct PublitWidgets: WidgetBundle {
    var body: some Widget {
        DeparturesWidget()
        TripLiveActivity()
    }
}

@available(iOS 18.0, *)
struct PublitWidgetsWithWatch: WidgetBundle {
    var body: some Widget {
        DeparturesWidget()
        WatchTripLiveActivity()
    }
}

private extension Color {
    init(hexString: String?, fallback: Color) {
        guard var s = hexString, !s.isEmpty else { self = fallback; return }
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { self = fallback; return }
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

private struct LineChip: View {
    let state: TripActivityAttributes.ContentState
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        if let name = state.lineName {
            Text(name)
                .font(.caption.weight(.bold))
                .lineLimit(1)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color(hexString: state.lineColor, fallback: .gray), in: RoundedRectangle(cornerRadius: 5))
                .foregroundStyle(Color(hexString: state.lineTextColor, fallback: .white))
                // Near-black lines on the dark Dynamic Island and lock screen get an edge.
                .overlay {
                    if LineColors.blendsIn(state.lineColor, dark: scheme == .dark) {
                        RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.45), lineWidth: 1)
                    }
                }
        } else {
            Image(systemName: "figure.walk")
        }
    }
}

/// The platform of the next departure; orange when it changed.
private struct PlatformChip: View {
    let state: TripActivityAttributes.ContentState
    var body: some View {
        if let p = state.platform {
            let changed = state.platformChanged == true
            HStack(spacing: 3) {
                if changed { Image(systemName: "exclamationmark.triangle.fill") }
                Text(p)
            }
            .font(.caption.weight(.bold))
            .lineLimit(1)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .foregroundStyle(changed ? Color.orange : Color.primary)
            .background((changed ? Color.orange : Color.secondary).opacity(0.18), in: RoundedRectangle(cornerRadius: 5))
            .fixedSize()
        }
    }
}

private struct Countdown: View {
    let state: TripActivityAttributes.ContentState
    var body: some View {
        if state.nextEvent > .now {
            Text(timerInterval: Date.now...state.nextEvent, countsDown: true)
                .monospacedDigit()
        } else {
            Text(state.nextEvent, style: .time)
        }
    }
}

/// The same Live Activity, also offered to Apple Watch (Smart Stack) and CarPlay in the small family.
@available(iOS 18.0, *)
struct WatchTripLiveActivity: Widget {
    var body: some WidgetConfiguration {
        TripLiveActivity().body.supplementalActivityFamilies([.small])
    }
}

/// Picks the compact watch layout for the small family, the full one elsewhere.
@available(iOS 18.0, *)
private struct FamilyAdaptiveView: View {
    let attributes: TripActivityAttributes
    let state: TripActivityAttributes.ContentState
    @Environment(\.activityFamily) private var family

    var body: some View {
        switch family {
        case .small:
            SmallActivityView(state: state).padding(8)
        default:
            LockScreenView(attributes: attributes, state: state).padding(16)
        }
    }
}

/// Watch Smart Stack: what to do now, the countdown with what it counts to, the vehicle, and how far along the trip is.
private struct SmallActivityView: View {
    let state: TripActivityAttributes.ContentState
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .top, spacing: 5) {
                StepIcon(state: state, size: 22)
                VStack(alignment: .leading, spacing: 0) {
                    CueLabel(state: state).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    // A running timer takes all the width it can get: kept to the space of "1:23:45".
                    Countdown(state: state).font(.headline.weight(.bold)).frame(maxWidth: 72, alignment: .leading)
                }
                Spacer(minLength: 2)
                LineChip(state: state)
            }
            Text(state.headline).font(.footnote.weight(.semibold)).lineLimit(2)
            HStack(spacing: 4) {
                PlatformChip(state: state)
                DelayText(state: state).font(.caption2.weight(.semibold))
                if let direction = state.direction {
                    Text(verbatim: "→ " + direction).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            TripProgressBar(state: state)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The step under way as an icon: walking in grey, a ride in the colour of its line.
private struct StepIcon: View {
    let state: TripActivityAttributes.ContentState
    var size: CGFloat = 30
    var body: some View {
        let mode = state.stepMode ?? (state.lineName == nil ? "WALK" : "BUS")
        let ride = ModeStyle.isTransit(mode) && state.lineName != nil
        let symbol = state.phase == "arrived" ? "flag.checkered"
            : state.phase == "cancelled" ? "exclamationmark.triangle.fill" : ModeStyle.symbol(mode)
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(ride ? Color(hexString: state.lineTextColor, fallback: .white) : Color.primary)
            .frame(width: size, height: size)
            .background(ride ? Color(hexString: state.lineColor, fallback: .gray) : Color.secondary.opacity(0.22), in: Circle())
            .accessibilityHidden(true)
    }
}

/// What the countdown counts to: "Leave in", "Departs in", "Get off in", "Arrive in".
private struct CueLabel: View {
    let state: TripActivityAttributes.ContentState
    var body: some View {
        switch state.phase {
        case "beforeLeaving": Text("Leave in")
        case "riding": Text("Get off in")
        case "walking", "transfer":
            if state.nextEvent >= state.arrival { Text("Arrive in") } else { Text("Departs in") }
        default: EmptyView()
        }
    }
}

private struct DelayText: View {
    let state: TripActivityAttributes.ContentState
    var body: some View {
        if state.delayMinutes > 0 {
            Text(verbatim: "+\(state.delayMinutes) min").foregroundStyle(.orange)
        }
    }
}

/// From the start of the trip to its arrival. Runs by itself between updates (no redraws needed).
private struct TripProgressBar: View {
    let state: TripActivityAttributes.ContentState
    var body: some View {
        if let start = state.tripStart, start < state.arrival, state.phase != "cancelled" {
            ProgressView(timerInterval: start...state.arrival, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.linear)
            .tint(Color(hexString: state.lineColor, fallback: .accentColor))
            .labelsHidden()
        }
    }
}

/// The vehicle that matters: line, direction, platform and its time (departure while waiting, arrival on board).
private struct VehicleRow: View {
    let state: TripActivityAttributes.ContentState
    var body: some View {
        if state.lineName != nil, state.phase != "arrived" {
            HStack(spacing: 6) {
                LineChip(state: state)
                if let direction = state.direction {
                    Text(verbatim: "→ " + direction).font(.subheadline.weight(.medium)).lineLimit(1)
                }
                Spacer(minLength: 4)
                if state.phase != "riding" { PlatformChip(state: state) }
                if let time = state.legTime {
                    Text(time, style: .time).font(.subheadline.weight(.semibold)).monospacedDigit()
                }
            }
        }
    }
}

private struct ActivityContent: View {
    let attributes: TripActivityAttributes
    let state: TripActivityAttributes.ContentState
    var body: some View {
        if #available(iOS 18.0, *) {
            FamilyAdaptiveView(attributes: attributes, state: state)
        } else {
            LockScreenView(attributes: attributes, state: state).padding(16)
        }
    }
}

struct TripLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TripActivityAttributes.self) { context in
            ActivityContent(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Color(.systemBackground).opacity(0.85))
                .widgetURL(context.attributes.tripURL)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    StepIcon(state: context.state, size: 34).padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 0) {
                        CueLabel(state: context.state).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        Countdown(state: context.state).font(.title3.weight(.semibold))
                    }
                    .frame(maxWidth: 100, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.headline).font(.headline).lineLimit(2).minimumScaleFactor(0.8)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        VehicleRow(state: context.state)
                        if context.state.phase == "riding", let then = context.state.then {
                            HStack(spacing: 6) {
                                Text(then).font(.caption.weight(.semibold)).lineLimit(1)
                                PlatformChip(state: context.state)
                            }
                        }
                        // On board: next stop and stops to go (with location), else when the vehicle arrives.
                        if context.state.phase == "riding", !context.state.detail.isEmpty {
                            Text(context.state.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        TripProgressBar(state: context.state)
                        HStack(spacing: 6) {
                            Image(systemName: "flag.checkered").font(.caption2).foregroundStyle(.secondary)
                            Text(verbatim: context.state.destination ?? context.attributes.title).font(.caption).lineLimit(1)
                            Text(context.state.arrival, style: .time).font(.caption.weight(.semibold)).monospacedDigit()
                            Spacer(minLength: 4)
                            if context.attributes.hasTicket {
                                Link(destination: context.attributes.ticketsURL) {
                                    Label("Show ticket", systemImage: "ticket").font(.caption.weight(.semibold))
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                HStack(spacing: 4) {
                    Image(systemName: ModeStyle.symbol(context.state.stepMode ?? "WALK"))
                    if context.state.stepMode.map(ModeStyle.isTransit) ?? false { LineChip(state: context.state) }
                }
            } compactTrailing: {
                Countdown(state: context.state).frame(maxWidth: 52)
            } minimal: {
                Countdown(state: context.state).frame(maxWidth: 44)
            }
            .widgetURL(context.attributes.tripURL)
        }
    }
}

private struct LockScreenView: View {
    let attributes: TripActivityAttributes
    let state: TripActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // What to do now, and the countdown with what it counts to.
            HStack(alignment: .top, spacing: 10) {
                StepIcon(state: state, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.headline).font(.headline).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    if state.phase == "beforeLeaving", let stop = state.boardAt {
                        Text(L10n.f("from %@", stop)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    } else if state.phase == "riding" || state.lineName == nil, !state.detail.isEmpty {
                        Text(state.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 0) {
                    CueLabel(state: state).font(.caption.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
                    Countdown(state: state).font(.title2.weight(.bold)).multilineTextAlignment(.trailing)
                    DelayText(state: state).font(.caption.weight(.semibold))
                }
                .frame(maxWidth: 110, alignment: .trailing)
            }
            VehicleRow(state: state)
            if state.phase == "riding", let then = state.then {
                HStack(spacing: 6) {
                    Text(then).font(.caption.weight(.semibold)).lineLimit(1)
                    PlatformChip(state: state)
                }
            }
            // How far along, where it ends and when, and the ticket.
            VStack(alignment: .leading, spacing: 4) {
                TripProgressBar(state: state)
                HStack(spacing: 6) {
                    Image(systemName: "flag.checkered").font(.caption2).foregroundStyle(.secondary)
                    Text(verbatim: state.destination ?? attributes.title).font(.caption).lineLimit(1)
                    Text(state.arrival, style: .time).font(.caption.weight(.semibold)).monospacedDigit()
                    Spacer(minLength: 4)
                    if attributes.hasTicket {
                        Link(destination: attributes.ticketsURL) {
                            Label("Show ticket", systemImage: "ticket")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(.tint.opacity(0.15), in: Capsule())
                        }
                    }
                }
            }
        }
    }
}

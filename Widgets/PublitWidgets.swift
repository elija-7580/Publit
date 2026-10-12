import SwiftUI
import WidgetKit
import ActivityKit

@main
struct PublitWidgets: WidgetBundle {
    var body: some Widget {
        DeparturesWidget()
        TripLiveActivity()
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
    var body: some View {
        if let name = state.lineName {
            Text(name)
                .font(.caption.weight(.bold))
                .lineLimit(1)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color(hexString: state.lineColor, fallback: .gray), in: RoundedRectangle(cornerRadius: 5))
                .foregroundStyle(Color(hexString: state.lineTextColor, fallback: .white))
        } else {
            Image(systemName: "figure.walk")
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

struct TripLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TripActivityAttributes.self) { context in
            LockScreenView(attributes: context.attributes, state: context.state)
                .padding(16)
                .activityBackgroundTint(Color(.systemBackground).opacity(0.85))
                .widgetURL(context.attributes.tripURL)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    LineChip(state: context.state).padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Countdown(state: context.state).font(.title3.weight(.semibold))
                        .frame(maxWidth: 90, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(context.state.headline).font(.headline)
                        Text(context.state.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        if context.attributes.hasTicket {
                            Link(destination: context.attributes.ticketsURL) {
                                Label("Show ticket", systemImage: "ticket").font(.caption.weight(.semibold))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                LineChip(state: context.state)
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
            HStack(alignment: .firstTextBaseline) {
                LineChip(state: state)
                Text(state.headline).font(.headline).lineLimit(1)
                Spacer()
                Countdown(state: state).font(.title2.weight(.bold)).multilineTextAlignment(.trailing)
                    .frame(maxWidth: 110, alignment: .trailing)
            }
            Text(state.detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            HStack {
                Text(attributes.title).font(.caption).lineLimit(1)
                if state.delayMinutes > 0 {
                    Text("+\(state.delayMinutes) min").font(.caption.weight(.semibold)).foregroundStyle(.orange)
                }
                Spacer()
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

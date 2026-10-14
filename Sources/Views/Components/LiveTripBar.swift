import SwiftUI
import UIKit

/// A bar above the tab bar while a saved trip is on: what to do next ("Leave in 6 min",
/// "Get off at …"), the line, delay and how far along the trip is. Tap for the trip with live status.
/// Shown 30 min before leaving until 5 min after arrival, or for the trip started by hand.
/// Swipe up or tap to open; starting a trip does not change the bar into a different layout.
struct LiveTripBar: View {
    @Environment(TripStore.self) private var trips
    @Environment(AppState.self) private var app
    @Environment(PassStore.self) private var passes
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState(resetTransaction: Transaction(animation: .spring(response: 0.35, dampingFraction: 0.8))) private var pull: CGFloat = 0
    /// Hidden by hand for this trip only; the next trip shows again.
    @AppStorage("liveBarHiddenTrip") private var hiddenId = ""

    var body: some View {
        // Minute clock: countdowns are in whole minutes, so one redraw a minute is enough.
        let now = Ticker.minute.now
        let current = trips.current(now: now).flatMap { $0.id == hiddenId ? nil : $0 }
        Group {
            if let trip = current {
                bar(trip, now: now)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    .task(id: "\(trip.id)|\(scenePhase)") { await follow(trip.id) }
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86), value: current?.id)
    }

    private func bar(_ trip: SavedTrip, now: Date) -> some View {
        let it = trip.itinerary
        let started = trips.activeTrip?.id == trip.id
        let status = TripStatus.at(now, it)
        let leg = it.transitLegs.first { $0.endTime > now } ?? it.transitLegs.last
        let progress = min(max(now.timeIntervalSince(it.startTime) / max(it.endTime.timeIntervalSince(it.startTime), 60), 0), 1)
        let minutes = max(0, Int(ceil(status.nextEvent.timeIntervalSince(now) / 60)))
        let headline = status.phase == .riding ? L10n.f("Get off in %lld min", minutes) : status.headline
        return HStack(spacing: 10) {
            Button { app.deepLink = .trip(trip.id) } label: {
                HStack(spacing: 10) {
                    if let leg { LineBadge(leg, compact: true).frame(maxWidth: 64) }
                    else { Image(systemName: "figure.walk").frame(width: 30) }
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Text(verbatim: headline).font(.subheadline.weight(.bold)).lineLimit(1)
                                .contentTransition(.numericText())
                            if status.phase != .cancelled && it.hasRealtime {
                                Text(verbatim: status.delayMinutes > 0 ? "+\(status.delayMinutes)" : L10n.t("On time"))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(status.delayMinutes > 0 ? Color.delay : Color.live).lineLimit(1)
                            }
                        }
                        Text(verbatim: status.detail.isEmpty ? trip.title : status.detail)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        InkProgress(value: progress).padding(.top, 1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityElement(children: .combine).accessibilityIdentifier("liveTripBar")
            if !started && status.phase != .arrived && status.phase != .cancelled {
                Button { Task { await start(trip) } } label: {
                    Image(systemName: "play.fill").font(.subheadline.weight(.bold))
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityLabel(Text("Start trip")).accessibilityIdentifier("liveTripBarStart")
            }
            Button { hiddenId = trip.id } label: {
                Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel(Text("Hide"))
        }
        .padding(.leading, 14).padding(.trailing, 2).padding(.vertical, 8)
        .matteSurface(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .offset(y: reduceMotion ? 0 : pull)
        .simultaneousGesture(DragGesture(minimumDistance: 12)
            .updating($pull) { value, state, transaction in
                transaction.animation = nil
                if abs(value.translation.height) > abs(value.translation.width) {
                    state = max(-36, min(0, value.translation.height * 0.25))
                }
            }
            .onEnded { value in
                if abs(value.translation.height) > abs(value.translation.width),
                   value.translation.height < -40 || (value.translation.height < -15 && value.predictedEndTranslation.height < -100) {
                    app.deepLink = .trip(trip.id)
                }
            })
        .accessibilityAction(named: Text("Open trip")) { app.deepLink = .trip(trip.id) }
    }

    private func start(_ trip: SavedTrip) async {
        app.deepLink = .trip(trip.id)
        await TripSession.start(trip, in: trips, hasTicket: !passes.passes(forTrip: trip.id, at: trip.startTime).isEmpty)
    }

    /// Live times every 90 s while the app is open and the trip is not over.
    private func follow(_ id: String) async {
        #if DEBUG
        if ProcessInfo.processInfo.environment["PUBLIT_UI_SAMPLE"]?.hasPrefix("reference-") == true { return }
        #endif
        guard scenePhase == .active else { return }
        while !Task.isCancelled {
            guard let t = trips.trip(id), t.endTime > .now else { return }
            await SavedTripView.refresh(t, in: trips)
            try? await Task.sleep(for: Energy.duration(90))
        }
    }
}

/// NavigationStack's destinations do not reliably honour an inset applied outside the stack.
/// Measure the actual bar (Dynamic Type included), then reserve it on each content scroller.
private struct LiveBarHeightKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct LiveBarInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var liveBarInset: CGFloat {
        get { self[LiveBarInsetKey.self] }
        set { self[LiveBarInsetKey.self] = newValue }
    }
}

private struct LiveTripBarHost: ViewModifier {
    var showLiveBar = true
    @State private var height: CGFloat = 0
    @State private var keyboardVisible = false

    func body(content: Content) -> some View {
        content
            .environment(\.liveBarInset, height)
            .overlay(alignment: .bottom) {
                VStack(spacing: 8) {
                    if !keyboardVisible {
                        if showLiveBar { LiveTripBar() }
                        InkTabBar()
                    }
                }
                    .padding(.horizontal, 16).padding(.bottom, keyboardVisible ? 0 : 8)
                    .fixedSize(horizontal: false, vertical: true)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(key: LiveBarHeightKey.self, value: proxy.size.height)
                        }
                    }
            }
            .toolbar(.hidden, for: .tabBar)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                keyboardVisible = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                keyboardVisible = false
            }
            .onPreferenceChange(LiveBarHeightKey.self) { value in
                // Geometry must not inherit row/appearance animations and bounce the list.
                guard abs(value - height) > 0.5 else { return }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { height = value }
            }
    }
}

private struct LiveBarPadding: ViewModifier {
    @Environment(\.liveBarInset) private var height
    func body(content: Content) -> some View { content.safeAreaPadding(.bottom, height) }
}

extension View {
    /// Install once, on the tab's NavigationStack. Sheets with no bar reset liveBarInset to zero.
    func liveTripBar() -> some View { modifier(LiveTripBarHost()) }
    func publitDock(showLiveBar: Bool) -> some View { modifier(LiveTripBarHost(showLiveBar: showLiveBar)) }
    func liveBarPadding() -> some View { modifier(LiveBarPadding()) }
}

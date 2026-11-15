import SwiftUI
import Observation
#if canImport(UIKit)
import UIKit
#endif

/// A clock that changes on whole interval boundaries (e.g. every full minute), as a plain
/// observable value instead of a `TimelineView`. Only views that read `now` redraw on a tick.
///
/// Freeze logs from build 11 showed SwiftUI's update loop on the main thread asking itself for
/// the next update while drawing (`requestUpdate(after:)`), for about 15 s, the period of the
/// trip screen's timeline. The timelines are replaced by these tickers.
@MainActor @Observable
final class Ticker {
    /// Shared minute clock for departure countdowns in lists: one timer for all rows.
    static let minute = Ticker(every: 60)

    private(set) var now = Date()
    @ObservationIgnored let interval: TimeInterval
    @ObservationIgnored private var loop: Task<Void, Never>?

    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init(every interval: TimeInterval) {
        self.interval = interval
        start()
        // Back from the background, or the wall clock was changed (time zone, manual time, NTP
        // correction): the sleeping loop no longer lines up with the minute, so tick now and re-align.
        var names: [Notification.Name] = [.NSSystemClockDidChange, .NSSystemTimeZoneDidChange]
        #if canImport(UIKit) && !os(watchOS)
        names += [UIApplication.didBecomeActiveNotification, UIApplication.significantTimeChangeNotification]
        #endif
        observers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
    }

    /// Sets `now` to the current time and starts counting again from it.
    func refresh() {
        now = Date()
        start()
    }

    private func start() {
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let delay = self?.delayToNextTick() else { return }
                try? await Task.sleep(for: .seconds(delay))
                guard let self, !Task.isCancelled else { return }
                self.now = Date()
            }
        }
    }

    private func delayToNextTick() -> TimeInterval {
        Ticker.delay(toNextMultipleOf: interval, from: Date())
    }

    /// Seconds until the next whole multiple of `interval` (counted from the reference date), plus a
    /// short margin so the new minute has begun when views redraw.
    nonisolated static func delay(toNextMultipleOf interval: TimeInterval, from date: Date) -> TimeInterval {
        let t = date.timeIntervalSinceReferenceDate
        let next = (floor(t / interval) + 1) * interval
        return max(0.05, next - t + 0.05)
    }
}

private struct TickKey: Equatable {
    let interval: TimeInterval
    let active: Bool
}

private struct Ticking: ViewModifier {
    let interval: TimeInterval
    @Binding var now: Date
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        // Restarts when the app becomes active again, so the screen is current right after unlocking.
        content.task(id: TickKey(interval: interval, active: scenePhase == .active)) {
            now = Date()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Ticker.delay(toNextMultipleOf: interval, from: Date())))
                if Task.isCancelled { return }
                now = Date()
            }
        }
    }
}

extension View {
    /// Sets `now` to the current time on appear and then on every whole `seconds` boundary while
    /// the view is on screen. Use for one screen-level clock instead of a `TimelineView`.
    func ticking(every seconds: TimeInterval, now: Binding<Date>) -> some View {
        modifier(Ticking(interval: seconds, now: now))
    }
}

/// Redraws `content` with the current time on every whole `every` seconds while on screen.
/// Replaces `TimelineView(.periodic…)` for one small part of a screen.
struct Clocked<Content: View>: View {
    let every: TimeInterval
    @ViewBuilder let content: (Date) -> Content
    @State private var now = Date()

    init(every: TimeInterval, @ViewBuilder content: @escaping (Date) -> Content) {
        self.every = every
        self.content = content
    }

    var body: some View {
        content(now).ticking(every: every, now: $now)
    }
}

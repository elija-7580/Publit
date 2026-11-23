import SwiftUI

/// Publit on the Apple Watch. Tickets, the trip under way, saved trips and stops come from the iPhone and stay on the watch
/// (`WatchLibrary`); where to, nearby departures and the map work on their own, without the iPhone nearby.
@main
struct PublitWatchApp: App {
    @State private var library: WatchLibrary
    @State private var nearby = WatchNearbyModel()
    @State private var path: [WatchRoute]
    /// The trip `WatchAutoOpen` opened since the app came to the front.
    @State private var autoOpened: String?
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        if let demo = WatchDemo.current {
            _library = State(initialValue: demo.library())
            _path = State(initialValue: demo.path())
            return
        }
        #endif
        _library = State(initialValue: WatchLibrary())
        _path = State(initialValue: [])
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack(path: $path) {
                WatchHomeView()
                    .navigationDestination(for: WatchRoute.self) { route in
                        WatchRouteView(route: route, nearby: nearby)
                    }
            }
            .environment(library)
            // A trip started on the iPhone opens by itself, like a route in Maps (also when the app was opened from
            // the trip's Live Activity in the Smart Stack). The data may arrive a moment after the app opened.
            .task { openTripUnderWay() }
            .onChange(of: library.snapshot.activeTripId) { _, _ in openTripUnderWay() }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .background: autoOpened = nil
                case .active: openTripUnderWay()
                default: break
                }
            }
            .onOpenURL { url in
                // The Live Activity's link: publit://trip/<id>.
                if case .trip(let id)? = DeepLink(url: url), library.snapshot.trip(id) != nil {
                    path = [.trip(id)]
                    autoOpened = id
                }
            }
            // Same weekly map of data gaps as on the iPhone (one small file a day at most).
            .task { await CoverageAtlasStore.shared.refreshIfNeeded() }
        }
    }

    private func openTripUnderWay() {
        guard let id = WatchAutoOpen.trip(in: library.snapshot, now: .now, onHome: path.isEmpty, opened: autoOpened) else { return }
        path = [.trip(id)]
        autoOpened = id
    }
}

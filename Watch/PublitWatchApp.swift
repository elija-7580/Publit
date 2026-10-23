import SwiftUI

/// Publit on the Apple Watch. Tickets, the trip under way, saved trips and stops come from the iPhone and stay on the watch
/// (`WatchLibrary`); where to, nearby departures and the map work on their own, without the iPhone nearby.
@main
struct PublitWatchApp: App {
    @State private var library: WatchLibrary
    @State private var nearby = WatchNearbyModel()
    @State private var path: [WatchRoute]

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
        }
    }
}

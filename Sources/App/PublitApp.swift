import SwiftUI

@main
struct PublitApp: App {
    @State private var app = AppState()
    @State private var location = LocationManager()
    @State private var favorites = FavoritesStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(location)
                .environment(favorites)
                .onAppear {
                    app.applyDemo(ProcessInfo.processInfo.environment["PUBLIT_DEMO"])
                    if let tab = ProcessInfo.processInfo.environment["PUBLIT_TAB"] {
                        app.tab = tab == "plan" ? .plan : tab == "saved" ? .favorites : .nearby
                    }
                    location.start()
                }
        }
    }
}

struct RootView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app
        TabView(selection: $app.tab) {
            NavigationStack { NearbyView() }
                .tabItem { Label("Nearby", systemImage: "location.circle") }
                .tag(AppTab.nearby)
            NavigationStack { PlanView() }
                .tabItem { Label("Plan", systemImage: "arrow.triangle.turn.up.right.diamond") }
                .tag(AppTab.plan)
            NavigationStack { FavoritesView() }
                .tabItem { Label("Saved", systemImage: "star") }
                .tag(AppTab.favorites)
        }
    }
}

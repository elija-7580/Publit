import SwiftUI
import UserNotifications

@main
struct PublitApp: App {
    @State private var app = AppState()
    @State private var location = LocationManager()
    @State private var favorites = FavoritesStore()
    @State private var trips = TripStore()
    @State private var tickets = TicketStore()
    @State private var passes = PassStore()
    @State private var history = SearchHistoryStore.shared

    init() {
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
        HangLog.shared.start()
        CrashReports.shared.start()
        // Offline copies older than a week are no use for departures or routes.
        DispatchQueue.global(qos: .utility).async { TransitousClient.shared.cache.prune(olderThan: 7 * 24 * 3600) }
    }

    @ViewBuilder
    private var appContent: some View {
        #if DEBUG
        if ProcessInfo.processInfo.environment["PUBLIT_UI_SAMPLE"] != nil { PresentationSampleView() }
        else { RootView() }
        #else
        RootView()
        #endif
    }

    /// Screenshot runs force light or dark (`PUBLIT_UI_DARK`); otherwise the system decides.
    private static var forcedScheme: ColorScheme? {
        switch ProcessInfo.processInfo.environment["PUBLIT_UI_DARK"] {
        case "1": .dark
        case "0": .light
        default: nil
        }
    }

    var body: some Scene {
        WindowGroup {
            appContent
                .environment(app)
                .environment(location)
                .environment(favorites)
                .environment(trips)
                .environment(tickets)
                .environment(passes)
                .environment(history)
                .tint(Color.ink)
                .toggleStyle(InkSwitchStyle())
                .preferredColorScheme(Self.forcedScheme)
                .onOpenURL { app.open($0) }
                .onAppear {
                    app.applyDemo(ProcessInfo.processInfo.environment["PUBLIT_DEMO"])
                    if ProcessInfo.processInfo.environment["PUBLIT_TAB"] == nil,
                       UserDefaults.standard.string(forKey: StartTab.defaultsKey) == StartTab.plan.rawValue {
                        app.tab = .plan
                    }
                    if let tab = ProcessInfo.processInfo.environment["PUBLIT_TAB"] {
                        app.tab = tab == "plan" ? .plan : tab == "saved" ? .favorites : tab == "lines" ? .favorites
                            : tab == "tickets" ? .tickets : .nearby
                    }
                    #if DEBUG
                    if let sample = ProcessInfo.processInfo.environment["PUBLIT_IMPORT_SAMPLE"],
                       let url = try? SharedTicketSamples.file(sample) { app.open(url) }
                    #endif
                    // First launch: the onboarding asks for the location with a reason first.
                    if !OnboardingView.needed { location.start() }
                    // Tickets of the first ticket version become passes (once per ticket).
                    passes.importLegacy(tickets.tickets, imageDirectory: tickets.imageDirectory)
                    NotificationRouter.shared.open = { [app] url in app.open(url) }
                    IntentBridge.connect { [app] url in app.open(url) }
                    PublitShortcuts.updateAppShortcutParameters()
                }
                .onChange(of: favorites.stops.count) { PublitShortcuts.updateAppShortcutParameters() }
        }
        // Saved lines checked for disruptions while the app is closed (iOS decides when).
        .backgroundTask(.appRefresh(LineAlertMonitor.taskId)) {
            LineAlertMonitor.scheduleBackgroundCheck()
            await LineAlertMonitor.check(minInterval: 10 * 60)
        }
    }
}

struct RootView: View {
    @Environment(AppState.self) private var app
    @Environment(TripStore.self) private var trips
    @Environment(PassStore.self) private var passes
    @Environment(FavoritesStore.self) private var favorites
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(LocationManager.self) private var location
    /// The launch animation, while the first departures load underneath.
    @State private var splash = true
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// Size of the window: the iPad layout needs room for the panel and the map.
    @State private var rootSize: CGSize = .zero
    @State private var onboarding = OnboardingView.needed
    @AppStorage(OnboardingView.doneKey) private var onboardingDone = false

    var body: some View {
        tabs
            .overlay {
                if splash {
                    LaunchSplash()
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .task { await endSplash() }
            .fullScreenCover(isPresented: $onboarding) { OnboardingView() }
            .onChange(of: onboardingDone) { _, done in if done { onboarding = false } }
    }

    /// At least 0.7 s (the animation), at most 2 s, ended earlier by the first board.
    private func endSplash() async {
        let start = Date()
        try? await Task.sleep(for: .milliseconds(700))
        while !app.firstBoardReady, app.tab == .nearby, Date().timeIntervalSince(start) < 2 {
            try? await Task.sleep(for: .milliseconds(100))
        }
        withAnimation(.easeOut(duration: 0.3)) { splash = false }
    }

    @ViewBuilder
    private var tabs: some View {
        @Bindable var app = app
        let wide = WideLayout.isWide(size: rootSize, sizeClass: sizeClass)
        Group {
            if #available(iOS 18, *) {
                AdaptiveTabs(tab: $app.tab, wide: wide)
            } else {
                TabView(selection: $app.tab) {
                    RootTab.content(.nearby, wide: wide)
                        .tabItem { Label("Nearby", systemImage: "location.circle") }
                        .tag(AppTab.nearby)
                    RootTab.content(.plan, wide: wide)
                        .tabItem { Label("Plan", systemImage: "calendar") }
                        .tag(AppTab.plan)
                    RootTab.content(.tickets, wide: wide)
                        .tabItem { Label("Tickets", systemImage: "ticket") }
                        .tag(AppTab.tickets)
                    RootTab.content(.favorites, wide: wide)
                        .tabItem { Label("Saved", systemImage: "star") }
                        .tag(AppTab.favorites)
                }
            }
        }
        // The unfolded iPhone Duo is compact like an iPhone; the wide layout (split views, sidebar
        // tabs) needs regular, so it gets regular there.
        .environment(\.horizontalSizeClass, wide ? .regular : sizeClass)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { rootSize = $0 }
        .sheet(item: $app.sharedTicketFile) { file in
            PassImportView(sharedURL: file.url)
        }
        // Full screen, not a sheet: a sheet could still be swiped away while pulling the trip panel
        // down ("the live view is suddenly gone"). It closes with Minimize or Done only.
        .fullScreenCover(item: tripLink) { id in
            NavigationStack {
                SavedTripView(tripId: id.value)
                    .toolbar {
                        // A started trip keeps running when the screen closes: it moves down into the live bar.
                        if trips.activeTrip?.id == id.value {
                            ToolbarItem(placement: .topBarLeading) {
                                Button { app.deepLink = nil } label: {
                                    Label(L10n.t("Minimize"), systemImage: "chevron.down")
                                }
                                .accessibilityIdentifier("minimizeTrip")
                            }
                        } else {
                            ToolbarItem(placement: .confirmationAction) { Button("Done") { app.deepLink = nil } }
                        }
                    }
            }
            // Swiping the trip panel all the way down closed the whole screen ("the live trip
            // disappears"); a started trip closes with Minimize only.
            .interactiveDismissDisabled(trips.activeTrip?.id == id.value)
        }
        .sheet(item: ticketLink) { link in
            NavigationStack {
                Group {
                    switch link {
                    case .ticket(let id?):
                        if let pass = passes.pass(linkedTo: id) { PassDetailView(passId: pass.id) } else { TripPassesView() }
                    case .tripTickets(let tripId):
                        TripPassesView(tripId: tripId, at: trips.trip(tripId)?.startTime ?? .now)
                    default:
                        TripPassesView()
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Done") { app.deepLink = nil } }
                }
            }
            .dynamicTypeSize(dynamicTypeSize)
        }
        .sheet(item: routeLink) { ref in
            NavigationStack {
                SharedRouteView(route: ref.route)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { app.deepLink = nil } }
                    }
            }
        }
        .sheet(item: stopLink) { stop in
            NavigationStack {
                StopDeparturesView(stopId: stop.id, name: stop.name, coordinate: stop.coordinate)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { app.deepLink = nil } }
                    }
            }
        }
        .onChange(of: app.deepLink) { _, link in
            guard case .go(let role) = link else { return }
            app.deepLink = nil
            if let place = favorites.place(for: role) {
                app.goNow(to: place, source: .favorite)
            } else {
                app.tab = .favorites // Home/Work not set yet: that is where it is set.
            }
        }
        .onChange(of: app.tab) { _, tab in HangLog.shared.note("tab \(tab)") }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            TransitousClient.shared.releaseMemory(background: false)
        }
        .task(id: scenePhase) {
            switch scenePhase {
            case .active: HangLog.shared.note("app active"); HangLog.shared.scene(active: true)
            case .inactive: HangLog.shared.note("app inactive")
            case .background:
                HangLog.shared.note("app background"); HangLog.shared.scene(active: false)
                trips.flushPendingSave()
                TransitousClient.shared.releaseMemory(background: true)
            @unknown default: break
            }
            if scenePhase == .background {
                LineAlertMonitor.scheduleBackgroundCheck()
                location.pause()
                // Nothing updates a Live Activity without the app: it goes by itself after the arrival.
                await LiveTripActivity.handOver { trips.trip($0) }
            }
            // Keep running Live Activities current while the app is open.
            guard scenePhase == .active else { return }
            location.start()
            for trip in await LiveTripActivity.resume({ trips.trip($0) }) {
                LiveTripActivity.start(trip, hasTicket: !passes.passes(forTrip: trip.id, at: trip.startTime).isEmpty)
            }
            await LineAlertMonitor.check()
            while !Task.isCancelled {
                let wait = await refreshLiveTrips()
                try? await Task.sleep(for: .seconds(wait))
            }
        }
    }

    private struct ID: Identifiable { let value: String; var id: String { value } }

    private struct StopRef: Identifiable {
        let id: String, name: String, coordinate: LatLon
    }

    private var stopLink: Binding<StopRef?> {
        Binding(get: {
            if case .stop(let id, let name, let lat, let lon) = app.deepLink {
                return StopRef(id: id, name: name, coordinate: LatLon(lat: lat, lon: lon))
            }
            return nil
        }, set: { if $0 == nil { app.deepLink = nil } })
    }

    private struct RouteRef: Identifiable { let route: SharedRoute; var id: String { route.query } }

    private var routeLink: Binding<RouteRef?> {
        Binding(get: {
            if case .route(let r) = app.deepLink { return RouteRef(route: r) }
            return nil
        }, set: { if $0 == nil { app.deepLink = nil } })
    }

    private var tripLink: Binding<ID?> {
        Binding(get: {
            if case .trip(let id) = app.deepLink { return ID(value: id) }
            return nil
        }, set: { if $0 == nil { app.deepLink = nil } })
    }

    private var ticketLink: Binding<DeepLink?> {
        Binding(get: {
            switch app.deepLink {
            case .ticket, .tripTickets: return Features.passes ? app.deepLink : nil
            default: return nil
            }
        }, set: { if $0 == nil { app.deepLink = nil } })
    }

    /// Refreshes the trips with a running Live Activity; returns the seconds until the next refresh.
    private func refreshLiveTrips() async -> TimeInterval {
        let now = Date()
        for trip in trips.upcoming(now: now.addingTimeInterval(-15 * 60)) where LiveTripActivity.isRunning(trip.id) || trips.activeTripId == trip.id {
            if let fresh = try? await TripRefreshCoordinator.shared.refresh(trip.itinerary.id) {
                trips.update(trip.id, with: fresh)
                if let updated = trips.trip(trip.id) {
                    await LeaveReminder.follow(trip, to: updated)
                    await GetOffReminder.follow(from: trip.itinerary, to: updated.itinerary)
                    await TripChangeAlert.follow(trip.id, from: trip.itinerary, to: updated.itinerary)
                    await ArrivalUpdates.follow(updated)
                }
            }
            if let t = trips.trip(trip.id) { await LiveTripActivity.update(t) }
        }
        // Trips with a leave reminder that start within 8 hours get their Live Activity now.
        for trip in trips.upcoming(now: now) where !LiveTripActivity.isRunning(trip.id) {
            if trips.wantsLiveActivity(trip.id), trip.startTime.timeIntervalSince(now) < LiveTripActivity.maxLead {
                LiveTripActivity.start(trip, hasTicket: !passes.passes(forTrip: trip.id, at: trip.startTime).isEmpty)
            }
        }
        let live = trips.upcoming(now: Date().addingTimeInterval(-15 * 60)).filter { LiveTripActivity.isRunning($0.id) || trips.activeTripId == $0.id }
        return LiveRefresh.interval(live.map(\.itinerary))
    }
}

/// The four tabs: on iPhone in the tab bar, on iPad in the tab bar at the top that turns into a sidebar.
@available(iOS 18, *)
private struct AdaptiveTabs: View {
    @Binding var tab: AppTab
    let wide: Bool

    var body: some View {
        TabView(selection: $tab) {
            Tab("Nearby", systemImage: "location.circle", value: AppTab.nearby) { RootTab.content(.nearby, wide: wide) }
            Tab("Plan", systemImage: "calendar", value: AppTab.plan) { RootTab.content(.plan, wide: wide) }
            Tab("Tickets", systemImage: "ticket", value: AppTab.tickets) { RootTab.content(.tickets, wide: wide) }
            Tab("Saved", systemImage: "star", value: AppTab.favorites) { RootTab.content(.favorites, wide: wide) }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}

/// What a tab shows: the iPhone screens in a navigation stack, or on a wide screen (iPad, iPhone Duo
/// unfolded) the map with a floating panel (Nearby, Plan) or a list with details beside it (Tickets, Saved).
enum RootTab {
    @MainActor @ViewBuilder
    static func content(_ tab: AppTab, wide: Bool) -> some View {
        switch tab {
        case .nearby:
            if wide { WideMapScreen { NearbyView() } } else { NavigationStack { NearbyView() }.liveTripBar() }
        case .plan:
            if wide { WideMapScreen { PlanView() } } else { NavigationStack { PlanView() }.liveTripBar() }
        case .tickets:
            if wide {
                WideSplitScreen(list: { PassWalletView() }, placeholder: "Choose a ticket", symbol: "ticket")
            } else {
                NavigationStack { PassWalletView() }.liveTripBar()
            }
        case .favorites:
            if wide {
                WideSplitScreen(list: { FavoritesView() }, placeholder: "Choose a trip or place", symbol: "star")
            } else {
                NavigationStack { FavoritesView() }.liveTripBar()
            }
        }
    }
}

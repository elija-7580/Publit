import SwiftUI
import UserNotifications

@main
struct PublitApp: App {
    @State private var app = AppState()
    @State private var location = LocationManager()
    @State private var favorites = FavoritesStore()
    @State private var trips = TripStore()
    @State private var tickets = TicketStore()

    init() {
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(location)
                .environment(favorites)
                .environment(trips)
                .environment(tickets)
                .tint(Color.appAccent)
                .onOpenURL { app.open($0) }
                .onAppear {
                    app.applyDemo(ProcessInfo.processInfo.environment["PUBLIT_DEMO"])
                    if let tab = ProcessInfo.processInfo.environment["PUBLIT_TAB"] {
                        app.tab = tab == "plan" ? .plan : tab == "saved" ? .favorites : .nearby
                    }
                    location.start()
                    NotificationRouter.shared.open = { [app] url in app.open(url) }
                }
        }
    }
}

struct RootView: View {
    @Environment(AppState.self) private var app
    @Environment(TripStore.self) private var trips
    @Environment(TicketStore.self) private var tickets
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var app = app
        TabView(selection: $app.tab) {
            NavigationStack { NearbyView() }
                .tabItem { Label("Nearby", systemImage: "location.circle") }
                .tag(AppTab.nearby)
            NavigationStack { PlanView() }
                .tabItem { Label("Plan", systemImage: "calendar") }
                .tag(AppTab.plan)
            NavigationStack { FavoritesView() }
                .tabItem { Label("Saved", systemImage: "star") }
                .tag(AppTab.favorites)
        }
        .sheet(item: tripLink) { id in
            NavigationStack {
                SavedTripView(tripId: id.value)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { app.deepLink = nil } }
                    }
            }
        }
        .fullScreenCover(item: ticketLink) { link in
            TicketDisplayView(tickets: ticketsFor(link))
        }
        .task(id: scenePhase) {
            // Keep running Live Activities current while the app is open.
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await refreshLiveTrips()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    private struct ID: Identifiable { let value: String; var id: String { value } }

    private var tripLink: Binding<ID?> {
        Binding(get: {
            if case .trip(let id) = app.deepLink { return ID(value: id) }
            return nil
        }, set: { if $0 == nil { app.deepLink = nil } })
    }

    private var ticketLink: Binding<DeepLink?> {
        Binding(get: {
            switch app.deepLink {
            case .ticket, .tripTickets: return app.deepLink
            default: return nil
            }
        }, set: { if $0 == nil { app.deepLink = nil } })
    }

    private func ticketsFor(_ link: DeepLink) -> [Ticket] {
        switch link {
        case .ticket(let id?): return tickets.ticket(id).map { [$0] } ?? tickets.tickets(forTrip: nil)
        case .ticket(nil): return tickets.tickets(forTrip: nil)
        case .tripTickets(let tripId): return tickets.tickets(forTrip: tripId)
        case .trip: return []
        }
    }

    private func refreshLiveTrips() async {
        let now = Date()
        for trip in trips.upcoming(now: now.addingTimeInterval(-15 * 60)) where LiveTripActivity.isRunning(trip.id) {
            if let fresh = try? await TransitousClient.shared.refresh(itineraryId: trip.itinerary.id) {
                trips.update(trip.id, with: fresh)
            }
            if let t = trips.trip(trip.id) { await LiveTripActivity.update(t) }
        }
        // Trips with a leave reminder that start within 8 hours get their Live Activity now.
        for trip in trips.upcoming(now: now) where !LiveTripActivity.isRunning(trip.id) {
            if trips.wantsLiveActivity(trip.id), trip.startTime.timeIntervalSince(now) < LiveTripActivity.maxLead {
                LiveTripActivity.start(trip, hasTicket: !tickets.tickets(forTrip: trip.id).isEmpty)
            }
        }
    }
}

#if DEBUG
import SwiftUI

/// A longer trip for design screenshots (route preview and live trip): walk, U6, change, S8 with a
/// delay and a platform change, walk. Times are minutes from launch; marked as a demo.
enum DesignSamples {
    static let base = Date()

    static var itinerary: Itinerary { DesignSampleTrip.itinerary(DesignSampleTrip.munich, base: base) }

    /// A trip through Carinthia, where data is missing (the warning on the route).
    static var carinthia: Itinerary { DesignSampleTrip.itinerary(DesignSampleTrip.carinthia, base: base.addingTimeInterval(40 * 60)) }
}

/// The real trip screens on the sample trip: `PUBLIT_UI_SAMPLE=route` (preview) or `live` (started),
/// `route-gap` for the trip through Carinthia, `live-missed` for the live trip four minutes later
/// (the U6 has left; standing at Münchner Freiheit shows "Missed it?" with a new route from here).
struct DesignSampleView: View {
    let kind: String
    @Environment(TripStore.self) private var trips
    @Environment(PassStore.self) private var passes
    @State private var tripId: String?

    var body: some View {
        NavigationStack {
            if kind == "route-gap" {
                ItineraryDetailView(itinerary: DesignSamples.carinthia, fromName: "Zuhause", toName: "Villach")
            } else if kind.hasPrefix("route") {
                ItineraryDetailView(itinerary: DesignSamples.itinerary, fromName: "Zuhause", toName: "Flughafen München")
            } else if let tripId {
                SavedTripView(tripId: tripId)
            } else {
                ProgressView()
            }
        }
        .task {
            guard kind.hasPrefix("live"), tripId == nil else { return }
            let it = kind == "live-missed"
                ? DesignSampleTrip.itinerary(DesignSampleTrip.munich, base: Date().addingTimeInterval(-240))
                : DesignSamples.itinerary
            let saved = trips.save(it, from: "Zuhause", to: "Flughafen München")
            trips.update(saved.id, with: it)
            _ = trips.start(saved.id)
            if kind == "live-undated-ticket" {
                for pass in passes.passes { passes.remove(pass.id) }
                passes.insert(TicketPass(id: "demo-undated-climate", title: "DEMO KlimaTicket — no dates", category: .subscription))
            }
            tripId = saved.id
        }
    }
}
#endif

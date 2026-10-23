#if DEBUG
import SwiftUI

/// A longer trip for design screenshots (route preview and live trip): walk, U6, change, S8 with a
/// delay and a platform change, walk. Times are minutes from launch; marked as a demo.
enum DesignSamples {
    static let base = Date()

    static var itinerary: Itinerary { DesignSampleTrip.itinerary(DesignSampleTrip.munich, base: base) }
}

/// The real trip screens on the sample trip: `PUBLIT_UI_SAMPLE=route` (preview) or `live` (started).
struct DesignSampleView: View {
    let kind: String
    @Environment(TripStore.self) private var trips
    @Environment(PassStore.self) private var passes
    @State private var tripId: String?

    var body: some View {
        NavigationStack {
            if kind.hasPrefix("route") {
                ItineraryDetailView(itinerary: DesignSamples.itinerary, fromName: "Zuhause", toName: "Flughafen München")
            } else if let tripId {
                SavedTripView(tripId: tripId)
            } else {
                ProgressView()
            }
        }
        .task {
            guard kind.hasPrefix("live"), tripId == nil else { return }
            let saved = trips.save(DesignSamples.itinerary, from: "Zuhause", to: "Flughafen München")
            trips.update(saved.id, with: DesignSamples.itinerary)
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

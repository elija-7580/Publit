import SwiftUI

/// A saved trip with its live status. Opened from Plan, from the calendar entry and from the Live Activity.
struct SavedTripView: View {
    let tripId: String
    @Environment(TripStore.self) private var trips
    @State private var errorMessage: String?

    var body: some View {
        if let trip = trips.trip(tripId) {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                ItineraryDetailView(itinerary: trip.itinerary, fromName: trip.fromName, toName: trip.toName,
                                    status: TripStatus.at(context.date, trip.itinerary), refreshedAt: trip.refreshedAt)
            }
            .navigationTitle(trip.toName)
            .overlay(alignment: .bottom) {
                if let errorMessage {
                    Text(errorMessage).font(.caption).padding(8)
                        .background(.regularMaterial, in: Capsule()).padding(.bottom, 8)
                }
            }
            .task(id: tripId) {
                // Live status: refresh now and every minute until the trip is over.
                while !Task.isCancelled {
                    guard let t = trips.trip(tripId), t.endTime.addingTimeInterval(15 * 60) > .now else { break }
                    await refresh(t)
                    try? await Task.sleep(for: .seconds(60))
                }
            }
        } else {
            ContentUnavailableView("Trip not found", systemImage: "bookmark.slash",
                                   description: Text("It was removed from this device."))
        }
    }

    private func refresh(_ t: SavedTrip) async {
        do {
            let fresh = try await TransitousClient.shared.refresh(itineraryId: t.itinerary.id)
            trips.update(t.id, with: fresh)
            errorMessage = nil
            if let updated = trips.trip(t.id) { await LiveTripActivity.update(updated) }
        } catch {
            if !(error is CancellationError) && (error as? URLError)?.code != .cancelled {
                errorMessage = "Live status unavailable. Showing saved times."
            }
        }
    }
}

/// One saved trip in a list.
struct SavedTripRow: View {
    let trip: SavedTrip

    var body: some View {
        let tz = trip.itinerary.legs.first?.from.tz
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(trip.toName).font(.headline).lineLimit(1)
                Spacer()
                Text(trip.startTime.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Text("\(Fmt.time(trip.startTime, tz: tz)) – \(Fmt.time(trip.endTime, tz: trip.itinerary.legs.last?.to.tz))")
                .font(.subheadline.monospacedDigit()).lineLimit(1)
            HStack(spacing: 6) {
                ForEach(Array(trip.itinerary.transitLegs.prefix(4).enumerated()), id: \.offset) { _, leg in
                    LineBadge(leg)
                }
            }
            Text("from \(trip.fromName)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

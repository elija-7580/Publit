import SwiftUI

/// What is saved: trips (also those saved on the iPhone), Home and Work, stops and places.
struct WatchSavedView: View {
    @Environment(WatchLibrary.self) private var library

    var body: some View {
        TimelineView(.everyMinute) { context in
            let snap = library.snapshot
            let now = context.date
            let upcoming = snap.upcoming(now: now)
            let past = Array(snap.past(now: now).prefix(3))
            List {
                if snap.trips.isEmpty && snap.places.isEmpty {
                    WatchMessage(symbol: "star", text: "Nothing saved yet. Save trips and stops on your iPhone or on the watch.")
                        .listRowBackground(Color.clear)
                }
                if !upcoming.isEmpty {
                    Section("Upcoming trips") {
                        ForEach(upcoming) { trip in
                            NavigationLink(value: WatchRoute.trip(trip.id)) {
                                WatchSavedTripRow(trip: trip, started: snap.activeTripId == trip.id)
                            }
                        }
                    }
                }
                if !snap.pinned.isEmpty {
                    Section("Home and Work") {
                        ForEach(snap.pinned) { place in
                            NavigationLink(value: WatchRoute.planTo(place)) { WatchPlaceRow(place: place) }
                        }
                    }
                }
                if !snap.stops.isEmpty {
                    Section("Stops") {
                        ForEach(snap.stops) { place in
                            NavigationLink(value: WatchRoute.stop(place)) { WatchPlaceRow(place: place) }
                        }
                    }
                }
                if !snap.otherPlaces.isEmpty {
                    Section("Places") {
                        ForEach(snap.otherPlaces) { place in
                            NavigationLink(value: WatchRoute.planTo(place)) { WatchPlaceRow(place: place) }
                        }
                    }
                }
                if !past.isEmpty {
                    Section("Past trips") {
                        ForEach(past) { trip in
                            NavigationLink(value: WatchRoute.trip(trip.id)) {
                                WatchSavedTripRow(trip: trip, started: false)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(Text("Saved"))
    }
}

/// A saved trip: where to, when, and the lines.
struct WatchSavedTripRow: View {
    let trip: SavedTrip
    let started: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                if started {
                    Image(systemName: "dot.radiowaves.left.and.right").font(.caption2).foregroundStyle(Color.live)
                        .accessibilityLabel(Text("Live"))
                }
                Text(verbatim: trip.toName).font(.headline).lineLimit(2)
            }
            Text(verbatim: "\(trip.startTime.formatted(date: .abbreviated, time: .omitted)) · \(Fmt.time(trip.startTime, tz: trip.itinerary.legs.first?.from.tz)) → \(Fmt.time(trip.endTime, tz: trip.itinerary.legs.last?.to.tz))")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            if !trip.itinerary.transitLegs.isEmpty {
                WatchFlowLayout(spacing: 3) {
                    ForEach(Array(trip.itinerary.transitLegs.enumerated()), id: \.offset) { _, leg in
                        LineBadge(leg, compact: true)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The next departures at a stop, with the star to keep it.
struct WatchStopView: View {
    let place: SavedPlace
    @Environment(WatchLibrary.self) private var library
    @State private var times: [StopTime] = []
    @State private var loaded = false
    @State private var failed = false
    @State private var updated: Date?

    var body: some View {
        TimelineView(.everyMinute) { context in
            List {
                if let notice = CoverageGuide.notice(at: place.coordinate) {
                    WatchCoverageNote(notices: [notice]).listRowBackground(Color.clear)
                }
                if !loaded {
                    HStack { Spacer(); ProgressView(); Spacer() }.listRowBackground(Color.clear)
                } else if times.isEmpty {
                    if failed {
                        VStack(spacing: 8) {
                            WatchMessage(symbol: "wifi.exclamationmark", text: "Departures unavailable")
                            Button("Try again") { Task { await load() } }
                        }
                        .listRowBackground(Color.clear)
                    } else {
                        WatchMessage(symbol: "tram", text: "No departures nearby").listRowBackground(Color.clear)
                    }
                }
                ForEach(times.prefix(12)) { stopTime in
                    WatchDepartureRow(stopTime: stopTime, now: context.date)
                }
                NavigationLink(value: WatchRoute.planTo(place)) {
                    Label("Route here", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                }
                if let updated {
                    Text(L10n.f("Updated %@", Fmt.time(updated))).font(.footnote).foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
            }
        }
        .navigationTitle(Text(verbatim: place.name))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                let saved = library.isSaved(place)
                Button {
                    if saved { library.remove(place: place) } else { library.save(place: place) }
                } label: {
                    Image(systemName: saved ? "star.fill" : "star")
                }
                .accessibilityLabel(saved ? Text("Saved") : Text("Save"))
            }
        }
        .task {
            while !Task.isCancelled {
                await load()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    private func load() async {
        guard let id = place.stopId else {
            loaded = true
            return
        }
        do {
            let res = try await TransitousClient.shared.departures(stopId: id, count: 30)
            times = StopTime.upcoming(res.stopTimes)
            failed = false
            updated = Date()
        } catch {
            failed = true
        }
        loaded = true
    }
}

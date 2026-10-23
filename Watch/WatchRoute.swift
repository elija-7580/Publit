import SwiftUI

/// Where a tap on the watch leads. One value per screen: the stack of them is the way back.
enum WatchRoute: Hashable {
    case tickets
    case ticket(String)
    /// A saved trip.
    case trip(String)
    /// A route from a search, not saved (yet).
    case route(OpenedRoute, from: String, to: String)
    /// The map of a whole trip (overview) or of one leg.
    case map(OpenedRoute, WatchTripPage)
    case nearby
    case plan
    /// The planner with the destination already set.
    case planTo(SavedPlace)
    case saved
    case stop(SavedPlace)
}

/// The screen for a route.
struct WatchRouteView: View {
    let route: WatchRoute
    let nearby: WatchNearbyModel
    @Environment(WatchLibrary.self) private var library

    var body: some View {
        switch route {
        case .tickets:
            WatchTicketsView()
        case .ticket(let id):
            WatchTicketView(ticketId: id)
        case .trip(let id):
            if let trip = library.snapshot.trip(id) {
                WatchTripView(itinerary: trip.itinerary, from: trip.fromName, to: trip.toName)
            } else {
                WatchMessage(symbol: "tram", text: "Trip not found")
            }
        case .route(let opened, let from, let to):
            WatchTripView(itinerary: opened.itinerary, from: from, to: to)
        case .map(let opened, let page):
            WatchTripMapView(itinerary: library.snapshot.trip(for: opened.itinerary)?.itinerary ?? opened.itinerary, page: page)
        case .nearby:
            WatchNearbyView(model: nearby)
        case .plan:
            WatchPlanView(destination: nil)
        case .planTo(let place):
            WatchPlanView(destination: place)
        case .saved:
            WatchSavedView()
        case .stop(let place):
            WatchStopView(place: place)
        }
    }
}

/// An icon and a short text in the middle of an empty screen.
struct WatchMessage: View {
    let symbol: String
    let text: LocalizedStringKey

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.title3).foregroundStyle(.secondary)
            Text(text).font(.footnote).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .accessibilityElement(children: .combine)
    }
}

/// "Not reliable here": the area and which data is missing there. The same words as on the iPhone.
struct WatchCoverageNote: View {
    let notices: [CoverageNotice]

    var body: some View {
        if !notices.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Label {
                    Text("Not reliable here").font(.footnote.weight(.bold))
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.delay)
                }
                ForEach(notices) { notice in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: notice.heading).font(.caption2.weight(.semibold))
                        Text(verbatim: notice.area.summary).font(.caption2).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(Color.delay.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityIdentifier("coverageNote")
        }
    }
}

/// A small orange triangle beside a place in an area with missing data.
struct WatchCoverageMark: View {
    let point: LatLon?

    var body: some View {
        if let notice = CoverageGuide.notice(at: point) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(Color.delay)
                .accessibilityLabel(Text("Not reliable here"))
                .accessibilityValue(Text(verbatim: notice.area.summary))
        }
    }
}

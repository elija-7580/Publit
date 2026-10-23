import SwiftUI

/// Start or end of a search on the watch: where you are, or a place you picked.
enum WatchEndpoint: Hashable {
    case current
    case place(SavedPlace)

    var title: String {
        switch self {
        case .current: return L10n.t("Current location")
        case .place(let p): return p.name
        }
    }

    var symbol: String {
        switch self {
        case .current: return "location.fill"
        case .place(let p): return p.role?.symbol ?? (p.isStop ? "tram.fill" : "mappin")
        }
    }

    func coordinate(here: LatLon?) -> LatLon? {
        switch self {
        case .current: return here
        case .place(let p): return p.coordinate
        }
    }
}

/// Where to? From (your location unless you choose another) and To, then the connections leaving now.
/// Enough to find a way and take it with the watch alone.
struct WatchPlanView: View {
    let destination: SavedPlace?

    private enum Role: String, Identifiable { case from, to; var id: String { rawValue } }
    private enum Phase: Equatable { case idle, loading, done, noLocation, locationOff, failed }
    private struct Key: Hashable { let from: WatchEndpoint; let to: WatchEndpoint? }
    private struct Request { let start: LatLon; let end: LatLon; let maxWalk: Int }

    @State private var from: WatchEndpoint = .current
    @State private var to: WatchEndpoint?
    @State private var chooser: Role?
    @State private var phase: Phase = .idle
    @State private var routes: [Itinerary] = []
    @State private var request: Request?
    @State private var cursor: String?
    @State private var loadingMore = false
    @State private var asked = false

    init(destination: SavedPlace?) {
        self.destination = destination
        _to = State(initialValue: destination.map { WatchEndpoint.place($0) })
    }

    var body: some View {
        List {
            Button { chooser = .from } label: { endpointRow("From", from) }
            Button { chooser = .to } label: {
                if let to { endpointRow("To", to) } else { Label("Where to?", systemImage: "magnifyingglass") }
            }
            content
        }
        .navigationTitle(Text("Plan"))
        .toolbar {
            if to != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await search() } } label: { Image(systemName: "arrow.clockwise") }
                        .accessibilityLabel(Text("Refresh"))
                }
            }
        }
        .sheet(item: $chooser) { role in
            NavigationStack {
                WatchPlaceChooser(isStart: role == .from) { endpoint in
                    if role == .from { from = endpoint } else { to = endpoint }
                    chooser = nil
                }
            }
        }
        .task(id: Key(from: from, to: to)) { await search() }
        .task {
            // Opened from "Where to?": pick the destination first.
            if to == nil, !asked {
                asked = true
                chooser = .to
            }
        }
    }

    private func endpointRow(_ label: LocalizedStringKey, _ endpoint: WatchEndpoint) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Label(endpoint.title, systemImage: endpoint.symbol).font(.headline).lineLimit(2)
        }
    }

    @ViewBuilder
    private var content: some View {
        let hereCoordinate = WatchLocator.shared.last
        if to != nil {
            WatchCoverageNote(notices: CoverageGuide.notices(start: from.coordinate(here: hereCoordinate), destination: to?.coordinate(here: hereCoordinate)))
                .listRowBackground(Color.clear)
        }
        switch phase {
        case .idle:
            EmptyView()
        case .loading:
            HStack { Spacer(); ProgressView(); Spacer() }.listRowBackground(Color.clear)
        case .locationOff:
            WatchMessage(symbol: "location.slash", text: "Location is off").listRowBackground(Color.clear)
        case .noLocation, .failed:
            VStack(spacing: 8) {
                WatchMessage(symbol: "wifi.exclamationmark", text: phase == .failed ? "Departures unavailable" : "Waiting for your location…")
                Button("Try again") { Task { await search() } }
            }
            .listRowBackground(Color.clear)
        case .done:
            if routes.isEmpty {
                WatchMessage(symbol: "tram", text: "No connections found.").listRowBackground(Color.clear)
            }
            ForEach(routes, id: \.routeKey) { route in
                NavigationLink(value: WatchRoute.route(OpenedRoute(itinerary: route), from: from.title, to: to?.title ?? "")) {
                    WatchRouteRow(itinerary: route)
                }
            }
            if !routes.isEmpty, cursor != nil {
                Button {
                    Task { await more() }
                } label: {
                    if loadingMore { ProgressView() } else { Label("Later connections", systemImage: "chevron.down") }
                }
            }
        }
    }

    // MARK: Search

    private func search() async {
        guard let to else {
            phase = .idle
            routes = []
            return
        }
        phase = .loading
        routes = []
        cursor = nil
        var here: LatLon?
        if from == .current { here = await WatchLocator.shared.locate() }
        if Task.isCancelled { return }
        guard let start = from.coordinate(here: here), let end = to.coordinate(here: here) else {
            phase = WatchLocator.shared.isDenied ? .locationOff : .noLocation
            return
        }
        do {
            var maxWalk = TransitousClient.walkLimits.prePost
            var res = try await TransitousClient.shared.plan(from: start, to: end, time: nil, arriveBy: false, maxWalk: maxWalk)
            // Nothing within a normal walk of a stop: look again with a longer walk, like the iPhone.
            while res.itineraries.isEmpty, let wider = Reach.nextWalkStep(after: maxWalk) {
                try Task.checkCancellation()
                maxWalk = wider
                res = try await TransitousClient.shared.plan(from: start, to: end, time: nil, arriveBy: false, maxWalk: maxWalk)
            }
            try Task.checkCancellation()
            routes = WatchRoutes.list(transit: res.itineraries, direct: res.direct)
            request = Request(start: start, end: end, maxWalk: maxWalk)
            cursor = res.nextPageCursor
            phase = .done
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
            phase = .failed
        }
    }

    private func more() async {
        guard let request, let cursor, !loadingMore else { return }
        loadingMore = true
        defer { loadingMore = false }
        guard let res = try? await TransitousClient.shared.plan(from: request.start, to: request.end, time: nil, arriveBy: false,
                                                                 pageCursor: cursor, maxWalk: request.maxWalk) else { return }
        let more = WatchRoutes.list(transit: res.itineraries, direct: [], limit: 6)
        routes = (routes + more).uniqueRoutes
        self.cursor = res.nextPageCursor
    }
}

/// A connection in the list: times, duration, changes and the lines.
struct WatchRouteRow: View {
    let itinerary: Itinerary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                let delay = itinerary.transitLegs.first?.delayMinutes ?? 0
                Text(verbatim: Fmt.time(itinerary.startTime, tz: itinerary.legs.first?.from.tz))
                    .foregroundStyle(itinerary.isCancelled ? Color.danger : delay > 0 ? Color.delay : Color.primary)
                    .strikethrough(itinerary.isCancelled)
                Text(verbatim: "→").foregroundStyle(.secondary)
                Text(verbatim: Fmt.time(itinerary.endTime, tz: itinerary.legs.last?.to.tz))
            }
            .font(.headline.monospacedDigit())
            if itinerary.transitLegs.isEmpty {
                Label(Fmt.duration(seconds: itinerary.duration), systemImage: "figure.walk").font(.caption2)
            } else {
                WatchFlowLayout(spacing: 3) {
                    ForEach(Array(itinerary.transitLegs.enumerated()), id: \.offset) { _, leg in
                        LineBadge(leg, compact: true)
                    }
                }
                Text(verbatim: "\(Fmt.duration(seconds: itinerary.duration)) · \(Fmt.changes(itinerary.transfers))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Choose a start or a destination: your location, saved places and stops, or a search (dictate or scribble).
struct WatchPlaceChooser: View {
    let isStart: Bool
    let pick: (WatchEndpoint) -> Void

    @Environment(WatchLibrary.self) private var library
    @State private var query = ""
    @State private var results: [GeocodeMatch] = []
    @State private var searching = false
    @State private var searched = false

    var body: some View {
        let snap = library.snapshot
        List {
            TextFieldLink(prompt: Text("Search")) {
                Label("Search", systemImage: "magnifyingglass")
            } onSubmit: { text in
                query = text
                Task { await search() }
            }
            if isStart {
                Button { pick(.current) } label: { Label("Current location", systemImage: "location.fill") }
            }
            if searching {
                HStack { Spacer(); ProgressView(); Spacer() }.listRowBackground(Color.clear)
            } else if searched && results.isEmpty {
                Text(L10n.f("No place found for “%@”.", query)).font(.footnote).listRowBackground(Color.clear)
            }
            ForEach(results) { match in
                Button { pick(.place(SavedPlace(match: match))) } label: { matchRow(match) }
            }
            if results.isEmpty, !snap.pinned.isEmpty || !snap.stops.isEmpty || !snap.otherPlaces.isEmpty {
                Section("Saved") {
                    ForEach(snap.pinned + snap.stops + snap.otherPlaces) { place in
                        Button { pick(.place(place)) } label: { WatchPlaceRow(place: place) }
                    }
                }
            }
        }
        .navigationTitle(isStart ? Text("From") : Text("To"))
    }

    private func matchRow(_ match: GeocodeMatch) -> some View {
        HStack(spacing: 6) {
            Image(systemName: match.isStop ? "tram.fill" : "mappin").foregroundStyle(.secondary).frame(width: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: match.name).font(.footnote.weight(.semibold)).lineLimit(2)
                if !match.subtitle.isEmpty {
                    Text(verbatim: match.subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            WatchCoverageMark(point: LatLon(lat: match.lat, lon: match.lon))
        }
        .accessibilityElement(children: .combine)
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        searching = true
        defer { searching = false }
        results = (try? await TransitousClient.shared.geocode(text, near: WatchLocator.shared.last)) ?? []
        searched = true
    }
}

/// A saved place or stop in a list.
struct WatchPlaceRow: View {
    let place: SavedPlace

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: place.role?.symbol ?? (place.isStop ? "tram.fill" : "mappin"))
                .foregroundStyle(.secondary).frame(width: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: place.role?.title ?? place.name).font(.footnote.weight(.semibold)).lineLimit(2)
                if place.role != nil {
                    Text(verbatim: place.name).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                } else if let subtitle = place.subtitle, !subtitle.isEmpty {
                    Text(verbatim: subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            WatchCoverageMark(point: place.coordinate)
        }
        .accessibilityElement(children: .combine)
    }
}

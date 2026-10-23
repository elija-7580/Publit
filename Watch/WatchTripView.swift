import SwiftUI

/// A trip as screens you page through with the Digital Crown: the overview first, then one screen for every ride
/// and longer walk. Each has its own Map button. A trip under way opens on the leg you are on.
struct WatchTripView: View {
    let itinerary: Itinerary
    let from: String
    let to: String

    @Environment(WatchLibrary.self) private var library
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: WatchTripPage
    @State private var followed: WatchTripPage
    @State private var loaded: Itinerary?

    init(itinerary: Itinerary, from: String, to: String) {
        self.itinerary = itinerary
        self.from = from
        self.to = to
        let first = WatchTripPages.current(in: itinerary, now: .now)
        _selection = State(initialValue: first)
        _followed = State(initialValue: first)
    }

    /// The newest copy: the saved trip (refreshed here or on the iPhone), else what was loaded on this screen.
    private var shown: Itinerary { library.snapshot.trip(for: itinerary)?.itinerary ?? loaded ?? itinerary }

    var body: some View {
        let it = shown
        let pages = WatchTripPages.pages(for: it)
        TabView(selection: $selection) {
            ForEach(pages, id: \.self) { page in
                pageView(page, in: it)
                    .tag(page)
            }
        }
        .tabViewStyle(.verticalPage)
        .navigationTitle(Text(verbatim: to))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // On every page: the map of exactly this page (the whole trip on the overview, else this leg).
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: WatchRoute.map(OpenedRoute(itinerary: it), selection)) {
                    Image(systemName: "map.fill")
                }
                .accessibilityLabel(Text("Map"))
            }
        }
        .task(id: it.routeKey) { await keepFresh() }
        .task(id: it.routeKey) { await followClock() }
        .onChange(of: pages) { _, new in
            if !new.contains(selection) { selection = .overview }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refreshNow() } }
        }
    }

    @ViewBuilder
    private func pageView(_ page: WatchTripPage, in it: Itinerary) -> some View {
        switch page {
        case .overview:
            WatchTripOverview(itinerary: it, from: from, to: to)
                .containerBackground(Color.appAccent.opacity(0.25).gradient, for: .tabView)
        case .leg(let index):
            if it.legs.indices.contains(index) {
                let leg = it.legs[index]
                WatchLegPage(itinerary: it, index: index, from: from, to: to)
                    .containerBackground((leg.isTransit ? leg.lineStroke : Color.gray).opacity(0.28).gradient, for: .tabView)
            }
        }
    }

    /// Loads fresh times while the trip is near or under way: every minute or two while the app is open.
    private func keepFresh() async {
        while !Task.isCancelled {
            await refreshNow()
            let it = shown
            let next = TripStatus.at(Date(), it).nextEvent
            let wait = LiveRefresh.interval(start: it.startTime, end: it.endTime, nextEvent: next)
            try? await Task.sleep(for: .seconds(max(60, min(wait, 300))))
        }
    }

    private func refreshNow() async {
        let it = shown
        let now = Date()
        // Far ahead, or long over: the times will not change.
        guard now >= it.startTime.addingTimeInterval(-3 * 3600), now <= it.endTime.addingTimeInterval(10 * 60) else { return }
        if let saved = library.snapshot.trip(for: it) {
            await library.refresh(trip: saved.id)
        } else if let fresh = try? await TripRefreshCoordinator.shared.refresh(it.id) {
            loaded = fresh
        }
    }

    /// The page follows the trip: when the ride you are on ends, the next one comes up (unless you looked elsewhere).
    private func followClock() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(20))
            let now = WatchTripPages.current(in: shown, now: Date())
            if now != followed {
                if selection == followed { selection = now }
                followed = now
            }
        }
    }
}

// MARK: Overview

struct WatchTripOverview: View {
    let itinerary: Itinerary
    let from: String
    let to: String
    @Environment(WatchLibrary.self) private var library

    var body: some View {
        TimelineView(.everyMinute) { context in
            let now = context.date
            let snap = library.snapshot
            let saved = snap.trip(for: itinerary)
            let started = saved != nil && snap.activeTripId == saved?.id
            let tickets = WatchTickets.forTrip(saved?.id, in: snap.tickets, at: itinerary.startTime)
            let blocked = TripStatus.startBlocked(itinerary, now: now)
            let live = started || (now >= itinerary.startTime.addingTimeInterval(-3600) && now <= itinerary.endTime.addingTimeInterval(300))
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    // Missing data first: it decides how far the times below can be trusted.
                    WatchCoverageNote(notices: CoverageGuide.notices(for: itinerary))
                    header
                    if live { status(now: now) }
                    if let first = tickets.first {
                        NavigationLink(value: tickets.count == 1 ? WatchRoute.ticket(first.id) : WatchRoute.tickets) {
                            Label("Tickets", systemImage: "ticket.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.appAccent)
                    }
                    NavigationLink(value: WatchRoute.map(OpenedRoute(itinerary: itinerary), .overview)) {
                        Label("Map", systemImage: "map.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    startButton(saved: saved, started: started, blocked: blocked)
                    saveButton(saved: saved)
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Trip overview").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(verbatim: "\(from) → \(to)").font(.headline).lineLimit(3)
            let tz = itinerary.legs.first?.from.tz
            HStack(spacing: 4) {
                Text(verbatim: Fmt.time(itinerary.startTime, tz: tz)).monospacedDigit()
                Text(verbatim: "→")
                Text(verbatim: Fmt.time(itinerary.endTime, tz: itinerary.legs.last?.to.tz)).monospacedDigit()
            }
            .font(.title3.weight(.semibold))
            Text(verbatim: "\(Fmt.duration(seconds: itinerary.duration)) · \(Fmt.changes(itinerary.transfers))")
                .font(.footnote).foregroundStyle(.secondary)
            WatchFlowLayout(spacing: 4) {
                ForEach(Array(itinerary.transitLegs.enumerated()), id: \.offset) { _, leg in
                    LineBadge(leg, compact: true)
                }
            }
            .padding(.top, 2)
        }
        .accessibilityElement(children: .combine)
    }

    private func status(now: Date) -> some View {
        let status = TripStatus.at(now, itinerary)
        return VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: status.headline)
                .font(.footnote.weight(.bold))
                .foregroundStyle(status.phase == .cancelled ? Color.danger : status.delayMinutes > 0 ? Color.delay : Color.primary)
            Text(verbatim: status.detail).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.live.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func startButton(saved: SavedTrip?, started: Bool, blocked: String?) -> some View {
        if started, let saved {
            Button { library.stop(trip: saved.id) } label: {
                Label("End trip", systemImage: "stop.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(Color.danger)
        } else if let blocked {
            Text(verbatim: blocked).font(.caption2).foregroundStyle(Color.danger)
        } else {
            Button {
                let trip = saved ?? library.save(itinerary, from: from, to: to)
                library.start(trip: trip.id)
            } label: {
                Label("Start trip", systemImage: "play.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(Color.live)
        }
    }

    @ViewBuilder
    private func saveButton(saved: SavedTrip?) -> some View {
        if let saved {
            Button { library.remove(trip: saved.id) } label: {
                Label("Remove", systemImage: "star.slash").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        } else {
            Button { library.save(itinerary, from: from, to: to) } label: {
                Label("Save trip", systemImage: "star").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }
}

// MARK: One leg

/// One ride or longer walk: line and direction, where it starts and ends, and the Map button for exactly this section.
struct WatchLegPage: View {
    let itinerary: Itinerary
    let index: Int
    let from: String
    let to: String

    var body: some View {
        let leg = itinerary.legs[index]
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if leg.isTransit { rideHeader(leg) } else { walkHeader(leg) }
                stop(leg.from, time: leg.startTime, scheduled: leg.scheduledStartTime, fallback: from, departing: true)
                between(leg)
                stop(leg.to, time: leg.endTime, scheduled: leg.scheduledEndTime, fallback: to, departing: false)
                note(leg)
                NavigationLink(value: WatchRoute.map(OpenedRoute(itinerary: itinerary), .leg(index))) {
                    Label("Map", systemImage: "map.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(leg.isTransit ? leg.lineStroke : Color.appAccent)
            }
            .padding(.horizontal, 2)
        }
    }

    private func rideHeader(_ leg: Leg) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                LineBadge(leg, compact: true)
                if leg.cancelled == true {
                    Text("Cancelled").font(.caption2.weight(.bold)).foregroundStyle(Color.danger)
                } else if leg.realTime {
                    Image(systemName: "dot.radiowaves.left.and.right").font(.caption2).foregroundStyle(Color.live)
                        .accessibilityLabel(Text("Live"))
                }
            }
            DirectionLabel(direction: leg.shownDirection, circular: leg.isCircular, font: .footnote).lineLimit(2)
        }
    }

    private func walkHeader(_ leg: Leg) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "figure.walk").font(.headline)
            Text(L10n.f("Walk %@", Fmt.duration(seconds: leg.duration))).font(.headline)
            if let d = leg.distance, d > 0 {
                Text(verbatim: Fmt.distance(meters: d)).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    /// Time and name of where the leg starts or ends, with the platform when there is one.
    private func stop(_ place: Place, time: Date, scheduled: Date, fallback: String, departing: Bool) -> some View {
        let delay = Int((time.timeIntervalSince(scheduled) / 60).rounded())
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: Fmt.time(time, tz: place.tz))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(delay > 0 ? Color.delay : Color.primary)
                if delay > 0 {
                    Text(L10n.f("+%lld min", delay)).font(.caption2).foregroundStyle(Color.delay)
                }
            }
            Text(verbatim: Self.name(place, fallback: fallback)).font(.footnote).lineLimit(2)
            if let track = place.track, !track.isEmpty {
                HStack(spacing: 4) {
                    Text(L10n.f("Pl. %@", track)).font(.caption2.weight(.semibold))
                    if place.platformChange != nil {
                        Text("Platform changed").font(.caption2.weight(.semibold)).foregroundStyle(Color.delay)
                    }
                }
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func between(_ leg: Leg) -> some View {
        let stops = leg.intermediateStops?.count ?? 0
        if leg.isTransit {
            Label {
                Text(verbatim: stops > 0 ? "\(Fmt.stops(stops)) · \(Fmt.duration(seconds: leg.duration))" : Fmt.duration(seconds: leg.duration))
                    .font(.caption2)
            } icon: {
                Image(systemName: "arrow.down").font(.caption2)
            }
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func note(_ leg: Leg) -> some View {
        if let alert = leg.alerts?.first, !alert.headerText.isEmpty {
            Label {
                Text(verbatim: alert.headerText).font(.caption2).lineLimit(3)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").font(.caption2).foregroundStyle(Color.delay)
            }
        }
    }

    /// MOTIS calls the endpoints of a search "START" and "END".
    private static func name(_ place: Place, fallback: String) -> String {
        place.name == "START" || place.name == "END" ? fallback : place.name
    }
}

/// Lines of small views that wrap, like words.
struct WatchFlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

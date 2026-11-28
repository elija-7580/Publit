import SwiftUI

struct FavoritesView: View {
    @Environment(FavoritesStore.self) private var favorites
    @Environment(AppState.self) private var app
    @Environment(TripStore.self) private var trips
    @State private var adding = false
    @State private var settingRole: PlaceRole?
    @State private var addingShortcut = false

    var body: some View {
        List {
            Section {
                ForEach(PlaceRole.allCases, id: \.self) { role in
                    if let p = favorites.place(for: role) {
                        Button { app.route(to: p, source: .favorite) } label: {
                            PlaceKeyRow(symbol: role.symbol, title: role.title, detail: p.name, routes: true)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button(role: .destructive) { favorites.clear(role) } label: { Label("Remove", systemImage: "trash") }.tint(Color.danger)
                            Button { settingRole = role } label: { Label("Change", systemImage: "pencil") }
                        }
                        .swipeActions(edge: .leading) { lastConnectionButton(p) }
                        .contextMenu { lastConnectionButton(p) }
                        .accessibilityHint("Plans a route to \(role.title)")
                    } else {
                        Button { settingRole = role } label: {
                            PlaceKeyRow(symbol: "plus", title: L10n.f("Set %@", role.title))
                        }
                        .buttonStyle(.plain)
                    }
                }
                // Own shortcuts next to Home and Work (#22): a gym, a school, someone's flat.
                ForEach(favorites.shortcuts) { p in
                    Button { app.route(to: p, source: .favorite) } label: {
                        PlaceKeyRow(symbol: p.shownSymbol, title: p.name, detail: p.subtitle, routes: true)
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button(role: .destructive) { favorites.removeShortcut(p.id) } label: {
                            Label("Remove", systemImage: "trash")
                        }.tint(Color.danger)
                    }
                    .swipeActions(edge: .leading) { lastConnectionButton(p) }
                    .contextMenu {
                        lastConnectionButton(p)
                        ShortcutSymbolMenu(place: p)
                        Button(role: .destructive) { favorites.removeShortcut(p.id) } label: {
                            Label("Remove shortcut", systemImage: "minus.circle")
                        }
                    }
                    .accessibilityHint(L10n.f("Plans a route to %@", p.name))
                }
                .onMove { favorites.moveShortcuts(fromOffsets: $0, toOffset: $1) }
                Button { addingShortcut = true } label: {
                    PlaceKeyRow(symbol: "plus", title: L10n.t("Add shortcut"))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("addShortcut")
            } header: {
                Text("Home and Work")
            } footer: {
                Text("Shortcuts are also on the Nearby screen, in widgets and in the Shortcuts app.")
            }

            upcomingTrips

            if !favorites.connections.isEmpty {
                Section("Connections") {
                    ForEach(favorites.connections) { c in
                        Button { app.route(c) } label: { SavedConnectionRow(connection: c) }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .leading) {
                                Button { app.route(c.reversed) } label: {
                                    Label("Way back", systemImage: "arrow.uturn.backward")
                                }.tint(Color.inkAction)
                            }
                            .contextMenu {
                                Button { app.route(c.reversed) } label: {
                                    Label("Way back", systemImage: "arrow.uturn.backward")
                                }
                            }
                    }
                    .onDelete { idx in favorites.removeConnections(idx.map { favorites.connections[$0].id }) }
                    .onMove { favorites.moveConnections(fromOffsets: $0, toOffset: $1) }
                }
            }

            if !favorites.lines.isEmpty {
                Section("Lines") {
                    ForEach(favorites.lines) { line in
                        NavigationLink {
                            // One direction (#21): straight to its next departures there.
                            if line.directionId != nil {
                                LineDeparturesView(line: line)
                            } else {
                                LineDetailView(line: LineRef(saved: line))
                            }
                        } label: {
                            SavedLineRow(line: line)
                        }
                    }
                    .onDelete { idx in favorites.removeLines(idx.map { favorites.lines[$0].id }) }
                    .onMove { favorites.moveLines(fromOffsets: $0, toOffset: $1) }
                }
            }
            if favorites.stops.isEmpty && favorites.places.isEmpty && favorites.lines.isEmpty && favorites.connections.isEmpty {
                Section {
                    EmptyState(title: L10n.t("Nothing else saved yet"), systemImage: "star",
                               message: L10n.t("Save stops from their departure board, lines from a trip, connections from Plan, or add places with +."))
                }
            }
            if !favorites.stops.isEmpty {
                Section("Stops") {
                    ForEach(favorites.stops) { s in
                        NavigationLink {
                            StopDeparturesView(stopId: s.stopId ?? s.id, name: s.name, coordinate: s.coordinate, exact: s.exact == true)
                        } label: {
                            HStack(spacing: 8) {
                                PlaceLabel(name: s.name, subtitle: s.subtitle, isStop: true)
                                Spacer(minLength: 0)
                                CoverageMark(point: s.coordinate)
                            }
                        }
                    }
                    .onDelete { idx in favorites.remove(idx.map { favorites.stops[$0].id }) }
                    .onMove { favorites.moveStops(fromOffsets: $0, toOffset: $1) }
                }
            }
            if !favorites.places.isEmpty {
                Section("Places") {
                    ForEach(favorites.places) { p in
                        Button { app.route(to: p, source: .favorite) } label: {
                            HStack(spacing: 8) {
                                PlaceLabel(name: p.name, subtitle: p.subtitle, isStop: false)
                                Spacer(minLength: 0)
                                CoverageMark(point: p.coordinate)
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button { favorites.set(p, as: .home) } label: { Label("Home", systemImage: "house") }.tint(Color.inkAction)
                            Button { favorites.set(p, as: .work) } label: { Label("Work", systemImage: "briefcase") }.tint(Color.inkAction)
                            lastConnectionButton(p)
                        }
                        .contextMenu {
                            lastConnectionButton(p)
                            Button { favorites.addShortcut(p) } label: { Label("Make a shortcut", systemImage: "star.circle") }
                        }
                    }
                    .onDelete { idx in favorites.remove(idx.map { favorites.places[$0].id }) }
                    .onMove { favorites.movePlaces(fromOffsets: $0, toOffset: $1) }
                }
            }
        }
        .readableWidth()
        .inkList()
        .navigationTitle("Saved")
        .screenTrail("Saved")
        .withSettingsButton()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { adding = true } label: { Label("Add", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $adding) {
            PlaceSearchView(title: "Save a place", allowCurrentLocation: false) { endpoint in
                if case .place(let p) = endpoint, !favorites.contains(p) { favorites.toggle(p) }
            }
        }
        .sheet(isPresented: $addingShortcut) {
            PlaceSearchView(title: "Add shortcut", allowCurrentLocation: false) { endpoint in
                if case .place(let p) = endpoint { favorites.addShortcut(p) }
            }
        }
        .sheet(item: $settingRole) { role in
            PlaceSearchView(title: "Set \(role.title)", allowCurrentLocation: false) { endpoint in
                if case .place(let p) = endpoint { favorites.set(p, as: role) }
            }
        }
    }

    /// Saved trips still to come, right below Home and Work; past ones on their own screen.
    @ViewBuilder
    private var upcomingTrips: some View {
        let upcoming = trips.upcoming()
        Section {
            ForEach(upcoming) { t in
                NavigationLink { SavedTripView(tripId: t.id, detailsFirst: true) } label: { SavedTripRow(trip: t) }
                    .linkIndicatorHidden()
            }
            .onDelete { idx in idx.map { upcoming[$0].id }.forEach { id in
                LeaveReminder.cancel(id); Task { await LiveTripActivity.end(id) }; trips.remove(id)
            } }
            if !trips.past().isEmpty {
                NavigationLink { PastTripsView() } label: {
                    Label("Past trips", systemImage: "clock.arrow.circlepath")
                }
                .accessibilityIdentifier("pastTrips")
            }
        } header: {
            Text("Upcoming trips")
        } footer: {
            if upcoming.isEmpty {
                Text("Save a route to see it here, add it to your calendar and get a reminder when to leave.")
            }
        }
    }

    /// Tonight's last connection from here to a saved place.
    private func lastConnectionButton(_ p: SavedPlace) -> some View {
        Button { app.lastConnection(to: p) } label: {
            Label("Last connection", systemImage: SmartRouting.Badge.lastConnection.symbol)
        }
        .tint(Color.inkAction)
        .accessibilityIdentifier("lastConnection")
    }
}

/// Trips that are over, newest first. Swipe right to plan the same route again next week.
struct PastTripsView: View {
    @Environment(AppState.self) private var app
    @Environment(TripStore.self) private var trips

    var body: some View {
        let past = Array(trips.past().prefix(50))
        List {
            ForEach(past) { t in
                NavigationLink { SavedTripView(tripId: t.id) } label: { SavedTripRow(trip: t).opacity(0.7) }
                    .swipeActions(edge: .leading) {
                        Button { planAgain(t) } label: { Label("Plan again", systemImage: "arrow.clockwise") }
                            .tint(Color.inkAction)
                    }
            }
            .onDelete { idx in idx.map { past[$0].id }.forEach(trips.remove) }
        }
        .readableWidth()
        .inkList()
        .overlay {
            if past.isEmpty { ContentUnavailableView("Past trips", systemImage: "clock.arrow.circlepath") }
        }
        .navigationTitle("Past trips")
        .screenTrail("Past trips")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Same route again: same places, next week at the same time, in the Plan tab.
    private func planAgain(_ t: SavedTrip) {
        app.plan.from = .place(SavedPlace(id: "trip-from-\(t.id)", name: t.fromName, subtitle: nil,
            lat: t.itinerary.legs.first?.from.lat ?? 0, lon: t.itinerary.legs.first?.from.lon ?? 0, stopId: nil))
        app.plan.to = .place(SavedPlace(id: "trip-to-\(t.id)", name: t.toName, subtitle: nil,
            lat: t.itinerary.legs.last?.to.lat ?? 0, lon: t.itinerary.legs.last?.to.lon ?? 0, stopId: nil))
        app.plan.timeMode = .departAt
        app.plan.date = PlanView.nextOccurrence(of: t.startTime)
        app.plan.searchStarted = true
        app.tab = .plan
    }
}

/// Picks the symbol of an own shortcut.
struct ShortcutSymbolMenu: View {
    let place: SavedPlace
    @Environment(FavoritesStore.self) private var favorites

    var body: some View {
        Menu {
            ForEach(SavedPlace.shortcutSymbols, id: \.self) { symbol in
                Button { favorites.setSymbol(symbol, for: place.id) } label: { Image(systemName: symbol) }
            }
        } label: {
            Label("Icon", systemImage: place.shownSymbol)
        }
    }
}

/// A saved line: badge, its direction (when saved for one) and stop, and the next times there.
struct SavedLineRow: View {
    let line: SavedLine
    @State private var next: [StopTime] = []

    var body: some View {
        HStack(spacing: 10) {
            LineBadge(line)
            VStack(alignment: .leading, spacing: 1) {
                if let h = line.headsign { Text(verbatim: "→ \(h)").font(.subheadline.weight(.semibold)).lineLimit(1) }
                Text(L10n.f("At %@", line.stopName)).font(line.headsign == nil ? .body : .caption)
                    .foregroundStyle(line.headsign == nil ? .primary : .secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if !next.isEmpty {
                Text(verbatim: next.prefix(2).map { Fmt.time($0.departureTime, tz: $0.place.tz) }.joined(separator: " · "))
                    .font(.subheadline.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(next.first?.realTime == true ? Color.live : .secondary)
            }
        }
        .task(id: line.id) {
            // Only for a line saved in one direction: the times say when to leave.
            guard line.directionId != nil,
                  let res = try? await TransitousClient.shared.departures(stopId: line.stopId, count: 60,
                                                                          radius: StopDeparturesView.stationRadius) else { return }
            next = Array(StopTime.upcoming(res.stopTimes).filter { line.matches($0) && !$0.isCancelled }.prefix(2))
        }
    }

    /// "→ Destination · At Stop", or "At Stop" for every direction.
    static func subtitle(_ line: SavedLine) -> String {
        let at = L10n.f("At %@", line.stopName)
        return line.headsign.map { "→ \($0) · \(at)" } ?? at
    }
}

/// A saved connection: from → to, and when the next one leaves (with its first line).
struct SavedConnectionRow: View {
    let connection: SavedConnection
    @State private var next: Itinerary?
    @State private var loaded = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.swap")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.ink)
                .frame(width: 34, height: 34)
                .background(Color.inkFill, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: connection.from.name).font(.body.weight(.semibold)).lineLimit(1)
                Text(verbatim: "→ " + connection.to.name).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if let next {
                VStack(alignment: .trailing, spacing: 2) {
                    if let leg = next.firstTransitLeg { LineBadge(leg) }
                    Text(Fmt.time(next.firstDeparture ?? next.startTime))
                        .font(.subheadline.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(next.hasRealtime ? Color.live : .primary)
                }
            } else if !loaded {
                ProgressView().controlSize(.small)
            }
        }
        .frame(minHeight: 46)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .task(id: connection.id) {
            let res = try? await TransitousClient.shared.plan(
                from: connection.from.coordinate, to: connection.to.coordinate, time: nil, arriveBy: false,
                stops: PlanStops(from: connection.from.stopId, to: connection.to.stopId))
            next = res?.itineraries.first { !$0.isCancelled && ($0.firstDeparture ?? $0.startTime) > .now.addingTimeInterval(-60) }
            loaded = true
        }
    }
}

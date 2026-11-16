import SwiftUI

struct PlaceSearchView: View {
    let title: LocalizedStringKey
    let allowCurrentLocation: Bool
    /// Pushed onto the caller's navigation stack (Nearby) instead of shown as its own sheet:
    /// no second window over the screen. The caller goes back itself after a pick.
    var embedded = false
    /// "Choose on map" under the current location (the From and To fields of the planners).
    var chooseOnMap = false
    let onSelect: (Endpoint) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(FavoritesStore.self) private var favorites
    @Environment(LocationManager.self) private var location
    @Environment(SearchHistoryStore.self) private var history
    @State private var confirmClear = false
    @State private var query = ""
    @State private var scope: PlaceSearchScope = .all
    @State private var search = PlaceSearchModel()
    @State private var fieldActive = false
    /// One pick at a time: a second tap while a suggestion is looked up does nothing.
    @State private var picked = false

    var body: some View {
        if embedded {
            content
        } else {
            NavigationStack {
                content
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    }
            }
        }
    }

    private var content: some View {
        List {
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                // Home and Work first, then the current location, other saved places, recent ones.
                Section {
                    ForEach(PlaceRole.allCases, id: \.self) { role in
                        if let p = favorites.place(for: role) {
                            Button { select(.place(p)) } label: {
                                Label {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(role.title).foregroundStyle(.primary)
                                        Text(verbatim: p.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                } icon: { Image(systemName: role.symbol) }
                            }
                            .accessibilityIdentifier("pick-\(role.rawValue)")
                        }
                    }
                    if allowCurrentLocation && !location.isDenied {
                        Button { select(.currentLocation) } label: {
                            Label("Current location", systemImage: "location.fill")
                        }
                    }
                    if chooseOnMap {
                        NavigationLink {
                            ChooseOnMapView(start: location.coordinate) { place in select(.place(place)) }
                        } label: {
                            Label("Choose on map", systemImage: "mappin.and.ellipse")
                        }
                        .accessibilityIdentifier("chooseOnMap")
                    }
                }
                let others = favorites.items.filter { $0.role == nil }
                if !others.isEmpty {
                    Section("Saved") {
                        ForEach(others) { f in
                            Button { select(.place(f)) } label: {
                                PlaceLabel(name: f.name, subtitle: f.subtitle, isStop: f.isStop)
                            }
                        }
                    }
                }
                recentSection
            } else {
                if let message = search.errorMessage {
                    Text(verbatim: message).foregroundStyle(.secondary)
                } else if search.hits.isEmpty && !search.isSearching && search.searched == PlaceSearchModel.key(query, scope) {
                    Text("No matches.").foregroundStyle(.secondary)
                }
                ForEach(search.hits) { hit in
                    PlaceHitRow(hit: hit, resolving: search.resolving) { save in pick(hit, save: save) }
                }
            }
        }
        .inkList()
        .environment(\.liveBarInset, 0)
        .searchable(text: $query, isPresented: $fieldActive, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Address, stop or place")
        .searchScopes($scope, activation: .onTextEntry) {
            ForEach(PlaceSearchScope.allCases) { Text(verbatim: $0.title).tag($0) }
        }
        .autocorrectionDisabled()
        .onSubmit(of: .search) { if let first = search.hits.first { pick(first, save: false) } }
        .navigationTitle(title)
        .screenTrail("Place search")
        .navigationBarTitleDisplayMode(.inline)
        // Opened to type: the keyboard is up right away, as in Apple Maps.
        .task {
            try? await Task.sleep(for: .milliseconds(embedded ? 450 : 350))
            fieldActive = true
        }
        .task(id: "\(scope.rawValue)|\(query)") {
            await search.search(query, scope: scope, near: location.coordinate)
        }
    }

    /// Places searched before, newest first: the history lives where you search.
    private var recentPlaces: [RecentSearch] {
        var seen = Set<String>()
        return history.entries.filter { entry in
            if case .currentLocation = entry.to { return false }
            return seen.insert(entry.to.key).inserted
        }
    }

    @ViewBuilder
    private var recentSection: some View {
        let recent = Array(recentPlaces.prefix(6))
        if !recent.isEmpty {
            Section {
                ForEach(recent) { search in
                    Button { select(search.to) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.title3).foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(search.to.title).foregroundStyle(.primary).lineLimit(1)
                                Text(L10n.f("from %@", search.from.title)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                    .accessibilityIdentifier("recentSearch")
                    .swipeActions { Button("Remove", role: .destructive) { history.remove(search.id) } }
                }
                Button("Clear history", role: .destructive) { confirmClear = true }
                    .font(.subheadline)
            } header: { Text("Recently searched") }
            .confirmationDialog("Clear search history?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear history", role: .destructive) { history.clear() }
                Button("Cancel", role: .cancel) { }
            }
        }
    }

    private func select(_ endpoint: Endpoint) {
        guard !picked else { return }
        picked = true
        onSelect(endpoint)
        if !embedded { dismiss() }
    }

    /// A hit is used as it is; a suggestion is looked up first (it has no coordinates yet).
    private func pick(_ hit: PlaceHit, save: Bool) {
        switch hit {
        case .match(let m):
            let place = SavedPlace(match: m)
            if save { favorites.toggle(place) } else { select(.place(place)) }
        case .suggestion(let s):
            guard search.resolving == nil, !picked else { return }
            Task {
                guard let m = await search.resolve(s) else { return }
                let place = SavedPlace(match: m)
                if save { favorites.toggle(place) } else { select(.place(place)) }
            }
        }
    }
}

/// One line of the place search: a stop, an address or a place, with "Save" on a swipe.
struct PlaceHitRow: View {
    let hit: PlaceHit
    let resolving: String?
    let onPick: (_ save: Bool) -> Void
    @Environment(FavoritesStore.self) private var favorites

    var body: some View {
        Button { onPick(false) } label: {
            HStack(spacing: 8) {
                switch hit {
                case .match(let m):
                    PlaceLabel(name: m.name, subtitle: m.subtitle, isStop: m.isStop, category: m.category)
                    Spacer(minLength: 0)
                    // Data is missing around this place: said before it is picked.
                    CoverageMark(point: LatLon(lat: m.lat, lon: m.lon))
                case .suggestion(let s):
                    PlaceLabel(name: s.title, subtitle: s.subtitle, isStop: s.isStop)
                    Spacer(minLength: 0)
                    if resolving == s.id { ProgressView() }
                }
            }
            .contentShape(Rectangle())
        }
        .disabled(resolving != nil)
        .swipeActions {
            Button { onPick(true) } label: {
                Label("Save", systemImage: isSaved ? "star.slash" : "star")
            }
            .tint(Color.inkAction)
        }
        .accessibilityIdentifier("placeSearchResult")
    }

    private var isSaved: Bool {
        guard let m = hit.match else { return false }
        return favorites.contains(SavedPlace(match: m))
    }
}

struct PlaceLabel: View {
    let name: String
    let subtitle: String?
    let isStop: Bool
    /// Apple's kind of place ("restaurant"): its coloured symbol, as in Apple Maps.
    var category: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            if !isStop, let c = PlaceCategory.of(category) {
                CategoryIcon(category: c, size: 28)
            } else {
                Image(systemName: isStop ? "tram.circle.fill" : "mappin.circle.fill")
                    .font(.title3)
                    .foregroundStyle(isStop ? Color.ink : Color.secondary)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(name).foregroundStyle(.primary).lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }
}

/// A kind of place as Apple Maps draws it: white symbol on a circle in the category's colour.
struct CategoryIcon: View {
    let category: PlaceCategory
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: category.symbol)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color(uiColor: UIColor(hex: category.colorHex)), in: Circle())
            .accessibilityHidden(true)
    }
}

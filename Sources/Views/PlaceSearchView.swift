import SwiftUI

struct PlaceSearchView: View {
    let title: LocalizedStringKey
    let allowCurrentLocation: Bool
    let onSelect: (Endpoint) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(FavoritesStore.self) private var favorites
    @Environment(LocationManager.self) private var location
    @Environment(SearchHistoryStore.self) private var history
    @State private var confirmClear = false
    @State private var query = ""
    @State private var results: [GeocodeMatch] = []
    @State private var errorMessage: String?
    @State private var isSearching = false
    /// Query the current results belong to; "No matches." only after a real search.
    @State private var searchToken = UUID()
    @State private var searched: String?
    @State private var scope: SearchScope = .all

    /// Search everything, or only stops, addresses or places (shops, sights, airports…).
    enum SearchScope: String, CaseIterable, Identifiable {
        case all, stops, addresses, places
        var id: String { rawValue }
        var apiType: String? {
            switch self {
            case .all: return nil
            case .stops: return "STOP"
            case .addresses: return "ADDRESS"
            case .places: return "PLACE"
            }
        }
        var title: LocalizedStringKey {
            switch self {
            case .all: return "All"
            case .stops: return "Stops"
            case .addresses: return "Addresses"
            case .places: return "Places"
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    if allowCurrentLocation && !location.isDenied {
                        Button { select(.currentLocation) } label: {
                            Label("Current location", systemImage: "location.fill")
                        }
                    }
                    recentSection
                    if !favorites.items.isEmpty {
                        Section("Saved") {
                            ForEach(favorites.items) { f in
                                Button { select(.place(f)) } label: {
                                    PlaceLabel(name: f.name, subtitle: f.subtitle, isStop: f.isStop)
                                }
                            }
                        }
                    }
                } else {
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.secondary)
                    } else if results.isEmpty && !isSearching && searched == query.trimmingCharacters(in: .whitespaces) + "|" + scope.rawValue {
                        Text("No matches.").foregroundStyle(.secondary)
                    }
                    ForEach(results) { m in
                        let saved = SavedPlace(match: m)
                        Button { select(.place(saved)) } label: {
                            PlaceLabel(name: m.name, subtitle: m.subtitle, isStop: m.isStop)
                        }
                        .swipeActions {
                            Button { favorites.toggle(saved) } label: {
                                Label("Save", systemImage: favorites.contains(saved) ? "star.slash" : "star")
                            }
                            .tint(.yellow)
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Address, stop or place")
            .searchScopes($scope, activation: .onTextEntry) {
                ForEach(SearchScope.allCases) { Text($0.title).tag($0) }
            }
            .autocorrectionDisabled()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .task(id: "\(scope.rawValue)|\(query)") { await search() }
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
        onSelect(endpoint)
        dismiss()
    }

    private func search() async {
        let token = UUID()
        searchToken = token
        let text = query.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2 else { results = []; errorMessage = nil; searched = nil; isSearching = false; return }
        // Debounce: the task is cancelled when the query changes again.
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        isSearching = true
        defer { if searchToken == token { isSearching = false } }
        do {
            let r = try await TransitousClient.shared.geocode(text, near: location.coordinate, type: scope.apiType)
            guard !Task.isCancelled, searchToken == token else { return }
            results = r
            errorMessage = nil
            searched = text + "|" + scope.rawValue
        } catch {
            guard !Task.isCancelled, searchToken == token else { return }
            if !(error is CancellationError) && (error as? URLError)?.code != .cancelled {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct PlaceLabel: View {
    let name: String
    let subtitle: String?
    let isStop: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isStop ? "tram.circle.fill" : "mappin.circle.fill")
                .font(.title3)
                .foregroundStyle(isStop ? Color.blue : Color.red)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).foregroundStyle(.primary).lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }
}

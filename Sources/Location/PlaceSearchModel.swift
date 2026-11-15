import Foundation
import MapKit

/// Apple Maps' autocomplete, the same suggestions as typing into Apple Maps: every street and
/// house number as you type ("Hauptstr 1" already offers "Hauptstraße 12"), shops and sights by
/// name. Only the typed text and the area around you go to Apple, as for the map itself.
@MainActor
final class AppleCompleter: NSObject, MKLocalSearchCompleterDelegate {
    private let completer = MKLocalSearchCompleter()
    private var waiting: CheckedContinuation<[MKLocalSearchCompletion], Never>?
    /// Each request has its own number, so a late timeout never answers a newer request.
    private var generation = 0
    /// The completions of the last answer, to look one up when it is picked.
    private var byId: [String: MKLocalSearchCompletion] = [:]

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func complete(_ text: String, near: LatLon?, scope: PlaceSearchScope) async -> [PlaceSuggestion] {
        let types: MKLocalSearchCompleter.ResultType
        switch scope {
        case .stops: return []
        case .addresses: types = .address
        case .places: types = .pointOfInterest
        case .all: types = [.address, .pointOfInterest]
        }
        finish(nil)
        generation += 1
        let mine = generation
        if completer.resultTypes != types { completer.resultTypes = types }
        if let near, near.isValidCoordinate {
            completer.region = MKCoordinateRegion(center: near.clCoordinate, latitudinalMeters: 60_000, longitudinalMeters: 60_000)
        }
        let completions: [MKLocalSearchCompletion] = await withTaskCancellationHandler {
            await withCheckedContinuation { (c: CheckedContinuation<[MKLocalSearchCompletion], Never>) in
                waiting = c
                if completer.queryFragment == text, !completer.isSearching {
                    finish(completer.results)
                } else {
                    completer.queryFragment = text
                }
                // Apple does not answer (no network): carry on with the stops after a moment.
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(3))
                    guard let self, self.generation == mine else { return }
                    self.finish(self.completer.results)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, self.generation == mine else { return }
                self.finish(nil)
            }
        }
        guard !Task.isCancelled, generation == mine else { return [] }
        var list: [PlaceSuggestion] = []
        var ids: [String: MKLocalSearchCompletion] = [:]
        for c in completions.prefix(15) where !c.title.isEmpty {
            let id = c.title + "|" + c.subtitle
            guard ids[id] == nil else { continue }
            ids[id] = c
            let isAddress = types == .address || (c.title.contains { $0.isNumber } && types.contains(.address))
            list.append(PlaceSuggestion(id: id, title: c.title, subtitle: c.subtitle, source: .apple, isAddress: isAddress))
        }
        byId = ids
        return list
    }

    /// The picked suggestion with its coordinates.
    func resolve(_ s: PlaceSuggestion) async -> GeocodeMatch? {
        guard let c = byId[s.id] else { return nil }
        let response = try? await MKLocalSearch(request: MKLocalSearch.Request(completion: c)).start()
        guard let item = response?.mapItems.first else { return nil }
        return AppleSearch.match(item, fallbackName: c.title)
    }

    private func finish(_ results: [MKLocalSearchCompletion]?) {
        guard let w = waiting else { return }
        waiting = nil
        w.resume(returning: results ?? [])
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        MainActor.assumeIsolated { finish(completer.results) }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        MainActor.assumeIsolated { finish([]) }
    }
}

/// The place search shared by Plan (From/To), Nearby ("Where to now?"), saved places and the map:
/// stops from Transitous, addresses and places from Apple Maps' autocomplete (or Google's, when it
/// is switched on in Settings), in one list ordered like Apple Maps (`PlaceSearchRanking`).
@MainActor
@Observable
final class PlaceSearchModel {
    private(set) var hits: [PlaceHit] = []
    private(set) var isSearching = false
    private(set) var errorMessage: String?
    /// Text and scope the current hits belong to: "No matches" only after a real search.
    private(set) var searched: String?
    /// The suggestion being looked up after a tap.
    private(set) var resolving: String?

    @ObservationIgnored private let apple = AppleCompleter()
    @ObservationIgnored private var google: [String: GooglePlaces.Suggestion] = [:]
    @ObservationIgnored private var googleSession = UUID().uuidString
    @ObservationIgnored private var token = UUID()

    static func key(_ text: String, _ scope: PlaceSearchScope) -> String {
        text.trimmingCharacters(in: .whitespaces) + "|" + scope.rawValue
    }

    func clear() {
        token = UUID()
        hits = []
        errorMessage = nil
        searched = nil
        isSearching = false
    }

    /// Call from `.task(id:)` with the text: a new text cancels the running search.
    func search(_ raw: String, scope: PlaceSearchScope, near location: LatLon?) async {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard text.count >= MapSearch.minLength else { clear(); return }
        let mine = UUID()
        token = mine
        // Short pause while typing; Apple's completer answers quickly, Transitous is asked once.
        try? await Task.sleep(for: .milliseconds(220))
        guard !Task.isCancelled, token == mine else { return }
        isSearching = true
        defer { if token == mine { isSearching = false } }
        let key = Self.key(text, scope)

        // A pasted link from Google Maps, Apple Maps or OpenStreetMap: the place it points to.
        var query = text
        if let link = MapLink.parse(text: text) {
            let place = await MapLink.resolve(link)
            guard !Task.isCancelled, token == mine else { return }
            if let place, let lat = place.lat, let lon = place.lon {
                hits = [.match(GeocodeMatch.picked(name: place.name ?? L10n.t("Place from the link"), at: LatLon(lat: lat, lon: lon)))]
                errorMessage = nil
                searched = key
                return
            }
            if let name = place?.name ?? link.name, name != text { query = name }
        }

        let near = SearchBias.position(for: query, location: location)
        let useGoogle = GooglePlaces.isActive && scope != .stops
        let transitTask = Task { try await Self.transit(query, near: near, scope: scope) }
        let suggestions: [PlaceSuggestion] = await withTaskCancellationHandler {
            if useGoogle { return await googleSuggestions(query, near: location, scope: scope) }
            return await apple.complete(query, near: near, scope: scope)
        } onCancel: { transitTask.cancel() }
        guard !Task.isCancelled, token == mine else { transitTask.cancel(); return }

        // Apple's suggestions on screen at once when Transitous takes a while; the stops join them.
        let early = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, let self, self.token == mine, !suggestions.isEmpty else { return }
            self.hits = PlaceSearchRanking.order(transit: [], suggestions: suggestions, query: query, scope: scope)
            self.errorMessage = nil
        }
        let transit = await withTaskCancellationHandler { await transitTask.result } onCancel: { transitTask.cancel() }
        early.cancel()
        guard !Task.isCancelled, token == mine else { return }

        switch transit {
        case .success(let found):
            var fallback: [GeocodeMatch] = []
            // Neither Apple nor Google suggested anything: one full Apple search before giving up.
            if suggestions.isEmpty, scope != .stops, !useGoogle {
                fallback = await AppleSearch.places(query, near: near, addresses: scope != .places, places: scope != .addresses)
                guard !Task.isCancelled, token == mine else { return }
            }
            hits = PlaceSearchRanking.order(transit: SearchBias.combine(found, fallback, query: query, limit: 40),
                                            suggestions: suggestions, query: query, scope: scope)
            errorMessage = nil
            searched = key
        case .failure(let error):
            if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
            // Transitous failed: Apple's or Google's addresses and places still help (not the stops).
            if !suggestions.isEmpty {
                hits = PlaceSearchRanking.order(transit: [], suggestions: suggestions, query: query, scope: scope)
                errorMessage = nil
                searched = key
            } else {
                hits = []
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Stops (and for Transitous-only searches its addresses and places), with a wider second
    /// search when nothing near you carries every word (a big street across town).
    private static func transit(_ text: String, near: LatLon?, scope: PlaceSearchScope) async throws -> [GeocodeMatch] {
        let type = scope.apiType
        var r = try await TransitousClient.shared.geocode(text, near: near, type: type)
        if near != nil, SearchBias.needsWiderSearch(text, results: r),
           let wide = try? await TransitousClient.shared.geocode(text, near: nil, type: type) {
            r = SearchBias.merge(r, wide.filter { !SearchBias.needsWiderSearch(text, results: [$0]) })
        }
        return r
    }

    private func googleSuggestions(_ text: String, near: LatLon?, scope: PlaceSearchScope) async -> [PlaceSuggestion] {
        guard let list = try? await GooglePlaces.autocomplete(text, near: near, session: googleSession) else { return [] }
        var out: [PlaceSuggestion] = []
        for g in list where !g.isStop {
            if scope == .addresses, !g.isAddress { continue }
            if scope == .places, g.isAddress { continue }
            google[g.id] = g
            out.append(PlaceSuggestion(id: g.id, title: g.name, subtitle: g.subtitle, source: .google, isAddress: g.isAddress))
        }
        return out
    }

    /// The place behind a suggestion, with coordinates; nil (and a message) when it cannot be found.
    func resolve(_ s: PlaceSuggestion) async -> GeocodeMatch? {
        resolving = s.id
        defer { resolving = nil }
        switch s.source {
        case .apple:
            if let m = await apple.resolve(s) { return m }
            // The completion is gone (a newer search): ask Apple by its words.
            let text = s.subtitle.isEmpty ? s.title : s.title + ", " + s.subtitle
            if let m = await AppleSearch.places(text, near: nil).first { return m }
        case .google:
            if let g = google[s.id], let m = try? await GooglePlaces.place(g, session: googleSession) {
                // The session ends with the pick; the next typing starts a new one.
                googleSession = UUID().uuidString
                return m
            }
        }
        errorMessage = L10n.t("No matches.")
        return nil
    }
}

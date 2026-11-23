import Foundation

/// A suggestion from Apple Maps' or Google's autocomplete: a name without coordinates yet.
/// It is looked up when picked (`PlaceSearchModel.resolve`).
struct PlaceSuggestion: Identifiable, Hashable, Sendable {
    enum Source: Hashable, Sendable { case apple, google }
    let id: String
    let title: String
    let subtitle: String
    let source: Source
    /// A street address (with or without number), not a shop or sight.
    var isAddress = false
    /// Google sometimes suggests stations; Apple's completer is asked for addresses and places only.
    var isStop = false
}

/// One line in the place search: a hit with coordinates (Transitous, a map link, a resolved place)
/// or an autocomplete suggestion.
enum PlaceHit: Identifiable, Hashable, Sendable {
    case match(GeocodeMatch)
    case suggestion(PlaceSuggestion)

    var id: String {
        switch self {
        case .match(let m): return "m|" + m.id
        case .suggestion(let s): return "s|" + s.id
        }
    }

    var title: String {
        switch self {
        case .match(let m): return m.name
        case .suggestion(let s): return s.title
        }
    }

    var isStop: Bool {
        switch self {
        case .match(let m): return m.isStop
        case .suggestion(let s): return s.isStop
        }
    }

    var match: GeocodeMatch? {
        if case .match(let m) = self { return m }
        return nil
    }
}

/// What the place search looks for (the scope bar).
enum PlaceSearchScope: String, CaseIterable, Identifiable, Sendable {
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
    var title: String {
        switch self {
        case .all: return L10n.t("All")
        case .stops: return L10n.t("Stops")
        case .addresses: return L10n.t("Addresses")
        case .places: return L10n.t("Places")
        }
    }
}

/// Order of the place search, like Apple Maps: what you are typing comes first.
///
/// Stops come from Transitous (they route best by their ID), addresses and places from Apple's
/// autocomplete, which finds every street and house number as you type. Stops that carry every
/// word of the query head the list; an address query with a house number puts the addresses first.
enum PlaceSearchRanking {
    static let limit = 25

    static func order(transit: [GeocodeMatch], suggestions: [PlaceSuggestion], query: String,
                      scope: PlaceSearchScope) -> [PlaceHit] {
        let words = SearchBias.words(query)
        let number = SearchBias.houseNumber(in: query)
        func rank(_ m: GeocodeMatch) -> Int { SearchBias.rank(m, words: words, number: number) }
        func sorted(_ list: [GeocodeMatch]) -> [GeocodeMatch] {
            list.enumerated().sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }.map(\.element)
        }

        let stops = sorted(transit.filter(\.isStop))
        if scope == .stops { return Array(stops.prefix(limit)).map(PlaceHit.match) }

        // A suggestion that is a stop already listed (same name) only once: the stop routes better.
        // A street stays next to the stop named after it: it is another place to go to
        // ("Utendorfgasse" in Vienna, the bus stop and the street, #115).
        let stopNames = Set(stops.map { StopGrouping.normalizedName($0.name) })
        let kept = suggestions.filter { $0.isAddress || !stopNames.contains(StopGrouping.normalizedName($0.title)) }
        let keptNames = Set(kept.map { StopGrouping.normalizedName($0.title) })
        // Transitous' own addresses and places only when Apple has none of that name.
        let others = sorted(transit.filter { !$0.isStop && !keptNames.contains(StopGrouping.normalizedName($0.name)) })

        let strongStops = stops.filter { rank($0) == 0 }
        let weakStops = stops.filter { rank($0) != 0 }
        var out: [PlaceHit] = []
        switch scope {
        case .stops:
            break
        case .addresses, .places:
            out = kept.map(PlaceHit.suggestion)
            if kept.isEmpty { out += others.map(PlaceHit.match) }
        case .all:
            if number != nil {
                // "Hauptstraße 12": the address is what is meant.
                out = kept.map(PlaceHit.suggestion) + strongStops.map(PlaceHit.match)
            } else {
                out = strongStops.prefix(3).map(PlaceHit.match) + kept.map(PlaceHit.suggestion)
                    + strongStops.dropFirst(3).map(PlaceHit.match)
            }
            // Without any suggestion (offline, Apple has nothing) Transitous' hits are all there is.
            let rest = kept.isEmpty ? others : others.filter { rank($0) == 0 }
            out += rest.map(PlaceHit.match) + weakStops.map(PlaceHit.match)
        }
        var seen = Set<String>()
        return Array(out.filter { seen.insert($0.id).inserted }.prefix(limit))
    }
}

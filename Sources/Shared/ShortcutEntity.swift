// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich

import AppIntents
import Foundation

/// A destination for the shortcuts widget (#6, #22): Home, Work, or any place. Its data lives in the
/// identifier, so the widget needs no access to the app's saved places: Home and Work open
/// `publit://go/home|work`, which the app resolves with the places saved there.
struct ShortcutEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Shortcut"
    static var defaultQuery = ShortcutQuery()

    enum Kind: Hashable { case role(PlaceRole), place(name: String, lat: Double, lon: Double, symbol: String?) }

    let id: String
    let kind: Kind

    init(role: PlaceRole) {
        kind = .role(role)
        id = role.rawValue
    }

    init(name: String, lat: Double, lon: Double, symbol: String?) {
        kind = .place(name: name, lat: lat, lon: lon, symbol: symbol)
        id = "p|\(lat),\(lon)|\(symbol ?? "")|\(name)"
    }

    /// `home`, `work` or `p|lat,lon|symbol|name`.
    init?(id: String) {
        if let role = PlaceRole(rawValue: id) { self.init(role: role); return }
        let parts = id.split(separator: "|", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 4, parts[0] == "p" else { return nil }
        let coords = parts[1].split(separator: ",").compactMap { Double($0) }
        guard coords.count == 2, LatLon(lat: coords[0], lon: coords[1]).isValidCoordinate, !parts[3].isEmpty else { return nil }
        self.init(name: parts[3], lat: coords[0], lon: coords[1], symbol: parts[2].isEmpty ? nil : parts[2])
    }

    var title: String {
        switch kind {
        case .role(let r): return r.title
        case .place(let name, _, _, _): return name
        }
    }

    var symbol: String {
        switch kind {
        case .role(let r): return r.symbol
        case .place(_, _, _, let s): return s ?? "mappin"
        }
    }

    var deepLink: URL {
        switch kind {
        case .role(let r): return DeepLink.go(r).url
        case .place(let name, let lat, let lon, _): return DeepLink.place(name: name, lat: lat, lon: lon).url
        }
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", image: .init(systemName: symbol))
    }
}

struct ShortcutQuery: EntityStringQuery {
    func entities(for identifiers: [ShortcutEntity.ID]) async throws -> [ShortcutEntity] {
        identifiers.compactMap(ShortcutEntity.init(id:))
    }

    /// Home and Work, the app's own shortcuts (when readable here), then a place search.
    func entities(matching string: String) async throws -> [ShortcutEntity] {
        let text = string.trimmingCharacters(in: .whitespaces)
        let fixed = Self.fixed().filter { text.isEmpty || $0.title.localizedCaseInsensitiveContains(text) }
        guard text.count >= 2 else { return fixed }
        let found = (try? await TransitousClient.shared.geocode(text, near: nil)) ?? []
        return fixed + found.prefix(10).map { ShortcutEntity(name: $0.name, lat: $0.lat, lon: $0.lon, symbol: nil) }
    }

    func suggestedEntities() async throws -> [ShortcutEntity] { Self.fixed() }

    private struct Saved: Decodable {
        let name: String; let lat: Double; let lon: Double
        let role: String?; let shortcut: Bool?; let symbol: String?
    }

    /// Home, Work and the own shortcuts saved in the app (the widget extension cannot read them and
    /// offers Home, Work and the search).
    static func fixed(defaults: UserDefaults = .standard) -> [ShortcutEntity] {
        var list = PlaceRole.allCases.map(ShortcutEntity.init(role:))
        if let data = defaults.data(forKey: "publit.favorites.v1"),
           let items = try? JSONDecoder().decode([Saved].self, from: data) {
            list += items.filter { $0.shortcut == true && $0.role == nil }
                .map { ShortcutEntity(name: $0.name, lat: $0.lat, lon: $0.lon, symbol: $0.symbol ?? "star.fill") }
        }
        return list
    }
}

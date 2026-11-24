// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich

import Foundation

/// The pages of Settings (layout A, Nov 2026): the start page shows the community card and these
/// categories; each opens a short page with the sections it always had. The search finds every setting.
enum SettingsCategory: String, CaseIterable, Identifiable {
    case general, travel, map, stations, search, tickets, notifications, data, diagnostics, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return L10n.t("General")
        case .travel: return L10n.t("Travel preferences")
        case .map: return L10n.t("Map")
        case .stations: return L10n.t("Stations")
        case .search: return L10n.t("Search")
        case .tickets: return Features.tickets ? L10n.t("Tickets") : L10n.t("Apple Watch")
        case .notifications: return L10n.t("Notifications")
        case .data: return L10n.t("Data")
        case .diagnostics: return L10n.t("Diagnostics")
        case .about: return L10n.t("About")
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .travel: return "figure.walk.departure"
        case .map: return "map"
        case .stations: return "tram.fill"
        case .search: return "magnifyingglass"
        case .tickets: return Features.tickets ? "ticket" : "applewatch"
        case .notifications: return "bell"
        case .data: return "externaldrive"
        case .diagnostics: return "stethoscope"
        case .about: return "info.circle"
        }
    }

    /// Tickets and the watch only when either is in this build.
    var isShown: Bool { self != .tickets || Features.tickets || Features.passes }

    /// The settings on this page, by the words on screen (catalog keys), for the search.
    var settings: [String] {
        switch self {
        case .general: return ["Start screen", "Stop"]
        case .travel: return ["Started trips", "Get-off alert", "Route options", "Show connection timelines", "How to read connections",
                              "Smart routing", "Changes", "Calendar", "Appointments as destinations"]
        case .map: return ["Nearby", "Map provider", "Map style", "Points of interest", "Lines", "Vehicles", "Bikes and scooters",
                           "Open directions in"]
        case .stations: return ["Platform map", "Departures by platform", "Change guide"]
        case .search: return ["Place search", "Google API key"]
        case .tickets: return (Features.tickets ? ["My tickets", "Ticket apps per operator"] : [])
            + (Features.passes ? ["Tickets on Apple Watch"] : [])
        case .notifications: return ["Disruptions on saved lines"]
        case .data: return ["Live data from more operators", "Exit numbers from OpenStreetMap", "Live data sources", "Export my data"]
        case .diagnostics: return ["Share diagnostics", "Report a problem", "Delete diagnostics"]
        case .about: return ["Source code and feedback", "Privacy policy", "Version"]
        }
    }

    struct Hit: Equatable {
        let title: String
        let category: SettingsCategory
    }

    /// Settings whose name (or page name) contains the words typed, ignoring case and accents; one hit per name.
    static func search(_ query: String, translate: (String) -> String = L10n.t) -> [Hit] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }
        func matches(_ text: String) -> Bool {
            words.allSatisfy { text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
        var seen = Set<String>()
        var hits: [Hit] = []
        for c in allCases where c.isShown {
            for key in c.settings {
                let title = translate(key)
                if (matches(title) || matches(c.title)), seen.insert(title).inserted {
                    hits.append(Hit(title: title, category: c))
                }
            }
        }
        return hits
    }
}

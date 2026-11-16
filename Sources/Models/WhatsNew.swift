import Foundation

/// The short "What's new" note after an update. Each build that changes something for users adds one
/// entry here (see CLAUDE.md): at most three items, a few words each, translated in Localizable.xcstrings.
struct WhatsNewItem: Hashable, Sendable {
    let symbol: String
    /// Catalog keys (English source text).
    let title: String
    let text: String
}

struct WhatsNewEntry: Sendable {
    let build: Int
    let items: [WhatsNewItem]
}

enum WhatsNew {
    /// Last build whose note was shown (or skipped on a fresh install).
    static let seenKey = "whatsNewBuild"

    /// Newest first.
    static let entries: [WhatsNewEntry] = [
        WhatsNewEntry(build: 87, items: [
            WhatsNewItem(symbol: "arrow.triangle.swap", title: "Honest change chances",
                         text: "Changes get a percentage only where Publit has measured how late the vehicles really run; elsewhere it says Estimate."),
        ]),
        WhatsNewEntry(build: 86, items: [
            WhatsNewItem(symbol: "map", title: "The Nearby map everywhere",
                         text: "Trips, lines and stations show you with your direction, the stops by name and the location button."),
        ]),
        WhatsNewEntry(build: 85, items: [
            WhatsNewItem(symbol: "sparkles", title: "Your update, explained",
                         text: "Swipe through what's new and try each feature with one tap."),
        ]),
        WhatsNewEntry(build: 84, items: [
            WhatsNewItem(symbol: "car", title: "Park & Ride: more stations",
                         text: "Stations a few minutes further away, for example on another line, now compete too."),
        ]),
        WhatsNewEntry(build: 83, items: [
            WhatsNewItem(symbol: "bell.badge", title: "Get off on time",
                         text: "On a started trip Publit follows your ride and alerts you one stop before yours."),
            WhatsNewItem(symbol: "scope", title: "Track your vehicle",
                         text: "Follow a departure on the map and see where its position comes from."),
            WhatsNewItem(symbol: "figure.walk", title: "Easier on foot",
                         text: "Start walking navigation in one tap, or pick From and To right on the map."),
        ]),
        WhatsNewEntry(build: 82, items: [
            WhatsNewItem(symbol: "ticket", title: "Routes for your ticket",
                         text: "Choose Deutschlandticket, KlimaTicket, GA and more in Route options; routes stay within what they cover."),
            WhatsNewItem(symbol: "map", title: "Regional KlimaTickets",
                         text: "VOR, Vienna and each state's ticket only use rides in their region."),
        ]),
        WhatsNewEntry(build: 81, items: [
            WhatsNewItem(symbol: "arrow.triangle.swap", title: "Clearer changes",
                         text: "Each change shows times, platforms and your buffer in one glance."),
            WhatsNewItem(symbol: "person.3", title: "Community first",
                         text: "Wishes, voting and support are now at the top of Settings."),
            WhatsNewItem(symbol: "heart", title: "Support Publit",
                         text: "Monthly or once – every feature stays free for everyone."),
        ]),
    ]

    /// What to show when `current` starts after `seen`: the items of every newer build, newest first,
    /// at most `limit`. Empty on a fresh install (seen == nil is handled by the caller) or when nothing changed.
    static func items(seen: Int, current: Int, limit: Int = 4) -> [WhatsNewItem] {
        guard current > seen else { return [] }
        let newer = entries.filter { $0.build > seen && $0.build <= current }.sorted { $0.build > $1.build }
        return Array(newer.flatMap(\.items).prefix(limit))
    }
}

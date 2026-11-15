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

import Foundation

/// The interactive "What's new" after a bigger update: a short story of cards, each with a small
/// live demo of the feature and a way to try it (concept: Notion "Update-Screen – Konzept & Standard").
/// Builds without a story fall back to the plain note from `WhatsNew.entries`.
/// All texts are catalog keys (English source) and translated in Localizable.xcstrings.
struct ReleaseStory: Sendable, Identifiable {
    /// Who asked for a card: shown as its chip.
    enum Credit: String, Sendable, Hashable {
        /// Asked for by users (Reddit, the wish list, mail).
        case community
        /// Asked for by TestFlight testers.
        case testers
        /// New, without a recorded request.
        case new
    }

    /// The small live demo on a card. Sample names stay as they are; they are not translated.
    enum Demo: Sendable, Hashable {
        /// A query types itself, then the matching address appears on top.
        case typing(query: String, result: String, detail: String)
        /// Drag a handle between the old and the new layout.
        case beforeAfter
        /// Turn left or right; the beam on the map turns with you.
        case compass
        /// Tap a pass; rides it does not cover disappear from the list.
        case tickets
        /// A vehicle moves along the line and the alert comes one stop early.
        case getOff
        /// Place names change, the app stays the same.
        case places([String])
    }

    /// Where "Try it" leads.
    enum Target: String, Sendable, Hashable {
        case nearby, plan
    }

    struct Card: Sendable, Hashable, Identifiable {
        let id: String
        let symbol: String
        let credit: Credit
        let title: String
        let text: String
        let demo: Demo
        let target: Target?
    }

    let version: String
    /// The story belongs to the builds `firstBuild...lastBuild`.
    let firstBuild: Int
    let lastBuild: Int
    let headline: String
    let thanks: String
    /// Bugs fixed in these builds (the list below shows the ones people noticed most).
    let fixCount: Int
    let cards: [Card]
    let fixes: [String]

    var id: String { version }

    /// Cards that came from requests (chip "You asked" or "Testers asked").
    var requestedCount: Int { cards.filter { $0.credit != .new }.count }

    /// The story to show after updating from `seen` to `current`: the newest one with a build
    /// that was not seen yet. Nil on a downgrade, the same build, or when no story covers it.
    static func story(seen: Int, current: Int) -> ReleaseStory? {
        guard current > seen else { return nil }
        return all
            .filter { $0.lastBuild > seen && $0.firstBuild <= current }
            .max { $0.lastBuild < $1.lastBuild }
    }

    /// Newest first.
    static let all: [ReleaseStory] = [
        ReleaseStory(
            version: "0.1.1", firstBuild: 66, lastBuild: 85,
            headline: "Built by you.",
            thanks: "Almost everything in this update started as a message, a vote or a bug report. Thank you.",
            fixCount: 32,
            cards: [
                Card(id: "address", symbol: "magnifyingglass", credit: .community,
                     title: "Your address, found.",
                     text: "Street and house number, the way you'd tell a taxi driver.",
                     demo: .typing(query: "Mariahilfer Str 48", result: "Mariahilfer Straße 48", detail: "1070 Wien"),
                     target: .plan),
                Card(id: "search-button", symbol: "hand.tap", credit: .testers,
                     title: "Search where your thumb is.",
                     text: "One big button at the bottom, and routes in timetable order. Drag to compare.",
                     demo: .beforeAfter, target: .plan),
                Card(id: "nearby-map", symbol: "map", credit: .new,
                     title: "Nearby is a map.",
                     text: "Stations around you, and a beam that shows which way you're facing.",
                     demo: .compass, target: .nearby),
                Card(id: "tickets", symbol: "ticket", credit: .new,
                     title: "Routes for your ticket.",
                     text: "Tap a pass: Publit hides the rides it doesn't cover.",
                     demo: .tickets, target: .plan),
                Card(id: "get-off", symbol: "bell.badge", credit: .new,
                     title: "Get off on time.",
                     text: "Publit follows your ride and alerts you one stop before yours.",
                     demo: .getOff, target: nil),
                Card(id: "abroad", symbol: "globe.europe.africa", credit: .new,
                     title: "Same app abroad.",
                     text: "Wherever there's open timetable data, Publit works like at home. Where data is missing, it says so.",
                     demo: .places(["Wien", "Venezia", "Lyon", "Ljubljana", "Praha"]), target: .nearby),
            ],
            fixes: [
                "Home addresses with a house number are found.",
                "Setting Work no longer removes Home.",
                "Routes are in timetable order, the next day is marked.",
                "No walk to the stop you start at or are standing at.",
                "Austrian regional trains show their line, like \"R 44\".",
                "A busy server no longer empties the route list.",
                "Park & Ride no longer drives almost all the way.",
                "With a Deutschlandticket you get all regional routes.",
                "Countdowns are on time after the phone wakes up.",
                "Saved walks keep their path instead of a straight line.",
                "No second vehicle next to you on the live map.",
                "Swipe actions are readable in dark mode.",
            ]),
    ]
}

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
        WhatsNewEntry(build: 107, items: [
            WhatsNewItem(symbol: "arrow.triangle.turn.up.right.diamond", title: "Arrive by: only routes your way",
                         text: "With “Arrive by”, Plan no longer lists a route that runs from your destination back to your start."),
        ]),
        WhatsNewEntry(build: 106, items: [
            WhatsNewItem(symbol: "capsule.portrait", title: "Dynamic Island opens again",
                         text: "Hold the Dynamic Island during a trip to see the next step, your vehicle and when you arrive."),
        ]),
        WhatsNewEntry(build: 105, items: [
            WhatsNewItem(symbol: "figure.walk", title: "Faster way while you walk",
                         text: "On the walk to your stop, Publit shows another way that arrives earlier."),
            WhatsNewItem(symbol: "applewatch", title: "Readable on Apple Watch",
                         text: "Your trip on the Apple Watch now has light text on a dark card."),
        ]),
        WhatsNewEntry(build: 104, items: [
            WhatsNewItem(symbol: "door.left.hand.open", title: "Exit numbers more often",
                         text: "Routes and live trips now show the exit number of metro stations more often, also when the walk only passes near the exit."),
            WhatsNewItem(symbol: "ticket", title: "Deleted tickets stay deleted",
                         text: "A ticket you deleted no longer comes back after an update."),
        ]),
        WhatsNewEntry(build: 103, items: [
            WhatsNewItem(symbol: "map", title: "Station map opens again",
                         text: "Pull the list in Nearby far down and let go: the station map opens again, as it should."),
        ]),
        WhatsNewEntry(build: 102, items: [
            WhatsNewItem(symbol: "map", title: "Smoother station map",
                         text: "Pull the list in Nearby far down and let go: the station map opens right out of the map at the top."),
        ]),
        WhatsNewEntry(build: 101, items: [
            WhatsNewItem(symbol: "mappin.and.ellipse", title: "Change where you want",
                         text: "Open a ride in a route and choose another stop or any place to change; Publit plans the way on from there."),
        ]),
        WhatsNewEntry(build: 100, items: [
            WhatsNewItem(symbol: "square.grid.2x2", title: "Widgets and complications",
                         text: "Home, Work, your own shortcuts and departures near you, on the Home Screen and on the Apple Watch face."),
            WhatsNewItem(symbol: "star", title: "Save connections and lines",
                         text: "Save a connection or a line in one direction, and see right away when the next one leaves."),
            WhatsNewItem(symbol: "ticket", title: "Wallet passes and your own ticket",
                         text: "Add tickets from Wallet pass files, and plan your journey around a ticket you already have."),
        ]),
        WhatsNewEntry(build: 99, items: [
            WhatsNewItem(symbol: "arrow.up.arrow.down", title: "Sections in your order",
                         text: "In Plan in sections, hold a place and drag it to put your stops in another order."),
            WhatsNewItem(symbol: "percent", title: "Chances for every change",
                         text: "Routes show how likely each change works, also with smart routing turned off."),
            WhatsNewItem(symbol: "map", title: "All routes on one map",
                         text: "In Plan, the map button shows every route found on one map, so you can compare where they go."),
        ]),
        WhatsNewEntry(build: 98, items: [
            WhatsNewItem(symbol: "point.topleft.down.to.point.bottomright.curvepath", title: "Plan in sections",
                         text: "Add stops in between and choose for each section how you travel and which departure you take."),
            WhatsNewItem(symbol: "door.left.hand.open", title: "Your way out",
                         text: "For metro and train rides Publit says where to board and which exit to take; you can also pick your own exit."),
            WhatsNewItem(symbol: "moon.stars", title: "Last connection",
                         text: "In Plan, the new time option “Last” shows the latest connections that still get you there tonight."),
        ]),
        WhatsNewEntry(build: 97, items: [
            WhatsNewItem(symbol: "arrow.triangle.branch", title: "Go on another way",
                         text: "Open a ride in a route and choose another way to go on from there; the way up to it stays."),
            WhatsNewItem(symbol: "calendar.badge.clock", title: "Appointments as destinations",
                         text: "Turn on calendar suggestions and Publit offers routes to your next events that arrive a few minutes early."),
            WhatsNewItem(symbol: "train.side.rear.car", title: "Without long-distance trains",
                         text: "A new switch in Route options leaves out high-speed, intercity and night trains."),
        ]),
        WhatsNewEntry(build: 95, items: [
            WhatsNewItem(symbol: "location.fill", title: "Your position, as before",
                         text: "The blue dot shows the way you face with a soft beam again, on every map."),
            WhatsNewItem(symbol: "arrow.triangle.swap", title: "Changes up close",
                         text: "During a live trip, the change map opens right on the platforms where you get off and board."),
        ]),
        WhatsNewEntry(build: 94, items: [
            WhatsNewItem(symbol: "map", title: "Maps scroll along",
                         text: "The map at the top now moves up with the list, so nothing slides under it."),
            WhatsNewItem(symbol: "person.3.fill", title: "Community, rearranged",
                         text: "In Settings, voting and supporting Publit sit side by side and are easier to find."),
        ]),
        WhatsNewEntry(build: 91, items: [
            WhatsNewItem(symbol: "map", title: "Maps from edge to edge",
                         text: "Nearby, routes, trips and lines show their map across the whole top again, and you can still move and zoom it right there."),
            WhatsNewItem(symbol: "mappin", title: "A better pin on the map",
                         text: "Choose on map has a new pin that lifts while you move the map, and double-tap to zoom works."),
        ]),
        WhatsNewEntry(build: 90, items: [
            WhatsNewItem(symbol: "hand.draw", title: "Maps you can move",
                         text: "Move and zoom the maps at the top of Nearby, routes and departures right where they are, and tap a station on Nearby to see its departures."),
            WhatsNewItem(symbol: "figure.walk", title: "Walking navigation fixed",
                         text: "Starting a walk now opens the route you just planned, not an old one."),
        ]),
        WhatsNewEntry(build: 89, items: [
            WhatsNewItem(symbol: "arrow.triangle.swap", title: "Honest change chances",
                         text: "Changes get a percentage only where Publit has measured how late the vehicles really run; elsewhere it says Estimate."),
            WhatsNewItem(symbol: "bell.badge", title: "Warned before a change breaks",
                         text: "On a started trip Publit rechecks each change with live times and warns you, with alternatives, when it becomes unlikely."),
            WhatsNewItem(symbol: "figure.walk", title: "Learns how you change",
                         text: "Turn on Learn from my trips and Publit learns how long your changes take, on your iPhone only."),
        ]),
        WhatsNewEntry(build: 87, items: [
            WhatsNewItem(symbol: "location.north.line", title: "Clearer live trips",
                         text: "Each stage starts at its own place on the map; the whole trip is one tap away under Trip overview."),
            WhatsNewItem(symbol: "list.bullet.rectangle", title: "Calmer route list",
                         text: "Every route shows its times, its lines, one line of facts and only the note that matters."),
            WhatsNewItem(symbol: "star", title: "Saved trips at a glance",
                         text: "Saved trips show their lines like in Plan and open on the route details."),
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

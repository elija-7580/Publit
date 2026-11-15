import Foundation

/// Supporting Publit with money: monthly support first (the steady income that keeps servers
/// running), one-time tips below. Nothing is unlocked: every feature stays free for everyone.
///
/// The same product IDs are used on Android (Google Play Billing). Prices are set per store
/// (App Store Connect / Play Console); the app only shows the store's localized price.
enum Support {
    static let prefix = "io.github.elija7580.publit.support"
    /// Monthly support in euro cents, cheapest first: 1.50, 3, 5, 10, 20, 50 €.
    static let monthlyCents = [150, 300, 500, 1000, 2000, 5000]
    /// One-time tips in euro cents.
    static let oneTimeCents = [300, 500, 1000, 2000, 5000]
    /// The amount marked as a good start in the list.
    static let suggestedMonthlyCents = 300

    static func monthlyID(_ cents: Int) -> String { "\(prefix).monthly.\(cents)" }
    static func oneTimeID(_ cents: Int) -> String { "\(prefix).tip.\(cents)" }

    static var monthlyIDs: [String] { monthlyCents.map(monthlyID) }
    static var oneTimeIDs: [String] { oneTimeCents.map(oneTimeID) }
    static var allIDs: [String] { monthlyIDs + oneTimeIDs }

    enum Kind: Equatable { case monthly, oneTime }

    /// Kind and amount (cents) of a product ID; nil for anything else.
    static func parse(_ id: String) -> (kind: Kind, cents: Int)? {
        guard id.hasPrefix(prefix + ".") else { return nil }
        let parts = id.dropFirst(prefix.count + 1).split(separator: ".")
        guard parts.count == 2, let cents = Int(parts[1]) else { return nil }
        switch parts[0] {
        case "monthly" where monthlyCents.contains(cents): return (.monthly, cents)
        case "tip" where oneTimeCents.contains(cents): return (.oneTime, cents)
        default: return nil
        }
    }

    /// Store products in the order of the amounts above, whatever order the store returns.
    static func sorted<T>(_ items: [T], id: (T) -> String, kind: Kind) -> [T] {
        items.compactMap { item -> (T, Int)? in
            guard let p = parse(id(item)), p.kind == kind else { return nil }
            return (item, p.cents)
        }.sorted { $0.1 < $1.1 }.map(\.0)
    }
}

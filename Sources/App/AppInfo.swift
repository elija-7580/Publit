import Foundation

/// Features that are built but not shipped yet.
enum Features {
    /// Stored tickets, ticket apps and "Buy ticket" links. Off until the ticket screen is redesigned.
    static let tickets = false
}

enum AppInfo {
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }

    /// Contact required by the Transitous usage policy. Set `PublitContact` in project.yml.
    static var contact: String {
        Bundle.main.infoDictionary?["PublitContact"] as? String ?? "https://github.com"
    }

    static var userAgent: String { "Publit/\(version) (iOS; +\(contact))" }

    static var repositoryURL: URL { URL(string: contact) ?? URL(string: "https://github.com")! }
    static let sourcesURL = URL(string: "https://transitous.org/sources/")!
    static let osmCopyrightURL = URL(string: "https://www.openstreetmap.org/copyright")!
}

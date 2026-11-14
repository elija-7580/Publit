import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One feature request on publit.eu/wuensche.
struct Wish: Decodable, Identifiable, Hashable, Sendable {
    enum Status: String, Decodable, Sendable {
        case open, planned, doing, done
    }

    let id: Int
    let title: String
    let body: String
    let status: Status
    let created: Date
    var votes: Int
    var mine: Bool

    private enum CodingKeys: String, CodingKey { case id, title, body, status, created, votes, mine }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        status = (try? c.decode(Status.self, forKey: .status)) ?? .open
        created = Date(timeIntervalSince1970: try c.decodeIfPresent(Double.self, forKey: .created) ?? 0)
        votes = try c.decodeIfPresent(Int.self, forKey: .votes) ?? 0
        mine = try c.decodeIfPresent(Bool.self, forKey: .mine) ?? false
    }

    init(id: Int, title: String, body: String = "", status: Status = .open, created: Date = Date(), votes: Int = 0, mine: Bool = false) {
        self.id = id; self.title = title; self.body = body; self.status = status
        self.created = created; self.votes = votes; self.mine = mine
    }
}

/// The wish list on publit.eu: read, vote, suggest. No account: a random voter ID kept on this
/// device marks your votes (the same scheme as the web page). The server stores no addresses.
struct WishesClient: Sendable {
    enum Sort: String, CaseIterable, Sendable { case top, new }

    enum Failure: Error, Equatable {
        /// Title shorter than 6 characters.
        case tooShort
        /// More than two links, or a link in the title.
        case links
        /// A wish with this title already exists.
        case exists
        /// Too many requests from this network; try later.
        case slowDown
        /// Server not reachable or an unexpected answer.
        case unavailable
    }

    static let pageURL = URL(string: "https://publit.eu/wuensche/")!
    static let minTitle = 6
    static let voterKey = "publit.wishes.voter"

    var base = URL(string: "https://publit.eu/api/wishes")!
    var session: URLSession = .shared
    var voter: String

    init(voter: String = WishesClient.storedVoter()) { self.voter = voter }

    /// A random 24-character ID (base64url), made once and kept in the app's settings.
    static func storedVoter(_ defaults: UserDefaults = .standard) -> String {
        if let v = defaults.string(forKey: voterKey), isValidVoter(v) { return v }
        let v = newVoter()
        defaults.set(v, forKey: voterKey)
        return v
    }

    static func newVoter() -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        var g = SystemRandomNumberGenerator()
        return String((0..<24).map { _ in alphabet[Int(g.next(upperBound: UInt64(alphabet.count)))] })
    }

    static func isValidVoter(_ v: String) -> Bool {
        (16...64).contains(v.count) && v.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    /// The server keeps German and English wishes; everything else is filed as English.
    static func language(_ preferred: [String] = Locale.preferredLanguages) -> String {
        (preferred.first ?? "en").lowercased().hasPrefix("de") ? "de" : "en"
    }

    func list(sort: Sort) async throws -> [Wish] {
        var c = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        c.queryItems = [URLQueryItem(name: "sort", value: sort.rawValue), URLQueryItem(name: "voter", value: voter)]
        let (data, status) = try await send(URLRequest(url: c.url!, timeoutInterval: 15))
        guard status == 200 else { throw Failure.unavailable }
        struct Response: Decodable { let wishes: [Wish] }
        do { return try JSONDecoder().decode(Response.self, from: data).wishes } catch { throw Failure.unavailable }
    }

    /// Votes, or takes the vote back when you already voted. Returns the new count and whether it is yours.
    func toggleVote(_ id: Int) async throws -> (votes: Int, mine: Bool) {
        let (data, status) = try await post(base.appendingPathComponent("\(id)").appendingPathComponent("vote"), ["voter": voter])
        guard status == 200 else { throw Self.failure(status, data) }
        struct Response: Decodable { let votes: Int; let mine: Bool }
        guard let r = try? JSONDecoder().decode(Response.self, from: data) else { throw Failure.unavailable }
        return (r.votes, r.mine)
    }

    /// Suggests a wish; it starts with your own vote.
    func suggest(title: String, body: String) async throws {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= Self.minTitle else { throw Failure.tooShort }
        let (data, status) = try await post(base, [
            "title": t, "body": body.trimmingCharacters(in: .whitespacesAndNewlines),
            "lang": Self.language(), "voter": voter, "website": "",
        ])
        guard status == 201 || status == 200 else { throw Self.failure(status, data) }
    }

    static func failure(_ status: Int, _ data: Data) -> Failure {
        let error = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
        switch status {
        case 409: return .exists
        case 429: return .slowDown
        case 422: return error == "links" ? .links : .tooShort
        default: return .unavailable
        }
    }

    private func post(_ url: URL, _ body: [String: String]) async throws -> (Data, Int) {
        var r = URLRequest(url: url, timeoutInterval: 15)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(r)
    }

    private func send(_ request: URLRequest) async throws -> (Data, Int) {
        var r = request
        r.setValue(AppInfo.userAgent, forHTTPHeaderField: "User-Agent")
        r.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await session.data(for: r)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        } catch {
            throw Failure.unavailable
        }
    }
}

import Foundation

// What the iPhone and the Apple Watch send each other. Pure data and rules; the transport
// (WatchConnectivity) lives in Sources/WatchSync (iPhone) and Watch/WatchLibrary.swift (watch).
//
// iPhone -> watch: one `WatchSnapshot` (saved trips, saved stops and places, tickets) and a picture per ticket code.
// watch -> iPhone: `WatchIntent`s (saved a trip, started a trip …); the iPhone answers with a new snapshot that lists
// the processed intents in `acks`. Until then the watch shows the change itself (`WatchState.snapshot`).

/// A ticket on the watch: the pass without its documents, and the file name of the picture of its code.
struct WatchTicket: Codable, Hashable, Identifiable, Sendable {
    var pass: TicketPass
    /// PNG the iPhone drew for the watch (see `WatchCodeFile`). Nil: no code that can be drawn.
    var code: String?
    var id: String { pass.id }
}

enum WatchTickets {
    /// The watch carries up to this many tickets.
    static let limit = 12

    /// Not archived, valid now first, then upcoming, without dates, expired (the order of the list on the iPhone).
    static func shared(from passes: [TicketPass], at now: Date) -> [TicketPass] {
        Array(PassGroup.grouped(passes, at: now).flatMap { $0.passes }.prefix(limit))
    }

    /// The tickets a trip offers (same rule as on the iPhone), from the ones on the watch.
    static func forTrip(_ tripId: String?, in tickets: [WatchTicket], at date: Date) -> [WatchTicket] {
        let byId = Dictionary(tickets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return TicketPass.offered(tickets.map(\.pass), forTrip: tripId, at: date).compactMap { byId[$0.id] }
    }

    /// The tickets worth showing first: valid now (a pass for a month, a ticket for today).
    static func validNow(_ tickets: [WatchTicket], at date: Date) -> [WatchTicket] {
        tickets.filter { if case .valid = $0.pass.validity(at: date) { return true } else { return false } }
    }
}

/// File names of the code pictures. The name holds the time the ticket was last changed and the
/// size, so a changed ticket or another watch gets a new file and nothing old is shown.
enum WatchCodeFile {
    static let defaultPixels = 352
    static let pixelRange = 200...560

    static func clamped(_ pixels: Int?) -> Int {
        guard let pixels else { return defaultPixels }
        return min(max(pixels, pixelRange.lowerBound), pixelRange.upperBound)
    }

    static func name(passId: String, updatedAt: Date, pixels: Int) -> String {
        let safe = String(passId.unicodeScalars.map { s -> Character in
            (s.isASCII && (CharacterSet.alphanumerics.contains(s) || s == "-")) ? Character(s) : "_"
        })
        return "\(safe)-\(Int(updatedAt.timeIntervalSince1970))-\(clamped(pixels)).png"
    }
}

/// A request from the watch to the iPhone.
struct WatchIntent: Codable, Hashable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case saveTrip, removeTrip, startTrip, stopTrip, savePlace, removePlace
        /// Ask for a new snapshot. Carries the screen width in pixels, so the codes are drawn to fit.
        case resend
    }

    var id: String
    var kind: Kind
    var createdAt: Date
    var trip: SavedTrip?
    var tripId: String?
    var place: SavedPlace?
    var placeId: String?
    var screen: Int?

    init(id: String = UUID().uuidString, kind: Kind, createdAt: Date = .now, trip: SavedTrip? = nil, tripId: String? = nil,
         place: SavedPlace? = nil, placeId: String? = nil, screen: Int? = nil) {
        self.id = id; self.kind = kind; self.createdAt = createdAt
        self.trip = trip; self.tripId = tripId; self.place = place; self.placeId = placeId; self.screen = screen
    }

    static func saveTrip(_ trip: SavedTrip, now: Date = .now) -> WatchIntent { WatchIntent(kind: .saveTrip, createdAt: now, trip: trip) }
    static func removeTrip(_ id: String, now: Date = .now) -> WatchIntent { WatchIntent(kind: .removeTrip, createdAt: now, tripId: id) }
    static func startTrip(_ id: String, now: Date = .now) -> WatchIntent { WatchIntent(kind: .startTrip, createdAt: now, tripId: id) }
    static func stopTrip(_ id: String, now: Date = .now) -> WatchIntent { WatchIntent(kind: .stopTrip, createdAt: now, tripId: id) }
    static func savePlace(_ place: SavedPlace, now: Date = .now) -> WatchIntent { WatchIntent(kind: .savePlace, createdAt: now, place: place) }
    static func removePlace(_ id: String, now: Date = .now) -> WatchIntent { WatchIntent(kind: .removePlace, createdAt: now, placeId: id) }
    static func resend(screen: Int?, now: Date = .now) -> WatchIntent { WatchIntent(kind: .resend, createdAt: now, screen: screen) }
}

/// Everything the watch shows that comes from the iPhone.
struct WatchSnapshot: Codable, Sendable {
    static let currentVersion = 1
    /// Trips the watch carries: the one started by hand and the next ones, at most.
    static let tripLimit = 8
    /// The same lead time as the live bar on the iPhone (`TripStore.liveLead`).
    static let liveLead: TimeInterval = 30 * 60

    var version: Int = WatchSnapshot.currentVersion
    var sentAt: Date
    var trips: [SavedTrip] = []
    var activeTripId: String?
    var places: [SavedPlace] = []
    var tickets: [WatchTicket] = []
    /// The iPhone's setting "Tickets on Apple Watch". Off: no ticket leaves the iPhone.
    var ticketsOn: Bool = true
    /// Requests of the watch the iPhone has processed.
    var acks: [String] = []

    static let empty = WatchSnapshot(sentAt: .distantPast)

    init(sentAt: Date, trips: [SavedTrip] = [], activeTripId: String? = nil, places: [SavedPlace] = [],
         tickets: [WatchTicket] = [], ticketsOn: Bool = true, acks: [String] = []) {
        self.sentAt = sentAt; self.trips = trips; self.activeTripId = activeTripId; self.places = places
        self.tickets = tickets; self.ticketsOn = ticketsOn; self.acks = acks
    }

    private enum CodingKeys: String, CodingKey { case version, sentAt, trips, activeTripId, places, tickets, ticketsOn, acks }

    /// Tolerant: an older or newer app version may leave fields out.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        sentAt = try c.decode(Date.self, forKey: .sentAt)
        trips = try c.decodeIfPresent([SavedTrip].self, forKey: .trips) ?? []
        activeTripId = try c.decodeIfPresent(String.self, forKey: .activeTripId)
        places = try c.decodeIfPresent([SavedPlace].self, forKey: .places) ?? []
        tickets = try c.decodeIfPresent([WatchTicket].self, forKey: .tickets) ?? []
        ticketsOn = try c.decodeIfPresent(Bool.self, forKey: .ticketsOn) ?? true
        acks = try c.decodeIfPresent([String].self, forKey: .acks) ?? []
    }

    /// The snapshot the iPhone sends.
    /// - Parameter codes: file name of the code picture per pass ID.
    static func make(now: Date, trips: [SavedTrip], activeTripId: String?, places: [SavedPlace], passes: [TicketPass],
                     ticketsOn: Bool, codes: [String: String] = [:], acks: [String] = []) -> WatchSnapshot {
        let chosen = chooseTrips(trips, active: activeTripId, now: now)
        let active = chosen.contains { $0.id == activeTripId } ? activeTripId : nil
        let tickets = ticketsOn
            ? WatchTickets.shared(from: passes, at: now).map { WatchTicket(pass: $0.forWatch(), code: codes[$0.id]) }
            : []
        return WatchSnapshot(sentAt: now, trips: chosen.map { $0.forWatch() }, activeTripId: active, places: places,
                             tickets: tickets, ticketsOn: ticketsOn, acks: Array(acks.suffix(50)))
    }

    /// The started trip, and the ones that are not over more than six hours ago, soonest first. At most `tripLimit`.
    static func chooseTrips(_ trips: [SavedTrip], active: String?, now: Date) -> [SavedTrip] {
        let startedTrip = trips.first { $0.id == active }
        let others = trips
            .filter { $0.id != active && $0.endTime >= now.addingTimeInterval(-6 * 3600) }
            .sorted { $0.startTime < $1.startTime }
            .prefix(max(0, tripLimit - (startedTrip == nil ? 0 : 1)))
        return (others + (startedTrip.map { [$0] } ?? [])).sorted { $0.startTime < $1.startTime }
    }

    // MARK: Reading

    func trip(_ id: String) -> SavedTrip? { trips.first { $0.id == id } }

    /// The saved trip for a route shown in a list of results.
    func trip(for itinerary: Itinerary) -> SavedTrip? {
        let key = itinerary.routeKey
        return trips.first { $0.itinerary.id == itinerary.id || $0.itinerary.routeKey == key }
    }

    func ticket(_ id: String) -> WatchTicket? { tickets.first { $0.id == id } }

    var activeTrip: SavedTrip? {
        guard let id = activeTripId, let trip = trip(id) else { return nil }
        return trip
    }

    /// The trip for the first tile: the one started by hand, otherwise a saved trip that is under way or leaves
    /// within half an hour. Up to five minutes after arrival it still shows "Arrived". Same rule as the live bar.
    func current(now: Date) -> SavedTrip? {
        if let t = activeTrip, t.endTime.addingTimeInterval(5 * 60) >= now, t.startTime.addingTimeInterval(-3 * 3600) <= now { return t }
        return trips
            .filter { $0.startTime.addingTimeInterval(-Self.liveLead) <= now && $0.endTime.addingTimeInterval(5 * 60) >= now }
            .min { $0.startTime < $1.startTime }
    }

    /// Not yet arrived, soonest first.
    func upcoming(now: Date) -> [SavedTrip] { trips.filter { $0.endTime >= now }.sorted { $0.startTime < $1.startTime } }

    /// Already arrived, most recent first.
    func past(now: Date) -> [SavedTrip] { trips.filter { $0.endTime < now }.sorted { $0.startTime > $1.startTime } }

    var stops: [SavedPlace] { places.filter { $0.isStop && $0.role == nil } }
    var otherPlaces: [SavedPlace] { places.filter { !$0.isStop && $0.role == nil } }
    var pinned: [SavedPlace] { PlaceRole.allCases.compactMap { role in places.first { $0.role == role } } }

    // MARK: Changes made on the watch

    /// The snapshot with requests the iPhone has not confirmed yet, so the watch answers at once.
    func applying(_ intents: [WatchIntent]) -> WatchSnapshot {
        var s = self
        for intent in intents {
            switch intent.kind {
            case .saveTrip:
                if let t = intent.trip, !s.trips.contains(where: { $0.id == t.id || $0.itinerary.routeKey == t.itinerary.routeKey }) {
                    s.trips.append(t)
                }
            case .removeTrip:
                if let id = intent.tripId {
                    s.trips.removeAll { $0.id == id }
                    if s.activeTripId == id { s.activeTripId = nil }
                }
            case .startTrip:
                if let id = intent.tripId, s.trips.contains(where: { $0.id == id }) { s.activeTripId = id }
            case .stopTrip:
                if let id = intent.tripId, s.activeTripId == id { s.activeTripId = nil }
            case .savePlace:
                if let p = intent.place, !s.places.contains(where: { $0.isSame(as: p) }) { s.places.append(p) }
            case .removePlace:
                if let id = intent.placeId { s.places.removeAll { $0.id == id } }
            case .resend:
                break
            }
        }
        return s
    }
}

/// What the watch keeps: the last snapshot from the iPhone and the requests the iPhone has not confirmed yet.
struct WatchState: Codable, Sendable {
    /// Requests that were never confirmed are dropped after this long.
    static let pendingLifetime: TimeInterval = 14 * 24 * 3600
    static let pendingLimit = 50

    var received: WatchSnapshot = .empty
    var pending: [WatchIntent] = []

    init(received: WatchSnapshot = .empty, pending: [WatchIntent] = []) {
        self.received = received; self.pending = pending
    }

    /// What the watch shows.
    var snapshot: WatchSnapshot { received.applying(pending) }

    /// Waiting for the first snapshot.
    var isEmpty: Bool { received.sentAt == .distantPast }

    mutating func add(_ intent: WatchIntent, now: Date = .now) {
        pending.append(intent)
        pending.removeAll { now.timeIntervalSince($0.createdAt) > Self.pendingLifetime }
        if pending.count > Self.pendingLimit { pending.removeFirst(pending.count - Self.pendingLimit) }
    }

    /// A newer snapshot arrived. Returns false for an older one (transfers can arrive out of order).
    /// A trip the watch refreshed after the iPhone did keeps the watch's newer times.
    @discardableResult
    mutating func receive(_ new: WatchSnapshot) -> Bool {
        guard new.sentAt >= received.sentAt else { return false }
        var merged = new
        for i in merged.trips.indices {
            let theirs = merged.trips[i]
            guard let mine = received.trips.first(where: { $0.id == theirs.id }), let mineAt = mine.refreshedAt,
                  mineAt > (theirs.refreshedAt ?? theirs.savedAt),
                  mine.itinerary.routeKey == theirs.itinerary.routeKey else { continue }
            merged.trips[i].itinerary = mine.itinerary
            merged.trips[i].refreshedAt = mineAt
        }
        let done = Set(new.acks)
        pending.removeAll { done.contains($0.id) }
        received = merged
        return true
    }

    /// The watch loaded fresh times for a trip.
    mutating func update(tripId: String, itinerary: Itinerary, at date: Date) {
        let slim = itinerary.forWatch()
        if let i = received.trips.firstIndex(where: { $0.id == tripId }) {
            received.trips[i].itinerary = slim
            received.trips[i].refreshedAt = date
        }
        for j in pending.indices where pending[j].kind == .saveTrip && pending[j].trip?.id == tripId {
            pending[j].trip?.itinerary = slim
            pending[j].trip?.refreshedAt = date
        }
    }

    /// Code pictures the state refers to (for cleaning up the others).
    var codeFiles: Set<String> { Set(received.tickets.compactMap(\.code)) }
}

/// When the iPhone sends a new snapshot: at once after a change of what the watch lists, and a refreshed
/// time at most every 90 seconds (the watch loads times itself, too).
enum WatchSyncPolicy {
    static let minInterval: TimeInterval = 90

    enum Decision: Equatable, Sendable {
        case send
        case wait(TimeInterval)
        case skip
    }

    /// Changes whenever something is added, removed or switched.
    static func structure(_ s: WatchSnapshot) -> String {
        var parts: [String] = ["v\(s.version)", s.ticketsOn ? "t1" : "t0", "a:\(s.activeTripId ?? "-")"]
        parts += s.trips.map { "T:\($0.id):\($0.itinerary.routeKey):\($0.followLive == true ? 1 : 0)" }
        parts += s.places.map { "P:\($0.id):\($0.role?.rawValue ?? "-")" }
        parts += s.tickets.map { "K:\($0.id):\(Int($0.pass.updatedAt.timeIntervalSince1970)):\($0.code ?? "-")" }
        return parts.joined(separator: "\n")
    }

    /// Changes also when only times were refreshed.
    static func content(_ s: WatchSnapshot) -> String {
        structure(s) + "\n" + s.trips.map { "\($0.id)=\(Int(($0.refreshedAt ?? $0.savedAt).timeIntervalSince1970))" }.joined(separator: ",")
    }

    static func decide(last: (structure: String, content: String, sentAt: Date)?, new: WatchSnapshot, now: Date) -> Decision {
        guard let last else { return .send }
        if structure(new) != last.structure { return .send }
        if content(new) == last.content { return .skip }
        let wait = minInterval - now.timeIntervalSince(last.sentAt)
        return wait <= 0 ? .send : .wait(wait)
    }
}

/// How the files travel (WatchConnectivity `transferFile` metadata).
enum WatchTransfer {
    static let kindKey = "kind"
    static let nameKey = "name"
    static let snapshotKind = "snapshot"
    static let codeKind = "code"
    static let intentKind = "intent"
}

enum WatchCodec {
    static func encode(_ snapshot: WatchSnapshot) throws -> Data { try JSONFile<WatchSnapshot>.encoder.encode(snapshot) }
    static func encode(_ intent: WatchIntent) throws -> Data { try JSONFile<WatchIntent>.encoder.encode(intent) }
    static func encode(_ state: WatchState) throws -> Data { try JSONFile<WatchState>.encoder.encode(state) }

    static func snapshot(from data: Data) throws -> WatchSnapshot { try TransitousClient.makeDecoder().decode(WatchSnapshot.self, from: data) }
    static func intent(from data: Data) throws -> WatchIntent { try TransitousClient.makeDecoder().decode(WatchIntent.self, from: data) }
    static func state(from data: Data) throws -> WatchState { try TransitousClient.makeDecoder().decode(WatchState.self, from: data) }
}

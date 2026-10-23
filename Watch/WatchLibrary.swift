import Foundation
import Observation
import WatchConnectivity
import WatchKit

/// What the watch holds of the iPhone: saved trips, saved stops and places, and the tickets with a
/// picture of each code. It arrives over WatchConnectivity (the two devices only, no server) and is kept
/// on the watch, so everything works without the iPhone nearby. What the user changes on the watch
/// (save a trip, start it, save a place) shows at once and is sent to the iPhone as a request;
/// the request stays until the iPhone confirms it.
@MainActor
@Observable
final class WatchLibrary: NSObject, WCSessionDelegate {
    private(set) var state = WatchState()
    /// Counts the pictures that arrived, so a ticket still waiting for its code draws it as soon as it is there.
    private(set) var codeVersion = 0

    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let persistent: Bool
    @ObservationIgnored private var session: WCSession?
    @ObservationIgnored private var sentRequests: Set<String> = []
    @ObservationIgnored private var checkingCodes = false
    @ObservationIgnored private var askedForCodes = false
    @ObservationIgnored private let writer = DispatchQueue(label: "eu.publit.watch.library", qos: .utility)

    static let screenKey = "publit.watch.screenSent"

    /// The watch app with its real data: the saved copy, and the connection to the iPhone.
    override init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        directory = base.appendingPathComponent("Publit", isDirectory: true)
        persistent = true
        super.init()
        try? FileManager.default.createDirectory(at: codesDirectory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: stateURL), let saved = try? WatchCodec.state(from: data) { state = saved }
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        s.delegate = self
        s.activate()
        session = s
    }

    /// A made-up state for screenshots and tests: nothing is saved, nothing is sent.
    init(demo: WatchState, codes: [String: Data] = [:]) {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("publit-watch-demo", isDirectory: true)
        persistent = false
        super.init()
        try? FileManager.default.createDirectory(at: codesDirectory, withIntermediateDirectories: true)
        for (name, data) in codes { try? data.write(to: codesDirectory.appendingPathComponent(name), options: .atomic) }
        state = demo
    }

    // MARK: What the watch shows

    var snapshot: WatchSnapshot { state.snapshot }

    /// When the iPhone last sent something; nil before the first time.
    var lastSync: Date? { state.isEmpty ? nil : state.received.sentAt }

    private var stateURL: URL { directory.appendingPathComponent("watch-state.json") }
    private var codesDirectory: URL { directory.appendingPathComponent("watch-codes", isDirectory: true) }
    private var outbox: URL { directory.appendingPathComponent("watch-outbox", isDirectory: true) }

    /// The picture of a ticket's code, when it has arrived.
    func codeURL(for ticket: WatchTicket) -> URL? {
        guard let name = ticket.code, Self.isSafe(name) else { return nil }
        let url = codesDirectory.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// File names come from the iPhone: nothing that leaves the folder.
    nonisolated static func isSafe(_ name: String) -> Bool {
        !name.isEmpty && name.count < 200 && name.hasSuffix(".png") && !name.contains("/") && !name.contains("..")
    }

    // MARK: Requests to the iPhone

    func perform(_ intent: WatchIntent) {
        state.add(intent)
        persist()
        send(intent)
    }

    /// Saves a route found on the watch as a trip (the iPhone keeps it too).
    @discardableResult
    func save(_ itinerary: Itinerary, from: String, to: String, now: Date = .now) -> SavedTrip {
        if let same = snapshot.trip(for: itinerary) { return same }
        let trip = SavedTrip(id: UUID().uuidString, itinerary: itinerary.forWatch(), fromName: from, toName: to, savedAt: now)
        perform(.saveTrip(trip, now: now))
        return trip
    }

    func remove(trip id: String) { perform(.removeTrip(id)) }
    func start(trip id: String) { perform(.startTrip(id)) }
    func stop(trip id: String) { perform(.stopTrip(id)) }

    func isSaved(_ place: SavedPlace) -> Bool { snapshot.places.contains { $0.isSame(as: place) } }

    func save(place: SavedPlace) {
        guard !isSaved(place) else { return }
        perform(.savePlace(place))
    }

    func remove(place: SavedPlace) {
        for saved in snapshot.places where saved.isSame(as: place) { perform(.removePlace(saved.id)) }
    }

    /// Fresh times for a saved trip, straight from Transitous.
    func refresh(trip id: String) async {
        guard let trip = snapshot.trip(id),
              let fresh = try? await TripRefreshCoordinator.shared.refresh(trip.itinerary.id) else { return }
        state.update(tripId: id, itinerary: fresh, at: .now)
        persist()
    }

    private func send(_ intent: WatchIntent) {
        guard let session, session.activationState == .activated, !sentRequests.contains(intent.id),
              let data = try? WatchCodec.encode(intent) else { return }
        try? FileManager.default.createDirectory(at: outbox, withIntermediateDirectories: true)
        let file = outbox.appendingPathComponent("request-\(intent.id).json")
        guard (try? data.write(to: file, options: .atomic)) != nil else { return }
        session.transferFile(file, metadata: [WatchTransfer.kindKey: WatchTransfer.intentKind])
        sentRequests.insert(intent.id)
    }

    private func sendPending() {
        for intent in state.pending { send(intent) }
    }

    // MARK: Connection

    /// Pixels the code pictures may use: the screen without its margins. The iPhone draws them to this size,
    /// so a module is a whole number of pixels on the watch.
    static var screenPixels: Int {
        let device = WKInterfaceDevice.current()
        return Int((device.screenBounds.width - 24) * device.screenScale)
    }

    private func activated() {
        sendPending()
        let pixels = Self.screenPixels
        // Everything is sent once for a new watch, and again when the screen size is not the one the iPhone knows.
        if state.isEmpty || UserDefaults.standard.integer(forKey: Self.screenKey) != pixels {
            UserDefaults.standard.set(pixels, forKey: Self.screenKey)
            perform(.resend(screen: pixels))
        }
        checkCodes()
    }

    private func received(kind: String?, name: String?, data: Data) {
        switch kind {
        case WatchTransfer.snapshotKind:
            guard let snapshot = try? WatchCodec.snapshot(from: data) else { return }
            if state.receive(snapshot) {
                persist()
                purgeCodes()
                checkCodes()
            }
        case WatchTransfer.codeKind:
            guard let name, Self.isSafe(name) else { return }
            try? FileManager.default.createDirectory(at: codesDirectory, withIntermediateDirectories: true)
            let url = codesDirectory.appendingPathComponent(name)
            if (try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])) != nil {
                codeVersion += 1
            }
        default:
            break
        }
    }

    /// A ticket whose picture is still missing a minute after the list arrived: ask the iPhone once more.
    private func checkCodes() {
        guard !checkingCodes, !askedForCodes, hasMissingCodes else { return }
        checkingCodes = true
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard let self else { return }
            self.checkingCodes = false
            if self.hasMissingCodes {
                self.askedForCodes = true
                self.perform(.resend(screen: Self.screenPixels))
            }
        }
    }

    private var hasMissingCodes: Bool {
        guard state.received.ticketsOn else { return false }
        return state.received.tickets.contains { $0.code != nil && codeURL(for: $0) == nil }
    }

    /// Pictures of tickets that are gone. A picture that arrived a moment before its list stays.
    private func purgeCodes() {
        guard persistent else { return }
        let keep = state.codeFiles
        let directory = codesDirectory
        writer.async {
            let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            for file in files where !keep.contains(file.lastPathComponent) {
                let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                if Date().timeIntervalSince(modified) > 600 { try? FileManager.default.removeItem(at: file) }
            }
        }
    }

    private func persist() {
        guard persistent, let data = try? WatchCodec.encode(state) else { return }
        let url = stateURL
        let directory = directory
        writer.async {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    // MARK: WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        Task { @MainActor in self.activated() }
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // The file is deleted when this method returns: read it now.
        guard let data = try? Data(contentsOf: file.fileURL) else { return }
        let kind = file.metadata?[WatchTransfer.kindKey] as? String
        let name = file.metadata?[WatchTransfer.nameKey] as? String
        Task { @MainActor in self.received(kind: kind, name: name, data: data) }
    }

    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        let url = fileTransfer.file.fileURL
        if url.deletingLastPathComponent().lastPathComponent == "watch-outbox" { try? FileManager.default.removeItem(at: url) }
    }
}

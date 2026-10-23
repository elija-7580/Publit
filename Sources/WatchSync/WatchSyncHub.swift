import Foundation
import Observation
import WatchConnectivity

/// Settings of the watch connection (a plain enum: Settings reads them outside the main actor).
enum WatchSettings {
    static let ticketsKey = "publit.watch.tickets"
    static let screenKey = "publit.watch.screen"
    static let processedKey = "publit.watch.processed"

    /// Tickets travel to the paired Apple Watch only while this is on (Settings). On by default: the watch is
    /// paired by the user, and the tickets stay between the two devices.
    static var ticketsOn: Bool {
        ((UserDefaults.standard.object(forKey: ticketsKey) as? Bool) ?? true) && Features.passes
    }
}

/// The iPhone's side of the Apple Watch app. It sends the watch what it shows (saved trips, saved stops and
/// places, tickets with a picture of their code) and carries out what the watch asks for (save a trip, start it,
/// save a place). Everything travels between the two devices through WatchConnectivity; nothing goes to a server.
@MainActor
final class WatchSyncHub: NSObject, WCSessionDelegate {
    static let shared = WatchSyncHub()

    private var trips: TripStore?
    private var favorites: FavoritesStore?
    private var passes: PassStore?
    private var session: WCSession?
    private var lastSent: (structure: String, content: String, sentAt: Date)?
    private var scheduled: Task<Void, Never>?
    private var sentFiles: Set<String> = []
    private var working = false
    private var again = false
    private var processed: [String] = UserDefaults.standard.stringArray(forKey: WatchSettings.processedKey) ?? []

    private struct CodeJob: Sendable {
        let passId: String
        let updatedAt: Date
        let code: TicketPass.Barcode
        let source: BarcodeSource?
    }

    // MARK: Start

    /// Called once from the app. Without a paired watch (or on an iPad) it does nothing.
    func attach(trips: TripStore, favorites: FavoritesStore, passes: PassStore) {
        guard self.trips == nil, WCSession.isSupported() else { return }
        self.trips = trips
        self.favorites = favorites
        self.passes = passes
        let s = WCSession.default
        s.delegate = self
        s.activate()
        session = s
        observe()
    }

    /// The setting "Tickets on Apple Watch" changed.
    func settingsChanged() {
        if !WatchSettings.ticketsOn { sentFiles.removeAll() }
        schedule(after: 0.2, force: true)
    }

    private var canSend: Bool {
        guard let session else { return false }
        return session.activationState == .activated && session.isPaired && session.isWatchAppInstalled
    }

    private var screenPixels: Int {
        WatchCodeFile.clamped(UserDefaults.standard.object(forKey: WatchSettings.screenKey) as? Int)
    }

    // MARK: What changed

    /// Watches the stores. The change callback fires once, so it starts the next round itself.
    private func observe() {
        guard let trips, let favorites, let passes else { return }
        withObservationTracking {
            _ = trips.trips
            _ = trips.activeTripId
            _ = favorites.items
            _ = passes.passes
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.schedule(after: 1.5, force: false)
                self?.observe()
            }
        }
    }

    /// Sends after a short pause: several changes in a row (a refresh of every trip) make one transfer.
    private func schedule(after seconds: Double, force: Bool) {
        scheduled?.cancel()
        scheduled = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
            guard !Task.isCancelled else { return }
            await self?.send(force: force)
        }
    }

    // MARK: Sending

    private func send(force: Bool) async {
        guard let trips, let favorites, let passes, canSend else { return }
        if working { again = true; return }
        working = true
        defer { working = false }
        let now = Date()
        let ticketsOn = WatchSettings.ticketsOn
        var codes: [String: String] = [:]
        if ticketsOn {
            let jobs = WatchTickets.shared(from: passes.passes, at: now).compactMap { pass -> CodeJob? in
                guard let code = pass.barcode else { return nil }
                let source = pass.document.map {
                    BarcodeSource.file(passes.documentDirectory.appendingPathComponent($0.file), $0.kind, page: $0.page)
                }
                return CodeJob(passId: pass.id, updatedAt: pass.updatedAt, code: code, source: source)
            }
            let pixels = screenPixels
            codes = await Task.detached(priority: .utility) { Self.draw(jobs, pixels: pixels) }.value
        } else {
            Task.detached(priority: .utility) { Self.deleteAllCodes() }
        }
        let list = trips.trips.filter { !trips.isPendingRemoval($0.id) }
        let snapshot = WatchSnapshot.make(now: now, trips: list, activeTripId: trips.activeTripId, places: favorites.items,
                                          passes: passes.passes, ticketsOn: ticketsOn, codes: codes, acks: processed)
        if !force {
            switch WatchSyncPolicy.decide(last: lastSent, new: snapshot, now: now) {
            case .skip: return
            case .wait(let seconds):
                schedule(after: seconds, force: false)
                return
            case .send: break
            }
        }
        transfer(snapshot)
        if again {
            again = false
            schedule(after: 0.5, force: false)
        }
    }

    private func transfer(_ snapshot: WatchSnapshot) {
        guard let session, let data = try? WatchCodec.encode(snapshot) else { return }
        // The pictures first, so a ticket is complete when the snapshot arrives.
        for ticket in snapshot.tickets {
            guard let name = ticket.code, !sentFiles.contains(name) else { continue }
            let url = Self.codeDirectory.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            session.transferFile(url, metadata: [WatchTransfer.kindKey: WatchTransfer.codeKind, WatchTransfer.nameKey: name])
            sentFiles.insert(name)
        }
        // The newest snapshot is all the watch needs: older ones still waiting are cancelled.
        for transfer in session.outstandingFileTransfers {
            if (transfer.file.metadata?[WatchTransfer.kindKey] as? String) == WatchTransfer.snapshotKind { transfer.cancel() }
        }
        let outbox = Self.outbox
        try? FileManager.default.createDirectory(at: outbox, withIntermediateDirectories: true)
        let file = outbox.appendingPathComponent("snapshot-\(UUID().uuidString).json")
        guard (try? data.write(to: file, options: .atomic)) != nil else { return }
        session.transferFile(file, metadata: [WatchTransfer.kindKey: WatchTransfer.snapshotKind])
        lastSent = (WatchSyncPolicy.structure(snapshot), WatchSyncPolicy.content(snapshot), snapshot.sentAt)
    }

    // MARK: Code pictures

    nonisolated static var codeDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Publit", isDirectory: true).appendingPathComponent("watch-codes", isDirectory: true)
    }

    nonisolated static var outbox: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("watch-outbox", isDirectory: true)
    }

    /// Draws what is missing; returns the file name per pass. Pictures of tickets that are gone are deleted after a day
    /// (a transfer may still be reading them).
    nonisolated private static func draw(_ jobs: [CodeJob], pixels: Int) -> [String: String] {
        let directory = codeDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var names: [String: String] = [:]
        for job in jobs {
            let name = WatchCodeFile.name(passId: job.passId, updatedAt: job.updatedAt, pixels: pixels)
            let url = directory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) {
                names[job.passId] = name
                continue
            }
            guard let png = WatchCodeImage.png(for: job.code, source: job.source, width: pixels) else { continue }
            if (try? png.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])) != nil {
                names[job.passId] = name
            }
        }
        let keep = Set(names.values)
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in files where !keep.contains(file.lastPathComponent) {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if Date().timeIntervalSince(modified) > 24 * 3600 { try? FileManager.default.removeItem(at: file) }
        }
        return names
    }

    nonisolated private static func deleteAllCodes() {
        try? FileManager.default.removeItem(at: codeDirectory)
    }

    // MARK: Requests from the watch

    private func handle(_ intent: WatchIntent) {
        guard let trips, let favorites else { return }
        if processed.contains(intent.id) {
            schedule(after: 0.3, force: true)
            return
        }
        switch intent.kind {
        case .saveTrip:
            guard let trip = intent.trip else { break }
            let saved = trips.insert(trip)
            // The watch sends the trip without walking directions: a fresh copy brings them back.
            Task { [weak self] in
                guard let fresh = try? await TripRefreshCoordinator.shared.refresh(saved.itinerary.id) else { return }
                self?.trips?.update(saved.id, with: fresh)
            }
        case .removeTrip:
            guard let id = intent.tripId, let trip = trips.trip(id) else { break }
            LeaveReminder.cancel(id)
            GetOffReminder.cancelAll(trip.itinerary)
            Task { await LiveTripActivity.end(id) }
            trips.remove(id)
        case .startTrip:
            guard let id = intent.tripId, let trip = trips.trip(id) else { break }
            let hasTicket = passes.map { !$0.passes(forTrip: id, at: trip.startTime).isEmpty } ?? false
            Task { await TripSession.start(trip, in: trips, hasTicket: hasTicket) }
        case .stopTrip:
            guard let id = intent.tripId, let trip = trips.trip(id) else { break }
            Task { await TripSession.stop(trip, in: trips) }
        case .savePlace:
            if let place = intent.place, !favorites.contains(place) { favorites.toggle(place) }
        case .removePlace:
            if let id = intent.placeId { favorites.remove([id]) }
        case .resend:
            if let pixels = intent.screen { UserDefaults.standard.set(WatchCodeFile.clamped(pixels), forKey: WatchSettings.screenKey) }
            sentFiles.removeAll()
            lastSent = nil
        }
        processed.append(intent.id)
        processed = Array(processed.suffix(200))
        UserDefaults.standard.set(processed, forKey: WatchSettings.processedKey)
        // The answer carries the confirmation, so the watch drops its own copy of the request.
        schedule(after: 0.3, force: true)
    }

    // MARK: WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        Task { @MainActor in self.schedule(after: 0.5, force: true) }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Another watch was selected: the session starts again for the new one.
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        // A watch app was installed or removed: everything goes out again.
        Task { @MainActor in
            self.sentFiles.removeAll()
            self.lastSent = nil
            self.schedule(after: 0.5, force: true)
        }
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard (file.metadata?[WatchTransfer.kindKey] as? String) == WatchTransfer.intentKind,
              let data = try? Data(contentsOf: file.fileURL),
              let intent = try? WatchCodec.intent(from: data) else { return }
        Task { @MainActor in self.handle(intent) }
    }

    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        // Snapshots are written to a temporary folder just for the transfer.
        let url = fileTransfer.file.fileURL
        if url.deletingLastPathComponent().lastPathComponent == "watch-outbox" { try? FileManager.default.removeItem(at: url) }
    }
}

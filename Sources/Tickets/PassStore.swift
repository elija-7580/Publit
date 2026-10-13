import Foundation
import Observation

/// Passes and their original documents, on the device only (file protection: complete).
@MainActor
@Observable
final class PassStore {
    private(set) var passes: [TicketPass] = []

    @ObservationIgnored private let file: JSONFile<[TicketPass]>
    @ObservationIgnored let documentDirectory: URL

    /// Documents above this size are rejected; tickets are a few pages at most.
    static let maxDocumentBytes = 25 * 1024 * 1024

    enum Failure: LocalizedError, Equatable {
        case documentTooLarge
        var errorDescription: String? { L10n.t("This file is too large for a ticket.") }
    }

    init(directory: URL? = nil) {
        let dir = directory ?? JSONFile<[TicketPass]>.defaultDirectory
        file = JSONFile(name: "passes.json", directory: dir)
        documentDirectory = dir.appendingPathComponent("passes", isDirectory: true)
        try? FileManager.default.createDirectory(at: documentDirectory, withIntermediateDirectories: true)
        passes = file.load() ?? []
    }

    func pass(_ id: String) -> TicketPass? { passes.first { $0.id == id } }

    /// A pass by its own ID or by the ID of the old ticket it came from (links in calendars and Live Activities).
    func pass(linkedTo id: String) -> TicketPass? { pass(id) ?? passes.first { $0.legacyId == id } }

    func documentURL(_ pass: TicketPass) -> URL? {
        pass.document.map { documentDirectory.appendingPathComponent($0.file) }
    }

    func logoURL(_ pass: TicketPass) -> URL? {
        pass.logo.map { documentDirectory.appendingPathComponent($0.file) }
    }

    /// Sets or removes (nil) the operator logo of a saved pass. PNG data, already scaled down.
    func setLogo(_ png: Data?, source: String?, for id: String) {
        guard var pass = pass(id) else { return }
        if let old = logoURL(pass) { try? FileManager.default.removeItem(at: old) }
        if let png {
            // A new name each time, so views showing the old file reload.
            let name = "\(id)-logo-\(Int(Date().timeIntervalSince1970)).png"
            guard (try? png.write(to: documentDirectory.appendingPathComponent(name), options: [.atomic, .completeFileProtection])) != nil
            else { return }
            pass.logo = TicketPass.Logo(file: name, source: source)
        } else {
            pass.logo = nil
        }
        update(pass)
    }

    func grouped(at date: Date = .now) -> [(group: PassGroup, passes: [TicketPass])] { PassGroup.grouped(passes, at: date) }

    /// What a trip offers: its own single tickets, then passes valid at the trip's time.
    func passes(forTrip tripId: String?, at date: Date = .now) -> [TicketPass] {
        let own = tripId.map { id in passes.filter { $0.tripId == id } } ?? []
        let valid = passes.filter { p in
            guard p.category.isPass, !own.contains(p) else { return false }
            if case .valid = p.validity(at: date) { return true }
            return false
        }
        return own + valid
    }

    /// Saves a checked pass. The document is written away from the main actor before the pass appears.
    @discardableResult
    func add(_ pass: TicketPass, document: Data? = nil, kind: TicketPass.Document.Kind? = nil, page: Int = 0) async throws -> TicketPass {
        var pass = pass
        if let document, let kind {
            guard document.count <= Self.maxDocumentBytes else { throw Failure.documentTooLarge }
            let name = "\(pass.id).\(kind == .pdf ? "pdf" : "img")"
            let url = documentDirectory.appendingPathComponent(name)
            try await Task.detached(priority: .userInitiated) {
                try document.write(to: url, options: [.atomic, .completeFileProtection])
            }.value
            pass.document = TicketPass.Document(file: name, kind: kind, page: page)
        }
        insert(pass)
        await Task.detached(priority: .userInitiated) { JSONPersistence.flush() }.value
        return pass
    }

    /// Adds or replaces a pass that needs no file work (samples, tests, imports).
    func insert(_ pass: TicketPass) {
        if let i = passes.firstIndex(where: { $0.id == pass.id }) { passes[i] = pass } else { passes.append(pass) }
        persist()
    }

    func update(_ pass: TicketPass, now: Date = .now) {
        guard let i = passes.firstIndex(where: { $0.id == pass.id }) else { return }
        var updated = pass
        updated.updatedAt = now
        passes[i] = updated
        persist()
    }

    func remove(_ id: String) {
        if let p = pass(id) {
            if let url = documentURL(p) { try? FileManager.default.removeItem(at: url) }
            if let url = logoURL(p) { try? FileManager.default.removeItem(at: url) }
        }
        passes.removeAll { $0.id == id }
        persist()
    }

    /// Takes over tickets from the first ticket version (screenshot + name + validity). Runs once per ticket.
    @discardableResult
    func importLegacy(_ tickets: [Ticket], imageDirectory: URL, now: Date = .now) -> Int {
        var count = 0
        for t in tickets where !passes.contains(where: { $0.legacyId == t.id }) {
            var pass = TicketPass(title: t.name, category: t.kind == .pass ? .period : .single, validUntil: t.validUntil,
                                  tripId: t.tripId, legacyId: t.id, createdAt: t.addedAt, updatedAt: now)
            if let file = t.imageFile {
                let source = imageDirectory.appendingPathComponent(file)
                let name = "\(pass.id).img"
                if (try? FileManager.default.copyItem(at: source, to: documentDirectory.appendingPathComponent(name))) != nil {
                    pass.document = TicketPass.Document(file: name, kind: .image, page: 0)
                }
            }
            if let link = t.appLink { pass.notes = link }
            passes.append(pass)
            count += 1
        }
        if count > 0 { persist() }
        return count
    }

    private func persist() { file.saveInBackground(passes) }
}

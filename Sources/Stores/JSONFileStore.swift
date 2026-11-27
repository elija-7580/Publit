import Foundation

/// Small JSON file persistence in Application Support (kept out of iCloud/iTunes backups is not needed:
/// these are the user's own trips and tickets, so they *should* be backed up with the device).
struct JSONFile<Value: Codable>: Sendable {
    let url: URL

    init(name: String, directory: URL? = nil) {
        let dir = directory ?? JSONFile.defaultDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent(name)
    }

    static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Publit", isDirectory: true)
    }

    static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { date, enc in
            var c = enc.singleValueContainer()
            try c.encode(DateParsing.format(date))
        }
        return e
    }

    func load() -> Value? {
        guard let data = read() else { return nil }
        if let value = try? TransitousClient.makeDecoder().decode(Value.self, from: data) { return value }
        // The store starts empty and its next save replaces the file: what is in it stays next to it.
        JSONFileRescue.keepCopy(of: url)
        return nil
    }

    /// The file's bytes; nil when there is none. A file that is there but cannot be read (the iPhone
    /// not unlocked since its restart) is remembered, so the first save keeps a copy of it.
    private func read() -> Data? {
        JSONPersistence.flush()
        if let data = try? Data(contentsOf: url) { return data }
        if FileManager.default.fileExists(atPath: url.path) { JSONFileRescue.couldNotRead(url) }
        return nil
    }

    /// A saved list, entry by entry: one entry the app cannot read (written by a newer version, or
    /// damaged) is left out instead of emptying the whole list. Trips and tickets used to be all or
    /// nothing: one bad entry and the store started empty, and the next save wrote that over the file.
    /// The file as it was is kept next to it ("….unreadable") whenever something could not be read.
    func loadList<Element: Codable>() -> Value? where Value == [Element] {
        guard let data = read() else { return nil }
        let decoder = TransitousClient.makeDecoder()
        if let value = try? decoder.decode(Value.self, from: data) { return value }
        JSONFileRescue.keepCopy(of: url)
        guard let rescued = try? decoder.decode(LossyList<Element>.self, from: data) else { return nil }
        HangLog.shared.note("store \(url.lastPathComponent): \(rescued.skipped) unreadable entr\(rescued.skipped == 1 ? "y" : "ies") left out")
        return rescued.items
    }

    /// Immutable snapshots are encoded and written in order, away from the UI thread.
    func saveInBackground(_ value: Value, completion: (@Sendable (Result<Void, Error>) -> Void)? = nil) where Value: Sendable {
        JSONPersistence.queue.async {
            do { try saveChecked(value); completion?(.success(())) }
            catch { completion?(.failure(error)) }
        }
    }

    func save(_ value: Value) { try? saveChecked(value) }

    /// Critical imports use this throwing path; a failed write must never report success.
    func saveChecked(_ value: Value) throws {
        let trace = PerformanceTrace.begin("Save local data")
        defer { PerformanceTrace.end(trace, "Save local data") }
        let data = try Self.encoder.encode(value)
        if JSONFileRescue.takeUnread(url) { JSONFileRescue.keepCopy(of: url) }
        try data.write(to: url, options: .atomic)
    }
}

/// Keeps what a store could not read. A store that starts empty writes its file anew on the next
/// change; the old file must not be gone with that.
enum JSONFileRescue {
    private static let lock = NSLock()
    private static var unread: Set<URL> = []

    static func copyURL(for url: URL) -> URL { url.appendingPathExtension("unreadable") }

    /// One copy per file, the newest.
    static func keepCopy(of url: URL) {
        let copy = copyURL(for: url)
        let files = FileManager.default
        guard files.fileExists(atPath: url.path) else { return }
        try? files.removeItem(at: copy)
        try? files.copyItem(at: url, to: copy)
    }

    static func couldNotRead(_ url: URL) {
        lock.lock(); unread.insert(url); lock.unlock()
    }

    /// True once after `couldNotRead`.
    static func takeUnread(_ url: URL) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return unread.remove(url) != nil
    }
}

/// Reads on launch/reload wait for pending snapshots. Ordinary writes never block the UI.
enum JSONPersistence {
    static let queue = DispatchQueue(label: "io.github.publit.persistence", qos: .utility)
    static func flush() { queue.sync { } }
}

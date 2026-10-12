import Foundation
import Observation

/// How long a response may be reused, and whether a copy is kept on disk for offline use.
struct CachePolicy: Sendable {
    /// Reuse without asking the server when younger than this (seconds). 0 = always ask.
    var maxAge: TimeInterval
    /// Keep a copy on disk so the screen still works without a connection.
    var persist: Bool
    /// Fixed slot instead of the URL, e.g. "nearby" (the GPS position changes on every request).
    var slot: String? = nil

    static let live = CachePolicy(maxAge: 20, persist: true)
    static let search = CachePolicy(maxAge: 24 * 3600, persist: true)
    static let noStore = CachePolicy(maxAge: 0, persist: false)
}

/// Responses kept in memory (instant back-navigation) and on disk in Caches (offline).
/// The system may delete Caches at any time; nothing here is the only copy of user data.
final class ResponseCache: @unchecked Sendable {
    struct Entry: Sendable {
        let data: Data
        let date: Date
        let url: String
    }

    private let lock = NSLock()
    private var memory: [String: Entry] = [:]
    private let directory: URL?
    static let maxMemoryEntries = 200

    init(directory: URL? = ResponseCache.defaultDirectory) {
        self.directory = directory
        if let directory { try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
    }

    static var defaultDirectory: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Publit/responses", isDirectory: true)
    }

    /// Stable short file name for a key (FNV-1a, 64 bit).
    static func fileName(_ key: String) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for b in key.utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
        return String(h, radix: 16) + ".cache"
    }

    func fresh(_ key: String, maxAge: TimeInterval, now: Date = Date()) -> Entry? {
        guard maxAge > 0 else { return nil }
        lock.lock(); defer { lock.unlock() }
        guard let e = memory[key], now.timeIntervalSince(e.date) < maxAge else { return nil }
        return e
    }

    func store(_ key: String, data: Data, url: String, persist: Bool, now: Date = Date()) {
        let entry = Entry(data: data, date: now, url: url)
        lock.lock()
        if memory.count >= Self.maxMemoryEntries {
            // Drop the oldest half; cheaper than tracking exact LRU order.
            let keep = memory.sorted { $0.value.date > $1.value.date }.prefix(Self.maxMemoryEntries / 2)
            memory = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
        memory[key] = entry
        lock.unlock()
        guard persist, let directory else { return }
        let header = "\(now.timeIntervalSince1970)\n\(url)\n"
        var blob = Data(header.utf8)
        blob.append(data)
        try? blob.write(to: directory.appendingPathComponent(Self.fileName(key)), options: .atomic)
    }

    /// Last known response, from memory or disk, however old.
    func stale(_ key: String) -> Entry? {
        lock.lock()
        let m = memory[key]
        lock.unlock()
        if let m { return m }
        guard let directory,
              let blob = try? Data(contentsOf: directory.appendingPathComponent(Self.fileName(key))) else { return nil }
        return Self.decode(blob)
    }

    static func decode(_ blob: Data) -> Entry? {
        let newline = UInt8(ascii: "\n")
        guard let first = blob.firstIndex(of: newline),
              let second = blob[blob.index(after: first)...].firstIndex(of: newline),
              let ts = Double(String(decoding: blob[blob.startIndex..<first], as: UTF8.self)) else { return nil }
        let url = String(decoding: blob[blob.index(after: first)..<second], as: UTF8.self)
        return Entry(data: Data(blob[blob.index(after: second)...]), date: Date(timeIntervalSince1970: ts), url: url)
    }

    /// Removes disk copies older than `age` seconds (called at launch).
    func prune(olderThan age: TimeInterval, now: Date = Date()) {
        guard let directory,
              let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
        else { return }
        for f in files {
            let date = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if now.timeIntervalSince(date) > age { try? FileManager.default.removeItem(at: f) }
        }
    }
}

/// Whether the last request reached the server. Screens show a small "Offline" note while
/// they display saved responses.
@MainActor
@Observable
final class Connectivity {
    static let shared = Connectivity()
    /// Set while screens show saved data; the time that data was fetched.
    private(set) var offlineDataFrom: Date?
    var isOffline: Bool { offlineDataFrom != nil }

    func reachedServer() { if offlineDataFrom != nil { offlineDataFrom = nil } }
    func servedOffline(from date: Date) { offlineDataFrom = date }
}

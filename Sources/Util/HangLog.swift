import Foundation

/// Notes when the main thread stops responding for 2 s or more, with the last screens opened,
/// so a freeze on a device can be traced to a screen. Only fixed screen names, the app version
/// and times are written — no places, stops, lines or tickets. The file stays on this device
/// until the user shares it from Settings.
final class HangLog: @unchecked Sendable {
    static let shared = HangLog()

    /// Seconds without a reply from the main thread before a freeze is noted, then while it lasts.
    /// iOS ends an app that has been blocked for about 10 s, so the last note comes before that.
    static let marks: [TimeInterval] = [2, 5, 8]
    static let maxTrail = 25
    static let maxBytes = 400_000

    let fileURL: URL
    private let lock = NSLock()
    private var trail: [String] = []
    private var waitingSince: Date?
    private var lastTick: Date?
    private var notedMarks = 0
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "io.github.publit.hanglog", qos: .utility)

    init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Diagnostics", isDirectory: true)
        fileURL = dir.appendingPathComponent("publit-freezes.txt")
    }

    var hasEntries: Bool {
        ((try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0) > 0
    }

    func clear() { try? FileManager.default.removeItem(at: fileURL) }

    /// A step such as "open Route" or "tab plan". Callers pass fixed names only.
    func note(_ event: String, at now: Date = Date()) {
        lock.lock()
        trail.append("\(Self.clock(now)) \(event)")
        if trail.count > Self.maxTrail { trail.removeFirst(trail.count - Self.maxTrail) }
        lock.unlock()
    }

    /// Starts the watchdog: every half second it asks the main thread for a reply.
    func start() {
        #if canImport(Darwin)
        MainThreadSampler.install()
        #endif
        lock.lock(); defer { lock.unlock() }
        guard timer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 1, repeating: 0.5, leeway: .milliseconds(100))
        t.setEventHandler { [weak self] in
            guard let self, self.tick(now: Date()) else { return }
            DispatchQueue.main.async { self.answered(now: Date()) }
        }
        timer = t
        t.resume()
    }

    /// One watchdog step. Returns true when a new question should be sent to the main thread.
    @discardableResult
    func tick(now: Date) -> Bool {
        lock.lock()
        // A long gap means the app was suspended, not frozen: start counting again.
        if let last = lastTick, now.timeIntervalSince(last) > 3, waitingSince != nil {
            waitingSince = now
            notedMarks = 0
        }
        lastTick = now
        guard let since = waitingSince else {
            waitingSince = now
            lock.unlock()
            return true
        }
        let blocked = now.timeIntervalSince(since)
        var entry: String?
        if notedMarks < Self.marks.count, blocked >= Self.marks[notedMarks] {
            let mark = Int(Self.marks[notedMarks])
            if notedMarks == 0 {
                let os = ProcessInfo.processInfo.operatingSystemVersionString
                entry = "\n— \(Self.dateTime(since)) · Publit \(AppInfo.version) (\(AppInfo.build)) · \(Self.device) · \(os)\n"
                    + "No response for \(mark) s. Last steps:\n"
                    + (trail.isEmpty ? "  (none)\n" : trail.map { "  \($0)\n" }.joined())
            } else {
                entry = "Still no response after \(mark) s\n"
            }
            notedMarks += 1
        }
        lock.unlock()
        if let entry { append(entry + stack()) }
        return false
    }

    /// What the main thread is doing right now; repeated frames are folded.
    private func stack() -> String {
        #if canImport(Darwin)
        guard let lines = MainThreadSampler.sample(), !lines.isEmpty else { return "  (no call stack)\n" }
        var out = "Main thread:\n"
        var previous: String?, repeats = 0
        func flush() { if repeats > 0 { out += "      … same ×\(repeats)\n" }; repeats = 0 }
        for line in lines {
            if line == previous { repeats += 1; continue }
            flush()
            out += "    \(line)\n"
            previous = line
        }
        flush()
        return out
        #else
        return ""
        #endif
    }

    private static var device: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }

    /// The main thread replied.
    func answered(now: Date) {
        lock.lock()
        let since = waitingSince, noted = notedMarks
        waitingSince = nil
        notedMarks = 0
        lock.unlock()
        if noted > 0, let since {
            append(String(format: "Responding again after %.1f s\n", now.timeIntervalSince(since)))
        }
    }

    private func append(_ text: String) {
        let fm = FileManager.default
        try? fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var data = (try? Data(contentsOf: fileURL)) ?? Data()
        data.append(Data(text.utf8))
        if data.count > Self.maxBytes {
            // Keep the newest half, starting at a whole line.
            var tail = data.suffix(Self.maxBytes / 2)
            if let nl = tail.firstIndex(of: 0x0A) { tail = tail[tail.index(after: nl)...] }
            data = Data(tail)
        }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func clock(_ date: Date) -> String { format(date, "HH:mm:ss") }
    private static func dateTime(_ date: Date) -> String { format(date, "yyyy-MM-dd HH:mm:ss") }
    private static func format(_ date: Date, _ pattern: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = pattern
        return f.string(from: date)
    }
}

#if canImport(SwiftUI)
import SwiftUI

extension View {
    /// Notes opening and closing this screen in the freeze log. Takes a fixed name only.
    func screenTrail(_ name: StaticString) -> some View {
        onAppear { HangLog.shared.note("open \(name)") }
            .onDisappear { HangLog.shared.note("close \(name)") }
    }
}
#endif

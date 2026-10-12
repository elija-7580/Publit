import Foundation

/// Small JSON file persistence in Application Support (kept out of iCloud/iTunes backups is not needed:
/// these are the user's own trips and tickets, so they *should* be backed up with the device).
struct JSONFile<Value: Codable> {
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
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? TransitousClient.makeDecoder().decode(Value.self, from: data)
    }

    func save(_ value: Value) {
        guard let data = try? Self.encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

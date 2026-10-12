import Foundation

enum Fmt {
    static func duration(seconds: Int) -> String {
        let minutes = max(1, Int((Double(seconds) / 60).rounded()))
        if minutes < 60 { return L10n.f("%lld min", minutes) }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? L10n.f("%lld h", h) : L10n.f("%lld h %lld min", h, m)
    }

    static func distance(meters: Double) -> String {
        if meters < 1000 { return "\(Int(meters.rounded())) m" }
        let f = NumberFormatter()
        f.locale = Locale.current
        f.minimumFractionDigits = 1
        f.maximumFractionDigits = 1
        return (f.string(from: NSNumber(value: meters / 1000)) ?? String(format: "%.1f", meters / 1000)) + " km"
    }

    static func changes(_ n: Int) -> String {
        n == 0 ? L10n.t("Direct") : n == 1 ? L10n.t("1 change") : L10n.f("%lld changes", n)
    }

    static func stops(_ n: Int) -> String {
        n == 0 ? L10n.t("No stops") : n == 1 ? L10n.t("1 stop") : L10n.f("%lld stops", n)
    }

    private static let lock = NSLock()
    private static var formatters: [String: DateFormatter] = [:]

    private static func formatter(_ tz: TimeZone) -> DateFormatter {
        lock.lock(); defer { lock.unlock() }
        if let f = formatters[tz.identifier] { return f }
        let f = DateFormatter()
        f.locale = Locale.current
        f.timeZone = tz
        f.setLocalizedDateFormatFromTemplate("jmm")
        formatters[tz.identifier] = f
        return f
    }

    /// Clock time in the stop's own time zone, so a trip in Istanbul shows Istanbul time
    /// even when the phone is still set to Vienna.
    static func time(_ date: Date, tz: String? = nil) -> String {
        formatter(timeZone(tz)).string(from: date)
    }

    static func timeZone(_ id: String?) -> TimeZone {
        id.flatMap(TimeZone.init(identifier:)) ?? .current
    }

    /// Non-nil when the place's time zone differs from the device's at `date`.
    static func foreignZoneNote(tz: String?, at date: Date, device: TimeZone = .current) -> String? {
        guard let id = tz, let zone = TimeZone(identifier: id),
              zone.secondsFromGMT(for: date) != device.secondsFromGMT(for: date) else { return nil }
        let offset = zone.secondsFromGMT(for: date) / 60
        let sign = offset >= 0 ? "+" : "−"
        let h = abs(offset) / 60, m = abs(offset) % 60
        let gmt = m == 0 ? "GMT\(sign)\(h)" : String(format: "GMT\(sign)%d:%02d", h, m)
        let city = id.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? id
        return L10n.f("Local time %@ (%@)", city, gmt)
    }
}

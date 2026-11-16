import Foundation

/// When the get-off reminder goes off (Settings → Trips). The time-based reminder is the fallback for
/// every choice: it still fires about two minutes before the arrival when no reliable location is there.
enum GetOffAlert: String, CaseIterable, Identifiable, Sendable {
    /// At the stop before yours ("Next stop: get off").
    case oneStopBefore
    /// Two stops before yours.
    case twoStopsBefore
    /// Shortly before your stop (about 400 m away).
    case approaching
    /// By the clock only: no location used.
    case timeOnly

    static let defaultsKey = "getOffAlert"
    static let `default`: GetOffAlert = .oneStopBefore

    var id: String { rawValue }

    static var current: GetOffAlert {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(GetOffAlert.init(rawValue:)) ?? .default
    }

    var title: String {
        switch self {
        case .oneStopBefore: return L10n.t("One stop before")
        case .twoStopsBefore: return L10n.t("Two stops before")
        case .approaching: return L10n.t("Shortly before the stop")
        case .timeOnly: return L10n.t("By the clock only")
        }
    }

    var usesLocation: Bool { self != .timeOnly }

    /// Stops before the one you get off at.
    var stopsBefore: Int {
        switch self {
        case .twoStopsBefore: return 2
        case .oneStopBefore: return 1
        case .approaching, .timeOnly: return 0
        }
    }
}

/// Decides from the phone's position on board (laid onto the line, see `TripProgress.located`)
/// whether the get-off alert is due. The order of the stops counts, not only distance: a line that
/// passes close to your stop earlier (a loop, a parallel street) does not set it off.
enum GetOffWatch {
    /// "Approaching": this close to the stop, along the line.
    static let approachMeters: Double = 400

    /// `progress` must come from GPS; `metresToExit` is the distance along the line to the exit stop.
    static func isDue(_ alert: GetOffAlert, progress: TripProgress, stopCount: Int, metresToExit: Double?) -> Bool {
        guard alert.usesLocation, stopCount >= 2 else { return false }
        let exit = stopCount - 1
        let value = progress.stopValue(count: stopCount)
        if case .notStarted = progress { return false }
        if case .finished = progress { return false }
        if alert == .approaching {
            if case .atStop(let i) = progress, i == exit { return true }
            guard value > Double(exit - 1), let metresToExit else { return false }
            return metresToExit <= approachMeters
        }
        // At (or past) the milestone stop, and not yet at the exit itself. With fewer stops on the ride
        // than the milestone asks for, the first stop counts once the vehicle has left it.
        let milestone = max(0, exit - alert.stopsBefore)
        if milestone == 0 {
            if case .atStop(0) = progress { return false }
        }
        return value >= Double(milestone) && value < Double(exit) + 0.001
    }

    /// The text of the alert: "Get off at Odeonsplatz (next stop)" / "… in 2 stops".
    static func message(exit: String, stopsLeft: Int) -> String {
        switch stopsLeft {
        case ...0: return L10n.f("Get off here: %@", exit)
        case 1: return L10n.f("Next stop: %@. Get off there.", exit)
        default: return L10n.f("Get off at %@ in %lld stops.", exit, stopsLeft)
        }
    }
}

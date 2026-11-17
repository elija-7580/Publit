import Foundation
import UserNotifications

/// A change on a followed trip has become unlikely: a notification right away, with the backup;
/// tapping it opens the trip with other connections from that stop. Once per change, again only
/// when the chance falls by another 20 points or the ride is cancelled. Computed on the iPhone
/// (live refresh while Publit is open, the position during a started trip); never asks for permission.
enum ChangeRiskNotifier {
    private static let sentKey = "changeRiskSent"

    static func identifier(tripId: String, _ change: SmartRouting.Change) -> String {
        "changerisk|\(tripId)|\(change.stopName)|\(change.outgoing.tripId ?? change.outgoing.lineName)"
    }

    @MainActor
    static func check(_ trip: SavedTrip, at now: Date = .now, position: LatLon? = nil) {
        guard SmartRouting.isEnabled, TransferLearning.warns,
              let risk = SmartRouting.changeAtRisk(trip.itinerary, at: now, position: position) else { return }
        notify(risk, tripId: trip.id, message: riskMessage(risk), now: now)
    }

    static func notify(_ change: SmartRouting.Change, tripId: String, message: String, now: Date = .now) {
        guard TransferLearning.warns else { return }
        let id = identifier(tripId: tripId, change)
        let cancelled = change.outgoing.cancelled == true || change.incoming.cancelled == true
        var sent = UserDefaults.standard.dictionary(forKey: sentKey) as? [String: [Double]] ?? [:]
        sent = sent.filter { now.timeIntervalSince1970 - ($0.value.last ?? 0) < 2 * 86_400 }
        guard TransferLearning.warningDue(chance: change.chance, cancelled: cancelled, lastWarned: sent[id]?.first) else { return }
        sent[id] = [cancelled ? 0.01 : change.chance, now.timeIntervalSince1970]
        UserDefaults.standard.set(sent, forKey: sentKey)
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = L10n.t("Change at risk")
            content.body = message + " " + L10n.t("Tap for other connections.")
            content.sound = .default
            content.interruptionLevel = .active
            content.userInfo = ["url": DeepLink.trip(tripId).url.absoluteString]
            try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
        }
    }

    /// "Your change at Ostbahnhof may not work (40 %). Backup: S7 at 13:27"
    static func riskMessage(_ r: SmartRouting.Change) -> String {
        if r.outgoing.cancelled == true {
            return L10n.f("%@ from %@ does not run.", r.outgoing.lineName, r.outgoing.from.name)
        }
        let backup = SmartRouting.backup(for: r.outgoing).map { b -> String in
            " " + L10n.f("Backup: %@ at %@", b.leg.lineName, Fmt.time(b.leg.startTime, tz: b.leg.from.tz))
        } ?? ""
        return L10n.f("Your change at %@ may not work (%lld %%).", r.stopName, r.percent) + backup
    }
}

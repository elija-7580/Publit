import Foundation
import UserNotifications

/// "Your connection at … is unlikely": a local notification when a change of a started or remembered
/// trip drops below "likely" or its connection is cancelled (`ChangeWatch` decides, at most once per
/// change unless it gets clearly worse). Tapping it opens routes from the change stop – or from where
/// the user is, once off the feeder – to the destination, leaving now. Only when notifications are
/// already allowed and Settings → Smart routing → "Change alerts" is on; this never asks.
@MainActor
enum ChangeRiskNotifier {
    /// Recomputes the trip's changes (live data, and the user's position and pace while on foot) and warns.
    static func follow(_ trip: SavedTrip, here: LatLon? = nil, speed: Double? = nil, now: Date = .now) async {
        guard SmartRouting.isEnabled, ChangeWatch.isEnabled else { return }
        var changes = SmartRouting.changes(trip.itinerary, at: now)
        if let here {
            let pace = speed ?? (UserDefaults.standard.object(forKey: SmartRouting.measuredSpeedKey) as? Double ?? 1.3)
            changes = changes.map { c in
                let table = DelayHistoryStore.shared.table(country: DelayHistory.country(ofId: c.outgoing.routeId))
                guard let p = ChangeWatch.onFoot(c, here: here, now: now, speed: pace, table: table) else { return c }
                return SmartRouting.Change(stopName: c.stopName, incoming: c.incoming, outgoing: c.outgoing, outgoingIndex: c.outgoingIndex,
                                           walkSeconds: c.walkSeconds, spareMinutes: c.spareMinutes, chance: min(c.chance, p),
                                           source: c.source, walk: c.walk)
            }
        }
        for c in ChangeWatch.due(changes, warned: ChangeWatch.warned, now: now) {
            ChangeWatch.markWarned(c)
            await post(c, trip: trip, here: here, now: now)
        }
    }

    private static func post(_ c: SmartRouting.Change, trip: SavedTrip, here: LatLon?, now: Date) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = L10n.t("Change at risk")
        content.body = ChangeWatch.message(c)
        content.sound = .default
        content.interruptionLevel = .active
        // Still on the feeder: from the change stop. Already off it: from here.
        let fromHere = here != nil && now >= c.incoming.endTime.addingTimeInterval(-60)
        let stop = c.incoming.to
        let from: SavedPlace? = fromHere ? nil
            : SavedPlace(id: "stop|\(stop.stationId)", name: stop.name, subtitle: nil, lat: stop.lat, lon: stop.lon, stopId: stop.parentId ?? stop.stopId)
        let end = trip.itinerary.legs.last?.to
        if let end {
            let to = SavedPlace(id: "dest|\(end.lat),\(end.lon)", name: trip.toName, subtitle: nil, lat: end.lat, lon: end.lon, stopId: end.stopId)
            content.userInfo = ["url": DeepLink.alternatives(from: from, to: to).url.absoluteString]
        }
        try? await center.add(UNNotificationRequest(identifier: "changerisk|\(ChangeWatch.key(c))", content: content, trigger: nil))
    }
}

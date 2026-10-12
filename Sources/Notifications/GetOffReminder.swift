import Foundation
import UserNotifications

/// Local notification shortly before the vehicle reaches the stop where you get off.
/// Nothing leaves the device.
enum GetOffReminder {
    /// Lead time before the (real-time) arrival.
    static let leadTime: TimeInterval = 120

    static func identifier(for leg: Leg) -> String {
        "getoff|\(leg.tripId ?? leg.lineName)|\(leg.to.name)|\(Int(leg.scheduledEndTime.timeIntervalSince1970))"
    }

    enum Result: Equatable { case scheduled(Date), tooLate, denied }

    static func schedule(for leg: Leg) async -> Result {
        let fireDate = max(leg.endTime.addingTimeInterval(-leadTime), leg.startTime)
        guard fireDate > Date().addingTimeInterval(5) else { return .tooLate }
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return .denied }

        let content = UNMutableNotificationContent()
        content.title = "Get off soon"
        content.body = "\(leg.lineName) reaches \(leg.to.name) at \(Fmt.time(leg.endTime, tz: leg.to.tz))."
        content.sound = .default
        content.interruptionLevel = .active

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fireDate)
        let request = UNNotificationRequest(identifier: identifier(for: leg), content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
        do {
            try await center.add(request)
            return .scheduled(fireDate)
        } catch {
            return .denied
        }
    }

    static func cancel(for leg: Leg) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier(for: leg)])
    }

    static func isScheduled(_ leg: Leg) async -> Bool {
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        return pending.contains { $0.identifier == identifier(for: leg) }
    }
}

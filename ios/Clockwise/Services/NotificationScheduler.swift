import Foundation
import Observation
import UserNotifications

@MainActor
@Observable
final class NotificationScheduler: NSObject, UNUserNotificationCenterDelegate {
    struct Reminder: Equatable {
        let id: String
        let fireDate: Date
        let minutesLeft: Int
    }

    nonisolated static let reminderLeadMinutes = [30, 3]
    nonisolated static let earlyOutDelay: TimeInterval = 15 * 60
    nonisolated private static let earlyOutID = "early-out"
    nonisolated private static let leftAtKey = "leftAt"

    private(set) var isAuthorized = false
    /// Set when the user taps the early-out banner; the UI asks them to confirm.
    var pendingEarlyOut: Date?

    @ObservationIgnored private let center = UNUserNotificationCenter.current()

    /// Reminders whose fire date already passed are dropped rather than delivered late.
    nonisolated static func reminders(timeOut: Date, now: Date) -> [Reminder] {
        reminderLeadMinutes.compactMap { minutes in
            let fireDate = timeOut.addingTimeInterval(-Double(minutes) * 60)
            guard fireDate > now else { return nil }
            return Reminder(id: "reminder-\(minutes)", fireDate: fireDate, minutesLeft: minutes)
        }
    }

    func requestAuthorization() async {
        isAuthorized = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func scheduleReminders(timeOut: Date) {
        cancelReminders()
        let timeOutText = timeOut.formatted(date: .omitted, time: .shortened)
        for reminder in Self.reminders(timeOut: timeOut, now: .now) {
            let content = UNMutableNotificationContent()
            content.title = "Time out in \(reminder.minutesLeft) minutes"
            content.body = "Your time out is \(timeOutText). Leaving before then counts as a shortfall."
            content.sound = .default

            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second], from: reminder.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger))
        }
    }

    func cancelReminders() {
        center.removePendingNotificationRequests(
            withIdentifiers: Self.reminderLeadMinutes.map { "reminder-\($0)" })
    }

    /// Fires only if the user is still away `earlyOutDelay` after leaving; re-entering cancels it.
    func scheduleEarlyOutWarning(leftAt: Date, timeOut: Date) {
        let content = UNMutableNotificationContent()
        content.title = "Did you time out early?"
        content.body = """
            You've been away from the office for 15 minutes. Leaving at \
            \(leftAt.formatted(date: .omitted, time: .shortened)) means a \
            \(timeOut.timeIntervalSince(leftAt).hoursAndMinutes) shortfall. Tap to confirm.
            """
        content.sound = .default
        content.userInfo = [Self.leftAtKey: leftAt.timeIntervalSince1970]

        let delay = max(1, leftAt.addingTimeInterval(Self.earlyOutDelay).timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        center.add(UNNotificationRequest(identifier: Self.earlyOutID, content: content, trigger: trigger))
    }

    func cancelEarlyOutWarning() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.earlyOutID])
        center.removeDeliveredNotifications(withIdentifiers: [Self.earlyOutID])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let request = response.notification.request
        guard request.identifier == Self.earlyOutID,
              let leftAt = request.content.userInfo[Self.leftAtKey] as? TimeInterval
        else { return }
        await MainActor.run { pendingEarlyOut = Date(timeIntervalSince1970: leftAt) }
    }
}

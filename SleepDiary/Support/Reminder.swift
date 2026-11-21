import Foundation
import UserNotifications

enum Reminder {
    static let id = "morning-sleep-diary"

    static func update(enabled: Bool, minutesAfterMidnight: Int) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard enabled else { return }

        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return }

        let content = UNMutableNotificationContent()
        content.title = "Sleep diary"
        content.body = "How did last night go? Log it while it's fresh."
        content.sound = .default

        var when = DateComponents()
        when.hour = minutesAfterMidnight / 60
        when.minute = minutesAfterMidnight % 60
        let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: true)
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}

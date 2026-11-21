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

extension Reminder {
    static let afternoonID = "afternoon-symptoms"

    /// 3 pm today, or an hour from now if it's already past 2:30 pm.
    static func afternoonTime(now: Date = Date()) -> Date {
        let cal = Calendar.current
        let three = cal.date(bySettingHour: 15, minute: 0, second: 0, of: now) ?? now
        return now < three.addingTimeInterval(-30 * 60) ? three : now.addingTimeInterval(3600)
    }

    /// A one-off reminder to log daytime symptoms. Returns its time, or nil if
    /// notifications aren't allowed.
    static func scheduleAfternoon() async -> Date? {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return nil }

        let when = afternoonTime()
        let content = UNMutableNotificationContent()
        content.title = "Sleep diary"
        content.body = "How do you feel this afternoon? Log any sleepiness, dizziness or other effects."
        content.sound = .default

        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: when)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        center.removePendingNotificationRequests(withIdentifiers: [afternoonID])
        do {
            try await center.add(UNNotificationRequest(identifier: afternoonID, content: content, trigger: trigger))
            return when
        } catch {
            return nil
        }
    }

    /// When the afternoon reminder is due, if one is pending.
    static func pendingAfternoon() async -> Date? {
        let requests = await UNUserNotificationCenter.current().pendingNotificationRequests()
        guard let trigger = requests.first(where: { $0.identifier == afternoonID })?.trigger
                as? UNCalendarNotificationTrigger else { return nil }
        return trigger.nextTriggerDate()
    }
}

import UIKit
import UserNotifications
import Observation

/// Carries "the user tapped a notification" from the app delegate to the views.
@MainActor
@Observable
final class NotificationRouter {
    static let shared = NotificationRouter()
    /// Set when the afternoon reminder is tapped; Home opens the daytime screen and clears it.
    var openDaytime = false
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        guard response.notification.request.identifier == Reminder.afternoonID else { return }
        await MainActor.run { NotificationRouter.shared.openDaytime = true }
    }

    /// Show reminders as banners even while the app is open.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

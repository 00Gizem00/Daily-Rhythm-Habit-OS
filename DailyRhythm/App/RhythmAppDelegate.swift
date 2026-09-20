import DailyRhythmCore
import UIKit
import UserNotifications

final class RhythmAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              response.notification.request.identifier.hasPrefix(RhythmNotificationRequest.prefix),
              let rawURL = response.notification.request.content.userInfo["dailyRhythmURL"] as? String,
              let url = URL(string: rawURL), let destination = RhythmNotificationDestination(url: url) else { return }
        await MainActor.run { RhythmNavigation.shared.openNotification(destination) }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        // The foreground app already shows live state; do not show a stale banner.
        await NotificationSettingsModel.shared.refresh()
        return []
    }
}

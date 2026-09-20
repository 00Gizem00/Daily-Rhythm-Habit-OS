import DailyRhythmCore
import Foundation
import OSLog
import UserNotifications

struct SystemRhythmNotificationClient: RhythmNotificationClient {
    func authorization() async -> RhythmNotificationAuthorization {
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: .authorized
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    func pending() async -> [RhythmPendingNotification] {
        await UNUserNotificationCenter.current().pendingNotificationRequests().map { request in
            guard let rawURL = request.content.userInfo["dailyRhythmURL"] as? String,
                  let url = URL(string: rawURL), let destination = RhythmNotificationDestination(url: url),
                  let trigger = request.trigger as? UNCalendarNotificationTrigger, !trigger.repeats,
                  let fire = trigger.nextTriggerDate() else {
                return RhythmPendingNotification(id: request.identifier, request: nil)
            }
            return RhythmPendingNotification(id: request.identifier, request: RhythmNotificationRequest(
                id: request.identifier, fireDate: fire, title: request.content.title,
                body: request.content.body, destination: destination))
        }
    }

    func deliveredIDs() async -> [String] {
        await UNUserNotificationCenter.current().deliveredNotifications().map { $0.request.identifier }
    }
    func removePending(_ identifiers: [String]) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }
    func removeDelivered(_ identifiers: [String]) async {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers)
    }
    func add(_ request: RhythmNotificationRequest) async throws {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.sound = .default
        content.userInfo = ["dailyRhythmURL": request.destination.url.absoluteString]
        // Explicit UTC components pin the computed instant, including DST folds.
        // Daily Close wall-clock times are recomputed on timezone/foreground refresh.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: request.fireDate)
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: request.id,
                                                                             content: content, trigger: trigger))
    }
}

enum RhythmNotifications {
    static func coordinator(expectedGeneration: UUID? = nil) throws -> RhythmNotificationCoordinator {
        let container = try SharedRoutineStore.containerURL()
        let store = try SharedRoutineStore.makeStore(expectedGeneration: expectedGeneration)
        return RhythmNotificationCoordinator(preferencesURL: container.appendingPathComponent("notification-preferences.json"),
            client: SystemRhythmNotificationClient(), validateAccess: { _ = try store.validateAccess() }) { preferences, now in
                try store.notificationPlan(preferences: preferences, at: now)
            }
    }

    /// An already saved habit action stays successful even if OS scheduling fails.
    /// Settings/foreground refresh can retry and expose the notification-only error.
    static func reconcileAfterMutation() async {
        do { _ = try await coordinator().reconcile() }
        catch { Logger(subsystem: "com.lumetechllc.DailyRhythm", category: "Notifications").error("Notification reconciliation failed; retry on foreground.") }
    }
}

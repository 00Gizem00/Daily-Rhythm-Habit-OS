import DailyRhythmCore
import SwiftUI
import UserNotifications

@MainActor
final class NotificationSettingsModel: ObservableObject {
    static let shared = NotificationSettingsModel()
    @Published private(set) var preferences = RhythmNotificationPreferences()
    @Published private(set) var authorization = RhythmNotificationAuthorization.notDetermined
    @Published private(set) var pendingCount = 0
    @Published private(set) var error: String?
    @Published private(set) var updating = false
    private(set) var generation: UUID?
    private var refreshID = UUID()

    func refresh() async {
        guard !updating else { return }
        let id = UUID(); refreshID = id
        do {
            let currentGeneration = try SharedRoutineStore.makeStore().validateAccess()
            let coordinator = try RhythmNotifications.coordinator(expectedGeneration: currentGeneration)
            preferences = try coordinator.preferences()
            let status = try await coordinator.reconcile()
            guard refreshID == id else { return }
            generation = currentGeneration
            apply(status)
        } catch {
            guard refreshID == id else { return }
            self.error = error.localizedDescription
        }
    }

    func update(_ change: RhythmNotificationPreferenceChange, expectedGeneration: UUID?, enabling: Bool = false) async {
        guard !updating else { return }
        updating = true
        refreshID = UUID()
        defer { updating = false }
        do {
            guard let expectedGeneration else { throw LocalDataError.staleAction }
            _ = try SharedRoutineStore.makeStore(expectedGeneration: expectedGeneration).validateAccess()
            let coordinator = try RhythmNotifications.coordinator(expectedGeneration: expectedGeneration)
            if enabling, await SystemRhythmNotificationClient().authorization() == .notDetermined {
                _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            }
            apply(try await coordinator.update(change))
        } catch {
            // Preferences can be saved before an OS scheduling failure. Show that
            // actual value rather than pretending the user's switch was reverted.
            if let saved = try? RhythmNotifications.coordinator().preferences() { preferences = saved }
            self.error = error.localizedDescription
        }
    }

    private func apply(_ status: RhythmNotificationStatus) {
        preferences = status.preferences
        authorization = status.authorization
        pendingCount = status.pendingCount
        error = nil
    }

    func clearAfterErasure() {
        refreshID = UUID()
        preferences = .init()
        generation = nil
        pendingCount = 0
        error = nil
    }
}

struct NotificationSettingsView: View {
    @ObservedObject private var notifications = NotificationSettingsModel.shared
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            Section {
                Toggle("Timed step reminders", isOn: Binding(
                    get: { notifications.preferences.timedSteps },
                    set: { enabled in
                        let generation = notifications.generation
                        Task { await notifications.update(.timedSteps(enabled), expectedGeneration: generation, enabling: enabled) }
                    }))
            } footer: {
                Text("Remind me at saved due times, including a time set with Later. Date-only steps do not send reminders. Set a due time when creating or editing a step.")
            }
            Section {
                Toggle("Daily Close", isOn: Binding(
                    get: { notifications.preferences.dailyClose },
                    set: { enabled in
                        let generation = notifications.generation
                        Task { await notifications.update(.dailyClose(enabled), expectedGeneration: generation, enabling: enabled) }
                    }))
                if notifications.preferences.dailyClose {
                    DatePicker("Review time", selection: Binding(get: { closeTime }, set: { value in
                        let components = Calendar.current.dateComponents([.hour, .minute], from: value)
                        let generation = notifications.generation
                        Task { await notifications.update(.closeTime(hour: components.hour ?? 20, minute: components.minute ?? 30), expectedGeneration: generation) }
                    }), displayedComponents: .hourAndMinute)
                }
            } footer: {
                Text("A gentle invitation to review your day, with no completion counts in the notification. The review time follows your current timezone when the schedule refreshes.")
            }
            Section("Delivery") {
                switch notifications.authorization {
                case .notDetermined:
                    Text("Choose a reminder above to request notification permission.")
                case .denied:
                    Text("Notifications are turned off in iOS. Your preferences are saved and all habit tracking still works.")
                    Button("Open notification settings") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                    }
                case .authorized:
                    if notifications.error == nil {
                        Text("\(notifications.pendingCount) notifications scheduled")
                    } else {
                        Text("The notification schedule needs a refresh.")
                    }
                    Text("iOS controls delivery, including Focus and notification summaries.")
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Text("Open Daily Rhythm regularly to refresh up to seven days of reminders. Edits, completion and opt-out reconcile the schedule at the next opportunity. Delivery timing is controlled by iOS.")
                Text("Notifications use general wording. Tap one to read the latest saved day or step; tapping never completes it.")
            }
            if let error = notifications.error {
                Section("Notification update needed") {
                    Text(error)
                    Button("Retry") { Task { await notifications.refresh() } }
                }
            }
        }
        .disabled(notifications.updating)
        .overlay { if notifications.updating { ProgressView("Updating notifications…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task { await notifications.refresh() }
    }

    private var closeTime: Date {
        Calendar.current.date(bySettingHour: notifications.preferences.closeHour,
                              minute: notifications.preferences.closeMinute, second: 0, of: Date()) ?? Date()
    }
}

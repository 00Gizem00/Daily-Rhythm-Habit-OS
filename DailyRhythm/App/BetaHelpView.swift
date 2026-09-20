import SwiftUI

struct BetaHelpView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "Version \(info["CFBundleShortVersionString"] as? String ?? "unknown") (\(info["CFBundleVersion"] as? String ?? "unknown"))"
    }

    var body: some View {
        Form {
            Section("Daily Rhythm beta") {
                Text(version).textSelection(.enabled)
                Text("Create a small routine, record a full or light step, and review your saved history. Manual tracking works offline without an account.")
            }
            Section("Send feedback") {
                Text("If you installed Daily Rhythm through TestFlight, open TestFlight, choose Daily Rhythm and tap Send Beta Feedback.")
                Text("Include this version, your iOS version, the steps you tried, what you expected and what happened. Mention whether you used the app, a widget, a Shortcut or Siri.")
                Text("Before sharing a screenshot, check it for private habit names or goals. A routine backup is not needed for an ordinary bug report.")
            }
            Section("Optional pilot report") {
                Text("You can choose to enable local diagnostics in Data & Privacy. They start off and never upload automatically. If you want to share a report with the pilot organizer, export diagnostics JSON and review it first. Declining diagnostics does not limit tracking.")
                NavigationLink("Data & Privacy") { DataPrivacyView() }
            }
            Section("Keep a recovery copy") {
                Text("Before updating a beta, use Export JSON in Data & Privacy and save the file somewhere you control. Keep the app installed during an update. CSV is for reading history and cannot restore a backup.")
                Text("If something fails, keep the app and your data in place and send feedback. Restore accepts a JSON backup only into an empty app. Erase Local Data permanently removes local records; it is not a troubleshooting step.")
            }
            Section("This beta's scope") {
                Text("Cloud sync, AI routine generation, routine-session Live Activities and purchases are not included. Ordinary App Shortcuts are available; Siri availability and system behavior depend on your device and settings.")
                NavigationLink("Widgets & Siri help") { SetupHelpView() }
            }
        }
        .navigationTitle("Help & Beta")
    }
}

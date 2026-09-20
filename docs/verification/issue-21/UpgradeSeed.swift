import DailyRhythmCore
import Foundation

// Copied into the old, disposable Debug app only. Never part of the candidate.
@MainActor enum UpgradeSeed {
    static var started = false
    static func run(model: AppModel, setup: OnboardingPreferences) async {
        guard !started,
              ProcessInfo.processInfo.environment["DAILY_RHYTHM_UPGRADE_SEED"] == "1",
              Bundle.main.bundleIdentifier?.hasPrefix("com.lumetechllc.DailyRhythm.Validation21.") == true else { return }
        started = true
        var result: [String: Any] = ["passed": false]
        do {
            let store = try SharedRoutineStore.makeStore()
            guard try store.habits(includeArchived: true).isEmpty else { throw RoutineStoreError.invalidTitle }
            try store.setPilotDiagnosticsEnabled(true)
            store.recordPilotSetupStarted()
            let now = Date(), key = LocalDay(calendar: .current).key(for: Date())
            let definition = HabitDefinition(title: "Upgrade fixture café ✓", normalTarget: "Two pages", lightTarget: "One line",
                dayPart: .morning, recurrence: .once(dayKey: key))
            let plans = try store.addHabits([definition, definition, definition, definition], now: now)
            for (index, action) in [OccurrenceAction.complete(.full), .complete(.light), .skip].enumerated() {
                _ = try store.perform(action, on: store.occurrence(id: "\(plans[index].id.uuidString)|\(key)"), now: now)
            }
            try store.archive(habitID: plans[0].id, now: now)
            _ = try await RhythmNotifications.coordinator().update(.dailyClose(false))
            setup.finish()
            UserDefaults.standard.set(false, forKey: "dailyRhythm.completionHaptics")
            // The runner terminates immediately after seeding; flush fixture defaults
            // before reporting ready instead of treating delayed OS persistence as loss.
            guard UserDefaults.standard.synchronize() else { throw CocoaError(.fileWriteUnknown) }
            result["hapticPreferenceReadback"] = UserDefaults.standard.object(forKey: "dailyRhythm.completionHaptics")
            result["onboardingValue"] = UserDefaults.standard.data(forKey: "dailyRhythm.onboarding.v1")?.base64EncodedString()
            try store.writeExport(format: .json, to: URL.documentsDirectory.appendingPathComponent("upgrade-backup.json"))
            result["passed"] = true
            result["seed"] = "Four plans; full/light/skipped/pending; archived plan; diagnostics; reminder preferences; completed setup; haptic preference; JSON backup"
        } catch { result["error"] = error.localizedDescription }
        try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL.documentsDirectory.appendingPathComponent("upgrade-seed-result.json"), options: .atomic)
    }
}

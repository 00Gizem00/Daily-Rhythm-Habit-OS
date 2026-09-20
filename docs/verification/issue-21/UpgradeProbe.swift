import DailyRhythmCore
import Foundation

// Read-only probe copied into the isolated Release test app, not the archive.
@MainActor enum UpgradeProbe {
    static var started = false
    static func run() {
        guard !started, ProcessInfo.processInfo.environment["DAILY_RHYTHM_UPGRADE_PROBE"] == "1",
              Bundle.main.bundleIdentifier?.hasPrefix("com.lumetechllc.DailyRhythm.Validation21.") == true else { return }
        started = true
        var report: [String: Any] = [:]
        report["hapticPreferenceReadback"] = UserDefaults.standard.object(forKey: "dailyRhythm.completionHaptics")
        report["onboardingValue"] = UserDefaults.standard.data(forKey: "dailyRhythm.onboarding.v1")?.base64EncodedString()
        report["planCount"] = try? SharedRoutineStore.makeStore().habits(includeArchived: true).count
        try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL.documentsDirectory.appendingPathComponent("upgrade-probe-result.json"), options: .atomic)
    }
}

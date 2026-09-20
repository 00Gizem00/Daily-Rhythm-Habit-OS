import Foundation
import DailyRhythmCore
import UserNotifications
import UIKit

// Disposable simulator-only fixture. It never targets the product's bundle/group.
@MainActor enum PrivacyValidation {
    static var started = false
    static func run(model: AppModel, setup: OnboardingPreferences) async {
        guard !started, ProcessInfo.processInfo.environment["DAILY_RHYTHM_PRIVACY_VALIDATION"] == "1" else { return }
        started = true
        guard Bundle.main.bundleIdentifier?.hasPrefix("com.lumetechllc.DailyRhythm.Validation15.") == true else { return }
        var report: [String: Any] = ["passed": false, "environment": UIDevice.current.systemVersion,
            "execution": "Application models and real iOS services; no UI event injection or share-sheet interaction"]
        var checks: [String] = []
        func check(_ condition: Bool, _ label: String) throws {
            guard condition else { throw NSError(domain: "PrivacyValidation", code: 1, userInfo: [NSLocalizedDescriptionKey: label]) }
            checks.append(label)
        }
        let output = URL.documentsDirectory.appendingPathComponent("privacy-validation-result.json")
        do {
            let store = try SharedRoutineStore.makeStore()
            try check(try store.habits(includeArchived: true).isEmpty, "isolated store starts empty")
            let now = Date()
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .current
            let parts = calendar.dateComponents([.year, .month, .day], from: now)
            let day = String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
            let definition = HabitDefinition(title: "Validation, \"read\" café", normalTarget: "=2+2", lightTarget: "One page", dayPart: .morning, recurrence: .once(dayKey: day))
            let habits = try store.addHabits([definition, definition, definition], now: now)
            for (index, action) in [OccurrenceAction.complete(.full), .complete(.light), .skip].enumerated() {
                _ = try store.perform(action, on: store.occurrence(id: "\(habits[index].id.uuidString)|\(day)"), now: now)
            }
            try store.archive(habitID: habits[0].id, now: now)
            model.refresh()
            let before = try Data(contentsOf: store.fileURL)
            let privacy = DataPrivacyModel.shared
            privacy.export(.json)
            guard let jsonShare = privacy.share else { throw NSError(domain: "PrivacyValidation", code: 2, userInfo: [NSLocalizedDescriptionKey: privacy.error ?? "No JSON export"]) }
            let json = try Data(contentsOf: jsonShare.url)
            let backup = try RoutineBackup(jsonExport: json)
            try check(backup.planCount == 3 && backup.recordCount == 3, "JSON includes archived plan and all three outcomes")
            privacy.endShare(url: jsonShare.url, completed: false, failure: nil)
            try check(!FileManager.default.fileExists(atPath: jsonShare.url.path), "share cancellation callback removes staged export")
            privacy.export(.csv)
            let csvURL = privacy.share!.url
            let csv = try String(contentsOf: csvURL, encoding: .utf8)
            try check(["\"full\"", "\"light\"", "\"skipped\"", "\"'=2+2\"", "\"\"read\"\""].allSatisfy { csv.contains($0) }, "CSV contains all outcomes and escapes quotes/formulas")
            privacy.share = nil // SwiftUI's binding clears before onDismiss.
            privacy.dismissShare()
            try check(!FileManager.default.fileExists(atPath: csvURL.path), "dismissal callback removes export after cleared sheet binding")
            privacy.export(.json)
            let failedShare = privacy.share!.url
            privacy.endShare(url: failedShare, completed: false, failure: "Fixture share failure")
            try check(privacy.error?.contains("Fixture share failure") == true, "share failure is surfaced")
            try check(try Data(contentsOf: store.fileURL) == before, "export and cancellation preserve store bytes")
            privacy.error = nil
            let keptBackup = URL.documentsDirectory.appendingPathComponent("validation-kept-backup.json")
            try json.write(to: keptBackup, options: .atomic)
            privacy.prepareRestore(from: keptBackup)
            try check(privacy.restorePreview?.backup.planCount == 3, "restore preview validates file and counts")
            privacy.restorePreview = nil
            try check(try Data(contentsOf: store.fileURL) == before, "restore preview cancellation preserves store bytes")
            privacy.prepareRestore(from: keptBackup)
            do {
                try privacy.restore(privacy.restorePreview!, model: model, setup: setup)
                throw NSError(domain: "PrivacyValidation", code: 3, userInfo: [NSLocalizedDescriptionKey: "restore overwrote populated store"])
            } catch LocalDataError.restoreRequiresEmptyStore { checks.append("restore refuses populated store") }
            privacy.restorePreview = nil
            let oldGeneration = try store.validateAccess()
            setup.choose(.morning)
            let oldDraft = setup.progress.draft!
            _ = try await RhythmNotifications.coordinator().update(.dailyClose(false))
            let preferences = try SharedRoutineStore.containerURL().appendingPathComponent("notification-preferences.json")
            try check(FileManager.default.fileExists(atPath: preferences.path), "real notification coordinator persists fixture preferences")
            let diagnostic = URL.documentsDirectory.appendingPathComponent("schema-smoke-\(UUID().uuidString).json")
            try store.writeAuxiliaryData(Data("fixture".utf8), to: diagnostic)
            for version in [1, 2] { try before.write(to: store.migrationBackupURL(from: version)) }
            let lockURL = store.fileURL.appendingPathExtension("lock")
            let inode = try FileManager.default.attributesOfItem(atPath: lockURL.path)[.systemFileNumber] as! NSNumber
            await privacy.erase(expectedGeneration: oldGeneration, model: model, setup: setup)
            try check(privacy.error == nil, "erase through real notification/search services succeeds: \(privacy.error ?? "none")")
            try check(!privacy.erasurePending && !privacy.busy, "erase completes recovery marker and busy state")
            try check(!FileManager.default.fileExists(atPath: store.fileURL.path), "erase removes main document")
            try check(!FileManager.default.fileExists(atPath: preferences.path), "erase removes reminder preferences")
            try check(!FileManager.default.fileExists(atPath: diagnostic.path), "erase removes owned diagnostics")
            try check(try FileManager.default.attributesOfItem(atPath: lockURL.path)[.systemFileNumber] as? NSNumber == inode, "erase keeps stable lock inode")
            for version in [1, 2] { try check(!FileManager.default.fileExists(atPath: store.migrationBackupURL(from: version).path), "erase removes v\(version) backup") }
            try check(setup.progress.draft == nil && UserDefaults.standard.data(forKey: "dailyRhythm.onboarding.v1") == nil, "erase clears setup draft and defaults")
            try check(model.habits.isEmpty && model.lastUndo == nil, "erase clears app caches and undo")
            let client = SystemRhythmNotificationClient()
            let pending = await client.pending(), delivered = await client.deliveredIDs()
            try check(pending.isEmpty && delivered.isEmpty, "actual simulator notification queues are empty")
            do { _ = try store.addHabit(definition); throw NSError(domain: "PrivacyValidation", code: 4) }
            catch LocalDataError.staleAction { checks.append("old store cannot recreate data") }
            do { _ = try SharedRoutineStore.makeStore().createInitialRoutine(oldDraft); throw NSError(domain: "PrivacyValidation", code: 5) }
            catch LocalDataError.staleAction { checks.append("old onboarding draft cannot recreate data") }
            privacy.prepareRestore(from: keptBackup)
            let preview = privacy.restorePreview!
            try privacy.restore(preview, model: model, setup: setup)
            try check(try SharedRoutineStore.makeStore().matchesRestoredBackup(preview.backup), "restored disk snapshot matches every expected field")
            try check(model.habits.count == 3, "restored app model includes all plans")
            try check(privacy.notice?.hasPrefix("Restored 3 plans and 3 saved records") == true, "restore success is reported")
            let corrupt = URL.documentsDirectory.appendingPathComponent("validation-corrupt.json")
            try Data("not JSON".utf8).write(to: corrupt)
            let restoredBytes = try Data(contentsOf: store.fileURL)
            privacy.prepareRestore(from: keptBackup)
            try check(privacy.restorePreview != nil, "second valid file prepares a new preview")
            privacy.prepareRestore(from: corrupt)
            try check(privacy.error != nil && privacy.restorePreview == nil, "corrupt restore is refused")
            try check(try Data(contentsOf: store.fileURL) == restoredBytes, "corrupt restore preserves restored data")
            privacy.prepareRestore(from: keptBackup)
            try check(privacy.restorePreview != nil && privacy.error == nil, "successful retry clears obsolete restore error")
            privacy.restorePreview = nil
            privacy.notice = nil
            report["passed"] = true
        } catch { report["error"] = error.localizedDescription }
        report["checks"] = checks
        try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output, options: .atomic)
    }
}

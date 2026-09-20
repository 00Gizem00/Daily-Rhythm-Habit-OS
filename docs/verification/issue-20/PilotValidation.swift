import DailyRhythmCore
import Foundation
import UIKit

// Disposable app/group only. Calls real models/adapters; does not drive system UI.
@MainActor enum PilotValidation {
    static var started = false
    static func run(model: AppModel, setup: OnboardingPreferences) async {
        guard !started, ProcessInfo.processInfo.environment["DAILY_RHYTHM_DIAGNOSTICS_VALIDATION"] == "1",
              Bundle.main.bundleIdentifier?.hasPrefix("com.lumetechllc.DailyRhythm.Validation20.") == true else { return }
        started = true
        var report: [String: Any] = ["passed": false, "environment": UIDevice.current.systemVersion,
            "execution": "Real app models and direct App Intent adapters in isolated app; no VoiceOver, system dispatch or share-sheet interaction"]
        var checks: [String] = []
        func check(_ value: Bool, _ label: String) throws {
            guard value else { throw NSError(domain: "PilotValidation", code: 1, userInfo: [NSLocalizedDescriptionKey: label]) }
            checks.append(label)
        }
        do {
            let store = try SharedRoutineStore.makeStore()
            let privacy = DataPrivacyModel.shared
            privacy.refresh(); model.refresh()
            try check(privacy.diagnostics?.enabled == false, "diagnostics default to off")
            privacy.exportDiagnostics()
            try check(privacy.share == nil && privacy.error != nil, "disabled export fails visibly without a share item")
            privacy.error = nil
            privacy.setDiagnosticsEnabled(true)
            try check(privacy.diagnostics?.enabled == true && privacy.diagnosticsError == nil, "explicit opt-in starts observation")
            setup.begin()
            let key = LocalDay(calendar: .current).key(for: Date())
            let definition = HabitDefinition(title: "Private fixture routine", normalTarget: "Private fixture goal", lightTarget: "Private fixture light",
                                             dayPart: .morning, recurrence: .once(dayKey: key))
            for _ in 0..<4 { try check(model.addHabit(definition, expectedGeneration: model.dataGeneration), "fixture one-off created") }
            let steps = model.today!.occurrences
            model.complete(steps[0], outcome: .full)
            try check(model.operationError == nil && model.today?.fullCount == 1, "app completion succeeds with diagnostics enabled")
            model.complete(steps[0], outcome: .full)
            try check(model.operationError != nil, "repeated stale app action is refused")
            model.operationError = nil
            let widget = CompleteWidgetOccurrenceIntent(occurrence: steps[1], useSmallStep: true)
            _ = try await widget.perform()
            var intent = CompleteOccurrenceIntent()
            intent.occurrence = RhythmOccurrenceEntity(steps[2])
            intent.useSmallStep = false
            _ = try await intent.perform()
            _ = try await intent.perform() // Adapter's idempotent repeated invocation.
            try store.complete(occurrenceID: steps[3].id, source: nil)
            model.refresh()
            let bytes = try store.pilotDiagnosticsExport()
            let exported = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
            let days = exported["days"] as! [[String: Any]]
            let sources = days[0]["sources"] as! [String: Int]
            try check(sources == ["app": 1, "widget": 1, "appIntent": 1, "unknown": 1], "app/widget/intent/unknown counts each represent one first saved completion")
            try check(exported["setupStartCaptured"] as? Bool == true && exported["setupToFirstCompletionSeconds"] != nil, "setup timing is captured after opt-in")
            let failures = exported["failures"] as! [[String: Any]]
            try check(failures.contains { $0["surface"] as? String == "app" && $0["category"] as? String == "staleAction" }, "app failure exports a category without error text")
            let text = String(decoding: bytes, as: UTF8.self)
            try check(!text.contains("Private fixture") && !text.contains(steps[0].habitID.uuidString) && !text.contains("timeZoneIdentifier"), "export omits routine content, local IDs and timezone identifier")
            try check(exported["day7"] as? String == "awaiting" && exported["day14"] as? String == "awaiting", "future checkpoints are awaiting, not failures or successes")
            let routineBytes = try Data(contentsOf: store.fileURL)
            let diagnosticBytes = try Data(contentsOf: store.diagnosticsURL)
            privacy.exportDiagnostics()
            guard let share = privacy.share else { throw NSError(domain: "PilotValidation", code: 2) }
            try check(try Data(contentsOf: share.url) == bytes, "actual staged diagnostic file matches the aggregate export")
            privacy.endShare(url: share.url, completed: false, failure: nil)
            try check(!FileManager.default.fileExists(atPath: share.url.path), "share cancellation cleans its diagnostic file")
            privacy.exportDiagnostics()
            let failedShare = privacy.share!.url
            privacy.endShare(url: failedShare, completed: false, failure: "Fixture delivery failure")
            try check(privacy.error != nil && !FileManager.default.fileExists(atPath: failedShare.path), "share failure surfaces error and cleans its diagnostic file")
            try check(try Data(contentsOf: store.fileURL) == routineBytes && Data(contentsOf: store.diagnosticsURL) == diagnosticBytes,
                      "export/share cancellation and failure preserve both stores")
            privacy.setDiagnosticsEnabled(false)
            store.recordPilotFailure(.validation, surface: .app)
            try check(privacy.diagnostics?.enabled == false && !FileManager.default.fileExists(atPath: store.diagnosticsURL.path), "opt-out deletes observation and does not recreate it on failures")
            privacy.setDiagnosticsEnabled(true)
            let baseline = try JSONSerialization.jsonObject(with: store.pilotDiagnosticsExport()) as! [String: Any]
            try check((baseline["days"] as? [Any])?.isEmpty == true, "new opt-in treats prior completions as baseline")
            try Data("invalid fixture diagnostics".utf8).write(to: store.diagnosticsURL)
            privacy.refresh()
            try check(privacy.diagnosticsError != nil, "unreadable diagnostics show a recoverable diagnostics error")
            model.reopen(model.today!.occurrences[0])
            model.complete(model.today!.occurrences.first { $0.id == steps[0].id }!, outcome: .full)
            try check(model.operationError == nil, "unreadable diagnostics never fail a committed app completion")
            privacy.setDiagnosticsEnabled(false)
            privacy.setDiagnosticsEnabled(true)
            try check(privacy.diagnostics?.enabled == true && privacy.diagnosticsError == nil, "clear and restart repairs diagnostics without touching habits")
            privacy.error = nil
            await privacy.erase(expectedGeneration: try store.validateAccess(), model: model, setup: setup)
            try check(privacy.error == nil && !privacy.erasurePending, "real app erase completes all service hooks")
            try check(privacy.diagnostics?.enabled == false && !FileManager.default.fileExists(atPath: store.diagnosticsURL.path), "erase removes pilot diagnostics and opt-in")
            store.recordPilotFailure(.validation, surface: .app)
            store.recordPilotSetupStarted()
            try check(!FileManager.default.fileExists(atPath: store.diagnosticsURL.path), "pre-erase diagnostic writers cannot recreate observation")
            try check(model.addHabit(definition, expectedGeneration: model.dataGeneration), "fresh generation remains usable with diagnostics off")
            setup.finish(); privacy.notice = nil
            report["sampleExport"] = exported
            report["passed"] = true
        } catch { report["error"] = error.localizedDescription }
        report["checks"] = checks
        let output = URL.documentsDirectory.appendingPathComponent("diagnostics-validation-result.json")
        try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output, options: .atomic)
    }
}

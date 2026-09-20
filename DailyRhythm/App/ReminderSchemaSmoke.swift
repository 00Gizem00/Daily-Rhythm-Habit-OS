#if DEBUG && DAILY_RHYTHM_SCHEMA_SPIKE && compiler(>=6.4)
import AppIntents
import DailyRhythmCore
import Foundation
import UIKit
import WidgetKit

/// Explicit developer invocation only. Calls the real gated adapters on the device,
/// not Siri or Shortcuts, and reports that distinction. It never edits existing plans.
@available(iOS 27.0, *)
@MainActor
enum ReminderSchemaSmoke {
    private static var started = false

    static func runIfRequested() async {
        guard !started, let request = ProcessInfo.processInfo.environment["DAILY_RHYTHM_SCHEMA_SMOKE"],
              let runID = UUID(uuidString: request) else { return }
        started = true
        let reportURL = URL.documentsDirectory.appendingPathComponent("schema-smoke-\(runID.uuidString).json")
        guard !FileManager.default.fileExists(atPath: reportURL.path) else { return }
        var report: [String: Any] = [
            "runID": runID.uuidString, "startedAt": ISO8601DateFormatter().string(from: Date()),
            "execution": "Direct calls to the actual schema intent perform methods; not a Siri invocation",
            "systemVersion": UIDevice.current.systemVersion, "deviceModel": UIDevice.current.model,
            "deviceLocale": Locale.current.identifier, "preferredLanguages": Locale.preferredLanguages,
            "siriLanguage": "Unverified", "siriAIState": "Unverified", "passed": false
        ]
        func writeReport() throws {
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: reportURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        var testHabitID: UUID?
        do {
            try writeReport() // A repeated launch cannot create a second test item for the same run ID.
            let store = try SharedRoutineStore.makeStore()
            let before = try store.habits(includeArchived: true)
            let earlierSteps = try before.flatMap { try store.managedOccurrences(habitID: $0.id) }
            let create = CreateRhythmSchemaReminder()
            create.title = "Schema validation \(runID.uuidString.prefix(8))"
            create.dueDate = nil
            create.recurrence = nil
            create.list = .appList
            create.note = nil
            create.isFlagged = nil
            create.images = []
            create.tags = []
            create.urls = []
            create.section = nil
            create.locationTrigger = nil
            guard let entity = try await create.perform().value else { throw SmokeFailure.failed("Create returned no entity") }
            let created = try store.occurrence(id: entity.id)
            testHabitID = created.habitID
            report["occurrenceID"] = entity.id
            guard created.outcome == nil, created.title == create.title else { throw SmokeFailure.failed("Create snapshot mismatch") }
            report["create"] = true

            let update = UpdateRhythmSchemaReminder()
            update.target = entity
            update.isCompleted = true
            _ = try await update.perform()
            let completed = try SharedRoutineStore.makeStore().occurrence(id: entity.id)
            guard completed.outcome == .full, completed.completedAt != nil, completed.completionSource == .appIntent
            else { throw SmokeFailure.failed("Completion was not persisted") }
            _ = try await update.perform()
            guard try SharedRoutineStore.makeStore().occurrence(id: entity.id) == completed
            else { throw SmokeFailure.failed("Repeated completion rewrote the record") }
            report["updateComplete"] = true
            report["repeatedCompletionUnchanged"] = true
            update.isCompleted = false
            _ = try await update.perform()
            let reopened = try SharedRoutineStore.makeStore().occurrence(id: entity.id)
            guard reopened.outcome == nil, reopened.completedAt == nil, reopened.id == created.id
            else { throw SmokeFailure.failed("Reopen was not persisted") }
            report["updateReopen"] = true

            // Reversible cleanup through the normal API, scoped to this newly created test item.
            try store.archive(habitID: created.habitID)
            WidgetCenter.shared.reloadTimelines(ofKind: SharedRoutineStore.widgetKind)
            report["testItemArchived"] = true
            let oldIDs = Set(before.map(\.id))
            guard try store.habits(includeArchived: true).filter({ oldIDs.contains($0.id) }) == before,
                  try before.flatMap({ try store.managedOccurrences(habitID: $0.id) }) == earlierSteps
            else { throw SmokeFailure.failed("Pre-existing plans or results changed") }
            report["preExistingPlansAndResultsUnchanged"] = true
            report["passed"] = true
        } catch {
            report["error"] = error.localizedDescription
            if let testHabitID {
                do {
                    try SharedRoutineStore.makeStore().archive(habitID: testHabitID)
                    WidgetCenter.shared.reloadTimelines(ofKind: SharedRoutineStore.widgetKind)
                    report["testItemArchived"] = true
                }
                catch { report["cleanupError"] = error.localizedDescription }
            }
        }
        report["finishedAt"] = ISO8601DateFormatter().string(from: Date())
        do { try writeReport() }
        catch { print("Schema validation report could not be saved: \(error.localizedDescription)") }
    }
}

private enum SmokeFailure: LocalizedError {
    case failed(String)
    var errorDescription: String? { switch self { case .failed(let message): message } }
}
#endif

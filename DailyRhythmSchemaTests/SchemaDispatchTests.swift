import AppIntentsTesting
import AppIntents
import Foundation
import XCTest

/// App Intents infrastructure only: no synthetic Siri speech or UI event injection.
/// Requires the opt-in schema build installed on an explicitly selected iOS 27 device.
final class SchemaDispatchTests: XCTestCase {
    private let definitions = IntentDefinitions(bundleIdentifier: "com.lumetechllc.DailyRhythm")

    func testSchemaListDiscoveryThroughSystem() async throws {
        let lists = try await definitions.entities["RhythmReminderList"].entities(matching: "Daily Rhythm")
        XCTAssertEqual(lists.count, 1)
        let name: String = try XCTUnwrap(lists.first).name
        XCTAssertEqual(name, "Daily Rhythm")
    }

    func testCreateCompleteRepeatAndReopenThroughSystem() async throws {
        try await runReminderFlow(flag: nil)
    }

    func testExplicitFalseFlagRepresentsAnUnflaggedReminder() async throws {
        try await runReminderFlow(flag: false)
    }

    func testTrueFlagIsRejectedWithoutCreatingATask() async throws {
        let runID = UUID().uuidString
        let title = "Schema dispatch \(runID)"
        do {
            do {
                try await definitions.intents["CreateRhythmSchemaReminder"]
                    .makeIntent(title: title, isFlagged: true, images: [IntentFile](), tags: [String](), urls: [URL]())
                    .run()
                XCTFail("Flagged reminders are unsupported and must not be created")
            } catch {
                XCTAssertEqual((error as NSError).domain, "DailyRhythmCore.ReminderMappingError")
                XCTAssertTrue(error.localizedDescription.contains("No task was created"))
            }
            let results = try await definitions.entities["RhythmSchemaReminder"].entities(matching: title)
            XCTAssertTrue(results.isEmpty)
        } catch let originalError {
            do { try await cleanup(runID) }
            catch { XCTFail("Fixture cleanup failed: \(error)") }
            throw originalError
        }
        try await cleanup(runID)
    }

    private func runReminderFlow(flag: Bool?) async throws {
        let runID = UUID().uuidString
        let title = "Schema dispatch \(runID)"
        do {
            let created = try await definitions.intents["CreateRhythmSchemaReminder"]
                .makeIntent(title: title, isFlagged: flag, images: [IntentFile](), tags: [String](), urls: [URL]())
                .run()
            let entity: AnyAppEntity = try created.value
            let createdTitle: String = try entity.title
            XCTAssertEqual(createdTitle, title)
            let queried = try await definitions.entities["RhythmSchemaReminder"].entities(matching: title)
            XCTAssertEqual(queried.count, 1)
            XCTAssertEqual(queried.first?.identifier.instanceIdentifier, entity.identifier.instanceIdentifier)
            try await assertIndexed(entity, title: title, present: true)

            let update = definitions.intents["UpdateRhythmSchemaReminder"]
            let completed = try await update.makeIntent(target: entity, isCompleted: true).run()
            let completedEntity: AnyAppEntity = try completed.value
            let isCompleted: Bool = try completedEntity.isCompleted
            let firstDate: Date = try completedEntity.completionDate
            XCTAssertTrue(isCompleted)
            XCTAssertEqual(completedEntity.identifier.instanceIdentifier, entity.identifier.instanceIdentifier)

            let repeated = try await update.makeIntent(target: entity, isCompleted: true).run()
            let secondDate: Date = try repeated.value.completionDate
            XCTAssertEqual(secondDate, firstDate)

            let reopened = try await update.makeIntent(target: entity, isCompleted: false).run()
            let reopenedEntity: AnyAppEntity = try reopened.value
            let reopenedCompleted: Bool = try reopenedEntity.isCompleted
            XCTAssertFalse(reopenedCompleted)
            XCTAssertEqual(reopenedEntity.identifier.instanceIdentifier, entity.identifier.instanceIdentifier)
            try await cleanup(runID)
            let archivedResults = try await definitions.entities["RhythmSchemaReminder"].entities(matching: title)
            XCTAssertTrue(archivedResults.isEmpty)
            try await assertIndexed(entity, title: title, present: false)
        } catch let originalError {
            do { try await cleanup(runID) }
            catch { XCTFail("Fixture cleanup failed: \(error)") }
            throw originalError
        }
    }

    private func assertIndexed(_ entity: AnyAppEntity, title: String, present: Bool) async throws {
        for attempt in 0..<20 {
            let results = try await definitions.entities["RhythmSchemaReminder"].spotlightQuery(title)
            let found = results.contains { $0.identifier.instanceIdentifier == entity.identifier.instanceIdentifier }
            if found == present { return }
            if attempt < 19 { try await Task.sleep(for: .milliseconds(250)) }
        }
        XCTFail(present ? "Saved reminder was not indexed" : "Archived reminder remained indexed")
    }

    private func cleanup(_ runID: String) async throws {
        try await definitions.intents["ArchiveSchemaDispatchTestIntent"].makeIntent(runID: runID).run()
    }
}

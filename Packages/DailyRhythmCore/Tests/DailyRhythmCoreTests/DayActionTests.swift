import Foundation
import XCTest
@testable import DailyRhythmCore

final class DayActionTests: XCTestCase {
    func testFullLightSkipAndPendingRemainDistinctAfterReloadAndArchive() throws {
        let f = try DayFixture(); defer { f.remove() }
        let items = try (0..<4).map { try f.add(title: "Step \($0)", once: true) }
        _ = try f.store.perform(.complete(.full), on: items[0], now: f.now)
        _ = try f.store.perform(.complete(.light), on: items[1], source: .widget, now: f.now)
        _ = try f.store.perform(.skip, on: items[2], now: f.now)
        let fresh = RoutineStore(fileURL: f.url, calendar: f.calendar)
        let summary = try fresh.summary(for: f.now)
        XCTAssertEqual([summary.fullCount, summary.lightCount, summary.skippedCount, summary.remainingCount], [1, 1, 1, 1])
        XCTAssertEqual(summary.completedCount, 2)
        let skipped = try fresh.occurrence(id: items[2].id)
        XCTAssertNil(skipped.completedAt)
        XCTAssertEqual(skipped.skippedAt, f.now)
        XCTAssertFalse(skipped.isCompleted)
        XCTAssertFalse(skipped.canComplete(at: f.now, calendar: f.calendar))
        try fresh.complete(occurrenceID: skipped.id, now: f.now) // repeated writer cannot overwrite skip
        try fresh.archive(habitID: skipped.habitID, now: f.now)
        XCTAssertEqual(try fresh.summary(for: f.now).skippedCount, 1)
        XCTAssertEqual(try fresh.history(days: 1, endingOn: f.now)[0].completedCount, 2)
    }

    func testUndoRestoresOriginalDueAndTargetsExactlyOnce() throws {
        let f = try DayFixture(); defer { f.remove() }
        let before = try f.add()
        let token = try f.store.perform(.later(until: f.now.addingTimeInterval(3600), timeZoneIdentifier: "UTC"), on: before, now: f.now)
        try f.store.undo(token, now: f.now)
        var restored = try f.store.occurrence(id: before.id)
        XCTAssertNotEqual(restored.revision, before.revision)
        restored.mutationID = before.mutationID
        XCTAssertEqual(restored, before)
        expect(.staleAction) { try f.store.undo(token, now: f.now) }
    }

    func testStaleUndoCannotEraseNewCompletionOrABARevision() throws {
        let f = try DayFixture(); defer { f.remove() }
        let initial = try f.add()
        let oldUndo = try f.store.perform(.complete(.light), on: initial, now: f.now)
        let recorded = try f.store.occurrence(id: initial.id)
        _ = try f.store.perform(.reopen, on: recorded, now: f.now)
        let pending = try f.store.occurrence(id: initial.id)
        _ = try f.store.perform(.complete(.light), on: pending, now: f.now)
        let latest = try f.store.occurrence(id: initial.id)
        XCTAssertEqual(latest.completedAt, recorded.completedAt) // even identical result and timestamp differ in revision
        XCTAssertNotEqual(latest.revision, recorded.revision)
        expect(.staleAction) { try f.store.undo(oldUndo, now: f.now) }
        expect(.staleAction) { try f.store.reopen(occurrenceID: initial.id, expectedRevision: recorded.revision, now: f.now) }
        XCTAssertEqual(try f.store.occurrence(id: initial.id), latest)
    }

    func testAllOutcomeTransitionsAndUndoReopenPreserveSkipTimestamp() throws {
        let f = try DayFixture(); defer { f.remove() }
        let initial = try f.add()
        for action in [OccurrenceAction.complete(.full), .complete(.light), .skip] {
            let pending = try f.store.occurrence(id: initial.id)
            let undo = try f.store.perform(action, on: pending, now: f.now)
            let resolved = try f.store.occurrence(id: initial.id)
            let reopenUndo = try f.store.perform(.reopen, on: resolved, now: f.now)
            try f.store.undo(reopenUndo, now: f.now)
            let restored = try f.store.occurrence(id: initial.id)
            XCTAssertEqual(restored.outcome, resolved.outcome)
            XCTAssertEqual(restored.completedAt, resolved.completedAt)
            XCTAssertEqual(restored.skippedAt, resolved.skippedAt)
            expect(.staleAction) { try f.store.undo(undo, now: f.now) }
            try f.store.reopen(occurrenceID: initial.id, expectedRevision: restored.revision, now: f.now)
        }
    }

    func testCompetingActionsAndConcurrentUndoHaveOnlyOneWinner() throws {
        let f = try DayFixture(); defer { f.remove() }
        let initial = try f.add(), url = f.url, calendar = f.calendar, now = f.now
        let results = ActionResults()
        DispatchQueue.concurrentPerform(iterations: 20) { index in
            do {
                let store = RoutineStore(fileURL: url, calendar: calendar)
                let action: OccurrenceAction = index.isMultiple(of: 2) ? .skip : .complete(.full)
                results.success(try store.perform(action, on: initial, now: now))
            } catch { results.failure(error) }
        }
        XCTAssertEqual(results.tokens.count, 1)
        XCTAssertEqual(results.errors, Array(repeating: .staleAction, count: 19))
        let token = try XCTUnwrap(results.tokens.first), undos = ActionResults()
        DispatchQueue.concurrentPerform(iterations: 20) { _ in
            do {
                try RoutineStore(fileURL: url, calendar: calendar).undo(token, now: now)
                undos.success(token)
            } catch { undos.failure(error) }
        }
        XCTAssertEqual(undos.tokens.count, 1)
        XCTAssertEqual(undos.errors, Array(repeating: .staleAction, count: 19))
        XCTAssertNil(try f.store.occurrence(id: initial.id).outcome)
    }

    func testLaterMovesExactOccurrenceAndResumesAtDeadlineWithStableTies() throws {
        let f = try DayFixture(); defer { f.remove() }
        _ = try f.add(title: "A"); _ = try f.add(title: "B"); _ = try f.add(title: "C")
        let agenda = try f.store.agenda(at: f.now)
        XCTAssertEqual(agenda.occurrences.map(\.id), agenda.occurrences.map(\.id).sorted())
        let first = try XCTUnwrap(agenda.next(at: f.now, calendar: f.calendar))
        let due = f.now.addingTimeInterval(3600)
        _ = try f.store.perform(.later(until: due, timeZoneIdentifier: "UTC"), on: first, now: f.now)
        let waiting = try f.store.agenda(at: f.now)
        XCTAssertEqual(waiting.occurrences.last?.id, first.id)
        XCTAssertNotEqual(waiting.next(at: f.now, calendar: f.calendar)?.id, first.id)
        let delayed = try f.store.occurrence(id: first.id)
        XCTAssertEqual(delayed.dayKey, first.dayKey)
        XCTAssertEqual(delayed.normalTarget, first.normalTarget)
        XCTAssertEqual(delayed.due.instant, due)
        XCTAssertFalse(delayed.isReady(at: due.addingTimeInterval(-1), calendar: f.calendar))
        XCTAssertTrue(delayed.isReady(at: due, calendar: f.calendar))
        let fresh = RoutineStore(fileURL: f.url, calendar: f.calendar)
        XCTAssertEqual(try fresh.agenda(at: f.now), waiting)
    }

    func testSavedDueTimePrecedesDayPartAndDayPartBreaksEqualInstants() throws {
        let f = try DayFixture(); defer { f.remove() }
        let morning = try f.add(title: "Morning", part: .morning)
        let evening = try f.add(title: "Evening", part: .evening)
        try f.store.rescheduleOccurrence(occurrenceID: evening.id, due: .timed(at: date("2026-09-20T08:00:00Z"), timeZoneIdentifier: "UTC"), now: f.now)
        XCTAssertEqual(try f.store.agenda(at: f.now).occurrences.map(\.id), [evening.id, morning.id])
        try f.store.rescheduleOccurrence(occurrenceID: evening.id, due: .timed(at: date("2026-09-20T09:00:00Z"), timeZoneIdentifier: "UTC"), now: f.now)
        XCTAssertEqual(try f.store.agenda(at: f.now).occurrences.map(\.id), [morning.id, evening.id])
    }

    func testMidnightDeferralKeepsIdentityHistoryAndRejectsOrdinaryStaleTodayAction() throws {
        let f = try DayFixture(); defer { f.remove() }
        let deferred = try f.add(title: "Deferred"), ordinary = try f.add(title: "Ordinary")
        let late = date("2026-09-20T23:30:00Z"), until = date("2026-09-21T00:30:00Z")
        _ = try f.store.perform(.later(until: until, timeZoneIdentifier: "UTC"), on: deferred, now: late)
        let midnight = try f.store.agenda(at: date("2026-09-21T00:00:00Z"))
        XCTAssertTrue(midnight.occurrences.contains { $0.id == deferred.id })
        XCTAssertFalse(midnight.occurrences.contains { $0.id == ordinary.id })
        expect(.staleAction) {
            _ = try f.store.perform(.complete(.full), on: ordinary, requiringAgenda: true, now: until)
        }
        let carried = try f.store.occurrence(id: deferred.id)
        _ = try f.store.perform(.complete(.light), on: carried, requiringAgenda: true, now: until)
        XCTAssertEqual(try f.store.summary(for: f.now).lightCount, 1)
        XCTAssertEqual(try f.store.summary(for: until).completedCount, 0)
        XCTAssertEqual(try f.store.summary(for: until).totalCount, 2)
        XCTAssertTrue(try f.store.agenda(at: until).occurrences.contains { $0.id == deferred.id && $0.isCompleted })
    }

    func testTimezoneTravelAndDSTUseTheSavedDeferralInstant() throws {
        let f = try DayFixture(); defer { f.remove() }
        let initial = try f.add()
        let until = date("2026-09-21T00:30:00Z")
        _ = try f.store.perform(.later(until: until, timeZoneIdentifier: "Asia/Tokyo"), on: initial, now: f.now)
        var la = f.calendar; la.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let travelStore = RoutineStore(fileURL: f.url, calendar: la)
        let saved = try travelStore.occurrence(id: initial.id)
        XCTAssertFalse(saved.isReady(at: until.addingTimeInterval(-1), calendar: la))
        XCTAssertTrue(saved.isReady(at: until, calendar: la))
        XCTAssertEqual(saved.due.dayKey(calendar: la), "2026-09-21")
        let nearFold = date("2026-11-01T08:30:00Z")
        let folded = try travelStore.addHabit(title: "Fold", normalTarget: "Walk", dayPart: .morning, now: nearFold)
        let occurrence = try travelStore.occurrence(id: "\(folded.id)|2026-11-01")
        _ = try travelStore.perform(.later(until: nearFold.addingTimeInterval(3600), timeZoneIdentifier: "America/Los_Angeles"), on: occurrence, now: nearFold)
        let postponed = try travelStore.occurrence(id: occurrence.id)
        XCTAssertEqual(postponed.deferredUntil, date("2026-11-01T09:30:00Z"))
        XCTAssertFalse(postponed.isReady(at: nearFold, calendar: la))
    }

    func testLightDayIsExplicitDayScopedAndNeverInventsOrChangesTargets() throws {
        let f = try DayFixture(); defer { f.remove() }
        let small = try f.add(), missing = try f.add(title: "No small target", light: nil)
        let habits = try f.store.habits(asOf: f.now), summary = try f.store.summary(for: f.now)
        try f.store.setLightDay(true, matching: summary, now: f.now)
        XCTAssertTrue(try RoutineStore(fileURL: f.url, calendar: f.calendar).summary(for: f.now).isLightDay)
        XCTAssertFalse(try f.store.summary(for: date("2026-09-21T00:00:00Z")).isLightDay)
        XCTAssertEqual(try f.store.habits(asOf: f.now), habits)
        XCTAssertEqual(try f.store.occurrence(id: small.id), small)
        expect(.lightTargetUnavailable) { _ = try f.store.perform(.complete(.light), on: missing, now: f.now) }
        expect(.staleAction) { try f.store.setLightDay(false, matching: summary, now: f.now) }
        let current = try f.store.summary(for: f.now)
        expect(.staleAction) { try f.store.setLightDay(true, matching: current, now: date("2026-09-21T00:00:00Z")) }
        try f.store.setLightDay(false, matching: current, now: f.now)
        XCTAssertFalse(try f.store.summary(for: f.now).isLightDay)
        XCTAssertEqual(try f.store.habits(asOf: f.now), habits)
    }

    func testStaleCompletionAfterLaterOrEditCannotOverwriteNewVersion() throws {
        let f = try DayFixture(); defer { f.remove() }
        let initial = try f.add()
        _ = try f.store.perform(.later(until: f.now.addingTimeInterval(3600), timeZoneIdentifier: "UTC"), on: initial, now: f.now)
        expect(.staleAction) { try f.store.complete(occurrenceID: initial.id, expectedRevision: initial.revision, now: f.now) }
        let delayed = try f.store.occurrence(id: initial.id)
        try f.store.updateOccurrence(occurrenceID: initial.id, normalTarget: "12 pages", lightTarget: "1 page", durationMinutes: 4, due: initial.due, now: f.now)
        XCTAssertNil(try f.store.occurrence(id: initial.id).deferredUntil)
        expect(.staleAction) { _ = try f.store.perform(.skip, on: delayed, now: f.now) }
        XCTAssertNil(try f.store.occurrence(id: initial.id).outcome)
    }

    func testOneOffCarryoverAppearsWithoutCreatingMissedRecurringBacklog() throws {
        let f = try DayFixture(); defer { f.remove() }
        let oneOff = try f.add(title: "Once", once: true), recurring = try f.add(title: "Daily")
        let tomorrow = date("2026-09-21T12:00:00Z")
        let agenda = try f.store.agenda(at: tomorrow)
        XCTAssertEqual(agenda.occurrences.count, 2)
        XCTAssertTrue(agenda.occurrences.contains { $0.id == oneOff.id })
        XCTAssertFalse(agenda.occurrences.contains { $0.id == recurring.id })
    }

    func testV2UpgradePreservesOriginalBytesAndSnapshotsAndRejectsFutureSchema() throws {
        let f = try DayFixture(); defer { f.remove() }
        let step = try f.add()
        try f.store.complete(occurrenceID: step.id, outcome: .light, now: f.now)
        var object = try JSONSerialization.jsonObject(with: Data(contentsOf: f.url)) as! [String: Any]
        object["version"] = 2
        var records = object["records"] as! [[String: Any]]
        records[0].removeValue(forKey: "mutationID")
        object["records"] = records
        let original = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try original.write(to: f.url)
        XCTAssertEqual(try f.store.summary(for: f.now).lightCount, 1)
        XCTAssertEqual(try Data(contentsOf: f.store.migrationBackupURL(from: 2)), original)
        let upgraded = try JSONDecoder().decode(StoreDocument.self, from: Data(contentsOf: f.url))
        XCTAssertEqual(upgraded.version, 3)
        XCTAssertNil(upgraded.records[0].mutationID)
        XCTAssertEqual(upgraded.records[0].completedAt, f.now)
        object["version"] = 4
        let future = try JSONSerialization.data(withJSONObject: object)
        try future.write(to: f.url)
        expect(.unsupportedVersion(4)) { _ = try f.store.summary(for: f.now) }
        XCTAssertEqual(try Data(contentsOf: f.url), future)
    }

    func testV2MigrationFailureAndUnknownFieldsNeverOverwriteOriginal() throws {
        let f = try DayFixture(); defer { f.remove() }
        _ = try f.add()
        var object = try JSONSerialization.jsonObject(with: Data(contentsOf: f.url)) as! [String: Any]
        object["version"] = 2
        let original = try JSONSerialization.data(withJSONObject: object)
        try original.write(to: f.url)
        let failing = RoutineStore(fileURL: f.url, calendar: f.calendar) { _, _ in throw CocoaError(.fileWriteOutOfSpace) }
        XCTAssertThrowsError(try failing.summary(for: f.now))
        XCTAssertEqual(try Data(contentsOf: f.url), original)
        XCTAssertEqual(try Data(contentsOf: f.store.migrationBackupURL(from: 2)), original)
        object["unknownFutureField"] = true
        let unfamiliar = try JSONSerialization.data(withJSONObject: object)
        try unfamiliar.write(to: f.url)
        expect(.corruptData) { _ = try f.store.summary(for: f.now) }
        XCTAssertEqual(try Data(contentsOf: f.url), unfamiliar)
        try original.write(to: f.url)
        XCTAssertEqual(try f.store.summary(for: f.now).totalCount, 1)
    }

    func testOrderingAfterTravelIntoTimezoneThatSkippedADateDoesNotChangeIdentity() throws {
        let f = try DayFixture(); defer { f.remove() }
        let creation = date("2011-12-29T12:00:00Z")
        let habit = try f.store.addHabit(HabitDefinition(title: "Once", normalTarget: "One step", dayPart: .morning,
                                                        recurrence: .once(dayKey: "2011-12-30")), now: creation)
        var apia = f.calendar; apia.timeZone = TimeZone(identifier: "Pacific/Apia")!
        let travel = RoutineStore(fileURL: f.url, calendar: apia)
        let agenda = try travel.agenda(at: date("2011-12-31T12:00:00Z"))
        XCTAssertEqual(agenda.occurrences.map(\.id), ["\(habit.id)|2011-12-30"])
    }

    func testFailedActionSaveLeavesPriorStateAndNoUsableUndo() throws {
        let f = try DayFixture(); defer { f.remove() }
        let step = try f.add(), bytes = try Data(contentsOf: f.url)
        let failing = RoutineStore(fileURL: f.url, calendar: f.calendar) { _, _ in throw CocoaError(.fileWriteOutOfSpace) }
        XCTAssertThrowsError(try failing.perform(.skip, on: step, now: f.now))
        XCTAssertEqual(try Data(contentsOf: f.url), bytes)
        XCTAssertEqual(try f.store.occurrence(id: step.id), step)
    }

    private func expect(_ error: RoutineStoreError, _ body: () throws -> Void, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try body(), file: file, line: line) { XCTAssertEqual($0 as? RoutineStoreError, error, file: file, line: line) }
    }
}

private struct DayFixture {
    let url: URL
    let calendar: Calendar
    let store: RoutineStore
    let now = date("2026-09-20T12:00:00Z")
    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("DayActions-\(UUID())/data.json")
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        self.calendar = calendar
        store = RoutineStore(fileURL: url, calendar: calendar)
    }
    func add(title: String = "Read", part: DayPart = .morning, light: String? = "2 pages", once: Bool = false) throws -> DailyOccurrence {
        let habit = try store.addHabit(HabitDefinition(title: title, normalTarget: "10 pages", lightTarget: light,
                                                       dayPart: part, recurrence: once ? .once(dayKey: "2026-09-20") : .weekly(weekdays: Set(1...7))), now: now)
        return try store.occurrence(id: "\(habit.id)|2026-09-20")
    }
    func remove() { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
}
private func date(_ string: String) -> Date { ISO8601DateFormatter().date(from: string)! }
private final class ActionResults: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var tokens: [OccurrenceUndo] = []
    private(set) var errors: [RoutineStoreError] = []
    func success(_ token: OccurrenceUndo) { lock.lock(); defer { lock.unlock() }; tokens.append(token) }
    func failure(_ error: Error) { lock.lock(); defer { lock.unlock() }; errors.append(error as? RoutineStoreError ?? .corruptData) }
}

import Foundation
import XCTest
@testable import DailyRhythmCore

final class VersionedStoreTests: XCTestCase {
    func testV1MigrationPreservesEveryHabitAndRecordFieldAndOriginalBytes() throws {
        let f = try ModelFixture()
        defer { f.remove() }
        let bytes = try f.installLegacy()
        let legacy = try JSONDecoder().decode(LegacyDocument.self, from: bytes)
        let migrated = try f.store.habits(includeArchived: true, asOf: stamp("2026-09-20T12:00:00Z"))
        XCTAssertEqual(migrated.count, legacy.habits.count)
        for (old, new) in zip(legacy.habits, migrated) {
            XCTAssertEqual(new.id, old.id)
            XCTAssertEqual(new.title, old.title)
            XCTAssertEqual(new.normalTarget, old.normalTarget)
            XCTAssertEqual(new.lightTarget, old.lightTarget)
            XCTAssertEqual(new.dayPart, old.dayPart)
            XCTAssertEqual(new.weekdays, old.weekdays)
            XCTAssertEqual(new.createdAt, old.createdAt)
            XCTAssertEqual(new.archivedAt, old.archivedAt)
            XCTAssertEqual(new.revisions.first?.effectiveDayKey, old.firstDayKey)
            XCTAssertNil(new.revisions.first?.recordedAt)
            XCTAssertEqual(new.archiveIntervals.first?.startDayKey, old.archiveDayKey)
            XCTAssertNil(new.durationMinutes, "Never infer duration from a label such as '20 minutes'")
            XCTAssertNil(new.dueTime, "A daypart is not a precise due time")
        }
        for old in legacy.records {
            let new = try f.store.occurrence(id: old.id)
            XCTAssertEqual(new.id, old.id)
            XCTAssertEqual(new.habitID, old.habitID)
            XCTAssertEqual(new.dayKey, old.dayKey)
            XCTAssertEqual(new.title, old.title)
            XCTAssertEqual(new.normalTarget, old.normalTarget)
            XCTAssertEqual(new.lightTarget, old.lightTarget)
            XCTAssertEqual(new.dayPart, old.dayPart)
            XCTAssertEqual(new.outcome, old.outcome)
            XCTAssertEqual(new.completedAt, old.completedAt)
            XCTAssertEqual(new.due, .dateOnly(dayKey: old.dayKey))
            XCTAssertNil(new.completionSource)
            XCTAssertNil(new.durationMinutes)
        }
        XCTAssertEqual(try Data(contentsOf: f.store.migrationBackupURL), bytes)
        let saved = try Data(contentsOf: f.url)
        XCTAssertEqual(try JSONDecoder().decode(StoreDocument.self, from: saved).version, 3)
        let history = try f.store.history(days: 4, endingOn: stamp("2026-09-21T12:00:00Z"))
        XCTAssertEqual(history.map(\.totalCount), [3, 2, 2, 2])
        XCTAssertEqual(history.map(\.completedCount), [1, 1, 1, 0])
        XCTAssertEqual(try Data(contentsOf: f.url), saved, "Only the first read migrates")
    }

    func testEmptyV1MigratesAndMissingFileStaysAbsentOnRead() throws {
        let f = try ModelFixture()
        defer { f.remove() }
        XCTAssertTrue(try f.store.habits().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.url.path))
        let bytes = try f.installLegacy("v1-empty")
        XCTAssertTrue(try f.store.habits().isEmpty)
        XCTAssertEqual(try Data(contentsOf: f.store.migrationBackupURL), bytes)
        XCTAssertEqual(try JSONDecoder().decode(StoreDocument.self, from: Data(contentsOf: f.url)).version, 3)
    }

    func testFailedMigrationValidationAndUnknownFieldsPreserveOriginalBytes() throws {
        let f = try ModelFixture()
        defer { f.remove() }
        let original = try f.legacyBytes()
        let mutations: [(inout [String: Any]) -> Void] = [
            { $0["version"] = 99 },
            { $0["futureProperty"] = "must not lose me" },
            { $0["records"] = "invalid" },
            { root in
                var habits = root["habits"] as! [[String: Any]]
                habits[0]["weekdays"] = [0, 8]
                root["habits"] = habits
            },
            { root in
                var records = root["records"] as! [[String: Any]]
                records[0]["normalTarget"] = "mismatched v1 snapshot"
                root["records"] = records
            },
            { root in
                var habits = root["habits"] as! [[String: Any]]
                habits[1].removeValue(forKey: "archiveDayKey")
                root["habits"] = habits
            },
            { root in
                var records = root["records"] as! [[String: Any]]
                records.append(records[0])
                root["records"] = records
            }
        ]
        for mutate in mutations {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
            mutate(&object)
            let bytes = try JSONSerialization.data(withJSONObject: object, options: .sortedKeys)
            try bytes.write(to: f.url)
            XCTAssertThrowsError(try f.store.habits())
            XCTAssertThrowsError(try f.add())
            XCTAssertEqual(try Data(contentsOf: f.url), bytes)
            XCTAssertFalse(FileManager.default.fileExists(atPath: f.store.migrationBackupURL.path))
        }
    }

    func testFailedMutationDuringMigrationDoesNotUpgradeOrBackup() throws {
        let f = try ModelFixture()
        defer { f.remove() }
        let original = try f.installLegacy()
        XCTAssertThrowsError(try f.store.complete(occurrenceID: "invalid"))
        XCTAssertEqual(try Data(contentsOf: f.url), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.store.migrationBackupURL.path))
    }

    func testMigrationSaveFailureKeepsOriginalAndBackupAndCanRetry() throws {
        let f = try ModelFixture()
        defer { f.remove() }
        let original = try f.installLegacy()
        let failing = RoutineStore(fileURL: f.url, calendar: f.calendar) { _, _ in
            throw CocoaError(.fileWriteOutOfSpace)
        }
        XCTAssertThrowsError(try failing.habits())
        XCTAssertEqual(try Data(contentsOf: f.url), original)
        XCTAssertEqual(try Data(contentsOf: failing.migrationBackupURL), original)
        XCTAssertEqual(try f.store.habits(includeArchived: true).count, 3)
        XCTAssertEqual(try Data(contentsOf: f.store.migrationBackupURL), original)
    }

    func testDifferentExistingBackupBlocksMigrationWithoutOverwritingEitherFile() throws {
        let f = try ModelFixture()
        defer { f.remove() }
        let original = try f.installLegacy()
        let other = Data("other saved data".utf8)
        try other.write(to: f.store.migrationBackupURL)
        XCTAssertThrowsError(try f.store.habits())
        XCTAssertEqual(try Data(contentsOf: f.url), original)
        XCTAssertEqual(try Data(contentsOf: f.store.migrationBackupURL), other)
    }

    func testFailedV2CompletionSavePreservesPendingSnapshotAndRetrySucceeds() throws {
        let f = try ModelFixture()
        defer { f.remove() }
        let habit = try f.add()
        let id = "\(habit.id)|2026-09-20"
        let original = try Data(contentsOf: f.url)
        let failing = RoutineStore(fileURL: f.url, calendar: f.calendar) { _, _ in
            throw CocoaError(.fileWriteOutOfSpace)
        }
        XCTAssertThrowsError(try failing.complete(occurrenceID: id, source: .widget, now: f.now))
        XCTAssertEqual(try Data(contentsOf: f.url), original)
        XCTAssertNil(try f.store.occurrence(id: id).outcome)
        try f.store.complete(occurrenceID: id, source: .app, now: f.now)
        XCTAssertEqual(try f.store.occurrence(id: id).completionSource, .app)
        XCTAssertEqual(try f.store.summary(for: f.now).completedCount, 1)
    }

    func testConcurrentFirstUseMigratesOnceAndPreservesEveryWrite() throws {
        let f = try ModelFixture()
        defer { f.remove() }
        let original = try f.installLegacy()
        let errors = ModelErrors()
        let url = f.url, calendar = f.calendar
        DispatchQueue.concurrentPerform(iterations: 20) { index in
            do {
                let store = RoutineStore(fileURL: url, calendar: calendar,
                                         entitlementProvider: ProEntitlementFixture())
                _ = try store.addHabit(title: "New \(index)", normalTarget: "1", dayPart: .morning,
                                       now: stamp("2026-09-21T12:00:00Z"))
                try store.complete(occurrenceID: "11111111-1111-4111-8111-111111111111|2026-09-20",
                                   source: .appIntent, now: stamp("2026-09-21T12:00:00Z"))
            } catch { errors.append(error) }
        }
        XCTAssertEqual(errors.values, [])
        XCTAssertEqual(try f.store.habits(includeArchived: true).count, 23)
        XCTAssertEqual(try Data(contentsOf: f.store.migrationBackupURL), original)
        XCTAssertEqual(try f.store.summary(for: stamp("2026-09-20T12:00:00Z")).completedCount, 2)
    }

    func testFutureEditPreservesUncompletedDenominatorsAndCompletedSnapshots() throws {
        let f = try ModelFixture()
        defer { f.remove() }
        let habit = try f.add(now: stamp("2026-09-18T09:00:00Z"))
        let oldID = "\(habit.id)|2026-09-19"
        try f.store.complete(occurrenceID: oldID, outcome: .light, source: .widget, now: stamp("2026-09-19T12:00:00Z"))
        let end = stamp("2026-09-21T12:00:00Z")
        let before = try f.store.history(days: 4, endingOn: end)
        var changed = habit.definition
        changed.title = "New title"
        changed.normalTarget = "30 pages"
        changed.lightTarget = nil
        changed.dayPart = .evening
        changed.recurrence = .weekly(weekdays: [3, 5])
        changed.durationMinutes = 20
        changed.dueTime = ScheduledTime(hour: 18, minute: 30, timeZoneIdentifier: "Europe/Istanbul")
        try f.store.editHabit(habitID: habit.id, definition: changed, effectiveDayKey: "2026-09-22", now: end)
        XCTAssertEqual(try f.store.history(days: 4, endingOn: end), before)
        XCTAssertEqual(try f.store.habits(asOf: end).first?.definition, habit.definition)
        XCTAssertEqual(try f.store.summary(for: stamp("2026-09-23T12:00:00Z")).totalCount, 0)
        let future = try XCTUnwrap(f.store.summary(for: stamp("2026-09-22T12:00:00Z")).occurrences.first)
        XCTAssertEqual(future.normalTarget, "30 pages")
        XCTAssertEqual(future.title, "New title")
        XCTAssertEqual(future.durationMinutes, 20)
        XCTAssertEqual(future.due.instant, stamp("2026-09-22T15:30:00Z"))
        // Reopening and completing an old snapshot still uses its original light target.
        try f.store.reopen(occurrenceID: oldID, now: end)
        try f.store.complete(occurrenceID: oldID, outcome: .light, source: .app, now: end)
        XCTAssertEqual(try f.store.occurrence(id: oldID).normalTarget, "10 pages")
        XCTAssertEqual(try f.store.occurrence(id: oldID).completionSource, .app)
        try f.store.complete(occurrenceID: "\(habit.id)|2026-09-20", outcome: .light, now: end)
        XCTAssertEqual(try f.store.occurrence(id: "\(habit.id)|2026-09-20").lightTarget, "2 pages")
    }

    func testEditsCannotRewriteTodayOrPastOrChangeRecurrenceIdentity() throws {
        let f = try ModelFixture()
        defer { f.remove() }
        let habit = try f.add()
        let saved = try Data(contentsOf: f.url)
        for key in ["2026-09-19", "2026-09-20", "2026-02-30"] {
            expect(.invalidEffectiveDate) {
                try f.store.editHabit(habitID: habit.id, definition: habit.definition, effectiveDayKey: key, now: f.now)
            }
        }
        var once = habit.definition
        once.recurrence = .once(dayKey: "2026-09-22")
        expect(.unsupportedRecurrenceChange) {
            try f.store.editHabit(habitID: habit.id, definition: once, effectiveDayKey: "2026-09-21", now: f.now)
        }
        XCTAssertEqual(try Data(contentsOf: f.url), saved)
    }

    func testOneOffDateOnlyAndNumericDurationAreNotInferredOrRepeated() throws {
        let f = try ModelFixture()
        defer { f.remove() }
        let definition = HabitDefinition(title: "Call", normalTarget: "One call", dayPart: .afternoon,
                                         recurrence: .once(dayKey: "2026-09-22"), durationMinutes: 15)
        let habit = try f.store.addHabit(definition, now: f.now)
        let history = try f.store.history(days: 5, endingOn: stamp("2026-09-24T12:00:00Z"))
        XCTAssertEqual(history.map(\.totalCount), [0, 0, 1, 0, 0])
        let occurrence = try f.store.occurrence(id: "\(habit.id)|2026-09-22")
        XCTAssertNil(occurrence.due.instant)
        XCTAssertEqual(occurrence.due, .dateOnly(dayKey: "2026-09-22"))
        XCTAssertEqual(occurrence.durationMinutes, 15)
        XCTAssertFalse(occurrence.isOverdue(at: stamp("2026-09-22T23:59:59Z"), calendar: f.calendar))
        XCTAssertTrue(occurrence.isOverdue(at: stamp("2026-09-23T00:00:00Z"), calendar: f.calendar))
        expect(.futureCompletion) { try f.store.complete(occurrenceID: occurrence.id, now: f.now) }
        try f.store.complete(occurrenceID: occurrence.id, source: .appIntent, now: stamp("2026-09-23T12:00:00Z"))
        XCTAssertFalse(try f.store.occurrence(id: occurrence.id).isOverdue(at: stamp("2026-09-24T12:00:00Z")))
        XCTAssertEqual(try f.store.summary(for: stamp("2026-09-23T12:00:00Z")).totalCount, 0)
    }

    func testReschedulingAcrossDaysRetainsIdentityDenominatorAndSingleCompletion() throws {
        let f = try ModelFixture()
        defer { f.remove() }
        let habit = try f.store.addHabit(HabitDefinition(title: "Call", normalTarget: "One call", dayPart: .morning,
                                                        recurrence: .once(dayKey: "2026-09-20")), now: f.now)
        let id = "\(habit.id)|2026-09-20"
        for time in ["2026-09-20T14:00:00Z", "2026-09-20T16:00:00Z"] {
            try f.store.rescheduleOccurrence(occurrenceID: id, due: .timed(at: stamp(time), timeZoneIdentifier: "UTC"), now: f.now)
            XCTAssertEqual(try f.store.occurrence(id: id).id, id)
        }
        try f.store.rescheduleOccurrence(occurrenceID: id, due: .dateOnly(dayKey: "2026-09-22"), now: f.now)
        XCTAssertEqual(try f.store.summary(for: f.now).totalCount, 1)
        XCTAssertEqual(try f.store.summary(for: stamp("2026-09-22T12:00:00Z")).totalCount, 0)
        expect(.futureCompletion) { try f.store.complete(occurrenceID: id, now: f.now) }
        let later = stamp("2026-09-22T12:00:00Z")
        expect(.invalidEffectiveDate) {
            try f.store.updateOccurrence(occurrenceID: id, normalTarget: "Changed past target", lightTarget: nil,
                                         durationMinutes: nil, due: .dateOnly(dayKey: "2026-09-22"), now: later)
        }
        try f.store.complete(occurrenceID: id, source: .widget, now: later)
        let saved = try Data(contentsOf: f.url)
        try f.store.complete(occurrenceID: id, source: .app, now: later.addingTimeInterval(20))
        XCTAssertEqual(try Data(contentsOf: f.url), saved)
        XCTAssertEqual(try f.store.occurrence(id: id).completionSource, .widget)
        XCTAssertEqual(try f.store.occurrence(id: id).completedAt, later)
        expect(.completedOccurrence) {
            try f.store.rescheduleOccurrence(occurrenceID: id, due: .dateOnly(dayKey: "2026-09-23"), now: later)
        }
        try f.store.reopen(occurrenceID: id, now: later)
        XCTAssertNil(try f.store.occurrence(id: id).completionSource)
        try f.store.rescheduleOccurrence(occurrenceID: id, due: .dateOnly(dayKey: "2026-09-23"), now: later)
        XCTAssertEqual(try f.store.occurrence(id: id).normalTarget, "One call")
    }

    func testFutureOccurrenceOverrideSurvivesLaterScheduleEditsAndCanClearOptionalFields() throws {
        let f = try ModelFixture()
        defer { f.remove() }
        let habit = try f.add()
        let id = "\(habit.id)|2026-09-23"
        try f.store.updateOccurrence(occurrenceID: id, normalTarget: "Special target", lightTarget: nil,
                                     durationMinutes: 30, due: .dateOnly(dayKey: "2026-09-24"), now: f.now)
        var edit = habit.definition
        edit.recurrence = .weekly(weekdays: [2])
        try f.store.editHabit(habitID: habit.id, definition: edit, effectiveDayKey: "2026-09-21", now: f.now)
        let pinned = try f.store.occurrence(id: id)
        XCTAssertEqual(pinned.normalTarget, "Special target")
        XCTAssertNil(pinned.lightTarget)
        XCTAssertEqual(pinned.durationMinutes, 30)
        XCTAssertEqual(try f.store.summary(for: stamp("2026-09-22T12:00:00Z")).totalCount, 0)
        XCTAssertEqual(try f.store.summary(for: stamp("2026-09-23T12:00:00Z")).totalCount, 1)
        try f.store.updateOccurrence(occurrenceID: id, normalTarget: pinned.normalTarget, lightTarget: nil,
                                     durationMinutes: nil, due: pinned.due, now: f.now)
        XCTAssertNil(try f.store.occurrence(id: id).durationMinutes)
    }

    func testArchiveRestoreIntervalsNeverFillGapsOrResurrectMissedOneOff() throws {
        let f = try ModelFixture()
        defer { f.remove() }
        let habit = try f.add(now: stamp("2026-09-18T12:00:00Z"))
        try f.store.archive(habitID: habit.id, now: stamp("2026-09-20T12:00:00Z"))
        try f.store.restore(habitID: habit.id, now: stamp("2026-09-22T12:00:00Z"))
        try f.store.archive(habitID: habit.id, now: stamp("2026-09-23T12:00:00Z"))
        try f.store.restore(habitID: habit.id, now: stamp("2026-09-25T12:00:00Z"))
        let history = try f.store.history(days: 8, endingOn: stamp("2026-09-25T12:00:00Z"))
        XCTAssertEqual(history.map(\.totalCount), [1, 1, 0, 0, 1, 0, 0, 1])
        XCTAssertEqual(try f.store.habits().first?.archiveIntervals.count, 2)
        let saved = try Data(contentsOf: f.url)
        try f.store.restore(habitID: habit.id, now: stamp("2026-09-26T12:00:00Z"))
        XCTAssertEqual(try Data(contentsOf: f.url), saved)
        let oneOff = try f.store.addHabit(HabitDefinition(title: "Once", normalTarget: "1", dayPart: .morning,
                                                         recurrence: .once(dayKey: "2026-09-21")), now: f.now)
        try f.store.archive(habitID: oneOff.id, now: f.now)
        try f.store.restore(habitID: oneOff.id, now: stamp("2026-09-22T12:00:00Z"))
        expect(.invalidOccurrence) { _ = try f.store.occurrence(id: "\(oneOff.id)|2026-09-21") }
    }

    func testTimedDSTGapUsesNextValidTimeAndRepeatedTimeUsesFirstInstant() throws {
        let f = try ModelFixture(zone: "America/New_York")
        defer { f.remove() }
        var definition = HabitDefinition(title: "Read", normalTarget: "10 pages", dayPart: .morning,
                                          recurrence: .weekly(weekdays: Set(1...7)),
                                          dueTime: ScheduledTime(hour: 2, minute: 30, timeZoneIdentifier: "America/New_York"))
        _ = try f.store.addHabit(definition, now: stamp("2026-03-01T12:00:00Z"))
        let spring = try XCTUnwrap(f.store.summary(for: stamp("2026-03-08T12:00:00Z")).occurrences.first)
        XCTAssertEqual(spring.due.instant, stamp("2026-03-08T07:00:00Z"), "Missing 02:30 resolves to 03:00")
        definition.title = "Fold"
        definition.dueTime = ScheduledTime(hour: 1, minute: 30, timeZoneIdentifier: "America/New_York")
        let fold = try f.store.addHabit(definition, now: stamp("2026-03-01T12:00:00Z"))
        let id = "\(fold.id)|2026-11-01"
        let first = try f.store.occurrence(id: id)
        XCTAssertEqual(first.due.instant, stamp("2026-11-01T05:30:00Z"))
        try f.store.complete(occurrenceID: id, source: .app, now: stamp("2026-11-01T05:30:00Z"))
        try f.store.complete(occurrenceID: id, source: .widget, now: stamp("2026-11-01T06:30:00Z"))
        XCTAssertEqual(try f.store.occurrence(id: id).completedAt, stamp("2026-11-01T05:30:00Z"))
        XCTAssertEqual(try f.store.summary(for: stamp("2026-11-01T06:30:00Z")).completedCount, 1)
    }

    func testTimezoneTravelKeepsTimedInstantAndDateOnlyCivilDateAndPreventsBackwardEdits() throws {
        let f = try ModelFixture(zone: "Asia/Tokyo")
        defer { f.remove() }
        let now = stamp("2026-09-20T23:30:00Z") // Sep 21 in Tokyo; Sep 20 in LA.
        let timed = try f.store.addHabit(HabitDefinition(title: "Timed", normalTarget: "1", dayPart: .morning,
                                                        recurrence: .once(dayKey: "2026-09-21"),
                                                        dueTime: ScheduledTime(hour: 9, minute: 0, timeZoneIdentifier: "Asia/Tokyo")), now: now)
        let floating = try f.store.addHabit(HabitDefinition(title: "Date", normalTarget: "1", dayPart: .morning,
                                                           recurrence: .once(dayKey: "2026-09-21")), now: now)
        let before = try f.store.occurrence(id: "\(timed.id)|2026-09-21")
        var west = f.calendar
        west.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let travelled = RoutineStore(fileURL: f.url, calendar: west)
        XCTAssertEqual(try travelled.occurrence(id: before.id), before)
        XCTAssertEqual(before.due.instant, stamp("2026-09-21T00:00:00Z"))
        XCTAssertEqual(try travelled.occurrence(id: "\(floating.id)|2026-09-21").due, .dateOnly(dayKey: "2026-09-21"))
        expect(.invalidEffectiveDate) { try travelled.archive(habitID: timed.id, now: now) }
        expect(.invalidEffectiveDate) {
            try travelled.editHabit(habitID: timed.id, definition: timed.definition, effectiveDayKey: "2026-09-21", now: now)
        }
        // It is the timed occurrence's due day in Tokyo, so an early completion is valid even while in LA.
        try travelled.complete(occurrenceID: before.id, now: now)
        XCTAssertEqual(try f.store.occurrence(id: before.id).completedAt, now)
    }

    func testInvalidDatesTimesDurationsAndUnsupportedEncodedRecurrenceFailExplicitly() throws {
        let f = try ModelFixture()
        defer { f.remove() }
        var definition = HabitDefinition(title: "Read", normalTarget: "1", dayPart: .morning,
                                          recurrence: .once(dayKey: "2026-02-30"))
        expect(.invalidDueDate) { _ = try f.store.addHabit(definition, now: f.now) }
        definition.recurrence = .weekly(weekdays: [1])
        for minutes in [0, -1] {
            definition.durationMinutes = minutes
            expect(.invalidDuration) { _ = try f.store.addHabit(definition, now: f.now) }
        }
        definition.durationMinutes = nil
        for time in [ScheduledTime(hour: 24, minute: 0, timeZoneIdentifier: "UTC"),
                     ScheduledTime(hour: 9, minute: 60, timeZoneIdentifier: "UTC"),
                     ScheduledTime(hour: 9, minute: 0, timeZoneIdentifier: "No/Such_Zone")] {
            definition.dueTime = time
            expect(.invalidDueDate) { _ = try f.store.addHabit(definition, now: f.now) }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.url.path))
        _ = try f.add()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: f.url)) as? [String: Any])
        var habits = object["habits"] as! [[String: Any]]
        var revisions = habits[0]["revisions"] as! [[String: Any]]
        var content = revisions[0]["definition"] as! [String: Any]
        content["recurrence"] = ["monthly": ["day": 20]]
        revisions[0]["definition"] = content
        habits[0]["revisions"] = revisions
        object["habits"] = habits
        let unsupported = try JSONSerialization.data(withJSONObject: object)
        try unsupported.write(to: f.url)
        expect(.corruptData) { _ = try f.store.habits() }
        XCTAssertEqual(try Data(contentsOf: f.url), unsupported)
    }

    func testConcurrentFutureEditAndCompletionUseOriginalSnapshotWithoutLostWrites() throws {
        let f = try ModelFixture()
        defer { f.remove() }
        let habit = try f.add()
        let id = "\(habit.id)|2026-09-20"
        let url = f.url, calendar = f.calendar, now = f.now
        let errors = ModelErrors()
        DispatchQueue.concurrentPerform(iterations: 30) { index in
            do {
                let store = RoutineStore(fileURL: url, calendar: calendar)
                if index.isMultiple(of: 2) {
                    var definition = habit.definition
                    definition.normalTarget = "New \(index)"
                    try store.editHabit(habitID: habit.id, definition: definition, effectiveDayKey: "2026-09-21", now: now)
                } else {
                    try store.complete(occurrenceID: id, outcome: .light, source: .appIntent, now: now)
                }
            } catch { errors.append(error) }
        }
        XCTAssertEqual(errors.values, [])
        let today = try f.store.occurrence(id: id)
        XCTAssertEqual(today.normalTarget, "10 pages")
        XCTAssertEqual(today.outcome, .light)
        XCTAssertEqual(today.completionSource, .appIntent)
        XCTAssertTrue(try f.store.occurrence(id: "\(habit.id)|2026-09-21").normalTarget.hasPrefix("New "))
        XCTAssertEqual(try f.store.summary(for: now).completedCount, 1)
    }

    private func expect(_ expected: RoutineStoreError, _ body: () throws -> Void,
                        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try body(), file: file, line: line) {
            XCTAssertEqual($0 as? RoutineStoreError, expected, file: file, line: line)
        }
    }
}

private struct ModelFixture {
    let directory: URL
    let url: URL
    let calendar: Calendar
    let store: RoutineStore
    let now = stamp("2026-09-20T12:00:00Z")

    init(zone: String = "UTC") throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("DailyRhythmV2-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("routines.json")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: zone))
        self.calendar = calendar
        store = RoutineStore(fileURL: url, calendar: calendar)
    }
    func add(now: Date? = nil) throws -> Habit {
        try store.addHabit(title: "Read", normalTarget: "10 pages", lightTarget: "2 pages", dayPart: .morning, now: now ?? self.now)
    }
    func legacyBytes(_ name: String = "v1-mixed") throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")))
    }
    @discardableResult func installLegacy(_ name: String = "v1-mixed") throws -> Data {
        let bytes = try legacyBytes(name)
        try bytes.write(to: url)
        return bytes
    }
    func remove() { try? FileManager.default.removeItem(at: directory) }
}

private func stamp(_ string: String) -> Date { ISO8601DateFormatter().date(from: string)! }

private final class ModelErrors: @unchecked Sendable {
    private let lock = NSLock()
    private var errors: [String] = []
    func append(_ error: any Error) { lock.lock(); defer { lock.unlock() }; errors.append(String(describing: error)) }
    var values: [String] { lock.lock(); defer { lock.unlock() }; return errors }
}

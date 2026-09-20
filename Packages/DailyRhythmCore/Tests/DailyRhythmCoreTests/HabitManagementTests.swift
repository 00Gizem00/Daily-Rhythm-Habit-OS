import Foundation
import XCTest
@testable import DailyRhythmCore

final class HabitManagementTests: XCTestCase {
    func testOneOffDraftPersistsDateOnlyAndTimedSemanticsAcrossReload() throws {
        let f = try ManagementFixture()
        defer { f.remove() }
        var draft = HabitFormDraft(definition: f.definition, now: f.now, calendar: f.calendar)
        draft.isRecurring = false
        draft.dayKey = "2026-09-22"
        draft.hasDuration = true
        draft.durationText = " 15 "
        let dateOnly = try f.store.addHabit(draft.definition(), now: f.now)
        draft.hasTime = true
        draft.hour = 8
        draft.minute = 35
        draft.timeZoneIdentifier = "Asia/Tokyo"
        let timed = try f.store.addHabit(draft.definition(), now: f.now)
        let fresh = RoutineStore(fileURL: f.url, calendar: f.calendar)
        XCTAssertEqual(try fresh.habits(asOf: f.now), [dateOnly, timed])
        let steps = try fresh.summary(for: stamp("2026-09-22T12:00:00Z")).occurrences
        XCTAssertEqual(steps[0].due, .dateOnly(dayKey: "2026-09-22"))
        XCTAssertNil(steps[0].due.instant)
        XCTAssertEqual(steps[1].due, .timed(at: stamp("2026-09-21T23:35:00Z"), timeZoneIdentifier: "Asia/Tokyo"))
        XCTAssertEqual(steps.map(\.durationMinutes), [15, 15])
        XCTAssertEqual(try fresh.summary(for: stamp("2026-09-23T12:00:00Z")).totalCount, 0)
    }

    func testCancelledDraftsAndInvalidInputDoNotMutateTheStore() throws {
        let f = try ManagementFixture()
        defer { f.remove() }
        let habit = try f.store.addHabit(f.definition, now: f.now)
        let original = try Data(contentsOf: f.url)
        var draft = HabitFormDraft(definition: habit.definition, now: f.now, calendar: f.calendar)
        draft.title = "Unsaved title"
        draft.normalTarget = "Unsaved target"
        draft.isRecurring = false
        draft.dayKey = "2026-09-23"
        _ = try draft.definition() // validation/preview is also read-only
        for duration in ["", "0", "-1", "1.5", "minutes", "999999999999999999999999999"] {
            draft.hasDuration = true
            draft.durationText = duration
            XCTAssertThrowsError(try draft.definition()) { XCTAssertEqual($0 as? RoutineStoreError, .invalidDuration) }
        }
        draft.hasDuration = false
        draft.hasTime = true
        draft.timeZoneIdentifier = "Invalid/Zone"
        XCTAssertThrowsError(try draft.definition())
        draft.hasTime = false
        draft.dayKey = "2026-02-30"
        XCTAssertThrowsError(try draft.definition())
        XCTAssertEqual(try Data(contentsOf: f.url), original)
        XCTAssertEqual(try f.store.habits(asOf: f.now), [habit])
    }

    func testFutureAndOccurrenceDraftsPreserveTheirExplicitScopeOnReload() throws {
        let f = try ManagementFixture()
        defer { f.remove() }
        let yesterday = f.now.addingTimeInterval(-86_400)
        let habit = try f.store.addHabit(f.definition, now: yesterday)
        let past = try f.store.summary(for: yesterday)
        let today = try XCTUnwrap(f.store.summary(for: f.now).occurrences.first)
        var future = HabitFormDraft(definition: habit.definition, now: f.now, calendar: f.calendar)
        future.title = "Future reading"
        future.normalTarget = "20 pages"
        future.hasTime = true
        future.hour = 18
        future.minute = 10
        future.timeZoneIdentifier = "Europe/Istanbul"
        try f.store.editHabit(habitID: habit.id, definition: future.definition(), effectiveDayKey: "2026-09-21", now: f.now)
        var step = HabitFormDraft(occurrence: today, calendar: f.calendar)
        step.normalTarget = "3 pages"
        step.hasLightTarget = false
        step.hasDuration = true
        step.durationText = "4"
        step.dayKey = "2026-09-22"
        let values = try step.definition()
        try f.store.updateOccurrence(occurrenceID: today.id, normalTarget: values.normalTarget,
                                     lightTarget: values.lightTarget, durationMinutes: values.durationMinutes,
                                     due: step.due(), now: f.now)
        let fresh = RoutineStore(fileURL: f.url, calendar: f.calendar)
        XCTAssertEqual(try fresh.summary(for: yesterday), past)
        let edited = try fresh.occurrence(id: today.id)
        XCTAssertEqual(edited.normalTarget, "3 pages")
        XCTAssertNil(edited.lightTarget)
        XCTAssertEqual(edited.durationMinutes, 4)
        XCTAssertEqual(edited.due, .dateOnly(dayKey: "2026-09-22"))
        XCTAssertEqual(edited.dayKey, "2026-09-20")
        let tomorrow = try XCTUnwrap(fresh.summary(for: f.now.addingTimeInterval(86_400)).occurrences.first)
        XCTAssertEqual(tomorrow.title, "Future reading")
        XCTAssertEqual(tomorrow.normalTarget, "20 pages")
        XCTAssertEqual(tomorrow.lightTarget, "2 pages")
        XCTAssertEqual(tomorrow.due, .timed(at: stamp("2026-09-21T15:10:00Z"), timeZoneIdentifier: "Europe/Istanbul"))
        XCTAssertFalse(edited.canComplete(at: f.now, calendar: f.calendar))
        XCTAssertEqual(try fresh.summary(for: f.now).completedCount, 0)
    }

    func testTargetOnlyDraftPreservesExactTimedInstantIncludingSecondDSTFold() throws {
        let f = try ManagementFixture()
        defer { f.remove() }
        let habit = try f.store.addHabit(f.definition, now: stamp("2026-11-01T05:00:00Z"))
        let id = "\(habit.id.uuidString)|2026-11-01"
        let exact = stamp("2026-11-01T06:30:27Z").addingTimeInterval(0.125)
        try f.store.rescheduleOccurrence(occurrenceID: id,
            due: .timed(at: exact, timeZoneIdentifier: "America/New_York"), now: stamp("2026-11-01T05:00:00Z"))
        let occurrence = try f.store.occurrence(id: id)
        var draft = HabitFormDraft(occurrence: occurrence, calendar: f.calendar)
        draft.normalTarget = "A different target"
        XCTAssertEqual(try draft.due(), occurrence.due)
        draft.minute = 31
        XCTAssertEqual(try draft.due(), .timed(at: stamp("2026-11-01T05:31:00Z"), timeZoneIdentifier: "America/New_York"))
        draft.hasTime = false
        XCTAssertEqual(try draft.due(), .dateOnly(dayKey: "2026-11-01"))
    }

    func testDraftUsesTheModelsDSTGapRuleAndCivilDatesDoNotShiftOnTravel() throws {
        let f = try ManagementFixture()
        defer { f.remove() }
        var draft = HabitFormDraft(definition: f.definition, now: f.now, calendar: f.calendar)
        draft.isRecurring = false
        draft.dayKey = "2026-03-08"
        draft.hasTime = true
        draft.hour = 2
        draft.minute = 30
        draft.timeZoneIdentifier = "America/New_York"
        XCTAssertEqual(try draft.due(), .timed(at: stamp("2026-03-08T07:00:00Z"), timeZoneIdentifier: "America/New_York"))
        let selectedDate = try XCTUnwrap(LocalDay.utc.date(for: "2026-09-20"))
        XCTAssertEqual(LocalDay.utc.key(for: selectedDate), "2026-09-20")
        draft.hasTime = false
        draft.dayKey = LocalDay.utc.key(for: selectedDate)
        XCTAssertEqual(try draft.due(), .dateOnly(dayKey: "2026-09-20"))
    }

    func testOneOffAgendaKeepsOverdueAndCompletedTasksWithoutInventingOccurrences() throws {
        let f = try ManagementFixture()
        defer { f.remove() }
        var definition = f.definition
        definition.recurrence = .once(dayKey: "2026-09-20")
        let habit = try f.store.addHabit(definition, now: f.now)
        let later = stamp("2026-10-10T12:00:00Z")
        let original = try XCTUnwrap(f.store.managedOccurrences(habitID: habit.id, startingOn: later).first)
        XCTAssertTrue(original.isOverdue(at: later, calendar: f.calendar))
        XCTAssertTrue(original.canComplete(at: later, calendar: f.calendar))
        XCTAssertFalse(original.isCompleted)
        XCTAssertEqual(original.dayKey, "2026-09-20")
        try f.store.complete(occurrenceID: original.id, now: later)
        let completed = try f.store.managedOccurrences(habitID: habit.id, startingOn: later)
        XCTAssertEqual(completed.count, 1)
        XCTAssertFalse(completed[0].isOverdue(at: later, calendar: f.calendar))
        XCTAssertFalse(completed[0].canComplete(at: later, calendar: f.calendar))
        XCTAssertEqual(try f.store.summary(for: later).totalCount, 0)
    }

    func testRecurringAgendaIncludesOnlyExplicitEarlierPendingStepsAndDoesNotWrite() throws {
        let f = try ManagementFixture()
        defer { f.remove() }
        let habit = try f.store.addHabit(f.definition, now: f.now.addingTimeInterval(-10 * 86_400))
        let id = "\(habit.id.uuidString)|2026-09-15"
        try f.store.rescheduleOccurrence(occurrenceID: id, due: .dateOnly(dayKey: "2026-09-22"), now: f.now)
        let original = try Data(contentsOf: f.url)
        let agenda = try f.store.managedOccurrences(habitID: habit.id, startingOn: f.now)
        XCTAssertEqual(agenda.map(\.dayKey), ["2026-09-15", "2026-09-20", "2026-09-21", "2026-09-22", "2026-09-23", "2026-09-24", "2026-09-25", "2026-09-26"])
        XCTAssertEqual(Set(agenda.map(\.id)).count, 8)
        XCTAssertEqual(try Data(contentsOf: f.url), original)
        XCTAssertThrowsError(try f.store.managedOccurrences(habitID: habit.id, startingOn: f.now, days: 0))
    }

    func testAgendaRespectsArchiveGapsAndCapacityCheckedRestore() throws {
        let f = try ManagementFixture()
        defer { f.remove() }
        let habit = try f.store.addHabit(f.definition, now: f.now)
        try f.store.archive(habitID: habit.id, now: f.now)
        XCTAssertTrue(try f.store.managedOccurrences(habitID: habit.id, startingOn: f.now).isEmpty)
        _ = try f.store.addHabits(Array(repeating: f.definition, count: 3), now: f.now)
        let before = try Data(contentsOf: f.url)
        XCTAssertThrowsError(try f.store.restore(habitID: habit.id, now: f.now)) {
            XCTAssertEqual($0 as? RoutineStoreError, .activeHabitLimitReached)
        }
        XCTAssertEqual(try Data(contentsOf: f.url), before)
        let replacement = try XCTUnwrap(f.store.habits().first)
        try f.store.archive(habitID: replacement.id, now: f.now)
        let tomorrow = f.now.addingTimeInterval(86_400)
        try f.store.restore(habitID: habit.id, now: tomorrow)
        XCTAssertEqual(try f.store.managedOccurrences(habitID: habit.id, startingOn: f.now, days: 2).map(\.dayKey), ["2026-09-21"])
    }

    func testEarlierRecurringStepStaysVisibleAfterCompletionSoItCanBeReopened() throws {
        let f = try ManagementFixture()
        defer { f.remove() }
        let habit = try f.store.addHabit(f.definition, now: f.now.addingTimeInterval(-86_400))
        let id = "\(habit.id.uuidString)|2026-09-19"
        try f.store.rescheduleOccurrence(occurrenceID: id, due: .dateOnly(dayKey: "2026-09-20"), now: f.now)
        try f.store.complete(occurrenceID: id, now: f.now)
        let recorded = try XCTUnwrap(f.store.managedOccurrences(habitID: habit.id, startingOn: f.now).first { $0.id == id })
        XCTAssertTrue(recorded.isCompleted)
        try f.store.reopen(occurrenceID: recorded.id, now: f.now)
        let reopened = try XCTUnwrap(f.store.managedOccurrences(habitID: habit.id, startingOn: f.now).first { $0.id == id })
        XCTAssertFalse(reopened.isCompleted)
        XCTAssertEqual(reopened.due, .dateOnly(dayKey: "2026-09-20"))
    }
}

private func stamp(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

private struct ManagementFixture {
    let directory: URL
    let url: URL
    let calendar: Calendar
    let store: RoutineStore
    let now = stamp("2026-09-20T12:00:00Z")
    let definition = HabitDefinition(title: "Read", normalTarget: "10 pages", lightTarget: "2 pages",
                                     dayPart: .morning, recurrence: .weekly(weekdays: Set(1...7)))
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("HabitManagement-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("routines.json")
        calendar = LocalDay.utc.calendar
        store = RoutineStore(fileURL: url, calendar: calendar)
    }
    func remove() { try? FileManager.default.removeItem(at: directory) }
}

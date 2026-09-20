import Foundation
import XCTest
@testable import DailyRhythmCore

final class RoutineStoreTests: XCTestCase {
    func testDailyOccurrencesHaveStableIDsAndResetWithoutMidnightWrite() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let first = instant("2026-09-20T09:00:00Z")
        let next = instant("2026-09-21T09:00:00Z")
        let habit = try fixture.add(now: first)
        let today = try XCTUnwrap(fixture.store.summary(for: first).occurrences.first)
        let tomorrow = try XCTUnwrap(fixture.store.summary(for: next).occurrences.first)
        XCTAssertEqual(today.habitID, habit.id)
        XCTAssertEqual(today.id, try fixture.store.summary(for: first).occurrences.first?.id)
        XCTAssertNotEqual(today.id, tomorrow.id)
        try fixture.store.complete(occurrenceID: today.id, now: first)
        let dataBefore = try Data(contentsOf: fixture.fileURL)
        XCTAssertEqual(try fixture.store.summary(for: next).completedCount, 0)
        XCTAssertEqual(try fixture.store.summary(for: next).totalCount, 1)
        XCTAssertEqual(try Data(contentsOf: fixture.fileURL), dataBefore, "Read-only future summaries must not rewrite the store")
    }

    func testSelectedWeekdaysAndCreationDayBoundaries() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        // Sunday creation; this habit runs Monday and Wednesday only.
        _ = try fixture.store.addHabit(title: "Read", normalTarget: "10 pages", dayPart: .morning,
                                      weekdays: [2, 4], now: instant("2026-09-20T09:00:00Z"))
        let week = try fixture.store.history(days: 8, endingOn: instant("2026-09-26T09:00:00Z"))
        XCTAssertEqual(week.map(\.dayKey), ["2026-09-19", "2026-09-20", "2026-09-21", "2026-09-22",
                                            "2026-09-23", "2026-09-24", "2026-09-25", "2026-09-26"])
        XCTAssertEqual(week.map(\.totalCount), [0, 0, 1, 0, 1, 0, 0, 0])
    }

    func testDuplicateCompletionFirstOutcomeWinsAndUndoAllowsChange() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let now = instant("2026-09-20T09:00:00Z")
        _ = try fixture.add(now: now)
        let id = try XCTUnwrap(fixture.store.summary(for: now).occurrences.first?.id)
        try fixture.store.complete(occurrenceID: id, outcome: .light, now: now)
        let saved = try Data(contentsOf: fixture.fileURL)
        try fixture.store.complete(occurrenceID: id, outcome: .full, now: now.addingTimeInterval(5))
        XCTAssertEqual(try Data(contentsOf: fixture.fileURL), saved)
        XCTAssertEqual(try fixture.store.summary(for: now).lightCount, 1)
        XCTAssertEqual(try fixture.store.summary(for: now).fullCount, 0)
        try fixture.store.reopen(occurrenceID: id)
        try fixture.store.reopen(occurrenceID: id)
        XCTAssertEqual(try fixture.store.summary(for: now).completedCount, 0)
        try fixture.store.complete(occurrenceID: id, outcome: .full, now: now.addingTimeInterval(10))
        XCTAssertEqual(try fixture.store.summary(for: now).fullCount, 1)
        XCTAssertEqual(try fixture.store.summary(for: now).lightCount, 0)
    }

    func testMidnightActionTargetsOriginalDayAndFutureCompletionIsRejected() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let beforeMidnight = instant("2026-09-20T23:59:59Z")
        let afterMidnight = instant("2026-09-21T00:00:01Z")
        _ = try fixture.add(now: beforeMidnight)
        let yesterday = try XCTUnwrap(fixture.store.summary(for: beforeMidnight).occurrences.first)
        let today = try XCTUnwrap(fixture.store.summary(for: afterMidnight).occurrences.first)
        assertError(.futureCompletion) {
            try fixture.store.complete(occurrenceID: today.id, now: beforeMidnight)
        }
        try fixture.store.complete(occurrenceID: yesterday.id, now: afterMidnight)
        XCTAssertEqual(try fixture.store.summary(for: beforeMidnight).completedCount, 1)
        XCTAssertEqual(try fixture.store.summary(for: afterMidnight).completedCount, 0)
    }

    func testDSTSpringForwardAndFallBackProduceExactlyOneOccurrencePerLocalDate() throws {
        let fixture = try Fixture(timeZone: "America/New_York")
        defer { fixture.remove() }
        _ = try fixture.add(now: instant("2026-03-01T12:00:00Z"))
        let spring = try fixture.store.history(days: 3, endingOn: instant("2026-03-09T16:00:00Z"))
        XCTAssertEqual(spring.map(\.dayKey), ["2026-03-07", "2026-03-08", "2026-03-09"])
        XCTAssertEqual(spring.map(\.totalCount), [1, 1, 1])
        let firstOneThirty = instant("2026-11-01T05:30:00Z")
        let secondOneThirty = instant("2026-11-01T06:30:00Z")
        let first = try XCTUnwrap(fixture.store.summary(for: firstOneThirty).occurrences.first)
        let second = try XCTUnwrap(fixture.store.summary(for: secondOneThirty).occurrences.first)
        XCTAssertEqual(first.id, second.id, "Repeated 1:30 AM is the same local day")
        try fixture.store.complete(occurrenceID: first.id, now: firstOneThirty)
        try fixture.store.complete(occurrenceID: second.id, now: secondOneThirty)
        XCTAssertEqual(try fixture.store.summary(for: secondOneThirty).completedCount, 1)
        let fall = try fixture.store.history(days: 3, endingOn: instant("2026-11-02T16:00:00Z"))
        XCTAssertEqual(fall.map(\.dayKey), ["2026-10-31", "2026-11-01", "2026-11-02"])
    }

    func testTimezoneTravelKeepsSavedCalendarDayAndHistory() throws {
        let fixture = try Fixture(timeZone: "America/Los_Angeles")
        defer { fixture.remove() }
        let creation = instant("2026-09-20T23:30:00Z")
        _ = try fixture.add(now: creation)
        let original = try XCTUnwrap(fixture.store.summary(for: creation).occurrences.first)
        try fixture.store.complete(occurrenceID: original.id, now: creation)
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        let travelled = RoutineStore(fileURL: fixture.fileURL, calendar: tokyo)
        let history = try travelled.history(days: 2, endingOn: creation)
        XCTAssertEqual(history.map(\.dayKey), ["2026-09-20", "2026-09-21"])
        XCTAssertEqual(history.map(\.completedCount), [1, 0])
        XCTAssertEqual(history.first?.occurrences.first?.id, original.id)
    }

    func testArchivePreservesPreviousHistoryAndCompletedArchiveDay() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let first = instant("2026-09-20T09:00:00Z")
        let archiveDate = instant("2026-09-21T09:00:00Z")
        let habit = try fixture.add(now: first)
        let id = try XCTUnwrap(fixture.store.summary(for: archiveDate).occurrences.first?.id)
        try fixture.store.complete(occurrenceID: id, now: archiveDate)
        try fixture.store.archive(habitID: habit.id, now: archiveDate)
        XCTAssertTrue(try fixture.store.habits().isEmpty)
        XCTAssertEqual(try fixture.store.habits(includeArchived: true).count, 1)
        XCTAssertEqual(try fixture.store.summary(for: first).totalCount, 1)
        XCTAssertEqual(try fixture.store.summary(for: archiveDate).completedCount, 1)
        XCTAssertEqual(try fixture.store.summary(for: instant("2026-09-22T09:00:00Z")).totalCount, 0)
        try fixture.store.reopen(occurrenceID: id)
        XCTAssertEqual(try fixture.store.summary(for: archiveDate).totalCount, 0)
        try fixture.store.reopen(occurrenceID: id)
        XCTAssertEqual(try fixture.store.summary(for: archiveDate).totalCount, 0)
    }

    func testArchiveRemovesPendingTodayAndRejectsOldWidgetAction() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let now = instant("2026-09-20T09:00:00Z")
        let habit = try fixture.add(now: now)
        let id = try XCTUnwrap(fixture.store.summary(for: now).occurrences.first?.id)
        try fixture.store.archive(habitID: habit.id, now: now)
        assertError(.invalidOccurrence) { try fixture.store.complete(occurrenceID: id, now: now) }
        XCTAssertEqual(try fixture.store.summary(for: now).totalCount, 0)
    }

    func testSameNameHabitsRemainDistinctAndLightRequiresConfiguredTarget() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let now = instant("2026-09-20T09:00:00Z")
        _ = try fixture.store.addHabit(title: "Read", normalTarget: "10 pages", dayPart: .morning, now: now)
        _ = try fixture.store.addHabit(title: "Read", normalTarget: "1 chapter", dayPart: .evening, now: now)
        let occurrences = try fixture.store.summary(for: now).occurrences
        XCTAssertEqual(occurrences.count, 2)
        XCTAssertNotEqual(occurrences[0].id, occurrences[1].id)
        assertError(.lightTargetUnavailable) { try fixture.store.complete(occurrenceID: occurrences[0].id, outcome: .light, now: now) }
        try fixture.store.complete(occurrenceID: occurrences[1].id, now: now)
        XCTAssertNil(try fixture.store.summary(for: now).occurrences[0].outcome)
        XCTAssertEqual(try fixture.store.summary(for: now).completedCount, 1)
    }

    func testFreshStoreInstanceSeesWritesAndPreservesFractionalDates() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let now = instant("2026-09-20T09:00:00Z").addingTimeInterval(0.123456)
        let habit = try fixture.add(now: now)
        let other = RoutineStore(fileURL: fixture.fileURL, calendar: fixture.calendar)
        XCTAssertEqual(try other.habits().first, habit)
        let id = try XCTUnwrap(other.summary(for: now).occurrences.first?.id)
        try other.complete(occurrenceID: id, outcome: .light, now: now)
        XCTAssertEqual(try fixture.store.summary(for: now).occurrences.first?.completedAt, now)
        XCTAssertEqual(try fixture.store.summary(for: now).lightCount, 1)
    }

    func testInvalidInputsDoNotCreateStoreAndMalformedIDDoesNotMutate() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let now = instant("2026-09-20T09:00:00Z")
        assertError(.invalidTitle) { _ = try fixture.store.addHabit(title: " \n", normalTarget: "10", dayPart: .morning) }
        assertError(.invalidTarget) { _ = try fixture.store.addHabit(title: "Read", normalTarget: "10", lightTarget: " ", dayPart: .morning) }
        assertError(.invalidWeekdays) { _ = try fixture.store.addHabit(title: "Read", normalTarget: "10", dayPart: .morning, weekdays: [0, 8]) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.fileURL.path))
        _ = try fixture.add(now: now)
        let dataBefore = try Data(contentsOf: fixture.fileURL)
        assertError(.invalidOccurrence) { try fixture.store.complete(occurrenceID: "garbage", now: now) }
        assertError(.invalidHistoryRange) { _ = try fixture.store.history(days: 0) }
        XCTAssertEqual(try Data(contentsOf: fixture.fileURL), dataBefore)
    }

    func testCorruptAndFutureVersionDataAreNeverOverwritten() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        for (text, expected) in [
            ("{incomplete", RoutineStoreError.corruptData),
            (#"{"version":1,"habits":[],"records":"wrong type"}"#, .corruptData),
            (#"{"version":99,"newData":"keep me"}"#, .unsupportedVersion(99))
        ] {
            let original = Data(text.utf8)
            try original.write(to: fixture.fileURL)
            assertError(expected) { _ = try fixture.store.habits() }
            assertError(expected) { _ = try fixture.add(now: instant("2026-09-20T09:00:00Z")) }
            XCTAssertEqual(try Data(contentsOf: fixture.fileURL), original)
        }
    }

    func testSemanticallyInvalidSnapshotIsPreserved() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        _ = try fixture.add(now: instant("2026-09-20T09:00:00Z"))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixture.fileURL)) as? [String: Any])
        var habits = try XCTUnwrap(object["habits"] as? [[String: Any]])
        var revisions = try XCTUnwrap(habits[0]["revisions"] as? [[String: Any]])
        var definition = try XCTUnwrap(revisions[0]["definition"] as? [String: Any])
        definition["recurrence"] = ["weekly": ["weekdays": [0, 8]]]
        revisions[0]["definition"] = definition
        habits[0]["revisions"] = revisions
        object["habits"] = habits
        let invalid = try JSONSerialization.data(withJSONObject: object)
        try invalid.write(to: fixture.fileURL)
        assertError(.corruptData) { _ = try fixture.store.habits() }
        XCTAssertEqual(try Data(contentsOf: fixture.fileURL), invalid)
    }

    func testConcurrentIndependentStoresDoNotLoseWritesOrDuplicateCompletion() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let now = instant("2026-09-20T09:00:00Z")
        let fileURL = fixture.fileURL
        let calendar = fixture.calendar
        let errors = ErrorCollector()
        DispatchQueue.concurrentPerform(iterations: 30) { index in
            do {
                let independent = RoutineStore(fileURL: fileURL, calendar: calendar,
                                               entitlementProvider: ProEntitlementFixture())
                _ = try independent.addHabit(title: "Habit \(index)", normalTarget: "1 step", dayPart: .morning, now: now)
            } catch { errors.append(error) }
        }
        XCTAssertTrue(errors.isEmpty)
        XCTAssertEqual(try fixture.store.habits().count, 30)
        let id = try XCTUnwrap(fixture.store.summary(for: now).occurrences.first?.id)
        DispatchQueue.concurrentPerform(iterations: 40) { _ in
            do { try RoutineStore(fileURL: fileURL, calendar: calendar).complete(occurrenceID: id, now: now) }
            catch { errors.append(error) }
        }
        XCTAssertTrue(errors.isEmpty)
        XCTAssertEqual(try fixture.store.summary(for: now).completedCount, 1)
        XCTAssertEqual(try fixture.store.summary(for: now).totalCount, 30)
    }

    private func assertError(_ expected: RoutineStoreError, _ action: () throws -> Void, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try action(), file: file, line: line) { error in
            XCTAssertEqual(error as? RoutineStoreError, expected, file: file, line: line)
        }
    }
}

private struct Fixture {
    let directory: URL
    let fileURL: URL
    let calendar: Calendar
    let store: RoutineStore

    init(timeZone: String = "UTC") throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("DailyRhythmTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("routines.json")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: timeZone))
        self.calendar = calendar
        store = RoutineStore(fileURL: fileURL, calendar: calendar)
    }

    func add(now: Date) throws -> Habit {
        try store.addHabit(title: "Read", normalTarget: "10 pages", lightTarget: "2 pages", dayPart: .morning, now: now)
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }
}

private func instant(_ value: String) -> Date {
    // Every test input is a fixed ISO-8601 fixture with whole seconds.
    ISO8601DateFormatter().date(from: value)!
}

private final class ErrorCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []
    func append(_ error: any Error) { lock.lock(); defer { lock.unlock() }; values.append(String(describing: error)) }
    var isEmpty: Bool { lock.lock(); defer { lock.unlock() }; return values.isEmpty }
}

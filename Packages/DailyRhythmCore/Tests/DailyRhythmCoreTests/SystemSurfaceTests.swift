import Foundation
import XCTest
@testable import DailyRhythmCore

final class SystemSurfaceTests: XCTestCase {
    func testNamedControlUsesStableIdentityAndRetriesPreserveBytes() throws {
        let f = SurfaceFixture(); defer { f.remove() }
        let a = try f.add(), b = try f.add() // Identical visible names and targets.
        let saved = try f.store.completeCurrentHabit(habitID: b.id, now: f.now)
        let bytes = try Data(contentsOf: f.url)
        XCTAssertEqual(saved.id, "\(b.id)|2026-09-20")
        XCTAssertEqual(saved.completionSource, .appIntent)
        XCTAssertEqual(saved.outcome, .full)
        XCTAssertNil(try f.store.occurrence(id: "\(a.id)|2026-09-20").outcome)
        XCTAssertEqual(try f.store.completeCurrentHabit(habitID: b.id, now: f.now.addingTimeInterval(60)), saved)
        XCTAssertEqual(try Data(contentsOf: f.url), bytes)
    }

    func testControlKeepsLightCompletionAndRequiresReopenForSkip() throws {
        let f = SurfaceFixture(); defer { f.remove() }
        let h = try f.add(), id = "\(h.id)|2026-09-20"
        try f.store.complete(occurrenceID: id, outcome: .light, source: .widget, now: f.now)
        let light = try f.store.occurrence(id: id)
        XCTAssertEqual(try f.store.completeCurrentHabit(habitID: h.id, now: f.now), light)
        try f.store.reopen(occurrenceID: id, now: f.now)
        try f.store.complete(occurrenceID: id, outcome: .skipped, now: f.now)
        let bytes = try Data(contentsOf: f.url)
        expect(.skipped) { _ = try f.store.completeCurrentHabit(habitID: h.id, now: f.now) }
        XCTAssertEqual(try Data(contentsOf: f.url), bytes)
    }

    func testArchiveMissingScheduleAndUnknownHabitDoNotFallBack() throws {
        let f = SurfaceFixture(); defer { f.remove() }
        let archived = try f.add(), monday = try f.add(days: [2]), other = try f.add()
        try f.store.archive(habitID: archived.id, now: f.now)
        let bytes = try Data(contentsOf: f.url)
        expect(.archived) { _ = try f.store.completeCurrentHabit(habitID: archived.id, now: f.now) }
        expect(.noCurrentOccurrence) { _ = try f.store.completeCurrentHabit(habitID: monday.id, now: f.now) }
        XCTAssertThrowsError(try f.store.completeCurrentHabit(habitID: UUID(), now: f.now))
        XCTAssertNil(try f.store.occurrence(id: "\(other.id)|2026-09-20").outcome)
        XCTAssertEqual(try Data(contentsOf: f.url), bytes)
    }

    func testControlResolvesNewDayWithoutCompletingPostponedCarryover() throws {
        let f = SurfaceFixture(); defer { f.remove() }
        let h = try f.add(), old = try f.store.occurrence(id: "\(h.id)|2026-09-20")
        let tomorrow = instant("2026-09-21T12:00:00Z")
        _ = try f.store.perform(.later(until: tomorrow, timeZoneIdentifier: "UTC"), on: old, now: f.now)
        expect(.notReady) { _ = try f.store.completeCurrentHabit(habitID: h.id, now: f.now) }
        let saved = try f.store.completeCurrentHabit(habitID: h.id, now: tomorrow)
        XCTAssertEqual(saved.id, "\(h.id)|2026-09-21")
        XCTAssertNil(try f.store.occurrence(id: old.id).outcome)
        XCTAssertEqual(try f.store.summary(for: f.now).completedCount, 0)
        XCTAssertEqual(try f.store.completeCurrentHabit(habitID: h.id, now: tomorrow), saved)
        XCTAssertNil(try f.store.occurrence(id: old.id).outcome)
    }

    func testInvocationUsesLocalCivilDayAfterTravel() throws {
        let f = SurfaceFixture(); defer { f.remove() }
        let h = try f.add()
        var tokyo = f.calendar; tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let travel = RoutineStore(fileURL: f.url, calendar: tokyo)
        let saved = try travel.completeCurrentHabit(habitID: h.id, now: instant("2026-09-20T16:00:00Z"))
        XCTAssertEqual(saved.dayKey, "2026-09-21")
        XCTAssertNil(try f.store.occurrence(id: "\(h.id)|2026-09-20").outcome)
    }

    func testConcurrentControlInvocationsReturnTheSameCommittedSnapshot() throws {
        let f = SurfaceFixture(); defer { f.remove() }
        let id = try f.add().id, url = f.url, calendar = f.calendar, now = f.now
        let results = SurfaceResults()
        DispatchQueue.concurrentPerform(iterations: 20) { _ in
            let result = try? RoutineStore(fileURL: url, calendar: calendar).completeCurrentHabit(habitID: id, now: now)
            results.append(result)
        }
        XCTAssertEqual(results.items.count, 20)
        let first = try XCTUnwrap(results.items.first)
        XCTAssertTrue(results.items.allSatisfy { $0 == first })
        XCTAssertEqual(try f.store.summary(for: f.now).completedCount, 1)
    }

    func testControlSaveFailurePreservesStoreAndReportsFailure() throws {
        let f = SurfaceFixture(); defer { f.remove() }
        let h = try f.add(), bytes = try Data(contentsOf: f.url)
        let failing = RoutineStore(fileURL: f.url, calendar: f.calendar) { _, _ in throw CocoaError(.fileWriteOutOfSpace) }
        XCTAssertThrowsError(try failing.completeCurrentHabit(habitID: h.id, now: f.now))
        XCTAssertEqual(try Data(contentsOf: f.url), bytes)
        XCTAssertNil(try f.store.occurrence(id: "\(h.id)|2026-09-20").outcome)
        try Data("unreadable store".utf8).write(to: f.url)
        XCTAssertThrowsError(try f.store.completeCurrentHabit(habitID: h.id, now: f.now))
        XCTAssertEqual(try String(contentsOf: f.url, encoding: .utf8), "unreadable store")
    }

    func testStaleVisibleWidgetCannotOverrideLaterOrCompleteTomorrow() throws {
        let f = SurfaceFixture(); defer { f.remove() }
        let h = try f.add(), before = try f.store.occurrence(id: "\(h.id)|2026-09-20")
        _ = try f.store.perform(.later(until: f.now.addingTimeInterval(3600), timeZoneIdentifier: "UTC"), on: before, now: f.now)
        XCTAssertThrowsError(try f.store.perform(.complete(.full), on: before, source: .widget, requiringAgenda: true, now: f.now))
        let another = try f.add(), stale = try f.store.occurrence(id: "\(another.id)|2026-09-20")
        let tomorrow = instant("2026-09-21T00:00:00Z")
        XCTAssertThrowsError(try f.store.perform(.complete(.full), on: stale, source: .widget, requiringAgenda: true, now: tomorrow))
        XCTAssertNil(try f.store.occurrence(id: "\(another.id)|2026-09-21").outcome)
    }

    func testTimelineIncludesUniqueLaterDeadlinesAndPreparedMidnight() throws {
        let f = SurfaceFixture(); defer { f.remove() }
        let deadline = f.now.addingTimeInterval(3600)
        for _ in 0..<2 {
            let h = try f.add(), step = try f.store.occurrence(id: "\(h.id)|2026-09-20")
            _ = try f.store.perform(.later(until: deadline, timeZoneIdentifier: "UTC"), on: step, now: f.now)
        }
        let agenda = try f.store.agenda(at: f.now)
        let dates = agenda.widgetRefreshDates(after: f.now, calendar: f.calendar)
        XCTAssertEqual(dates, [deadline, instant("2026-09-21T00:00:00Z")])
        XCTAssertNil(agenda.next(at: f.now, calendar: f.calendar))
        XCTAssertNotNil(try f.store.agenda(at: dates[0]).next(at: dates[0], calendar: f.calendar))
        XCTAssertEqual(try f.store.agenda(at: dates[1]).summary.dayKey, "2026-09-21")
    }

    func testTimelineHandlesDSTAndAnchoredDueDayBeforeLocalMidnight() throws {
        var newYork = Calendar(identifier: .gregorian); newYork.timeZone = TimeZone(identifier: "America/New_York")!
        let empty = DailyAgenda(summary: DailySummary(dayKey: "2026-03-08", occurrences: []), occurrences: [])
        let spring = instant("2026-03-08T05:00:00Z"), autumn = instant("2026-11-01T04:00:00Z")
        XCTAssertEqual(empty.widgetRefreshDates(after: spring, calendar: newYork)[0].timeIntervalSince(spring), 23 * 3600)
        XCTAssertEqual(empty.widgetRefreshDates(after: autumn, calendar: newYork)[0].timeIntervalSince(autumn), 25 * 3600)
        let f = SurfaceFixture(); defer { f.remove() }
        let h = try f.add(), id = "\(h.id)|2026-09-20"
        try f.store.rescheduleOccurrence(occurrenceID: id, due: .timed(at: instant("2026-09-21T01:00:00Z"), timeZoneIdentifier: "Asia/Tokyo"), now: f.now)
        let agenda = try f.store.agenda(at: f.now)
        XCTAssertEqual(agenda.widgetRefreshDates(after: f.now, calendar: f.calendar), [instant("2026-09-20T15:00:00Z"), instant("2026-09-21T00:00:00Z")])
        XCTAssertNil(agenda.next(at: f.now, calendar: f.calendar))
        XCTAssertNotNil(agenda.next(at: instant("2026-09-20T15:00:00Z"), calendar: f.calendar))
    }

    private func expect(_ error: HabitControlError, _ body: () throws -> Void, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try body(), file: file, line: line) { XCTAssertEqual($0 as? HabitControlError, error, file: file, line: line) }
    }
}

private struct SurfaceFixture {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("Surfaces-\(UUID())/data.json")
    let now = instant("2026-09-20T12:00:00Z")
    var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    var store: RoutineStore { RoutineStore(fileURL: url, calendar: calendar) }
    func add(days: Set<Int> = Set(1...7)) throws -> Habit {
        try store.addHabit(title: "Read", normalTarget: "10 pages", lightTarget: "2 pages", dayPart: .morning, weekdays: days, now: now)
    }
    func remove() { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
}
private func instant(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
private final class SurfaceResults: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var items: [DailyOccurrence] = []
    func append(_ item: DailyOccurrence?) { lock.lock(); defer { lock.unlock() }; if let item { items.append(item) } }
}

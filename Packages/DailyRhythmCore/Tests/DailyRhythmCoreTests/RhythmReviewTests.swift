import XCTest
@testable import DailyRhythmCore

final class RhythmReviewTests: XCTestCase {
    func testEmptyReviewHasSevenOffDaysAndDoesNotCreateADataFile() throws {
        let f = ReviewFixture(); defer { f.remove() }
        let review = try f.store.review(at: instant("2026-09-20T12:00:00Z"))
        XCTAssertEqual(review.days.map(\.id), (14...20).map { "2026-09-\($0)" })
        XCTAssertEqual(review.plannedCount, 0)
        XCTAssertEqual(review.remainingCount, 0)
        XCTAssertEqual(review.days.filter(\.isToday).map(\.id), ["2026-09-20"])
        XCTAssertNil(review.tomorrowFirstStep)
        XCTAssertEqual(review.tomorrow.dayKey, "2026-09-21")
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.url.path))
    }

    func testMixedOutcomesReconcileAndFutureDeferralStaysInItsOriginalDenominator() throws {
        let f = ReviewFixture(); defer { f.remove() }
        let start = instant("2026-09-14T12:00:00Z"), now = instant("2026-09-20T12:00:00Z")
        let habits = try f.store.addHabits([definition("Read"), definition("Walk"), definition("Write")], now: start)
        let once = try f.store.addHabit(definition("Call", recurrence: .once(dayKey: "2026-09-20")), now: start)
        try f.store.complete(occurrenceID: "\(habits[0].id)|2026-09-20", outcome: .full, now: now)
        try f.store.complete(occurrenceID: "\(habits[1].id)|2026-09-20", outcome: .light, now: now)
        let skipped = try f.store.occurrence(id: "\(habits[2].id)|2026-09-20")
        _ = try f.store.perform(.skip, on: skipped, now: now)
        try f.store.rescheduleOccurrence(occurrenceID: "\(once.id)|2026-09-20",
                                         due: .dateOnly(dayKey: "2026-09-22"), now: now)
        let before = try Data(contentsOf: f.url)
        let review = try f.store.review(at: now)
        XCTAssertEqual(review.plannedCount, 22)
        XCTAssertEqual(review.fullCount, 1)
        XCTAssertEqual(review.lightCount, 1)
        XCTAssertEqual(review.skippedCount, 1)
        XCTAssertEqual(review.remainingCount, 19)
        XCTAssertEqual(review.plannedLaterCount, 1)
        XCTAssertEqual(review.days.last?.summary, review.agenda.summary)
        XCTAssertEqual(review.agenda.summary.totalCount, 4)
        XCTAssertEqual(review.agenda.summary.remainingCount, 1)
        XCTAssertEqual(review.tomorrow.totalCount, 3)
        XCTAssertEqual(review.plannedCount, review.fullCount + review.lightCount + review.skippedCount + review.remainingCount)
        XCTAssertEqual(try Data(contentsOf: f.url), before)
    }

    func testEffectiveScheduleArchiveGapsAndOneOffCountOnlyTheirPlannedDays() throws {
        let f = ReviewFixture(); defer { f.remove() }
        let start = instant("2026-09-14T12:00:00Z")
        let edited = try f.store.addHabit(definition("Edited"), now: start)
        let archived = try f.store.addHabit(definition("Archived"), now: start)
        _ = try f.store.addHabit(definition("Once", recurrence: .once(dayKey: "2026-09-18")), now: start)
        try f.store.editHabit(habitID: edited.id, definition: definition("New", recurrence: .weekly(weekdays: [4])),
                             effectiveDayKey: "2026-09-17", now: start)
        try f.store.archive(habitID: archived.id, now: instant("2026-09-16T12:00:00Z"))
        try f.store.restore(habitID: archived.id, now: instant("2026-09-19T12:00:00Z"))
        let now = instant("2026-09-20T12:00:00Z")
        try f.store.complete(occurrenceID: "\(archived.id)|2026-09-20", now: now)
        try f.store.archive(habitID: archived.id, now: now)
        let review = try f.store.review(at: now)
        XCTAssertEqual(review.days.map { $0.summary.totalCount }, [2, 2, 1, 0, 1, 1, 1])
        XCTAssertEqual(review.plannedCount, 8)
        XCTAssertEqual(review.fullCount, 1)
        XCTAssertEqual(review.days.first?.summary.occurrences.first?.title, "Edited")
        XCTAssertEqual(review.tomorrow.totalCount, 0)
        XCTAssertNil(review.tomorrowFirstStep)
        XCTAssertTrue(review.habits.contains { $0.id == archived.id && $0.archivedAt != nil })
    }

    func testLateUndoAndCompletionRecomputeOriginalDayWithoutInflatingToday() throws {
        let f = ReviewFixture(); defer { f.remove() }
        let start = instant("2026-09-14T12:00:00Z"), now = instant("2026-09-20T12:00:00Z")
        let habit = try f.store.addHabit(definition("Once", recurrence: .once(dayKey: "2026-09-14")), now: start)
        let initial = try f.store.occurrence(id: "\(habit.id)|2026-09-14")
        let token = try f.store.perform(.complete(.light), on: initial, now: start)
        XCTAssertEqual(try f.store.review(at: now).lightCount, 1)
        try f.store.undo(token, now: now)
        let reopened = try f.store.review(at: now)
        XCTAssertEqual(reopened.lightCount, 0)
        XCTAssertEqual(reopened.remainingCount, 1)
        XCTAssertEqual(reopened.days.first?.summary.remainingCount, 1)
        XCTAssertEqual(reopened.agenda.summary.totalCount, 0)
        XCTAssertEqual(reopened.agenda.occurrences.map(\.id), [initial.id])
        try f.store.complete(occurrenceID: initial.id, now: now)
        let completed = try f.store.review(at: now)
        XCTAssertEqual(completed.fullCount, 1)
        XCTAssertEqual(completed.remainingCount, 0)
        XCTAssertEqual(completed.agenda.summary.completedCount, 0)
        XCTAssertEqual(completed.days.first?.summary.fullCount, 1)
    }

    func testTomorrowPreviewUsesEffectiveTargetsAndDueOrderWithoutIncludingCarryovers() throws {
        let f = ReviewFixture(); defer { f.remove() }
        let now = instant("2026-09-20T12:00:00Z")
        let early = try f.store.addHabit(definition("Morning"), now: now)
        let timed = try f.store.addHabit(definition("Evening", part: .evening), now: now)
        _ = try f.store.addHabit(definition("Earlier", recurrence: .once(dayKey: "2026-09-20")), now: now)
        var revised = definition("Revised", part: .evening)
        revised.normalTarget = "One revised step"
        revised.dueTime = ScheduledTime(hour: 7, minute: 0, timeZoneIdentifier: "UTC")
        try f.store.editHabit(habitID: timed.id, definition: revised, effectiveDayKey: "2026-09-21", now: now)
        let before = try Data(contentsOf: f.url)
        let preview = try f.store.review(at: now)
        XCTAssertEqual(preview.tomorrowFirstStep?.id, "\(timed.id)|2026-09-21")
        XCTAssertEqual(preview.tomorrowFirstStep?.normalTarget, "One revised step")
        XCTAssertEqual(preview.tomorrow.totalCount, 2)
        XCTAssertEqual(try Data(contentsOf: f.url), before)
        let document = try JSONDecoder().decode(StoreDocument.self, from: before)
        XCTAssertTrue(document.records.isEmpty)
        try f.store.rescheduleOccurrence(occurrenceID: "\(timed.id)|2026-09-21",
                                         due: .dateOnly(dayKey: "2026-09-22"), now: now)
        XCTAssertEqual(try f.store.review(at: now).tomorrowFirstStep?.habitID, early.id)
    }

    func testPinnedOverrideSurvivesFutureScheduleEditAndFutureWorkStaysOutOfWeek() throws {
        let f = ReviewFixture(); defer { f.remove() }
        let now = instant("2026-09-20T12:00:00Z")
        let habit = try f.store.addHabit(definition("Read"), now: now)
        try f.store.updateOccurrence(occurrenceID: "\(habit.id)|2026-09-21", normalTarget: "Pinned step",
                                    lightTarget: nil, durationMinutes: nil, due: .dateOnly(dayKey: "2026-09-21"), now: now)
        try f.store.editHabit(habitID: habit.id, definition: definition("Weekends", recurrence: .weekly(weekdays: [1, 7])),
                             effectiveDayKey: "2026-09-21", now: now)
        let review = try f.store.review(at: now)
        XCTAssertEqual(review.plannedCount, 1)
        XCTAssertEqual(review.tomorrowFirstStep?.normalTarget, "Pinned step")
        XCTAssertEqual(review.tomorrow.totalCount, 1)
    }

    func testLaterCountIncludesTimedAndDeferredWorkButNeverResolvedOutcomes() throws {
        let f = ReviewFixture(); defer { f.remove() }
        let now = instant("2026-09-20T12:00:00Z")
        let habit = try f.store.addHabit(definition("Read"), now: now)
        let item = try f.store.occurrence(id: "\(habit.id)|2026-09-20")
        _ = try f.store.perform(.later(until: now.addingTimeInterval(3600), timeZoneIdentifier: "UTC"), on: item, now: now)
        XCTAssertEqual(try f.store.review(at: now).plannedLaterCount, 1)
        XCTAssertEqual(try f.store.review(at: now.addingTimeInterval(3600)).plannedLaterCount, 0)
        try f.store.complete(occurrenceID: item.id, now: now)
        let done = try f.store.review(at: now)
        XCTAssertEqual(done.plannedLaterCount, 0)
        XCTAssertEqual(done.remainingCount, 0)
        XCTAssertEqual(done.agenda.summary.completedCount, done.agenda.summary.totalCount)
    }

    func testCivilWeekAndTomorrowAcrossDSTAndTravel() throws {
        for (zone, value, today, tomorrow) in [
            ("America/Los_Angeles", "2026-03-09T06:30:00Z", "2026-03-08", "2026-03-09"),
            ("America/Los_Angeles", "2026-11-02T07:30:00Z", "2026-11-01", "2026-11-02"),
            ("Asia/Tokyo", "2026-09-20T23:30:00Z", "2026-09-21", "2026-09-22")
        ] {
            let f = ReviewFixture(zone: zone); defer { f.remove() }
            let review = try f.store.review(at: instant(value))
            XCTAssertEqual(review.days.count, 7)
            XCTAssertEqual(Set(review.days.map(\.id)).count, 7)
            XCTAssertEqual(review.days.last?.id, today)
            XCTAssertEqual(review.tomorrow.dayKey, tomorrow)
        }
    }
}

private struct ReviewFixture {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("RhythmReview-\(UUID())/data.json")
    let calendar: Calendar
    var store: RoutineStore { RoutineStore(fileURL: url, calendar: calendar) }
    init(zone: String = "UTC") {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        self.calendar = calendar
    }
    func remove() { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
}

private func definition(_ title: String, part: DayPart = .morning,
                        recurrence: Recurrence = .weekly(weekdays: Set(1...7))) -> HabitDefinition {
    HabitDefinition(title: title, normalTarget: "One step", lightTarget: "A small step",
                    dayPart: part, recurrence: recurrence)
}

private func instant(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

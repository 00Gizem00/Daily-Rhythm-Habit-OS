import Foundation
import XCTest
@testable import DailyRhythmCore

final class ReminderSchemaMappingTests: XCTestCase {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian); result.timeZone = TimeZone(secondsFromGMT: 0)!
        return result
    }
    private let now = ISO8601DateFormatter().date(from: "2026-09-20T12:00:00Z")!

    func testUndatedOneOffUsesTodayAndOnlyTheUserSuppliedGoal() throws {
        let definition = try ReminderSchemaMapping.definition(title: "  Buy milk  ", dueDate: nil, hasRecurrence: false, now: now, calendar: calendar)
        XCTAssertEqual(definition.title, "Buy milk")
        XCTAssertEqual(definition.normalTarget, "Buy milk")
        XCTAssertEqual(definition.recurrence, .once(dayKey: "2026-09-20"))
        XCTAssertNil(definition.lightTarget)
        XCTAssertNil(definition.durationMinutes)
        XCTAssertNil(definition.dueTime)
    }

    func testDateOnlyHasNoInventedMidnightOrTimezone() throws {
        let input = DateComponents(year: 2026, month: 9, day: 22)
        let definition = try ReminderSchemaMapping.definition(title: "Call", dueDate: input, hasRecurrence: false, now: now, calendar: calendar)
        let due = try definition.due(on: "2026-09-22")
        XCTAssertEqual(due, .dateOnly(dayKey: "2026-09-22"))
        let output = ReminderSchemaMapping.dueComponents(due)
        XCTAssertEqual(output.year, 2026)
        XCTAssertEqual(output.month, 9)
        XCTAssertEqual(output.day, 22)
        XCTAssertNil(output.hour)
        XCTAssertNil(output.timeZone)
    }

    func testNamedTimezoneTimedDueRoundTripsWithoutChangingDateOnlyMeaning() throws {
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let input = DateComponents(timeZone: tokyo, year: 2026, month: 9, day: 22, hour: 8, minute: 35)
        let definition = try ReminderSchemaMapping.definition(title: "Call", dueDate: input, hasRecurrence: false, now: now, calendar: calendar)
        let due = try definition.due(on: "2026-09-22")
        XCTAssertEqual(due.instant, ISO8601DateFormatter().date(from: "2026-09-21T23:35:00Z"))
        let output = ReminderSchemaMapping.dueComponents(due)
        XCTAssertEqual(output.hour, 8)
        XCTAssertEqual(output.minute, 35)
        XCTAssertEqual(output.timeZone, tokyo)
        XCTAssertEqual(output.day, 22)
    }

    func testUnsupportedRecurrenceAndPartialDateFailBeforeSaving() throws {
        XCTAssertThrowsError(try ReminderSchemaMapping.definition(title: "Walk", dueDate: nil, hasRecurrence: true, now: now, calendar: calendar))
        for input in [DateComponents(hour: 8, minute: 0), DateComponents(year: 2026, month: 9),
                      DateComponents(year: 2026, month: 2, day: 30), DateComponents(year: 2026, month: 9, day: 20, hour: 8)] {
            XCTAssertThrowsError(try ReminderSchemaMapping.definition(title: "Walk", dueDate: input, hasRecurrence: false, now: now, calendar: calendar))
        }
    }

    func testNoSilentLossOfUnsupportedDateComponents() throws {
        let plain = DateComponents(year: 2026, month: 9, day: 22, hour: 8, minute: 30)
        var inputs: [DateComponents] = []
        var value = plain; value.second = 17; inputs.append(value)
        value = plain; value.nanosecond = 123; inputs.append(value)
        value = plain; value.weekday = 3; inputs.append(value)
        value = plain; value.weekOfYear = 1; inputs.append(value)
        value = plain; value.calendar = Calendar(identifier: .hebrew); inputs.append(value)
        if #available(macOS 15, iOS 18, *) { value = plain; value.dayOfYear = 265; inputs.append(value) }
        for input in inputs {
            XCTAssertThrowsError(try ReminderSchemaMapping.definition(title: "Walk", dueDate: input, hasRecurrence: false, now: now, calendar: calendar))
        }
        XCTAssertThrowsError(try ReminderSchemaMapping.definition(title: "Walk", dueDate: nil, hasRecurrence: false,
                                                                   now: Date(timeIntervalSinceReferenceDate: .infinity), calendar: calendar))
    }

    func testMappedOneOffUsesSharedStoreForFullCompletionAndReopen() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SchemaMapping-\(UUID())/data.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = RoutineStore(fileURL: url, calendar: calendar)
        let definition = try ReminderSchemaMapping.definition(title: "Schema test", dueDate: nil, hasRecurrence: false, now: now, calendar: calendar)
        let habit = try store.addHabit(definition, now: now)
        let id = "\(habit.id)|2026-09-20"
        let pending = try store.occurrence(id: id)
        try store.complete(occurrenceID: id, source: .appIntent, expectedRevision: pending.revision, now: now)
        let complete = try RoutineStore(fileURL: url, calendar: calendar).occurrence(id: id)
        XCTAssertEqual(complete.outcome, .full)
        XCTAssertEqual(complete.completionSource, .appIntent)
        try store.complete(occurrenceID: id, source: .appIntent, expectedRevision: complete.revision, now: now)
        XCTAssertEqual(try store.occurrence(id: id), complete)
        try store.reopen(occurrenceID: id, expectedRevision: complete.revision, now: now)
        let reopened = try store.occurrence(id: id)
        XCTAssertEqual(reopened.id, id)
        XCTAssertNil(reopened.completedAt)
        XCTAssertNil(reopened.outcome)
        XCTAssertEqual(try store.summary(for: now).totalCount, 1)
        XCTAssertEqual(try store.summary(for: now.addingTimeInterval(86400)).totalCount, 0)
    }
}

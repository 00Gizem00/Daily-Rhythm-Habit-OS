import Foundation
import XCTest
@testable import DailyRhythmCore

/// Test-only entitlement fixtures; the app ships only the Free provider.
struct ProEntitlementFixture: HabitEntitlementProvider {
    func currentEntitlement() -> HabitEntitlement { .pro }
}

final class HabitActivationPolicyTests: XCTestCase {
    func testDefaultFreeCountsHabitsRegardlessOfWeekdayNameOrCompletion() throws {
        let f = try PolicyFixture()
        defer { f.remove() }
        // All share a name; the weekday-only habit is not due on this Sunday.
        _ = try f.store.addHabit(title: "Read", normalTarget: "1 page", dayPart: .morning,
                                weekdays: [2], now: f.now)
        let second = try f.store.addHabit(f.recurring, now: f.now)
        _ = try f.store.addHabit(f.recurring, now: f.now)
        let id = "\(second.id.uuidString)|2026-09-20"
        try f.store.complete(occurrenceID: id, source: .appIntent, now: f.now)
        XCTAssertEqual(try f.store.summary(for: f.now).totalCount, 2)
        let before = try f.bytes()
        expectLimit { _ = try f.store.addHabit(f.recurring, now: f.now) }
        expectLimit {
            _ = try f.store.addHabit(title: "Fourth", normalTarget: "1", dayPart: .evening, now: f.now)
        }
        XCTAssertEqual(try f.bytes(), before)
        XCTAssertEqual(try f.store.habits().count, 3)
        XCTAssertEqual(RoutineStoreError.activeHabitLimitReached.localizedDescription,
                       HabitActivationPolicy.limitMessage)
    }

    func testBatchCapacityCountsEveryHabitAndNeverPartiallyApplies() throws {
        let f = try PolicyFixture()
        defer { f.remove() }
        expectLimit { _ = try f.store.addHabits(Array(repeating: f.recurring, count: 4), now: f.now) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.url.path))
        _ = try f.store.addHabit(f.recurring, now: f.now)
        let before = try f.bytes()
        expectLimit {
            _ = try f.store.addHabits([f.oneOff, f.recurring, f.recurring, f.recurring], now: f.now)
        }
        XCTAssertEqual(try f.bytes(), before, "Do not create even the one-off in a rejected batch")
        let added = try f.store.addHabits([f.oneOff, f.recurring, f.oneOff, f.recurring], now: f.now)
        XCTAssertEqual(added.count, 4)
        XCTAssertEqual(Set(added.map(\.id)).count, 4)
        XCTAssertEqual(try f.store.habits().filter { $0.recurrence.isRecurring }.count, 3)
        XCTAssertEqual(try f.store.habits().count, 5)
        let full = try f.bytes()
        XCTAssertTrue(try f.store.addHabits([], now: f.now).isEmpty)
        XCTAssertEqual(try f.bytes(), full)
    }

    func testInvalidBatchAndDiskFailurePreserveAllOriginalRecords() throws {
        let f = try PolicyFixture()
        defer { f.remove() }
        _ = try f.store.addHabit(f.recurring, now: f.now)
        let before = try f.bytes()
        var invalid = f.recurring
        invalid.title = " "
        expect(.invalidTitle) { _ = try f.store.addHabits([f.recurring, invalid], now: f.now) }
        XCTAssertEqual(try f.bytes(), before)
        let failing = RoutineStore(fileURL: f.url, calendar: f.calendar) { _, _ in
            throw CocoaError(.fileWriteOutOfSpace)
        }
        XCTAssertThrowsError(try failing.addHabits([f.oneOff, f.recurring, f.recurring], now: f.now)) {
            guard case .fileAccess = $0 as? RoutineStoreError else { return XCTFail("Unexpected error: \($0)") }
        }
        XCTAssertEqual(try f.bytes(), before)
        XCTAssertEqual(try f.store.addHabits([f.recurring, f.recurring], now: f.now).count, 2)
    }

    func testArchiveFreesOneSlotAndRestoreChecksCapacityWithoutRewritingHistory() throws {
        let f = try PolicyFixture()
        defer { f.remove() }
        let habits = try f.store.addHabits(Array(repeating: f.recurring, count: 3), now: f.now)
        let historical = try f.store.summary(for: f.now)
        let tomorrow = f.now.addingTimeInterval(86_400)
        try f.store.archive(habitID: habits[0].id, now: tomorrow)
        try f.store.archive(habitID: habits[0].id, now: tomorrow)
        let replacement = try f.store.addHabit(f.recurring, now: tomorrow)
        let full = try f.bytes()
        expectLimit { try f.store.restore(habitID: habits[0].id, now: tomorrow) }
        try f.store.restore(habitID: replacement.id, now: tomorrow) // already active
        XCTAssertEqual(try f.bytes(), full)
        try f.store.archive(habitID: replacement.id, now: tomorrow)
        try f.store.restore(habitID: habits[0].id, now: tomorrow.addingTimeInterval(86_400))
        XCTAssertEqual(try f.store.habits().count, 3)
        XCTAssertEqual(try f.store.summary(for: f.now), historical)
        XCTAssertEqual(try f.store.summary(for: tomorrow).totalCount, 2, "The archive gap remains")
        expectLimit { _ = try f.store.addHabit(f.recurring, now: tomorrow.addingTimeInterval(86_400)) }
    }

    func testBatchRestoreIsAtomicAndDeduplicatesAlreadyActiveAndRepeatedIDs() throws {
        let f = try PolicyFixture()
        defer { f.remove() }
        let habits = try f.store.addHabits([f.recurring, f.recurring, f.recurring, f.oneOff], now: f.now)
        for habit in habits.prefix(2) + [habits[3]] { try f.store.archive(habitID: habit.id, now: f.now) }
        let replacement = try f.store.addHabit(f.recurring, now: f.now)
        let before = try f.bytes()
        expectLimit { try f.store.restore(habitIDs: [habits[0].id, habits[3].id, habits[1].id], now: f.now) }
        XCTAssertEqual(try f.bytes(), before)
        expect(.habitNotFound) { try f.store.restore(habitIDs: [habits[0].id, UUID()], now: f.now) }
        XCTAssertEqual(try f.bytes(), before)
        try f.store.restore(habitIDs: [habits[0].id, habits[0].id, replacement.id, habits[3].id], now: f.now)
        XCTAssertEqual(try f.store.habits().filter { $0.recurrence.isRecurring }.count, 3)
        XCTAssertEqual(try f.store.habits().count, 4)
        let restored = try f.bytes()
        try f.store.restore(habitIDs: [habits[0].id, replacement.id], now: f.now)
        try f.store.restore(habitIDs: [], now: f.now)
        XCTAssertEqual(try f.bytes(), restored)
    }

    func testOneOffCreationAndRestoreRemainAvailableAtCapacityAndCannotBecomeRecurring() throws {
        let f = try PolicyFixture()
        defer { f.remove() }
        _ = try f.store.addHabits(Array(repeating: f.recurring, count: 3), now: f.now)
        let tasks = try f.store.addHabits(Array(repeating: f.oneOff, count: 5), now: f.now)
        let task = tasks[0]
        try f.store.archive(habitID: task.id, now: f.now)
        try f.store.restore(habitID: task.id, now: f.now)
        let id = "\(task.id.uuidString)|2026-09-21"
        try f.store.complete(occurrenceID: id, source: .widget, now: f.now.addingTimeInterval(86_400))
        try f.store.reopen(occurrenceID: id, now: f.now.addingTimeInterval(86_400))
        expect(.unsupportedRecurrenceChange) {
            try f.store.editHabit(habitID: task.id, definition: f.recurring,
                                  effectiveDayKey: "2026-09-22", now: f.now.addingTimeInterval(86_400))
        }
        expectLimit { _ = try f.store.addHabit(f.recurring, now: f.now) }
        XCTAssertEqual(try f.store.habits().count, 8)
    }

    func testConcurrentFreeCreatorsAllowExactlyThreeIndependentStores() throws {
        let f = try PolicyFixture()
        defer { f.remove() }
        let results = PolicyResults()
        DispatchQueue.concurrentPerform(iterations: 40) { _ in
            results.record { _ = try f.independentStore().addHabit(f.recurring, now: f.now) }
        }
        XCTAssertEqual(results.successes, 3)
        XCTAssertEqual(results.limitFailures, 37)
        XCTAssertEqual(results.unexpectedErrors, [])
        XCTAssertEqual(try f.store.habits().count, 3)
    }

    func testConcurrentBatchRequestsNeverSplitTheLastSlots() throws {
        let f = try PolicyFixture()
        defer { f.remove() }
        let results = PolicyResults()
        DispatchQueue.concurrentPerform(iterations: 20) { _ in
            results.record { _ = try f.independentStore().addHabits([f.recurring, f.recurring], now: f.now) }
        }
        XCTAssertEqual(results.successes, 1)
        XCTAssertEqual(results.limitFailures, 19)
        XCTAssertEqual(results.unexpectedErrors, [])
        XCTAssertEqual(try f.store.habits().count, 2)
        _ = try f.store.addHabit(f.recurring, now: f.now)
        expectLimit { _ = try f.store.addHabit(f.recurring, now: f.now) }
    }

    func testConcurrentCreateAndRestoreCompeteForTheSameLastSlot() throws {
        let f = try PolicyFixture()
        defer { f.remove() }
        let pro = RoutineStore(fileURL: f.url, calendar: f.calendar, entitlementProvider: ProEntitlementFixture())
        let archived = try pro.addHabits(Array(repeating: f.recurring, count: 20), now: f.now)
        for habit in archived { try pro.archive(habitID: habit.id, now: f.now) }
        _ = try f.store.addHabits([f.recurring, f.recurring], now: f.now)
        let results = PolicyResults()
        DispatchQueue.concurrentPerform(iterations: 40) { index in
            results.record {
                let store = f.independentStore()
                if index < archived.count { try store.restore(habitID: archived[index].id, now: f.now) }
                else { _ = try store.addHabit(f.recurring, now: f.now) }
            }
        }
        XCTAssertEqual(results.successes, 1)
        XCTAssertEqual(results.limitFailures, 39)
        XCTAssertEqual(results.unexpectedErrors, [])
        XCTAssertEqual(try f.store.habits().count, 3)
    }

    func testDowngradeKeepsExistingDataAndCoreOperationsAvailable() throws {
        let f = try PolicyFixture()
        defer { f.remove() }
        let provider = MutableEntitlementFixture(.pro)
        let store = RoutineStore(fileURL: f.url, calendar: f.calendar, entitlementProvider: provider)
        let habits = try store.addHabits(Array(repeating: f.recurring, count: 5), now: f.now)
        let original = try f.bytes()
        provider.set(.free)
        XCTAssertEqual(try store.habits(), habits)
        XCTAssertEqual(try f.bytes(), original, "Downgrade does not archive or delete anything")
        expectLimit { _ = try store.addHabit(f.recurring, now: f.now) }
        for (index, source) in [CompletionSource.app, .widget, .appIntent].enumerated() {
            let id = "\(habits[index].id.uuidString)|2026-09-20"
            try store.complete(occurrenceID: id, outcome: .full, source: source, now: f.now)
            try store.reopen(occurrenceID: id, now: f.now)
            try store.complete(occurrenceID: id, outcome: .light, source: source, now: f.now)
            XCTAssertEqual(try store.occurrence(id: id).completionSource, source)
        }
        XCTAssertEqual(try store.history(days: 1, endingOn: f.now).first?.lightCount, 3)
        var edited = f.recurring
        edited.normalTarget = "20 pages"
        edited.recurrence = .weekly(weekdays: [2])
        try store.editHabit(habitID: habits[4].id, definition: edited, effectiveDayKey: "2026-09-21", now: f.now)
        _ = try store.addHabit(f.oneOff, now: f.now) // allowed even while over the cap
        try store.restore(habitID: habits[0].id, now: f.now) // already active, still allowed
        try store.archive(habitID: habits[4].id, now: f.now)
        expectLimit { try store.restore(habitID: habits[4].id, now: f.now) }
        try store.archive(habitID: habits[3].id, now: f.now)
        expectLimit { _ = try store.addHabit(f.recurring, now: f.now) } // exactly three
        try store.archive(habitID: habits[2].id, now: f.now)
        _ = try store.addHabit(f.recurring, now: f.now)
        XCTAssertEqual(try store.habits().filter { $0.recurrence.isRecurring }.count, 3)
        XCTAssertEqual(try store.habits(includeArchived: true).count, 7)
    }

    func testExistingStoreRechecksCurrentEntitlementForEachActivation() throws {
        let f = try PolicyFixture()
        defer { f.remove() }
        let provider = MutableEntitlementFixture(.free)
        let store = RoutineStore(fileURL: f.url, calendar: f.calendar, entitlementProvider: provider)
        _ = try store.addHabits(Array(repeating: f.recurring, count: 3), now: f.now)
        expectLimit { _ = try store.addHabit(f.recurring, now: f.now) }
        provider.set(.pro)
        let fourth = try store.addHabit(f.recurring, now: f.now)
        try store.archive(habitID: fourth.id, now: f.now)
        provider.set(.free)
        expectLimit { try store.restore(habitID: fourth.id, now: f.now) }
        provider.set(.pro)
        try store.restore(habitID: fourth.id, now: f.now)
        provider.set(.free)
        expectLimit { _ = try store.addHabits([f.recurring, f.oneOff], now: f.now) }
        XCTAssertEqual(try store.habits().count, 4)
    }

    func testOverLimitLegacyDataCanMigrateAndCompleteWithoutBeingPruned() throws {
        let f = try PolicyFixture()
        defer { f.remove() }
        let fixtureURL = try XCTUnwrap(Bundle.module.url(forResource: "v1-mixed", withExtension: "json", subdirectory: "Fixtures"))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as? [String: Any])
        var habits = try XCTUnwrap(object["habits"] as? [[String: Any]])
        for _ in 0..<2 {
            var copy = habits[0]
            copy["id"] = UUID().uuidString
            habits.append(copy)
        }
        object["habits"] = habits
        let original = try JSONSerialization.data(withJSONObject: object)
        try original.write(to: f.url)
        expectLimit { _ = try f.store.addHabit(f.recurring, now: f.now) }
        expectLimit { try f.store.restore(habitID: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!, now: f.now) }
        XCTAssertEqual(try f.bytes(), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.store.migrationBackupURL.path))
        XCTAssertEqual(try f.store.habits(includeArchived: true).count, 5)
        XCTAssertEqual(try f.store.habits().count, 4)
        XCTAssertEqual(try Data(contentsOf: f.store.migrationBackupURL), original)
        let id = "11111111-1111-4111-8111-111111111111|2026-09-20"
        try f.store.complete(occurrenceID: id, source: .appIntent, now: f.now)
        XCTAssertEqual(try f.store.occurrence(id: id).outcome, .full)
        XCTAssertEqual(try f.store.history(days: 3, endingOn: f.now).count, 3)
    }

    private func expectLimit(_ action: () throws -> Void, file: StaticString = #filePath, line: UInt = #line) {
        expect(.activeHabitLimitReached, action, file: file, line: line)
    }

    private func expect(_ expected: RoutineStoreError, _ action: () throws -> Void,
                        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try action(), file: file, line: line) {
            XCTAssertEqual($0 as? RoutineStoreError, expected, file: file, line: line)
        }
    }
}

private struct PolicyFixture: Sendable {
    let directory: URL
    let url: URL
    let calendar: Calendar
    let store: RoutineStore
    let now = Date(timeIntervalSince1970: 1_789_905_600) // 2026-09-20 12:00 UTC
    let recurring = HabitDefinition(title: "Read", normalTarget: "10 pages", lightTarget: "2 pages",
                                    dayPart: .morning, recurrence: .weekly(weekdays: Set(1...7)))
    let oneOff = HabitDefinition(title: "Call", normalTarget: "1 call", dayPart: .evening,
                                 recurrence: .once(dayKey: "2026-09-21"))

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("HabitPolicyTests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("routines.json")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        self.calendar = calendar
        store = RoutineStore(fileURL: url, calendar: calendar)
    }

    func independentStore() -> RoutineStore { RoutineStore(fileURL: url, calendar: calendar) }
    func bytes() throws -> Data { try Data(contentsOf: url) }
    func remove() { try? FileManager.default.removeItem(at: directory) }
}

private final class MutableEntitlementFixture: HabitEntitlementProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var value: HabitEntitlement
    init(_ value: HabitEntitlement) { self.value = value }
    func set(_ value: HabitEntitlement) { lock.lock(); defer { lock.unlock() }; self.value = value }
    func currentEntitlement() -> HabitEntitlement { lock.lock(); defer { lock.unlock() }; return value }
}

private final class PolicyResults: @unchecked Sendable {
    private let lock = NSLock()
    private var accepted = 0
    private var rejected = 0
    private var errors: [String] = []
    func record(_ action: () throws -> Void) {
        do {
            try action()
            lock.lock(); defer { lock.unlock() }; accepted += 1
        } catch {
            lock.lock(); defer { lock.unlock() }
            if error as? RoutineStoreError == .activeHabitLimitReached { rejected += 1 }
            else { errors.append(String(describing: error)) }
        }
    }
    var successes: Int { lock.lock(); defer { lock.unlock() }; return accepted }
    var limitFailures: Int { lock.lock(); defer { lock.unlock() }; return rejected }
    var unexpectedErrors: [String] { lock.lock(); defer { lock.unlock() }; return errors }
}

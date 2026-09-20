import Foundation
import XCTest
@testable import DailyRhythmCore

final class OnboardingTests: XCTestCase {
    func testTemplatesAndCancelledDraftsCreateNoHiddenHabits() throws {
        let f = SetupFixture(); defer { f.remove() }
        for template in [OnboardingTemplate.morning, .evening] {
            var draft = OnboardingDraft(template: template, now: f.now, calendar: f.calendar)
            XCTAssertEqual(draft.entries.count, 2)
            for entry in draft.entries {
                let definition = try entry.form.definition()
                XCTAssertEqual(definition.dayPart, template == .morning ? .morning : .evening)
                XCTAssertNotNil(definition.lightTarget)
                XCTAssertEqual(definition.recurrence.weekdays, Set(1...7))
            }
            draft.entries[0].form.normalTarget = "My unsaved change"
            _ = try JSONEncoder().encode(draft) // saving a resumable draft is not applying habits
        }
        XCTAssertTrue(try f.store.habits(asOf: f.now).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.url.path))
    }

    func testManualSetupAndFirstRealCompletionWithoutAccountOrAI() throws {
        let f = SetupFixture(); defer { f.remove() }
        var draft = OnboardingDraft(template: .manual, now: f.now, calendar: f.calendar)
        draft.entries[0].form.title = "Read my book"
        draft.entries[0].form.normalTarget = "Read 5 pages"
        draft.entries[0].form.hasLightTarget = true
        draft.entries[0].form.lightTarget = "Read 1 page"
        let habits = try f.store.createInitialRoutine(draft, now: f.now)
        XCTAssertEqual(habits.map(\.id), draft.entries.map(\.id))
        let step = try XCTUnwrap(f.store.agenda(at: f.now).next(at: f.now, calendar: f.calendar))
        _ = try f.store.perform(.complete(.full), on: step, requiringAgenda: true, now: f.now)
        XCTAssertEqual(try f.store.summary(for: f.now).fullCount, 1)
        XCTAssertEqual(try f.store.habits(asOf: f.now)[0].normalTarget, "Read 5 pages")
    }

    func testResumeAndRepeatedConfirmationKeepIDsAndBytes() throws {
        let f = SetupFixture(); defer { f.remove() }
        var progress = OnboardingProgress()
        progress.status = .inProgress
        progress.draft = OnboardingDraft(template: .morning, now: f.now, calendar: f.calendar)
        progress.draft!.entries[0].form.title = "My morning stretch"
        progress.status = .skipped
        let restored = try JSONDecoder().decode(OnboardingProgress.self, from: JSONEncoder().encode(progress))
        XCTAssertEqual(restored, progress)
        let draft = try XCTUnwrap(restored.draft)
        _ = try f.store.createInitialRoutine(draft, now: f.now)
        let bytes = try Data(contentsOf: f.url)
        let reloadedStore = RoutineStore(fileURL: f.url, calendar: f.calendar)
        for _ in 0..<3 { _ = try reloadedStore.createInitialRoutine(draft, now: f.now.addingTimeInterval(60)) }
        XCTAssertEqual(try Data(contentsOf: f.url), bytes)
        XCTAssertEqual(try reloadedStore.habits(asOf: f.now).count, 2)
    }

    func testConcurrentConfirmationsDoNotCreateCopies() throws {
        let f = SetupFixture(); defer { f.remove() }
        let draft = OnboardingDraft(template: .evening, now: f.now, calendar: f.calendar)
        let results = SetupResults(), url = f.url, calendar = f.calendar, now = f.now
        DispatchQueue.concurrentPerform(iterations: 20) { _ in
            do {
                _ = try RoutineStore(fileURL: url, calendar: calendar).createInitialRoutine(draft, now: now)
                results.add(nil)
            } catch { results.add(error) }
        }
        XCTAssertEqual(results.successes, 20)
        XCTAssertTrue(results.errors.isEmpty)
        XCTAssertEqual(Set(try f.store.habits(asOf: f.now).map(\.id)), Set(draft.entries.map(\.id)))
    }

    func testCompetingDifferentDraftsNeverPartiallyApply() throws {
        let f = SetupFixture(); defer { f.remove() }
        let drafts = [OnboardingDraft(template: .morning), OnboardingDraft(template: .evening)]
        let results = SetupResults(), url = f.url, calendar = f.calendar, now = f.now
        DispatchQueue.concurrentPerform(iterations: 2) { index in
            do {
                _ = try RoutineStore(fileURL: url, calendar: calendar).createInitialRoutine(drafts[index], now: now)
                results.add(nil)
            } catch { results.add(error) }
        }
        XCTAssertEqual(results.successes, 1)
        XCTAssertEqual(results.errors, [.onboardingAlreadyStarted])
        let ids = Set(try f.store.habits(asOf: f.now).map(\.id))
        XCTAssertTrue(drafts.contains { Set($0.entries.map(\.id)) == ids })
    }

    func testConfirmationRetryDoesNotRestoreOrRewriteEditedHabit() throws {
        let f = SetupFixture(); defer { f.remove() }
        let draft = OnboardingDraft(template: .morning, now: f.now, calendar: f.calendar)
        let habits = try f.store.createInitialRoutine(draft, now: f.now)
        var future = habits[0].definition; future.normalTarget = "New goal"
        try f.store.editHabit(habitID: habits[0].id, definition: future, effectiveDayKey: "2026-09-21", now: f.now)
        try f.store.archive(habitID: habits[1].id, now: f.now)
        let bytes = try Data(contentsOf: f.url)
        _ = try f.store.createInitialRoutine(draft, now: f.now.addingTimeInterval(86400))
        XCTAssertEqual(try Data(contentsOf: f.url), bytes)
        XCTAssertEqual(try f.store.habits(asOf: f.now.addingTimeInterval(86400)).first?.normalTarget, "New goal")
        XCTAssertEqual(try f.store.habits(includeArchived: true, asOf: f.now).filter { $0.archivedAt != nil }.count, 1)
    }

    func testExistingManualOrArchivedPlanPreventsAnotherFirstRunApply() throws {
        let f = SetupFixture(); defer { f.remove() }
        let habit = try f.store.addHabit(title: "Existing", normalTarget: "My goal", dayPart: .morning, now: f.now)
        try f.store.archive(habitID: habit.id, now: f.now)
        let bytes = try Data(contentsOf: f.url)
        expect(.onboardingAlreadyStarted) {
            _ = try f.store.createInitialRoutine(OnboardingDraft(template: .evening), now: f.now)
        }
        XCTAssertEqual(try Data(contentsOf: f.url), bytes)
    }

    func testInvalidOrOversizedDraftCannotCreatePartialRecordsAndThreeFitsFree() throws {
        let f = SetupFixture(); defer { f.remove() }
        var draft = OnboardingDraft(template: .morning, now: f.now, calendar: f.calendar)
        draft.entries.append(contentsOf: OnboardingDraft(template: .evening, now: f.now, calendar: f.calendar).entries)
        expect(.invalidOnboardingDraft) { _ = try f.store.createInitialRoutine(draft, now: f.now) }
        draft.entries.removeLast()
        var invalid = draft
        invalid.entries[1].form.title = ""
        expect(.invalidTitle) { _ = try f.store.createInitialRoutine(invalid, now: f.now) }
        invalid = draft; invalid.entries[1] = invalid.entries[0]
        expect(.invalidOnboardingDraft) { _ = try f.store.createInitialRoutine(invalid, now: f.now) }
        invalid = draft; invalid.entries[1].form.isRecurring = false
        expect(.invalidOnboardingDraft) { _ = try f.store.createInitialRoutine(invalid, now: f.now) }
        invalid.entries = []
        expect(.invalidOnboardingDraft) { _ = try f.store.createInitialRoutine(invalid, now: f.now) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.url.path))
        XCTAssertEqual(try f.store.createInitialRoutine(draft, now: f.now).count, 3)
        expect(.activeHabitLimitReached) {
            _ = try f.store.addHabit(title: "Fourth", normalTarget: "Goal", dayPart: .morning, now: f.now)
        }
    }

    func testFailedConfirmationPreservesDraftAndStoreForRetry() throws {
        let f = SetupFixture(); defer { f.remove() }
        let draft = OnboardingDraft(template: .morning, now: f.now, calendar: f.calendar)
        let failing = RoutineStore(fileURL: f.url, calendar: f.calendar) { _, _ in throw CocoaError(.fileWriteOutOfSpace) }
        XCTAssertThrowsError(try failing.createInitialRoutine(draft, now: f.now))
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.url.path))
        let saved = try f.store.createInitialRoutine(draft, now: f.now)
        XCTAssertEqual(saved.map(\.id), draft.entries.map(\.id))
    }

    func testFirstRunOfferDoesNotInterruptReturningOrSkippedUsers() throws {
        var progress = OnboardingProgress()
        XCTAssertTrue(progress.shouldOfferAutomatically(hasExistingHabits: false))
        XCTAssertFalse(progress.shouldOfferAutomatically(hasExistingHabits: true))
        for status in [OnboardingProgress.Status.inProgress, .skipped, .finished] {
            progress.status = status
            XCTAssertFalse(progress.shouldOfferAutomatically(hasExistingHabits: false))
        }
    }

    private func expect(_ error: RoutineStoreError, _ body: () throws -> Void, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try body(), file: file, line: line) { XCTAssertEqual($0 as? RoutineStoreError, error, file: file, line: line) }
    }
}

private struct SetupFixture {
    let url: URL
    let calendar: Calendar
    let store: RoutineStore
    let now = ISO8601DateFormatter().date(from: "2026-09-20T12:00:00Z")!
    init() {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("Onboarding-\(UUID())/data.json")
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        self.calendar = calendar; store = RoutineStore(fileURL: url, calendar: calendar)
    }
    func remove() { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
}
private final class SetupResults: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var successes = 0
    private(set) var errors: [RoutineStoreError] = []
    func add(_ error: Error?) {
        lock.lock(); defer { lock.unlock() }
        if let error { errors.append(error as? RoutineStoreError ?? .corruptData) }
        else { successes += 1 }
    }
}

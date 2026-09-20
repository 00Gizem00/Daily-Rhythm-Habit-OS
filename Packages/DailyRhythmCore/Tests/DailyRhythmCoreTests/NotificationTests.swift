import XCTest
@testable import DailyRhythmCore

@MainActor
final class NotificationTests: XCTestCase {
    func testDefaultsAreOffAndReconciliationNeverAsksPermissionOrSeedsData() async throws {
        let f = NotificationFixture(); defer { f.remove() }
        let status = try await f.coordinator().reconcile()
        XCTAssertFalse(status.preferences.timedSteps)
        XCTAssertFalse(status.preferences.dailyClose)
        XCTAssertEqual(status.pendingCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.preferencesURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.store.fileURL.path))
    }

    func testEnableRepeatAndIndependentOptOutHaveStableRequestsAndPreserveForeignIDs() async throws {
        let f = NotificationFixture(); defer { f.remove() }
        _ = try f.addTimed()
        await f.client.seedForeign()
        let first = try await f.coordinator().update(.timedSteps(true))
        XCTAssertEqual(first.pendingCount, 7)
        let initial = await f.client.requests()
        _ = try await f.coordinator().reconcile()
        let repeated = await f.client.requests(), additions = await f.client.additions
        XCTAssertEqual(initial, repeated)
        XCTAssertEqual(additions, 7)
        let both = try await f.coordinator().update(.dailyClose(true))
        XCTAssertEqual(both.pendingCount, 14)
        let onlyClose = try await f.coordinator().update(.timedSteps(false))
        XCTAssertEqual(onlyClose.pendingCount, 7)
        let none = try await f.coordinator().update(.dailyClose(false))
        XCTAssertEqual(none.pendingCount, 0)
        let remaining = await f.client.pending(), delivered = await f.client.deliveredIDs()
        XCTAssertEqual(remaining.map(\.id), ["unrelated.request"])
        XCTAssertEqual(delivered, ["unrelated.delivered"])
    }

    func testDeniedAndRevokedPermissionClearOurQueueWhilePreservingPreferencesAndTracking() async throws {
        let f = NotificationFixture(); defer { f.remove() }
        let step = try f.addTimed()
        await f.client.setAuthorization(.denied)
        let denied = try await f.coordinator().update(.timedSteps(true))
        XCTAssertEqual(denied.pendingCount, 0)
        XCTAssertTrue(denied.preferences.timedSteps)
        await f.client.setAuthorization(.authorized)
        let granted = try await f.coordinator().reconcile()
        XCTAssertEqual(granted.pendingCount, 7)
        await f.client.setAuthorization(.denied)
        let revoked = try await f.coordinator().reconcile()
        XCTAssertEqual(revoked.pendingCount, 0)
        try f.store.complete(occurrenceID: step.id, now: f.clock.read())
        XCTAssertEqual(try f.store.summary(for: f.clock.read()).fullCount, 1)
    }

    func testCompletionReopenSkipArchiveAndEditsReconcileOnlyTheExactOccurrence() async throws {
        let f = NotificationFixture(); defer { f.remove() }
        let step = try f.addTimed(), id = RhythmNotificationRequest.prefix + "step." + step.id
        _ = try await f.coordinator().update(.timedSteps(true))
        try f.store.complete(occurrenceID: step.id, now: f.clock.read())
        _ = try await f.coordinator().reconcile()
        var requests = await f.client.requests()
        XCTAssertFalse(requests.contains { $0.id == id })
        XCTAssertEqual(requests.count, 6)
        try f.store.reopen(occurrenceID: step.id, now: f.clock.read())
        _ = try await f.coordinator().reconcile()
        requests = await f.client.requests()
        XCTAssertTrue(requests.contains { $0.id == id })
        let fresh = try f.store.occurrence(id: step.id)
        let until = f.clock.read().addingTimeInterval(7200)
        let undo = try f.store.perform(.later(until: until, timeZoneIdentifier: "UTC"), on: fresh, now: f.clock.read())
        _ = try await f.coordinator().reconcile()
        requests = await f.client.requests()
        XCTAssertEqual(requests.first { $0.id == id }?.fireDate, until)
        try f.store.undo(undo, now: f.clock.read())
        _ = try f.store.perform(.skip, on: f.store.occurrence(id: step.id), now: f.clock.read())
        _ = try await f.coordinator().reconcile()
        requests = await f.client.requests()
        XCTAssertFalse(requests.contains { $0.id == id })
        var nextPlan = timedDefinition()
        nextPlan.dueTime = ScheduledTime(hour: 18, minute: 45, timeZoneIdentifier: "UTC")
        try f.store.editHabit(habitID: step.habitID, definition: nextPlan, effectiveDayKey: "2026-09-21", now: f.clock.read())
        _ = try await f.coordinator().reconcile()
        requests = await f.client.requests()
        XCTAssertEqual(requests.first?.fireDate, notificationDate("2026-09-21T18:45:00Z"))
        try f.store.archive(habitID: step.habitID, now: f.clock.read())
        let archived = try await f.coordinator().reconcile()
        XCTAssertEqual(archived.pendingCount, 0)
    }

    func testDateOnlyIsSilentAndOldLaterKeepsItsOriginalDeepLink() throws {
        let f = NotificationFixture(); defer { f.remove() }
        let old = notificationDate("2026-09-01T12:00:00Z")
        let habit = try f.store.addHabit(HabitDefinition(title: "Once", normalTarget: "One step", dayPart: .morning,
                                                       recurrence: .once(dayKey: "2026-09-01")), now: old)
        var preferences = RhythmNotificationPreferences(); preferences.timedSteps = true
        XCTAssertTrue(try f.store.notificationPlan(preferences: preferences, at: f.clock.read()).isEmpty)
        let step = try f.store.occurrence(id: "\(habit.id)|2026-09-01")
        _ = try f.store.perform(.later(until: notificationDate("2026-09-21T09:00:00Z"), timeZoneIdentifier: "UTC"),
                                on: step, now: f.clock.read())
        let before = try Data(contentsOf: f.store.fileURL)
        let plan = try f.store.notificationPlan(preferences: preferences, at: f.clock.read())
        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(plan.first?.destination, .occurrence(step.id))
        XCTAssertEqual(try Data(contentsOf: f.store.fileURL), before)
    }

    func testQueueIsBoundedAndReservesDailyCloseWithoutDuplicates() throws {
        let f = NotificationFixture(); defer { f.remove() }
        let definitions = (0..<80).map { i in
            HabitDefinition(title: "Step \(i)", normalTarget: "One", dayPart: .morning,
                recurrence: .once(dayKey: "2026-09-20"), dueTime: ScheduledTime(hour: 15, minute: 0, timeZoneIdentifier: "UTC"))
        }
        _ = try f.store.addHabits(definitions, now: f.clock.read())
        var preferences = RhythmNotificationPreferences(); preferences.timedSteps = true; preferences.dailyClose = true
        let plan = try f.store.notificationPlan(preferences: preferences, at: f.clock.read())
        XCTAssertEqual(plan.count, 56)
        XCTAssertEqual(Set(plan.map(\.id)).count, 56)
        XCTAssertEqual(plan.filter { if case .day = $0.destination { true } else { false } }.count, 7)
        XCTAssertTrue(plan.allSatisfy { $0.fireDate > f.clock.read() })
        XCTAssertFalse(plan.contains { $0.body.contains("completed") || $0.body.contains("80") })
    }

    func testTimezoneAndDSTRecomputeCloseButPreserveSavedTimedInstants() throws {
        let f = NotificationFixture(); defer { f.remove() }
        _ = try f.addTimed()
        var preferences = RhythmNotificationPreferences(); preferences.timedSteps = true; preferences.dailyClose = true
        let utc = try f.store.notificationPlan(preferences: preferences, at: f.clock.read())
        var tokyo = f.calendar; tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let travel = RoutineStore(fileURL: f.store.fileURL, calendar: tokyo)
        let shifted = try travel.notificationPlan(preferences: preferences, at: f.clock.read())
        let id = RhythmNotificationRequest.prefix + "close.2026-09-21"
        XCTAssertEqual(utc.first { $0.id == id }?.fireDate, notificationDate("2026-09-21T20:30:00Z"))
        XCTAssertEqual(shifted.first { $0.id == id }?.fireDate, notificationDate("2026-09-21T11:30:00Z"))
        let stepID = utc.first { if case .occurrence = $0.destination { true } else { false } }!.id
        XCTAssertEqual(utc.first { $0.id == stepID }?.fireDate, shifted.first { $0.id == stepID }?.fireDate)
        var la = f.calendar; la.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let dst = RoutineStore(fileURL: f.store.fileURL, calendar: la)
        preferences.timedSteps = false; preferences.closeHour = 2; preferences.closeMinute = 30
        let spring = try dst.notificationPlan(preferences: preferences, at: notificationDate("2026-03-08T08:00:00Z"))
        XCTAssertEqual(spring.first?.fireDate, notificationDate("2026-03-08T10:00:00Z"))
        preferences.closeHour = 1
        let fall = try dst.notificationPlan(preferences: preferences, at: notificationDate("2026-11-01T07:00:00Z"))
        XCTAssertEqual(fall.first?.fireDate, notificationDate("2026-11-01T08:30:00Z"))
        XCTAssertEqual(fall.count, 7)
    }

    func testLateRefreshDoesNotReplayElapsedNotificationsAndExtendsTheWindow() async throws {
        let f = NotificationFixture(); defer { f.remove() }
        _ = try f.addTimed()
        _ = try await f.coordinator().update(.timedSteps(true))
        f.clock.set(notificationDate("2026-09-21T16:00:00Z"))
        _ = try await f.coordinator().reconcile()
        let requests = await f.client.requests()
        XCTAssertTrue(requests.allSatisfy { $0.fireDate > f.clock.read() })
        XCTAssertEqual(requests.first?.fireDate, notificationDate("2026-09-22T15:00:00Z"))
        XCTAssertEqual(requests.last?.fireDate, notificationDate("2026-09-27T15:00:00Z"))
    }

    func testConcurrentPreferenceChangesAcrossCoordinatorInstancesDoNotLoseOptOut() async throws {
        let f = NotificationFixture(); defer { f.remove() }
        _ = try f.addTimed()
        let a = f.coordinator(), b = f.coordinator()
        async let first = a.update(.timedSteps(true))
        async let second = b.update(.dailyClose(true))
        _ = try await (first, second)
        let saved = try a.preferences()
        XCTAssertTrue(saved.timedSteps && saved.dailyClose)
        async let refresh = a.reconcile()
        async let disable = b.update(.timedSteps(false))
        _ = try await (refresh, disable)
        let pending = await f.client.requests()
        XCTAssertEqual(pending.count, 7)
        XCTAssertTrue(pending.allSatisfy { if case .day = $0.destination { true } else { false } })
        XCTAssertFalse(try a.preferences().timedSteps)
    }

    func testSchedulingFailureClearsPartialQueueAndAllowsRetryWithSavedPreferences() async throws {
        let f = NotificationFixture(); defer { f.remove() }
        _ = try f.addTimed()
        await f.client.failNextAdd()
        do { _ = try await f.coordinator().update(.timedSteps(true)); XCTFail("Expected failure") }
        catch {}
        let pending = await f.client.requests()
        XCTAssertTrue(pending.isEmpty)
        XCTAssertTrue(try f.coordinator().preferences().timedSteps)
        let retry = try await f.coordinator().reconcile()
        XCTAssertEqual(retry.pendingCount, 7)
    }

    func testCorruptPreferencesAndStoreArePreservedAndDoNotKeepObsoleteNudges() async throws {
        let f = NotificationFixture(); defer { f.remove() }
        _ = try f.addTimed()
        _ = try await f.coordinator().update(.timedSteps(true))
        let original = try Data(contentsOf: f.preferencesURL)
        let corrupt = Data("{\"version\":99}".utf8)
        try corrupt.write(to: f.preferencesURL)
        do { _ = try await f.coordinator().reconcile(); XCTFail("Expected invalid preferences") } catch {}
        XCTAssertEqual(try Data(contentsOf: f.preferencesURL), corrupt)
        var pending = await f.client.requests(); XCTAssertTrue(pending.isEmpty)
        try original.write(to: f.preferencesURL)
        _ = try await f.coordinator().reconcile()
        let invalidStore = Data("invalid store".utf8); try invalidStore.write(to: f.store.fileURL)
        do { _ = try await f.coordinator().reconcile(); XCTFail("Expected invalid store") } catch {}
        XCTAssertEqual(try Data(contentsOf: f.store.fileURL), invalidStore)
        pending = await f.client.requests(); XCTAssertTrue(pending.isEmpty)
        let disabled = try await f.coordinator().update(.timedSteps(false))
        XCTAssertEqual(disabled.pendingCount, 0)
    }

    func testRoutesRoundTripExactIdentityAndRejectMalformedOrAmbiguousLinks() {
        let id = "\(UUID().uuidString)|2026-09-20"
        for destination in [RhythmNotificationDestination.occurrence(id), .day("2026-09-20")] {
            XCTAssertEqual(RhythmNotificationDestination(url: destination.url), destination)
        }
        for raw in ["https://step?id=\(id)", "daily-rhythm://review?day=2026-02-30",
                    "daily-rhythm://review?day=2026-09-20&day=2026-09-21", "daily-rhythm://step?id=next",
                    "daily-rhythm://review/path?day=2026-09-20", "daily-rhythm://user@review?day=2026-09-20"] {
            XCTAssertNil(RhythmNotificationDestination(url: URL(string: raw)!))
        }
    }
}

private struct NotificationFixture {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("NotificationTests-\(UUID())")
    let calendar: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }()
    let clock = NotificationTestClock()
    let client = NotificationTestClient()
    var store: RoutineStore { RoutineStore(fileURL: directory.appendingPathComponent("data.json"), calendar: calendar) }
    var preferencesURL: URL { directory.appendingPathComponent("notifications.json") }
    func coordinator() -> RhythmNotificationCoordinator {
        let store = store, clock = clock
        return RhythmNotificationCoordinator(preferencesURL: preferencesURL, client: client, now: { clock.read() }) {
            preferences, now in try store.notificationPlan(preferences: preferences, at: now)
        }
    }
    func addTimed() throws -> DailyOccurrence {
        let habit = try store.addHabit(timedDefinition(), now: clock.read())
        return try store.occurrence(id: "\(habit.id)|2026-09-20")
    }
    func remove() { try? FileManager.default.removeItem(at: directory) }
}

private final class NotificationTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = notificationDate("2026-09-20T12:00:00Z")
    func read() -> Date { lock.lock(); defer { lock.unlock() }; return value }
    func set(_ date: Date) { lock.lock(); defer { lock.unlock() }; value = date }
}

private actor NotificationTestClient: RhythmNotificationClient {
    private var access = RhythmNotificationAuthorization.authorized
    private var items: [String: RhythmPendingNotification] = [:]
    private var delivered = [String]()
    private var fail = false
    private(set) var additions = 0
    func authorization() -> RhythmNotificationAuthorization { access }
    func pending() -> [RhythmPendingNotification] { Array(items.values) }
    func deliveredIDs() -> [String] { delivered }
    func removePending(_ identifiers: [String]) { for id in identifiers { items.removeValue(forKey: id) } }
    func removeDelivered(_ identifiers: [String]) { delivered.removeAll { identifiers.contains($0) } }
    func add(_ request: RhythmNotificationRequest) async throws {
        try await Task.sleep(for: .milliseconds(1))
        if fail { fail = false; throw CocoaError(.fileWriteUnknown) }
        items[request.id] = RhythmPendingNotification(id: request.id, request: request)
        additions += 1
    }
    func setAuthorization(_ value: RhythmNotificationAuthorization) { access = value }
    func failNextAdd() { fail = true }
    func requests() -> [RhythmNotificationRequest] {
        items.values.compactMap(\.request).sorted { $0.fireDate == $1.fireDate ? $0.id < $1.id : $0.fireDate < $1.fireDate }
    }
    func seedForeign() {
        items["unrelated.request"] = RhythmPendingNotification(id: "unrelated.request", request: nil)
        delivered = ["unrelated.delivered", RhythmNotificationRequest.prefix + "old"]
    }
}

private func timedDefinition() -> HabitDefinition {
    HabitDefinition(title: "Read", normalTarget: "10 pages", lightTarget: "2 pages", dayPart: .morning,
                    recurrence: .weekly(weekdays: Set(1...7)),
                    dueTime: ScheduledTime(hour: 15, minute: 0, timeZoneIdentifier: "UTC"))
}
private func notificationDate(_ string: String) -> Date { ISO8601DateFormatter().date(from: string)! }

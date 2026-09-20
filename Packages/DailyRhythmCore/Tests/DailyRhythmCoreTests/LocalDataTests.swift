import XCTest
@testable import DailyRhythmCore

@MainActor
final class LocalDataTests: XCTestCase {
    func testRestorePreservesHistoryWithNewIdentitiesAndRejectsOverwrite() throws {
        let f = try DataFixture(); defer { f.remove() }
        let store = f.store
        var definition = f.definition
        definition.recurrence = .weekly(weekdays: Set(1...7))
        let habits = try store.addHabits(Array(repeating: definition, count: 3), now: f.now)
        let oldStep = try store.occurrence(id: "\(habits[0].id)|2026-09-20")
        _ = try store.perform(.complete(.full), on: oldStep, now: f.now.addingTimeInterval(0.123456))
        try store.archive(habitID: habits[0].id, now: f.now)
        let oldSnapshot = try store.exportData(format: .json, at: f.now)
        let originalBytes = try Data(contentsOf: f.url)
        let backup = try RoutineBackup(jsonExport: oldSnapshot)
        XCTAssertEqual(backup.planCount, 3)
        XCTAssertEqual(backup.recordCount, 1)
        XCTAssertThrowsError(try store.restoreBackup(backup))
        XCTAssertEqual(try Data(contentsOf: f.url), originalBytes)
        let lifecycle = try store.beginErasure(expectedGeneration: RoutineDataLifecycle.initialGeneration)
        try store.finishErasure(generation: lifecycle.generation)
        let restored = RoutineStore(fileURL: f.url, calendar: f.calendar, entitlementProvider: NoExportEntitlementLookup())
        try restored.restoreBackup(backup)
        XCTAssertTrue(try restored.matchesRestoredBackup(backup))
        let newHabits = try restored.habits(includeArchived: true, asOf: f.now)
        XCTAssertTrue(Set(newHabits.map(\.id)).isDisjoint(with: habits.map(\.id)))
        let completedHabit = try XCTUnwrap(newHabits.first(where: { $0.archivedAt != nil }))
        let completed = try restored.managedOccurrences(habitID: completedHabit.id).first
        XCTAssertEqual(completed?.outcome, .full)
        XCTAssertEqual(completed?.completedAt, f.now.addingTimeInterval(0.123456))
        XCTAssertThrowsError(try restored.perform(.complete(.full), on: oldStep, now: f.now))
        XCTAssertThrowsError(try restored.restoreBackup(backup))
    }

    func testRestoreRejectsMalformedFutureAndStaleDataAndRetainsAtomicFailure() throws {
        let f = try DataFixture(); defer { f.remove() }
        _ = try f.store.addHabit(f.definition, now: f.now)
        let source = try f.store.exportData(format: .json)
        XCTAssertThrowsError(try RoutineBackup(jsonExport: Data("{}".utf8)))
        var future = try JSONSerialization.jsonObject(with: source) as! [String: Any]
        future["exportVersion"] = 99
        XCTAssertThrowsError(try RoutineBackup(jsonExport: JSONSerialization.data(withJSONObject: future)))
        let backup = try RoutineBackup(jsonExport: source), old = f.store
        let lifecycle = try old.beginErasure(expectedGeneration: RoutineDataLifecycle.initialGeneration)
        XCTAssertThrowsError(try f.store.restoreBackup(backup))
        try old.finishErasure(generation: lifecycle.generation)
        XCTAssertThrowsError(try old.restoreBackup(backup))
        let failing = RoutineStore(fileURL: f.url, calendar: f.calendar, saveSnapshot: { _, _ in throw CocoaError(.fileWriteUnknown) })
        XCTAssertThrowsError(try failing.restoreBackup(backup))
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.url.path))
        XCTAssertTrue(try f.store.habits().isEmpty)
    }

    func testConcurrentRestoreAndCreationNeverOverwriteEachOther() throws {
        let f = try DataFixture(); defer { f.remove() }
        _ = try f.store.addHabit(f.definition, now: f.now)
        let bytes = try f.store.exportData(format: .json)
        let lifecycle = try f.store.beginErasure(expectedGeneration: RoutineDataLifecycle.initialGeneration)
        try f.store.finishErasure(generation: lifecycle.generation)
        var createdDefinition = f.definition
        createdDefinition.title = "Created during restore"
        let definition = createdDefinition, now = f.now, url = f.url, calendar = f.calendar
        let failures = DataTestFailures()
        DispatchQueue.concurrentPerform(iterations: 2) { index in
            do {
                let store = RoutineStore(fileURL: url, calendar: calendar)
                if index == 0 { try store.restoreBackup(RoutineBackup(jsonExport: bytes)) }
                else { _ = try store.addHabit(definition, now: now) }
            } catch LocalDataError.restoreRequiresEmptyStore {} catch { failures.append(error) }
        }
        XCTAssertTrue(failures.errors.isEmpty)
        let saved = try f.store.habits()
        XCTAssertTrue((1...2).contains(saved.count))
        XCTAssertEqual(saved.filter { $0.title == "Created during restore" }.count, 1)
    }

    func testFailedEraseBarrierPreservesOriginalData() throws {
        let f = try DataFixture(); defer { f.remove() }
        _ = try f.store.addHabit(f.definition, now: f.now)
        let original = try Data(contentsOf: f.url)
        let failing = RoutineStore(fileURL: f.url, calendar: f.calendar,
            saveLifecycle: { _, _ in throw CocoaError(.fileWriteUnknown) },
            saveSnapshot: { try $0.write(to: $1, options: .atomic) })
        XCTAssertThrowsError(try failing.beginErasure(expectedGeneration: RoutineDataLifecycle.initialGeneration))
        XCTAssertEqual(try Data(contentsOf: f.url), original)
        XCTAssertFalse(try f.store.dataLifecycle().erasurePending)
        XCTAssertEqual(try f.store.habits().count, 1)
    }

    func testUncancelledNotificationsKeepErasePendingUntilRetry() async throws {
        let f = try DataFixture(); defer { f.remove() }
        let store = f.store, client = EraseNotificationClient(), now = f.now
        let preferencesURL = f.directory.appendingPathComponent("notifications.json")
        let coordinator = RhythmNotificationCoordinator(preferencesURL: preferencesURL, client: client,
            now: { now }, validateAccess: { _ = try store.validateAccess() }) { preferences, date in
                try store.notificationPlan(preferences: preferences, at: date)
            }
        async let update = coordinator.update(.dailyClose(true))
        await client.waitForFirstAdd(); await client.releaseFirstAdd()
        _ = try await update
        let lifecycle = try store.beginErasure(expectedGeneration: RoutineDataLifecycle.initialGeneration)
        await client.setRemovalBlocked(true)
        do { try await coordinator.erasePreferences(); XCTFail("Expected unfinished OS cancellation") }
        catch RhythmNotificationError.cancellationIncomplete {}
        XCTAssertTrue(try f.store.dataLifecycle().erasurePending)
        XCTAssertTrue(FileManager.default.fileExists(atPath: preferencesURL.path))
        await client.setRemovalBlocked(false)
        try await coordinator.erasePreferences()
        try store.finishErasure(generation: lifecycle.generation)
        XCTAssertFalse(try f.store.dataLifecycle().erasurePending)
    }
    func testLegacyExportDoesNotMigrateOrCreateAnotherBackup() throws {
        let f = try DataFixture(); defer { f.remove() }
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "v1-empty", withExtension: "json", subdirectory: "Fixtures"))
        let bytes = try Data(contentsOf: fixture)
        try bytes.write(to: f.url)
        _ = try f.store.exportData(format: .json, at: f.now)
        _ = try f.store.exportData(format: .csv, at: f.now)
        XCTAssertEqual(try Data(contentsOf: f.url), bytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.store.migrationBackupURL.path))
    }

    func testErasureWaitsForInFlightNotificationAddsAndRejectsAnOldPreferenceUpdate() async throws {
        let f = try DataFixture(); defer { f.remove() }
        let oldStore = f.store, client = EraseNotificationClient()
        let preferencesURL = f.directory.appendingPathComponent("notifications.json")
        let now = f.now
        let coordinator = RhythmNotificationCoordinator(preferencesURL: preferencesURL, client: client,
            now: { now }, validateAccess: { _ = try oldStore.validateAccess() }) { preferences, date in
                try oldStore.notificationPlan(preferences: preferences, at: date)
            }
        async let update = coordinator.update(.dailyClose(true))
        await client.waitForFirstAdd()
        let state = try oldStore.beginErasure(expectedGeneration: RoutineDataLifecycle.initialGeneration)
        async let clear: Void = coordinator.erasePreferences()
        await client.releaseFirstAdd()
        _ = try await (update, clear)
        try oldStore.finishErasure(generation: state.generation)
        let pending = await client.pending(), delivered = await client.deliveredIDs()
        XCTAssertTrue(pending.isEmpty)
        XCTAssertEqual(delivered, ["unrelated.notice"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: preferencesURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: preferencesURL.appendingPathExtension("lock").path))
        do { _ = try await coordinator.update(.dailyClose(true)); XCTFail("Old permission reply must be rejected") }
        catch LocalDataError.staleAction {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: preferencesURL.path))

        let freshStore = f.store
        let freshCoordinator = RhythmNotificationCoordinator(preferencesURL: preferencesURL, client: client,
            now: { now }, validateAccess: { _ = try freshStore.validateAccess() }) { preferences, date in
                try freshStore.notificationPlan(preferences: preferences, at: date)
            }
        _ = try await freshCoordinator.update(.dailyClose(true))
        let freshIDs = await client.pending().map(\.id).sorted()
        XCTAssertFalse(freshIDs.isEmpty)
        do { _ = try await coordinator.update(.dailyClose(false)); XCTFail("Old opt-out must not clear the new queue") }
        catch LocalDataError.staleAction {}
        let survivingIDs = await client.pending().map(\.id).sorted()
        XCTAssertEqual(survivingIDs, freshIDs)
        XCTAssertTrue(try freshCoordinator.preferences().dailyClose)
    }
    func testExportsPreserveArchivedRecordsOutcomesAndExactJSONTextWithoutWriting() throws {
        let f = try DataFixture(); defer { f.remove() }
        let store = f.store
        var definition = f.definition
        definition.title = "Read, \"café\"\nToday"
        definition.normalTarget = "=2+2"
        definition.lightTarget = "One page"
        let habits = try store.addHabits(Array(repeating: definition, count: 4), now: f.now)
        for (index, action) in [OccurrenceAction.complete(.full), .complete(.light), .skip].enumerated() {
            let step = try store.occurrence(id: "\(habits[index].id)|2026-09-20")
            _ = try store.perform(action, on: step, now: f.now.addingTimeInterval(0.123456))
        }
        try store.archive(habitID: habits[0].id, now: f.now)
        let pending = try store.occurrence(id: "\(habits[3].id)|2026-09-20")
        _ = try store.perform(.later(until: f.now.addingTimeInterval(3600), timeZoneIdentifier: "UTC"), on: pending, now: f.now)
        let bytes = try Data(contentsOf: f.url)
        let exported = try JSONSerialization.jsonObject(with: store.exportData(format: .json, at: f.now)) as! [String: Any]
        XCTAssertEqual(exported["exportVersion"] as? Int, 1)
        let data = exported["data"] as! [String: Any]
        let original = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
        XCTAssertTrue(NSDictionary(dictionary: data).isEqual(to: original), "JSON must retain the entire stored snapshot, including timestamp precision")
        let records = data["records"] as! [[String: Any]]
        XCTAssertEqual(records.count, 4)
        XCTAssertTrue(records.allSatisfy { $0["title"] as? String == definition.title })
        XCTAssertTrue(records.allSatisfy { $0["normalTarget"] as? String == "=2+2" })
        XCTAssertEqual((data["habits"] as? [Any])?.count, 4)
        XCTAssertTrue((exported["exportedAt"] as? String)?.hasSuffix("Z") == true)
        let csv = String(decoding: try store.exportData(format: .csv, at: f.now), as: UTF8.self)
        XCTAssertTrue(csv.contains("\"Read, \"\"café\"\"\nToday\""))
        XCTAssertTrue(csv.contains("\"'=2+2\""))
        for outcome in ["full", "light", "skipped", "pending"] { XCTAssertTrue(csv.contains("\"\(outcome)\"")) }
        XCTAssertTrue(csv.hasSuffix("\r\n"))
        XCTAssertEqual(try Data(contentsOf: f.url), bytes)
    }

    func testExportRemainsFreeAndDoesNotInventUnrecordedDays() throws {
        let f = try DataFixture(); defer { f.remove() }
        _ = try f.store.addHabit(f.definition, now: f.now)
        let store = RoutineStore(fileURL: f.url, calendar: f.calendar, entitlementProvider: NoExportEntitlementLookup())
        let csv = String(decoding: try store.exportData(format: .csv), as: UTF8.self)
        XCTAssertEqual(csv.components(separatedBy: "\r\n").count, 2, "Only the header and trailing empty line")
        XCTAssertFalse(try store.exportData(format: .json).isEmpty)
    }

    func testExportErrorsPreserveCorruptDataAndReportDestinationFailure() throws {
        let f = try DataFixture(); defer { f.remove() }
        let corrupt = Data("not JSON".utf8)
        try corrupt.write(to: f.url)
        XCTAssertThrowsError(try f.store.exportData(format: .json))
        XCTAssertEqual(try Data(contentsOf: f.url), corrupt)
        try FileManager.default.removeItem(at: f.url)
        _ = try f.store.addHabit(f.definition, now: f.now)
        let before = try Data(contentsOf: f.url)
        XCTAssertThrowsError(try f.store.writeExport(format: .csv, to: f.directory))
        XCTAssertEqual(try Data(contentsOf: f.url), before)
    }

    func testPreparingOrCancellingEraseDoesNotChangeData() throws {
        let f = try DataFixture(); defer { f.remove() }
        _ = try f.store.addHabit(f.definition, now: f.now)
        let before = try Data(contentsOf: f.url)
        let confirmationGeneration = try f.store.dataLifecycle().generation
        XCTAssertEqual(confirmationGeneration, RoutineDataLifecycle.initialGeneration)
        // Cancelling the confirmation discards this value and never calls beginErasure.
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.store.lifecycleURL.path))
        XCTAssertEqual(try Data(contentsOf: f.url), before)
    }

    func testEraseRemovesBackupsKeepsLockAndRejectsOldStoresDraftsAndConfirmation() throws {
        let f = try DataFixture(); defer { f.remove() }
        let old = f.store
        let draft = OnboardingDraft(template: .morning, now: f.now, calendar: f.calendar)
        _ = try old.createInitialRoutine(draft, now: f.now)
        for version in [1, 2] { try Data("backup".utf8).write(to: old.migrationBackupURL(from: version)) }
        let lock = f.url.appendingPathExtension("lock")
        let inode = try FileManager.default.attributesOfItem(atPath: lock.path)[.systemFileNumber] as! NSNumber
        let started = try old.beginErasure(expectedGeneration: RoutineDataLifecycle.initialGeneration)
        XCTAssertThrowsError(try old.habits())
        XCTAssertThrowsError(try f.store.addHabit(f.definition, now: f.now))
        try old.finishErasure(generation: started.generation)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.url.path))
        for version in [1, 2] { XCTAssertFalse(FileManager.default.fileExists(atPath: old.migrationBackupURL(from: version).path)) }
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: lock.path)[.systemFileNumber] as? NSNumber, inode)
        XCTAssertThrowsError(try old.addHabit(f.definition, now: f.now))
        XCTAssertThrowsError(try f.store.createInitialRoutine(draft, now: f.now))
        XCTAssertThrowsError(try f.store.beginErasure(expectedGeneration: RoutineDataLifecycle.initialGeneration))
        let newDraft = OnboardingDraft(template: .morning, now: f.now, calendar: f.calendar, generation: started.generation)
        XCTAssertEqual(try f.store.createInitialRoutine(newDraft, now: f.now).count, 2)
        try old.finishErasure(generation: started.generation) // retry cannot delete newly created data
        XCTAssertEqual(try f.store.habits().count, 2)
    }

    func testUnfinishedEraseResumesSameGenerationAndCanRemoveCorruptHabitData() throws {
        let f = try DataFixture(); defer { f.remove() }
        try Data("corrupt".utf8).write(to: f.url)
        let store = f.store
        let start = try store.beginErasure(expectedGeneration: RoutineDataLifecycle.initialGeneration)
        // Simulate a process exit or cleanup-hook failure: finish was never called.
        let reopened = f.store
        XCTAssertTrue(try reopened.dataLifecycle().erasurePending)
        XCTAssertThrowsError(try reopened.addHabit(f.definition, now: f.now))
        XCTAssertEqual(try reopened.beginErasure(expectedGeneration: start.generation), start)
        try reopened.finishErasure(generation: start.generation)
        XCTAssertTrue(try f.store.habits().isEmpty)
        XCTAssertFalse(try f.store.dataLifecycle().erasurePending)
    }

    func testFailedCleanupKeepsBarrierUntilRetryAndPreservesUnknownLifecycle() throws {
        let f = try DataFixture(); defer { f.remove() }
        _ = try f.store.addHabit(f.definition, now: f.now)
        let store = RoutineStore(fileURL: f.url, calendar: f.calendar,
            saveLifecycle: { lifecycle, url in
                if !lifecycle.erasurePending { throw CocoaError(.fileWriteUnknown) }
                try lifecycle.write(to: url)
            }, saveSnapshot: { try $0.write(to: $1, options: .atomic) })
        let start = try store.beginErasure(expectedGeneration: RoutineDataLifecycle.initialGeneration)
        // Data removal succeeds but committing the completed marker fails.
        XCTAssertThrowsError(try store.finishErasure(generation: start.generation))
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.url.path))
        XCTAssertTrue(try f.store.dataLifecycle().erasurePending)
        XCTAssertThrowsError(try f.store.addHabit(f.definition, now: f.now))
        try f.store.finishErasure(generation: start.generation)
        let unknown = Data("{\"version\":99,\"generation\":\"\(start.generation)\",\"erasurePending\":false}".utf8)
        try unknown.write(to: store.lifecycleURL)
        XCTAssertThrowsError(try f.store.habits())
        XCTAssertEqual(try Data(contentsOf: store.lifecycleURL), unknown)
    }

    func testConcurrentOldWritersCannotRepopulateAfterErase() throws {
        let f = try DataFixture(); defer { f.remove() }
        let stores = (0..<24).map { _ in f.store }, eraser = f.store, failures = DataTestFailures()
        let definition = f.definition, now = f.now
        DispatchQueue.concurrentPerform(iterations: 25) { index in
            do {
                if index == 24 {
                    let state = try eraser.beginErasure(expectedGeneration: RoutineDataLifecycle.initialGeneration)
                    try eraser.finishErasure(generation: state.generation)
                } else { _ = try stores[index].addHabit(definition, now: now) }
            } catch LocalDataError.staleAction {} catch LocalDataError.erasurePending {}
            catch { failures.append(error) }
        }
        XCTAssertTrue(failures.errors.isEmpty)
        XCTAssertTrue(try f.store.habits().isEmpty)
        for store in stores { XCTAssertThrowsError(try store.addHabit(definition, now: now)) }
        _ = try f.store.addHabit(definition, now: now)
        XCTAssertEqual(try f.store.habits().count, 1)
    }

    func testOldExportAndDiagnosticWritesCannotRecreateFilesAfterErase() throws {
        let f = try DataFixture(); defer { f.remove() }
        let old = f.store
        _ = try old.addHabit(f.definition, now: f.now)
        let start = try old.beginErasure(expectedGeneration: RoutineDataLifecycle.initialGeneration)
        try old.finishErasure(generation: start.generation)
        let destination = f.directory.appendingPathComponent("export.json")
        XCTAssertThrowsError(try old.writeExport(format: .json, to: destination))
        XCTAssertThrowsError(try old.writeAuxiliaryData(Data("old report".utf8), to: destination))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }
}

private actor EraseNotificationClient: RhythmNotificationClient {
    private var requests: [String: RhythmNotificationRequest] = [:]
    private var delivered = ["unrelated.notice", RhythmNotificationRequest.prefix + "old"]
    private var started = false
    private var removalBlocked = false
    private var startedWaiter: CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    func authorization() -> RhythmNotificationAuthorization { .authorized }
    func pending() -> [RhythmPendingNotification] { requests.values.map { .init(id: $0.id, request: $0) } }
    func deliveredIDs() -> [String] { delivered }
    func removePending(_ ids: [String]) { if !removalBlocked { for id in ids { requests.removeValue(forKey: id) } } }
    func setRemovalBlocked(_ value: Bool) { removalBlocked = value }
    func removeDelivered(_ ids: [String]) { delivered.removeAll { ids.contains($0) } }
    func add(_ request: RhythmNotificationRequest) async throws {
        if !started {
            started = true
            startedWaiter?.resume(); startedWaiter = nil
            await withCheckedContinuation { releaseWaiter = $0 }
        }
        requests[request.id] = request
    }
    func waitForFirstAdd() async {
        if !started { await withCheckedContinuation { startedWaiter = $0 } }
    }
    func releaseFirstAdd() { releaseWaiter?.resume(); releaseWaiter = nil }
}

private struct DataFixture {
    let directory: URL
    let now = ISO8601DateFormatter().date(from: "2026-09-20T12:00:00Z")!
    let calendar: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }()
    var url: URL { directory.appendingPathComponent("data.json") }
    var store: RoutineStore { RoutineStore(fileURL: url, calendar: calendar) }
    var definition: HabitDefinition { .init(title: "Read", normalTarget: "One page", dayPart: .morning, recurrence: .once(dayKey: "2026-09-20")) }
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("LocalDataTests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    func remove() { try? FileManager.default.removeItem(at: directory) }
}

private struct NoExportEntitlementLookup: HabitEntitlementProvider {
    func currentEntitlement() -> HabitEntitlement { XCTFail("Export must not query entitlements"); return .free }
}
private final class DataTestFailures: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Error] = []
    var errors: [Error] { lock.lock(); defer { lock.unlock() }; return values }
    func append(_ value: Error) { lock.lock(); defer { lock.unlock() }; values.append(value) }
}

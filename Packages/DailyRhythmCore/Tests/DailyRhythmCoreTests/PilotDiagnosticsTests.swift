import XCTest
@testable import DailyRhythmCore

@MainActor final class PilotDiagnosticsTests: XCTestCase {
    func testOffByDefaultAndExportRequiresOptIn() throws {
        let f = try PilotFixture(); defer { f.remove() }
        let step = try f.add()
        try f.store.complete(occurrenceID: step.id, source: .app, now: f.now)
        f.store.recordPilotSetupStarted(at: f.now)
        f.store.recordPilotFailure(.validation, surface: .app, at: f.now)
        XCTAssertFalse(try f.store.pilotDiagnosticsStatus(at: f.now).enabled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.store.diagnosticsURL.path))
        XCTAssertThrowsError(try f.store.pilotDiagnosticsExport(at: f.now))
    }

    func testSetupTimingAndContentFreeExport() throws {
        let f = try PilotFixture(); defer { f.remove() }
        try f.enable()
        f.store.recordPilotSetupStarted(at: f.now.addingTimeInterval(10))
        f.store.recordPilotSetupStarted(at: f.now.addingTimeInterval(20))
        let step = try f.add(at: f.now.addingTimeInterval(30))
        try f.store.complete(occurrenceID: step.id, source: .app, now: f.now.addingTimeInterval(70))
        let report = try f.report(at: f.now.addingTimeInterval(80))
        XCTAssertEqual(report.setupToFirstCompletionSeconds, 60)
        XCTAssertEqual(report.firstCompletionDay, 1)
        XCTAssertEqual(report.days[0].sources.app, 1)
        let data = try f.store.pilotDiagnosticsExport(at: f.now.addingTimeInterval(80))
        let text = String(decoding: data, as: UTF8.self)
        for secret in ["PRIVATE NAME", "PRIVATE GOAL", "PRIVATE LIGHT", step.habitID.uuidString, step.id, "timeZoneIdentifier", "startedAt", "seen"] {
            XCTAssertFalse(text.contains(secret), secret)
        }
        let disk = String(decoding: try Data(contentsOf: f.store.diagnosticsURL), as: UTF8.self)
        XCTAssertFalse(disk.contains("PRIVATE"))
        XCTAssertTrue(disk.contains(step.habitID.uuidString)) // Local deduplication only.
    }

    func testRetryUndoAndRecompleteDoNotInflateObservation() throws {
        let f = try PilotFixture(); defer { f.remove() }
        try f.enable(); let step = try f.add()
        let token = try f.store.perform(.complete(.light), on: step, source: .widget, now: f.now)
        try f.store.complete(occurrenceID: step.id, source: .appIntent, now: f.now)
        try f.store.undo(token, now: f.now)
        try f.store.complete(occurrenceID: step.id, source: .app, now: f.now)
        let report = try f.report()
        XCTAssertEqual(report.total, 1)
        XCTAssertEqual(report.days[0].light, 1)
        XCTAssertEqual(report.days[0].sources.widget, 1)
        XCTAssertEqual(report.days[0].sources.app, 0)
        XCTAssertEqual(report.completionDays, 1)
    }

    func testAllKnownSourcesAndUnknownRemainSeparate() throws {
        let f = try PilotFixture(); defer { f.remove() }
        try f.enable()
        for source in [CompletionSource.app, .widget, .appIntent, nil] {
            let step = try f.add()
            try f.store.complete(occurrenceID: step.id, source: source, now: f.now)
        }
        let report = try f.report()
        XCTAssertEqual(report.days[0].sources.app, 1)
        XCTAssertEqual(report.days[0].sources.widget, 1)
        XCTAssertEqual(report.days[0].sources.appIntent, 1)
        XCTAssertEqual(report.days[0].sources.unknown, 1)
    }

    func testLegacyProvenanceIsUnknownBaselineNotActivation() throws {
        let f = try PilotFixture(); defer { f.remove() }
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "v1-mixed", withExtension: "json", subdirectory: "Fixtures"))
        let bytes = try Data(contentsOf: fixture)
        try bytes.write(to: f.url)
        let count = try StoreDocument.decode(bytes).document.records.filter(\.isCompleted).count
        XCTAssertGreaterThan(count, 0)
        try f.enable()
        let report = try f.report()
        XCTAssertEqual(report.baselineSources.unknown, count)
        XCTAssertEqual(report.baselineSources.app, 0)
        XCTAssertEqual(report.total, 0)
        XCTAssertNil(report.firstCompletionDay)
        XCTAssertEqual(try Data(contentsOf: f.url), bytes) // Opt-in does not migrate.
    }

    func testConcurrentAndRepeatedActivationCountsOneCommittedStep() throws {
        let f = try PilotFixture(); defer { f.remove() }
        try f.enable(); let step = try f.add()
        let url = f.url, calendar = f.calendar, now = f.now, id = step.id
        DispatchQueue.concurrentPerform(iterations: 24) { _ in
            let store = RoutineStore(fileURL: url, calendar: calendar)
            try! store.complete(occurrenceID: id, source: .appIntent, now: now)
        }
        XCTAssertEqual(try f.report().total, 1)
        XCTAssertEqual(try f.report().days[0].sources.appIntent, 1)
    }

    func testDay7Day14AndExpiryUseCivilDaysAcrossDST() throws {
        let f = try PilotFixture(zone: "America/New_York", start: "2026-11-01T05:30:00Z"); defer { f.remove() }
        try f.enable()
        for offset in [0, 6, 13] {
            let now = f.calendar.date(byAdding: .day, value: offset, to: f.now)!
            let step = try f.add(at: now)
            try f.store.complete(occurrenceID: step.id, source: .app, now: now)
        }
        let during7 = f.calendar.date(byAdding: .day, value: 6, to: f.now)!
        XCTAssertEqual(try f.report(at: during7).day7, "awaiting")
        let after14 = f.calendar.date(byAdding: .day, value: 14, to: f.now)!
        let report = try f.report(at: after14)
        XCTAssertEqual(report.days.map(\.day), [1, 7, 14])
        XCTAssertEqual(report.day7, "completionObserved")
        XCTAssertEqual(report.day14, "completionObserved")
        let expiry = f.calendar.date(byAdding: .day, value: 30, to: f.calendar.startOfDay(for: f.now))!
        XCTAssertTrue(try f.store.pilotDiagnosticsStatus(at: expiry.addingTimeInterval(-1)).enabled)
        XCTAssertFalse(try f.store.pilotDiagnosticsStatus(at: expiry).enabled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.store.diagnosticsURL.path))
        XCTAssertThrowsError(try f.store.pilotDiagnosticsExport(at: expiry))
    }

    func testMissingCheckpointAndUnknownSetupAreNotAssumedSuccess() throws {
        let f = try PilotFixture(); defer { f.remove() }
        _ = try f.add(); try f.enable()
        f.store.recordPilotSetupStarted(at: f.now)
        let report = try f.report(at: f.calendar.date(byAdding: .day, value: 14, to: f.now)!)
        XCTAssertFalse(report.setupStartCaptured)
        XCTAssertNil(report.setupToFirstCompletionSeconds)
        XCTAssertEqual(report.day7, "noCompletionObserved")
        XCTAssertEqual(report.day14, "noCompletionObserved")
    }

    func testDiagnosticWriteFailureCannotFailCoreMutationOrChangeOriginalError() throws {
        let f = try PilotFixture(); defer { f.remove() }
        try f.enable(); let step = try f.add()
        let store = RoutineStore(fileURL: f.url, calendar: f.calendar,
            saveDiagnostics: { _, _ in throw CocoaError(.fileWriteNoPermission) },
            saveSnapshot: { try $0.write(to: $1, options: .atomic) })
        try store.complete(occurrenceID: step.id, source: .app, now: f.now)
        XCTAssertEqual(try f.store.occurrence(id: step.id).outcome, .full)
        XCTAssertEqual(try f.report().total, 0) // Explicitly best-effort, never a fabricated pass.
        XCTAssertThrowsError(try store.diagnoseAction(surface: .app, at: f.now) {
            throw RoutineStoreError.invalidTitle
        }) { XCTAssertEqual($0 as? RoutineStoreError, .invalidTitle) }
    }

    func testFailedCoreWriteRecordsOnlySanitizedFailure() throws {
        let f = try PilotFixture(); defer { f.remove() }
        try f.enable(); let step = try f.add()
        let before = try Data(contentsOf: f.url)
        let store = RoutineStore(fileURL: f.url, calendar: f.calendar,
            saveSnapshot: { _, _ in throw RoutineStoreError.fileAccess("PRIVATE ERROR /Users/private/path") })
        XCTAssertThrowsError(try store.diagnoseAction(surface: .widget, at: f.now) {
            try store.complete(occurrenceID: step.id, source: .widget, now: f.now)
        })
        XCTAssertEqual(try Data(contentsOf: f.url), before)
        let report = try f.report()
        XCTAssertEqual(report.total, 0)
        XCTAssertEqual(report.failures, [PilotFailureCount(day: 1, surface: .widget, category: .storage, count: 1)])
        XCTAssertFalse(String(decoding: try f.store.pilotDiagnosticsExport(at: f.now), as: UTF8.self).contains("PRIVATE"))
    }

    func testCorruptOrFutureDiagnosticsDoNotBlockTrackingAndCanBeCleared() throws {
        let f = try PilotFixture(); defer { f.remove() }
        try f.enable(); let step = try f.add()
        var object = try JSONSerialization.jsonObject(with: Data(contentsOf: f.store.diagnosticsURL)) as! [String: Any]
        object["version"] = 99
        let invalid = try JSONSerialization.data(withJSONObject: object)
        try invalid.write(to: f.store.diagnosticsURL)
        try f.store.complete(occurrenceID: step.id, source: .app, now: f.now)
        XCTAssertEqual(try Data(contentsOf: f.store.diagnosticsURL), invalid)
        XCTAssertThrowsError(try f.report())
        try f.store.setPilotDiagnosticsEnabled(false, at: f.now)
        XCTAssertFalse(try f.store.pilotDiagnosticsStatus(at: f.now).enabled)
        XCTAssertEqual(try f.store.occurrence(id: step.id).outcome, .full)
    }

    func testOptOutDeletesAndReenableStartsNewBaseline() throws {
        let f = try PilotFixture(); defer { f.remove() }
        try f.enable(); let step = try f.add()
        try f.store.complete(occurrenceID: step.id, source: .app, now: f.now)
        try f.store.setPilotDiagnosticsEnabled(false, at: f.now)
        f.store.recordPilotFailure(.validation, surface: .app, at: f.now)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.store.diagnosticsURL.path))
        try f.enable()
        XCTAssertEqual(try f.report().total, 0)
        XCTAssertEqual(try f.report().baselineSources.app, 1)
        try f.store.reopen(occurrenceID: step.id, now: f.now)
        try f.store.complete(occurrenceID: step.id, source: .app, now: f.now)
        XCTAssertEqual(try f.report().total, 0)
    }

    func testEraseRemovesObservationAndRejectsLateWriterAndExport() throws {
        let f = try PilotFixture(); defer { f.remove() }
        try f.enable(); let old = f.store
        let marker = try old.beginErasure(expectedGeneration: RoutineDataLifecycle.initialGeneration)
        old.recordPilotFailure(.validation, surface: .app, at: f.now)
        XCTAssertThrowsError(try old.writePilotDiagnosticsExport(to: f.directory.appendingPathComponent("blocked.json"), at: f.now))
        try old.finishErasure(generation: marker.generation)
        old.recordPilotFailure(.validation, surface: .app, at: f.now)
        old.recordPilotSetupStarted(at: f.now)
        XCTAssertThrowsError(try old.setPilotDiagnosticsEnabled(true, at: f.now))
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.diagnosticsURL.path))
        XCTAssertFalse(try f.store.pilotDiagnosticsStatus(at: f.now).enabled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.directory.appendingPathComponent("blocked.json").path))
    }

    func testExportFailurePreservesDiagnosticAndRoutineBytes() throws {
        let f = try PilotFixture(); defer { f.remove() }
        try f.enable(); _ = try f.add()
        let routine = try Data(contentsOf: f.url), diagnostics = try Data(contentsOf: f.store.diagnosticsURL)
        XCTAssertThrowsError(try f.store.writePilotDiagnosticsExport(to: f.directory, at: f.now))
        XCTAssertEqual(try Data(contentsOf: f.url), routine)
        XCTAssertEqual(try Data(contentsOf: f.store.diagnosticsURL), diagnostics)
        let destination = f.directory.appendingPathComponent("diagnostics.json")
        try f.store.writePilotDiagnosticsExport(to: destination, at: f.now)
        XCTAssertEqual(try Data(contentsOf: destination), try f.store.pilotDiagnosticsExport(at: f.now))
    }

    func testBackupRestoreIsNotObservedAsNewCompletion() throws {
        let donor = try PilotFixture(); defer { donor.remove() }
        let step = try donor.add()
        try donor.store.complete(occurrenceID: step.id, source: .app, now: donor.now)
        let backup = try RoutineBackup(jsonExport: donor.store.exportData(format: .json, at: donor.now))
        let recipient = try PilotFixture(); defer { recipient.remove() }
        try recipient.enable()
        try recipient.store.restoreBackup(backup)
        XCTAssertEqual(try recipient.report().total, 0)
        XCTAssertNil(try recipient.report().firstCompletionDay)
    }

    func testInterruptedEraseKeepsBarrierUntilDiagnosticsCleanupRetry() throws {
        let f = try PilotFixture(); defer { f.remove() }
        try f.enable()
        let failing = RoutineStore(fileURL: f.url, calendar: f.calendar,
            saveLifecycle: { marker, url in
                if !marker.erasurePending { throw CocoaError(.fileWriteNoPermission) }
                try marker.write(to: url)
            }, saveSnapshot: { try $0.write(to: $1, options: .atomic) })
        let marker = try failing.beginErasure(expectedGeneration: RoutineDataLifecycle.initialGeneration)
        XCTAssertThrowsError(try failing.finishErasure(generation: marker.generation))
        XCTAssertTrue(try f.store.dataLifecycle().erasurePending)
        XCTAssertFalse(FileManager.default.fileExists(atPath: failing.diagnosticsURL.path))
        failing.recordPilotSetupStarted(at: f.now)
        XCTAssertFalse(FileManager.default.fileExists(atPath: failing.diagnosticsURL.path))
        try f.store.finishErasure(generation: marker.generation)
        XCTAssertFalse(try f.store.dataLifecycle().erasurePending)
        XCTAssertFalse(try f.store.pilotDiagnosticsStatus(at: f.now).enabled)
    }

    func testBoundedObservationStopsCountingButDoesNotStopCompletion() throws {
        let f = try PilotFixture(); defer { f.remove() }
        try f.enable(); let step = try f.add()
        var object = try JSONSerialization.jsonObject(with: Data(contentsOf: f.store.diagnosticsURL)) as! [String: Any]
        object["seen"] = (0..<10_000).map { _ in "\(UUID().uuidString)|2026-09-20" }
        object["baselineSources"] = ["app": 10_000, "widget": 0, "appIntent": 0, "unknown": 0]
        try JSONSerialization.data(withJSONObject: object).write(to: f.store.diagnosticsURL)
        try f.store.complete(occurrenceID: step.id, source: .app, now: f.now)
        XCTAssertEqual(try f.store.occurrence(id: step.id).outcome, .full)
        XCTAssertTrue(try f.store.pilotDiagnosticsStatus(at: f.now).capacityReached)
        XCTAssertEqual(try f.report().total, 0)
    }
}

private struct PilotReport: Decodable {
    let setupStartCaptured: Bool
    let setupToFirstCompletionSeconds: Int?
    let firstCompletionDay: Int?
    let completionDays: Int
    let baselineSources: PilotSourceCounts
    let days: [PilotDayCounts]
    let failures: [PilotFailureCount]
    let day7: String
    let day14: String
    var total: Int { days.reduce(0) { $0 + $1.full + $1.light } }
}

private struct PilotFixture {
    let directory: URL
    let url: URL
    let now: Date
    let calendar: Calendar
    var store: RoutineStore { RoutineStore(fileURL: url, calendar: calendar) }

    init(zone: String = "UTC", start: String = "2026-09-20T10:00:00Z") throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("pilot-tests-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("routine.json")
        now = ISO8601DateFormatter().date(from: start)!
        var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(identifier: zone)!
        calendar = value
    }
    func remove() { try? FileManager.default.removeItem(at: directory) }
    func enable() throws { try store.setPilotDiagnosticsEnabled(true, at: now) }
    func add(at date: Date? = nil) throws -> DailyOccurrence {
        let at = date ?? now, key = LocalDay(calendar: calendar).key(for: at)
        let definition = HabitDefinition(title: "PRIVATE NAME", normalTarget: "PRIVATE GOAL", lightTarget: "PRIVATE LIGHT", dayPart: .morning, recurrence: .once(dayKey: key))
        let habit = try store.addHabit(definition, now: at)
        return try store.occurrence(id: "\(habit.id.uuidString)|\(key)")
    }
    func report(at date: Date? = nil) throws -> PilotReport {
        try JSONDecoder().decode(PilotReport.self, from: store.pilotDiagnosticsExport(at: date ?? now))
    }
}

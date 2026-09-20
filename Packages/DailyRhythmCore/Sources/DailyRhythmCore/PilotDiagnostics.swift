import Foundation

public enum PilotInputSurface: String, Codable, CaseIterable, Sendable {
    case app, widget, appIntent, unknown

    init(_ source: CompletionSource?) {
        switch source {
        case .app: self = .app
        case .widget: self = .widget
        case .appIntent: self = .appIntent
        case nil: self = .unknown
        }
    }
}

public enum PilotFailureCategory: String, Codable, CaseIterable, Sendable {
    case staleAction, unavailableStep, validation, capacity, storage, other

    public static func classify(_ error: Error) -> Self {
        if let categorized = error as? any PilotCategorizedError { return categorized.pilotFailureCategory }
        if error is ReminderMappingError { return .validation }
        if let error = error as? RoutineStoreError {
            switch error {
            case .staleAction: return .staleAction
            case .activeHabitLimitReached: return .capacity
            case .fileAccess, .corruptData, .unsupportedVersion: return .storage
            case .completedOccurrence, .habitNotFound, .futureCompletion: return .unavailableStep
            default: return .validation
            }
        }
        if error is HabitControlError { return .unavailableStep }
        if let error = error as? LocalDataError {
            switch error {
            case .staleAction, .erasurePending: return .staleAction
            case .invalidLifecycle: return .storage
            default: return .validation
            }
        }
        return .other // Never persist an error description, path or user input.
    }
}

public protocol PilotCategorizedError: Error {
    var pilotFailureCategory: PilotFailureCategory { get }
}

public struct PilotSourceCounts: Codable, Equatable, Sendable {
    public private(set) var app = 0
    public private(set) var widget = 0
    public private(set) var appIntent = 0
    public private(set) var unknown = 0
    var total: Int { app + widget + appIntent + unknown }
    var valid: Bool { [app, widget, appIntent, unknown].allSatisfy { (0...10_000).contains($0) } }

    mutating func add(_ source: PilotInputSurface) {
        switch source {
        case .app: app += 1
        case .widget: widget += 1
        case .appIntent: appIntent += 1
        case .unknown: unknown += 1
        }
    }
}

public struct PilotDayCounts: Codable, Equatable, Sendable {
    public let day: Int
    public internal(set) var full = 0
    public internal(set) var light = 0
    public internal(set) var sources = PilotSourceCounts()
}

public struct PilotFailureCount: Codable, Equatable, Sendable {
    public let day: Int
    public let surface: PilotInputSurface
    public let category: PilotFailureCategory
    public internal(set) var count: Int
}

public struct PilotDiagnosticsStatus: Equatable, Sendable {
    public let enabled: Bool
    public let observationDay: Int?
    public let capacityReached: Bool
    static let off = Self(enabled: false, observationDay: nil, capacityReached: false)
}

public struct PilotDiagnosticsExport: Encodable, Sendable {
    public let format = "daily-rhythm-pilot-diagnostics"
    public let exportVersion = 1
    public let observationDay: Int
    public let bestEffort = true
    public let capacityReached: Bool
    public let setupStartCaptured: Bool
    public let setupToFirstCompletionSeconds: Int?
    public let firstCompletionDay: Int?
    public let completionDays: Int
    public let days: [PilotDayCounts]
    public let baselineSources: PilotSourceCounts
    public let failures: [PilotFailureCount]
    public let day7: String
    public let day14: String
    public let definitions = [
        "completion": "First committed full/light transition per occurrence during observation; retries and reopen/recomplete never add another event. Undo does not remove a past observation.",
        "baselineSources": "Already-completed records when observation began; excluded from pilot completions. Nil legacy provenance is unknown.",
        "day": "1-based civil day in the timezone captured at opt-in. Day 7/14 are awaiting until that civil day ends.",
        "setup": "First empty-app onboarding or manual-create opening after opt-in. Missing timing is unknown, not zero.",
        "appIntent": "Known App Intent entry point, including Siri, Shortcuts and configured controls; exact invocation method is not observable.",
        "failures": "Best-effort failed action attempts by category and entry point; repeated failures may count again and are not activation metrics.",
        "coverage": "Local optional diagnostics may omit events after an I/O failure or interruption. No automatic upload. Restoring a backup is not a completion event."
    ]
}

public enum PilotDiagnosticsError: Error, LocalizedError {
    case disabled, invalidData, capacity
    public var errorDescription: String? {
        switch self {
        case .disabled: "Local diagnostics are off or the 30-day observation has ended. Enable them to start a new observation."
        case .invalidData: "Local diagnostics couldn't be read. Habit tracking is unaffected. Turn diagnostics off to clear them before starting again."
        case .capacity: "This store has too many existing completions for the optional pilot diagnostics. Habit tracking and data export remain available."
        }
    }
}

/// No routine content. Local occurrence keys only deduplicate; they never leave this file in an export.
struct PilotDiagnosticsDocument: Codable {
    var version = 1
    let startedAt: Date
    let timeZoneIdentifier: String
    var setupStartedAt: Date?
    var setupToFirstCompletionSeconds: Int?
    var firstCompletionDay: Int?
    var seen: Set<String>
    var days: [PilotDayCounts] = []
    let baselineSources: PilotSourceCounts
    var failures: [PilotFailureCount] = []
    var capacityReached = false

    var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: timeZoneIdentifier)!
        return value
    }
    var expiresAt: Date { calendar.date(byAdding: .day, value: 30, to: calendar.startOfDay(for: startedAt))! }
    func day(at date: Date) -> Int {
        (calendar.dateComponents([.day], from: calendar.startOfDay(for: startedAt), to: calendar.startOfDay(for: date)).day ?? 0) + 1
    }

    init(startedAt: Date, timeZoneIdentifier: String, baseline: [DailyOccurrence]) throws {
        guard baseline.count <= 10_000 else { throw PilotDiagnosticsError.capacity }
        self.startedAt = startedAt
        self.timeZoneIdentifier = timeZoneIdentifier
        seen = Set(baseline.map(\.id))
        var sources = PilotSourceCounts()
        for record in baseline { sources.add(PilotInputSurface(record.completionSource)) }
        baselineSources = sources
    }

    mutating func observe(_ records: [DailyOccurrence]) {
        for record in records.sorted(by: { ($0.completedAt ?? .distantFuture) < ($1.completedAt ?? .distantFuture) }) {
            guard record.isCompleted, let at = record.completedAt, at >= startedAt, at < expiresAt,
                  !seen.contains(record.id) else { continue }
            guard seen.count < 10_000 else { capacityReached = true; continue }
            let number = day(at: at)
            seen.insert(record.id)
            if firstCompletionDay == nil {
                firstCompletionDay = number
                if let setupStartedAt, at >= setupStartedAt {
                    setupToFirstCompletionSeconds = Int(at.timeIntervalSince(setupStartedAt))
                }
            }
            if !days.contains(where: { $0.day == number }) { days.append(PilotDayCounts(day: number)) }
            let index = days.firstIndex { $0.day == number }!
            if record.outcome == .light { days[index].light += 1 } else { days[index].full += 1 }
            days[index].sources.add(PilotInputSurface(record.completionSource))
        }
    }

    mutating func recordFailure(_ category: PilotFailureCategory, surface: PilotInputSurface, at date: Date) {
        guard date >= startedAt, date < expiresAt else { return }
        let number = day(at: date)
        if let index = failures.firstIndex(where: { $0.day == number && $0.surface == surface && $0.category == category }) {
            if failures[index].count < 10_000 { failures[index].count += 1 } else { capacityReached = true }
        } else { failures.append(PilotFailureCount(day: number, surface: surface, category: category, count: 1)) }
    }

    func export(at date: Date) -> PilotDiagnosticsExport {
        let number = day(at: date)
        func checkpoint(_ target: Int) -> String {
            if number <= target { return "awaiting" }
            return days.contains { $0.day == target } ? "completionObserved" : "noCompletionObserved"
        }
        return PilotDiagnosticsExport(observationDay: number, capacityReached: capacityReached,
            setupStartCaptured: setupStartedAt != nil, setupToFirstCompletionSeconds: setupToFirstCompletionSeconds,
            firstCompletionDay: firstCompletionDay, completionDays: days.count, days: days.sorted { $0.day < $1.day },
            baselineSources: baselineSources,
            failures: failures.sorted { ($0.day, $0.surface.rawValue, $0.category.rawValue) < ($1.day, $1.surface.rawValue, $1.category.rawValue) },
            day7: checkpoint(7), day14: checkpoint(14))
    }

    static func read(from url: URL) throws -> Self? {
        let data: Data
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            data = try handle.read(upToCount: 2_000_001) ?? Data()
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile { return nil }
        do {
            guard data.count <= 2_000_000 else { throw PilotDiagnosticsError.invalidData }
            let value = try JSONDecoder().decode(Self.self, from: data)
            guard value.version == 1, validDate(value.startedAt), TimeZone(identifier: value.timeZoneIdentifier) != nil,
                  value.seen.count <= 10_000, value.days.count <= 30, value.baselineSources.valid,
                  Set(value.days.map(\.day)).count == value.days.count,
                  value.days.allSatisfy({ (1...30).contains($0.day) && (0...10_000).contains($0.full) && (0...10_000).contains($0.light)
                      && $0.sources.valid && $0.sources.total == $0.full + $0.light && $0.sources.total > 0 }),
                  value.failures.count <= 30 * PilotInputSurface.allCases.count * PilotFailureCategory.allCases.count,
                  Set(value.failures.map { "\($0.day)|\($0.surface.rawValue)|\($0.category.rawValue)" }).count == value.failures.count,
                  value.failures.allSatisfy({ (1...30).contains($0.day) && (1...10_000).contains($0.count) }),
                  value.setupStartedAt.map({ validDate($0) && $0 >= value.startedAt && $0 < value.expiresAt }) ?? true,
                  value.setupToFirstCompletionSeconds.map({ (0...2_700_000).contains($0) }) ?? true,
                  value.firstCompletionDay.map({ firstDay in value.days.contains { $0.day == firstDay } }) ?? value.days.isEmpty,
                  value.seen.count == value.baselineSources.total + value.days.reduce(0, { $0 + $1.sources.total }) else {
                throw PilotDiagnosticsError.invalidData
            }
            return value
        } catch { throw PilotDiagnosticsError.invalidData }
    }

    func write(to url: URL) throws { try LocalDataFiles.write(JSONEncoder().encode(self), to: url) }
}

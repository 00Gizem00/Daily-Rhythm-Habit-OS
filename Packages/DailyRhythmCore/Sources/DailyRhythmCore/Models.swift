import Foundation

public enum DayPart: String, CaseIterable, Codable, Sendable {
    case morning, afternoon, evening
    public var title: String { rawValue.capitalized }
    var sortOrder: Int { Self.allCases.firstIndex(of: self)! }
}

public enum CompletionOutcome: String, Codable, Sendable { case full, light, skipped }

/// `appIntent` covers ordinary Shortcuts and Siri; those callers cannot be distinguished reliably.
public enum CompletionSource: String, Codable, Sendable { case app, widget, appIntent }

/// The complete supported recurrence vocabulary. Unknown encoded cases fail decoding.
public enum Recurrence: Codable, Equatable, Sendable {
    case once(dayKey: String)
    /// Foundation weekday numbers: Sunday = 1, Saturday = 7. All seven means daily.
    case weekly(weekdays: Set<Int>)

    public var weekdays: Set<Int> {
        if case .weekly(let days) = self { return days }
        return []
    }

    func matches(_ key: String) -> Bool {
        switch self {
        case .once(let day): day == key
        case .weekly(let days): LocalDay.utc.weekday(for: key).map(days.contains) ?? false
        }
    }
}

/// A wall-clock time in a named, fixed timezone. Travel does not move its deadline.
public struct ScheduledTime: Codable, Equatable, Sendable {
    public let hour: Int
    public let minute: Int
    public let timeZoneIdentifier: String

    public init(hour: Int, minute: Int, timeZoneIdentifier: String) {
        self.hour = hour
        self.minute = minute
        self.timeZoneIdentifier = timeZoneIdentifier
    }
}

/// Date-only is deliberately separate from an instant; it never implies midnight or a reminder time.
public enum OccurrenceDue: Codable, Equatable, Sendable {
    case dateOnly(dayKey: String)
    case timed(at: Date, timeZoneIdentifier: String)

    public var instant: Date? {
        if case .timed(let date, _) = self { return date }
        return nil
    }

    public func dayKey(calendar: Calendar = .current) -> String {
        switch self {
        case .dateOnly(let key): return key
        case .timed(let date, let zone):
            var anchored = calendar
            // Store validation rejects invalid zones before exposing persisted values.
            anchored.timeZone = TimeZone(identifier: zone) ?? calendar.timeZone
            return LocalDay(calendar: anchored).key(for: date)
        }
    }

    func currentDay(at now: Date, calendar: Calendar) -> String {
        var anchored = calendar
        if case .timed(_, let zone) = self, let timeZone = TimeZone(identifier: zone) {
            anchored.timeZone = timeZone
        }
        return LocalDay(calendar: anchored).key(for: now)
    }
}

/// Complete replacement values for a future revision. Validation happens inside store APIs.
public struct HabitDefinition: Codable, Equatable, Sendable {
    public var title: String
    public var normalTarget: String
    public var lightTarget: String?
    public var dayPart: DayPart
    public var recurrence: Recurrence
    public var dueTime: ScheduledTime?
    public var durationMinutes: Int?

    public init(title: String, normalTarget: String, lightTarget: String? = nil,
                dayPart: DayPart, recurrence: Recurrence, dueTime: ScheduledTime? = nil,
                durationMinutes: Int? = nil) {
        self.title = title
        self.normalTarget = normalTarget
        self.lightTarget = lightTarget
        self.dayPart = dayPart
        self.recurrence = recurrence
        self.dueTime = dueTime
        self.durationMinutes = durationMinutes
    }
}

public struct HabitRevision: Codable, Equatable, Sendable {
    public let effectiveDayKey: String
    /// Nil for v1, whose edit timestamp was never recorded.
    public let recordedAt: Date?
    public let definition: HabitDefinition
}

/// Half-open civil-date interval: archive day is excluded; restore day is included.
public struct ArchiveInterval: Codable, Equatable, Sendable {
    public let startDayKey: String
    public let archivedAt: Date
    public internal(set) var endDayKey: String?
    public internal(set) var restoredAt: Date?
}

/// A projection of the definition effective on the requested date, plus its immutable history.
public struct Habit: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let definition: HabitDefinition
    public let createdAt: Date
    public let archivedAt: Date?
    public let revisions: [HabitRevision]
    public let archiveIntervals: [ArchiveInterval]

    public var title: String { definition.title }
    public var normalTarget: String { definition.normalTarget }
    public var lightTarget: String? { definition.lightTarget }
    public var dayPart: DayPart { definition.dayPart }
    public var weekdays: Set<Int> { definition.recurrence.weekdays }
    public var recurrence: Recurrence { definition.recurrence }
    public var dueTime: ScheduledTime? { definition.dueTime }
    public var durationMinutes: Int? { definition.durationMinutes }
}

public struct DailyOccurrence: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let habitID: UUID
    /// Original planned date, also used for identity and the historical denominator.
    public let dayKey: String
    public let title: String
    public internal(set) var normalTarget: String
    public internal(set) var lightTarget: String?
    public let dayPart: DayPart
    public internal(set) var durationMinutes: Int?
    public internal(set) var due: OccurrenceDue
    public internal(set) var outcome: CompletionOutcome?
    public internal(set) var completedAt: Date?
    /// Nil means unknown, including every migrated completion.
    public internal(set) var completionSource: CompletionSource?

    public internal(set) var skippedAt: Date?
    /// An explicit Later action suppresses Next Up until this instant.
    public internal(set) var deferredUntil: Date?
    public internal(set) var mutationID: UUID?

    public var revision: String { mutationID?.uuidString ?? "unrecorded" }
    public var isCompleted: Bool { outcome == .full || outcome == .light }
    public var isResolved: Bool { outcome != nil }
    public var resolvedAt: Date? { completedAt ?? skippedAt }

    public func isReady(at now: Date, calendar: Calendar = .current) -> Bool {
        canComplete(at: now, calendar: calendar) && (deferredUntil.map { $0 <= now } ?? true)
    }

    public func canComplete(at now: Date = Date(), calendar: Calendar = .current) -> Bool {
        !isResolved && due.dayKey(calendar: calendar) <= due.currentDay(at: now, calendar: calendar)
    }

    public func isOverdue(at now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard !isResolved else { return false }
        switch due {
        case .dateOnly(let key): return key < LocalDay(calendar: calendar).key(for: now)
        case .timed(let date, _): return date < now
        }
    }
}

public struct DailySummary: Equatable, Sendable {
    public let dayKey: String
    public let occurrences: [DailyOccurrence]
    public internal(set) var isLightDay = false
    public internal(set) var modeRevision: UUID?
    public var totalCount: Int { occurrences.count }
    public var completedCount: Int { occurrences.filter(\.isCompleted).count }
    public var fullCount: Int { occurrences.filter { $0.outcome == .full }.count }
    public var lightCount: Int { occurrences.filter { $0.outcome == .light }.count }
    public var skippedCount: Int { occurrences.filter { $0.outcome == .skipped }.count }
    public var remainingCount: Int { totalCount - completedCount - skippedCount }
}

public enum RoutineStoreError: Error, Equatable, Sendable, LocalizedError {
    case invalidTitle, invalidTarget, invalidWeekdays, invalidHistoryRange, invalidOccurrence
    case invalidDueDate, invalidDuration, invalidEffectiveDate, unsupportedRecurrenceChange
    case completedOccurrence, habitNotFound, lightTargetUnavailable, futureCompletion, corruptData
    case activeHabitLimitReached, staleAction, onboardingAlreadyStarted, invalidOnboardingDraft
    case unsupportedVersion(Int)
    case fileAccess(String)

    public var errorDescription: String? {
        switch self {
        case .invalidTitle: "Enter a habit name of 1–100 characters."
        case .invalidTarget: "Enter a target of 1–200 characters."
        case .invalidWeekdays: "Choose at least one valid day of the week."
        case .invalidHistoryRange: "Choose a history range between 1 and 366 days."
        case .invalidOccurrence: "This habit occurrence is no longer available."
        case .invalidDueDate: "Choose a valid due date, time and timezone on or after the planned date."
        case .invalidDuration: "Enter a duration in whole minutes greater than zero."
        case .invalidEffectiveDate: "Schedule and target edits must start on a future date."
        case .unsupportedRecurrenceChange: "Keep the recurrence type. Reschedule a one-off using its occurrence."
        case .completedOccurrence: "Reopen this step before changing it."
        case .habitNotFound: "This habit could not be found."
        case .lightTargetUnavailable: "Add a smaller target before using Light Day."
        case .futureCompletion: "Future habits cannot be completed early."
        case .onboardingAlreadyStarted: "You already have a plan. Continue in Today or add another habit from Habits."
        case .invalidOnboardingDraft: "Review between one and three habits before creating your routine."
        case .staleAction: "This step has changed. Refresh and choose the action again."
        case .activeHabitLimitReached: HabitActivationPolicy.limitMessage
        case .corruptData: "Your saved data could not be read. It has been preserved."
        case .unsupportedVersion: "This data was saved by an unsupported app version. Update the app to continue."
        case .fileAccess: "Your habits could not be accessed. Please try again."
        }
    }
}

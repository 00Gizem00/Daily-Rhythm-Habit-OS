import Foundation

public enum DayPart: String, CaseIterable, Codable, Sendable {
    case morning, afternoon, evening

    public var title: String { rawValue.capitalized }

    var sortOrder: Int { Self.allCases.firstIndex(of: self)! }
}

public enum CompletionOutcome: String, Codable, Sendable {
    case full, light
}

public struct Habit: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let normalTarget: String
    public let lightTarget: String?
    public let dayPart: DayPart
    /// Foundation weekday numbers: Sunday = 1, Monday = 2, Saturday = 7.
    public let weekdays: Set<Int>
    public let createdAt: Date
    public internal(set) var archivedAt: Date?

    // Persist calendar dates, so timezone travel never moves the creation/archive day.
    let firstDayKey: String
    var archiveDayKey: String?
}

public struct DailyOccurrence: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let habitID: UUID
    public let dayKey: String
    public let title: String
    public let normalTarget: String
    public let lightTarget: String?
    public let dayPart: DayPart
    public internal(set) var outcome: CompletionOutcome?
    public internal(set) var completedAt: Date?

    public var isCompleted: Bool { outcome != nil }
}

public struct DailySummary: Equatable, Sendable {
    public let dayKey: String
    public let occurrences: [DailyOccurrence]

    public var totalCount: Int { occurrences.count }
    public var completedCount: Int { occurrences.filter(\.isCompleted).count }
    public var fullCount: Int { occurrences.filter { $0.outcome == .full }.count }
    public var lightCount: Int { occurrences.filter { $0.outcome == .light }.count }
    public var remainingCount: Int { totalCount - completedCount }
}

public enum RoutineStoreError: Error, Equatable, Sendable, LocalizedError {
    case invalidTitle
    case invalidTarget
    case invalidWeekdays
    case invalidHistoryRange
    case invalidOccurrence
    case habitNotFound
    case lightTargetUnavailable
    case futureCompletion
    case corruptData
    case unsupportedVersion(Int)
    case fileAccess(String)

    public var errorDescription: String? {
        switch self {
        case .invalidTitle: "Enter a habit name of 1–100 characters."
        case .invalidTarget: "Enter a target of 1–200 characters."
        case .invalidWeekdays: "Choose at least one valid day of the week."
        case .invalidHistoryRange: "Choose a history range between 1 and 366 days."
        case .invalidOccurrence: "This habit occurrence is no longer available."
        case .habitNotFound: "This habit could not be found."
        case .lightTargetUnavailable: "Add a smaller target before using Light Day."
        case .futureCompletion: "Future habits cannot be completed early."
        case .corruptData: "Your saved data could not be read. It has been preserved."
        case .unsupportedVersion: "This data was saved by an unsupported app version. Update the app to continue."
        case .fileAccess: "Your habits could not be accessed. Please try again."
        }
    }
}

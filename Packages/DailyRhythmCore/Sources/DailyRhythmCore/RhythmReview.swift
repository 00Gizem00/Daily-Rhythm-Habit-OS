import Foundation

/// A review uses one locked store snapshot for Today, history and the next plan.
/// Occurrences belong to their original planned day, even after deferral or late completion.
public struct RhythmReview: Equatable, Sendable {
    public let asOf: Date
    public let agenda: DailyAgenda
    public let habits: [Habit]
    public let days: [RhythmReviewDay]
    public let tomorrow: DailySummary
    public let tomorrowFirstStep: DailyOccurrence?

    public var plannedCount: Int { days.reduce(0) { $0 + $1.summary.totalCount } }
    public var fullCount: Int { days.reduce(0) { $0 + $1.summary.fullCount } }
    public var lightCount: Int { days.reduce(0) { $0 + $1.summary.lightCount } }
    public var skippedCount: Int { days.reduce(0) { $0 + $1.summary.skippedCount } }
    public var remainingCount: Int { days.reduce(0) { $0 + $1.summary.remainingCount } }
    public var plannedLaterCount: Int { days.reduce(0) { $0 + $1.plannedLaterCount } }
}

public struct RhythmReviewDay: Equatable, Sendable, Identifiable {
    public let summary: DailySummary
    /// A subset of remaining work, never a completion or a missed-step count.
    public let plannedLaterCount: Int
    public let isToday: Bool
    public var id: String { summary.dayKey }

    init(summary: DailySummary, asOf now: Date, calendar: Calendar) {
        self.summary = summary
        isToday = summary.dayKey == LocalDay(calendar: calendar).key(for: now)
        plannedLaterCount = summary.occurrences.filter {
            Self.isPlannedLater($0, at: now, calendar: calendar)
        }.count
    }

    public static func isPlannedLater(_ occurrence: DailyOccurrence, at now: Date,
                                      calendar: Calendar = .current) -> Bool {
        guard !occurrence.isResolved else { return false }
        if let deferred = occurrence.deferredUntil, deferred > now { return true }
        switch occurrence.due {
        case .timed(let instant, _): return instant > now
        case .dateOnly(let day): return day > LocalDay(calendar: calendar).key(for: now)
        }
    }
}

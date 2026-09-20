import Foundation

public enum OccurrenceAction: Equatable, Sendable {
    case complete(CompletionOutcome)
    case skip
    case later(until: Date, timeZoneIdentifier: String)
    case reopen
}

/// Created only by a successful store transaction. Undo restores the snapshot once,
/// then stamps a fresh revision to prevent an older token becoming valid again.
public struct OccurrenceUndo: Sendable {
    let previous: DailyOccurrence
    let resultingRevision: String
}

struct DayMode: Codable, Equatable {
    let dayKey: String
    let isLightDay: Bool
    let revision: UUID
}

public struct DailyAgenda: Equatable, Sendable {
    public let summary: DailySummary
    public let occurrences: [DailyOccurrence]

    public func next(at now: Date, calendar: Calendar = .current) -> DailyOccurrence? {
        occurrences.first { $0.isReady(at: now, calendar: calendar) }
    }

    /// Known widget transitions, including civil midnight without a foreground app.
    /// Timed due dates can become eligible at a different timezone's midnight.
    public func widgetRefreshDates(after now: Date, calendar: Calendar = .current) -> [Date] {
        guard let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return [] }
        var dates: Set<Date> = [midnight]
        for item in occurrences where !item.isResolved {
            var candidates = [Date]()
            if let deferred = item.deferredUntil { candidates.append(deferred) }
            if case .timed(let due, let zone) = item.due, let timeZone = TimeZone(identifier: zone) {
                var dueCalendar = Calendar(identifier: .gregorian)
                dueCalendar.timeZone = timeZone
                candidates.append(dueCalendar.startOfDay(for: due))
            }
            dates.formUnion(candidates.filter { $0 > now && $0 < midnight })
        }
        return dates.sorted()
    }

    /// Timed deadlines use their absolute instant. Date-only items use the due date
    /// and 09:00/14:00/19:00 as ordering anchors only, never as invented due times.
    /// Equal anchors are ordered by day part then the stable occurrence ID.
    static func ordered(_ items: [DailyOccurrence], calendar: Calendar) -> [DailyOccurrence] {
        let localDay = LocalDay(calendar: calendar)
        func anchor(_ item: DailyOccurrence) -> Date {
            if let instant = item.due.instant { return instant }
            let key = item.due.dayKey(calendar: calendar)
            // Travel can enter a timezone that skipped this civil date entirely.
            // Use its UTC ordering anchor instead of crashing or changing identity.
            guard let noon = localDay.date(for: key) else { return LocalDay.utc.date(for: key)! }
            let hour = [9, 14, 19][item.dayPart.sortOrder]
            return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: noon) ?? noon
        }
        return items.sorted {
            let a = anchor($0), b = anchor($1)
            if a != b { return a < b }
            if $0.dayPart != $1.dayPart { return $0.dayPart.sortOrder < $1.dayPart.sortOrder }
            return $0.id < $1.id
        }
    }
}

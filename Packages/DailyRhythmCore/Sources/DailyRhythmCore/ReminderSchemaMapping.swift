import Foundation

/// Deliberately narrow capability spike: app-owned one-offs, not Apple Reminders
/// synchronization or recurring-template interpretation. Unsupported input fails
/// before a store write rather than being silently reduced to a different request.
public enum ReminderSchemaMapping {
    public static func definition(title: String, dueDate: DateComponents?, hasRecurrence: Bool,
                                  now: Date = Date(), calendar: Calendar = .current) throws -> HabitDefinition {
        guard validDate(now) else { throw ReminderMappingError.unsupportedDate }
        guard !hasRecurrence else { throw ReminderMappingError.unsupportedRecurrence }
        let local = LocalDay(calendar: calendar)
        var key = local.key(for: now)
        var time: ScheduledTime?
        if let due = dueDate {
            if #available(iOS 18.0, macOS 15.0, *), due.dayOfYear != nil {
                throw ReminderMappingError.unsupportedDate
            }
            guard due.calendar == nil || due.calendar?.identifier == .gregorian,
                  due.era == nil || due.era == 1,
                  due.weekday == nil, due.weekdayOrdinal == nil, due.weekOfMonth == nil,
                  due.weekOfYear == nil, due.yearForWeekOfYear == nil, due.quarter == nil,
                  due.isLeapMonth != true,
                  due.second == nil || due.second == 0,
                  due.nanosecond == nil || due.nanosecond == 0,
                  let year = due.year, let month = due.month, let day = due.day,
                  (1...9999).contains(year), (1...12).contains(month), (1...31).contains(day),
                  (due.hour == nil) == (due.minute == nil) else { throw ReminderMappingError.unsupportedDate }
            key = String(format: "%04d-%02d-%02d", year, month, day)
            guard validKey(key) else { throw ReminderMappingError.unsupportedDate }
            if let hour = due.hour, let minute = due.minute {
                let zone = due.timeZone ?? due.calendar?.timeZone ?? local.calendar.timeZone
                time = ScheduledTime(hour: hour, minute: minute, timeZoneIdentifier: zone.identifier)
            }
        }
        let part: DayPart = time.map { $0.hour < 12 ? .morning : ($0.hour < 18 ? .afternoon : .evening) } ?? .morning
        return try HabitDefinition(title: title, normalTarget: title, dayPart: part,
                                   recurrence: .once(dayKey: key), dueTime: time).cleaned()
    }

    public static func dueComponents(_ due: OccurrenceDue) -> DateComponents {
        switch due {
        case .dateOnly(let key):
            let parts = key.split(separator: "-").map { Int($0)! }
            return DateComponents(year: parts[0], month: parts[1], day: parts[2])
        case .timed(let at, let zone):
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: zone)!
            var result = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: at)
            result.timeZone = calendar.timeZone
            return result
        }
    }
}

public enum ReminderMappingError: Error, LocalizedError {
    case unsupportedRecurrence, unsupportedDate, unsupportedUpdate, unsupportedItem, unsupportedFields

    public var errorDescription: String? {
        switch self {
        case .unsupportedRecurrence: "This validation action supports one-off tasks only. Create a repeating habit in Daily Rhythm."
        case .unsupportedDate: "Choose a full calendar date, with an optional hour and minute. This action cannot preserve the supplied date components."
        case .unsupportedUpdate: "Choose whether this step is completed. Other reminder edits are not supported by this validation action."
        case .unsupportedFields: "Notes, flags, attachments, tags, links, sections and location triggers are not supported by this validation action. No task was created."
        case .unsupportedItem: "This validation action supports Daily Rhythm's own one-off tasks only."
        }
    }
}

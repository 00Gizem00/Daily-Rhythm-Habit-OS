import Foundation

/// An unsaved value used by creation and editing forms. No setter writes to the store.
/// Civil dates and wall-clock time stay separate until the user explicitly saves.
public struct HabitFormDraft: Sendable {
    public var title: String
    public var normalTarget: String
    public var hasLightTarget: Bool
    public var lightTarget: String
    public var dayPart: DayPart
    public var isRecurring: Bool
    public var weekdays: Set<Int>
    public var dayKey: String
    public var hasTime: Bool
    public var hour: Int
    public var minute: Int
    public var timeZoneIdentifier: String
    public var hasDuration: Bool
    public var durationText: String
    private var originalDue: OccurrenceDue?
    private var originalDayKey: String?
    private var originalTime: ScheduledTime?

    public init(definition: HabitDefinition, now: Date = Date(), calendar: Calendar = .current) {
        title = definition.title
        normalTarget = definition.normalTarget
        hasLightTarget = definition.lightTarget != nil
        lightTarget = definition.lightTarget ?? ""
        dayPart = definition.dayPart
        isRecurring = definition.recurrence.isRecurring
        weekdays = isRecurring ? definition.recurrence.weekdays : Set(1...7)
        if case .once(let key) = definition.recurrence { dayKey = key }
        else { dayKey = LocalDay(calendar: calendar).key(for: now) }
        hasTime = definition.dueTime != nil
        hour = definition.dueTime?.hour ?? 9
        minute = definition.dueTime?.minute ?? 0
        timeZoneIdentifier = definition.dueTime?.timeZoneIdentifier ?? calendar.timeZone.identifier
        hasDuration = definition.durationMinutes != nil
        durationText = definition.durationMinutes.map(String.init) ?? ""
    }

    public init(occurrence: DailyOccurrence, calendar: Calendar = .current) {
        var time: ScheduledTime?
        if case .timed(let at, let zone) = occurrence.due {
            var anchored = Calendar(identifier: .gregorian)
            anchored.timeZone = TimeZone(identifier: zone) ?? calendar.timeZone
            let components = anchored.dateComponents([.hour, .minute], from: at)
            time = ScheduledTime(hour: components.hour!, minute: components.minute!, timeZoneIdentifier: zone)
        }
        let key = occurrence.due.dayKey(calendar: calendar)
        self.init(definition: HabitDefinition(title: occurrence.title, normalTarget: occurrence.normalTarget,
                                             lightTarget: occurrence.lightTarget, dayPart: occurrence.dayPart,
                                             recurrence: .once(dayKey: key), dueTime: time,
                                             durationMinutes: occurrence.durationMinutes), calendar: calendar)
        originalDue = occurrence.due
        originalDayKey = key
        originalTime = time
    }

    public func definition() throws -> HabitDefinition {
        let duration: Int?
        if hasDuration {
            let text = durationText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, text.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let value = Int(text), value > 0 else { throw RoutineStoreError.invalidDuration }
            duration = value
        } else { duration = nil }
        return try HabitDefinition(title: title, normalTarget: normalTarget,
                                   lightTarget: hasLightTarget ? lightTarget : nil, dayPart: dayPart,
                                   recurrence: isRecurring ? .weekly(weekdays: weekdays) : .once(dayKey: dayKey),
                                   dueTime: selectedTime, durationMinutes: duration).cleaned()
    }

    public func due() throws -> OccurrenceDue {
        // A target-only edit must preserve seconds, subseconds and the selected DST fold.
        if let originalDue, dayKey == originalDayKey, selectedTime == originalTime { return originalDue }
        guard validKey(dayKey) else { throw RoutineStoreError.invalidDueDate }
        let definition = try definition()
        return try definition.due(on: dayKey)
    }

    private var selectedTime: ScheduledTime? {
        hasTime ? ScheduledTime(hour: hour, minute: minute, timeZoneIdentifier: timeZoneIdentifier) : nil
    }
}

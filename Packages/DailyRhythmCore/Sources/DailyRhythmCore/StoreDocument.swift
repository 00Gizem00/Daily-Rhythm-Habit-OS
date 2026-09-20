import Foundation

struct StoredHabit: Codable {
    let id: UUID
    let createdAt: Date
    let firstDayKey: String
    var mutationDayKey: String
    var revisions: [HabitRevision]
    var archiveIntervals: [ArchiveInterval]

    var archivedAt: Date? {
        guard let last = archiveIntervals.last, last.endDayKey == nil else { return nil }
        return last.archivedAt
    }

    func definition(on key: String) -> HabitDefinition? {
        revisions.last(where: { $0.effectiveDayKey <= key })?.definition
    }

    func isActive(on key: String) -> Bool {
        key >= firstDayKey && !archiveIntervals.contains {
            key >= $0.startDayKey && ($0.endDayKey.map { key < $0 } ?? true)
        }
    }

    func snapshot(on key: String) -> Habit {
        Habit(id: id, definition: definition(on: key) ?? revisions[0].definition,
              createdAt: createdAt, archivedAt: archivedAt, revisions: revisions,
              archiveIntervals: archiveIntervals)
    }
}

struct StoreDocument: Codable {
    var version = 2
    var habits: [StoredHabit] = []
    var records: [DailyOccurrence] = []

    static func decode(_ data: Data) throws -> (document: Self, migrated: Bool) {
        struct Header: Decodable { let version: Int }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        let version: Int
        do { version = try decoder.decode(Header.self, from: data).version }
        catch { throw RoutineStoreError.corruptData }
        guard version == 1 || version == 2 else { throw RoutineStoreError.unsupportedVersion(version) }
        do {
            let document = version == 1
                ? try LegacyDocument.migrate(data, decoder: decoder)
                : try decoder.decode(Self.self, from: data)
            try document.validate()
            return (document, version == 1)
        } catch { throw RoutineStoreError.corruptData }
    }

    func validate() throws {
        guard version == 2,
              Set(habits.map(\.id)).count == habits.count,
              Set(records.map(\.id)).count == records.count else { throw RoutineStoreError.corruptData }
        for habit in habits {
            guard validDate(habit.createdAt), validKey(habit.firstDayKey), validKey(habit.mutationDayKey),
                  habit.mutationDayKey >= habit.firstDayKey,
                  habit.revisions.first?.effectiveDayKey == habit.firstDayKey else {
                throw RoutineStoreError.corruptData
            }
            var previousKey: String?
            for revision in habit.revisions {
                guard validKey(revision.effectiveDayKey),
                      previousKey.map({ $0 < revision.effectiveDayKey }) ?? true,
                      revision.recordedAt.map(validDate) ?? true else { throw RoutineStoreError.corruptData }
                try validateDefinition(revision.definition)
                try validateRecurrenceChange(from: habit.revisions[0].definition.recurrence,
                                             to: revision.definition.recurrence)
                if case .once(let key) = revision.definition.recurrence {
                    guard key >= revision.effectiveDayKey else { throw RoutineStoreError.corruptData }
                }
                previousKey = revision.effectiveDayKey
            }
            var previousEnd = habit.firstDayKey
            for (index, interval) in habit.archiveIntervals.enumerated() {
                guard validKey(interval.startDayKey), validDate(interval.archivedAt),
                      interval.startDayKey >= previousEnd, interval.startDayKey <= habit.mutationDayKey,
                      (interval.endDayKey == nil) == (interval.restoredAt == nil) else {
                    throw RoutineStoreError.corruptData
                }
                if let end = interval.endDayKey, let restoredAt = interval.restoredAt {
                    guard validKey(end), end >= interval.startDayKey, end <= habit.mutationDayKey,
                          validDate(restoredAt) else { throw RoutineStoreError.corruptData }
                    previousEnd = end
                } else if index != habit.archiveIntervals.count - 1 { throw RoutineStoreError.corruptData }
            }
        }
        let byID = Dictionary(uniqueKeysWithValues: habits.map { ($0.id, $0) })
        for record in records {
            guard let habit = byID[record.habitID], validKey(record.dayKey),
                  record.id == "\(record.habitID.uuidString)|\(record.dayKey)",
                  record.dayKey >= habit.firstDayKey,
                  (record.outcome == nil) == (record.completedAt == nil),
                  record.completedAt.map(validDate) ?? true,
                  record.outcome != nil || record.completionSource == nil,
                  record.outcome != .light || record.lightTarget != nil else {
                throw RoutineStoreError.corruptData
            }
            // A record owns its snapshot, including a weekday removed by a later future edit.
            // Only a one-off's identity date is fixed by its recurrence; recurring snapshots
            // must not be revalidated against a mutable schedule.
            if case .once(let day) = habit.revisions[0].definition.recurrence, day != record.dayKey {
                throw RoutineStoreError.corruptData
            }
            try validateText(title: record.title, target: record.normalTarget, light: record.lightTarget)
            try validateDuration(record.durationMinutes)
            try validateDue(record.due, plannedDay: record.dayKey)
        }
    }
}

func validKey(_ key: String) -> Bool { LocalDay.utc.date(for: key) != nil }
func validDate(_ date: Date) -> Bool {
    date.timeIntervalSinceReferenceDate.isFinite &&
        date >= Date(timeIntervalSince1970: -62_135_596_800) &&
        date < Date(timeIntervalSince1970: 253_402_300_800)
}

func validateText(title: String, target: String, light: String?) throws {
    guard (1...100).contains(title.count), !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        throw RoutineStoreError.invalidTitle
    }
    guard (1...200).contains(target.count), !target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          light.map({ (1...200).contains($0.count) && !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? true
    else { throw RoutineStoreError.invalidTarget }
}

func validateDuration(_ minutes: Int?) throws {
    guard minutes.map({ $0 > 0 }) ?? true else { throw RoutineStoreError.invalidDuration }
}

func validateDefinition(_ definition: HabitDefinition) throws {
    try validateText(title: definition.title, target: definition.normalTarget, light: definition.lightTarget)
    try validateDuration(definition.durationMinutes)
    switch definition.recurrence {
    case .once(let key):
        guard validKey(key) else { throw RoutineStoreError.invalidDueDate }
    case .weekly(let days):
        guard !days.isEmpty, days.isSubset(of: Set(1...7)) else { throw RoutineStoreError.invalidWeekdays }
    }
    if let time = definition.dueTime {
        guard (0...23).contains(time.hour), (0...59).contains(time.minute),
              TimeZone(identifier: time.timeZoneIdentifier) != nil else { throw RoutineStoreError.invalidDueDate }
    }
}

func validateRecurrenceChange(from old: Recurrence, to new: Recurrence) throws {
    switch (old, new) {
    case (.weekly, .weekly): break
    case (.once(let oldDay), .once(let newDay)) where oldDay == newDay: break
    default: throw RoutineStoreError.unsupportedRecurrenceChange
    }
}

func validateDue(_ due: OccurrenceDue, plannedDay: String) throws {
    switch due {
    case .dateOnly(let key):
        guard validKey(key), key >= plannedDay else { throw RoutineStoreError.invalidDueDate }
    case .timed(let date, let zone):
        guard validDate(date), TimeZone(identifier: zone) != nil, due.dayKey() >= plannedDay else {
            throw RoutineStoreError.invalidDueDate
        }
    }
}

extension HabitDefinition {
    func cleaned() throws -> Self {
        var result = self
        result.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        result.normalTarget = normalTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        result.lightTarget = lightTarget?.trimmingCharacters(in: .whitespacesAndNewlines)
        try validateDefinition(result)
        return result
    }

    func due(on key: String) throws -> OccurrenceDue {
        guard let time = dueTime else { return .dateOnly(dayKey: key) }
        var calendar = Calendar(identifier: .gregorian)
        guard let zone = TimeZone(identifier: time.timeZoneIdentifier) else { throw RoutineStoreError.invalidDueDate }
        calendar.timeZone = zone
        let localDay = LocalDay(calendar: calendar)
        guard let noon = localDay.date(for: key),
              let date = calendar.nextDate(
                after: calendar.startOfDay(for: noon).addingTimeInterval(-1),
                matching: DateComponents(hour: time.hour, minute: time.minute, second: 0),
                matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward
              ), localDay.key(for: date) == key else { throw RoutineStoreError.invalidDueDate }
        return .timed(at: date, timeZoneIdentifier: time.timeZoneIdentifier)
    }
}

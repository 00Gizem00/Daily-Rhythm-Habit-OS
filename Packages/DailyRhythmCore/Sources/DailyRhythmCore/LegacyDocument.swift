import Foundation

/// Kept separate from v2 so changes to today's model cannot reinterpret a v1 file.
struct LegacyDocument: Decodable {
    struct Habit: Decodable {
        let id: UUID
        let title: String
        let normalTarget: String
        let lightTarget: String?
        let dayPart: DayPart
        let weekdays: Set<Int>
        let createdAt: Date
        let archivedAt: Date?
        let firstDayKey: String
        let archiveDayKey: String?
    }
    struct Record: Decodable {
        let id: String
        let habitID: UUID
        let dayKey: String
        let title: String
        let normalTarget: String
        let lightTarget: String?
        let dayPart: DayPart
        let outcome: CompletionOutcome?
        let completedAt: Date?
    }
    let habits: [Habit]
    let records: [Record]

    static func migrate(_ data: Data, decoder: JSONDecoder) throws -> StoreDocument {
        // Reject unfamiliar fields instead of silently dropping data during an upgrade.
        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? [String: Any],
              Set(root.keys).isSubset(of: ["version", "habits", "records"]),
              let rawHabits = root["habits"] as? [[String: Any]],
              let rawRecords = root["records"] as? [[String: Any]],
              rawHabits.allSatisfy({ Set($0.keys).isSubset(of: [
                "id", "title", "normalTarget", "lightTarget", "dayPart", "weekdays", "createdAt",
                "archivedAt", "firstDayKey", "archiveDayKey"
              ]) }),
              rawRecords.allSatisfy({ Set($0.keys).isSubset(of: [
                "id", "habitID", "dayKey", "title", "normalTarget", "lightTarget", "dayPart", "outcome", "completedAt"
              ]) }) else { throw RoutineStoreError.corruptData }
        let legacy = try decoder.decode(Self.self, from: data)
        guard Set(legacy.habits.map(\.id)).count == legacy.habits.count,
              Set(legacy.records.map(\.id)).count == legacy.records.count else { throw RoutineStoreError.corruptData }
        var habits = try legacy.habits.map { habit in
            guard validKey(habit.firstDayKey),
                  (habit.archivedAt == nil) == (habit.archiveDayKey == nil) else { throw RoutineStoreError.corruptData }
            var intervals: [ArchiveInterval] = []
            if let date = habit.archivedAt, let key = habit.archiveDayKey {
                guard validKey(key), key >= habit.firstDayKey else { throw RoutineStoreError.corruptData }
                intervals.append(ArchiveInterval(startDayKey: key, archivedAt: date))
            }
            let definition = HabitDefinition(title: habit.title, normalTarget: habit.normalTarget,
                                             lightTarget: habit.lightTarget, dayPart: habit.dayPart,
                                             recurrence: .weekly(weekdays: habit.weekdays))
            return StoredHabit(id: habit.id, createdAt: habit.createdAt, firstDayKey: habit.firstDayKey,
                               mutationDayKey: max(habit.firstDayKey, habit.archiveDayKey ?? habit.firstDayKey),
                               revisions: [HabitRevision(effectiveDayKey: habit.firstDayKey, recordedAt: nil,
                                                         definition: definition)], archiveIntervals: intervals)
        }
        let byID = Dictionary(uniqueKeysWithValues: legacy.habits.map { ($0.id, $0) })
        let records = try legacy.records.map { record in
            guard let habit = byID[record.habitID],
                  let weekday = LocalDay.utc.weekday(for: record.dayKey), habit.weekdays.contains(weekday),
                  record.title == habit.title, record.normalTarget == habit.normalTarget,
                  record.lightTarget == habit.lightTarget, record.dayPart == habit.dayPart else {
                throw RoutineStoreError.corruptData
            }
            return DailyOccurrence(id: record.id, habitID: record.habitID, dayKey: record.dayKey,
                                   title: record.title, normalTarget: record.normalTarget,
                                   lightTarget: record.lightTarget, dayPart: record.dayPart,
                                   durationMinutes: nil, due: .dateOnly(dayKey: record.dayKey),
                                   outcome: record.outcome, completedAt: record.completedAt, completionSource: nil)
        }
        for index in habits.indices {
            let lastRecordedDay = records.filter { $0.habitID == habits[index].id }.map(\.dayKey).max()
            habits[index].mutationDayKey = max(habits[index].mutationDayKey, lastRecordedDay ?? habits[index].firstDayKey)
        }
        return StoreDocument(habits: habits, records: records)
    }
}

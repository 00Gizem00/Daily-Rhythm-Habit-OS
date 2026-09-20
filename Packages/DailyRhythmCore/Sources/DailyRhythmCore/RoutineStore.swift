import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// A local, app-group-compatible store. Each operation locks a separate stable lock
/// file, rereads the latest snapshot, then atomically replaces the JSON if changed.
/// All entry points (app, widget, intents) must use this store for mutations.
///
/// Methods are synchronous and keep lock duration short. Large imports and long
/// history computations should be invoked away from the main actor.
public final class RoutineStore: @unchecked Sendable {
    public let fileURL: URL
    private let localDay: LocalDay

    public init(fileURL: URL, calendar: Calendar = .current) {
        self.fileURL = fileURL
        self.localDay = LocalDay(calendar: calendar)
    }

    public func habits(includeArchived: Bool = false) throws -> [Habit] {
        try transaction { state in
            (state.habits.filter { includeArchived || $0.archivedAt == nil }, false)
        }
    }

    @discardableResult
    public func addHabit(
        title: String,
        normalTarget: String,
        lightTarget: String? = nil,
        dayPart: DayPart,
        weekdays: Set<Int> = Set(1...7),
        now: Date = Date()
    ) throws -> Habit {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTarget = normalTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanLight = lightTarget?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...100).contains(cleanTitle.count) else { throw RoutineStoreError.invalidTitle }
        guard (1...200).contains(cleanTarget.count), cleanLight == nil || (1...200).contains(cleanLight!.count)
        else { throw RoutineStoreError.invalidTarget }
        guard !weekdays.isEmpty, weekdays.isSubset(of: Set(1...7)) else { throw RoutineStoreError.invalidWeekdays }
        let habit = Habit(
            id: UUID(), title: cleanTitle, normalTarget: cleanTarget,
            lightTarget: cleanLight, dayPart: dayPart, weekdays: weekdays,
            createdAt: now, archivedAt: nil, firstDayKey: localDay.key(for: now), archiveDayKey: nil
        )
        return try transaction { state in
            state.habits.append(habit)
            return (habit, true)
        }
    }

    public func summary(for date: Date = Date()) throws -> DailySummary {
        let key = localDay.key(for: date)
        return try transaction { state in (self.summary(dayKey: key, state: state), false) }
    }

    /// Oldest day first. Days with no scheduled habits are included with zero counts.
    public func history(days: Int = 7, endingOn: Date = Date()) throws -> [DailySummary] {
        let keys = try localDay.keys(days: days, endingOn: endingOn)
        return try transaction { state in
            (keys.map { self.summary(dayKey: $0, state: state) }, false)
        }
    }

    /// First completion wins. Repeated requests, including a competing full/light
    /// action, never increment progress or replace the original timestamp/outcome.
    /// Reopen explicitly before choosing a different outcome.
    public func complete(
        occurrenceID: String,
        outcome: CompletionOutcome = .full,
        now: Date = Date()
    ) throws {
        try transaction { state in
            let (habitID, key) = try self.parse(occurrenceID: occurrenceID)
            guard key <= self.localDay.key(for: now) else { throw RoutineStoreError.futureCompletion }
            guard let habit = state.habits.first(where: { $0.id == habitID }) else {
                throw RoutineStoreError.habitNotFound
            }
            if state.records.contains(where: { $0.id == occurrenceID && $0.outcome != nil }) {
                return ((), false)
            }
            guard self.isScheduled(habit, on: key) else { throw RoutineStoreError.invalidOccurrence }
            if outcome == .light && habit.lightTarget == nil { throw RoutineStoreError.lightTargetUnavailable }
            var occurrence = self.occurrence(for: habit, on: key)
            occurrence.outcome = outcome
            occurrence.completedAt = now
            if let index = state.records.firstIndex(where: { $0.id == occurrenceID }) {
                state.records[index] = occurrence
            } else {
                state.records.append(occurrence)
            }
            return ((), true)
        }
    }

    public func reopen(occurrenceID: String) throws {
        try transaction { state in
            let (habitID, key) = try self.parse(occurrenceID: occurrenceID)
            guard state.habits.contains(where: { $0.id == habitID }) else { throw RoutineStoreError.habitNotFound }
            guard let index = state.records.firstIndex(where: { $0.id == occurrenceID }) else {
                guard let habit = state.habits.first(where: { $0.id == habitID }), self.isScheduled(habit, on: key)
                else { throw RoutineStoreError.invalidOccurrence }
                return ((), false)
            }
            guard state.records[index].outcome != nil else { return ((), false) }
            state.records[index].outcome = nil
            state.records[index].completedAt = nil
            return ((), true)
        }
    }

    /// Archiving removes uncompleted work from the archive day onward. Completed
    /// occurrences and earlier scheduled history remain available.
    public func archive(habitID: UUID, now: Date = Date()) throws {
        try transaction { state in
            guard let index = state.habits.firstIndex(where: { $0.id == habitID }) else {
                throw RoutineStoreError.habitNotFound
            }
            guard state.habits[index].archivedAt == nil else { return ((), false) }
            guard self.localDay.key(for: now) >= state.habits[index].firstDayKey else {
                throw RoutineStoreError.invalidOccurrence
            }
            state.habits[index].archivedAt = now
            state.habits[index].archiveDayKey = self.localDay.key(for: now)
            return ((), true)
        }
    }

    private func isScheduled(_ habit: Habit, on key: String) -> Bool {
        guard key >= habit.firstDayKey,
              habit.archiveDayKey.map({ key < $0 }) ?? true,
              let weekday = localDay.weekday(for: key) else { return false }
        return habit.weekdays.contains(weekday)
    }

    private func occurrence(for habit: Habit, on key: String) -> DailyOccurrence {
        DailyOccurrence(
            id: "\(habit.id.uuidString)|\(key)", habitID: habit.id, dayKey: key,
            title: habit.title, normalTarget: habit.normalTarget, lightTarget: habit.lightTarget,
            dayPart: habit.dayPart, outcome: nil, completedAt: nil
        )
    }

    private func summary(dayKey: String, state: StoreState) -> DailySummary {
        var result: [DailyOccurrence] = []
        for habit in state.habits {
            let id = "\(habit.id.uuidString)|\(dayKey)"
            let saved = state.records.first { $0.id == id }
            if let saved, saved.outcome != nil {
                result.append(saved)
            } else if isScheduled(habit, on: dayKey) {
                result.append(saved ?? occurrence(for: habit, on: dayKey))
            }
        }
        // Creation order is stable within each daypart, even for duplicate titles.
        let order = Dictionary(uniqueKeysWithValues: state.habits.enumerated().map { ($0.element.id, $0.offset) })
        result.sort {
            if $0.dayPart != $1.dayPart { return $0.dayPart.sortOrder < $1.dayPart.sortOrder }
            return order[$0.habitID, default: 0] < order[$1.habitID, default: 0]
        }
        return DailySummary(dayKey: dayKey, occurrences: result)
    }

    private func parse(occurrenceID: String) throws -> (UUID, String) {
        let parts = occurrenceID.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count == 2, let id = UUID(uuidString: String(parts[0])),
              id.uuidString == parts[0], localDay.date(for: String(parts[1])) != nil else {
            throw RoutineStoreError.invalidOccurrence
        }
        return (id, String(parts[1]))
    }

    private struct StoreState: Codable {
        var version = 1
        var habits: [Habit] = []
        var records: [DailyOccurrence] = []
    }

    private struct VersionHeader: Decodable { let version: Int }

    private func transaction<T>(_ body: (inout StoreState) throws -> (T, Bool)) throws -> T {
        guard fileURL.isFileURL else { throw RoutineStoreError.fileAccess("Expected a file URL") }
        let directory = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try configureFileProtection(at: directory)
        }
        catch { throw RoutineStoreError.fileAccess("Create directory: \(error.localizedDescription)") }

        // Never lock the JSON file itself: atomic replacement changes its inode.
        let lockURL = fileURL.appendingPathExtension("lock")
        let descriptor = lockURL.path.withCString { open($0, O_CREAT | O_RDWR | O_CLOEXEC, mode_t(0o600)) }
        guard descriptor >= 0 else { throw RoutineStoreError.fileAccess("Open lock: \(errno)") }
        defer { close(descriptor) }
        do { try configureFileProtection(at: lockURL) }
        catch { throw RoutineStoreError.fileAccess("Protect lock: \(error.localizedDescription)") }
        while flock(descriptor, LOCK_EX) != 0 {
            guard errno == EINTR else { throw RoutineStoreError.fileAccess("Acquire lock: \(errno)") }
        }
        defer { _ = flock(descriptor, LOCK_UN) }

        var state = try readState()
        let (result, changed) = try body(&state)
        if changed {
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .deferredToDate
                let data = try encoder.encode(state)
                #if os(iOS)
                try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                #else
                try data.write(to: fileURL, options: .atomic)
                #endif
            } catch { throw RoutineStoreError.fileAccess("Save data: \(error.localizedDescription)") }
        }
        return result
    }

    private func configureFileProtection(at url: URL) throws {
        #if os(iOS)
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
        #endif
    }

    private func readState() throws -> StoreState {
        let data: Data
        do { data = try Data(contentsOf: fileURL) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return StoreState() }
        catch { throw RoutineStoreError.fileAccess("Read data: \(error.localizedDescription)") }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        let header: VersionHeader
        do { header = try decoder.decode(VersionHeader.self, from: data) }
        catch { throw RoutineStoreError.corruptData }
        guard header.version == 1 else { throw RoutineStoreError.unsupportedVersion(header.version) }
        let state: StoreState
        do { state = try decoder.decode(StoreState.self, from: data) }
        catch { throw RoutineStoreError.corruptData }
        try validate(state)
        return state
    }

    private func validate(_ state: StoreState) throws {
        guard Set(state.habits.map(\.id)).count == state.habits.count,
              Set(state.records.map(\.id)).count == state.records.count else { throw RoutineStoreError.corruptData }
        for habit in state.habits {
            guard (1...100).contains(habit.title.count), (1...200).contains(habit.normalTarget.count),
                  habit.lightTarget == nil || (1...200).contains(habit.lightTarget!.count),
                  !habit.weekdays.isEmpty, habit.weekdays.isSubset(of: Set(1...7)),
                  localDay.date(for: habit.firstDayKey) != nil,
                  (habit.archivedAt == nil) == (habit.archiveDayKey == nil) else {
                throw RoutineStoreError.corruptData
            }
            if let key = habit.archiveDayKey {
                guard localDay.date(for: key) != nil, key >= habit.firstDayKey else { throw RoutineStoreError.corruptData }
            }
        }
        for record in state.records {
            guard let habit = state.habits.first(where: { $0.id == record.habitID }),
                  record.id == "\(record.habitID.uuidString)|\(record.dayKey)",
                  let weekday = localDay.weekday(for: record.dayKey),
                  record.dayKey >= habit.firstDayKey, habit.weekdays.contains(weekday),
                  (record.outcome == nil) == (record.completedAt == nil),
                  record.outcome != .light || record.lightTarget != nil,
                  record.title == habit.title, record.normalTarget == habit.normalTarget,
                  record.lightTarget == habit.lightTarget, record.dayPart == habit.dayPart else {
                throw RoutineStoreError.corruptData
            }
        }
    }
}

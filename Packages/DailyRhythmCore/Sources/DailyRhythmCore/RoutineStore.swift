import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Every operation locks a stable sibling lock file, rereads and validates the latest
/// document, then atomically replaces it if changed. Migration uses the same lock.
public final class RoutineStore: @unchecked Sendable {
    public let fileURL: URL
    public var migrationBackupURL: URL { fileURL.appendingPathExtension("v1-backup") }
    private let localDay: LocalDay
    private let entitlementProvider: any HabitEntitlementProvider
    private let saveSnapshot: @Sendable (Data, URL) throws -> Void

    public convenience init(fileURL: URL, calendar: Calendar = .current,
                            entitlementProvider: any HabitEntitlementProvider = FreeHabitEntitlementProvider()) {
        self.init(fileURL: fileURL, calendar: calendar, entitlementProvider: entitlementProvider,
                  saveSnapshot: Self.writeSnapshot)
    }

    // Internal fault-injection seam for atomic-save/migration failure tests.
    init(fileURL: URL, calendar: Calendar,
         entitlementProvider: any HabitEntitlementProvider = FreeHabitEntitlementProvider(),
         saveSnapshot: @escaping @Sendable (Data, URL) throws -> Void) {
        self.fileURL = fileURL
        self.localDay = LocalDay(calendar: calendar)
        self.entitlementProvider = entitlementProvider
        self.saveSnapshot = saveSnapshot
    }

    /// Archive filtering reflects the latest archive/restore action. `asOf` selects the effective definition.
    public func habits(includeArchived: Bool = false, asOf: Date = Date()) throws -> [Habit] {
        try checkDate(asOf)
        let key = localDay.key(for: asOf)
        return try transaction { state in
            (state.habits.filter { includeArchived || $0.archivedAt == nil }.map { $0.snapshot(on: key) }, false)
        }
    }

    @discardableResult
    public func addHabit(title: String, normalTarget: String, lightTarget: String? = nil,
                         dayPart: DayPart, weekdays: Set<Int> = Set(1...7), now: Date = Date()) throws -> Habit {
        try addHabit(HabitDefinition(title: title, normalTarget: normalTarget, lightTarget: lightTarget,
                                    dayPart: dayPart, recurrence: .weekly(weekdays: weekdays)), now: now)
    }

    @discardableResult
    public func addHabit(_ definition: HabitDefinition, now: Date = Date()) throws -> Habit {
        try addHabits([definition], now: now)[0]
    }

    /// All-or-nothing creation for routines and future proposal Apply. Every recurring
    /// definition consumes a slot, even when several definitions belong to one routine.
    @discardableResult
    public func addHabits(_ definitions: [HabitDefinition], now: Date = Date()) throws -> [Habit] {
        try checkDate(now)
        let key = localDay.key(for: now)
        let habits = try definitions.map { input in
            let definition = try input.cleaned()
            if case .once(let day) = definition.recurrence {
                guard day >= key else { throw RoutineStoreError.invalidDueDate }
                _ = try definition.due(on: day)
            }
            return StoredHabit(id: UUID(), createdAt: now, firstDayKey: key, mutationDayKey: key,
                               revisions: [HabitRevision(effectiveDayKey: key, recordedAt: now, definition: definition)],
                               archiveIntervals: [])
        }
        return try transaction { state in
            try self.validateActivation(of: habits, in: state)
            state.habits.append(contentsOf: habits)
            return (habits.map { $0.snapshot(on: key) }, !habits.isEmpty)
        }
    }

    /// Full definition replacement, effective strictly after today and the last mutation's civil date.
    /// Existing future revisions after this date remain in force. An occurrence override takes precedence.
    public func editHabit(habitID: UUID, definition: HabitDefinition, effectiveDayKey: String,
                          now: Date = Date()) throws {
        try checkDate(now)
        let definition = try definition.cleaned()
        let today = localDay.key(for: now)
        guard validKey(effectiveDayKey), effectiveDayKey > today else { throw RoutineStoreError.invalidEffectiveDate }
        try transaction { state in
            let index = try self.index(of: habitID, in: state)
            guard effectiveDayKey > state.habits[index].mutationDayKey else { throw RoutineStoreError.invalidEffectiveDate }
            try validateRecurrenceChange(from: state.habits[index].revisions[0].definition.recurrence, to: definition.recurrence)
            if case .once(let day) = definition.recurrence {
                guard effectiveDayKey <= day else { throw RoutineStoreError.invalidEffectiveDate }
                _ = try definition.due(on: day)
            }
            if let previous = state.habits[index].revisions.first(where: { $0.effectiveDayKey == effectiveDayKey }),
               previous.definition == definition { return ((), false) }
            state.habits[index].revisions.removeAll { $0.effectiveDayKey == effectiveDayKey }
            state.habits[index].revisions.append(HabitRevision(effectiveDayKey: effectiveDayKey, recordedAt: now, definition: definition))
            state.habits[index].revisions.sort { $0.effectiveDayKey < $1.effectiveDayKey }
            state.habits[index].mutationDayKey = max(today, state.habits[index].mutationDayKey)
            return ((), true)
        }
    }

    /// Summaries always use the original planned day; postponing never moves a historical denominator.
    public func summary(for date: Date = Date()) throws -> DailySummary {
        try checkDate(date)
        let key = localDay.key(for: date)
        return try transaction { state in (try self.summary(dayKey: key, state: state), false) }
    }

    /// Oldest day first, including days with zero planned work. Reads do not materialize future occurrences.
    public func history(days: Int = 7, endingOn: Date = Date()) throws -> [DailySummary] {
        try checkDate(endingOn)
        let keys = try localDay.keys(days: days, endingOn: endingOn)
        return try transaction { state in (try keys.map { try self.summary(dayKey: $0, state: state) }, false) }
    }

    /// Resolves an exact identity, including overdue one-offs and postponed work on an earlier planned date.
    public func occurrence(id: String) throws -> DailyOccurrence {
        try transaction { state in (try self.requireOccurrence(id, state: state), false) }
    }

    /// First completion wins, including its source. Early completion is allowed on the due date,
    /// but never before that civil date. Reopen explicitly to choose a different outcome.
    public func complete(occurrenceID: String, outcome: CompletionOutcome = .full,
                         source: CompletionSource? = nil, now: Date = Date()) throws {
        try checkDate(now)
        try transaction { state in
            var occurrence = try self.requireOccurrence(occurrenceID, state: state)
            guard !occurrence.isCompleted else { return ((), false) }
            guard occurrence.due.dayKey(calendar: self.localDay.calendar) <=
                    occurrence.due.currentDay(at: now, calendar: self.localDay.calendar) else {
                throw RoutineStoreError.futureCompletion
            }
            if outcome == .light && occurrence.lightTarget == nil { throw RoutineStoreError.lightTargetUnavailable }
            occurrence.outcome = outcome
            occurrence.completedAt = now
            occurrence.completionSource = source
            self.save(occurrence, in: &state, now: now)
            return ((), true)
        }
    }

    public func reopen(occurrenceID: String, now: Date = Date()) throws {
        try checkDate(now)
        try transaction { state in
            // Repeated undo stays a no-op even after the first undo hides an archived record.
            let (habitID, _) = try self.parse(occurrenceID: occurrenceID)
            _ = try self.index(of: habitID, in: state)
            var occurrence = try state.records.first(where: { $0.id == occurrenceID })
                ?? self.requireOccurrence(occurrenceID, state: state)
            guard occurrence.isCompleted else { return ((), false) }
            occurrence.outcome = nil
            occurrence.completedAt = nil
            occurrence.completionSource = nil
            self.save(occurrence, in: &state, now: now)
            return ((), true)
        }
    }

    /// Due-only changes may postpone overdue work. ID, targets and planned day are retained.
    public func rescheduleOccurrence(occurrenceID: String, due: OccurrenceDue, now: Date = Date()) throws {
        try mutatePending(occurrenceID, now: now) { occurrence, _ in
            try validateDue(due, plannedDay: occurrence.dayKey)
            occurrence.due = due
        }
    }

    /// Replaces this pending occurrence's targets/duration/due only. Nil removes the optional value.
    /// Past target snapshots cannot be edited; use the due-only API to postpone overdue work.
    public func updateOccurrence(occurrenceID: String, normalTarget: String, lightTarget: String?,
                                 durationMinutes: Int?, due: OccurrenceDue, now: Date = Date()) throws {
        let target = normalTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        let light = lightTarget?.trimmingCharacters(in: .whitespacesAndNewlines)
        try mutatePending(occurrenceID, now: now) { occurrence, frontier in
            guard occurrence.dayKey >= frontier else { throw RoutineStoreError.invalidEffectiveDate }
            try validateText(title: occurrence.title, target: target, light: light)
            try validateDuration(durationMinutes)
            try validateDue(due, plannedDay: occurrence.dayKey)
            occurrence.normalTarget = target
            occurrence.lightTarget = light
            occurrence.durationMinutes = durationMinutes
            occurrence.due = due
        }
    }

    /// Removes pending work from this original planned date onward, retaining earlier history and completed records.
    public func archive(habitID: UUID, now: Date = Date()) throws {
        try checkDate(now)
        let today = localDay.key(for: now)
        try transaction { state in
            let index = try self.index(of: habitID, in: state)
            guard state.habits[index].archivedAt == nil else { return ((), false) }
            guard today >= state.habits[index].mutationDayKey else { throw RoutineStoreError.invalidEffectiveDate }
            state.habits[index].archiveIntervals.append(ArchiveInterval(startDayKey: today, archivedAt: now))
            state.habits[index].mutationDayKey = today
            return ((), true)
        }
    }

    /// Restarts planning on the restore date. All preceding archive gaps remain excluded.
    public func restore(habitID: UUID, now: Date = Date()) throws {
        try restore(habitIDs: [habitID], now: now)
    }

    /// Atomically restores a selection. Duplicate IDs and already-active habits do
    /// not consume extra slots. Capacity or validation failure leaves all archived.
    public func restore(habitIDs: [UUID], now: Date = Date()) throws {
        try checkDate(now)
        let today = localDay.key(for: now)
        try transaction { state in
            let indices = try Set(habitIDs).map { try self.index(of: $0, in: state) }
                .filter { state.habits[$0].archivedAt != nil }
            for index in indices {
                guard today >= state.habits[index].mutationDayKey else { throw RoutineStoreError.invalidEffectiveDate }
            }
            try self.validateActivation(of: indices.map { state.habits[$0] }, in: state)
            for index in indices {
                let last = state.habits[index].archiveIntervals.count - 1
                state.habits[index].archiveIntervals[last].endDayKey = today
                state.habits[index].archiveIntervals[last].restoredAt = now
                state.habits[index].mutationDayKey = today
            }
            return ((), !indices.isEmpty)
        }
    }

    /// Call only after rereading the document under the transaction lock. Recurrence
    /// kind is immutable, so future revisions and today's weekdays cannot evade capacity.
    private func validateActivation(of habits: [StoredHabit], in state: StoreDocument) throws {
        let requested = habits.filter { $0.revisions[0].definition.recurrence.isRecurring }.count
        guard requested > 0 else { return }
        let active = state.habits.filter {
            $0.archivedAt == nil && $0.revisions[0].definition.recurrence.isRecurring
        }.count
        try HabitActivationPolicy.validate(activeCount: active, activatingCount: requested,
                                           entitlement: entitlementProvider.currentEntitlement())
    }

    private func mutatePending(_ id: String, now: Date,
                               body: (inout DailyOccurrence, String) throws -> Void) throws {
        try checkDate(now)
        try transaction { state in
            var occurrence = try self.requireOccurrence(id, state: state)
            guard !occurrence.isCompleted else { throw RoutineStoreError.completedOccurrence }
            let index = try self.index(of: occurrence.habitID, in: state)
            let before = occurrence
            try body(&occurrence, max(self.localDay.key(for: now), state.habits[index].mutationDayKey))
            guard occurrence != before else { return ((), false) }
            self.save(occurrence, in: &state, now: now)
            return ((), true)
        }
    }

    private func save(_ occurrence: DailyOccurrence, in state: inout StoreDocument, now: Date) {
        if let index = state.records.firstIndex(where: { $0.id == occurrence.id }) { state.records[index] = occurrence }
        else { state.records.append(occurrence) }
        if let index = state.habits.firstIndex(where: { $0.id == occurrence.habitID }) {
            state.habits[index].mutationDayKey = max(state.habits[index].mutationDayKey, localDay.key(for: now))
        }
    }

    private func index(of id: UUID, in state: StoreDocument) throws -> Int {
        guard let index = state.habits.firstIndex(where: { $0.id == id }) else { throw RoutineStoreError.habitNotFound }
        return index
    }

    private func requireOccurrence(_ id: String, state: StoreDocument) throws -> DailyOccurrence {
        let (habitID, key) = try parse(occurrenceID: id)
        let habit = state.habits[try index(of: habitID, in: state)]
        guard let occurrence = try occurrence(for: habit, on: key, state: state) else { throw RoutineStoreError.invalidOccurrence }
        return occurrence
    }

    private func occurrence(for habit: StoredHabit, on key: String, state: StoreDocument) throws -> DailyOccurrence? {
        let id = "\(habit.id.uuidString)|\(key)"
        let saved = state.records.first { $0.id == id }
        if let saved, saved.isCompleted { return saved }
        guard habit.isActive(on: key) else { return nil }
        // Explicit pending overrides are pinned even if a later future schedule edit removes this weekday.
        if let saved { return saved }
        guard let definition = habit.definition(on: key), definition.recurrence.matches(key) else { return nil }
        return DailyOccurrence(id: id, habitID: habit.id, dayKey: key, title: definition.title,
                               normalTarget: definition.normalTarget, lightTarget: definition.lightTarget,
                               dayPart: definition.dayPart, durationMinutes: definition.durationMinutes,
                               due: try definition.due(on: key))
    }

    private func summary(dayKey: String, state: StoreDocument) throws -> DailySummary {
        var result = try state.habits.compactMap { try occurrence(for: $0, on: dayKey, state: state) }
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
              id.uuidString == parts[0], validKey(String(parts[1])) else { throw RoutineStoreError.invalidOccurrence }
        return (id, String(parts[1]))
    }

    private func checkDate(_ date: Date) throws {
        guard validDate(date) else { throw RoutineStoreError.invalidDueDate }
    }

    private func transaction<T>(_ body: (inout StoreDocument) throws -> (T, Bool)) throws -> T {
        guard fileURL.isFileURL else { throw RoutineStoreError.fileAccess("Expected a file URL") }
        let directory = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try configureFileProtection(at: directory)
        } catch { throw RoutineStoreError.fileAccess("Create directory: \(error.localizedDescription)") }

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

        var (state, legacyBytes) = try readState()
        let (result, changed) = try body(&state)
        if changed || legacyBytes != nil {
            do { try state.validate() }
            catch { throw RoutineStoreError.corruptData }
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .deferredToDate
                let data = try encoder.encode(state)
                // All migration + operation validation/encoding has succeeded before touching disk.
                if let legacyBytes { try preserveLegacyBytes(legacyBytes) }
                try saveSnapshot(data, fileURL)
            } catch { throw RoutineStoreError.fileAccess("Save data: \(error.localizedDescription)") }
        }
        return result
    }

    private func preserveLegacyBytes(_ original: Data) throws {
        if !FileManager.default.fileExists(atPath: migrationBackupURL.path) {
            try FileManager.default.copyItem(at: fileURL, to: migrationBackupURL)
            try configureFileProtection(at: migrationBackupURL)
        }
        guard try Data(contentsOf: migrationBackupURL) == original else {
            throw RoutineStoreError.fileAccess("Existing v1 backup differs; preserve both files for recovery")
        }
    }

    private static func writeSnapshot(_ data: Data, to url: URL) throws {
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }

    private func configureFileProtection(at url: URL) throws {
        #if os(iOS)
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        #endif
    }

    private func readState() throws -> (StoreDocument, Data?) {
        let data: Data
        do { data = try Data(contentsOf: fileURL) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return (StoreDocument(), nil) }
        catch { throw RoutineStoreError.fileAccess("Read data: \(error.localizedDescription)") }
        let decoded = try StoreDocument.decode(data)
        return (decoded.document, decoded.migrated ? data : nil)
    }
}

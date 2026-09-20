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
    public func migrationBackupURL(from version: Int) -> URL {
        fileURL.appendingPathExtension("v\(version)-backup")
    }
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

    /// First-run confirmation is atomic and retry-safe even if the process exits
    /// after saving habits but before marking the UI flow finished. Draft IDs are
    /// the persisted habit IDs; retries never rewrite a habit that was later edited.
    @discardableResult
    public func createInitialRoutine(_ draft: OnboardingDraft, now: Date = Date()) throws -> [Habit] {
        try checkDate(now)
        guard (1...3).contains(draft.entries.count), Set(draft.entries.map(\.id)).count == draft.entries.count else {
            throw RoutineStoreError.invalidOnboardingDraft
        }
        let key = localDay.key(for: now)
        let habits = try draft.entries.map { entry in
            let definition = try entry.form.definition()
            guard definition.recurrence.isRecurring else { throw RoutineStoreError.invalidOnboardingDraft }
            return StoredHabit(id: entry.id, createdAt: now, firstDayKey: key, mutationDayKey: key,
                               revisions: [HabitRevision(effectiveDayKey: key, recordedAt: now, definition: definition)],
                               archiveIntervals: [])
        }
        return try transaction { state in
            let ids = Set(habits.map(\.id))
            let existing = state.habits.filter { ids.contains($0.id) }
            if existing.count == habits.count { return (existing.map { $0.snapshot(on: key) }, false) }
            guard state.habits.isEmpty else { throw RoutineStoreError.onboardingAlreadyStarted }
            try self.validateActivation(of: habits, in: state)
            state.habits.append(contentsOf: habits)
            return (habits.map { $0.snapshot(on: key) }, true)
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

    /// Seven civil days through today. Previewing tomorrow never inserts records.
    public func review(at now: Date = Date()) throws -> RhythmReview {
        try checkDate(now)
        let keys = try localDay.keys(days: 7, endingOn: now)
        let todayKey = localDay.key(for: now)
        guard let noon = localDay.date(for: todayKey),
              let nextDay = localDay.calendar.date(byAdding: .day, value: 1, to: noon) else {
            throw RoutineStoreError.invalidHistoryRange
        }
        let tomorrowKey = localDay.key(for: nextDay)
        return try transaction { state in
            let agenda = try self.agenda(at: now, state: state)
            let days = try keys.map { key in
                RhythmReviewDay(summary: try self.summary(dayKey: key, state: state),
                                asOf: now, calendar: self.localDay.calendar)
            }
            let tomorrow = try self.summary(dayKey: tomorrowKey, state: state)
            // Preview only tomorrow's original plan, excluding steps moved to later dates.
            // Use the same due-time/day-part/ID order as Next Up, without a readiness check at noon.
            let candidates = tomorrow.occurrences.filter {
                !$0.isResolved && $0.due.dayKey(calendar: self.localDay.calendar) == tomorrowKey
            }
            let first = DailyAgenda.ordered(candidates, calendar: self.localDay.calendar).first
            return (RhythmReview(asOf: now, agenda: agenda,
                                 habits: state.habits.map { $0.snapshot(on: todayKey) }, days: days,
                                 tomorrow: tomorrow, tomorrowFirstStep: first), false)
        }
    }

    /// Resolves an exact identity, including overdue one-offs and postponed work on an earlier planned date.
    public func occurrence(id: String) throws -> DailyOccurrence {
        try transaction { state in (try self.requireOccurrence(id, state: state), false) }
    }

    /// Management agenda: a one-off remains visible at its original identity regardless
    /// of due date. Recurring plans show the requested window plus saved pending earlier
    /// steps (for example a postponed occurrence). Earlier steps completed within this
    /// window stay visible for Undo; unrecorded missed days are not added.
    public func managedOccurrences(habitID: UUID, startingOn date: Date = Date(), days: Int = 7) throws -> [DailyOccurrence] {
        try checkDate(date)
        guard (1...366).contains(days),
              let end = localDay.calendar.date(byAdding: .day, value: days - 1, to: date), validDate(end) else {
            throw RoutineStoreError.invalidHistoryRange
        }
        let keys = try localDay.keys(days: days, endingOn: end)
        return try transaction { state in
            let habit = state.habits[try self.index(of: habitID, in: state)]
            var plannedKeys: Set<String>
            if case .once(let key) = habit.revisions[0].definition.recurrence { plannedKeys = [key] }
            else {
                plannedKeys = Set(keys)
                plannedKeys.formUnion(state.records.filter {
                    guard $0.habitID == habitID, $0.dayKey < keys[0] else { return false }
                    guard let completedAt = $0.resolvedAt else { return true }
                    return (keys[0]...keys[keys.count - 1]).contains(self.localDay.key(for: completedAt))
                }.map(\.dayKey))
            }
            return (try plannedKeys.sorted().compactMap { try self.occurrence(for: habit, on: $0, state: state) }, false)
        }
    }

    /// First result wins. Supplying a revision additionally rejects stale surfaces.
    public func complete(occurrenceID: String, outcome: CompletionOutcome = .full,
                         source: CompletionSource? = nil, expectedRevision: String? = nil,
                         now: Date = Date()) throws {
        try checkDate(now)
        try transaction { state in
            let previous = try self.requireOccurrence(occurrenceID, state: state)
            if let expectedRevision, previous.revision != expectedRevision { throw RoutineStoreError.staleAction }
            guard !previous.isResolved else { return ((), false) }
            let action: OccurrenceAction = outcome == .skipped ? .skip : .complete(outcome)
            var next = previous
            try self.apply(action, to: &next, source: source, now: now)
            self.save(next, in: &state, now: now)
            return ((), true)
        }
    }

    /// A configured control always resolves this habit's original planned day at invocation.
    /// Never advance to a carryover or another habit after a repeated completion.
    @discardableResult
    public func completeCurrentHabit(habitID: UUID, now: Date = Date()) throws -> DailyOccurrence {
        try checkDate(now)
        return try transaction { state in
            let habit = state.habits[try self.index(of: habitID, in: state)]
            guard habit.archivedAt == nil else { throw HabitControlError.archived }
            guard var current = try self.occurrence(for: habit, on: self.localDay.key(for: now), state: state)
            else { throw HabitControlError.noCurrentOccurrence }
            // Preserve both full and light results, timestamps, source and revision on retries.
            if current.isCompleted { return (current, false) }
            guard current.outcome != .skipped else { throw HabitControlError.skipped }
            guard current.isReady(at: now, calendar: self.localDay.calendar)
            else { throw HabitControlError.notReady }
            try self.apply(.complete(.full), to: &current, source: .appIntent, now: now)
            current.mutationID = UUID()
            self.save(current, in: &state, now: now, stampRevision: false)
            return (current, true)
        }
    }

    public func reopen(occurrenceID: String, expectedRevision: String? = nil, now: Date = Date()) throws {
        try checkDate(now)
        try transaction { state in
            let (habitID, _) = try self.parse(occurrenceID: occurrenceID)
            _ = try self.index(of: habitID, in: state)
            var occurrence = try state.records.first(where: { $0.id == occurrenceID })
                ?? self.requireOccurrence(occurrenceID, state: state)
            if let expectedRevision, occurrence.revision != expectedRevision { throw RoutineStoreError.staleAction }
            guard occurrence.isResolved else { return ((), false) }
            try self.apply(.reopen, to: &occurrence, source: nil, now: now)
            self.save(occurrence, in: &state, now: now)
            return ((), true)
        }
    }

    /// Compare and mutate while holding the file lock. Tokens are valid for exactly one resulting version.
    public func perform(_ action: OccurrenceAction, on snapshot: DailyOccurrence,
                        source: CompletionSource = .app, requiringAgenda: Bool = false,
                        now: Date = Date()) throws -> OccurrenceUndo {
        try checkDate(now)
        return try transaction { state in
            let previous = try self.requireOccurrence(snapshot.id, state: state)
            guard previous == snapshot else { throw RoutineStoreError.staleAction }
            if requiringAgenda {
                guard try self.agenda(at: now, state: state).occurrences.contains(where: { $0.id == snapshot.id })
                else { throw RoutineStoreError.staleAction }
            }
            var next = previous
            try self.apply(action, to: &next, source: source, now: now)
            guard next != previous else { throw RoutineStoreError.staleAction }
            next.mutationID = UUID()
            self.save(next, in: &state, now: now, stampRevision: false)
            return (OccurrenceUndo(previous: previous, resultingRevision: next.revision), true)
        }
    }

    public func undo(_ token: OccurrenceUndo, now: Date = Date()) throws {
        try checkDate(now)
        try transaction { state in
            let current = try self.requireOccurrence(token.previous.id, state: state)
            guard current.revision == token.resultingRevision else { throw RoutineStoreError.staleAction }
            self.save(token.previous, in: &state, now: now)
            return ((), true)
        }
    }

    private func apply(_ action: OccurrenceAction, to occurrence: inout DailyOccurrence,
                       source: CompletionSource?, now: Date) throws {
        if case .reopen = action {
            occurrence.outcome = nil
            occurrence.completedAt = nil
            occurrence.skippedAt = nil
            occurrence.completionSource = nil
            return
        }
        guard !occurrence.isResolved else { throw RoutineStoreError.completedOccurrence }
        guard occurrence.canComplete(at: now, calendar: localDay.calendar) else { throw RoutineStoreError.futureCompletion }
        switch action {
        case .complete(let outcome):
            guard outcome != .skipped else { throw RoutineStoreError.invalidOccurrence }
            if outcome == .light && occurrence.lightTarget == nil { throw RoutineStoreError.lightTargetUnavailable }
            occurrence.outcome = outcome
            occurrence.completedAt = now
            occurrence.completionSource = source
        case .skip:
            occurrence.outcome = .skipped
            occurrence.skippedAt = now
            occurrence.completionSource = source
        case .later(let until, let zone):
            guard until > now else { throw RoutineStoreError.invalidDueDate }
            let due = OccurrenceDue.timed(at: until, timeZoneIdentifier: zone)
            try validateDue(due, plannedDay: occurrence.dayKey)
            occurrence.due = due
            occurrence.deferredUntil = until
        case .reopen: break
        }
    }

    /// A local civil-day choice; no template targets are changed or generated.
    public func setLightDay(_ enabled: Bool, matching snapshot: DailySummary, now: Date = Date()) throws {
        try checkDate(now)
        let key = localDay.key(for: now)
        try transaction { state in
            let current = try self.summary(dayKey: key, state: state)
            guard snapshot.dayKey == key, current.modeRevision == snapshot.modeRevision else {
                throw RoutineStoreError.staleAction
            }
            guard current.isLightDay != enabled else { return ((), false) }
            var modes = state.dayModes ?? []
            modes.removeAll { $0.dayKey == key }
            modes.append(DayMode(dayKey: key, isLightDay: enabled, revision: UUID()))
            state.dayModes = modes
            return ((), true)
        }
    }

    /// Today's original plan plus explicitly saved carryovers and overdue one-offs.
    /// Past unrecorded recurring days are never manufactured as a backlog.
    public func agenda(at now: Date = Date()) throws -> DailyAgenda {
        try checkDate(now)
        return try transaction { state in (try self.agenda(at: now, state: state), false) }
    }

    private func agenda(at now: Date, state: StoreDocument) throws -> DailyAgenda {
        let key = localDay.key(for: now)
        let today = try summary(dayKey: key, state: state)
        var ids = Set(today.occurrences.map(\.id))
        var items = today.occurrences
        var candidates = state.records.filter { $0.dayKey < key }.map(\.id)
        for habit in state.habits {
            if case .once(let planned) = habit.revisions[0].definition.recurrence, planned < key {
                candidates.append("\(habit.id.uuidString)|\(planned)")
            }
        }
        for id in Set(candidates).sorted() where !ids.contains(id) {
            let (habitID, planned) = try parse(occurrenceID: id)
            let habit = state.habits[try index(of: habitID, in: state)]
            guard let item = try occurrence(for: habit, on: planned, state: state),
                  !item.isResolved || item.resolvedAt.map({ localDay.key(for: $0) == key }) == true else { continue }
            items.append(item)
            ids.insert(id)
        }
        return DailyAgenda(summary: today, occurrences: DailyAgenda.ordered(items, calendar: localDay.calendar))
    }

    /// Due-only changes may postpone overdue work. ID, targets and planned day are retained.
    public func rescheduleOccurrence(occurrenceID: String, due: OccurrenceDue, now: Date = Date()) throws {
        try mutatePending(occurrenceID, now: now) { occurrence, _ in
            try validateDue(due, plannedDay: occurrence.dayKey)
            occurrence.due = due
            occurrence.deferredUntil = nil
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
            occurrence.deferredUntil = nil
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
            guard !occurrence.isResolved else { throw RoutineStoreError.completedOccurrence }
            let index = try self.index(of: occurrence.habitID, in: state)
            let before = occurrence
            try body(&occurrence, max(self.localDay.key(for: now), state.habits[index].mutationDayKey))
            guard occurrence != before else { return ((), false) }
            self.save(occurrence, in: &state, now: now)
            return ((), true)
        }
    }

    private func save(_ snapshot: DailyOccurrence, in state: inout StoreDocument, now: Date, stampRevision: Bool = true) {
        var occurrence = snapshot
        if stampRevision { occurrence.mutationID = UUID() }
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
        if let saved, saved.isResolved { return saved }
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
        let mode = state.dayModes?.first { $0.dayKey == dayKey }
        return DailySummary(dayKey: dayKey, occurrences: result, isLightDay: mode?.isLightDay ?? false,
                            modeRevision: mode?.revision)
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

        var (state, legacyBytes, sourceVersion) = try readState()
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
                if let legacyBytes, let sourceVersion { try preserveLegacyBytes(legacyBytes, version: sourceVersion) }
                try saveSnapshot(data, fileURL)
            } catch { throw RoutineStoreError.fileAccess("Save data: \(error.localizedDescription)") }
        }
        return result
    }

    private func preserveLegacyBytes(_ original: Data, version: Int) throws {
        let migrationBackupURL = migrationBackupURL(from: version)
        if !FileManager.default.fileExists(atPath: migrationBackupURL.path) {
            try FileManager.default.copyItem(at: fileURL, to: migrationBackupURL)
            try configureFileProtection(at: migrationBackupURL)
        }
        guard try Data(contentsOf: migrationBackupURL) == original else {
            throw RoutineStoreError.fileAccess("Existing migration backup differs; preserve both files for recovery")
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

    private func readState() throws -> (StoreDocument, Data?, Int?) {
        let data: Data
        do { data = try Data(contentsOf: fileURL) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return (StoreDocument(), nil, nil) }
        catch { throw RoutineStoreError.fileAccess("Read data: \(error.localizedDescription)") }
        let decoded = try StoreDocument.decode(data)
        return (decoded.document, decoded.sourceVersion != nil ? data : nil, decoded.sourceVersion)
    }
}

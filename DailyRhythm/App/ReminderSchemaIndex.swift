#if DAILY_RHYTHM_SCHEMA_SPIKE && compiler(>=6.4)
import AppIntents
import CoreSpotlight
import DailyRhythmCore
import Foundation
import OSLog

/// The opt-in reminder catalog must be indexed for Siri's semantic entity lookup.
/// Persistence is authoritative; an indexing failure must never undo a saved task
/// or report creation failure after commit (which could invite duplicate retries).
@available(iOS 27.0, *)
actor ReminderSchemaIndex {
    static let shared = ReminderSchemaIndex()
    private let logger = Logger(subsystem: "com.lumetechllc.DailyRhythm", category: "ReminderSchemaIndex")
    private var isRefreshing = false
    private var needsRefresh = false
    private var erasing = false

    func refreshAfterMutation() async {
        guard !erasing else { return }
        needsRefresh = true
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        // A mutation during an index write requests another fresh snapshot. Never
        // let an older refresh finish after a newer one and restore stale fields.
        while needsRefresh {
            needsRefresh = false
            do { try await refresh() }
            catch { logger.error("Reminder indexing failed; saved tasks are unchanged.") }
        }
    }

    func clearForErasure() async throws {
        erasing = true
        defer { erasing = false }
        needsRefresh = false
        while isRefreshing { try await Task.sleep(for: .milliseconds(25)) }
        try await CSSearchableIndex(name: "DailyRhythmReminderSchemas").deleteAllSearchableItems()
    }

    private func refresh() async throws {
        let store = try SharedRoutineStore.makeStore()
        let habits = try store.habits(includeArchived: true).filter { !$0.recurrence.isRecurring }
        let entities = try habits.filter { $0.archivedAt == nil }.flatMap { habit in
            try store.managedOccurrences(habitID: habit.id).map { RhythmSchemaReminder($0, createdAt: habit.createdAt) }
        }
        let archivedIDs = habits.filter { $0.archivedAt != nil }.compactMap { habit -> String? in
            guard case .once(let day) = habit.revisions[0].definition.recurrence else { return nil }
            return "\(habit.id.uuidString)|\(day)"
        }
        // Keep the non-Sendable framework instance local to this refresh.
        let index = CSSearchableIndex(name: "DailyRhythmReminderSchemas")
        try await index.indexAppEntities(entities)
        if !archivedIDs.isEmpty {
            try await index.deleteAppEntities(identifiedBy: archivedIDs, ofType: RhythmSchemaReminder.self)
        }
    }
}
#endif

import DailyRhythmCore
import Combine
import Foundation
import SwiftUI
import WidgetKit

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var today: DailySummary?
    @Published private(set) var habits: [Habit] = []
    @Published private(set) var review: RhythmReview?
    @Published private(set) var loadError: String?
    @Published var operationError: String?
    @Published private(set) var lastUndo: OccurrenceUndo?
    @Published private(set) var agenda: DailyAgenda?
    @Published private(set) var completionFeedback = 0
    @Published private(set) var refreshedAt = Date()
    @Published private(set) var dataGeneration = RoutineDataLifecycle.initialGeneration

    var activeHabits: [Habit] { habits.filter { $0.archivedAt == nil } }
    var archivedHabits: [Habit] { habits.filter { $0.archivedAt != nil } }

    var nextOccurrence: DailyOccurrence? {
        agenda?.next(at: refreshedAt)
    }

    func refresh() {
        do {
            let store = try SharedRoutineStore.makeStore()
            let now = Date()
            let snapshot = try store.review(at: now)
            dataGeneration = try store.validateAccess()
            review = snapshot
            today = snapshot.agenda.summary
            agenda = snapshot.agenda
            habits = snapshot.habits
            refreshedAt = now
            loadError = nil
        } catch {
            // Keep the last successful view available. A read error must never reset data.
            loadError = error.localizedDescription
        }
        Task { await NotificationSettingsModel.shared.refresh() }
    }

    @discardableResult
    func addHabit(_ definition: HabitDefinition, expectedGeneration: UUID) -> Bool {
        performMutation {
            _ = try SharedRoutineStore.makeStore(expectedGeneration: expectedGeneration).addHabit(definition)
        }
    }

    func clearForErasure() {
        today = nil; habits = []; review = nil; agenda = nil
        lastUndo = nil; operationError = nil; loadError = nil
        completionFeedback = 0
    }

    func createInitialRoutine(_ draft: OnboardingDraft) -> Bool {
        performMutation { _ = try SharedRoutineStore.makeStore().createInitialRoutine(draft) }
    }

    func complete(_ occurrence: DailyOccurrence, outcome: CompletionOutcome, requiringToday: Bool = true) {
        act(.complete(outcome), on: occurrence, requiringToday: requiringToday)
    }

    func skip(_ occurrence: DailyOccurrence) { act(.skip, on: occurrence) }

    func later(_ occurrence: DailyOccurrence) {
        act(.later(until: Date().addingTimeInterval(3600), timeZoneIdentifier: TimeZone.current.identifier), on: occurrence)
    }

    func reopen(_ occurrence: DailyOccurrence) { act(.reopen, on: occurrence, requiringToday: false) }

    func undoLastAction() {
        guard let token = lastUndo else { return }
        _ = performMutation { try SharedRoutineStore.makeStore().undo(token) }
        lastUndo = nil
    }

    func setLightDay(_ enabled: Bool) {
        guard let today else { return }
        _ = performMutation { try SharedRoutineStore.makeStore().setLightDay(enabled, matching: today) }
    }

    private func act(_ action: OccurrenceAction, on occurrence: DailyOccurrence, requiringToday: Bool = true) {
        if performMutation({
            lastUndo = try SharedRoutineStore.makeStore().perform(action, on: occurrence,
                                                                  requiringAgenda: requiringToday)
        }) { completionFeedback += 1 }
    }

    func archive(_ habit: Habit) {
        _ = performMutation {
            try SharedRoutineStore.makeStore().archive(habitID: habit.id)
        }
    }

    func restore(_ habit: Habit) {
        _ = performMutation { try SharedRoutineStore.makeStore().restore(habitID: habit.id) }
    }

    func editSchedule(habitID: UUID, definition: HabitDefinition, effectiveDayKey: String) -> Bool {
        performMutation {
            try SharedRoutineStore.makeStore().editHabit(habitID: habitID, definition: definition,
                                                        effectiveDayKey: effectiveDayKey)
        }
    }

    func editOccurrence(_ occurrence: DailyOccurrence, draft: HabitFormDraft, dueOnly: Bool) -> Bool {
        performMutation {
            let store = try SharedRoutineStore.makeStore()
            let due = try draft.due()
            if dueOnly { try store.rescheduleOccurrence(occurrenceID: occurrence.id, due: due) }
            else {
                let definition = try draft.definition()
                try store.updateOccurrence(occurrenceID: occurrence.id, normalTarget: definition.normalTarget,
                                           lightTarget: definition.lightTarget, durationMinutes: definition.durationMinutes,
                                           due: due)
            }
        }
    }

    private func performMutation(_ action: () throws -> Void) -> Bool {
        do {
            try action()
            operationError = nil
            RhythmSurfaceRefresh.reload()
            #if DAILY_RHYTHM_SCHEMA_SPIKE && compiler(>=6.4)
            if #available(iOS 27.0, *) { Task { await ReminderSchemaIndex.shared.refreshAfterMutation() } }
            #endif
            refresh()
            return true
        } catch {
            operationError = error.localizedDescription
            refresh()
            return false
        }
    }
}

extension DayPart {
    var displayName: String {
        switch self {
        case .morning: "Morning"
        case .afternoon: "Afternoon"
        case .evening: "Evening"
        }
    }

    var symbol: String {
        switch self {
        case .morning: "sunrise"
        case .afternoon: "sun.max"
        case .evening: "moon.stars"
        }
    }
}

enum RhythmDates {
    static func planLabel(_ definition: HabitDefinition) -> String {
        let recurrence: String
        switch definition.recurrence {
        case .weekly(let weekdays): recurrence = scheduleLabel(weekdays)
        case .once(let key): recurrence = "Once · \(dayLabel(key))"
        }
        guard let time = definition.dueTime else { return recurrence + " · Date only" }
        return recurrence + String(format: " · %02d:%02d · ", time.hour, time.minute) + time.timeZoneIdentifier
    }

    static func dueLabel(_ due: OccurrenceDue) -> String {
        switch due {
        case .dateOnly(let key): return "Due \(dayLabel(key)) · Date only"
        case .timed(let at, let zone):
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_GB")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = TimeZone(identifier: zone)
            formatter.dateFormat = "d MMM yyyy, HH:mm"
            return "Due \(formatter.string(from: at)) · \(zone)"
        }
    }

    static func todayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "EEEE, d MMMM"
        return formatter.string(from: date)
    }

    static func dayLabel(_ dayKey: String) -> String {
        guard let date = LocalDay.utc.date(for: dayKey) else { return dayKey }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, d MMM yyyy"
        return formatter.string(from: date)
    }

    static let weekdays: [(value: Int, label: String)] = [
        (2, "Monday"), (3, "Tuesday"), (4, "Wednesday"), (5, "Thursday"),
        (6, "Friday"), (7, "Saturday"), (1, "Sunday")
    ]

    static func scheduleLabel(_ weekdays: Set<Int>) -> String {
        if weekdays == Set(1...7) { return "Every day" }
        if weekdays == Set(2...6) { return "Weekdays" }
        if weekdays == Set([1, 7]) { return "Weekends" }
        return self.weekdays.filter { weekdays.contains($0.value) }
            .map { String($0.label.prefix(3)) }.joined(separator: ", ")
    }
}

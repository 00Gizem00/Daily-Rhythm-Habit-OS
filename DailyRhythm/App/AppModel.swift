import DailyRhythmCore
import Combine
import Foundation
import SwiftUI
import WidgetKit

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var today: DailySummary?
    @Published private(set) var habits: [Habit] = []
    @Published private(set) var history: [DailySummary] = []
    @Published private(set) var loadError: String?
    @Published var operationError: String?
    @Published private(set) var lastUndo: OccurrenceUndo?
    @Published private(set) var agenda: DailyAgenda?
    @Published private(set) var completionFeedback = 0
    @Published private(set) var refreshedAt = Date()

    var activeHabits: [Habit] { habits.filter { $0.archivedAt == nil } }
    var archivedHabits: [Habit] { habits.filter { $0.archivedAt != nil } }

    var nextOccurrence: DailyOccurrence? {
        agenda?.next(at: refreshedAt)
    }

    func refresh() {
        do {
            let store = try SharedRoutineStore.makeStore()
            let now = Date()
            let newAgenda = try store.agenda(at: now)
            let newToday = newAgenda.summary
            let newHabits = try store.habits(includeArchived: true)
            let newHistory = try store.history(days: 7, endingOn: now)
            today = newToday
            agenda = newAgenda
            habits = newHabits
            history = newHistory
            refreshedAt = now
            loadError = nil
        } catch {
            // Keep the last successful view available. A read error must never reset data.
            loadError = error.localizedDescription
        }
    }

    @discardableResult
    func addHabit(_ definition: HabitDefinition) -> Bool {
        performMutation {
            _ = try SharedRoutineStore.makeStore().addHabit(definition)
        }
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
            WidgetCenter.shared.reloadAllTimelines()
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
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dayKey) else { return dayKey }
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

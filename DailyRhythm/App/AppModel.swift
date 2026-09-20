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
    @Published private(set) var lastCompletedID: String?
    @Published private(set) var completionFeedback = 0
    @Published private(set) var refreshedAt = Date()

    var activeHabits: [Habit] { habits.filter { $0.archivedAt == nil } }
    var archivedHabits: [Habit] { habits.filter { $0.archivedAt != nil } }

    var nextOccurrence: DailyOccurrence? {
        today?.occurrences.first { $0.outcome == nil }
    }

    func refresh() {
        do {
            let store = try SharedRoutineStore.makeStore()
            let now = Date()
            let newToday = try store.summary(for: now)
            let newHabits = try store.habits(includeArchived: true)
            let newHistory = try store.history(days: 7, endingOn: now)
            today = newToday
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
    func addHabit(title: String, normalTarget: String, lightTarget: String?, dayPart: DayPart, weekdays: Set<Int>) -> Bool {
        performMutation {
            let store = try SharedRoutineStore.makeStore()
            _ = try store.addHabit(
                title: title,
                normalTarget: normalTarget,
                lightTarget: lightTarget,
                dayPart: dayPart,
                weekdays: weekdays
            )
        }
    }

    func complete(_ occurrence: DailyOccurrence, outcome: CompletionOutcome) {
        guard occurrence.outcome == nil else { return }
        if performMutation({
            let store = try SharedRoutineStore.makeStore()
            let now = Date()
            guard try store.summary(for: now).dayKey == occurrence.dayKey else {
                refresh()
                throw AppActionError.dayChanged
            }
            try store.complete(occurrenceID: occurrence.id, outcome: outcome, source: .app, now: now)
        }) {
            lastCompletedID = occurrence.id
            completionFeedback += 1
        }
    }

    func reopen(_ occurrenceID: String) {
        if performMutation({
            try SharedRoutineStore.makeStore().reopen(occurrenceID: occurrenceID)
        }), lastCompletedID == occurrenceID {
            lastCompletedID = nil
        }
    }

    func archive(_ habit: Habit) {
        _ = performMutation {
            try SharedRoutineStore.makeStore().archive(habitID: habit.id)
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
            return false
        }
    }
}

private enum AppActionError: LocalizedError {
    case dayChanged

    var errorDescription: String? {
        "A new day has started. Today's steps have been refreshed; choose the step you want to record."
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
        formatter.dateFormat = "EEE, d MMM"
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

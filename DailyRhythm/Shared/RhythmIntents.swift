import AppIntents
import Foundation
import WidgetKit
import DailyRhythmCore

enum HabitTimeOfDay: String, AppEnum {
    case morning, afternoon, evening

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Time of Day")
    static let caseDisplayRepresentations: [HabitTimeOfDay: DisplayRepresentation] = [
        .morning: "Morning", .afternoon: "Afternoon", .evening: "Evening"
    ]

    var coreValue: DayPart {
        switch self {
        case .morning: .morning
        case .afternoon: .afternoon
        case .evening: .evening
        }
    }
}

enum HabitRepeatPattern: String, AppEnum {
    case everyDay, weekdays, weekends

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Repeat")
    static let caseDisplayRepresentations: [HabitRepeatPattern: DisplayRepresentation] = [
        .everyDay: "Every Day", .weekdays: "Weekdays", .weekends: "Weekends"
    ]

    var calendarWeekdays: Set<Int> {
        switch self {
        case .everyDay: Set(1...7)
        case .weekdays: Set(2...6)
        case .weekends: [1, 7]
        }
    }
}

/// Ordinary App Intents work through Siri Shortcuts; these are not Siri AI App Schemas.
struct CreateHabitIntent: AppIntent {
    static let title: LocalizedStringResource = "Create Habit"
    static let description = IntentDescription("Create a recurring habit in Daily Rhythm.")
    static let openAppWhenRun = false

    @Parameter(title: "Habit Name") var habitName: String
    @Parameter(title: "Target", default: "One step") var target: String
    @Parameter(title: "Time of Day", default: .morning) var timeOfDay: HabitTimeOfDay
    @Parameter(title: "Repeat", default: .everyDay) var repeatPattern: HabitRepeatPattern

    static var parameterSummary: some ParameterSummary {
        Summary("Create \(\.$habitName) in Daily Rhythm") {
            \.$target
            \.$timeOfDay
            \.$repeatPattern
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = try SharedRoutineStore.makeStore()
        _ = try store.addHabit(
            title: habitName,
            normalTarget: target,
            dayPart: timeOfDay.coreValue,
            weekdays: repeatPattern.calendarWeekdays
        )
        WidgetCenter.shared.reloadTimelines(ofKind: SharedRoutineStore.widgetKind)
        return .result(dialog: "Your habit is ready in Daily Rhythm.")
    }
}

struct CompleteOccurrenceIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete Daily Step"
    static let description = IntentDescription("Record the selected step for its scheduled day.")
    static let openAppWhenRun = false

    @Parameter(title: "Daily Step") var occurrence: RhythmOccurrenceEntity
    @Parameter(title: "Use Small Step", default: false) var useSmallStep: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Complete \(\.$occurrence)") {
            \.$useSmallStep
        }
    }

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try completeStep(occurrence: occurrence, useSmallStep: useSmallStep, source: .appIntent)
        return .result(dialog: "Your step is recorded.")
    }
}

/// A separate, undiscoverable intent identifies a widget action without guessing its
/// origin from the process that iOS chooses to execute it in.
struct CompleteWidgetOccurrenceIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete Widget Step"
    static let isDiscoverable = false
    static let openAppWhenRun = false

    @Parameter(title: "Daily Step") var occurrence: RhythmOccurrenceEntity
    @Parameter(title: "Use Small Step", default: false) var useSmallStep: Bool

    init() {}

    init(occurrence: DailyOccurrence, useSmallStep: Bool = false) {
        self.occurrence = RhythmOccurrenceEntity(occurrence)
        self.useSmallStep = useSmallStep
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try completeStep(occurrence: occurrence, useSmallStep: useSmallStep, source: .widget)
        return .result(dialog: "Your step is recorded.")
    }
}

private func completeStep(occurrence: RhythmOccurrenceEntity, useSmallStep: Bool, source: CompletionSource) throws {
    let store = try SharedRoutineStore.makeStore()
    let now = Date()
    let today = try store.summary(for: now)
    guard today.dayKey == occurrence.dayKey,
          let current = today.occurrences.first(where: { $0.id == occurrence.id }) else {
        WidgetCenter.shared.reloadTimelines(ofKind: SharedRoutineStore.widgetKind)
        throw SharedStoreError.staleOccurrence
    }
    guard !useSmallStep || current.lightTarget != nil else {
        throw SharedStoreError.noSmallStep
    }
    try store.complete(
        occurrenceID: current.id,
        outcome: useSmallStep ? .light : .full,
        source: source,
        now: now
    )
    WidgetCenter.shared.reloadTimelines(ofKind: SharedRoutineStore.widgetKind)
}

struct ReopenOccurrenceIntent: AppIntent {
    static let title: LocalizedStringResource = "Undo Daily Step"
    static let description = IntentDescription("Remove today's completion so you can record it again.")
    static let openAppWhenRun = false

    @Parameter(title: "Daily Step") var occurrence: RhythmOccurrenceEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Undo completion of \(\.$occurrence)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = try SharedRoutineStore.makeStore()
        let today = try store.summary()
        guard today.dayKey == occurrence.dayKey,
              today.occurrences.contains(where: { $0.id == occurrence.id }) else {
            WidgetCenter.shared.reloadTimelines(ofKind: SharedRoutineStore.widgetKind)
            throw SharedStoreError.staleOccurrence
        }
        try store.reopen(occurrenceID: occurrence.id)
        WidgetCenter.shared.reloadTimelines(ofKind: SharedRoutineStore.widgetKind)
        return .result(dialog: "Your step is ready to record again.")
    }
}

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
        _ = try store.diagnoseAction(surface: .appIntent) { try store.addHabit(
            title: habitName,
            normalTarget: target,
            dayPart: timeOfDay.coreValue,
            weekdays: repeatPattern.calendarWeekdays
        ) }
        RhythmSurfaceRefresh.reload()
        await RhythmNotifications.reconcileAfterMutation()
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
        await RhythmNotifications.reconcileAfterMutation()
        return .result(dialog: "Your step is recorded.")
    }
}

/// A separate, undiscoverable intent identifies a widget action without guessing its
/// origin from the process that iOS chooses to execute it in.
struct CompleteWidgetOccurrenceIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete Widget Step"
    static let isDiscoverable = false
    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @Parameter(title: "Daily Step") var occurrence: RhythmOccurrenceEntity
    @Parameter(title: "Use Small Step", default: false) var useSmallStep: Bool

    // Explicit parameter survives AppEntity re-resolution on execution.
    @Parameter(title: "Snapshot Revision") var snapshotRevision: String?

    init() {}

    init(occurrence: DailyOccurrence, useSmallStep: Bool = false) {
        self.occurrence = RhythmOccurrenceEntity(occurrence)
        self.useSmallStep = useSmallStep
        self.snapshotRevision = occurrence.revision
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try completeStep(occurrence: occurrence, useSmallStep: useSmallStep, source: .widget, expectedRevision: snapshotRevision)
        await RhythmNotifications.reconcileAfterMutation()
        return .result(dialog: "Your step is recorded.")
    }
}

private func completeStep(occurrence: RhythmOccurrenceEntity, useSmallStep: Bool, source: CompletionSource, expectedRevision: String? = nil) throws {
    defer { RhythmSurfaceRefresh.reload() }
    let store = try SharedRoutineStore.makeStore()
    try store.diagnoseAction(surface: source == .widget ? .widget : .appIntent) {
        let now = Date()
        let agenda = try store.agenda(at: now)
        guard let current = agenda.occurrences.first(where: { $0.id == occurrence.id }) else {
            throw SharedStoreError.staleOccurrence
        }
        if source == .widget {
            guard let expectedRevision, expectedRevision == current.revision, current.isReady(at: now) else {
                throw SharedStoreError.staleOccurrence
            }
        }
        guard current.outcome != .skipped else { throw RoutineStoreError.completedOccurrence }
        guard !useSmallStep || current.lightTarget != nil else {
            throw SharedStoreError.noSmallStep
        }
        if source == .widget {
            // Recheck the entire shown snapshot and agenda membership under the write lock.
            _ = try store.perform(.complete(useSmallStep ? .light : .full), on: current,
                                  source: .widget, requiringAgenda: true, now: now)
        } else {
            try store.complete(occurrenceID: current.id, outcome: useSmallStep ? .light : .full,
                               source: source, expectedRevision: current.revision, now: now)
        }
    }
}

struct ReopenOccurrenceIntent: AppIntent {
    static let title: LocalizedStringResource = "Reopen Daily Step"
    static let description = IntentDescription("Reopen a recorded or skipped step so you can record it again.")
    static let openAppWhenRun = false

    @Parameter(title: "Daily Step") var occurrence: RhythmOccurrenceEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Reopen \(\.$occurrence)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = try SharedRoutineStore.makeStore()
        try store.diagnoseAction(surface: .appIntent) {
            let agenda = try store.agenda()
            guard let current = agenda.occurrences.first(where: { $0.id == occurrence.id }) else {
                RhythmSurfaceRefresh.reload()
                throw SharedStoreError.staleOccurrence
            }
            try store.reopen(occurrenceID: occurrence.id, expectedRevision: current.revision)
        }
        RhythmSurfaceRefresh.reload()
        await RhythmNotifications.reconcileAfterMutation()
        return .result(dialog: "Your step is ready to record again.")
    }
}

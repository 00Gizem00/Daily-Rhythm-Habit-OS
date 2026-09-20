import AppIntents
import Foundation
import WidgetKit
import DailyRhythmCore
#if !WIDGET_EXTENSION
import SwiftUI

@MainActor
final class RhythmNavigation: ObservableObject {
    static let shared = RhythmNavigation()
    @Published var selectedTab = 0
    @Published var todayRoute = UUID()

    func openToday() {
        selectedTab = 0
        todayRoute = UUID()
    }
}
#endif

enum RhythmScreen: String, AppEnum {
    case today
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Daily Rhythm Screen")
    static let caseDisplayRepresentations: [RhythmScreen: DisplayRepresentation] = [.today: "Today"]
}

/// In both target memberships; OpenIntent is executed by the foreground app.
struct OpenTodayIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Today"
    @Parameter(title: "Screen", default: .today) var target: RhythmScreen

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        RhythmNavigation.shared.openToday()
        #endif
        return .result()
    }
}

/// A persistent habit choice, deliberately distinct from a dated occurrence entity.
struct RhythmHabitEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Habit")
    static let defaultQuery = RhythmHabitQuery()
    let id: UUID
    let title: String
    let detail: String

    init(_ habit: Habit) {
        id = habit.id
        title = habit.title
        let days = habit.weekdays.sorted().map { ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][$0 - 1] }.joined(separator: ", ")
        // A stable suffix distinguishes even identical names, targets and schedules.
        detail = (habit.archivedAt != nil ? "Archived · " : "")
            + "\(habit.normalTarget) · \(habit.dayPart.rawValue.capitalized) · \(days) · \(habit.id.uuidString.prefix(8))"
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(detail)")
    }
}

struct RhythmHabitQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [RhythmHabitEntity] {
        // Retain archived identity so execution can report the specific problem.
        let habits = try SharedRoutineStore.makeStore().habits(includeArchived: true)
        let byID = Dictionary(uniqueKeysWithValues: habits.map { ($0.id, $0) })
        return identifiers.compactMap { byID[$0].map(RhythmHabitEntity.init) }
    }

    func suggestedEntities() async throws -> [RhythmHabitEntity] {
        try SharedRoutineStore.makeStore().habits().filter { $0.recurrence.isRecurring }.map(RhythmHabitEntity.init)
    }

    func entities(matching string: String) async throws -> [RhythmHabitEntity] {
        try await suggestedEntities().filter { $0.title.localizedStandardContains(string) }
    }
}

struct ChooseControlHabitIntent: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Choose a Habit"
    @Parameter(title: "Habit") var habit: RhythmHabitEntity?

    static var parameterSummary: some ParameterSummary { Summary("Complete today's full step for \(\.$habit)") }
}

struct CompleteControlHabitIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete Configured Habit"
    static let isDiscoverable = false
    static let openAppWhenRun = false
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    @Parameter(title: "Habit") var habit: RhythmHabitEntity?

    init() {}
    init(habit: RhythmHabitEntity?) { self.habit = habit }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let habit else { throw ControlConfigurationError.chooseHabit }
        defer { RhythmSurfaceRefresh.reload() }
        let saved = try SharedRoutineStore.makeStore().completeCurrentHabit(habitID: habit.id)
        let outcome = saved.outcome == .light ? "light" : "full"
        return .result(dialog: "\(saved.title): today's \(outcome) step is recorded.")
    }
}

private enum ControlConfigurationError: LocalizedError {
    case chooseHabit
    var errorDescription: String? { "Choose a habit in this control's settings before using it." }
}

enum RhythmSurfaceRefresh {
    static let habitControlKind = "DailyRhythmCompleteHabit"
    static let todayURL = URL(string: "daily-rhythm://today")!

    static func reload() {
        WidgetCenter.shared.reloadTimelines(ofKind: SharedRoutineStore.widgetKind)
        ControlCenter.shared.reloadControls(ofKind: habitControlKind)
    }
}

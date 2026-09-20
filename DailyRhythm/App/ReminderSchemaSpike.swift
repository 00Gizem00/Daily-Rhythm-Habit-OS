// Opt in only for the #10 capability-validation build. The normal iOS 18 product
// keeps ordinary App Shortcuts until the schema/device gate has actual evidence.
#if DAILY_RHYTHM_SCHEMA_SPIKE && compiler(>=6.4)
import AppIntents
import DailyRhythmCore
import Foundation
import GeoToolbox
import WidgetKit

@available(iOS 27.0, *)
@AppEnum(schema: .reminders.listType)
enum RhythmReminderListType: String {
    case standard
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [.standard: "Standard"]
}

@available(iOS 27.0, *)
@AppEntity(schema: .reminders.list)
struct RhythmReminderList {
    static let defaultQuery = RhythmReminderListQuery()
    let id: String
    var name: String
    var type: RhythmReminderListType
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }

    init() {
        id = "daily-rhythm-one-offs"
        name = "Daily Rhythm"
        type = .standard
    }
    static var appList: Self { Self() }
}

@available(iOS 27.0, *)
struct RhythmReminderListQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [RhythmReminderList] {
        identifiers.contains(RhythmReminderList.appList.id) ? [.appList] : []
    }
    func entities(matching string: String) async throws -> [RhythmReminderList] {
        RhythmReminderList.appList.name.localizedStandardContains(string) ? [.appList] : []
    }
    func suggestedEntities() async throws -> [RhythmReminderList] { [.appList] }
}

// Required schema vocabulary. This spike supports neither sections nor location
// triggers: queries return no entities, and supplied values are explicitly refused.
@available(iOS 27.0, *)
@AppEntity(schema: .reminders.section)
struct RhythmReminderSection {
    static let defaultQuery = RhythmReminderSectionQuery()
    let id: String
    var name: String
    var list: RhythmReminderList
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

@available(iOS 27.0, *)
struct RhythmReminderSectionQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [RhythmReminderSection] { [] }
    func entities(matching string: String) async throws -> [RhythmReminderSection] { [] }
    func suggestedEntities() async throws -> [RhythmReminderSection] { [] }
}

@available(iOS 27.0, *)
@AppEnum(schema: .reminders.locationTriggerEvent)
enum RhythmReminderLocationEvent: String {
    case arrive, depart
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [.arrive: "Arrive", .depart: "Depart"]
}

@available(iOS 27.0, *)
@AppEntity(schema: .reminders.locationTrigger)
struct RhythmReminderLocation {
    static let defaultQuery = RhythmReminderLocationQuery()
    let id: String
    var place: PlaceDescriptor
    var event: RhythmReminderLocationEvent
    var displayRepresentation: DisplayRepresentation { "Location trigger" }
}

@available(iOS 27.0, *)
struct RhythmReminderLocationQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [RhythmReminderLocation] { [] }
    func entities(matching string: String) async throws -> [RhythmReminderLocation] { [] }
    func suggestedEntities() async throws -> [RhythmReminderLocation] { [] }
}

@available(iOS 27.0, *)
@AppEntity(schema: .reminders.reminder)
struct RhythmSchemaReminder: IndexedEntity {
    static let defaultQuery = RhythmSchemaReminderQuery()
    let id: String
    var title: String
    var dueDate: DateComponents?
    var note: AttributedString?
    var isCompleted: Bool
    var completionDate: Date?
    var creationDate: Date?
    var recurrence: Calendar.RecurrenceRule?
    var isFlagged: Bool?
    var locationTrigger: RhythmReminderLocation?
    var list: RhythmReminderList
    var tags: Set<String>
    var urls: [URL]

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "Daily Rhythm · \(note.map { String($0.characters) } ?? "")")
    }

    init(_ step: DailyOccurrence, createdAt: Date? = nil) {
        id = step.id
        title = step.title
        dueDate = ReminderSchemaMapping.dueComponents(step.due)
        switch step.outcome {
        case .full: note = AttributedString("Full · " + step.normalTarget)
        case .light: note = AttributedString("Light · " + (step.lightTarget ?? step.normalTarget))
        case .skipped: note = AttributedString("Skipped · not completed")
        case nil: note = AttributedString("Pending · " + step.normalTarget)
        }
        isCompleted = step.isCompleted
        completionDate = step.completedAt
        creationDate = createdAt
        recurrence = nil
        isFlagged = false
        locationTrigger = nil
        list = .appList
        tags = []
        urls = []
    }
}

@available(iOS 27.0, *)
struct RhythmSchemaReminderQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [RhythmSchemaReminder] {
        let store = try SharedRoutineStore.makeStore()
        let oneOffIDs = Set(try store.habits().filter { !$0.recurrence.isRecurring }.map(\.id))
        return try identifiers.compactMap { id in
            let step: DailyOccurrence
            do { step = try store.occurrence(id: id) }
            catch RoutineStoreError.invalidOccurrence { return nil }
            catch RoutineStoreError.habitNotFound { return nil }
            guard oneOffIDs.contains(step.habitID) else { return nil }
            return RhythmSchemaReminder(step)
        }
    }

    func entities(matching string: String) async throws -> [RhythmSchemaReminder] {
        try all().filter { $0.title.localizedStandardContains(string) }
    }
    func suggestedEntities() async throws -> [RhythmSchemaReminder] { try all() }

    private func all() throws -> [RhythmSchemaReminder] {
        let store = try SharedRoutineStore.makeStore()
        return try store.habits().filter { !$0.recurrence.isRecurring }.flatMap {
            try store.managedOccurrences(habitID: $0.id).map { RhythmSchemaReminder($0) }
        }
    }
}

@available(iOS 27.0, *)
@AppIntent(schema: .reminders.createReminder)
struct CreateRhythmSchemaReminder {
    static let title: LocalizedStringResource = "Create Daily Rhythm Reminder"
    static let description = IntentDescription("Validation action: create one one-off task in Daily Rhythm.")
    static let supportedModes: IntentModes = .background
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    var title: String
    var dueDate: DateComponents?
    var recurrence: Calendar.RecurrenceRule?
    var list: RhythmReminderList?
    var note: AttributedString?
    var isFlagged: Bool?
    var images: [IntentFile]
    var tags: Set<String>
    var urls: [URL]
    var locationTrigger: RhythmReminderLocation?
    var section: RhythmReminderSection?

    func perform() async throws -> some IntentResult & ReturnsValue<RhythmSchemaReminder> {
        guard list == nil || list?.id == RhythmReminderList.appList.id else { throw ReminderMappingError.unsupportedItem }
        guard note == nil, isFlagged != true, images.isEmpty, tags.isEmpty, urls.isEmpty,
              locationTrigger == nil, section == nil else { throw ReminderMappingError.unsupportedFields }
        let now = Date()
        let definition = try ReminderSchemaMapping.definition(title: title, dueDate: dueDate,
                                                               hasRecurrence: recurrence != nil, now: now)
        let store = try SharedRoutineStore.makeStore()
        let habit = try store.addHabit(definition, now: now)
        guard case .once(let key) = habit.recurrence else { throw ReminderMappingError.unsupportedItem }
        let step = try store.occurrence(id: "\(habit.id.uuidString)|\(key)")
        RhythmSurfaceRefresh.reload()
        await RhythmNotifications.reconcileAfterMutation()
        await ReminderSchemaIndex.shared.refreshAfterMutation()
        return .result(value: RhythmSchemaReminder(step, createdAt: habit.createdAt))
    }
}

@available(iOS 27.0, *)
@AppIntent(schema: .reminders.updateReminder)
struct UpdateRhythmSchemaReminder {
    static let title: LocalizedStringResource = "Update Daily Rhythm Reminder"
    static let description = IntentDescription("Validation action: complete or reopen a Daily Rhythm one-off task.")
    static let supportedModes: IntentModes = .background
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    var target: RhythmSchemaReminder
    var isCompleted: Bool?
    var title: String?
    var note: AttributedString?
    var tags: Set<String>?
    var urls: [URL]?
    var dueDate: DateComponents?
    var recurrence: Calendar.RecurrenceRule?
    var isFlagged: Bool?
    var list: RhythmReminderList?
    var locationTrigger: RhythmReminderLocation?

    func perform() async throws -> some IntentResult & ReturnsValue<RhythmSchemaReminder> {
        guard let isCompleted, title == nil, note == nil, tags == nil, urls == nil,
              dueDate == nil, recurrence == nil, isFlagged == nil, list == nil, locationTrigger == nil
        else { throw ReminderMappingError.unsupportedUpdate }
        let store = try SharedRoutineStore.makeStore()
        let step = try store.occurrence(id: target.id)
        guard try store.habits().contains(where: { $0.id == step.habitID && !$0.recurrence.isRecurring })
        else { throw ReminderMappingError.unsupportedItem }
        if isCompleted {
            guard step.outcome != .skipped else { throw RoutineStoreError.completedOccurrence }
            try store.complete(occurrenceID: step.id, source: .appIntent, expectedRevision: step.revision)
        } else {
            try store.reopen(occurrenceID: step.id, expectedRevision: step.revision)
        }
        RhythmSurfaceRefresh.reload()
        await RhythmNotifications.reconcileAfterMutation()
        await ReminderSchemaIndex.shared.refreshAfterMutation()
        return .result(value: RhythmSchemaReminder(try store.occurrence(id: step.id)))
    }
}
#endif

import AppIntents
import Foundation
import DailyRhythmCore

/// Identifies a single scheduled day, not the indefinitely recurring habit template.
struct RhythmOccurrenceEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Daily Step")
    static let defaultQuery = RhythmOccurrenceQuery()

    let id: String
    let title: String
    let dayKey: String
    let dayPart: String
    let isCompleted: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(dayPart) · \(dayKey)\(isCompleted ? " · Recorded" : "")"
        )
    }

    init(_ occurrence: DailyOccurrence) {
        id = occurrence.id
        title = occurrence.title
        dayKey = occurrence.dayKey
        dayPart = occurrence.dayPart.rawValue.capitalized
        isCompleted = occurrence.outcome != nil
    }
}

struct RhythmOccurrenceQuery: EntityStringQuery {
    func entities(for identifiers: [RhythmOccurrenceEntity.ID]) async throws -> [RhythmOccurrenceEntity] {
        let occurrences = try SharedRoutineStore.makeStore().summary().occurrences
        let byID = Dictionary(uniqueKeysWithValues: occurrences.map { ($0.id, $0) })
        // Preserve exact identities. Never substitute tomorrow's occurrence for a saved shortcut.
        return identifiers.compactMap { byID[$0].map(RhythmOccurrenceEntity.init) }
    }

    func entities(matching string: String) async throws -> [RhythmOccurrenceEntity] {
        try SharedRoutineStore.makeStore().summary().occurrences
            .filter { $0.title.localizedStandardContains(string) }
            .map(RhythmOccurrenceEntity.init)
    }

    func suggestedEntities() async throws -> [RhythmOccurrenceEntity] {
        // Completed items remain available so a repeated request can be idempotent or undone.
        try SharedRoutineStore.makeStore().summary().occurrences
            .map(RhythmOccurrenceEntity.init)
    }
}

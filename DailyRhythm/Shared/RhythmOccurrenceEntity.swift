import AppIntents
import Foundation
import DailyRhythmCore

/// Identifies a single scheduled day, not the indefinitely recurring habit template.
struct RhythmOccurrenceEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Daily Step")
    static let defaultQuery = RhythmOccurrenceQuery()

    let id: String
    let title: String
    let normalTarget: String
    let dayKey: String
    let dayPart: String
    let status: String
    let revision: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(normalTarget) · \(dayPart) · \(dayKey) · \(status)"
        )
    }

    init(_ occurrence: DailyOccurrence) {
        id = occurrence.id
        title = occurrence.title
        normalTarget = occurrence.normalTarget
        dayKey = occurrence.dayKey
        dayPart = occurrence.dayPart.rawValue.capitalized
        status = occurrence.outcome?.rawValue.capitalized ?? "Pending"
        revision = occurrence.revision
    }
}

struct RhythmOccurrenceQuery: EntityStringQuery {
    func entities(for identifiers: [RhythmOccurrenceEntity.ID]) async throws -> [RhythmOccurrenceEntity] {
        let occurrences = try SharedRoutineStore.makeStore().agenda().occurrences
        let byID = Dictionary(uniqueKeysWithValues: occurrences.map { ($0.id, $0) })
        // Preserve exact identities. Never substitute tomorrow's occurrence for a saved shortcut.
        return identifiers.compactMap { byID[$0].map(RhythmOccurrenceEntity.init) }
    }

    func entities(matching string: String) async throws -> [RhythmOccurrenceEntity] {
        try SharedRoutineStore.makeStore().agenda().occurrences
            .filter { $0.title.localizedStandardContains(string) }
            .map(RhythmOccurrenceEntity.init)
    }

    func suggestedEntities() async throws -> [RhythmOccurrenceEntity] {
        // Completed items remain available so a repeated request can be idempotent or undone.
        try SharedRoutineStore.makeStore().agenda().occurrences
            .map(RhythmOccurrenceEntity.init)
    }
}

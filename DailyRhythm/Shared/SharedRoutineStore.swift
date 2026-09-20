import Foundation
import DailyRhythmCore

/// App and extensions must open the same protected, coordinated store.
/// A missing App Group is a configuration error, never a reason to create a second database.
enum SharedRoutineStore {
    static let widgetKind = "DailyRhythmToday"

    static func makeStore() throws -> RoutineStore {
        guard let identifier = Bundle.main.object(forInfoDictionaryKey: "DailyRhythmAppGroup") as? String,
              !identifier.isEmpty,
              !identifier.contains("$(") else {
            throw SharedStoreError.missingConfiguration
        }
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: identifier
        ) else {
            throw SharedStoreError.unavailableContainer
        }
        return RoutineStore(fileURL: container.appendingPathComponent("daily-rhythm.json"))
    }
}

enum SharedStoreError: LocalizedError {
    case missingConfiguration
    case unavailableContainer
    case staleOccurrence
    case noSmallStep

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "Daily Rhythm's shared storage is not configured. Open the app to check setup."
        case .unavailableContainer:
            return "Daily Rhythm cannot access its shared storage. Unlock your iPhone and try again."
        case .staleOccurrence:
            return "This step is no longer available for today. Open Daily Rhythm to see the current day."
        case .noSmallStep:
            return "This habit has no small step. Complete its full target instead."
        }
    }
}

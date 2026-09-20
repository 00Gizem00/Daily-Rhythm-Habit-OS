import Foundation

public enum HabitControlError: Error, Equatable, Sendable, LocalizedError {
    case archived, noCurrentOccurrence, skipped, notReady

    public var errorDescription: String? {
        switch self {
        case .archived: "This habit is archived. Choose an active habit in the control's settings."
        case .noCurrentOccurrence: "This habit has no step planned for today. Open Daily Rhythm to choose a different day."
        case .skipped: "Today's step was skipped. Reopen it in Daily Rhythm before completing it."
        case .notReady: "Today's step is planned for later. Open Daily Rhythm to review its due date."
        }
    }
}

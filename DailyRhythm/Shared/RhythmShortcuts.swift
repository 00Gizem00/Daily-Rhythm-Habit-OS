#if !WIDGET_EXTENSION
import AppIntents

struct RhythmShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CreateHabitIntent(),
            phrases: [
                "Create a habit in \(.applicationName)",
                "Add a habit in \(.applicationName)"
            ],
            shortTitle: "Create Habit",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: CompleteOccurrenceIntent(),
            phrases: [
                "Complete a step in \(.applicationName)",
                "Complete \(\.$occurrence) in \(.applicationName)"
            ],
            shortTitle: "Complete Step",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: ReopenOccurrenceIntent(),
            phrases: ["Undo a step in \(.applicationName)"],
            shortTitle: "Undo Step",
            systemImageName: "arrow.uturn.backward.circle"
        )
    }
}
#endif

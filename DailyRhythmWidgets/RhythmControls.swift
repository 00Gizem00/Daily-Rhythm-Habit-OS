import AppIntents
import SwiftUI
import WidgetKit

struct OpenTodayControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "DailyRhythmOpenToday") {
            ControlWidgetButton(action: OpenTodayIntent()) {
                Label("Today", systemImage: "sun.max")
            }
        }
        .displayName("Open Today")
        .description("Open your current day in Daily Rhythm.")
    }
}

struct CompleteHabitControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: RhythmSurfaceRefresh.habitControlKind, intent: ChooseControlHabitIntent.self) { configuration in
            ControlWidgetButton(action: CompleteControlHabitIntent(habit: configuration.habit)) {
                Label(configuration.habit?.title ?? "Choose a habit", systemImage: "checkmark.circle")
                    .privacySensitive()
                    .controlWidgetActionHint("Complete today's full step")
            }
        }
        .displayName("Complete Habit")
        .description("Choose one habit. Complete its full step planned for today; repeated taps preserve the recorded result. For postponed earlier steps, open Today.")
        .promptsForUserConfiguration()
    }
}

import AppIntents
import SwiftUI

struct SetupHelpView: View {
    var body: some View {
        List {
            Section("Your first completion") {
                Text("Open Today and look at Next Up. Do the goal shown, then choose Full step done. If you did the saved smaller target, choose Light step instead. Use Undo if you recorded the wrong result.")
                Text("A habit appears on its selected weekdays. Light and full goals are recorded separately; skipping never counts as completing.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section("Add a Home Screen widget") {
                Text("1. Touch and hold an empty area of your Home Screen.")
                Text("2. Tap Edit, then Add Widget.")
                Text("3. Search for Daily Rhythm. Choose a small or medium widget, tap Add Widget, then Done.")
                Text("The small widget shows Next Up; the medium widget shows progress and steps. Widget refresh timing is managed by iOS. Open Daily Rhythm if information looks old.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Link("Apple's widget guide", destination: URL(string: "https://support.apple.com/guide/iphone/iphb8f1bf206/ios")!)
            }
            Section("Lock Screen & StandBy") {
                Text("Touch and hold your unlocked Lock Screen, choose Customize, then Lock Screen. Tap the widget area and add Daily Rhythm for compact progress.")
                Text("For StandBy, turn on Settings → StandBy, connect your iPhone to power, rest it sideways and press the side button. Swipe to the widget view; touch and hold a widget to add Daily Rhythm.")
                Text("StandBy uses the small widget. iOS manages its layout, privacy and refresh timing. You may need to unlock before recording a step. Always-on display depends on your iPhone and settings.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Link("Apple's StandBy guide", destination: URL(string: "https://support.apple.com/guide/iphone/iph878d77632/ios")!)
            }
            Section("Add a control") {
                Text("Open Control Center, touch and hold an empty area, then tap Add a Control. Search for Daily Rhythm and choose Open Today or Complete Habit. Edit Complete Habit to choose a specific habit.")
                Text("Complete Habit records the full target of that habit's step planned for today. It keeps an existing full or light result. A skipped, postponed or unscheduled step needs review in the app; the control never switches to another habit. Light Day does not change this full-step control.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("You can also choose these controls while customizing Lock Screen buttons. On an iPhone with an Action button, open Settings → Action Button → Controls and choose a control. Device authentication may be required.")
                Link("Apple's Control Center guide", destination: URL(string: "https://support.apple.com/guide/iphone/iph59095ec58/ios")!)
            }
            Section("Try an App Shortcut") {
                Text("In Shortcuts, open App Shortcuts and choose Daily Rhythm. Try Create Habit, Complete Step or Undo Step. You'll be asked to choose a specific step when needed.")
                ShortcutsLink()
                Text("You can also try these phrases with Siri:")
                Text("“Create a habit in Daily Rhythm”")
                Text("“Complete a step in Daily Rhythm”")
                Text("“Undo a step in Daily Rhythm”")
                Text("Use the app name. A general request like ‘remind me’ may open a different app. A saved step refers to one scheduled day, so choose a current step when an old shortcut is no longer available.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("Siri availability and recognition depend on your device, language, settings and system version; you may need to unlock your iPhone. If voice recognition fails, run the action in Shortcuts or use Today.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Link("Apple's App Shortcuts guide", destination: URL(string: "https://support.apple.com/guide/shortcuts/apd43295406d/ios")!)
                Link("Apple's Siri shortcut guide", destination: URL(string: "https://support.apple.com/guide/shortcuts/apd07c25bb38/ios")!)
            }
            RoutinePlanningHelp()
            Section("Your choice, when you need it") {
                Text("Manual habits and these templates need no account, AI or launch-time permissions. A due time currently describes your plan; it does not send a notification.")
            }
        }
        .navigationTitle("Widgets & Siri")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

/// Future availability-gated planning entry belongs here; do not offer a button
/// until a real proposal/review/apply flow is available.
private struct RoutinePlanningHelp: View {
    var body: some View {
        Section("Planning your routine") {
            Text("This version offers manual setup and editable templates. Build My Routine and advanced Siri AI actions are not available here yet.")
            Text("The actions above are ordinary App Shortcuts. They don't promise Apple Intelligence planning or access to Apple Reminders.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

import DailyRhythmCore
import SwiftUI

struct HabitGoalFields: View {
    @Binding var draft: HabitFormDraft
    var editName = true

    var body: some View {
        Section("Your next small step") {
            if editName {
                TextField("Name, e.g. Read", text: $draft.title)
                    .accessibilityLabel("Name")
                    .accessibilityIdentifier("plan.name")
            } else { Text(draft.title).font(.headline) }
            TextField("Full goal, e.g. 10 pages", text: $draft.normalTarget)
                .accessibilityLabel("Full goal")
                .accessibilityIdentifier("plan.target")
            Toggle("Add a light version", isOn: $draft.hasLightTarget)
            if draft.hasLightTarget {
                TextField("Smaller goal, e.g. 2 pages", text: $draft.lightTarget)
                    .accessibilityLabel("Light goal")
                    .accessibilityIdentifier("plan.lightTarget")
            }
        }
        Section {
            Toggle("Add a duration", isOn: $draft.hasDuration)
            if draft.hasDuration {
                TextField("Minutes", text: $draft.durationText)
                    .keyboardType(.numberPad)
                    .accessibilityLabel("Duration in minutes")
            }
        } footer: {
            Text("Use whole minutes. Duration describes the step; it does not start a timer.")
        }
    }
}

struct HabitScheduleFields: View {
    @Binding var draft: HabitFormDraft
    var allowKindChange = false

    var body: some View {
        Section("When it fits") {
            Picker("Part of day", selection: $draft.dayPart) {
                ForEach(DayPart.allCases, id: \.self) { part in
                    Text(part.displayName).tag(part)
                }
            }
            if !draft.isRecurring && allowKindChange {
                CivilDatePicker(title: "Planned date", dayKey: $draft.dayKey)
            }
        }
        if draft.isRecurring {
            Section {
                ForEach(RhythmDates.weekdays, id: \.value) { weekday in
                    Toggle(weekday.label, isOn: Binding(
                        get: { draft.weekdays.contains(weekday.value) },
                        set: { selected in
                            if selected { draft.weekdays.insert(weekday.value) }
                            else { draft.weekdays.remove(weekday.value) }
                        }
                    ))
                }
            } header: { Text("Repeat") } footer: {
                Text("Choose at least one day. Each planned day keeps its own result.")
            }
        }
        HabitTimeFields(draft: $draft)
    }
}

struct HabitTimeFields: View {
    @Binding var draft: HabitFormDraft

    var body: some View {
        Section {
            Toggle("Set a due time", isOn: $draft.hasTime)
            if draft.hasTime {
                DatePicker("Due time", selection: Binding(
                    get: {
                        LocalDay.utc.calendar.date(from: DateComponents(year: 2001, month: 1, day: 1,
                                                                        hour: draft.hour, minute: draft.minute))!
                    },
                    set: {
                        let values = LocalDay.utc.calendar.dateComponents([.hour, .minute], from: $0)
                        draft.hour = values.hour!
                        draft.minute = values.minute!
                    }
                ), displayedComponents: .hourAndMinute)
                .environment(\.calendar, LocalDay.utc.calendar)
                .environment(\.timeZone, LocalDay.utc.calendar.timeZone)
                Picker("Time zone", selection: $draft.timeZoneIdentifier) {
                    ForEach(Array(Set(TimeZone.knownTimeZoneIdentifiers + [draft.timeZoneIdentifier])).sorted(), id: \.self) {
                        Text($0.replacingOccurrences(of: "_", with: " ")).tag($0)
                    }
                }
                .pickerStyle(.navigationLink)
            }
        } footer: {
            Text(draft.hasTime
                 ? "The time stays in this time zone when you travel. A due time does not schedule a notification."
                 : "Date only: no due time is set. Morning, afternoon and evening are groups, not deadlines.")
        }
    }
}

/// Render civil dates in UTC so picker selection never shifts through the device timezone.
struct CivilDatePicker: View {
    let title: String
    @Binding var dayKey: String

    var body: some View {
        DatePicker(title, selection: Binding(
            get: { LocalDay.utc.date(for: dayKey) ?? Date() },
            set: { dayKey = LocalDay.utc.key(for: $0) }
        ), displayedComponents: .date)
        .environment(\.calendar, LocalDay.utc.calendar)
        .environment(\.timeZone, LocalDay.utc.calendar.timeZone)
    }
}

struct FormSaveError: ViewModifier {
    @Binding var message: String?
    func body(content: Content) -> some View {
        content.alert("Couldn't save this plan", isPresented: Binding(
            get: { message != nil }, set: { if !$0 { message = nil } }
        )) { Button("OK", role: .cancel) { message = nil } } message: {
            Text(message ?? "Please try again. Your input has been kept.")
        }
    }
}

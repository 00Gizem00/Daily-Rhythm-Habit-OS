import DailyRhythmCore
import SwiftUI

struct FuturePlanEditor: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let habit: Habit
    @State private var draft: HabitFormDraft
    @State private var effectiveDayKey: String
    @State private var saveError: String?

    init(habit: Habit, effectiveDayKey: String) {
        self.habit = habit
        _effectiveDayKey = State(initialValue: effectiveDayKey)
        let definition = habit.revisions.last(where: { $0.effectiveDayKey <= effectiveDayKey })?.definition ?? habit.definition
        _draft = State(initialValue: HabitFormDraft(definition: definition))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Future plan only").font(.headline)
                    CivilDatePicker(title: "Starting on", dayKey: $effectiveDayKey)
                } footer: {
                    Text("Choose a date after today. Earlier plans and recorded steps stay unchanged. Later scheduled changes and individually edited steps stay in place.")
                }
                HabitGoalFields(draft: $draft)
                HabitScheduleFields(draft: $draft)
                if !draft.isRecurring {
                    Section {
                        Text("Planned once on \(RhythmDates.dayLabel(draft.dayKey)).")
                        Text("The change must start on or before that date. To move the due date, edit the individual step.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Edit future plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
            .modifier(FormSaveError(message: $saveError))
        }
    }

    private func save() {
        do {
            let definition = try draft.definition()
            if model.editSchedule(habitID: habit.id, definition: definition, effectiveDayKey: effectiveDayKey) { dismiss() }
            else { saveError = model.operationError; model.operationError = nil }
        } catch { saveError = error.localizedDescription }
    }
}

struct OccurrenceEditor: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let occurrence: DailyOccurrence
    @State private var draft: HabitFormDraft
    @State private var saveError: String?

    init(occurrence: DailyOccurrence) {
        self.occurrence = occurrence
        _draft = State(initialValue: HabitFormDraft(occurrence: occurrence))
    }

    private var dueOnly: Bool { occurrence.dayKey < LocalDay(calendar: .current).key(for: Date()) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("This step only").font(.headline)
                    Text("Originally planned for \(RhythmDates.dayLabel(occurrence.dayKey)).")
                } footer: {
                    Text(dueOnly
                         ? "Past targets stay in your history. You can change this pending step's due date and time."
                         : "Your recurring plan and other days keep their existing targets and schedule.")
                }
                if !dueOnly { HabitGoalFields(draft: $draft, editName: false) }
                else {
                    Section(occurrence.title) {
                        Text(occurrence.normalTarget)
                        if let light = occurrence.lightTarget { Text("Light: \(light)") }
                    }
                }
                Section {
                    CivilDatePicker(title: "Due date", dayKey: $draft.dayKey)
                } footer: {
                    Text("Choose the original planned date or a later date. Moving the due date keeps the same step and its place in history.")
                }
                HabitTimeFields(draft: $draft)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Edit this step")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if model.editOccurrence(occurrence, draft: draft, dueOnly: dueOnly) { dismiss() }
                        else { saveError = model.operationError; model.operationError = nil }
                    }
                }
            }
            .modifier(FormSaveError(message: $saveError))
        }
    }
}

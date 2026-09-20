import DailyRhythmCore
import SwiftUI

enum HabitCreationRoute: String, Identifiable {
    case custom, reading
    var id: String { rawValue }
}

struct AddHabitView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: HabitFormDraft
    @State private var saveError: String?
    @State private var generation: UUID?

    init(readingTemplate: Bool = false) {
        _draft = State(initialValue: HabitFormDraft(definition: HabitDefinition(
            title: readingTemplate ? "Read" : "", normalTarget: readingTemplate ? "10 pages" : "",
            lightTarget: readingTemplate ? "2 pages" : nil, dayPart: .morning,
            recurrence: .weekly(weekdays: Set(1...7))
        )))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Free plan") {
                    Text(HabitActivationPolicy.freePlanDescription + " One-off tasks do not count toward this limit.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("Plan type") {
                    Picker("Plan type", selection: $draft.isRecurring) {
                        Text("Recurring habit").tag(true)
                        Text("One-off task").tag(false)
                    }
                    .pickerStyle(.inline)
                }
                HabitGoalFields(draft: $draft)
                HabitScheduleFields(draft: $draft, allowKindChange: true)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollContentBackground(.hidden)
            .background(RhythmTheme.canvas)
            .navigationTitle(draft.isRecurring ? "New habit" : "New task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { save() }.fontWeight(.semibold).disabled(generation == nil)
                }
            }
            .modifier(FormSaveError(message: $saveError))
            .task {
                guard generation == nil else { return }
                do { generation = try SharedRoutineStore.makeStore().validateAccess() }
                catch { saveError = error.localizedDescription }
            }
        }
    }

    private func save() {
        do {
            let definition = try draft.definition()
            guard let generation else { throw LocalDataError.staleAction }
            if model.addHabit(definition, expectedGeneration: generation) { dismiss() }
            else { saveError = model.operationError; model.operationError = nil }
        } catch { saveError = error.localizedDescription }
    }
}

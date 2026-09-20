import DailyRhythmCore
import SwiftUI

enum HabitCreationRoute: String, Identifiable {
    case custom, reading
    var id: String { rawValue }
}

struct AddHabitView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var normalTarget: String
    @State private var lightTarget: String
    @State private var hasLightTarget: Bool
    @State private var dayPart = DayPart.morning
    @State private var weekdays = Set(1...7)
    @State private var saveError: String?

    init(readingTemplate: Bool = false) {
        _title = State(initialValue: readingTemplate ? "Read" : "")
        _normalTarget = State(initialValue: readingTemplate ? "10 pages" : "")
        _lightTarget = State(initialValue: readingTemplate ? "2 pages" : "")
        _hasLightTarget = State(initialValue: readingTemplate)
    }

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !normalTarget.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (!hasLightTarget || !lightTarget.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            && !weekdays.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Free plan") {
                    Text(HabitActivationPolicy.freePlanDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    TextField("Habit name, e.g. Read", text: $title)
                        .textInputAutocapitalization(.sentences)
                        .accessibilityLabel("Habit name")
                    TextField("Full goal, e.g. 10 pages", text: $normalTarget)
                        .textInputAutocapitalization(.sentences)
                        .accessibilityLabel("Full goal")
                } header: {
                    Text("Your next small step")
                } footer: {
                    Text("Choose a goal you can recognise as done. You decide when to record it.")
                }

                Section {
                    Toggle("Add a light version", isOn: $hasLightTarget)
                    if hasLightTarget {
                        TextField("Smaller goal, e.g. 2 pages", text: $lightTarget)
                            .textInputAutocapitalization(.sentences)
                            .accessibilityLabel("Light goal")
                    }
                } header: {
                    Text("For the busy days")
                } footer: {
                    Text("A light version is optional. It is recorded separately from your full goal.")
                }

                Section("When it fits") {
                    Picker("Part of day", selection: $dayPart) {
                        ForEach(DayPart.allCases, id: \.self) { part in
                            Label(part.displayName, systemImage: part.symbol).tag(part)
                        }
                    }
                }

                Section {
                    ForEach(RhythmDates.weekdays, id: \.value) { weekday in
                        Toggle(weekday.label, isOn: Binding(
                            get: { weekdays.contains(weekday.value) },
                            set: { selected in
                                if selected { weekdays.insert(weekday.value) }
                                else { weekdays.remove(weekday.value) }
                            }
                        ))
                    }
                } header: {
                    Text("Repeat")
                } footer: {
                    Text(weekdays.isEmpty ? "Choose at least one day." : "Your habit repeats on these days. Each day keeps its own result.")
                }

                if let saveError {
                    Section {
                        Label(saveError, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(RhythmTheme.canvas)
            .navigationTitle("New habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { save() }
                        .fontWeight(.semibold)
                        .disabled(!isValid)
                }
            }
        }
    }

    private func save() {
        let saved = model.addHabit(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            normalTarget: normalTarget.trimmingCharacters(in: .whitespacesAndNewlines),
            lightTarget: hasLightTarget ? lightTarget.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
            dayPart: dayPart,
            weekdays: weekdays
        )
        if saved { dismiss() }
        else {
            // The form stays open with the user's input intact on a failed save.
            saveError = model.operationError ?? "Please try again."
            model.operationError = nil
        }
    }
}

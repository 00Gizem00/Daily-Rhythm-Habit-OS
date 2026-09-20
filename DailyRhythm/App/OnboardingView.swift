import DailyRhythmCore
import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var setup: OnboardingPreferences
    @Environment(\.dismiss) private var dismiss
    @State private var created = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Group {
                if created { ready }
                else if !model.habits.isEmpty { returning }
                else if let draft = setup.progress.draft { review(draft) }
                else { welcome }
            }
            .navigationTitle(created ? "Your routine is ready" : "Find your first step")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(created || !model.habits.isEmpty ? "Done" : "Not now") {
                        setup.pause()
                        dismiss()
                    }
                }
            }
            .modifier(FormSaveError(message: $saveError))
        }
        .onDisappear { setup.pause() }
    }

    private var welcome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("One small step is enough.")
                    .font(.largeTitle.bold()).fixedSize(horizontal: false, vertical: true)
                Text("Choose a starting point, edit it to fit your day, then decide what to save. Everything here works offline, without an account or AI.")
                    .foregroundStyle(.secondary)
                Button("Start with a morning routine", systemImage: "sunrise") { setup.choose(.morning) }
                    .buttonStyle(RhythmPrimaryButtonStyle())
                Button("Start with an evening routine", systemImage: "moon.stars") { setup.choose(.evening) }
                    .buttonStyle(RhythmSecondaryButtonStyle())
                Button("Create my own habit", systemImage: "pencil") { setup.choose(.manual) }
                    .buttonStyle(RhythmSecondaryButtonStyle())
                Text(HabitActivationPolicy.freePlanDescription)
                    .font(.footnote).foregroundStyle(.secondary)
                Text("Nothing is added until you choose Create my routine.")
                    .font(.footnote)
            }
            .padding(24)
        }
        .background(RhythmTheme.canvas)
    }

    private func review(_ draft: OnboardingDraft) -> some View {
        List {
            Section {
                Text("Make this routine yours").font(.title2.bold())
                Text("Open each habit to edit its goal, smaller target and schedule. Remove any you don't want.")
                    .foregroundStyle(.secondary)
            }
            Section("Your draft · \(draft.entries.count) of 3 habits") {
                ForEach(draft.entries) { entry in
                    NavigationLink {
                        OnboardingEntryEditor(entry: entry)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(entry.form.title.isEmpty ? "Name your habit" : entry.form.title).font(.headline)
                            Text(entry.form.normalTarget.isEmpty ? "Add a goal to continue" : entry.form.normalTarget)
                                .font(.subheadline).foregroundStyle(.secondary)
                            if let definition = try? entry.form.definition() {
                                Text(RhythmDates.planLabel(definition)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button("Remove \(entry.form.title.isEmpty ? "unnamed habit" : entry.form.title)", role: .destructive) {
                        setup.removeEntry(id: entry.id)
                    }
                    .font(.caption)
                }
                if draft.entries.count < 3 {
                    Button("Add another habit", systemImage: "plus") { setup.addEntry() }
                }
            }
            Section {
                Button("Create my routine") { confirm(draft) }
                    .font(.headline).frame(minHeight: 44)
                    .disabled(draft.entries.isEmpty || draft.entries.contains { (try? $0.form.definition()) == nil })
            } footer: {
                Text("This creates only the habits shown above. Not now keeps this reviewed draft on your iPhone so you can resume later.")
            }
        }
    }

    private var ready: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Label("Start in Today", systemImage: "sun.max").font(.title2.bold())
                Text("Your habits are saved. When you've done the goal shown in Next Up, choose Full step done, or record the smaller goal with Light step. Undo is there if you tap by mistake.")
                Text("If you chose a future schedule, your first step will appear on that day.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button("Go to Today") { dismiss() }.buttonStyle(RhythmPrimaryButtonStyle())
                NavigationLink("Add a widget or try Siri later") { SetupHelpView() }
                    .frame(minHeight: 44)
            }.padding(24)
        }.background(RhythmTheme.canvas)
    }

    private var returning: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Your plan is already here.").font(.title2.bold())
                Text("Continue in Today. You can add or edit habits from Habits, and find widget and Siri help there too.")
                Button("Continue to Today") { setup.finish(); dismiss() }.buttonStyle(RhythmPrimaryButtonStyle())
            }.padding(24)
        }
    }

    private func confirm(_ draft: OnboardingDraft) {
        if model.createInitialRoutine(draft) {
            setup.finish()
            created = true
        } else { saveError = model.operationError; model.operationError = nil }
    }
}

private struct OnboardingEntryEditor: View {
    @EnvironmentObject private var setup: OnboardingPreferences
    @Environment(\.dismiss) private var dismiss
    let entry: OnboardingEntry
    @State private var form: HabitFormDraft
    @State private var saveError: String?

    init(entry: OnboardingEntry) { self.entry = entry; _form = State(initialValue: entry.form) }

    var body: some View {
        Form {
            Section {
                Text("Draft only. This habit is created when you confirm the whole routine.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            HabitGoalFields(draft: $form)
            HabitScheduleFields(draft: $form)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Edit draft habit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Use these details") {
                    do {
                        _ = try form.definition()
                        setup.updateEntry(id: entry.id, form: form)
                        dismiss()
                    } catch { saveError = error.localizedDescription }
                }
            }
        }
        .modifier(FormSaveError(message: $saveError))
    }
}

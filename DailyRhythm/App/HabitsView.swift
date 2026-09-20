import DailyRhythmCore
import SwiftUI

struct HabitsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var creationRoute: HabitCreationRoute?
    @State private var archiveCandidate: Habit?

    var body: some View {
        List {
            if model.activeHabits.isEmpty {
                Section {
                    RhythmEmptyState(
                        symbol: "square.stack.3d.up",
                        title: "Make space for what matters.",
                        message: "Create one habit to start. Keep the goal small enough to fit your life."
                    )
                    Button("Create a habit") { creationRoute = .custom }
                        .buttonStyle(RhythmPrimaryButtonStyle())
                        .disabled(model.today == nil)
                }
                .listRowBackground(RhythmTheme.card)
            } else {
                Section {
                    Text("Your goals repeat on the days you choose. Light versions give you an honest smaller step.")
                        .foregroundStyle(RhythmTheme.muted)
                }
                .listRowBackground(Color.clear)

                ForEach(DayPart.allCases, id: \.self) { part in
                    let habits = model.activeHabits.filter { $0.dayPart == part }
                    if !habits.isEmpty {
                        Section(part.displayName) {
                            ForEach(habits, id: \.id) { habit in
                                habitDetails(habit)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button { archiveCandidate = habit } label: {
                                            Label("Archive", systemImage: "archivebox")
                                        }
                                        .tint(RhythmTheme.navy)
                                    }
                                    .contextMenu {
                                        Button("Archive habit", systemImage: "archivebox") {
                                            archiveCandidate = habit
                                        }
                                    }
                            }
                        }
                        .listRowBackground(RhythmTheme.card)
                    }
                }
            }

            if !model.archivedHabits.isEmpty {
                Section {
                    ForEach(model.archivedHabits, id: \.id) { habit in
                        habitDetails(habit)
                            .foregroundStyle(RhythmTheme.muted)
                    }
                } header: {
                    Text("Archived")
                } footer: {
                    Text("Archived habits keep their recorded history. Uncompleted steps stop from the day they are archived.")
                }
                .listRowBackground(RhythmTheme.card)
            }
        }
        .scrollContentBackground(.hidden)
        .background(RhythmTheme.canvas)
        .navigationTitle("Your habits")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { creationRoute = .custom } label: {
                    Label("Add habit", systemImage: "plus")
                }
                .disabled(model.today == nil)
            }
        }
        .sheet(item: $creationRoute) { route in
            AddHabitView(readingTemplate: route == .reading)
        }
        .confirmationDialog("Archive this habit?", isPresented: Binding(
            get: { archiveCandidate != nil },
            set: { if !$0 { archiveCandidate = nil } }
        ), titleVisibility: .visible) {
            Button("Archive habit") {
                if let habit = archiveCandidate { model.archive(habit) }
                archiveCandidate = nil
            }
            Button("Cancel", role: .cancel) { archiveCandidate = nil }
        } message: {
            Text("Past results stay in your history. Uncompleted steps from today onwards will be removed.")
        }
        .refreshable { model.refresh() }
    }

    private func habitDetails(_ habit: Habit) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(habit.title).font(.headline)
            Text(habit.normalTarget).font(.subheadline)
            if let light = habit.lightTarget {
                Label("Light: \(light)", systemImage: "leaf")
                    .font(.caption)
                    .foregroundStyle(RhythmTheme.muted)
            }
            Text(RhythmDates.scheduleLabel(habit.weekdays))
                .font(.caption.weight(.medium))
                .foregroundStyle(RhythmTheme.muted)
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }
}

import DailyRhythmCore
import SwiftUI

struct HabitDetailView: View {
    @EnvironmentObject private var model: AppModel
    let habitID: UUID
    @State private var occurrences: [DailyOccurrence] = []
    @State private var loadError: String?
    @State private var editingOccurrence: DailyOccurrence?
    @State private var editingPlan: PlanEditRoute?
    @State private var confirmArchive = false

    private var habit: Habit? { model.habits.first { $0.id == habitID } }
    private var todayKey: String { LocalDay(calendar: .current).key(for: model.refreshedAt) }
    private var tomorrowKey: String {
        let calendar = LocalDay(calendar: .current).calendar
        return LocalDay(calendar: calendar).key(for: calendar.date(byAdding: .day, value: 1, to: model.refreshedAt)!)
    }

    var body: some View {
        List {
            if let habit {
                Section("Current plan") {
                    Text(habit.title).font(.headline)
                    Text(habit.normalTarget)
                    if let light = habit.lightTarget { Label("Light: \(light)", systemImage: "leaf") }
                    Text(RhythmDates.planLabel(habit.definition)).font(.subheadline).foregroundStyle(.secondary)
                    if let duration = habit.durationMinutes { Text("\(duration) minutes") }
                    if habit.archivedAt != nil { Label("Archived", systemImage: "archivebox") }
                }
                if habit.archivedAt == nil && canEditFuture(habit) {
                    Section {
                        Button("Edit future plan") { editingPlan = PlanEditRoute(dayKey: tomorrowKey) }
                    } footer: {
                        Text("Changes start after today. To change one step, use Edit this step below.")
                    }
                }
                let revisions = habit.revisions.filter { $0.effectiveDayKey > todayKey }
                if !revisions.isEmpty {
                    Section("Scheduled changes") {
                        ForEach(revisions, id: \.effectiveDayKey) { revision in
                            VStack(alignment: .leading, spacing: 5) {
                                Text("From \(RhythmDates.dayLabel(revision.effectiveDayKey))").font(.headline)
                                Text("\(revision.definition.title) · \(revision.definition.normalTarget)")
                                Text(RhythmDates.planLabel(revision.definition)).font(.caption).foregroundStyle(.secondary)
                                if habit.archivedAt == nil {
                                    Button("Edit this future plan") {
                                        editingPlan = PlanEditRoute(dayKey: revision.effectiveDayKey)
                                    }
                                }
                            }
                        }
                    }
                }
                if let loadError {
                    Section {
                        Text(loadError).foregroundStyle(.red)
                        Button("Retry") { loadOccurrences() }
                    }
                } else {
                    Section {
                        ForEach(occurrences) { occurrence in step(occurrence) }
                        if occurrences.isEmpty {
                            Text("No steps in this view.").foregroundStyle(.secondary)
                        }
                    } header: { Text(habit.recurrence.isRecurring ? "Steps · next 7 days" : "One-off step") } footer: {
                        Text(habit.recurrence.isRecurring
                             ? "Also includes earlier steps you edited or reopened, and steps completed in this window for Undo. Overdue means pending, not completed."
                             : "A one-off keeps its original planned date in history even when its due date changes. Restoring an item does not fill an archived gap.")
                    }
                }
                Section {
                    if habit.archivedAt == nil {
                        Button("Archive", systemImage: "archivebox") { confirmArchive = true }
                    } else {
                        Button("Restore", systemImage: "arrow.uturn.backward") { model.restore(habit) }
                    }
                } footer: {
                    Text(habit.archivedAt == nil
                         ? "Archiving keeps past results and stops pending steps from today onward."
                         : "Restore resumes the plan from today and checks the active-habit limit. Earlier archived dates stay excluded.")
                }
            } else {
                ContentUnavailableView("Plan unavailable", systemImage: "questionmark.folder")
            }
        }
        .navigationTitle(habit?.title ?? "Plan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task(id: model.refreshedAt) { loadOccurrences() }
        .refreshable { model.refresh() }
        .sheet(item: $editingOccurrence) { OccurrenceEditor(occurrence: $0) }
        .sheet(item: $editingPlan) { route in
            if let habit { FuturePlanEditor(habit: habit, effectiveDayKey: route.dayKey) }
        }
        .confirmationDialog("Archive this plan?", isPresented: $confirmArchive, titleVisibility: .visible) {
            Button("Archive") { if let habit { model.archive(habit) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Past results stay in history. Pending steps from today onward stop until you restore the plan.")
        }
    }

    private func step(_ occurrence: DailyOccurrence) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Planned \(RhythmDates.dayLabel(occurrence.dayKey))").font(.headline)
            Text(occurrence.normalTarget)
            if let light = occurrence.lightTarget { Text("Light: \(light)").font(.subheadline) }
            Text(RhythmDates.dueLabel(occurrence.due)).font(.subheadline).foregroundStyle(.secondary)
            if let duration = occurrence.durationMinutes { Text("\(duration) minutes").font(.caption) }
            if let outcome = occurrence.outcome {
                Label(outcome == .skipped ? "Skipped · not completed" : (outcome == .full ? "Full step recorded" : "Light step recorded"),
                      systemImage: outcome == .skipped ? "forward.end.circle" : "checkmark.circle.fill")
                    .foregroundStyle(RhythmTheme.leaf)
                Button("Reopen this step") { model.reopen(occurrence) }
            } else {
                if occurrence.isOverdue(at: model.refreshedAt) {
                    Label("Overdue · not recorded", systemImage: "clock").foregroundStyle(RhythmTheme.coral)
                } else { Text("Not recorded").font(.caption).foregroundStyle(.secondary) }
                Button("Edit this step") { editingOccurrence = occurrence }
                if occurrence.canComplete(at: model.refreshedAt) {
                    Menu("Record step") {
                        Button("Full: \(occurrence.normalTarget)") {
                            model.complete(occurrence, outcome: .full, requiringToday: false)
                        }
                        if let light = occurrence.lightTarget {
                            Button("Light: \(light)") { model.complete(occurrence, outcome: .light, requiringToday: false) }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 5)
        .buttonStyle(.borderless)
    }

    private func canEditFuture(_ habit: Habit) -> Bool {
        if case .once(let day) = habit.recurrence { return day >= tomorrowKey }
        return true
    }

    private func loadOccurrences() {
        do {
            occurrences = try SharedRoutineStore.makeStore().managedOccurrences(habitID: habitID, startingOn: model.refreshedAt)
            loadError = nil
        } catch { loadError = error.localizedDescription }
    }
}

private struct PlanEditRoute: Identifiable {
    let dayKey: String
    var id: String { dayKey }
}

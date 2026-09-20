import DailyRhythmCore
import SwiftUI

struct NotificationDetailView: View {
    let destination: RhythmNotificationDestination
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var summary: DailySummary?
    @State private var step: DailyOccurrence?
    @State private var archived = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let error {
                    ContentUnavailableView("This notice couldn't be refreshed", systemImage: "exclamationmark.circle",
                                           description: Text(error))
                    Button("Retry") { refresh() }
                } else if let summary {
                    Text(RhythmDates.dayLabel(summary.dayKey)).font(.title2.weight(.semibold))
                    ReviewCounts(full: summary.fullCount, light: summary.lightCount,
                                 skipped: summary.skippedCount, remaining: summary.remainingCount)
                    Text(summary.totalCount == 0 ? "No steps planned for this day."
                         : "\(summary.completedCount) of \(summary.totalCount) planned steps completed.")
                    ForEach(summary.occurrences) { occurrence in stepDetails(occurrence) }
                    Text("This review reflects the latest saved results for the original planned day.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else if let step {
                    stepDetails(step)
                    if archived { Label("This plan is archived", systemImage: "archivebox") }
                    Text("Opened from a reminder. No step was changed.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else { ProgressView("Reading your saved step…") }
            }.padding(20)
        }
        .background(RhythmTheme.canvas)
        .navigationTitle("Saved review")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .task(id: model.refreshedAt) { refresh() }
    }

    private func stepDetails(_ occurrence: DailyOccurrence) -> some View {
        RhythmCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(occurrence.title).font(.headline)
                Text("Planned for \(RhythmDates.dayLabel(occurrence.dayKey))").font(.subheadline)
                switch occurrence.outcome {
                case .full: Label("Full · \(occurrence.normalTarget)", systemImage: "checkmark.circle.fill")
                case .light: Label("Light · \(occurrence.lightTarget ?? occurrence.normalTarget)", systemImage: "leaf.fill")
                case .skipped: Label("Skipped · not completed", systemImage: "forward.end.circle")
                case nil: Label("Not completed · \(occurrence.normalTarget)", systemImage: "circle")
                }
                Text(RhythmDates.dueLabel(occurrence.due)).font(.caption).foregroundStyle(.secondary)
            }.accessibilityElement(children: .combine)
        }
    }

    private func refresh() {
        do {
            let store = try SharedRoutineStore.makeStore()
            switch destination {
            case .day(let key):
                // Parse in the same local calendar used by the store. If travel
                // skipped this civil date, report that instead of showing a different day.
                guard let date = LocalDay(calendar: .current).date(for: key) else {
                    error = "This date is not available in your current timezone."
                    return
                }
                summary = try store.summary(for: date)
            case .occurrence(let id):
                let current = try store.occurrence(id: id)
                archived = try store.habits(includeArchived: true).first { $0.id == current.habitID }?.archivedAt != nil
                step = current
            }
            error = nil
        } catch RoutineStoreError.invalidOccurrence {
            error = "This exact step is no longer available. Its plan may have changed or been archived. No other step was opened."
        } catch RoutineStoreError.habitNotFound {
            error = "The plan for this notice is no longer available. No other step was opened."
        } catch { self.error = error.localizedDescription }
    }
}
